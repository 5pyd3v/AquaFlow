-- ============================================================
-- AquaFlow Auth Overhaul Migration
-- Run this in Supabase SQL Editor (once).
--
-- What it does:
--   1. Enforces phone uniqueness at the DB level.
--   2. Links each customer to exactly ONE vendor (customers.vendor_id).
--   3. Adds a permanent 6-digit login PIN for customers.
--   4. Restricts product visibility so a customer only sees the
--      products of their linked vendor.
--   5. Provisions customer accounts (real auth.users row + PIN) so a
--      vendor can create a customer on-device and hand them a PIN.
--   6. Links riders / self-registering customers to a vendor by id.
--
-- PIN-login model: the customer's Supabase auth identity is a synthetic
-- email  <digits-of-phone>@pin.aquaflow.app  with the 6-digit PIN as the
-- password. The Flutter client creates that auth user via auth.signUp on
-- a throwaway client (so the vendor's session is untouched) and then
-- calls finalize_customer_account to confirm the email and write the
-- profile + customer rows. Customers later sign in with signInWithPassword
-- against the synthetic email using their phone + PIN.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1. Phone uniqueness
--    Partial unique index (skips blank phones, which are allowed
--    for OAuth/bootstrap rows that haven't captured a phone yet).
-- ------------------------------------------------------------
create unique index if not exists profiles_phone_unique
  on public.profiles (phone)
  where phone <> '';

-- ------------------------------------------------------------
-- 2. Customer -> Vendor link
-- ------------------------------------------------------------
alter table public.customers
  add column if not exists vendor_id uuid references public.vendors(id);

create index if not exists idx_customers_vendor on public.customers(vendor_id);

-- ------------------------------------------------------------
-- 3. Customer login PIN (6 digits, permanent)
-- ------------------------------------------------------------
alter table public.customers
  add column if not exists pin varchar(6);

-- ------------------------------------------------------------
-- 4. Product visibility: a customer only sees their vendor's products.
--    Vendors keep managing their own; admins see everything.
-- ------------------------------------------------------------
drop policy if exists "products_visible_to_customer" on public.products;
drop policy if exists "products_readable" on public.products;
drop policy if exists "products_visible_to_linked_customer" on public.products;

create policy "products_visible_to_linked_customer"
  on public.products for select
  using (
    exists (
      select 1 from public.customers c
      where c.profile_id = auth.uid()
        and c.vendor_id = products.vendor_id
    )
    or public.owns_vendor(vendor_id)
    or public.is_admin()
  );

-- ------------------------------------------------------------
-- 5. finalize_customer_account
--    The Flutter client first creates the auth user on a throwaway
--    Supabase client (auth.signUp with synthetic email <digits>@pin.aquaflow.app
--    and the 6-digit PIN as the password) so the vendor's own session is
--    never disturbed. It then calls this RPC (as the authenticated
--    vendor) to finalise: confirm the email so PIN login works instantly,
--    write the profile + customer rows, link the vendor, and store the PIN.
-- ------------------------------------------------------------
create or replace function public.finalize_customer_account(
  p_uid uuid,
  p_vendor_id uuid,
  p_phone text,
  p_full_name text,
  p_pin varchar
) returns json
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
begin
  if not exists (select 1 from public.vendors where id = p_vendor_id) then
    raise exception 'Invalid vendor ID';
  end if;

  -- Confirm the synthetic email so signInWithPassword succeeds even when
  -- the project has email confirmations enabled.
  update auth.users
    set email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = p_uid;

  insert into public.profiles (id, full_name, phone, email, role, is_verified, is_active)
  values (
    p_uid, p_full_name, p_phone,
    regexp_replace(p_phone, '[^0-9]', '', 'g') || '@pin.aquaflow.app',
    'customer', true, true
  )
  on conflict (id) do update
    set full_name = excluded.full_name,
        phone = excluded.phone,
        is_verified = true,
        is_active = true;

  insert into public.customers (profile_id, vendor_id, pin)
  values (p_uid, p_vendor_id, p_pin)
  on conflict (profile_id) do update
    set vendor_id = excluded.vendor_id,
        pin = excluded.pin;

  return json_build_object('profile_id', p_uid, 'pin', p_pin);
end;
$$;

-- ------------------------------------------------------------
-- 6. link_customer_to_vendor  (self-registered customer via email)
-- ------------------------------------------------------------
create or replace function public.link_customer_to_vendor(
  p_profile_id uuid,
  p_vendor_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.vendors where id = p_vendor_id) then
    raise exception 'Invalid vendor ID. Please check with your water vendor.';
  end if;

  update public.customers set vendor_id = p_vendor_id where profile_id = p_profile_id;
  if not found then
    raise exception 'Customer profile not found';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- 7. link_rider_to_vendor_by_id  (rider self-links during signup)
-- ------------------------------------------------------------
create or replace function public.link_rider_to_vendor_by_id(
  p_rider_profile_id uuid,
  p_vendor_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.vendors where id = p_vendor_id) then
    raise exception 'Invalid vendor ID';
  end if;

  update public.riders set vendor_id = p_vendor_id where profile_id = p_rider_profile_id;
  if not found then
    raise exception 'Rider profile not found';
  end if;
end;
$$;

-- ------------------------------------------------------------
-- 8. Grants — these RPCs are callable by anon (customer PIN create is
--    vendor-initiated while authenticated; validation happens inside).
-- ------------------------------------------------------------
grant execute on function public.finalize_customer_account(uuid, uuid, text, text, varchar) to authenticated;
grant execute on function public.link_customer_to_vendor(uuid, uuid) to authenticated;
grant execute on function public.link_rider_to_vendor_by_id(uuid, uuid) to authenticated;
