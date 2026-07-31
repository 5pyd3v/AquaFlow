-- ============================================================================
-- AquaFlow — Finance Accounting Correctness (Migration 0033)
--
-- Establishes one consistent accounting model across the whole finance
-- section, so the vendor's balance sheet actually tallies:
--
--   SALES        = cash actually collected, net of refunds. An order of
--                  Rs. 2000 where the customer hands over Rs. 1500 is
--                  Rs. 1500 of sales + Rs. 500 of debt. When a rider later
--                  collects that Rs. 500, it becomes Rs. 500 more sales.
--   DEBT         = orders.outstanding_amount (money owed to the vendor).
--   UNSETTLED    = cash physically held by RIDERS = (what the rider
--                  collected, net of refunds) − (what the vendor has
--                  verified receiving). Nothing else may appear here.
--   CREDIT       = only genuine excess, i.e. money left over after every
--                  outstanding debt the customer has is cleared.
--
-- Three fixes:
--
-- 1. complete_delivery_with_payment — overpayment used to go straight to
--    wallet credit even when the customer still owed money on other
--    orders. Now the excess FIFO-clears their other outstanding orders
--    first (oldest first) and only the true leftover becomes credit.
--
--    Cash-integrity note: each rupee tendered is now recorded by EXACTLY
--    ONE payment_transactions row. Previously the primary row stored the
--    full tendered amount; had we simply added reallocation rows on top,
--    the same cash would have been counted twice in every collection
--    total. Instead the tendered amount is now split across rows:
--      - the primary row  = amount applied to THIS order
--      - one row per other order the excess cleared
--      - one 'over' row   = the true leftover credited to the wallet
--    so SUM(rows) == amount tendered, and each row is attributed to the
--    order it actually paid. This also repairs `credits_issued`, which
--    was summing the whole tendered amount of every 'over' payment
--    instead of just the credited excess.
--
-- 2. get_vendor_finance_kpis —
--      * adds `total_sales` (lifetime net cash collected);
--      * `refunds` was missing a `status = 'active'` filter, so deleted
--        refunds still inflated the figure;
--      * `credits_issued` now derives from the wallet delta recorded on
--        each row (credit_after − credit_before), which is correct for
--        both pre-0033 and post-0033 rows;
--      * `awaiting_settlement` was summing EVERY unsettled transaction
--        for the vendor with no rider filter — money never held by a
--        rider (rider_id null) counted as "cash on the road", and it read
--        the `settled` boolean, which since 0032 deliberately lags on
--        partial settlements. It is now computed per rider as
--        (collected − verified settlements), floored at zero, which makes
--        it rider-held cash only and makes it tie exactly to the sum of
--        get_vendor_rider_cash_positions.outstanding.
--
-- 3. get_rider_cod_balance — the legacy fallback fired whenever the
--    transaction sum was <= 0, which now happens legitimately (a delivery
--    collecting Rs. 0 writes a zero-amount row). It would then report
--    phantom cash straight off the orders table. It now fires only when
--    the rider genuinely has no payment_transactions at all.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. complete_delivery_with_payment
-- ----------------------------------------------------------------------------

