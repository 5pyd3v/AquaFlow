-- ============================================================================
-- AquaFlow — Core Schema (Migration 0001)
-- Water bottle distribution platform: Customer / Vendor / Rider / Admin
-- ============================================================================

create extension if not exists "uuid-ossp";
create extension if not exists postgis;

-- ----------------------------------------------------------------------------
-- ENUMS
-- ----------------------------------------------------------------------------
create type user_role as enum ('customer', 'vendor', 'rider', 'admin', 'super_admin');

create type order_status as enum (
  'pending', 'accepted', 'assigned', 'picked_up', 'on_the_way',
  'delivered', 'returned', 'completed', 'cancelled', 'rejected'
);

create type payment_method as enum ('cod', 'wallet', 'stripe', 'razorpay', 'easypaisa', 'jazzcash');
create type payment_status as enum ('pending', 'paid', 'failed', 'refunded');
create type subscription_frequency as enum ('weekly', 'monthly');
create type subscription_status as enum ('active', 'paused', 'cancelled');
create type vendor_status as enum ('pending', 'approved', 'suspended', 'rejected');
create type rider_status as enum ('offline', 'available', 'on_delivery', 'suspended');
create type notification_type as enum (
  'order_update', 'new_order', 'rider_assigned', 'promo', 'system', 'chat'
);
create type address_label as enum ('home', 'office', 'other');
create type bottle_return_status as enum ('requested', 'scheduled', 'collected', 'refunded');

-- ----------------------------------------------------------------------------
-- PROFILES (1:1 with auth.users)
-- ----------------------------------------------------------------------------
create table public.profiles (
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

create index idx_profiles_role on public.profiles(role);
create index idx_profiles_phone on public.profiles(phone);

-- ----------------------------------------------------------------------------
-- COMPANIES (top-level tenant; supports multi-company / white-label future)
-- ----------------------------------------------------------------------------
create table public.companies (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  logo_url text,
  contact_email text,
  contact_phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- VENDORS
-- ----------------------------------------------------------------------------
create table public.vendors (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  business_name text not null,
  business_license_url text,
  status vendor_status not null default 'pending',
  rating numeric(2,1) not null default 5.0 check (rating >= 0 and rating <= 5),
  total_orders integer not null default 0,
  location geography(Point, 4326),
  address text,
  delivery_radius_km numeric(5,2) not null default 8.0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id)
);

create index idx_vendors_status on public.vendors(status);
create index idx_vendors_location on public.vendors using gist(location);

-- ----------------------------------------------------------------------------
-- RIDERS
-- ----------------------------------------------------------------------------
create table public.riders (
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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id)
);

create index idx_riders_status on public.riders(status);
create index idx_riders_vendor on public.riders(vendor_id);
create index idx_riders_location on public.riders using gist(current_location);

-- ----------------------------------------------------------------------------
-- CUSTOMERS (extends profile with commerce-specific fields)
-- ----------------------------------------------------------------------------
create table public.customers (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  referral_code text unique,
  referred_by uuid references public.profiles(id),
  loyalty_points integer not null default 0,
  created_at timestamptz not null default now(),
  unique (profile_id)
);

-- ----------------------------------------------------------------------------
-- CATEGORIES & PRODUCTS
-- ----------------------------------------------------------------------------
create table public.categories (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  icon_name text,
  sort_order integer not null default 0,
  is_active boolean not null default true
);

