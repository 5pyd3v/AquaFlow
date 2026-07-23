-- ============================================================================
-- AquaFlow — Consolidated Schema: Tables
--
-- GENERATED REFERENCE — see README.md. Base is migration 0001, with every
-- later `alter table ... add column` folded in, and every table dropped by
-- 0017 (and never recreated) excluded. See README.md for the full
-- excluded-tables list. payment_amendment_requests.review_notes/
-- reviewed_by/updated_at were a confirmed live bug (missing columns a
-- live function depended on) fixed by migration 0029 during review — see
-- that table's own comment below and README.md for details.
-- ============================================================================
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PROFILES (1:1 with auth.users) — 0001
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  phone text not null default '',
  role user_role not null default 'customer',
  avatar_url text,
  fcm_token text,
  is_verified boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- VENDORS — 0001, minus company_id (dropped 0017 with the companies table),
-- plus lat/lng (0005). business_name NOT NULL dropped in 0008.
-- ----------------------------------------------------------------------------
create table if not exists public.vendors (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  business_name text,
  business_license_url text,
  status vendor_status not null default 'pending',
  rating numeric(2,1) not null default 5.0 check (rating >= 0 and rating <= 5),
  total_orders integer not null default 0,
  location geography(Point, 4326),
  address text,
  delivery_radius_km numeric(5,2) not null default 8.0,
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id)
);

-- ----------------------------------------------------------------------------
-- RIDERS — 0001, plus lat/lng (0005)
-- ----------------------------------------------------------------------------
create table if not exists public.riders (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  vendor_id uuid references public.vendors(id) on delete set null,
  vehicle_type text,
  vehicle_plate text,
  license_url text,
  status rider_status not null default 'offline',
  rating numeric(2,1) not null default 5.0 check (rating >= 0 and rating <= 5),
  total_deliveries integer not null default 0,
  current_location geography(Point, 4326),
  is_on_shift boolean not null default false,
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id)
);

-- ----------------------------------------------------------------------------
-- CUSTOMERS — 0001, plus vendor_id + pin (0016)
-- ----------------------------------------------------------------------------
create table if not exists public.customers (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  referral_code text unique,
  referred_by uuid references public.profiles(id),
  loyalty_points integer not null default 0,
  vendor_id uuid references public.vendors(id) on delete set null,
  pin varchar(6),
  created_at timestamptz not null default now(),
  unique (profile_id)
);

-- ----------------------------------------------------------------------------
-- CATEGORIES & PRODUCTS — 0001, unchanged
-- ----------------------------------------------------------------------------
create table if not exists public.categories (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  icon_name text,
  sort_order integer not null default 0,
  is_active boolean not null default true
);

