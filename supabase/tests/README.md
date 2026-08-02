# AquaFlow — Finance Tests

Three independent layers guard the payments/finance logic. Run all three
after any change to a money-touching RPC.

| # | Layer | File | Safe on production? |
|---|---|---|---|
| 1 | Invariants (read-only) | `01_balance_sheet_invariants.sql` | Yes — SELECT only |
| 2 | Scenarios (end-to-end) | `02_finance_scenarios.sql` | Rolls back, but prefer staging |
| 3 | Client unit tests | `test/features/payments/finance_accounting_test.dart` | N/A |

## The accounting model being tested

Established by migration `0033_finance_accounting_correctness.sql`:

- **Sales** = cash actually collected, net of refunds. An Rs. 2000 order
  where the customer hands over Rs. 1500 books **Rs. 1500 of sales** and
  **Rs. 500 of debt**. When a rider later collects that Rs. 500, it becomes
  Rs. 500 more sales. Sales are never the order's face value.
- **Debt** = `orders.outstanding_amount` — what customers still owe.
- **Unsettled** = cash physically held by **riders only**:
  `collected (net of refunds) − verified settlements`, floored at zero per
  rider. Nothing without a `rider_id` may ever appear here.
- **Credit** = genuine excess only. An overpayment first clears every other
  outstanding order the customer has (oldest first); only what survives that
  becomes wallet credit.
- **Cash conservation** — every rupee tendered is recorded by exactly one
  `payment_transactions` row. The tendered amount is split across rows (the
  order it paid, each other order its excess cleared, and the wallet credit
  remainder) so totals can never double-count.

## 1. Invariants — read-only

```bash
psql "$DATABASE_URL" -f supabase/tests/01_balance_sheet_invariants.sql
```

Returns one row per check. A clean database shows `PASS` everywhere.

`ERROR` severity means a rule that should be unbreakable was broken —
investigate before shipping. `INFO` rows are expected to be non-zero on a
database with pre-0033 history:

- **INV-7** counts unsettled payments with no rider attached. These used to
  inflate "cash on the road"; 0033 excludes them. A non-zero count here is
  informational, not a failure.
- **INV-8** is the per-order cash tie-out. Pre-0033, an overpayment stored
  the *whole* tendered amount on the order's primary row, so historically
  overpaid orders will legitimately flag. Only treat it as a failure for
  orders created after 0033 was applied.

## 2. Scenarios — transactional

```bash
psql "$DATABASE_URL" -f supabase/tests/02_finance_scenarios.sql
```

Seeds an isolated vendor, three riders and four customers, drives the real
RPCs (`complete_delivery_with_payment`, `collect_pending_payment`,
`generate_cod_settlement`, `verify_cod_settlement`,
`get_vendor_finance_kpis`, `get_vendor_rider_cash_positions`,
`get_rider_cod_balance`) and asserts exact figures. Everything is rolled
back at the end.

Success prints `ALL FINANCE SCENARIOS PASSED`. Any failed assertion raises
and names the scenario.

| Scenario | Asserts |
|---|---|
| S1 | Rs. 2000 order, Rs. 1500 paid → 1500 sales, 500 debt |
| S2 | Collecting that 500 later moves it into sales |
| S3 | Collected 4000, settled 3500 → 3500 settled, 500 unsettled |
| S4 | Overpayment clears existing debt instead of becoming credit |
| S5 | True excess (no debt) becomes credit; the `over` row records only the excess |
| S6 | A payment with no rider does not move "unsettled" |
| S7 | KPI unsettled == sum of the per-rider cards |
| S8 | `total_sales` == summed cash, net of refunds |
| S9 | A **partial** pending-payment collection succeeds (regression, 0034) |
| S10 | Overpayment whose excess only **partly** covers other debt (regression, 0034) |
| S11 | A refund cannot itself be refunded (regression, 0035) |

S1, S4, S5 and S10 additionally assert **cash conservation** — that the
transaction rows sum to exactly what was tendered, catching any future
double-counting regression.

### Why S9 and S10 exist

The original S2 collected a debt in full and S4 cleared an old debt exactly,
so both took the `outstanding = 0 → 'paid'` branch and **never executed the
`else 'partial'` branch**. That blind spot let
`invalid input value for enum payment_status: "partial"` survive from
migration 0026 into production — the pending-payment module only ever worked
when a payment happened to clear the balance exactly.

**When adding a scenario, make sure it exercises the branch where money is
left over, not just the clean-settlement path.** Partial outcomes are where
the bugs live.

> The scenario file writes to `auth.users`, so it needs a role that can
> (the Supabase SQL editor's `postgres` role can). It rolls everything back.

## 3. Client unit tests

```bash
flutter test test/features/payments/
```

- `finance_accounting_test.dart` — KPI/cash-position parsing, rounding, the
  `sales + debt == order value` relationship, the KPI-to-rider-card tie-out,
  and graceful defaulting if the backend has not been migrated yet.
- `payment_transaction_entity_test.dart` — `isEditable` vs `isRefundable`
  (regression, 0035): a refund row is active+unsettled just like a normal
  payment, so `isEditable` alone lets its own "Refund" button render.
  `isRefundable` additionally excludes `type == refund` and is what the UI
  must gate on.
