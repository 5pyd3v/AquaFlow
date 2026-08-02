-- ============================================================================
-- AquaFlow — Reject Refund-of-a-Refund (Migration 0035)
--
-- BUG: process_refund never checked the payment_type of the transaction
-- being refunded. Since a fresh 'refund' row is itself status='active' and
-- settled=false (refunds are never settled — see migration 0028's comment
-- on get_vendor_finance_kpis), a rider who tapped "Refund" on their OWN
-- refund record would sail straight through every existing guard
-- (status='active', same rider, not settled) and the RPC would create a
-- refund-of-a-refund: a second 'refund' row linked via
-- refunds_transaction_id back to the first refund, netting out as
-- yet more negative cash and silently re-crediting/re-debiting amounts in a
-- way nothing downstream (get_rider_cod_balance, get_vendor_finance_kpis,
-- the customer ledger) was ever designed to interpret.
--
-- This was reachable from the app: rider_order_detail_screen.dart's
-- payment-history list showed the refund action button on every row where
-- `isEditable` was true, and `isEditable` only checked
-- `status == active && !settled` — it never excluded `type == refund`. Any
-- refund the rider hadn't yet had settled by the vendor displayed its own
-- "Refund" arrow.
--
-- Fixed at both layers: this migration adds a hard server-side guard (so no
-- future UI entry point can bypass it either), and the Flutter client
-- separately stops rendering the button on refund rows.
-- ============================================================================

create or replace function public.process_refund(
  p_transaction_id uuid,
  p_amount numeric,
  p_reason text
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
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
  if v_txn.payment_type = 'refund' then
    raise exception 'A refund cannot itself be refunded';
  end if;

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
