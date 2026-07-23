-- ============================================================================
-- AquaFlow — Migration 0027: Refund History Preservation & Outstanding
-- Consistency Fix
--
-- Two distinct, confirmed-live bugs, both stemming from the same root
-- problem: multiple functions each kept their own private notion of "how
-- much is owed / how much was collected" instead of trusting the
-- `orders.outstanding_amount` / `payment_transactions.amount` columns as
-- the single source of truth.
--
-- BUG 1 — destructive history mutation:
-- process_refund / resolve_payment_amendment's 'refund' branch permanently
-- overwrote the ORIGINAL payment_transactions row's `amount` (e.g. a real
-- Rs 360 collection got silently rewritten to Rs 80 after an Rs 280
-- refund). This is why "Track Order" showed "Full payment: Rs 80" instead
-- of the true Rs 360 that was actually collected — the original number was
-- gone, not just netted. Fix: refunds are now purely ADDITIVE. The
-- original transaction is never touched; a new `payment_transactions.
-- refunds_transaction_id` column links each refund row back to the
-- original it refunds, so the true collected amount is always visible and
-- refunds/partial-refunds against the same original are still capped
-- correctly (no double-refunding).
--
-- BUG 2 — stale "outstanding" recomputation:
-- get_vendor_customers, get_customer_total_outstanding, and
-- collect_pending_payment's FIFO order-selection all recomputed
-- `total_amount - amount_paid - credit_applied` from scratch instead of
-- reading `orders.outstanding_amount` (the column every payment RPC
-- already keeps correct, including the "this order's debt is forgiven"
-- rule after a refund reallocation). Recomputing blindly ignored that
-- forgiveness, so a fully-settled order could still show as "owed" on the
-- vendor's customer list — e.g. "Owes Rs 280" on an order whose real
-- outstanding_amount was already 0. Fix: read the column everywhere.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Link refund rows back to the original transaction they refund, so we
--    never need to mutate the original to know "how much has already been
--    refunded against it."
-- ----------------------------------------------------------------------------
alter table public.payment_transactions
  add column if not exists refunds_transaction_id uuid references public.payment_transactions(id) on delete set null;

create index if not exists idx_pay_txn_refunds
  on public.payment_transactions(refunds_transaction_id)
  where refunds_transaction_id is not null;

-- ----------------------------------------------------------------------------
-- 2. process_refund — rewritten to never mutate the original transaction.
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
  v_already_refunded numeric := 0;
  v_available numeric;
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

  -- How much of this ORIGINAL transaction has already been refunded
  -- (across possibly more than one prior partial refund)? The original's
  -- own `amount` never changes, so this is always computed live rather
  -- than trusted from a mutated column.
  select coalesce(sum(amount), 0) into v_already_refunded
  from public.payment_transactions
  where refunds_transaction_id = v_txn.id and status = 'active';

  v_available := v_txn.amount - v_already_refunded;
  if v_available <= 0 then
    raise exception 'This payment has already been fully refunded';
  end if;

  v_refund_amount := least(round(coalesce(p_amount, v_available)), v_available);
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

  -- This money never actually leaves the rider's hand when it's reallocated
  -- to cover another order's debt — so that order's amount_paid must be
  -- credited (mirroring collect_pending_payment's FIFO allocation), with a
  -- matching payment_transactions row so every collected-cash total stays
  -- in sync with the orders table.
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

  -- For this order: remove the paid amount and clear its own debt (the
  -- debt for this order is cancelled/forgiven, not carried forward).
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid, 0) - v_refund_amount, 0),
        outstanding_amount = 0,
        payment_status = case when v_refund_amount >= v_available then 'refunded'::payment_status else payment_status end,
        updated_at = now()
    where id = v_order_id;

  -- The ORIGINAL transaction is never mutated — its `amount` permanently
  -- records the true amount actually collected at the time. This refund
  -- row is the only record of money moving back out, linked via
  -- refunds_transaction_id so future refund attempts against the same
  -- original correctly see how much remains available.
  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by, refunds_transaction_id
  ) values (
    v_txn.order_id, v_txn.customer_profile_id, v_txn.rider_id, v_txn.vendor_id,
    v_refund_amount,
    v_other_outstanding + v_order_outstanding_before,
    v_other_outstanding - v_debt_cleared,
    v_wallet_balance,
    v_wallet_balance,
    'refund', coalesce(p_reason, 'Rider cash refund'), auth.uid(), v_txn.id
  ) returning id into v_refund_txn_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (v_txn.id, 'refund', v_txn.amount, v_available - v_refund_amount, p_reason, auth.uid());

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
-- 3. resolve_payment_amendment — same "never mutate the original" fix for
--    its 'refund' branch, plus a guard on 'delete'/'edit' so a vendor can't
--    approve an amendment against a transaction that's already had money
--    refunded off it (which would double-count against amount_paid).
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
  v_already_refunded numeric := 0;
  v_available numeric;