create table if not exists public.products (
  id uuid primary key default uuid_generate_v4(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  brand text,
  size_liters numeric(5,2) not null,
  description text,
  image_url text,
  price numeric(10,2) not null check (price >= 0),
  deposit_amount numeric(10,2) not null default 0 check (deposit_amount >= 0),
  discount_percent numeric(4,1) not null default 0,
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  average_delivery_minutes integer not null default 45,
  rating numeric(2,1) not null default 5.0,
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- INVENTORY — 0001, unchanged
-- ----------------------------------------------------------------------------
create table if not exists public.inventory (
  id uuid primary key default uuid_generate_v4(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  warehouse_name text not null default 'Main Warehouse',
  quantity_full integer not null default 0,
  quantity_empty_returned integer not null default 0,
  low_stock_threshold integer not null default 20,
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- ADDRESSES — 0001, plus lat/lng (0005)
-- ----------------------------------------------------------------------------
create table if not exists public.addresses (
  id uuid primary key default uuid_generate_v4(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  label address_label not null default 'home',
  full_address text not null,
  location geography(Point, 4326) not null,
  landmark text,
  is_default boolean not null default false,
  lat double precision,
  lng double precision,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- COUPONS — 0001, unchanged
-- ----------------------------------------------------------------------------
create table if not exists public.coupons (
  id uuid primary key default uuid_generate_v4(),
  code text not null unique,
  description text,
  discount_percent numeric(4,1),
  discount_flat numeric(10,2),
  min_order_amount numeric(10,2) not null default 0,
  max_uses integer,
  used_count integer not null default 0,
  valid_from timestamptz not null default now(),
  valid_until timestamptz not null,
  is_active boolean not null default true
);

-- ----------------------------------------------------------------------------
-- ORDERS — 0001, plus amount_paid / outstanding_amount / credit_applied (0024)
-- ----------------------------------------------------------------------------
create table if not exists public.orders (
  id uuid primary key default uuid_generate_v4(),
  order_number text not null unique,
  customer_profile_id uuid not null references public.profiles(id),
  vendor_id uuid references public.vendors(id),
  rider_id uuid references public.riders(id),
  address_id uuid not null references public.addresses(id),
  status order_status not null default 'pending',
  is_emergency boolean not null default false,
  is_subscription_order boolean not null default false,
  subtotal numeric(10,2) not null default 0,
  deposit_total numeric(10,2) not null default 0,
  discount_amount numeric(10,2) not null default 0,
  delivery_fee numeric(10,2) not null default 0,
  total_amount numeric(10,2) not null default 0,
  coupon_id uuid references public.coupons(id),
  payment_method payment_method not null default 'cod',
  payment_status payment_status not null default 'pending',
  scheduled_for timestamptz,
  delivered_at timestamptz,
  cancelled_reason text,
  rider_otp text,
  customer_signature_url text,
  delivery_photo_url text,
  amount_paid numeric(12,0) not null default 0,
  outstanding_amount numeric(12,0) not null default 0,
  credit_applied numeric(12,0) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(10,2) not null,
  unit_deposit numeric(10,2) not null default 0
);

-- ----------------------------------------------------------------------------
-- WALLETS & TRANSACTIONS — 0001, unchanged
-- ----------------------------------------------------------------------------
create table if not exists public.wallets (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  balance numeric(10,2) not null default 0,
  updated_at timestamptz not null default now(),
  unique (profile_id)
);

create table if not exists public.wallet_transactions (
  id uuid primary key default uuid_generate_v4(),
  wallet_id uuid not null references public.wallets(id) on delete cascade,
  order_id uuid references public.orders(id),
  amount numeric(10,2) not null,
  type text not null check (type in ('credit', 'debit')),
  description text,
  created_at timestamptz not null default now()
);

-- Legacy generic gateway-transaction table (Stripe/Razorpay/etc placeholder).
-- Distinct from payment_transactions (0024), which is the live COD/cash
-- payment ledger actually used by the app today. Kept because nothing ever
-- dropped it.
create table if not exists public.transactions (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id),
  amount numeric(10,2) not null,
  method payment_method not null,
  status payment_status not null default 'pending',
  gateway_reference text,
  raw_response jsonb,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- RATINGS & REVIEWS — 0001, unchanged (uniqueness indexes in 02_indexes.sql)
-- ----------------------------------------------------------------------------
create table if not exists public.ratings (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id),
  rater_profile_id uuid not null references public.profiles(id),
  rated_profile_id uuid references public.profiles(id),
  rated_vendor_id uuid references public.vendors(id),
  rated_rider_id uuid references public.riders(id),
  stars integer not null check (stars between 1 and 5),
  review text,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- FAVORITES — 0001, unchanged
-- ----------------------------------------------------------------------------
create table if not exists public.favorites (
  id uuid primary key default uuid_generate_v4(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid references public.products(id) on delete cascade,
  vendor_id uuid references public.vendors(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (product_id is not null or vendor_id is not null)
);

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS — dropped in 0017, restored verbatim by 0020 (final version)
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

-- ----------------------------------------------------------------------------
-- REALTIME LOCATIONS & TRACKING LOGS — 0001, plus lat/lng (0005)
-- ----------------------------------------------------------------------------
create table if not exists public.realtime_locations (
  rider_id uuid primary key references public.riders(id) on delete cascade,
  location geography(Point, 4326) not null,
  heading numeric(6,2),
  speed_kmh numeric(6,2),
  lat double precision,
  lng double precision,
  updated_at timestamptz not null default now()
);

create table if not exists public.tracking_logs (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status order_status not null,
  location geography(Point, 4326),
  note text,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- SETTINGS, AUDIT LOGS — 0001, unchanged
-- ----------------------------------------------------------------------------
create table if not exists public.settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default uuid_generate_v4(),
  actor_profile_id uuid references public.profiles(id),
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- COD SETTLEMENTS — 0015, plus reconciliation columns (0024)
-- ----------------------------------------------------------------------------
create table if not exists public.cod_settlements (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.riders(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  code text not null unique,
  status text not null default 'pending' check (status in ('pending', 'verified', 'expired')),
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  expires_at timestamptz not null default (now() + interval '24 hours'),
  order_count int not null default 0,
  transaction_count int not null default 0,
  outstanding_remaining numeric(12,0),
  total_cash_collected numeric(12,0),
  total_cash_settled numeric(12,0),
  cash_difference numeric(12,0),
  verified_notes text,
  generated_by uuid references public.profiles(id),
  verified_by uuid references public.profiles(id)
);

-- ----------------------------------------------------------------------------
-- PAYMENT_TRANSACTIONS — 0024, plus refunds_transaction_id (0027)
-- ----------------------------------------------------------------------------
create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  rider_id uuid references public.riders(id) on delete set null,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  amount numeric(12,0) not null check (amount >= 0),
  outstanding_before numeric(12,0) not null default 0,
  outstanding_after numeric(12,0) not null default 0,
  credit_before numeric(12,0) not null default 0,
  credit_after numeric(12,0) not null default 0,
  payment_type text not null check (payment_type in ('full','partial','over','credit','refund','adjustment')),
  status text not null default 'active' check (status in ('active','edited','deleted')),
  settled boolean not null default false,
  settlement_id uuid references public.cod_settlements(id) on delete set null,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  refunds_transaction_id uuid references public.payment_transactions(id) on delete set null
);

-- ----------------------------------------------------------------------------
-- PAYMENT_RECEIPTS — 0024, unchanged
-- ----------------------------------------------------------------------------
create table if not exists public.payment_receipts (
  id uuid primary key default gen_random_uuid(),
  payment_transaction_id uuid not null references public.payment_transactions(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  receipt_type text not null default 'cash'
    check (receipt_type in ('cash','bank_transfer','signature','delivery_proof','other')),
  receipt_url text not null,
  image_hash text,
  gps_lat numeric,
  gps_lng numeric,
  device_time timestamptz,
  uploaded_at timestamptz not null default now(),
  uploaded_by uuid references public.profiles(id)
);

-- ----------------------------------------------------------------------------
-- PAYMENT_AUDIT_LOGS — 0024, with the widened action CHECK from 0026 folded
-- into the base CREATE (originally 6 values; 0026 added refund /
-- collect_pending / apply_credit).
-- ----------------------------------------------------------------------------
create table if not exists public.payment_audit_logs (
  id uuid primary key default gen_random_uuid(),
  payment_transaction_id uuid references public.payment_transactions(id) on delete set null,
  action text not null check (action in ('create','edit','delete','amend_request','amend_approve','amend_reject','refund','collect_pending','apply_credit')),
  old_amount numeric(12,0),
  new_amount numeric(12,0),
  reason text,
  performed_by uuid references public.profiles(id),
  performed_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- PAYMENT_AMENDMENT_REQUESTS — 0024, with the widened requested_action CHECK
-- from 0025 folded in (originally 'edit'/'delete'; 0025 added 'refund').
--
-- FIXED by migration 0029 (was a live bug, not just a doc gap): the
-- resolve_payment_amendment() function started writing
--   `review_notes`, `reviewed_by`, `updated_at`
-- in migration 0026, but no migration before 0029 ever added those
-- columns — so on a database that only had 0001-0028 applied, every
-- single vendor approve/reject call would fail with an undefined-column
-- error. 0029 adds the three missing columns AND updates the function to
-- also keep setting resolved_at/resolved_by, so the existing Dart client
-- (which reads resolved_at) keeps working unchanged.
-- ----------------------------------------------------------------------------
create table if not exists public.payment_amendment_requests (
  id uuid primary key default gen_random_uuid(),
  payment_transaction_id uuid not null references public.payment_transactions(id) on delete cascade,
  rider_id uuid references public.riders(id) on delete set null,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  requested_action text not null check (requested_action in ('edit','delete','refund')),
  requested_amount numeric(12,0),
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id),
  -- added by migration 0029 (fixes a live bug: resolve_payment_amendment
  -- started writing these in 0026 with no ALTER TABLE ever adding them)
  review_notes text,
  reviewed_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- CUSTOMER_ACCOUNT_STATEMENTS — 0024, unchanged
-- ----------------------------------------------------------------------------
create table if not exists public.customer_account_statements (
  id uuid primary key default gen_random_uuid(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  opening_balance numeric(12,0) not null default 0,
  total_purchases numeric(12,0) not null default 0,
  total_paid numeric(12,0) not null default 0,
  total_credits numeric(12,0) not null default 0,
  total_refunds numeric(12,0) not null default 0,
  closing_balance numeric(12,0) not null default 0,
  generated_at timestamptz not null default now(),
  statement_url text,
  unique (customer_profile_id, vendor_id, period_start)
);
