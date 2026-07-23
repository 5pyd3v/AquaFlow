-- ============================================================================
-- AquaFlow — Consolidated Schema: Triggers
--
-- GENERATED REFERENCE — see README.md. Every trigger, matched by name, using
-- the LAST definition (drop + recreate) across the migration history. All
-- functions referenced here are defined in 03_functions.sql.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Generic updated_at bumpers (0003)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists trg_vendors_updated_at on public.vendors;
create trigger trg_vendors_updated_at before update on public.vendors
  for each row execute function public.set_updated_at();

drop trigger if exists trg_riders_updated_at on public.riders;
create trigger trg_riders_updated_at before update on public.riders
  for each row execute function public.set_updated_at();

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at before update on public.orders
  for each row execute function public.set_updated_at();

drop trigger if exists trg_inventory_updated_at on public.inventory;
create trigger trg_inventory_updated_at before update on public.inventory
  for each row execute function public.set_updated_at();

drop trigger if exists trg_wallets_updated_at on public.wallets;
create trigger trg_wallets_updated_at before update on public.wallets
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- auth.users -> profiles (final recreate: 0016, via 0003 -> 0014 -> 0016)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ----------------------------------------------------------------------------
-- profiles.role -> ensure matching sub-row (final recreate: 0014)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_profiles_ensure_subrow on public.profiles;
create trigger trg_profiles_ensure_subrow
  after insert or update of role on public.profiles
  for each row execute function public.ensure_role_subrow();

-- ----------------------------------------------------------------------------
-- Orders (0003)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_orders_generate_number on public.orders;
create trigger trg_orders_generate_number
  before insert on public.orders
  for each row execute function public.generate_order_number();

drop trigger if exists trg_orders_log_status on public.orders;
create trigger trg_orders_log_status
  after insert or update of status on public.orders
  for each row execute function public.log_order_status_change();

drop trigger if exists trg_orders_notify on public.orders;
create trigger trg_orders_notify
  after insert or update of status on public.orders
  for each row execute function public.notify_order_status_change();

-- ----------------------------------------------------------------------------
-- Delivery OTP (0010)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_orders_generate_delivery_otp on public.orders;
create trigger trg_orders_generate_delivery_otp
  before update of rider_id on public.orders
  for each row execute function public.generate_delivery_otp();

-- ----------------------------------------------------------------------------
-- Zero outstanding on cancel/reject (0026)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_orders_zero_outstanding_on_cancel on public.orders;
create trigger trg_orders_zero_outstanding_on_cancel
  before insert or update on public.orders
  for each row
  execute function public.zero_outstanding_on_cancel();

-- ----------------------------------------------------------------------------
-- Realtime locations (0003 + 0005)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_realtime_locations_sync on public.realtime_locations;
create trigger trg_realtime_locations_sync
  after insert or update on public.realtime_locations
  for each row execute function public.sync_rider_location();

-- Keep geography(Point,4326) columns in sync with the plain lat/lng doubles
-- the Flutter client writes (0005).
drop trigger if exists trg_addresses_sync_location on public.addresses;
create trigger trg_addresses_sync_location
  before insert or update of lat, lng on public.addresses
  for each row execute function public.sync_lat_lng_to_geography();

drop trigger if exists trg_vendors_sync_location on public.vendors;
create trigger trg_vendors_sync_location
  before insert or update of lat, lng on public.vendors
  for each row execute function public.sync_lat_lng_to_geography();

drop trigger if exists trg_riders_sync_location on public.riders;
create trigger trg_riders_sync_location
  before insert or update of lat, lng on public.riders
  for each row execute function public.sync_lat_lng_to_geography();

drop trigger if exists trg_realtime_locations_sync_location on public.realtime_locations;
create trigger trg_realtime_locations_sync_location
  before insert or update of lat, lng on public.realtime_locations
  for each row execute function public.sync_lat_lng_to_geography();

-- ----------------------------------------------------------------------------
-- Ratings aggregation (0013)
-- ----------------------------------------------------------------------------
drop trigger if exists trg_ratings_aggregate on public.ratings;
create trigger trg_ratings_aggregate
  after insert or update or delete on public.ratings
  for each row execute function public.recompute_rating_aggregates();
