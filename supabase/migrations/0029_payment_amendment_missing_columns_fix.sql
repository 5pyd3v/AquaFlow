-- ============================================================================
-- AquaFlow — Migration 0029: payment_amendment_requests Missing Columns Fix
--
-- BUG (predates this session's fixes — introduced in 0026, before 0027):
-- resolve_payment_amendment() writes `review_notes`, `reviewed_by`, and
-- `updated_at` on every approve/reject call, but no migration ever added
-- those columns to payment_amendment_requests — only `resolved_at` and
-- `resolved_by` exist (from 0024). Since this write happens unconditionally
-- on every call, if these columns don't already exist on the live database,
-- a vendor could never approve or reject ANY amendment request — the RPC
-- would fail with "column review_notes does not exist" every single time.
--
-- Also: the Dart client (payment_amendment_model.dart) reads `resolved_at`
-- to show when a request was resolved, but the current function only sets
-- `updated_at`, so that field would silently stop populating even once the
-- missing-column error above is fixed. This migration adds the missing
-- columns AND makes the function set both the old and new column pairs, so
-- existing UI keeps working with zero Dart changes.
-- ============================================================================

alter table public.payment_amendment_requests
  add column if not exists review_notes text;
alter table public.payment_amendment_requests
  add column if not exists reviewed_by uuid references public.profiles(id);
alter table public.payment_amendment_requests
  add column if not exists updated_at timestamptz not null default now();

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
      -- either — see process_refund's header comment (migration 0027) for why.
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
      set status = 'approved',
          review_notes = p_review_notes, reviewed_by = auth.uid(), updated_at = now(),
          resolved_at = now(), resolved_by = auth.uid()
      where id = v_req.id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_approve', v_txn.amount, coalesce(v_req.requested_amount, 0), v_req.reason, auth.uid());

  else
    update public.payment_amendment_requests
      set status = 'rejected',
          review_notes = p_review_notes, reviewed_by = auth.uid(), updated_at = now(),
          resolved_at = now(), resolved_by = auth.uid()
      where id = v_req.id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_reject', v_txn.amount, v_txn.amount, p_review_notes, auth.uid());
  end if;

  return json_build_object('success', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end;
$$;

grant execute on function public.resolve_payment_amendment(uuid, bool, text) to authenticated;