create table public.products (
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

create index idx_products_vendor on public.products(vendor_id);
create index idx_products_category on public.products(category_id);
create index idx_products_available on public.products(is_available);

-- ----------------------------------------------------------------------------
-- INVENTORY (warehouse-level stock ledger, separate from product-level stock)
-- ----------------------------------------------------------------------------
create table public.inventory (
  id uuid primary key default uuid_generate_v4(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  warehouse_name text not null default 'Main Warehouse',
  quantity_full integer not null default 0,
  quantity_empty_returned integer not null default 0,
  low_stock_threshold integer not null default 20,
  updated_at timestamptz not null default now()
);

create index idx_inventory_vendor on public.inventory(vendor_id);

-- ----------------------------------------------------------------------------
-- ADDRESSES
-- ----------------------------------------------------------------------------
create table public.addresses (
  id uuid primary key default uuid_generate_v4(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  label address_label not null default 'home',
  full_address text not null,
  location geography(Point, 4326) not null,
  landmark text,
  is_default boolean not null default false,
  created_at timestamptz not null default now()
);

create index idx_addresses_customer on public.addresses(customer_profile_id);
create index idx_addresses_location on public.addresses using gist(location);

-- ----------------------------------------------------------------------------
-- DELIVERY ZONES
-- ----------------------------------------------------------------------------
create table public.delivery_zones (
  id uuid primary key default uuid_generate_v4(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  name text not null,
  boundary geography(Polygon, 4326) not null,
  is_active boolean not null default true
);

create index idx_delivery_zones_vendor on public.delivery_zones(vendor_id);
create index idx_delivery_zones_boundary on public.delivery_zones using gist(boundary);

-- ----------------------------------------------------------------------------
-- COUPONS
-- ----------------------------------------------------------------------------
create table public.coupons (
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
-- ORDERS
-- ----------------------------------------------------------------------------
create table public.orders (
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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_orders_customer on public.orders(customer_profile_id);
create index idx_orders_vendor on public.orders(vendor_id);
create index idx_orders_rider on public.orders(rider_id);
create index idx_orders_status on public.orders(status);
create index idx_orders_created_at on public.orders(created_at desc);

create table public.order_items (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(10,2) not null,
  unit_deposit numeric(10,2) not null default 0
);

create index idx_order_items_order on public.order_items(order_id);

-- ----------------------------------------------------------------------------
-- SUBSCRIPTIONS
-- ----------------------------------------------------------------------------
create table public.subscriptions (
  id uuid primary key default uuid_generate_v4(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id),
  address_id uuid not null references public.addresses(id),
  frequency subscription_frequency not null,
  status subscription_status not null default 'active',
  next_delivery_date date not null,
  preferred_time_slot text,
  created_at timestamptz not null default now()
);

create table public.subscription_items (
  id uuid primary key default uuid_generate_v4(),
  subscription_id uuid not null references public.subscriptions(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0)
);

-- ----------------------------------------------------------------------------
-- BOTTLE RETURNS / DEPOSITS
-- ----------------------------------------------------------------------------
create table public.deposits (
  id uuid primary key default uuid_generate_v4(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id),
  order_id uuid references public.orders(id),
  bottles_held integer not null default 0,
  amount_held numeric(10,2) not null default 0,
  updated_at timestamptz not null default now()
);

create table public.bottle_returns (
  id uuid primary key default uuid_generate_v4(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  order_id uuid references public.orders(id),
  rider_id uuid references public.riders(id),
  bottles_count integer not null check (bottles_count > 0),
  status bottle_return_status not null default 'requested',
  refund_amount numeric(10,2) not null default 0,
  requested_at timestamptz not null default now(),
  collected_at timestamptz
);

-- ----------------------------------------------------------------------------
-- WALLETS & TRANSACTIONS
-- ----------------------------------------------------------------------------
create table public.wallets (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  balance numeric(10,2) not null default 0,
  updated_at timestamptz not null default now(),
  unique (profile_id)
);

create table public.wallet_transactions (
  id uuid primary key default uuid_generate_v4(),
  wallet_id uuid not null references public.wallets(id) on delete cascade,
  order_id uuid references public.orders(id),
  amount numeric(10,2) not null,
  type text not null check (type in ('credit', 'debit')),
  description text,
  created_at timestamptz not null default now()
);

create table public.transactions (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id),
  amount numeric(10,2) not null,
  method payment_method not null,
  status payment_status not null default 'pending',
  gateway_reference text,
  raw_response jsonb,
  created_at timestamptz not null default now()
);

create index idx_transactions_order on public.transactions(order_id);

-- ----------------------------------------------------------------------------
-- INVOICES
-- ----------------------------------------------------------------------------
create table public.invoices (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id),
  invoice_number text not null unique,
  pdf_url text,
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- RATINGS & REVIEWS
-- ----------------------------------------------------------------------------
create table public.ratings (
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

create index idx_ratings_vendor on public.ratings(rated_vendor_id);
create index idx_ratings_rider on public.ratings(rated_rider_id);

-- ----------------------------------------------------------------------------
-- FAVORITES
-- ----------------------------------------------------------------------------
create table public.favorites (
  id uuid primary key default uuid_generate_v4(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid references public.products(id) on delete cascade,
  vendor_id uuid references public.vendors(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (product_id is not null or vendor_id is not null)
);

create unique index idx_favorites_unique_product on public.favorites(customer_profile_id, product_id) where product_id is not null;
create unique index idx_favorites_unique_vendor on public.favorites(customer_profile_id, vendor_id) where vendor_id is not null;

-- ----------------------------------------------------------------------------
-- CHATS & MESSAGES
-- ----------------------------------------------------------------------------
create table public.chats (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid references public.orders(id),
  participant_one uuid not null references public.profiles(id),
  participant_two uuid not null references public.profiles(id),
  last_message text,
  last_message_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.messages (
  id uuid primary key default uuid_generate_v4(),
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_profile_id uuid not null references public.profiles(id),
  content text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index idx_messages_chat on public.messages(chat_id);

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS
-- ----------------------------------------------------------------------------
create table public.notifications (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  type notification_type not null,
  title text not null,
  body text not null,
  data jsonb,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index idx_notifications_profile on public.notifications(profile_id, is_read);

-- ----------------------------------------------------------------------------
-- REALTIME LOCATIONS & TRACKING LOGS
-- ----------------------------------------------------------------------------
create table public.realtime_locations (
  rider_id uuid primary key references public.riders(id) on delete cascade,
  location geography(Point, 4326) not null,
  heading numeric(6,2),
  speed_kmh numeric(6,2),
  updated_at timestamptz not null default now()
);

create table public.tracking_logs (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status order_status not null,
  location geography(Point, 4326),
  note text,
  created_at timestamptz not null default now()
);

create index idx_tracking_logs_order on public.tracking_logs(order_id);

-- ----------------------------------------------------------------------------
-- SETTINGS, AUDIT LOGS
-- ----------------------------------------------------------------------------
create table public.settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default uuid_generate_v4(),
  actor_profile_id uuid references public.profiles(id),
  action text not null,
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index idx_audit_logs_actor on public.audit_logs(actor_profile_id);
