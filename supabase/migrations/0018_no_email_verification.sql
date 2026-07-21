-- ============================================================================
-- AquaFlow — Remove Email Verification (Migration 0018)
--
-- 1. Enable pgcrypto (needed for crypt/gen_salt password hashing)
-- 2. auto_confirm_user  — confirms auth.users.email_confirmed_at
-- 3. create_pin_customer — atomic customer account creation
-- 4. create_email_user — atomic email/password user creation (no email sent)
-- ============================================================================

-- pgcrypto is required for crypt() and gen_salt() used below
create extension if not exists pgcrypto with schema extensions;

-- ----------------------------------------------------------------------------
-- 1. auto_confirm_user
--    Called from the Flutter app immediately after signUp() so the user
--    can sign in without clicking an email link.
-- ----------------------------------------------------------------------------

create or replace function public.auto_confirm_user(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update auth.users
  set email_confirmed_at = coalesce(email_confirmed_at, now()),
      confirmation_token = '',
      updated_at = now()
  where id = p_uid;
end;
$$;

grant execute on function public.auto_confirm_user(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. create_pin_customer
--    Vendor calls this to create a customer account in one shot:
--    • Inserts into auth.users with a confirmed email
--    • Upserts profile row
--    • Upserts customer sub-row with vendor link + PIN
--    Returns true on success, false if the email already exists.
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
  -- Check if this email (synthetic) already exists in auth.users
  select id into v_uid
  from auth.users
  where email = p_email
  limit 1;

  if v_uid is not null then
    -- Already exists — return false so the app shows a clean error
    return false;
  end if;

  -- Generate a new UUID for the user
  v_uid := gen_random_uuid();

  -- Create the auth.users row directly (SECURITY DEFINER can do this)
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
    created_at,
    updated_at
  )
  values (
    v_uid,
    '00000000-0000-0000-0000-000000000000',
    p_email,
    extensions.crypt(p_pin, extensions.gen_salt('bf')),
    now(),  -- confirmed immediately
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'full_name', p_full_name,
      'phone', p_phone,
      'role', 'customer'
    ),
    'authenticated',
    'authenticated',
    '',
    now(),
    now()
  );

  -- Create identity row so Supabase auth recognises this user
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

  -- Upsert the profile row
  insert into public.profiles (id, full_name, email, phone, role, is_verified, is_active)
  values (
    v_uid,
    p_full_name,
    p_email,
    p_phone,
    'customer',
    true,
    true
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    email = excluded.email,
    is_verified = true,
    is_active = true,
    updated_at = now();

  -- Upsert the customer sub-row with vendor link + PIN
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
-- 4. create_email_user
--    Creates a user directly in auth.users with a confirmed email so
--    NO confirmation email is ever sent by Supabase. Called from the app
--    during normal email/password sign-up. Returns the new user's UUID
--    so the app can sign in immediately with signInWithPassword.
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
  -- Check if email already exists in auth.users
  select id into v_uid from auth.users where email = p_email limit 1;
  if v_uid is not null then
    return null; -- signals duplicate email
  end if;

  -- Check if phone already exists in profiles
  if p_phone <> '' then
    perform 1 from public.profiles where phone = p_phone limit 1;
    if found then
      return null; -- signals duplicate phone
    end if;
  end if;

  v_uid := gen_random_uuid();
  v_active := p_role not in ('vendor', 'rider');

  -- Create auth.users row — email pre-confirmed, no email sent
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
    '',
    now(),
    now()
  );

  -- Create identity row
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

  -- Create profile row
  insert into public.profiles (id, full_name, email, phone, role, is_verified, is_active)
  values (
    v_uid,
    p_full_name,
    p_email,
    p_phone,
    p_role::user_role,
    true,
    v_active
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    email = excluded.email,
    role = excluded.role,
    is_verified = true,
    is_active = v_active,
    updated_at = now();

  -- Create role sub-row (vendors, riders, customers tables)
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
