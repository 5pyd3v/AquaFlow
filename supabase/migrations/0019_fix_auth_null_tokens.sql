-- ============================================================================
-- AquaFlow — Fix "Database error querying schema" (Migration 0019)
--
-- When we manually INSERT into auth.users, GoTrue later scans the row on
-- login. Its token columns (confirmation_token, recovery_token,
-- email_change*, phone_change*, reauthentication_token) are read into
-- non-nullable Go strings. If they are NULL, GoTrue errors with
-- "Database error querying schema" — breaking BOTH email and PIN login.
--
-- Migration 0018 only set confirmation_token = '' ; the rest defaulted to
-- NULL. This migration:
--   1. Repairs every existing auth.users row (NULL tokens -> '')
--   2. Recreates create_email_user + create_pin_customer to always set
--      every token column to '' on insert.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Repair existing rows
-- ----------------------------------------------------------------------------

update auth.users
set
  confirmation_token         = coalesce(confirmation_token, ''),
  recovery_token             = coalesce(recovery_token, ''),
  email_change_token_new     = coalesce(email_change_token_new, ''),
  email_change               = coalesce(email_change, ''),
  email_change_token_current = coalesce(email_change_token_current, ''),
  phone_change               = coalesce(phone_change, ''),
  phone_change_token         = coalesce(phone_change_token, ''),
  reauthentication_token     = coalesce(reauthentication_token, '')
where
  confirmation_token is null
  or recovery_token is null
  or email_change_token_new is null
  or email_change is null
  or email_change_token_current is null
  or phone_change is null
  or phone_change_token is null
  or reauthentication_token is null;

-- ----------------------------------------------------------------------------
-- 2. create_pin_customer — now sets all token columns
-- ----------------------------------------------------------------------------

create or replace function public.create_pin_customer(
  p_vendor_id uuid,
  p_phone text,
  p_full_name text,
  p_email text,
  p_pin text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
begin
  select id into v_uid from auth.users where email = p_email limit 1;
  if v_uid is not null then
    return false;
  end if;

  v_uid := gen_random_uuid();

  insert into auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    aud,
    role,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    email_change_token_current,
    phone_change,
    phone_change_token,
    reauthentication_token,
    created_at,
    updated_at
  )
  values (
    v_uid,
    '00000000-0000-0000-0000-000000000000',
    p_email,
    extensions.crypt(p_pin, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'full_name', p_full_name,
      'phone', p_phone,
      'role', 'customer'
    ),
    'authenticated',
    'authenticated',
    '', '', '', '', '', '', '', '',
    now(),
    now()
  );

  insert into auth.identities (
    id,
    user_id,
    provider_id,
    provider,
    identity_data,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    v_uid,
    v_uid,
    v_uid::text,
    'email',
    jsonb_build_object('sub', v_uid::text, 'email', p_email),
    now(),
    now(),
    now()
  );

  insert into public.profiles (id, full_name, email, phone, role, is_verified, is_active)
  values (v_uid, p_full_name, p_email, p_phone, 'customer', true, true)
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    email = excluded.email,
    is_verified = true,
    is_active = true,
    updated_at = now();

  insert into public.customers (profile_id, vendor_id, pin, referral_code)
  values (
    v_uid,
    p_vendor_id,
    p_pin,
    upper(substr(replace(v_uid::text, '-', ''), 1, 8))
  )
  on conflict (profile_id) do update set
    vendor_id = excluded.vendor_id,
    pin = excluded.pin;

  return true;
end;
$$;

grant execute on function public.create_pin_customer(uuid, text, text, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. create_email_user — now sets all token columns
-- ----------------------------------------------------------------------------

create or replace function public.create_email_user(
  p_email text,
  p_password text,
  p_full_name text,
  p_phone text,
  p_role text,
  p_business_name text default null,
  p_vendor_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
  v_active boolean;
begin
  select id into v_uid from auth.users where email = p_email limit 1;
  if v_uid is not null then
    return null;
  end if;

  if p_phone <> '' then
    perform 1 from public.profiles where phone = p_phone limit 1;
    if found then
      return null;
    end if;
  end if;

  v_uid := gen_random_uuid();
  v_active := p_role not in ('vendor', 'rider');

  insert into auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    aud,
    role,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    email_change_token_current,
    phone_change,
    phone_change_token,
    reauthentication_token,
    created_at,
    updated_at
  )
  values (
    v_uid,
    '00000000-0000-0000-0000-000000000000',
    p_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'full_name', p_full_name,
      'phone', p_phone,
      'role', p_role
    ),
    'authenticated',
    'authenticated',
    '', '', '', '', '', '', '', '',
    now(),
    now()
  );

  insert into auth.identities (
    id,
    user_id,
    provider_id,
    provider,
    identity_data,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    v_uid,
    v_uid,
    v_uid::text,
    'email',
    jsonb_build_object('sub', v_uid::text, 'email', p_email),
    now(),
    now(),
    now()
  );

  insert into public.profiles (id, full_name, email, phone, role, is_verified, is_active)
  values (v_uid, p_full_name, p_email, p_phone, p_role::user_role, true, v_active)
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    email = excluded.email,
    role = excluded.role,
    is_verified = true,
    is_active = v_active,
    updated_at = now();

  if p_role = 'vendor' then
    insert into public.vendors (profile_id, business_name)
    values (v_uid, coalesce(p_business_name, ''))
    on conflict (profile_id) do update set business_name = coalesce(p_business_name, vendors.business_name);
  elsif p_role = 'rider' then
    insert into public.riders (profile_id, vendor_id)
    values (v_uid, p_vendor_id)
    on conflict (profile_id) do update set vendor_id = coalesce(p_vendor_id, riders.vendor_id);
  elsif p_role = 'customer' then
    insert into public.customers (profile_id, vendor_id, referral_code)
    values (v_uid, p_vendor_id, upper(substr(replace(v_uid::text, '-', ''), 1, 8)))
    on conflict (profile_id) do update set vendor_id = coalesce(p_vendor_id, customers.vendor_id);
  end if;

  return v_uid;
end;
$$;

grant execute on function public.create_email_user(text, text, text, text, text, text, uuid) to anon, authenticated;
