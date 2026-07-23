-- ============================================================================
-- AquaFlow — Consolidated Schema: Row Level Security Policies
--
-- GENERATED REFERENCE — see README.md. Deny by default; every policy below
-- is the LAST (drop + create) definition for that exact policy name across
-- the migration history. Tables belonging to dropped/superseded features
-- (companies, delivery_zones, subscriptions, subscription_items, deposits,
-- bottle_returns, invoices, chats, messages) have no RLS section here
-- because the tables themselves are excluded — see README.md.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PROFILES
-- ----------------------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (id = auth.uid());

drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin"
  on public.profiles for update
  using (id = auth.uid() or public.is_admin());

-- Order-scoped visibility (0007): customer <-> assigned vendor/rider.
drop policy if exists "profiles_visible_via_shared_order" on public.profiles;
create policy "profiles_visible_via_shared_order"
  on public.profiles for select
  using (
    exists (
      select 1 from public.orders o
      left join public.vendors v on v.id = o.vendor_id
      left join public.riders r on r.id = o.rider_id
      where (o.customer_profile_id = auth.uid() or v.profile_id = auth.uid() or r.profile_id = auth.uid())
        and (profiles.id = o.customer_profile_id or profiles.id = v.profile_id or profiles.id = r.profile_id)
    )
  );

-- Vendor may read the profile of any rider linked to their business (0022).
drop policy if exists "profiles_visible_to_owning_vendor" on public.profiles;
create policy "profiles_visible_to_owning_vendor"
  on public.profiles for select
  using (
    exists (
      select 1 from public.riders r
      where r.profile_id = profiles.id
        and public.owns_vendor(r.vendor_id)
    )
  );

-- ----------------------------------------------------------------------------
-- VENDORS
-- ----------------------------------------------------------------------------
alter table public.vendors enable row level security;

-- vendors_select_all — final version: 0026 widened to `using (true)` so
-- riders/customers can always read vendor profiles (originally restricted
-- to approved / own / admin in 0002).
drop policy if exists "vendors_select_all" on public.vendors;
create policy "vendors_select_all" on public.vendors
  for select using (true);

drop policy if exists "vendors_insert_own" on public.vendors;
create policy "vendors_insert_own"
  on public.vendors for insert
  with check (profile_id = auth.uid());

drop policy if exists "vendors_update_own_or_admin" on public.vendors;
create policy "vendors_update_own_or_admin"
  on public.vendors for update
  using (profile_id = auth.uid() or public.is_admin());

-- ----------------------------------------------------------------------------
-- RIDERS
-- ----------------------------------------------------------------------------
alter table public.riders enable row level security;

drop policy if exists "riders_select_relevant" on public.riders;
create policy "riders_select_relevant"
  on public.riders for select
  using (
    profile_id = auth.uid()
    or public.is_admin()
    or public.owns_vendor(vendor_id)
    or exists (
      select 1 from public.orders o
      where o.rider_id = riders.id and o.customer_profile_id = auth.uid()
    )
  );

drop policy if exists "riders_insert_own" on public.riders;
create policy "riders_insert_own"
  on public.riders for insert
  with check (profile_id = auth.uid());

drop policy if exists "riders_update_own_or_vendor_or_admin" on public.riders;
create policy "riders_update_own_or_vendor_or_admin"
  on public.riders for update
  using (profile_id = auth.uid() or public.owns_vendor(vendor_id) or public.is_admin());

-- ----------------------------------------------------------------------------
-- CUSTOMERS
-- ----------------------------------------------------------------------------
alter table public.customers enable row level security;

drop policy if exists "customers_select_own_or_admin" on public.customers;
create policy "customers_select_own_or_admin"
  on public.customers for select
  using (profile_id = auth.uid() or public.is_admin());

drop policy if exists "customers_insert_own" on public.customers;
create policy "customers_insert_own"
  on public.customers for insert
  with check (profile_id = auth.uid());

