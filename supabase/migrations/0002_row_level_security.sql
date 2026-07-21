-- ============================================================================
-- AquaFlow — Row Level Security Policies (Migration 0002)
-- Principle: deny by default, then grant the narrowest policy that
-- lets each role do its job. Every table with `enable row level
-- security` below has NO access at all until a policy explicitly
-- allows it.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper functions (SECURITY DEFINER so policies can call them without
-- re-triggering RLS on `profiles` recursively)
-- ----------------------------------------------------------------------------
create or replace function public.current_role()
returns user_role
language sql
security definer
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select coalesce(
    (select role in ('admin', 'super_admin') from public.profiles where id = auth.uid()),
    false
  );
$$;

create or replace function public.owns_vendor(check_vendor_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.vendors
    where id = check_vendor_id and profile_id = auth.uid()
  );
$$;

create or replace function public.owns_rider(check_rider_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.riders
    where id = check_rider_id and profile_id = auth.uid()
  );
$$;

-- ----------------------------------------------------------------------------
-- PROFILES
-- ----------------------------------------------------------------------------
alter table public.profiles enable row level security;

create policy "profiles_select_own_or_admin"
  on public.profiles for select
  using (id = auth.uid() or public.is_admin());

create policy "profiles_insert_own"
  on public.profiles for insert
  with check (id = auth.uid());

create policy "profiles_update_own_or_admin"
  on public.profiles for update
  using (id = auth.uid() or public.is_admin());

-- ----------------------------------------------------------------------------
-- COMPANIES — admin managed, publicly readable (branding)
-- ----------------------------------------------------------------------------
alter table public.companies enable row level security;

create policy "companies_select_all" on public.companies for select using (true);
create policy "companies_admin_write" on public.companies for all
  using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- VENDORS
-- ----------------------------------------------------------------------------
alter table public.vendors enable row level security;

create policy "vendors_select_all"
  on public.vendors for select
  using (status = 'approved' or profile_id = auth.uid() or public.is_admin());

create policy "vendors_insert_own"
  on public.vendors for insert
  with check (profile_id = auth.uid());

create policy "vendors_update_own_or_admin"
  on public.vendors for update
  using (profile_id = auth.uid() or public.is_admin());

-- ----------------------------------------------------------------------------
-- RIDERS
-- ----------------------------------------------------------------------------
alter table public.riders enable row level security;

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

create policy "riders_insert_own"
  on public.riders for insert
  with check (profile_id = auth.uid());

create policy "riders_update_own_or_vendor_or_admin"
  on public.riders for update
  using (profile_id = auth.uid() or public.owns_vendor(vendor_id) or public.is_admin());

-- ----------------------------------------------------------------------------
-- CUSTOMERS
-- ----------------------------------------------------------------------------
alter table public.customers enable row level security;

create policy "customers_select_own_or_admin"
  on public.customers for select
  using (profile_id = auth.uid() or public.is_admin());

create policy "customers_insert_own"
  on public.customers for insert
  with check (profile_id = auth.uid());

