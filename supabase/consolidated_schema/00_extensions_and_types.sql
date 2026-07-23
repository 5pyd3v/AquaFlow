-- ============================================================================
-- AquaFlow — Consolidated Schema: Extensions & Enum Types
--
-- GENERATED REFERENCE — see README.md in this directory. Mechanically
-- extracted from supabase/migrations/0001..0028; NOT a migration to run
-- against the live database (which already has this schema). Every
-- statement is idempotent so it is nonetheless safe to run on a fresh,
-- empty database or re-run against the live one.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Extensions
-- ----------------------------------------------------------------------------
create extension if not exists "uuid-ossp";
create extension if not exists postgis;

-- pgcrypto is required for crypt()/gen_salt() used by create_pin_customer /
-- create_email_user (migration 0018). Installed into the `extensions`
-- schema, matching the Supabase convention used in 0018/0019.
create extension if not exists pgcrypto with schema extensions;

-- ----------------------------------------------------------------------------
-- Enum types (from 0001)
--
-- Excluded (dropped in 0017, never recreated — their owning tables were
-- also dropped and never recreated):
--   subscription_frequency, subscription_status, bottle_return_status
--
-- notification_type WAS dropped in 0017 but IS recreated in 0020 (its
-- owning table, notifications, was also restored there) — so it survives
-- and is included below, guarded exactly as 0020 guards it.
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type public.user_role as enum ('customer', 'vendor', 'rider', 'admin', 'super_admin');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'order_status') then
    create type public.order_status as enum (
      'pending', 'accepted', 'assigned', 'picked_up', 'on_the_way',
      'delivered', 'returned', 'completed', 'cancelled', 'rejected'
    );
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'payment_method') then
    create type public.payment_method as enum ('cod', 'wallet', 'stripe', 'razorpay', 'easypaisa', 'jazzcash');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'payment_status') then
    create type public.payment_status as enum ('pending', 'paid', 'failed', 'refunded');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'vendor_status') then
    create type public.vendor_status as enum ('pending', 'approved', 'suspended', 'rejected');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'rider_status') then
    create type public.rider_status as enum ('offline', 'available', 'on_delivery', 'suspended');
  end if;
end$$;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'address_label') then
    create type public.address_label as enum ('home', 'office', 'other');
  end if;
end$$;

-- notification_type — recreated by migration 0020 after 0017 dropped it;
-- guarded exactly as 0020 guards it.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type public.notification_type as enum (
      'order_update', 'new_order', 'rider_assigned', 'promo', 'system', 'chat'
    );
  end if;
end$$;
