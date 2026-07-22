-- ============================================================================
-- AquaFlow — Migration 0026: Pending Payments, Audit Log Fix, Storage & Debt Fixes
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Widen payment_audit_logs CHECK constraint
-- ----------------------------------------------------------------------------
alter table public.payment_audit_logs
  drop constraint if exists payment_audit_logs_action_check;

alter table public.payment_audit_logs
  add constraint payment_audit_logs_action_check
  check (action in ('create','edit','delete','amend_request','amend_approve','amend_reject','refund','collect_pending','apply_credit'));

-- ----------------------------------------------------------------------------
-- 2. Storage Bucket Fix: Make delivery-proofs public & readable
-- ----------------------------------------------------------------------------
update storage.buckets set public = true where id = 'delivery-proofs';

drop policy if exists "delivery_proofs_public_read" on storage.objects;
create policy "delivery_proofs_public_read" on storage.objects
  for select using (bucket_id = 'delivery-proofs');

-- ----------------------------------------------------------------------------
-- 3. Vendors RLS Fix: Ensure riders and customers can read vendor profiles
-- ----------------------------------------------------------------------------
drop policy if exists "vendors_select_all" on public.vendors;
create policy "vendors_select_all" on public.vendors
  for select using (true);

-- ----------------------------------------------------------------------------
-- 4. Trigger: Automatically zero out outstanding_amount when order is cancelled/rejected
-- ----------------------------------------------------------------------------
create or replace function public.zero_outstanding_on_cancel()
returns trigger
language plpgsql
security definer
as $$
begin
  if NEW.status in ('cancelled', 'rejected') then
    NEW.outstanding_amount := 0;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_orders_zero_outstanding_on_cancel on public.orders;
create trigger trg_orders_zero_outstanding_on_cancel
  before insert or update on public.orders
  for each row
  execute function public.zero_outstanding_on_cancel();

-- Retroactively fix existing cancelled/rejected orders
update public.orders
  set outstanding_amount = 0
  where status in ('cancelled', 'rejected') and outstanding_amount > 0;

-- ----------------------------------------------------------------------------
-- 5. RPC get_rider_pending_customers: ONLY return customers with debt on orders assigned to THIS rider
-- ----------------------------------------------------------------------------
create or replace function public.get_rider_pending_customers(p_rider_id uuid)
returns json[]
language plpgsql
security definer
as $$
declare
  v_rider_profile_id uuid;
  v_results json[];
begin
  select profile_id into v_rider_profile_id
  from public.riders
  where id = p_rider_id;

  if v_rider_profile_id is distinct from auth.uid() and not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  select array_agg(
    json_build_object(
      'id', c.id,
      'profile_id', c.profile_id,
      'full_name', p.full_name,
      'phone', p.phone,
      'email', p.email,
      'address', (
        select a.full_address
        from public.addresses a
        where a.customer_profile_id = c.profile_id
        order by a.is_default desc, a.created_at asc
        limit 1
      ),
      'outstanding', coalesce(
        (select sum(coalesce(o.outstanding_amount,0))
         from public.orders o
         where o.customer_profile_id = c.profile_id
           and o.rider_id = p_rider_id
           and o.status not in ('cancelled','rejected')),
        0
      )
    )
  )
  into v_results
  from public.customers c
  join public.profiles p on p.id = c.profile_id
  where exists (
    select 1 from public.orders o
    where o.customer_profile_id = c.profile_id
      and o.rider_id = p_rider_id
      and o.status not in ('cancelled','rejected')
      and coalesce(o.outstanding_amount, 0) > 0
  );

  return coalesce(v_results, '{}');
end;
$$;

