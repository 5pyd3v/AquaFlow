-- ============================================================================
-- AquaFlow — Payment Enhancements (Migration 0025)
--
-- 1. Update get_vendor_customers to include outstanding + available_credit
-- 2. GRANT order_outstanding to authenticated
-- 3. New RPC: get_customer_total_outstanding (vendor-scoped)
-- 4. ALTER payment_amendment_requests CHECK to include 'refund'
-- 5. New RPC: process_refund (pre-settlement direct refund)
-- 6. Update resolve_payment_amendment to handle 'refund' action
-- 7. New RPC: get_customer_wallet_summary (customer self-service)
-- ============================================================================

-- ============================================================================
-- 1. Update get_vendor_customers — add outstanding + available_credit
-- ============================================================================
create or replace function public.get_vendor_customers(p_vendor_id uuid)
returns json[]
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller_vendor_id uuid;
  v_results json[];
begin
  select id into v_caller_vendor_id
  from public.vendors
  where id = p_vendor_id and profile_id = auth.uid();

  if v_caller_vendor_id is null then
    raise exception 'Not authorized';
  end if;

  select array_agg(
    json_build_object(
      'id', c.id,
      'profile_id', c.profile_id,
      'full_name', p.full_name,
      'phone', p.phone,
      'email', p.email,
      'pin', c.pin,
      'referral_code', c.referral_code,
      'total_orders', coalesce(
        (select count(*) from public.orders o where o.customer_profile_id = c.profile_id and o.vendor_id = p_vendor_id),
        0
      ),
      'outstanding', coalesce(
        (select sum(greatest(round(coalesce(o.total_amount,0)) - coalesce(o.amount_paid,0) - coalesce(o.credit_applied,0), 0))
         from public.orders o
         where o.customer_profile_id = c.profile_id
           and o.vendor_id = p_vendor_id
           and o.status not in ('cancelled','rejected')),
        0
      ),
      'available_credit', coalesce(
        (select w.balance from public.wallets w where w.profile_id = c.profile_id),
        0
      ),
      'address', (
        select a.full_address
        from public.addresses a
        where a.customer_profile_id = c.profile_id
        order by a.is_default desc, a.created_at asc
        limit 1
      ),
      'created_at', p.created_at
    )
  )
  into v_results
  from public.customers c
  join public.profiles p on p.id = c.profile_id
  where c.vendor_id = p_vendor_id;

  return coalesce(v_results, '{}');
end;
$$;

-- ============================================================================
-- 2. GRANT order_outstanding to authenticated
-- ============================================================================
grant execute on function public.order_outstanding(uuid) to authenticated;

-- ============================================================================
-- 3. get_customer_total_outstanding — vendor asks "how much does this
--    customer owe me across all orders?"
-- ============================================================================
create or replace function public.get_customer_total_outstanding(
  p_customer_profile_id uuid,
  p_vendor_id uuid
)
returns numeric
language sql
stable
security definer
as $$
  select coalesce(
    sum(greatest(
      round(coalesce(o.total_amount,0))
        - coalesce(o.amount_paid,0)
        - coalesce(o.credit_applied,0),
      0
    )),
    0
  )
  from public.orders o
  where o.customer_profile_id = p_customer_profile_id
    and o.vendor_id = p_vendor_id
    and o.status not in ('cancelled','rejected');
$$;

grant execute on function public.get_customer_total_outstanding(uuid, uuid) to authenticated;

-- ============================================================================
-- 4. Widen payment_amendment_requests CHECK to include 'refund'
-- ============================================================================
alter table public.payment_amendment_requests
  drop constraint if exists payment_amendment_requests_requested_action_check;

alter table public.payment_amendment_requests
  add constraint payment_amendment_requests_requested_action_check
  check (requested_action in ('edit','delete','refund'));