drop policy if exists "customers_update_own" on public.customers;
create policy "customers_update_own"
  on public.customers for update
  using (profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- CATEGORIES & PRODUCTS — public catalog, vendor-owned writes
-- ----------------------------------------------------------------------------
alter table public.categories enable row level security;

drop policy if exists "categories_select_all" on public.categories;
create policy "categories_select_all" on public.categories for select using (true);

drop policy if exists "categories_admin_write" on public.categories;
create policy "categories_admin_write" on public.categories for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.products enable row level security;

drop policy if exists "products_select_all" on public.products;
create policy "products_select_all"
  on public.products for select
  using (is_available or public.owns_vendor(vendor_id) or public.is_admin());

drop policy if exists "products_vendor_write" on public.products;
create policy "products_vendor_write"
  on public.products for all
  using (public.owns_vendor(vendor_id) or public.is_admin())
  with check (public.owns_vendor(vendor_id) or public.is_admin());

-- ----------------------------------------------------------------------------
-- INVENTORY — vendor-only
-- ----------------------------------------------------------------------------
alter table public.inventory enable row level security;

drop policy if exists "inventory_vendor_only" on public.inventory;
create policy "inventory_vendor_only"
  on public.inventory for all
  using (public.owns_vendor(vendor_id) or public.is_admin())
  with check (public.owns_vendor(vendor_id) or public.is_admin());

-- ----------------------------------------------------------------------------
-- ADDRESSES — customer owns their own, plus assigned rider/vendor read (0011)
-- ----------------------------------------------------------------------------
alter table public.addresses enable row level security;

drop policy if exists "addresses_owner_only" on public.addresses;
create policy "addresses_owner_only"
  on public.addresses for all
  using (customer_profile_id = auth.uid() or public.is_admin())
  with check (customer_profile_id = auth.uid());

drop policy if exists "addresses_visible_via_assigned_order" on public.addresses;
create policy "addresses_visible_via_assigned_order"
  on public.addresses for select
  using (
    exists (
      select 1 from public.orders o
      where o.address_id = addresses.id
        and (public.owns_rider(o.rider_id) or public.owns_vendor(o.vendor_id))
    )
  );

-- ----------------------------------------------------------------------------
-- COUPONS — publicly readable if active, admin managed
-- ----------------------------------------------------------------------------
alter table public.coupons enable row level security;

drop policy if exists "coupons_select_active" on public.coupons;
create policy "coupons_select_active" on public.coupons for select using (is_active or public.is_admin());

drop policy if exists "coupons_admin_write" on public.coupons;
create policy "coupons_admin_write" on public.coupons for all
  using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- ORDERS — the central authorization surface
-- ----------------------------------------------------------------------------
alter table public.orders enable row level security;

drop policy if exists "orders_select_participants" on public.orders;
create policy "orders_select_participants"
  on public.orders for select
  using (
    customer_profile_id = auth.uid()
    or public.owns_vendor(vendor_id)
    or public.owns_rider(rider_id)
    or public.is_admin()
  );

drop policy if exists "orders_insert_customer" on public.orders;
create policy "orders_insert_customer"
  on public.orders for insert
  with check (customer_profile_id = auth.uid());

drop policy if exists "orders_update_participants" on public.orders;
create policy "orders_update_participants"
  on public.orders for update
  using (
    customer_profile_id = auth.uid()
    or public.owns_vendor(vendor_id)
    or public.owns_rider(rider_id)
    or public.is_admin()
  );

-- ----------------------------------------------------------------------------
-- ORDER ITEMS — inherit access from parent order
-- ----------------------------------------------------------------------------
alter table public.order_items enable row level security;

drop policy if exists "order_items_via_order" on public.order_items;
create policy "order_items_via_order"
  on public.order_items for all
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and (
          o.customer_profile_id = auth.uid()
          or public.owns_vendor(o.vendor_id)
          or public.owns_rider(o.rider_id)
          or public.is_admin()
        )
    )
  )
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.customer_profile_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- WALLETS & TRANSACTIONS
-- ----------------------------------------------------------------------------
alter table public.wallets enable row level security;

drop policy if exists "wallets_owner_or_admin" on public.wallets;
create policy "wallets_owner_or_admin"
  on public.wallets for select
  using (profile_id = auth.uid() or public.is_admin());

alter table public.wallet_transactions enable row level security;

