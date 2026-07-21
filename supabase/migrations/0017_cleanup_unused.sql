-- ============================================================================
-- AquaFlow — Supabase Cleanup (Migration 0017)
--
-- Drops unused tables, their RLS policies, triggers, indexes, and
-- associated functions/constraints that the app never references.
-- These were designed for future features that haven't been built.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Drop unused tables (CASCADE removes policies, indexes, triggers)
-- ----------------------------------------------------------------------------

drop table if exists public.subscriptions cascade;
drop table if exists public.invoices cascade;
drop table if exists public.chats cascade;
drop table if exists public.messages cascade;
drop table if exists public.notifications cascade;
drop table if exists public.deposits cascade;
drop table if exists public.bottle_returns cascade;
drop table if exists public.delivery_zones cascade;
drop table if exists public.companies cascade;

-- ----------------------------------------------------------------------------
-- 2. Drop unused enums
-- ----------------------------------------------------------------------------

drop type if exists public.subscription_frequency cascade;
drop type if exists public.subscription_status cascade;
drop type if exists public.notification_type cascade;
drop type if exists public.bottle_return_status cascade;

-- ----------------------------------------------------------------------------
-- 3. Remove unused constants from companies FK on vendors
--    (already handled by CASCADE above, but ensure the column is gone)
-- ----------------------------------------------------------------------------

alter table public.vendors drop column if exists company_id;

-- ----------------------------------------------------------------------------
-- 4. Remove address_label enum if never used in code
-- ----------------------------------------------------------------------------
-- Keeping: address_label IS used by the addresses feature in the app.
