# AquaFlow — Consolidated Schema (generated reference)

**Generated:** 2026-07-23, refreshed 2026-07-31
**Source:** mechanical extraction from `supabase/migrations/0001` through
`0031` (31 files, ~7,230 lines), all committed to `main`.

## What this is

A clean, deduplicated snapshot of the **final, currently-live** state of
every database object, expressed as a set of idempotent SQL files that could
recreate the current schema from scratch on an empty database.

**This is NOT a migration to run against the live database** — the live
database already has this exact schema, built up incrementally by the 28
migrations. This directory exists purely as a readable reference so you
don't have to mentally replay 28 files (many of which redefine the same
function 2-4 times) to answer "what does `process_refund` actually do
today?"

Every statement here (`create table if not exists`, `create or replace
function`, `drop policy if exists` + `create policy`, `create index if not
exists`) is idempotent, so this file set happens to also be safe to run
against the live database without erroring — but that is a side effect of
being a careful reference, not its purpose.

**`supabase/migrations/` remains the sole authoritative historical record.**
It was not touched, reordered, or deleted in any way to produce this
directory. At least one migration is known to have been run directly
against production before being committed to git, so the migrations
directory — not this one — is the source of truth for "what actually
happened to the database, in what order."

## File structure

| File | Contents |
|---|---|
| `00_extensions_and_types.sql` | Extensions (`uuid-ossp`, `postgis`, `pgcrypto`) + enum types |
| `01_tables.sql` | All tables, base + every later `alter table add column` folded in |
| `02_indexes.sql` | All indexes, including ones added by later migrations |
| `03_functions.sql` | One `create or replace function` per distinct function name (51 total) — final body only |
| `04_triggers.sql` | All triggers (20 total), final `create trigger` definition per name |
| `05_rls_policies.sql` | All RLS policies, final `create policy` definition per (table, name) |
| `06_storage_and_realtime.sql` | Storage buckets/policies + `supabase_realtime` publication membership |
| `07_grants.sql` | All `grant execute on function ... to authenticated/anon` statements |

Run in numeric order on an empty database to build the schema from scratch.

## Counts

- **Tables:** 27 (see exclusions below)
- **Functions:** 52 (`03_functions.sql` has exactly one `create or replace
  function public.X` per distinct name — verified by grep, no duplicates).
  Adds `reset_customer_pin` (0031) on top of the original 51.
- **Triggers:** 20
- **RLS policies:** 55 across 27 tables (all policy names are globally
  unique — verified no two tables reuse the same policy name)
- **Storage policies:** 10 (9 original + `delivery_proofs_public_read` added later)
- **Grants:** 35 `grant execute` statements (17 more functions — mostly
  trigger functions plus the four RLS helper functions — rely on Postgres's
  default PUBLIC execute privilege instead, since nothing ever revoked it)

## Excluded objects (dropped and never recreated)

**Tables** (dropped by migration `0017_cleanup_unused.sql`, never recreated):
`subscriptions`, `invoices`, `chats`, `messages`, `deposits`,
`bottle_returns`, `delivery_zones`, `companies`, and `subscription_items`
(child of `subscriptions`; see "Uncertainties" below — its exclusion is not
as clean-cut as the others).

**Columns:** `vendors.company_id` (dropped in 0017 along with the `companies`
table it referenced).

**Enum types** (dropped in 0017, never recreated): `subscription_frequency`,
`subscription_status`, `bottle_return_status`.

