-- ============================================================================
-- AquaFlow — lat/lng convenience columns (Migration 0005)
--
-- PostgREST (Supabase's REST layer) can't easily return/accept PostGIS
-- geography values as plain floats over the auto-generated REST API,
-- and no Flutter client should be formatting WKB/GeoJSON by hand just
-- to save an address. So every table that stores a location accepts
-- plain `lat`/`lng` double columns from the client; a trigger keeps
-- the real `geography(Point,4326)` column in sync automatically so
-- spatial queries (nearest vendor, delivery zone containment, etc.)
-- still work exactly as before.
-- ============================================================================

alter table public.addresses add column if not exists lat double precision;
alter table public.addresses add column if not exists lng double precision;

alter table public.vendors add column if not exists lat double precision;
alter table public.vendors add column if not exists lng double precision;

alter table public.riders add column if not exists lat double precision;
alter table public.riders add column if not exists lng double precision;

alter table public.realtime_locations add column if not exists lat double precision;
alter table public.realtime_locations add column if not exists lng double precision;

create or replace function public.sync_lat_lng_to_geography()
returns trigger
language plpgsql
as $$
begin
  if new.lat is not null and new.lng is not null then
    if tg_table_name = 'addresses' then
      new.location := ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)::geography;
    elsif tg_table_name = 'vendors' then
      new.location := ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)::geography;
    elsif tg_table_name = 'riders' then
      new.current_location := ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)::geography;
    elsif tg_table_name = 'realtime_locations' then
      new.location := ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)::geography;
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_addresses_sync_location
  before insert or update of lat, lng on public.addresses
  for each row execute function public.sync_lat_lng_to_geography();

create trigger trg_vendors_sync_location
  before insert or update of lat, lng on public.vendors
  for each row execute function public.sync_lat_lng_to_geography();

create trigger trg_riders_sync_location
  before insert or update of lat, lng on public.riders
  for each row execute function public.sync_lat_lng_to_geography();

create trigger trg_realtime_locations_sync_location
  before insert or update of lat, lng on public.realtime_locations
  for each row execute function public.sync_lat_lng_to_geography();

-- Backfill lat/lng for any rows that already had a geography point
-- set directly (e.g. via the seed file) before this migration ran.
update public.addresses set lat = ST_Y(location::geometry), lng = ST_X(location::geometry)
  where location is not null and lat is null;
update public.vendors set lat = ST_Y(location::geometry), lng = ST_X(location::geometry)
  where location is not null and lat is null;
