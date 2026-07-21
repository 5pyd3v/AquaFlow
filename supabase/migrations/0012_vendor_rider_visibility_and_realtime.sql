-- ============================================================================
-- AquaFlow — Vendor rider-location visibility + Realtime replication (Migration 0012)
--
-- Two separate gaps closed here:
--
-- 1. RLS gap: `realtime_locations_relevant` (0002) lets the rider
--    themselves, an admin, or the customer of an active order read a
--    rider's live location — but never the vendor who employs that
--    rider. The vendor's live rider map has nothing to read without
--    this.
--
-- 2. Realtime replication gap: Supabase only streams `postgres_changes`
--    for tables explicitly added to the `supabase_realtime` publication
--    (via Dashboard → Database → Replication, or SQL, as done here).
--    Every `.stream()` call in this codebase — order tracking AND the
--    new rider-location map — has been silently non-realtime without
--    this; the initial fetch works, but no live updates ever arrive,
--    and it fails completely silently (no error, just nothing happens).
-- ============================================================================

create policy "realtime_locations_visible_to_vendor"
  on public.realtime_locations for select
  using (
    exists (
      select 1 from public.riders r
      where r.id = realtime_locations.rider_id
        and public.owns_vendor(r.vendor_id)
    )
  );

-- Enable live streaming for every table this app subscribes to via
-- `.stream()`. Safe to run more than once — Postgres raises a notice
-- (not an error) if a table is already in the publication, but we
-- guard with a check anyway for a clean re-run.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'realtime_locations'
  ) then
    alter publication supabase_realtime add table public.realtime_locations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;