-- ============================================================================
-- 5. process_refund — rider refunds a PRE-settlement transaction
--    Creates a refund transaction, reverses amount_paid, credits wallet
-- ============================================================================
create or replace function public.process_refund(
  p_transaction_id uuid,
  p_amount numeric,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_rider_profile_id uuid;
  v_refund_amount numeric;
  v_new_outstanding numeric;
  v_refund_txn_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required for refund';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id for update;
  if v_txn.id is null then raise exception 'Payment not found'; end if;
  if v_txn.status <> 'active' then raise exception 'Only active payments can be refunded'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can process a refund';
  end if;

  if v_txn.settled then
    raise exception 'This payment is already settled — request a refund amendment from the vendor instead';
  end if;

  v_refund_amount := least(round(coalesce(p_amount, v_txn.amount)), v_txn.amount);
  if v_refund_amount <= 0 then
    raise exception 'Refund amount must be positive';
  end if;

  update public.orders
    set amount_paid = greatest(coalesce(amount_paid,0) - v_refund_amount, 0),
        outstanding_amount = greatest(
          round(coalesce(total_amount,0))
            - greatest(coalesce(amount_paid,0) - v_refund_amount, 0)
            - coalesce(credit_applied,0),
          0
        ),
        updated_at = now()
    where id = v_txn.order_id;

  select greatest(
    round(coalesce(total_amount,0))
      - greatest(coalesce(amount_paid,0) - v_refund_amount, 0)
      - coalesce(credit_applied,0),
    0
  ) into v_new_outstanding
  from public.orders where id = v_txn.order_id;

  perform public.adjust_wallet_balance(
    v_txn.customer_profile_id, v_refund_amount, 'credit', v_txn.order_id,
    'Refund: ' || coalesce(p_reason, 'Rider-initiated refund')
  );

  if v_refund_amount >= v_txn.amount then
    update public.payment_transactions set status = 'deleted', updated_at = now() where id = v_txn.id;
  else
    update public.payment_transactions
      set amount = v_txn.amount - v_refund_amount, updated_at = now()
      where id = v_txn.id;
  end if;

  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by
  ) values (
    v_txn.order_id, v_txn.customer_profile_id, v_txn.rider_id, v_txn.vendor_id,
    v_refund_amount,
    public.order_outstanding(v_txn.order_id) + v_refund_amount,
    v_new_outstanding,
    coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0) - v_refund_amount,
    coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0),
    'refund', coalesce(p_reason, 'Rider-initiated refund'), auth.uid()
  ) returning id into v_refund_txn_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (v_txn.id, 'refund', v_txn.amount, v_txn.amount - v_refund_amount, p_reason, auth.uid());

  return json_build_object(
    'refund_transaction_id', v_refund_txn_id,
    'refunded_amount', v_refund_amount,
    'new_outstanding', v_new_outstanding
  );
end;
$$;

grant execute on function public.process_refund(uuid, numeric, text) to authenticated;