begin
  select * into v_req from public.payment_amendment_requests where id = p_request_id for update;
  if v_req.id is null then raise exception 'Amendment request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is already processed'; end if;

  select profile_id into v_vendor_profile_id from public.vendors where id = v_req.vendor_id;
  if v_vendor_profile_id is distinct from auth.uid() then
    raise exception 'Only the vendor can resolve this request';
  end if;

  select * into v_txn from public.payment_transactions where id = v_req.payment_transaction_id for update;

  select coalesce(sum(amount), 0) into v_already_refunded
  from public.payment_transactions
  where refunds_transaction_id = v_txn.id and status = 'active';
  v_available := v_txn.amount - v_already_refunded;

  if p_approve then
    if v_req.requested_action in ('delete', 'edit') and v_already_refunded > 0 then
      raise exception 'This payment already has a refund recorded against it and can no longer be edited or deleted directly';
    end if;

    if v_req.requested_action = 'delete' then
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_txn.amount, 0),
            outstanding_amount = 0,
            updated_at = now()
        where id = v_txn.order_id;
      update public.payment_transactions set status = 'deleted', updated_at = now() where id = v_txn.id;

    elsif v_req.requested_action = 'refund' then
      if v_available <= 0 then
        raise exception 'This payment has already been fully refunded';
      end if;
      v_refund_amount := least(round(coalesce(v_req.requested_amount, v_available)), v_available);

      -- CASH REFUND: Do NOT increase outstanding debt
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_refund_amount, 0),
            outstanding_amount = 0,
            payment_status = case when v_refund_amount >= v_available then 'refunded'::payment_status else payment_status end,
            updated_at = now()
        where id = v_txn.order_id;

      -- DO NOT add wallet credit for cash refunds!

      -- The original transaction is never mutated or marked deleted here
      -- either — see process_refund's header comment for why.
      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by, refunds_transaction_id
      ) values (
        v_txn.order_id, v_txn.customer_profile_id, v_txn.rider_id, v_txn.vendor_id,
        v_refund_amount,
        0, 0,
        coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0),
        coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0),
        'refund', 'Vendor-approved cash refund: ' || coalesce(v_req.reason, ''), auth.uid(), v_txn.id
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
-- 4. edit_payment / delete_payment — same "already refunded" guard for the
--    rider's own pre-settlement edit/delete flow.
-- ----------------------------------------------------------------------------
create or replace function public.edit_payment(
  p_transaction_id uuid,
  p_new_amount numeric,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_order public.orders;
  v_new numeric := round(coalesce(p_new_amount, 0));
  v_delta numeric;
  v_rider_profile_id uuid;
  v_already_refunded numeric := 0;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id for update;
  if v_txn.id is null then raise exception 'Payment not found'; end if;
  if v_txn.status = 'deleted' then raise exception 'Payment already deleted'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can edit this payment';
  end if;

  if v_txn.settled then
    raise exception 'This payment is already settled — submit an amendment request instead';
  end if;

  select coalesce(sum(amount), 0) into v_already_refunded
  from public.payment_transactions
  where refunds_transaction_id = v_txn.id and status = 'active';
  if v_already_refunded > 0 then
    raise exception 'This payment already has a refund recorded against it — request an amendment instead';
  end if;

  if v_new < 0 then raise exception 'Amount cannot be negative'; end if;

  v_delta := v_new - v_txn.amount;

  -- Adjust the order's amount_paid by the delta (bounded by outstanding logic)
  select * into v_order from public.orders where id = v_txn.order_id for update;
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid,0) + v_delta, 0),
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) + v_delta,0) - coalesce(credit_applied,0), 0),
        updated_at = now()
    where id = v_txn.order_id;

  update public.payment_transactions
    set amount = v_new, updated_at = now()
    where id = p_transaction_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (p_transaction_id, 'edit', v_txn.amount, v_new, p_reason, auth.uid());

  return json_build_object('transaction_id', p_transaction_id, 'new_amount', v_new);
