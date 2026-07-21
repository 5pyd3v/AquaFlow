-- ============================================================================
-- AquaFlow — Functions & Triggers (Migration 0003)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Generic `updated_at` bumper, attached to every table that has the column.
-- ----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_profiles_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger trg_vendors_updated_at before update on public.vendors
  for each row execute function public.set_updated_at();
create trigger trg_riders_updated_at before update on public.riders
  for each row execute function public.set_updated_at();
create trigger trg_products_updated_at before update on public.products
  for each row execute function public.set_updated_at();
create trigger trg_orders_updated_at before update on public.orders
  for each row execute function public.set_updated_at();
create trigger trg_inventory_updated_at before update on public.inventory
  for each row execute function public.set_updated_at();
create trigger trg_wallets_updated_at before update on public.wallets
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- Auto-create a `profiles` row the instant a Supabase Auth user is
-- created (belt-and-suspenders alongside the client-side bootstrap in
-- AuthRepositoryImpl — whichever runs first wins, the other is a no-op).
-- ----------------------------------------------------------------------------
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.profiles (id, full_name, email, phone, role, is_verified, is_active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email,
    coalesce(new.raw_user_meta_data->>'phone', new.phone, ''),
    coalesce((new.raw_user_meta_data->>'role')::user_role, 'customer'),
    false,
    true
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ----------------------------------------------------------------------------
-- Auto-generate a human-friendly, sequential order number
-- (e.g. AQF-20260716-000042) instead of exposing the raw UUID to users.
-- ----------------------------------------------------------------------------
create sequence if not exists public.order_number_seq;

create or replace function public.generate_order_number()
returns trigger
language plpgsql
as $$
begin
  if new.order_number is null or new.order_number = '' then
    new.order_number := 'AQF-' || to_char(now(), 'YYYYMMDD') || '-' ||
      lpad(nextval('public.order_number_seq')::text, 6, '0');
  end if;
  return new;
end;
$$;

create trigger trg_orders_generate_number
  before insert on public.orders
  for each row execute function public.generate_order_number();

-- ----------------------------------------------------------------------------
-- Append a tracking_logs row every time an order's status changes —
-- this is what powers the customer-facing timeline UI without the
-- client needing to write both tables in one round trip.
-- ----------------------------------------------------------------------------
create or replace function public.log_order_status_change()
returns trigger
language plpgsql
as $$
begin
  if (tg_op = 'INSERT') or (old.status is distinct from new.status) then
    insert into public.tracking_logs (order_id, status, created_at)
    values (new.id, new.status, now());
  end if;
  return new;
end;
$$;

create trigger trg_orders_log_status
  after insert or update of status on public.orders
  for each row execute function public.log_order_status_change();

-- ----------------------------------------------------------------------------
-- Push a `notifications` row (and rely on Supabase Realtime + a
-- Database Webhook to fan it out to FCM) whenever an order changes
-- status, so both customer and vendor apps get instant updates.
-- ----------------------------------------------------------------------------
create or replace function public.notify_order_status_change()
returns trigger
language plpgsql
security definer
as $$
declare
  vendor_profile_id uuid;
begin
  if tg_op = 'UPDATE' and old.status = new.status then
    return new;
  end if;

  insert into public.notifications (profile_id, type, title, body, data)
  values (
    new.customer_profile_id,
    'order_update',
    'Order ' || new.order_number,
    'Your order status is now: ' || new.status,
    jsonb_build_object('order_id', new.id, 'status', new.status)
  );

  if new.vendor_id is not null then
    select profile_id into vendor_profile_id from public.vendors where id = new.vendor_id;
    if vendor_profile_id is not null then
      insert into public.notifications (profile_id, type, title, body, data)
      values (
        vendor_profile_id,
        case when tg_op = 'INSERT' then 'new_order' else 'order_update' end,
        case when tg_op = 'INSERT' then 'New Order Received' else 'Order Updated' end,
        'Order ' || new.order_number || ' is now ' || new.status,
        jsonb_build_object('order_id', new.id, 'status', new.status)
      );
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_orders_notify
  after insert or update of status on public.orders
  for each row execute function public.notify_order_status_change();

-- ----------------------------------------------------------------------------
-- Keep `realtime_locations` in sync with the rider's last-known point
-- on `riders.current_location` for simpler admin heat-map queries.
-- ----------------------------------------------------------------------------
create or replace function public.sync_rider_location()
returns trigger
language plpgsql
as $$
begin
  update public.riders
  set current_location = new.location, updated_at = now()
  where id = new.rider_id;
  return new;
end;
$$;

create trigger trg_realtime_locations_sync
  after insert or update on public.realtime_locations
  for each row execute function public.sync_rider_location();

-- ----------------------------------------------------------------------------
-- Wallet debit/credit helper — keeps balance math atomic and off the
-- client, called from Edge Functions / RPC rather than raw updates.
-- ----------------------------------------------------------------------------
create or replace function public.adjust_wallet_balance(
  p_profile_id uuid,
  p_amount numeric,
  p_type text,
  p_order_id uuid default null,
  p_description text default null
)
returns void
language plpgsql
security definer
as $$
declare
  v_wallet_id uuid;
begin
  insert into public.wallets (profile_id, balance)
  values (p_profile_id, 0)
  on conflict (profile_id) do nothing;

  select id into v_wallet_id from public.wallets where profile_id = p_profile_id;

  if p_type = 'credit' then
    update public.wallets set balance = balance + p_amount, updated_at = now() where id = v_wallet_id;
  elsif p_type = 'debit' then
    update public.wallets set balance = balance - p_amount, updated_at = now() where id = v_wallet_id;
  else
    raise exception 'Invalid wallet transaction type: %', p_type;
  end if;

  insert into public.wallet_transactions (wallet_id, order_id, amount, type, description)
  values (v_wallet_id, p_order_id, p_amount, p_type, p_description);
end;
$$;