grant execute on function public.get_rider_pending_customers(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. Re-implement get_rider_cod_balance RPC using actual payment_transactions
-- ----------------------------------------------------------------------------
create or replace function public.get_rider_cod_balance(
  p_rider_id uuid,
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
as $$
declare
  v_outstanding numeric := 0;
  v_pending numeric := 0;
  v_total_submitted numeric := 0;
  v_total_verified numeric := 0;
  v_total_collected numeric := 0;
begin
  -- Settlements created by rider
  select
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0),
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0),
    coalesce(sum(amount), 0),
    coalesce(sum(case when status = 'verified' then amount else 0 end), 0)
  into v_pending, v_outstanding, v_total_submitted, v_total_verified
  from public.cod_settlements
  where rider_id = p_rider_id and vendor_id = p_vendor_id;

  -- Total collected from active payment transactions (delivery payments + pending
  -- payment collections). IMPORTANT: 'refund' rows must NOT be subtracted again
  -- here — process_refund / resolve_payment_amendment already reduce the
  -- ORIGINAL transaction's `amount` when a refund happens, and insert the
  -- 'refund' row purely as a display/audit record. Summing 'refund' on top of
  -- that double-counts the refund and understates the rider's true COD
  -- balance (this was the cause of the rider wallet showing a lower number
  -- than the vendor's rider-cash-position view for the same rider).
  select coalesce(sum(amount), 0) into v_total_collected
  from public.payment_transactions
  where rider_id = p_rider_id
    and vendor_id = p_vendor_id
    and status = 'active'
    and payment_type in ('full', 'partial', 'over');

  -- Fallback for legacy delivered COD orders if no payment transactions exist yet
  if v_total_collected <= 0 then
    select coalesce(sum(coalesce(amount_paid, total_amount)), 0) into v_total_collected
    from public.orders
    where vendor_id = p_vendor_id
      and rider_id = p_rider_id
      and status in ('delivered', 'completed')
      and payment_method = 'cod';
  end if;

  v_outstanding := greatest(v_total_collected - v_total_verified, 0);

  return json_build_object(
    'outstanding', v_outstanding,
    'pending', v_pending,
    'total_submitted', v_total_submitted,
    'total_verified', v_total_verified,
    'total_collected', v_total_collected
  );
end;
$$;

grant execute on function public.get_rider_cod_balance(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Atomic collect_pending_payment RPC (Rider-scoped FIFO debt allocation & Idempotency)
-- ----------------------------------------------------------------------------
create or replace function public.collect_pending_payment(
  p_customer_profile_id uuid,
  p_vendor_id uuid,
  p_amount numeric,
  p_receipt_url text default null,
  p_receipt_meta jsonb default '{}'::jsonb,
  p_notes text default null,
  p_idempotency_key text default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_caller_rider_id uuid;
  v_caller_profile_id uuid := auth.uid();
  v_remaining_payment numeric := round(coalesce(p_amount, 0));
  v_order_rec record;
  v_apply numeric;
  v_outstanding_before numeric;
  v_outstanding_after numeric;
  v_credit_before numeric := 0;
  v_credit_after numeric := 0;
  v_excess numeric := 0;
  v_total_settled numeric := 0;
  v_total_debt_remaining numeric := 0;
  v_txn_id uuid;
  v_txn_ids uuid[] := '{}';
  v_existing_txn_id uuid;
begin
  if v_caller_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  if v_remaining_payment <= 0 then
    raise exception 'Payment amount must be positive';
  end if;

  -- Idempotency check: if idempotency key provided, check if transaction already exists
  if p_idempotency_key is not null and length(trim(p_idempotency_key)) > 0 then
    select id into v_existing_txn_id
    from public.payment_transactions
    where notes like '%[idempotency:' || p_idempotency_key || ']%'
    limit 1;

    if v_existing_txn_id is not null then
      select coalesce(balance, 0) into v_credit_after from public.wallets where profile_id = p_customer_profile_id;
      return json_build_object(
        'success', true,
        'duplicate', true,
        'message', 'Payment already processed',
        'settled_amount', p_amount,
        'wallet_credit', v_credit_after
      );
    end if;
  end if;

  -- Get rider ID if caller is a rider
  select id into v_caller_rider_id from public.riders where profile_id = v_caller_profile_id limit 1;

  -- Lock wallets table to get customer wallet balance
  select coalesce(balance, 0) into v_credit_before
  from public.wallets where profile_id = p_customer_profile_id for update;
  v_credit_before := coalesce(v_credit_before, 0);

  -- FIFO Loop over customer's unpaid/partially-paid orders for this vendor allotted to THIS rider (oldest first)
  for v_order_rec in
    select * from public.orders
    where customer_profile_id = p_customer_profile_id
      and vendor_id = p_vendor_id
      and (v_caller_rider_id is null or rider_id = v_caller_rider_id)
      and status not in ('cancelled', 'rejected')
      and (
        greatest(round(coalesce(total_amount,0)) - coalesce(amount_paid,0) - coalesce(credit_applied,0), 0) > 0
        or payment_status in ('pending', 'partial')
      )
    order by created_at asc
    for update
  loop
    exit when v_remaining_payment <= 0;

    v_outstanding_before := greatest(
      round(coalesce(v_order_rec.total_amount,0)) - coalesce(v_order_rec.amount_paid,0) - coalesce(v_order_rec.credit_applied,0),
      0
    );

    if v_outstanding_before > 0 then
      v_apply := least(v_remaining_payment, v_outstanding_before);
      v_outstanding_after := greatest(v_outstanding_before - v_apply, 0);

      -- Update order header
      update public.orders
        set amount_paid = coalesce(amount_paid, 0) + v_apply,
            outstanding_amount = v_outstanding_after,
            payment_status = case when v_outstanding_after = 0 then 'paid'::payment_status else 'partial'::payment_status end,
            updated_at = now()
        where id = v_order_rec.id;

      -- Insert payment transaction
      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by
      ) values (
        v_order_rec.id, p_customer_profile_id, v_caller_rider_id, p_vendor_id, v_apply,
        v_outstanding_before, v_outstanding_after, v_credit_before, v_credit_before,
        'full',
        coalesce(p_notes, 'Pending payment collection') ||
          case when p_idempotency_key is not null then ' [idempotency:' || p_idempotency_key || ']' else '' end,
        v_caller_profile_id
      ) returning id into v_txn_id;

      v_txn_ids := array_append(v_txn_ids, v_txn_id);

      -- Upload/Link receipt if provided
      if p_receipt_url is not null and length(trim(p_receipt_url)) > 0 then
        insert into public.payment_receipts (
          payment_transaction_id, vendor_id, receipt_type, receipt_url,
          image_hash, gps_lat, gps_lng, device_time, uploaded_by
        ) values (
          v_txn_id, p_vendor_id,
          coalesce(p_receipt_meta->>'receipt_type', 'cash'),
          p_receipt_url,
          p_receipt_meta->>'image_hash',
          (p_receipt_meta->>'gps_lat')::numeric,
          (p_receipt_meta->>'gps_lng')::numeric,
          (p_receipt_meta->>'device_time')::timestamptz,
          v_caller_profile_id
        );
      end if;

      -- Insert audit log
      insert into public.payment_audit_logs (
        payment_transaction_id, action, old_amount, new_amount, reason, performed_by
      ) values (
        v_txn_id, 'collect_pending', v_outstanding_before, v_outstanding_after,
        'Pending payment collected by rider', v_caller_profile_id
      );

      v_total_settled := v_total_settled + v_apply;
      v_remaining_payment := v_remaining_payment - v_apply;
    end if;
  end loop;

  -- ONLY after all pending orders for this rider are cleared:
  -- Excess funds land in wallet credit!
  if v_remaining_payment > 0 then
    v_excess := v_remaining_payment;
    perform public.adjust_wallet_balance(
      p_customer_profile_id, v_excess, 'credit', null,
      'Excess pending payment credit'
    );
    v_credit_after := v_credit_before + v_excess;
  else
    v_credit_after := v_credit_before;
  end if;

  -- Calculate remaining debt across all active orders
  select coalesce(
    sum(greatest(round(coalesce(total_amount,0)) - coalesce(amount_paid,0) - coalesce(credit_applied,0), 0)),
    0
  ) into v_total_debt_remaining
  from public.orders
  where customer_profile_id = p_customer_profile_id
    and vendor_id = p_vendor_id
    and (v_caller_rider_id is null or rider_id = v_caller_rider_id)
    and status not in ('cancelled', 'rejected');

  return json_build_object(
    'success', true,
    'settled_amount', v_total_settled,
    'excess_credit', v_excess,
    'remaining_debt', v_total_debt_remaining,
    'wallet_credit', v_credit_after,
    'transaction_ids', v_txn_ids
  );
end;
$$;

grant execute on function public.collect_pending_payment(uuid, uuid, numeric, text, jsonb, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. Update process_refund RPC (Corrected Debt Settlement Logic)
--
-- BUG FIX: the previous version computed
--   v_other_outstanding / (sum of outstanding across the same set of orders)
-- which is always 1, so it subtracted the FULL v_debt_cleared amount from
-- EVERY other outstanding order at once instead of distributing it. Fixed to
-- clear debt FIFO (oldest order first), capped at each order's own
-- outstanding_amount, mirroring the allocation style used in
-- collect_pending_payment. Also captures this order's outstanding_amount
-- BEFORE it gets zeroed out, so the audit trail's outstanding_before is
-- correct instead of always reading back 0.
-- ----------------------------------------------------------------------------
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
  v_customer_profile_id uuid;
  v_vendor_id uuid;
  v_order_id uuid;
  v_refund_amount numeric;
  v_refund_txn_id uuid;
  v_debt_txn_id uuid;
  v_other_outstanding numeric := 0;
  v_debt_cleared numeric := 0;
  v_amount_returned numeric := 0;
  v_order_outstanding_before numeric := 0;
  v_remaining_to_clear numeric := 0;
  v_apply numeric;
  v_order_rec record;
  v_wallet_balance numeric := 0;
  v_loop_outstanding_before numeric;
  v_loop_outstanding_after numeric;
  v_refunded_order_number text;
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

  v_customer_profile_id := v_txn.customer_profile_id;
  v_vendor_id := v_txn.vendor_id;
  v_order_id := v_txn.order_id;

  select coalesce(balance, 0) into v_wallet_balance from public.wallets where profile_id = v_customer_profile_id;
  v_wallet_balance := coalesce(v_wallet_balance, 0);

  -- Capture this order's outstanding amount BEFORE we zero it out below
  select coalesce(outstanding_amount, 0), order_number into v_order_outstanding_before, v_refunded_order_number
  from public.orders where id = v_order_id;

  -- Get outstanding debt from OTHER orders (excluding this one being refunded)
  select coalesce(sum(outstanding_amount), 0) into v_other_outstanding
  from public.orders
  where customer_profile_id = v_customer_profile_id
    and vendor_id = v_vendor_id
    and status not in ('cancelled', 'rejected')
    and id != v_order_id;

  -- BUSINESS LOGIC:
  -- 1. First, clear other outstanding debt with the refund amount, oldest order first (FIFO)
  -- 2. Only return remaining amount to customer
  -- 3. Remove debt from this order completely (cancel the debt)

  v_debt_cleared := least(v_refund_amount, v_other_outstanding);
  v_amount_returned := v_refund_amount - v_debt_cleared;

  -- BUG FIX: this money never actually leaves the rider's hand — it is
  -- REALLOCATED from the refunded order onto the debt-carrying order(s), not
  -- handed back to the customer. The old code only reduced outstanding_amount
  -- here without ever crediting amount_paid, so the reallocated cash quietly
  -- disappeared from every orders-table-based total (get_vendor_payment_overview,
  -- customer ledgers, etc.) even though the rider was still holding it. It also
  -- never recorded a payment_transactions row for the credited order, so
  -- payment_transactions-based totals (get_rider_cod_balance) fell out of sync
  -- with the orders table by the exact same amount — this was the root cause
  -- of "COD collected" and "wallet balance" disagreeing after a refund.
  -- Fix: credit amount_paid on the cleared order (mirroring
  -- collect_pending_payment's FIFO allocation) and log a matching transaction.
  if v_debt_cleared > 0 then
    v_remaining_to_clear := v_debt_cleared;

    for v_order_rec in
      select * from public.orders
      where customer_profile_id = v_customer_profile_id
        and vendor_id = v_vendor_id
        and status not in ('cancelled', 'rejected')
        and id != v_order_id
        and outstanding_amount > 0
      order by created_at asc
      for update
    loop
      exit when v_remaining_to_clear <= 0;

      v_apply := least(v_remaining_to_clear, v_order_rec.outstanding_amount);
      v_loop_outstanding_before := v_order_rec.outstanding_amount;
      v_loop_outstanding_after := greatest(v_loop_outstanding_before - v_apply, 0);

      update public.orders
        set amount_paid = coalesce(amount_paid, 0) + v_apply,
            outstanding_amount = v_loop_outstanding_after,
            payment_status = case when v_loop_outstanding_after = 0 then 'paid'::payment_status else payment_status end,
            updated_at = now()
        where id = v_order_rec.id;

      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by
      ) values (
        v_order_rec.id, v_customer_profile_id, v_txn.rider_id, v_vendor_id, v_apply,
        v_loop_outstanding_before, v_loop_outstanding_after, v_wallet_balance, v_wallet_balance,
        'full', 'Debt cleared via refund reallocation from order #' || coalesce(v_refunded_order_number, ''),
        auth.uid()
      ) returning id into v_debt_txn_id;

      insert into public.payment_audit_logs (
        payment_transaction_id, action, old_amount, new_amount, reason, performed_by
      ) values (
        v_debt_txn_id, 'collect_pending', v_loop_outstanding_before, v_loop_outstanding_after,
        'Outstanding balance cleared via refund reallocation', auth.uid()
      );

      v_remaining_to_clear := v_remaining_to_clear - v_apply;
    end loop;
  end if;

  -- For this order: remove the paid amount and clear debt
  -- The debt for this order is cancelled (removed entirely)
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid, 0) - v_refund_amount, 0),
        outstanding_amount = 0,
        payment_status = case when v_refund_amount >= v_txn.amount then 'refunded'::payment_status else payment_status end,
        updated_at = now()
    where id = v_order_id;

  -- Update or soft-delete original payment transaction
  if v_refund_amount >= v_txn.amount then
    update public.payment_transactions set status = 'deleted', updated_at = now() where id = v_txn.id;
  else
    update public.payment_transactions
      set amount = v_txn.amount - v_refund_amount, updated_at = now()
      where id = v_txn.id;
  end if;

  -- Create refund audit transaction. This is a DISPLAY/HISTORY record only —
  -- it must never be summed alongside 'full'/'partial'/'over' rows when
  -- computing collected cash, because the original transaction's amount
  -- above already nets out the refunded portion. (See get_rider_cod_balance
  -- and get_vendor_finance_kpis, which deliberately exclude payment_type =
  -- 'refund' from their collected-cash totals for this reason.)
  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by
  ) values (
    v_txn.order_id, v_txn.customer_profile_id, v_txn.rider_id, v_txn.vendor_id,
    v_refund_amount,
    v_other_outstanding + v_order_outstanding_before,
    v_other_outstanding - v_debt_cleared,
    v_wallet_balance,
    v_wallet_balance,
    'refund', coalesce(p_reason, 'Rider cash refund'), auth.uid()
  ) returning id into v_refund_txn_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (v_txn.id, 'refund', v_txn.amount, v_txn.amount - v_refund_amount, p_reason, auth.uid());

  return json_build_object(
    'refund_transaction_id', v_refund_txn_id,
    'refunded_amount', v_refund_amount,
    'debt_cleared', v_debt_cleared,
    'amount_returned_to_customer', v_amount_returned,
    'new_outstanding', v_other_outstanding - v_debt_cleared
  );