**Table exception — notifications:** `public.notifications` and the
`notification_type` enum WERE dropped in 0017, but migration
`0020_restore_notifications.sql` recreates both (0017 broke the
`notify_order_status_change` trigger, which still inserted into
`notifications` unconditionally — plpgsql resolves table names at runtime,
so the drop didn't fail loudly, it just broke order placement). Both are
therefore included, using 0020's definition.

**Realtime:** `public.messages` was added to the `supabase_realtime`
publication in migration 0012, but the `messages` table itself was dropped
in 0017 and never recreated — omitted from `06_storage_and_realtime.sql`.

## Superseded function versions (used the LAST one only)

| Function | Versions found | Used |
|---|---|---|
| `handle_new_auth_user` | 0003, 0008, 0014, 0016 | 0016 |
| `ensure_role_subrow` | 0008, 0014 | 0014 |
| `get_vendor_customers` | 0022, 0023, 0025, 0027 | 0027 |
| `create_pin_customer` | 0018, 0019, 0030 | 0030 |
| `create_email_user` | 0018, 0019, 0030 | 0030 |
| `process_refund` | 0025, 0026, 0027 | 0027 |
| `resolve_payment_amendment` | 0024, 0025, 0026, 0027, 0029 | 0029 |
| `get_rider_cod_balance` | 0015, 0026, 0027 | 0027 |
| `get_customer_ledger` | 0024, 0026, 0027 | 0027 |
| `get_vendor_finance_kpis` | 0024, 0026, 0027, 0028 | 0028 |
| `edit_payment` | 0024, 0027 | 0027 |
| `delete_payment` | 0024, 0027 | 0027 |
| `collect_pending_payment` | 0026, 0027 | 0027 |
| `get_customer_total_outstanding` | 0025, 0027 | 0027 |
| `verify_cod_settlement` | 0015, 0024 | 0024 |
| `generate_cod_settlement` | 0015, 0024 | 0024 |

Every other function (35 of the 51) was defined exactly once. `03_functions.sql`
carries an inline comment on every function noting its version history.

## Superseded / inline-modified RLS policies (used the LAST definition)

- `vendors_select_all` — 0002 (scoped to approved/own/admin) → **0026**
  (`using (true)`, unconditional read for all authenticated users).
- `notifications_owner_only` — 0002 → **0020** (identical clause; the table
  was dropped and restored in between, so the policy was necessarily
  recreated).
- `delivery_proofs_public_read` — new policy added by 0026 alongside the
  bucket's `public` flag flip; the older `delivery_proofs_participants_read`
  (0004) was never dropped and still coexists (both are additive — RLS
  `select` policies are OR'd together).

Every other named policy was defined exactly once.

## Uncertainties / flagged for review

These are explicit judgment calls made during extraction — please verify
against the live database before treating this as gospel for anything
payments-related:

1. **`payment_amendment_requests.review_notes` / `.reviewed_by` /
   `.updated_at` — CONFIRMED as a real, live bug and fixed during review.**
   The final `resolve_payment_amendment()` body (introduced in migration
   0026) executed
   ```sql
   update public.payment_amendment_requests
     set status = 'approved', review_notes = p_review_notes,
         reviewed_by = auth.uid(), updated_at = now()
     where id = v_req.id;
   ```
   against three columns that migration `0024_payment_management.sql` (the
   table's only `CREATE TABLE`) never defines, and no migration from
   0025-0028 added via `ALTER TABLE` either — this was independently
   verified against the migration source (not inferred) by tracing every
   version of the function and the table's DDL. Since this write runs
   unconditionally on every approve/reject call, if a database only had
   migrations through 0028 applied, **every single vendor amendment
   approval or rejection would fail** with an undefined-column error.
   Additionally, the function stopped populating `resolved_at`/`resolved_by`
   after 0026, which the Dart client (`payment_amendment_model.dart`) reads
   to display when a request was resolved — so even once the missing-column
   error was fixed, that field would have silently gone stale.
   **Fixed by a new migration, `0029_payment_amendment_missing_columns_fix.sql`**:
   adds the three missing columns, and updates the function to set both the
   new columns and `resolved_at`/`resolved_by`, so the existing Dart client
   needs zero changes. This consolidated reference reflects the 0029 state.
2. **`subscription_items` exclusion is inferred, not explicit.**
   `0017_cleanup_unused.sql` drops `subscriptions` with `CASCADE`, but
   `CASCADE` on `DROP TABLE` only cascades to dependent *objects* (e.g. the
   foreign-key constraint on `subscription_items.subscription_id`) — it does
   **not** drop `subscription_items` itself, which has no other migration
   ever dropping it either. Strictly by migration text, `subscription_items`
   likely still exists in the live database today as an orphaned, FK-less,
   permanently-empty table (nothing in the app ever wrote to it, and its
   only parent table is gone). It is excluded here as dead weight consistent
   with the rest of the abandoned subscriptions feature, but if a mechanical
   "does this exact object exist in the live DB" audit is run, expect this
   one table to be a discrepancy — that's a gap in migration hygiene, not in
   this extraction.

3. **`get_vendor_cod_summary` and the four RLS helper functions
   (`current_role`, `is_admin`, `owns_vendor`, `owns_rider`) never receive an
   explicit `grant execute`.** They are callable today only because Postgres
   grants `EXECUTE` to `PUBLIC` by default at function-creation time and
   nothing ever issued a `REVOKE`. This is almost certainly intentional /
   working-as-is in production, but is called out because it means
   `07_grants.sql` is not a complete list of "who can call what" — some of
   that authority comes from Postgres defaults, not an explicit grant.

4. **Enum-type recreation is guarded with `do $$ ... if not exists $$`
   blocks** rather than 0001's plain `create type`, since plain `create type`
   is not idempotent in Postgres (no `if not exists` variant exists for
   types) and the task requires every statement here to be safely re-runnable.
   The enum *values* are copied verbatim; only the existence-guard wrapper is
   new.

5. **`0030_fix_gotrue_null_columns.sql`'s one-time data-repair `update
   auth.users set ... where ... is null` statements are intentionally
   excluded.** They repair rows that already existed with NULL token/boolean
   columns on a live database — meaningless on the empty database this
   reference is meant to bootstrap (there are no rows yet to repair). Only
   the migration's *schema* changes (the redefined `create_email_user` /
   `create_pin_customer`, which now write those columns correctly for every
   newly-created row) are carried into `03_functions.sql`.

No other ambiguities were found — every other function, policy, trigger, and
table version was unambiguous by "highest migration number wins."

## Changes since initial generation (refreshed 2026-07-31)

The directory was originally generated through migration `0028`. It has
since been updated in place — not regenerated from scratch — to fold in
three later migrations:

- **`0029_payment_amendment_missing_columns_fix.sql`** — already covered by
  the original generation (see Uncertainty #1 above); no further change
  needed.
- **`0030_fix_gotrue_null_columns.sql`** — `create_pin_customer` and
  `create_email_user` in `03_functions.sql` updated to the 0030 bodies,
  which detect (`information_schema.columns`) and set `is_sso_user` /
  `is_anonymous` on newer GoTrue installs. Function signatures are
  unchanged, so `07_grants.sql` needed no update for these two.
- **`0031_vendor_reset_customer_pin.sql`** — new function
  `reset_customer_pin(uuid, uuid, text)` added to `03_functions.sql` (under
  "VENDOR CUSTOMERS") plus its `grant execute` in `07_grants.sql`. Lets a
  vendor regenerate the login PIN for one of their own customers.

No table, index, trigger, RLS policy, storage, or type changes were
introduced by 0029-0031 beyond what's listed above (verified by grepping
each migration for `alter table` / `create policy` / `create index` /
`create trigger` / `create type`).