create policy "customers_update_own"
  on public.customers for update
  using (profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- CATEGORIES & PRODUCTS — public catalog, vendor-owned writes
-- ----------------------------------------------------------------------------
alter table public.categories enable row level security;
create policy "categories_select_all" on public.categories for select using (true);
create policy "categories_admin_write" on public.categories for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.products enable row level security;

create policy "products_select_all"
  on public.products for select
  using (is_available or public.owns_vendor(vendor_id) or public.is_admin());

create policy "products_vendor_write"
  on public.products for all
  using (public.owns_vendor(vendor_id) or public.is_admin())
  with check (public.owns_vendor(vendor_id) or public.is_admin());

-- ----------------------------------------------------------------------------
-- INVENTORY — vendor-only
-- ----------------------------------------------------------------------------
alter table public.inventory enable row level security;

create policy "inventory_vendor_only"
  on public.inventory for all
  using (public.owns_vendor(vendor_id) or public.is_admin())
  with check (public.owns_vendor(vendor_id) or public.is_admin());

-- ----------------------------------------------------------------------------
-- ADDRESSES — customer owns their own
-- ----------------------------------------------------------------------------
alter table public.addresses enable row level security;

create policy "addresses_owner_only"
  on public.addresses for all
  using (customer_profile_id = auth.uid() or public.is_admin())
  with check (customer_profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- DELIVERY ZONES — vendor managed, publicly readable for checkout logic
-- ----------------------------------------------------------------------------
alter table public.delivery_zones enable row level security;

create policy "delivery_zones_select_all" on public.delivery_zones for select using (true);
create policy "delivery_zones_vendor_write" on public.delivery_zones for all
  using (public.owns_vendor(vendor_id) or public.is_admin())
  with check (public.owns_vendor(vendor_id) or public.is_admin());

-- ----------------------------------------------------------------------------
-- COUPONS — publicly readable if active, admin managed
-- ----------------------------------------------------------------------------
alter table public.coupons enable row level security;

create policy "coupons_select_active" on public.coupons for select using (is_active or public.is_admin());
create policy "coupons_admin_write" on public.coupons for all
  using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- ORDERS — the central authorization surface
-- ----------------------------------------------------------------------------
alter table public.orders enable row level security;

create policy "orders_select_participants"
  on public.orders for select
  using (
    customer_profile_id = auth.uid()
    or public.owns_vendor(vendor_id)
    or public.owns_rider(rider_id)
    or public.is_admin()
  );

create policy "orders_insert_customer"
  on public.orders for insert
  with check (customer_profile_id = auth.uid());

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
-- SUBSCRIPTIONS
-- ----------------------------------------------------------------------------
alter table public.subscriptions enable row level security;

create policy "subscriptions_owner_or_vendor_or_admin"
  on public.subscriptions for all
  using (customer_profile_id = auth.uid() or public.owns_vendor(vendor_id) or public.is_admin())
  with check (customer_profile_id = auth.uid());

alter table public.subscription_items enable row level security;

create policy "subscription_items_via_subscription"
  on public.subscription_items for all
  using (
    exists (
      select 1 from public.subscriptions s
      where s.id = subscription_items.subscription_id
        and (s.customer_profile_id = auth.uid() or public.owns_vendor(s.vendor_id) or public.is_admin())
    )
  );

-- ----------------------------------------------------------------------------
-- DEPOSITS & BOTTLE RETURNS
-- ----------------------------------------------------------------------------
alter table public.deposits enable row level security;

create policy "deposits_owner_or_admin"
  on public.deposits for select
  using (customer_profile_id = auth.uid() or public.is_admin());

alter table public.bottle_returns enable row level security;

create policy "bottle_returns_participants"
  on public.bottle_returns for all
  using (customer_profile_id = auth.uid() or public.owns_rider(rider_id) or public.is_admin())
  with check (customer_profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- WALLETS & TRANSACTIONS
-- ----------------------------------------------------------------------------
alter table public.wallets enable row level security;

create policy "wallets_owner_or_admin"
  on public.wallets for select
  using (profile_id = auth.uid() or public.is_admin());

alter table public.wallet_transactions enable row level security;

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
-- INVOICES
-- ----------------------------------------------------------------------------
alter table public.invoices enable row level security;

create policy "invoices_via_order"
  on public.invoices for select
  using (
    exists (
      select 1 from public.orders o
      where o.id = invoices.order_id
        and (o.customer_profile_id = auth.uid() or public.owns_vendor(o.vendor_id) or public.is_admin())
    )
  );

-- ----------------------------------------------------------------------------
-- RATINGS
-- ----------------------------------------------------------------------------
alter table public.ratings enable row level security;

create policy "ratings_select_all" on public.ratings for select using (true);

create policy "ratings_insert_rater"
  on public.ratings for insert
  with check (rater_profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- FAVORITES
-- ----------------------------------------------------------------------------
alter table public.favorites enable row level security;

create policy "favorites_owner_only"
  on public.favorites for all
  using (customer_profile_id = auth.uid())
  with check (customer_profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- CHATS & MESSAGES
-- ----------------------------------------------------------------------------
alter table public.chats enable row level security;

create policy "chats_participants_only"
  on public.chats for all
  using (participant_one = auth.uid() or participant_two = auth.uid() or public.is_admin())
  with check (participant_one = auth.uid() or participant_two = auth.uid());

alter table public.messages enable row level security;

create policy "messages_via_chat"
  on public.messages for all
  using (
    exists (
      select 1 from public.chats c
      where c.id = messages.chat_id
        and (c.participant_one = auth.uid() or c.participant_two = auth.uid() or public.is_admin())
    )
  )
  with check (sender_profile_id = auth.uid());

-- ----------------------------------------------------------------------------
-- NOTIFICATIONS
-- ----------------------------------------------------------------------------
alter table public.notifications enable row level security;

create policy "notifications_owner_only"
  on public.notifications for all
  using (profile_id = auth.uid() or public.is_admin());

-- ----------------------------------------------------------------------------
-- REALTIME LOCATIONS & TRACKING LOGS
-- ----------------------------------------------------------------------------
alter table public.realtime_locations enable row level security;

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

create policy "realtime_locations_rider_write"
  on public.realtime_locations for insert
  with check (public.owns_rider(rider_id));

create policy "realtime_locations_rider_update"
  on public.realtime_locations for update
  using (public.owns_rider(rider_id));

alter table public.tracking_logs enable row level security;

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
create policy "settings_admin_only" on public.settings for all
  using (public.is_admin()) with check (public.is_admin());

alter table public.audit_logs enable row level security;
create policy "audit_logs_admin_read" on public.audit_logs for select using (public.is_admin());
create policy "audit_logs_system_insert" on public.audit_logs for insert with check (true);