end;
$$;

grant execute on function public.process_refund(uuid, numeric, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. Update resolve_payment_amendment RPC (Vendor Cash Refund: No Wallet Credit & No Debt Inflation)
-- ----------------------------------------------------------------------------
create or replace function public.resolve_payment_amendment(
  p_request_id uuid,
  p_approve bool,
  p_review_notes text default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_req public.payment_amendment_requests;
  v_txn public.payment_transactions;
  v_vendor_profile_id uuid;
  v_refund_amount numeric;
  v_refund_txn_id uuid;
  v_delta numeric;
begin
  select * into v_req from public.payment_amendment_requests where id = p_request_id for update;
  if v_req.id is null then raise exception 'Amendment request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is already processed'; end if;

  select profile_id into v_vendor_profile_id from public.vendors where id = v_req.vendor_id;
  if v_vendor_profile_id is distinct from auth.uid() then
    raise exception 'Only the vendor can resolve this request';
  end if;

  select * into v_txn from public.payment_transactions where id = v_req.payment_transaction_id for update;

  if p_approve then
    if v_req.requested_action = 'delete' then
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_txn.amount, 0),
            outstanding_amount = 0,
            updated_at = now()
        where id = v_txn.order_id;
      update public.payment_transactions set status = 'deleted', updated_at = now() where id = v_txn.id;

    elsif v_req.requested_action = 'refund' then
      v_refund_amount := least(round(coalesce(v_req.requested_amount, v_txn.amount)), v_txn.amount);

      -- CASH REFUND: Do NOT increase outstanding debt
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_refund_amount, 0),
            outstanding_amount = 0,
            payment_status = case when v_refund_amount >= v_txn.amount then 'refunded'::payment_status else payment_status end,
            updated_at = now()
        where id = v_txn.order_id;

      -- DO NOT add wallet credit for cash refunds!

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
        0, 0,
        coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0),
        coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0),
        'refund', 'Vendor-approved cash refund: ' || coalesce(v_req.reason, ''), auth.uid()
      ) returning id into v_refund_txn_id;

    else -- edit
      v_delta := round(coalesce(v_req.requested_amount,0)) - v_txn.amount;
      update public.payment_transactions
        set amount = round(coalesce(v_req.requested_amount,0)), updated_at = now()
        where id = v_txn.id;

      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) + v_delta, 0),
            updated_at = now()
        where id = v_txn.order_id;
    end if;

    update public.payment_amendment_requests
      set status = 'approved', review_notes = p_review_notes, reviewed_by = auth.uid(), updated_at = now()
      where id = v_req.id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_approve', v_txn.amount, coalesce(v_req.requested_amount, 0), v_req.reason, auth.uid());

  else
    update public.payment_amendment_requests
      set status = 'rejected', review_notes = p_review_notes, reviewed_by = auth.uid(), updated_at = now()
      where id = v_req.id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_reject', v_txn.amount, v_txn.amount, p_review_notes, auth.uid());
  end if;

  return json_build_object('success', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end;
$$;

grant execute on function public.resolve_payment_amendment(uuid, bool, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 10. Update get_vendor_finance_kpis (Subtract refunds from collections)
-- ----------------------------------------------------------------------------
create or replace function public.get_vendor_finance_kpis(p_vendor_id uuid)
returns json
language plpgsql
security definer
as $$
declare
  v_today_start timestamptz := date_trunc('day', now());
  v_month_start timestamptz := date_trunc('month', now());
  v_todays_collection numeric;
  v_months_collection numeric;
  v_pending_collection numeric;
  v_outstanding_customers int;
  v_credits_issued numeric;
  v_refunds numeric;
  v_partial_count int;
  v_awaiting_settlement numeric;
begin
  if not exists (
    select 1 from public.vendors where id = p_vendor_id and profile_id = auth.uid()
    union
    select 1 from public.riders where vendor_id = p_vendor_id and profile_id = auth.uid()
  ) then
    raise exception 'Not authorized';
  end if;

  -- Same double-counting fix as get_rider_cod_balance: the original
  -- transaction's amount is already reduced by any refund, so summing only
  -- collection-type rows (and leaving 'refund' rows out) avoids subtracting
  -- the refund twice.
  select coalesce(sum(amount), 0)
  into v_todays_collection
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active'
    and payment_type in ('full', 'partial', 'over')
    and created_at >= v_today_start;

  select coalesce(sum(amount), 0)
  into v_months_collection
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active'
    and payment_type in ('full', 'partial', 'over')
    and created_at >= v_month_start;

  select coalesce(sum(outstanding_amount), 0) into v_pending_collection
  from public.orders where vendor_id = p_vendor_id and status not in ('cancelled', 'rejected');

  select count(distinct customer_profile_id) into v_outstanding_customers
  from public.orders where vendor_id = p_vendor_id and outstanding_amount > 0 and status not in ('cancelled', 'rejected');

  select coalesce(sum(amount), 0) into v_credits_issued
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active' and payment_type = 'over';

  select coalesce(sum(amount), 0) into v_refunds
  from public.payment_transactions
  where vendor_id = p_vendor_id and payment_type = 'refund';

  select count(*) into v_partial_count
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active' and payment_type = 'partial';

  select coalesce(sum(amount), 0) into v_awaiting_settlement
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active' and settled = false
    and payment_type in ('full', 'partial', 'over');

  return json_build_object(
    'todays_collection', greatest(v_todays_collection, 0),
    'months_collection', greatest(v_months_collection, 0),
    'pending_collection', v_pending_collection,
    'outstanding_customers', v_outstanding_customers,
    'credits_issued', v_credits_issued,
    'refunds', v_refunds,
    'partial_count', v_partial_count,
    'awaiting_settlement', v_awaiting_settlement
  );
end;
$$;

grant execute on function public.get_vendor_finance_kpis(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 11. SECURITY FIX: get_customer_ledger had no authorization check at all —
-- any authenticated user could pass an arbitrary p_customer_profile_id and
-- read that customer's full purchase history, payments, outstanding balance
-- and wallet credit. Restrict it to the customer themselves or a vendor who
-- has actually served that customer (mirrors the scoping already used by
-- get_vendor_payment_overview / get_vendor_rider_cash_positions).
-- ----------------------------------------------------------------------------
create or replace function public.get_customer_ledger(p_customer_profile_id uuid)
returns json
language plpgsql
security definer
as $$
declare
  v_total_purchases numeric;
  v_total_paid numeric;
  v_outstanding numeric;
  v_credit numeric;
  v_last_payment timestamptz;
  v_entries json;
begin
  if auth.uid() is distinct from p_customer_profile_id
    and not exists (
      select 1 from public.orders o
      join public.vendors v on v.id = o.vendor_id
      where o.customer_profile_id = p_customer_profile_id and v.profile_id = auth.uid()
    )
  then
    raise exception 'Not authorized';
  end if;

  select coalesce(sum(round(total_amount)), 0) into v_total_purchases
  from public.orders where customer_profile_id = p_customer_profile_id;

  select coalesce(sum(amount), 0) into v_total_paid
  from public.payment_transactions
  where customer_profile_id = p_customer_profile_id
    and status = 'active' and payment_type in ('full','partial','over','credit');

  select coalesce(sum(outstanding_amount), 0) into v_outstanding
  from public.orders where customer_profile_id = p_customer_profile_id;

  select coalesce(balance, 0) into v_credit
  from public.wallets where profile_id = p_customer_profile_id;
  v_credit := coalesce(v_credit, 0);

  select max(created_at) into v_last_payment
  from public.payment_transactions
  where customer_profile_id = p_customer_profile_id and status = 'active';

  select json_agg(e order by e.created_at desc) into v_entries
  from (
    select t.id, t.order_id, o.order_number, t.amount, t.payment_type,
           t.outstanding_before, t.outstanding_after, t.notes, t.status, t.created_at
    from public.payment_transactions t
    join public.orders o on o.id = t.order_id
    where t.customer_profile_id = p_customer_profile_id
  ) e;

  return json_build_object(
    'total_purchases', v_total_purchases,
    'total_paid', v_total_paid,
    'outstanding', v_outstanding,
    'available_credit', v_credit,
    'last_payment_at', v_last_payment,
    'entries', coalesce(v_entries, '[]'::json)
  );
end;
$$;

grant execute on function public.get_customer_ledger(uuid) to authenticated;