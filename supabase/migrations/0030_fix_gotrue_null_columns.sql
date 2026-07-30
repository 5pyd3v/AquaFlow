-- ============================================================================
-- AquaFlow — Fix "Database error querying schema" for new accounts (Migration 0030)
--
-- GoTrue (Supabase's auth server) reads auth.users rows into Go structs with
-- non-nullable fields. Any NULL in a token/string column causes the scan to
-- fail with "Database error querying schema". Modern GoTrue also requires
-- is_sso_user (boolean) and is_anonymous (boolean) to be non-null.
--
-- This migration:
--   1. Repairs ALL existing auth.users rows (NULL → '' / false / 0)
--   2. Recreates create_email_user to explicitly set every column GoTrue reads
--   3. Recreates create_pin_customer similarly
--
-- Safe to run even if 0019 was already applied — all operations are idempotent.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Repair existing rows — token strings
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
-- 1b. Repair is_sso_user / is_anonymous (added in newer GoTrue versions).
--     These columns may not exist on older Supabase instances — wrap in DO
--     blocks so the migration doesn't fail if the column isn't there yet.
-- ----------------------------------------------------------------------------

do $$
begin
  execute 'update auth.users set is_sso_user = false where is_sso_user is null';
exception when undefined_column then
  null; -- column doesn't exist on this instance, nothing to fix
end;
$$;

do $$
begin
  execute 'update auth.users set is_anonymous = false where is_anonymous is null';
exception when undefined_column then
  null;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. create_email_user — sets ALL token columns + is_sso_user/is_anonymous
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
  v_has_sso_col boolean;
  v_has_anon_col boolean;
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

  -- Check if newer GoTrue columns exist
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'auth' and table_name = 'users' and column_name = 'is_sso_user'
  ) into v_has_sso_col;

  select exists(
    select 1 from information_schema.columns
    where table_schema = 'auth' and table_name = 'users' and column_name = 'is_anonymous'
  ) into v_has_anon_col;

  -- Insert auth.users row with all token columns explicitly set to ''
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

  -- Set boolean columns if they exist (newer GoTrue)
  if v_has_sso_col then
    execute format('update auth.users set is_sso_user = false where id = %L', v_uid);
  end if;
  if v_has_anon_col then
    execute format('update auth.users set is_anonymous = false where id = %L', v_uid);
  end if;

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
  values (v_uid, p_full_name, p_email, p_phone, p_role::user_role, true, v_active)
  on conflict (id) do update set
    full_name = excluded.full_name,
    phone = excluded.phone,
    email = excluded.email,
    role = excluded.role,
    is_verified = true,
    is_active = v_active,
    updated_at = now();

  -- Create role sub-row
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

-- ----------------------------------------------------------------------------
-- 3. create_pin_customer — same fix: all token columns set to ''
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
  v_has_sso_col boolean;
  v_has_anon_col boolean;
begin
  select id into v_uid from auth.users where email = p_email limit 1;
  if v_uid is not null then
    return false;
  end if;

  v_uid := gen_random_uuid();

  -- Check if newer GoTrue columns exist
  select exists(
    select 1 from information_schema.columns
    where table_schema = 'auth' and table_name = 'users' and column_name = 'is_sso_user'
  ) into v_has_sso_col;

  select exists(
    select 1 from information_schema.columns
    where table_schema = 'auth' and table_name = 'users' and column_name = 'is_anonymous'
  ) into v_has_anon_col;

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

  -- Set boolean columns if they exist (newer GoTrue)
  if v_has_sso_col then
    execute format('update auth.users set is_sso_user = false where id = %L', v_uid);
  end if;
  if v_has_anon_col then
    execute format('update auth.users set is_anonymous = false where id = %L', v_uid);
  end if;

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
