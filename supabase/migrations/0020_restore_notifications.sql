-- ============================================================================
-- AquaFlow — Restore notifications table (Migration 0020)
--
-- Migration 0017 dropped public.notifications (and the notification_type
-- enum) as "unused". But the order triggers created in 0003
-- (notify_order_status_change) still INSERT into it on every order
-- placement / status change. Because plpgsql resolves table names at
-- runtime, the drop didn't fail — it just left the trigger broken, so
-- placing an order now errors with:
--   "relation public.notifications does not exist"
--
-- This migration recreates the enum, table, index, RLS policy, and
-- realtime publication exactly as they were in 0001/0002/0012 so the
-- notification triggers work again.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Enum
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type public.notification_type as enum (
      'order_update', 'new_order', 'rider_assigned', 'promo', 'system', 'chat'
    );
  end if;
end$$;

-- ----------------------------------------------------------------------------
-- 2. Table + index
-- ----------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  type public.notification_type not null,
  title text not null,
  body text not null,
  data jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_profile
  on public.notifications(profile_id, is_read);

-- ----------------------------------------------------------------------------
-- 3. Row level security — a profile can only see/manage its own rows
-- ----------------------------------------------------------------------------
alter table public.notifications enable row level security;

drop policy if exists "notifications_owner_only" on public.notifications;
create policy "notifications_owner_only"
  on public.notifications for all
  using (profile_id = auth.uid() or public.is_admin());

-- ----------------------------------------------------------------------------
-- 4. Realtime publication (mirrors 0012) so the client + webhook fan-out
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end$$;