drop policy if exists "wallet_transactions_owner_or_admin" on public.wallet_transactions;
create policy "wallet_transactions_owner_or_admin"
  on public.wallet_transactions for select
  using (
    exists (
      select 1 from public.wallets w
      where w.id = wallet_transactions.wallet_id
        and (w.profile_id = auth.uid() or public.is_admin())
    )
  );

alter table public.transactions enable row level security;

drop policy if exists "transactions_via_order" on public.transactions;
create policy "transactions_via_order"
  on public.transactions for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = transactions.order_id
        and (o.customer_profile_id = auth.uid() or public.owns_vendor(o.vendor_id) or public.is_admin())
    )
  );

-- ----------------------------------------------------------------------------
-- RATINGS
-- ----------------------------------------------------------------------------
alter table public.ratings enable row level security;

drop policy if exists "ratings_select_all" on public.ratings;
create policy "ratings_select_all" on public.ratings for select using (true);

drop policy if exists "ratings_insert_rater" on public.ratings;
create policy "ratings_insert_rater"
  on public.ratings for insert
  with check (rater_profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- FAVORITES
-- ----------------------------------------------------------------------------
alter table public.favorites enable row level security;

drop policy if exists "favorites_owner_only" on public.favorites;
create policy "favorites_owner_only"
  on public.favorites for all
  using (customer_profile_id = auth.uid())
  with check (customer_profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS — final version: 0020 (restored after 0017 drop; identical
-- clause to the original 0002 definition)
-- ----------------------------------------------------------------------------
alter table public.notifications enable row level security;

drop policy if exists "notifications_owner_only" on public.notifications;
create policy "notifications_owner_only"
  on public.notifications for all
  using (profile_id = auth.uid() or public.is_admin());

-- ----------------------------------------------------------------------------
-- REALTIME LOCATIONS & TRACKING LOGS
-- ----------------------------------------------------------------------------
alter table public.realtime_locations enable row level security;

drop policy if exists "realtime_locations_relevant" on public.realtime_locations;
create policy "realtime_locations_relevant"
  on public.realtime_locations for select
  using (
    public.owns_rider(rider_id)
    or public.is_admin()
    or exists (
      select 1 from public.orders o
      where o.rider_id = realtime_locations.rider_id
        and o.customer_profile_id = auth.uid()
        and o.status in ('assigned', 'picked_up', 'on_the_way')
    )
  );

drop policy if exists "realtime_locations_rider_write" on public.realtime_locations;
create policy "realtime_locations_rider_write"
  on public.realtime_locations for insert
  with check (public.owns_rider(rider_id));

drop policy if exists "realtime_locations_rider_update" on public.realtime_locations;
create policy "realtime_locations_rider_update"
  on public.realtime_locations for update
  using (public.owns_rider(rider_id));

-- Vendor visibility into their own riders' live locations (0012).
drop policy if exists "realtime_locations_visible_to_vendor" on public.realtime_locations;
create policy "realtime_locations_visible_to_vendor"
  on public.realtime_locations for select
  using (
    exists (
      select 1 from public.riders r
      where r.id = realtime_locations.rider_id
        and public.owns_vendor(r.vendor_id)
    )
  );

alter table public.tracking_logs enable row level security;

drop policy if exists "tracking_logs_via_order" on public.tracking_logs;
create policy "tracking_logs_via_order"
  on public.tracking_logs for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = tracking_logs.order_id
        and (o.customer_profile_id = auth.uid() or public.owns_vendor(o.vendor_id) or public.owns_rider(o.rider_id) or public.is_admin())
    )
  );

-- ----------------------------------------------------------------------------
-- SETTINGS & AUDIT LOGS — admin only
-- ----------------------------------------------------------------------------
alter table public.settings enable row level security;
drop policy if exists "settings_admin_only" on public.settings;
create policy "settings_admin_only" on public.settings for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.audit_logs enable row level security;
drop policy if exists "audit_logs_admin_read" on public.audit_logs;
create policy "audit_logs_admin_read" on public.audit_logs for select using (public.is_admin());
drop policy if exists "audit_logs_system_insert" on public.audit_logs;
create policy "audit_logs_system_insert" on public.audit_logs for insert with check (true);

