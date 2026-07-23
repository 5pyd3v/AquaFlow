-- ============================================================================
-- AquaFlow — Migration 0028: Awaiting-Settlement Refund Netting Fix
--
-- Follow-up to 0027. That migration made refunds purely additive (the
-- original payment_transactions row is never mutated anymore) and fixed
-- every "collected cash" total to explicitly subtract 'refund' rows again
-- — EXCEPT one spot inside get_vendor_finance_kpis: v_awaiting_settlement.
-- It still summed 'full'/'partial'/'over' with no refund subtraction, so
-- it kept counting cash that had already been refunded/reallocated as
-- still "awaiting settlement" — e.g. showing Rs 560 owed on the vendor
-- finance dashboard when the true unsettled amount was Rs 280.
-- ============================================================================
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

  -- FIX: refund rows are always settled = false (verify_cod_settlement only
  -- ever flips 'full'/'partial'/'over' rows to settled), so they must be
  -- subtracted here explicitly or refunded cash keeps showing as "awaiting
  -- settlement" forever.
  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0)
  into v_awaiting_settlement
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active' and settled = false
    and payment_type in ('full', 'partial', 'over', 'refund');

  return json_build_object(
    'todays_collection', greatest(v_todays_collection, 0),
    'months_collection', greatest(v_months_collection, 0),
    'pending_collection', v_pending_collection,
    'outstanding_customers', v_outstanding_customers,
    'credits_issued', v_credits_issued,
    'refunds', v_refunds,
    'partial_count', v_partial_count,
    'awaiting_settlement', greatest(v_awaiting_settlement, 0)
  );
end;
$$;

grant execute on function public.get_vendor_finance_kpis(uuid) to authenticated;