create or replace function public.complete_delivery_with_payment(
  p_order_id uuid,
  p_entered_otp text,
  p_amount numeric,
  p_receipt_url text default null,
  p_receipt_meta jsonb default '{}'::jsonb,
  p_notes text default null
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.orders;
  v_rider_profile_id uuid;
  v_outstanding numeric;
  v_credit_before numeric;
  v_credit_after numeric;
  v_applied numeric;          -- applied to THIS order
  v_excess numeric;           -- tendered beyond this order's outstanding
  v_remaining_excess numeric; -- excess still unallocated
  v_debt_cleared numeric := 0;
  v_pay_type text;
  v_txn_id uuid;
  v_amount numeric := round(coalesce(p_amount, 0));
  v_other record;
  v_apply numeric;
  v_other_before numeric;
  v_other_after numeric;
  v_other_txn_id uuid;
  v_order_number text;
begin
  -- Lock the order row to prevent double completion / races
  select o.* into v_order from public.orders o where o.id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_order.rider_id;
  if v_rider_profile_id is null or v_rider_profile_id != auth.uid() then
    raise exception 'You are not the assigned rider for this order';
  end if;

  if v_order.status = 'delivered' or v_order.status = 'completed' then
    raise exception 'This order has already been completed';
  end if;

  if v_order.status not in ('assigned','picked_up','on_the_way') then
    raise exception 'This order is not ready to be completed';
  end if;

  if v_order.rider_otp is distinct from p_entered_otp then
    raise exception 'Incorrect delivery code — ask the customer to confirm it';
  end if;

  if v_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  end if;

  v_outstanding := public.order_outstanding(p_order_id);
  v_applied := least(v_amount, v_outstanding);
  v_excess := greatest(v_amount - v_outstanding, 0);

  select coalesce(balance, 0) into v_credit_before
  from public.wallets where profile_id = v_order.customer_profile_id;
  v_credit_before := coalesce(v_credit_before, 0);

  -- Update this order: paid + delivered
  update public.orders
    set amount_paid = coalesce(amount_paid,0) + v_applied,
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - (coalesce(amount_paid,0) + v_applied) - coalesce(credit_applied,0), 0),
        payment_status = case
          when greatest(round(coalesce(total_amount,0)) - (coalesce(amount_paid,0) + v_applied) - coalesce(credit_applied,0), 0) = 0
            then 'paid'::payment_status
          else payment_status
        end,
        status = 'delivered',
        delivered_at = now(),
        updated_at = now()
    where id = p_order_id
    returning * into v_order;

  v_order_number := v_order.order_number;

  update public.riders set total_deliveries = total_deliveries + 1 where id = v_order.rider_id;

  -- Classify THIS order's payment. 'over' is no longer used here: genuine
  -- excess gets its own dedicated row further down.
  if v_amount = 0 then
    v_pay_type := 'partial';
  elsif v_applied >= v_outstanding then
    v_pay_type := 'full';
  else
    v_pay_type := 'partial';
  end if;

  -- Primary transaction — records ONLY what this order absorbed.
  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by
  ) values (
    p_order_id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_applied,
    v_outstanding, greatest(v_outstanding - v_applied, 0), v_credit_before, v_credit_before,
    v_pay_type, p_notes, auth.uid()
  ) returning id into v_txn_id;

  -- Excess clears the customer's OTHER outstanding orders first (FIFO).
  v_remaining_excess := v_excess;
  if v_remaining_excess > 0 then
    for v_other in
      select * from public.orders
      where customer_profile_id = v_order.customer_profile_id
        and vendor_id = v_order.vendor_id
        and id <> p_order_id
        and status not in ('cancelled', 'rejected')
        and coalesce(outstanding_amount, 0) > 0
      order by created_at asc
      for update
    loop
      exit when v_remaining_excess <= 0;

      v_other_before := coalesce(v_other.outstanding_amount, 0);
      v_apply := least(v_remaining_excess, v_other_before);
      v_other_after := greatest(v_other_before - v_apply, 0);

      update public.orders
        set amount_paid = coalesce(amount_paid, 0) + v_apply,
            outstanding_amount = v_other_after,
            payment_status = case when v_other_after = 0 then 'paid'::payment_status else 'partial'::payment_status end,
            updated_at = now()
        where id = v_other.id;

      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by
      ) values (
        v_other.id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_apply,
        v_other_before, v_other_after, v_credit_before, v_credit_before,
        'full',
        'Overpayment from order #' || coalesce(v_order_number, '') || ' applied to outstanding balance',
        auth.uid()
      ) returning id into v_other_txn_id;

      insert into public.payment_audit_logs (
        payment_transaction_id, action, old_amount, new_amount, reason, performed_by
      ) values (
        v_other_txn_id, 'collect_pending', v_other_before, v_other_after,
        'Debt cleared via overpayment reallocation', auth.uid()
      );

      v_debt_cleared := v_debt_cleared + v_apply;
      v_remaining_excess := v_remaining_excess - v_apply;
    end loop;
  end if;

  -- Only what survives every outstanding debt becomes wallet credit.
  if v_remaining_excess > 0 then
    perform public.adjust_wallet_balance(
      v_order.customer_profile_id, v_remaining_excess, 'credit', p_order_id, 'Overpayment credit'
    );
    v_credit_after := v_credit_before + v_remaining_excess;

    insert into public.payment_transactions (
      order_id, customer_profile_id, rider_id, vendor_id, amount,
      outstanding_before, outstanding_after, credit_before, credit_after,
      payment_type, notes, created_by
    ) values (
      p_order_id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_remaining_excess,
      0, 0, v_credit_before, v_credit_after,
      'over', 'Overpayment credited to wallet', auth.uid()
    );
  else
    v_credit_after := v_credit_before;
  end if;

  -- Optional receipt — attached to the primary delivery transaction.
  if p_receipt_url is not null and length(trim(p_receipt_url)) > 0 then
    insert into public.payment_receipts (
      payment_transaction_id, vendor_id, receipt_type, receipt_url,
      image_hash, gps_lat, gps_lng, device_time, uploaded_by
    ) values (
      v_txn_id, v_order.vendor_id,
      coalesce(p_receipt_meta->>'receipt_type', 'cash'),
      p_receipt_url,
      p_receipt_meta->>'image_hash',
      (p_receipt_meta->>'gps_lat')::numeric,
      (p_receipt_meta->>'gps_lng')::numeric,
      (p_receipt_meta->>'device_time')::timestamptz,
      auth.uid()
    );
  end if;

  insert into public.payment_audit_logs (payment_transaction_id, action, new_amount, reason, performed_by)
  values (v_txn_id, 'create', v_amount, 'Delivery payment collected', auth.uid());

  return json_build_object(
    'transaction_id', v_txn_id,
    'order_id', p_order_id,
    'amount', v_amount,
    'applied', v_applied,
    'debt_cleared', v_debt_cleared,
    'excess_credit', greatest(v_remaining_excess, 0),
    'outstanding_after', greatest(v_outstanding - v_applied, 0),
    'credit_after', v_credit_after,
    'payment_type', v_pay_type
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. get_vendor_finance_kpis
-- ----------------------------------------------------------------------------

create or replace function public.get_vendor_finance_kpis(p_vendor_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today_start timestamptz := date_trunc('day', now());
  v_month_start timestamptz := date_trunc('month', now());
  v_todays_collection numeric;
  v_months_collection numeric;
  v_total_sales numeric;
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

  -- Lifetime sales = every rupee actually collected, net of refunds.
  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0)
  into v_total_sales
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund');

  select coalesce(sum(outstanding_amount), 0) into v_pending_collection
  from public.orders where vendor_id = p_vendor_id and status not in ('cancelled', 'rejected');

  select count(distinct customer_profile_id) into v_outstanding_customers
  from public.orders where vendor_id = p_vendor_id and outstanding_amount > 0 and status not in ('cancelled', 'rejected');

  -- Credit actually issued = the wallet delta each row recorded, not the
  -- whole tendered amount of an over-payment (the pre-0033 bug).
  select coalesce(sum(greatest(coalesce(credit_after, 0) - coalesce(credit_before, 0), 0)), 0)
  into v_credits_issued
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active';

  select coalesce(sum(amount), 0) into v_refunds
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active' and payment_type = 'refund';

  select count(*) into v_partial_count
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active' and payment_type = 'partial';

  -- Cash still physically held by RIDERS: per rider, everything they
  -- collected (net of refunds) minus everything the vendor has verified
  -- receiving from them. Floored per rider so one rider's over-settlement
  -- can't mask another's shortfall. Ties exactly to the sum of
  -- get_vendor_rider_cash_positions.outstanding.
  select coalesce(sum(greatest(q.collected - q.settled, 0)), 0)
  into v_awaiting_settlement
  from (
    select
      coalesce((
        select sum(case when t.payment_type = 'refund' then -t.amount else t.amount end)
        from public.payment_transactions t
        where t.rider_id = r.id and t.vendor_id = p_vendor_id and t.status = 'active'
          and t.payment_type in ('full', 'partial', 'over', 'refund')
      ), 0) as collected,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status = 'verified'
      ), 0) as settled
    from public.riders r
    where r.vendor_id = p_vendor_id
  ) q;

  return json_build_object(
    'todays_collection', greatest(v_todays_collection, 0),
    'months_collection', greatest(v_months_collection, 0),
    'total_sales', greatest(v_total_sales, 0),
    'pending_collection', v_pending_collection,
    'outstanding_customers', v_outstanding_customers,
    'credits_issued', v_credits_issued,
    'refunds', v_refunds,
    'partial_count', v_partial_count,
    'awaiting_settlement', v_awaiting_settlement
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. get_rider_cod_balance
-- ----------------------------------------------------------------------------

create or replace function public.get_rider_cod_balance(
  p_rider_id uuid,
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_outstanding numeric := 0;
  v_pending numeric := 0;
  v_total_submitted numeric := 0;
  v_total_verified numeric := 0;
  v_total_collected numeric := 0;
begin
  select
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0),
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0),
    coalesce(sum(amount), 0),
    coalesce(sum(case when status = 'verified' then amount else 0 end), 0)
  into v_pending, v_outstanding, v_total_submitted, v_total_verified
  from public.cod_settlements
  where rider_id = p_rider_id and vendor_id = p_vendor_id;

  select coalesce(
    sum(case when payment_type = 'refund' then -amount else amount end), 0
  ) into v_total_collected
  from public.payment_transactions
  where rider_id = p_rider_id
    and vendor_id = p_vendor_id
    and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund');

  -- Legacy fallback for pre-payment-transactions data. Must key off the
  -- ABSENCE of transactions, not a <= 0 sum: a delivery that collected
  -- nothing legitimately writes a zero-amount row, and the old condition
  -- would then report phantom cash straight off the orders table.
  if not exists (
    select 1 from public.payment_transactions
    where rider_id = p_rider_id and vendor_id = p_vendor_id and status = 'active'
  ) then
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