-- ----------------------------------------------------------------------------
-- COD SETTLEMENTS (0015)
-- ----------------------------------------------------------------------------
alter table public.cod_settlements enable row level security;

drop policy if exists "Riders see own settlements" on public.cod_settlements;
create policy "Riders see own settlements"
  on public.cod_settlements for select
  using (rider_id in (
    select id from public.riders where profile_id = auth.uid()
  ));

drop policy if exists "Vendors see own settlements" on public.cod_settlements;
create policy "Vendors see own settlements"
  on public.cod_settlements for select
  using (vendor_id in (
    select id from public.vendors where profile_id = auth.uid()
  ));

-- ----------------------------------------------------------------------------
-- PAYMENT_TRANSACTIONS (0024)
-- ----------------------------------------------------------------------------
alter table public.payment_transactions enable row level security;

drop policy if exists "pt_rider_select" on public.payment_transactions;
create policy "pt_rider_select" on public.payment_transactions for select
  using (rider_id in (select id from public.riders where profile_id = auth.uid()));

drop policy if exists "pt_vendor_select" on public.payment_transactions;
create policy "pt_vendor_select" on public.payment_transactions for select
  using (vendor_id in (select id from public.vendors where profile_id = auth.uid()));

drop policy if exists "pt_customer_select" on public.payment_transactions;
create policy "pt_customer_select" on public.payment_transactions for select
  using (customer_profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- PAYMENT_RECEIPTS (0024)
-- ----------------------------------------------------------------------------
alter table public.payment_receipts enable row level security;

drop policy if exists "pr_vendor_select" on public.payment_receipts;
create policy "pr_vendor_select" on public.payment_receipts for select
  using (vendor_id in (select id from public.vendors where profile_id = auth.uid()));

drop policy if exists "pr_rider_select" on public.payment_receipts;
create policy "pr_rider_select" on public.payment_receipts for select
  using (exists (
    select 1 from public.payment_transactions t
    join public.riders r on r.id = t.rider_id
    where t.id = payment_receipts.payment_transaction_id and r.profile_id = auth.uid()
  ));

drop policy if exists "pr_customer_select" on public.payment_receipts;
create policy "pr_customer_select" on public.payment_receipts for select
  using (exists (
    select 1 from public.payment_transactions t
    where t.id = payment_receipts.payment_transaction_id and t.customer_profile_id = auth.uid()
  ));

-- ----------------------------------------------------------------------------
-- PAYMENT_AUDIT_LOGS (0024)
-- ----------------------------------------------------------------------------
alter table public.payment_audit_logs enable row level security;

drop policy if exists "pal_select" on public.payment_audit_logs;
create policy "pal_select" on public.payment_audit_logs for select
  using (
    performed_by = auth.uid()
    or exists (
      select 1 from public.payment_transactions t
      join public.vendors v on v.id = t.vendor_id
      where t.id = payment_audit_logs.payment_transaction_id and v.profile_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- PAYMENT_AMENDMENT_REQUESTS (0024)
-- ----------------------------------------------------------------------------
alter table public.payment_amendment_requests enable row level security;

drop policy if exists "par_rider_select" on public.payment_amendment_requests;
create policy "par_rider_select" on public.payment_amendment_requests for select
  using (rider_id in (select id from public.riders where profile_id = auth.uid()));

drop policy if exists "par_vendor_select" on public.payment_amendment_requests;
create policy "par_vendor_select" on public.payment_amendment_requests for select
  using (vendor_id in (select id from public.vendors where profile_id = auth.uid()));

-- ----------------------------------------------------------------------------
-- CUSTOMER_ACCOUNT_STATEMENTS (0024)
-- ----------------------------------------------------------------------------
alter table public.customer_account_statements enable row level security;

drop policy if exists "cas_customer_select" on public.customer_account_statements;
create policy "cas_customer_select" on public.customer_account_statements for select
  using (customer_profile_id = auth.uid());

drop policy if exists "cas_vendor_select" on public.customer_account_statements;
create policy "cas_vendor_select" on public.customer_account_statements for select
  using (vendor_id in (select id from public.vendors where profile_id = auth.uid()));
