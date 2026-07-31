-- ============================================================================
-- AquaFlow — Fix Rider Cash Reconciliation (Migration 0032)
--
-- Two confirmed bugs in the vendor "cash held by riders" reporting:
--
-- 1. get_vendor_rider_cash_positions' `collected` figure never subtracted
--    refunds, unlike its sibling get_rider_cod_balance (fixed in 0027) and
--    get_vendor_finance_kpis (fixed in 0028). Same rider, same day, two
--    vendor screens showing two different "amount collected" numbers.
--    Fixed by netting 'refund' payment_transactions rows the same way the
--    other two functions do, and adding an `outstanding` field
--    (collected - settled, floor 0) so the vendor dashboard can finally
--    show the true "cash still on the road" figure its own caption
--    already promises instead of the unrelated pending-settlement-code sum.
--
-- 2. verify_cod_settlement flipped EVERY currently-unsettled payment
--    transaction to settled=true whenever a rider's settlement code was
--    verified — regardless of whether the settled amount actually covered
--    them. A rider submitting a partial cash amount (the "Submit Cash"
--    screen explicitly allows less than the full outstanding balance)
--    would silently have their ENTIRE unsettled balance marked settled and
--    tagged against that one settlement, corrupting the settlement detail
--    audit trail and permanently hiding the uncovered remainder from any
--    future settlement's "collected since last settlement" snapshot.
--    Fixed by only flipping the oldest transactions that are fully covered
--    by the verified amount (whole-transaction units — there's no partial-
--    settled amount on a single row), leaving the rest correctly unsettled
--    for the next settlement.
-- ============================================================================

create or replace function public.get_vendor_rider_cash_positions(p_vendor_id uuid)
returns json[]
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid;
  v_results json[];
begin
  select id into v_caller from public.vendors where id = p_vendor_id and profile_id = auth.uid();
  if v_caller is null then
    raise exception 'Not authorized';
  end if;

  select array_agg(row_to_json(x)) into v_results from (
    select
      r.id as rider_id,
      p.full_name as rider_name,
      coalesce((
        select sum(case when t.payment_type = 'refund' then -t.amount else t.amount end)
        from public.payment_transactions t
        where t.rider_id = r.id and t.vendor_id = p_vendor_id and t.status = 'active'
          and t.payment_type in ('full', 'partial', 'over', 'refund')
      ), 0) as collected,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status = 'verified'
      ), 0) as settled,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status = 'pending'
      ), 0) as pending_settlement,
      greatest(
        coalesce((
          select sum(case when t.payment_type = 'refund' then -t.amount else t.amount end)
          from public.payment_transactions t
          where t.rider_id = r.id and t.vendor_id = p_vendor_id and t.status = 'active'
            and t.payment_type in ('full', 'partial', 'over', 'refund')
        ), 0)
        -
        coalesce((
          select sum(s.amount) from public.cod_settlements s
          where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status = 'verified'
        ), 0),
        0
      ) as outstanding
    from public.riders r
    join public.profiles p on p.id = r.profile_id
    where r.vendor_id = p_vendor_id
  ) x;

  return coalesce(v_results, '{}');
end;
$$;

create or replace function public.verify_cod_settlement(
  p_code text,
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_settlement record;
  v_rider_name text;
  v_outstanding_before numeric;
  v_outstanding_after numeric;
  v_txn_count int;
  v_order_count int;
  v_remaining numeric;
  v_txn record;
begin
  select * into v_settlement
  from public.cod_settlements
  where code = p_code and vendor_id = p_vendor_id and status = 'pending' and expires_at > now();

  if v_settlement is null then
    raise exception 'Invalid or expired settlement code' using errcode = 'P0001';
  end if;

  select coalesce(sum(amount), 0) into v_outstanding_before
  from public.cod_settlements
  where rider_id = v_settlement.rider_id and vendor_id = p_vendor_id and status = 'pending';

  -- Only flip the oldest transactions that are FULLY covered by the
  -- verified amount — never mark more as settled than was actually
  -- handed over. A single row has no "partially settled" state, so any
  -- transaction the remaining amount can't fully cover is left untouched
  -- for the next settlement.
  v_remaining := v_settlement.amount;
  for v_txn in
    select id, amount from public.payment_transactions
    where rider_id = v_settlement.rider_id and vendor_id = p_vendor_id
      and status = 'active' and settled = false
      and payment_type in ('full', 'partial', 'over')
    order by created_at asc
    for update
  loop
    exit when v_remaining < v_txn.amount;
    update public.payment_transactions
      set settled = true, settlement_id = v_settlement.id, updated_at = now()
      where id = v_txn.id;
    v_remaining := v_remaining - v_txn.amount;
  end loop;

  select count(*), count(distinct order_id) into v_txn_count, v_order_count
  from public.payment_transactions where settlement_id = v_settlement.id;

  update public.cod_settlements
  set status = 'verified',
      verified_at = now(),
      verified_by = auth.uid(),
      transaction_count = coalesce(v_txn_count,0),
      order_count = coalesce(v_order_count,0),
      total_cash_settled = v_settlement.amount,
      cash_difference = coalesce(total_cash_collected,0) - v_settlement.amount,
      outstanding_remaining = greatest(v_outstanding_before - v_settlement.amount, 0)
  where id = v_settlement.id;

  v_outstanding_after := v_outstanding_before - v_settlement.amount;

  select p.full_name into v_rider_name
  from public.riders r join public.profiles p on p.id = r.profile_id
  where r.id = v_settlement.rider_id;

  return json_build_object(
    'settlement_id', v_settlement.id,
    'rider_name', coalesce(v_rider_name, 'Unknown Rider'),
    'amount', v_settlement.amount,
    'created_at', v_settlement.created_at,
    'outstanding_before', v_outstanding_before,
    'outstanding_after', v_outstanding_after
  );
end;
$$;