end;
$$;

grant execute on function public.edit_payment(uuid, numeric, text) to authenticated;

create or replace function public.delete_payment(
  p_transaction_id uuid,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_rider_profile_id uuid;
  v_already_refunded numeric := 0;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id for update;
  if v_txn.id is null then raise exception 'Payment not found'; end if;
  if v_txn.status = 'deleted' then raise exception 'Payment already deleted'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can delete this payment';
  end if;

  if v_txn.settled then
    raise exception 'This payment is already settled — submit an amendment request instead';
  end if;

  select coalesce(sum(amount), 0) into v_already_refunded
  from public.payment_transactions
  where refunds_transaction_id = v_txn.id and status = 'active';
  if v_already_refunded > 0 then
    raise exception 'This payment already has a refund recorded against it — request an amendment instead';
  end if;

  -- Reverse the order effect
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid,0) - v_txn.amount, 0),
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) - v_txn.amount,0) - coalesce(credit_applied,0), 0),
        payment_status = 'pending'::payment_status,
        updated_at = now()
    where id = v_txn.order_id;

  update public.payment_transactions
    set status = 'deleted', updated_at = now()
    where id = p_transaction_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (p_transaction_id, 'delete', v_txn.amount, 0, p_reason, auth.uid());

  return json_build_object('transaction_id', p_transaction_id, 'status', 'deleted');
end;
$$;

grant execute on function public.delete_payment(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. get_rider_cod_balance / get_vendor_finance_kpis — now that refunds
--    never mutate the original transaction's amount, 'refund' rows must be
--    subtracted again to net out collected cash (this is the opposite of
--    migration 0026's fix, which was only correct because refunds WERE
--    mutating originals at the time — now they don't, so this is safe).
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

  -- Net cash collected: full/partial/over payments minus refunds. Original
  -- transactions are immutable, so refunds must be subtracted explicitly —
  -- they are no longer already "baked into" a reduced original amount.
  select coalesce(
    sum(case when payment_type = 'refund' then -amount else amount end), 0
  ) into v_total_collected
  from public.payment_transactions
  where rider_id = p_rider_id
    and vendor_id = p_vendor_id
    and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund');

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

  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0)
  into v_todays_collection
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund')
    and created_at >= v_today_start;

  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0)
  into v_months_collection
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund')
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
-- 6. get_customer_ledger — total_paid must now also subtract refunds
--    (same reasoning as above).
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

  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0) into v_total_paid
  from public.payment_transactions
  where customer_profile_id = p_customer_profile_id
    and status = 'active' and payment_type in ('full','partial','over','credit','refund');

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

-- ----------------------------------------------------------------------------
-- 7. get_vendor_customers — read outstanding_amount directly instead of
--    recomputing (this was the direct cause of "Owes Rs 280" showing on a
--    customer whose real outstanding_amount was already 0).
-- ----------------------------------------------------------------------------
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
        (select sum(o.outstanding_amount)
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

grant execute on function public.get_vendor_customers(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. get_customer_total_outstanding — same fix.
-- ----------------------------------------------------------------------------
create or replace function public.get_customer_total_outstanding(
  p_customer_profile_id uuid,
  p_vendor_id uuid
)
returns numeric
language sql
stable
security definer
as $$
  select coalesce(sum(o.outstanding_amount), 0)
  from public.orders o
  where o.customer_profile_id = p_customer_profile_id
    and o.vendor_id = p_vendor_id
    and o.status not in ('cancelled','rejected');
$$;

grant execute on function public.get_customer_total_outstanding(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. collect_pending_payment — FIFO order selection and the "remaining
--    debt" summary must also key off outstanding_amount directly, not a
--    recompute that can't see refund-driven forgiveness. This also drops
--    the redundant `or payment_status in ('pending','partial')` clause,
--    which could select an order for debt collection purely because its
--    payment_status was stale, even though its real outstanding_amount was
--    already 0 — i.e. a rider could otherwise be prompted to collect money
--    on a debt that no longer exists.
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
      and outstanding_amount > 0
    order by created_at asc
    for update
  loop
    exit when v_remaining_payment <= 0;

    v_outstanding_before := coalesce(v_order_rec.outstanding_amount, 0);

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
  select coalesce(sum(outstanding_amount), 0) into v_total_debt_remaining
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