-- ============================================================================
-- 6. Update resolve_payment_amendment — handle 'refund' action on approval
-- ============================================================================
create or replace function public.resolve_payment_amendment(
  p_request_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_req public.payment_amendment_requests;
  v_txn public.payment_transactions;
  v_vendor_profile_id uuid;
  v_delta numeric;
  v_refund_amount numeric;
  v_new_outstanding numeric;
  v_refund_txn_id uuid;
begin
  select * into v_req from public.payment_amendment_requests where id = p_request_id for update;
  if v_req.id is null then raise exception 'Amendment request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'This request is already resolved'; end if;

  select profile_id into v_vendor_profile_id from public.vendors where id = v_req.vendor_id;
  if v_vendor_profile_id is distinct from auth.uid() then
    raise exception 'Only the vendor can resolve this request';
  end if;

  select * into v_txn from public.payment_transactions where id = v_req.payment_transaction_id for update;

  if p_approve then
    if v_req.requested_action = 'delete' then
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_txn.amount, 0),
            outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) - v_txn.amount,0) - coalesce(credit_applied,0), 0),
            updated_at = now()
        where id = v_txn.order_id;
      update public.payment_transactions set status = 'deleted', updated_at = now() where id = v_txn.id;

    elsif v_req.requested_action = 'refund' then
      v_refund_amount := least(round(coalesce(v_req.requested_amount, v_txn.amount)), v_txn.amount);

      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_refund_amount, 0),
            outstanding_amount = greatest(
              round(coalesce(total_amount,0))
                - greatest(coalesce(amount_paid,0) - v_refund_amount, 0)
                - coalesce(credit_applied,0),
              0
            ),
            updated_at = now()
        where id = v_txn.order_id;

      select greatest(
        round(coalesce(total_amount,0))
          - coalesce(amount_paid,0)
          - coalesce(credit_applied,0),
        0
      ) into v_new_outstanding
      from public.orders where id = v_txn.order_id;

      perform public.adjust_wallet_balance(
        v_txn.customer_profile_id, v_refund_amount, 'credit', v_txn.order_id,
        'Refund (vendor approved): ' || coalesce(v_req.reason, 'Amendment refund')
      );

      if v_refund_amount >= v_txn.amount then
        update public.payment_transactions set status = 'deleted', updated_at = now() where id = v_txn.id;
      else
        update public.payment_transactions
          set amount = v_txn.amount - v_refund_amount, updated_at = now()
          where id = v_txn.id;
      end if;

      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by
      ) values (
        v_txn.order_id, v_txn.customer_profile_id, v_txn.rider_id, v_txn.vendor_id,
        v_refund_amount,
        v_new_outstanding + v_refund_amount,
        v_new_outstanding,
        coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0) - v_refund_amount,
        coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0),
        'refund', 'Vendor-approved refund: ' || coalesce(v_req.reason, ''), auth.uid()
      ) returning id into v_refund_txn_id;

    else -- edit
      v_delta := round(coalesce(v_req.requested_amount,0)) - v_txn.amount;
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) + v_delta, 0),
            outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) + v_delta,0) - coalesce(credit_applied,0), 0),
            updated_at = now()
        where id = v_txn.order_id;
      update public.payment_transactions set amount = round(coalesce(v_req.requested_amount,0)), updated_at = now() where id = v_txn.id;
    end if;

    update public.payment_amendment_requests
      set status = 'approved', resolved_at = now(), resolved_by = auth.uid()
      where id = p_request_id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_approve', v_txn.amount, round(coalesce(v_req.requested_amount, 0)), coalesce(p_reason, v_req.reason), auth.uid());
  else
    update public.payment_amendment_requests
      set status = 'rejected', resolved_at = now(), resolved_by = auth.uid()
      where id = p_request_id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_reject', v_txn.amount, v_txn.amount, coalesce(p_reason, 'Rejected'), auth.uid());
  end if;

  return json_build_object('request_id', p_request_id, 'approved', p_approve);
end;
$$;

-- ============================================================================
-- 7. get_customer_wallet_summary — customer self-service wallet view
--    Returns balance, total outstanding across all vendors, and transactions
-- ============================================================================
create or replace function public.get_customer_wallet_summary()
returns json
language plpgsql
security definer
as $$
declare
  v_profile_id uuid := auth.uid();
  v_balance numeric;
  v_total_outstanding numeric;
  v_pending_order_count int;
  v_transactions json;
begin
  select coalesce(balance, 0) into v_balance
  from public.wallets where profile_id = v_profile_id;
  v_balance := coalesce(v_balance, 0);

  -- Use outstanding_amount column which correctly reflects debt after refunds
  -- The process_refund RPC sets this to 0 for refunded orders
  select coalesce(sum(outstanding_amount), 0),
    count(*) filter (where outstanding_amount > 0)
  into v_total_outstanding, v_pending_order_count
  from public.orders
  where customer_profile_id = v_profile_id
    and status not in ('cancelled','rejected');

  select json_agg(t order by t.created_at desc)
  into v_transactions
  from (
    select wt.id, wt.type, wt.amount, wt.description, wt.order_id,
           o.order_number, wt.created_at
    from public.wallet_transactions wt
    left join public.orders o on o.id = wt.order_id
    where wt.wallet_id = (select id from public.wallets where profile_id = v_profile_id)
    order by wt.created_at desc
    limit 100
  ) t;

  return json_build_object(
    'balance', v_balance,
    'total_outstanding', v_total_outstanding,
    'pending_order_count', v_pending_order_count,
    'transactions', coalesce(v_transactions, '[]'::json)
  );
end;
$$;

grant execute on function public.get_customer_wallet_summary() to authenticated;
