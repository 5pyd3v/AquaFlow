-- ============================================================================
-- AquaFlow — Auth Overhaul (Migration 0016)
--
-- 1. Add vendor_id + pin columns to customers
-- 2. Add unique constraint on profiles.phone
-- 3. Update handle_new_auth_user to set is_active = false for vendors/riders
-- 4. Create resolve_pin_login RPC (PIN-only customer login)
-- 5. Create finalize_customer_account RPC (vendor creates customer)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema additions
-- ----------------------------------------------------------------------------

alter table public.customers
  add column if not exists vendor_id uuid references public.vendors(id) on delete set null;

alter table public.customers
  add column if not exists pin varchar(6);

create index if not exists idx_customers_vendor on public.customers(vendor_id);
create unique index if not exists idx_customers_pin on public.customers(pin) where pin is not null;

-- Phone uniqueness (soft — allow empty strings which are bootstrapped defaults)
create unique index if not exists idx_profiles_phone_unique
  on public.profiles(phone)
  where phone <> '';

-- ----------------------------------------------------------------------------
-- 2. Updated auth trigger — vendors/riders start inactive
-- ----------------------------------------------------------------------------

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role user_role;
  v_active boolean;
begin
  begin
    v_role := coalesce(
      (new.raw_user_meta_data->>'role')::user_role,
      'customer'
    );
  exception when others then
    v_role := 'customer';
  end;

  v_active := v_role not in ('vendor', 'rider');

  begin
    insert into public.profiles (
      id, full_name, email, phone, role, is_verified, is_active
    )
    values (
      new.id,
      coalesce(new.raw_user_meta_data->>'full_name', ''),
      new.email,
      coalesce(new.raw_user_meta_data->>'phone', new.phone, ''),
      v_role,
      false,
      v_active
    )
    on conflict (id) do nothing;
  exception when others then
    raise warning
      'handle_new_auth_user: profile insert failed for %: %',
      new.id, sqlerrm;
  end;

  return new;
end;
$$;

-- Recreate trigger
drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ----------------------------------------------------------------------------
-- 3. resolve_pin_login — lookup customer by PIN, return phone
-- ----------------------------------------------------------------------------

create or replace function public.resolve_pin_login(p_pin text)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_phone text;
begin
  select p.phone into v_phone
  from public.customers c
  join public.profiles p on p.id = c.profile_id
  where c.pin = p_pin
  limit 1;

  if v_phone is null then
    return null;
  end if;

  return json_build_object('phone', v_phone);
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. finalize_customer_account — vendor creates a customer
--    Called after the throwaway client signs up the auth user.
--    Confirms the email, writes profile + customer rows.
-- ----------------------------------------------------------------------------

create or replace function public.finalize_customer_account(
  p_uid uuid,
  p_vendor_id uuid,
  p_phone text,
  p_full_name text,
  p_pin text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Upsert the profile row
  insert into public.profiles (id, full_name, email, phone, role, is_verified, is_active)
  values (
    p_uid,
    p_full_name,
    (regexp_replace(p_phone, '[^0-9]', '', 'g') || '@pin.aquaflow.app'),
    p_phone,
    'customer',
    true,
    true
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    is_verified = true,
    is_active = true,
    updated_at = now();

  -- Upsert the customer sub-row with vendor link + PIN
  insert into public.customers (profile_id, vendor_id, pin, referral_code)
  values (
    p_uid,
    p_vendor_id,
    p_pin,
    upper(substr(replace(p_uid::text, '-', ''), 1, 8))
  )
  on conflict (profile_id) do update set
    vendor_id = excluded.vendor_id,
    pin = excluded.pin;

  -- Confirm the synthetic email in auth so signInWithPassword works
  update auth.users
  set email_confirmed_at = now(),
      confirmation_token = '',
      updated_at = now()
  where id = p_uid
    and email_confirmed_at is null;
end;
$$;

-- Grant execute to authenticated (vendor calls this via their session)
grant execute on function public.finalize_customer_account(uuid, uuid, text, text, text) to authenticated;
grant execute on function public.resolve_pin_login(text) to anon, authenticated;
