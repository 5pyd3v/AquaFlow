-- ============================================================================
-- AquaFlow — Balance Sheet Invariants (READ-ONLY)
--
-- Safe to run against production: it only SELECTs. Every row it returns is
-- a violation of an accounting rule that should never be breakable. A clean
-- run returns `status = 'PASS'` for every check.
--
-- Run in the Supabase SQL editor, or:
--   psql "$DATABASE_URL" -f supabase/tests/01_balance_sheet_invariants.sql
-- ============================================================================

with

-- INV-1 — Order identity: every non-cancelled order must satisfy
--   total = paid + credit_applied + outstanding.
-- Orders carrying a refund are excluded: process_refund deliberately
-- forgives the remaining debt (sets outstanding to 0), which breaks the
-- identity by design.
inv_order_identity as (
  select count(*) as violations
  from public.orders o
  where o.status not in ('cancelled', 'rejected')
    and round(coalesce(o.total_amount, 0))
        <> coalesce(o.amount_paid, 0) + coalesce(o.credit_applied, 0) + coalesce(o.outstanding_amount, 0)
    and not exists (
      select 1 from public.payment_transactions t
      where t.order_id = o.id and t.payment_type = 'refund' and t.status = 'active'
    )
),

-- INV-2 — No negative money anywhere.
inv_no_negatives as (
  select
    (select count(*) from public.orders where coalesce(outstanding_amount, 0) < 0)
  + (select count(*) from public.orders where coalesce(amount_paid, 0) < 0)
  + (select count(*) from public.wallets where coalesce(balance, 0) < 0)
  + (select count(*) from public.payment_transactions where amount < 0)
    as violations
),

-- INV-3 — A rider can never have settled more cash than they collected.
-- (collected is net of refunds, matching get_rider_cod_balance.)
inv_rider_oversettled as (
  select count(*) as violations
  from (
    select
      r.id,
      coalesce((
        select sum(case when t.payment_type = 'refund' then -t.amount else t.amount end)
        from public.payment_transactions t
        where t.rider_id = r.id and t.vendor_id = r.vendor_id and t.status = 'active'
          and t.payment_type in ('full', 'partial', 'over', 'refund')
      ), 0) as collected,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = r.vendor_id and s.status = 'verified'
      ), 0) as settled
    from public.riders r
    where r.vendor_id is not null
  ) q
  where q.settled > q.collected
),

-- INV-4 — Settlement tagging integrity: no transaction may be tagged to a
-- settlement that was never verified.
inv_settlement_tagging as (
  select count(*) as violations
  from public.payment_transactions t
  join public.cod_settlements s on s.id = t.settlement_id
  where t.settlement_id is not null and s.status <> 'verified'
),

-- INV-5 — A settled transaction must carry the settlement that settled it.
inv_settled_flag as (
  select count(*) as violations
  from public.payment_transactions
  where settled = true and settlement_id is null
),

-- INV-6 — Wallet balance must equal the sum of its own ledger.
inv_wallet_ledger as (
  select count(*) as violations
  from public.wallets w
  where round(coalesce(w.balance, 0), 2) <> round(coalesce((
    select sum(case when wt.type = 'debit' then -wt.amount else wt.amount end)
    from public.wallet_transactions wt where wt.wallet_id = w.id
  ), 0), 2)
),

-- INV-7 — Unsettled cash must be RIDER-held only. Any unsettled active
-- payment with no rider attached would leak into "cash on the road" under
-- the pre-0033 KPI. Post-0033 the KPI joins through riders so these are
-- already excluded; this reports them so you can see whether any exist.
info_riderless_unsettled as (
  select count(*) as violations
  from public.payment_transactions
  where status = 'active' and settled = false and rider_id is null
    and payment_type in ('full', 'partial', 'over')
),

-- INV-8 — Per-order cash tie-out: an order's amount_paid should equal the
-- payments booked against it, net of refunds. 'over' rows are excluded —
-- they represent wallet credit, not money applied to the order.
-- NOTE: pre-0033 rows stored the whole tendered amount (including the
-- excess) on the primary row, so historical orders that were overpaid will
-- legitimately appear here. Treat a non-zero count as INFO unless the
-- orders listed were created after migration 0033 was applied.
info_order_cash_tie as (
  select count(*) as violations
  from public.orders o
  where o.status not in ('cancelled', 'rejected')
    and exists (select 1 from public.payment_transactions t where t.order_id = o.id and t.status = 'active')
    and coalesce(o.amount_paid, 0) <> coalesce((
      select sum(case
                   when t.payment_type = 'refund' then -t.amount
                   when t.payment_type = 'over' then 0
                   else t.amount
                 end)
      from public.payment_transactions t
      where t.order_id = o.id and t.status = 'active'
        and t.payment_type in ('full', 'partial', 'over', 'refund')
    ), 0)
)

select check_id, severity, description, violations,
       case when violations = 0 then 'PASS' else 'FAIL' end as status
from (
  select 'INV-1' as check_id, 'ERROR' as severity,
         'Order identity: total = paid + credit_applied + outstanding' as description,
         violations from inv_order_identity
  union all
  select 'INV-2', 'ERROR', 'No negative balances, payments or outstanding', violations from inv_no_negatives
  union all
  select 'INV-3', 'ERROR', 'No rider has settled more than they collected', violations from inv_rider_oversettled
  union all
  select 'INV-4', 'ERROR', 'No transaction tagged to an unverified settlement', violations from inv_settlement_tagging
  union all
  select 'INV-5', 'ERROR', 'Every settled transaction carries a settlement_id', violations from inv_settled_flag
  union all
  select 'INV-6', 'ERROR', 'Wallet balance equals its transaction ledger', violations from inv_wallet_ledger
  union all
  select 'INV-7', 'INFO', 'Unsettled payments with no rider attached (excluded from rider cash by 0033)', violations from info_riderless_unsettled
  union all
  select 'INV-8', 'INFO', 'Per-order cash tie-out (pre-0033 overpaid orders expected to flag)', violations from info_order_cash_tie
) checks
order by
  case when violations > 0 and severity = 'ERROR' then 0
       when violations > 0 then 1
       else 2 end,
  check_id;
