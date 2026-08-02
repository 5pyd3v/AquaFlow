-- ============================================================================
-- AquaFlow — Consolidated Schema: Functions
--
-- GENERATED REFERENCE — see README.md. Exactly one `create or replace
-- function` per distinct function name: the text is copied verbatim from
-- the LAST migration file that (re)defined it. See README.md for the full
-- version-history table (which migration each final body came from).
--
-- Organized: helpers -> auth/profile -> rider linking/approval ->
-- vendor-customers -> order lifecycle -> ratings -> wallet ->
-- COD settlements -> payment management.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- HELPERS (0002) — SECURITY DEFINER so RLS policies can call them without
-- re-triggering RLS on `profiles` recursively.
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

-- Generic `updated_at` bumper (0003), attached to every table that has the column.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- AUTH / PROFILE
-- ----------------------------------------------------------------------------

-- handle_new_auth_user — final version: 0016 (0003 -> 0008 -> 0014 -> 0016)
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

-- ensure_role_subrow — final version: 0014 (0008 -> 0014)
create or replace function public.ensure_role_subrow()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  begin
    if new.role = 'vendor' then
      insert into public.vendors (profile_id, business_name, status)
      values (new.id, nullif(new.full_name, ''), 'pending')
      on conflict (profile_id) do nothing;

    elsif new.role = 'rider' then
      insert into public.riders (profile_id, status)
      values (new.id, 'offline')
      on conflict (profile_id) do nothing;

    elsif new.role = 'customer' then
      -- Retry with a longer slug once, in the astronomically unlikely
      -- case the first 8-hex slice collides with an existing referral.
      begin
        insert into public.customers (profile_id, referral_code)
        values (
          new.id,
          upper(substr(replace(new.id::text, '-', ''), 1, 8))
        )
        on conflict (profile_id) do nothing;
      exception when unique_violation then
        insert into public.customers (profile_id, referral_code)
        values (
          new.id,
          upper(substr(replace(new.id::text, '-', ''), 1, 12))
        )
        on conflict (profile_id) do nothing;
      end;
    end if;
  exception when others then
    -- Never let a sub-row failure abort the auth transaction or a
    -- profile update. The client-side `_fetchOrBootstrapProfile` and
    -- the `completeProfile` flow both create the sub-row on demand.
    raise warning
      'ensure_role_subrow: sub-row insert failed for % (role=%): %',
      new.id, new.role, sqlerrm;
  end;

  return new;
end;
$$;

-- resolve_pin_login (0016) — lookup customer by PIN, return phone
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

-- finalize_customer_account (0016) — vendor creates a customer (confirms
-- email, writes profile + customer rows) after the throwaway client signs up.
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

-- auto_confirm_user (0018) — called immediately after signUp() so the user
-- can sign in without clicking an email link.
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

-- create_pin_customer — final version: 0030 (0018 -> 0019 -> 0030). Sets all
-- auth token columns to '' to avoid GoTrue's "Database error querying
-- schema", and additionally (0030) detects and sets is_sso_user/is_anonymous
-- when those columns exist on the target Supabase instance's auth.users
-- (newer GoTrue versions require them non-null).
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

-- create_email_user — final version: 0030 (0018 -> 0019 -> 0030). Same auth
-- token + is_sso_user/is_anonymous handling as create_pin_customer above.
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

-- ----------------------------------------------------------------------------
-- RIDER LINKING / APPROVAL
-- ----------------------------------------------------------------------------

-- link_rider_to_vendor (0009) — vendor "claims" a self-registered rider by phone.
create or replace function public.link_rider_to_vendor(p_rider_phone text)
returns public.riders
language plpgsql
security definer
as $$
declare
  v_vendor_id uuid;
  v_rider public.riders;
begin
  select id into v_vendor_id from public.vendors where profile_id = auth.uid();
  if v_vendor_id is null then
    raise exception 'Only a vendor account can link riders';
  end if;

  select r.* into v_rider
  from public.riders r
  join public.profiles p on p.id = r.profile_id
  where p.phone = p_rider_phone and p.role = 'rider';

  if v_rider.id is null then
    raise exception 'No rider account found with that phone number';
  end if;

  if v_rider.vendor_id is not null and v_rider.vendor_id != v_vendor_id then
    raise exception 'This rider is already linked to another vendor';
  end if;

  update public.riders
    set vendor_id = v_vendor_id, updated_at = now()
    where id = v_rider.id
    returning * into v_rider;

  insert into public.audit_logs (actor_profile_id, action, entity_type, entity_id)
  values (auth.uid(), 'link_rider_to_vendor', 'riders', v_rider.id);

  return v_rider;
end;
$$;

-- approve_rider (0021) — owning vendor flips a pending rider's profile active.
create or replace function public.approve_rider(p_rider_id uuid)
returns public.riders
language plpgsql
security definer
as $$
declare
  v_vendor_id uuid;
  v_rider public.riders;
begin
  select id into v_vendor_id from public.vendors where profile_id = auth.uid();
  if v_vendor_id is null then
    raise exception 'Only a vendor account can approve riders';
  end if;

  select * into v_rider from public.riders where id = p_rider_id;
  if v_rider.id is null then
    raise exception 'Rider not found';
  end if;

  if v_rider.vendor_id is null or v_rider.vendor_id != v_vendor_id then
    raise exception 'This rider is not linked to your business';
  end if;

  update public.profiles
    set is_active = true, updated_at = now()
    where id = v_rider.profile_id;

  insert into public.audit_logs (actor_profile_id, action, entity_type, entity_id)
  values (auth.uid(), 'approve_rider', 'riders', v_rider.id);

  return v_rider;
end;
$$;

-- reject_rider (0021) — unlink a pending rider from this vendor.
create or replace function public.reject_rider(p_rider_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_vendor_id uuid;
  v_rider public.riders;
begin
  select id into v_vendor_id from public.vendors where profile_id = auth.uid();
  if v_vendor_id is null then
    raise exception 'Only a vendor account can reject riders';
  end if;

  select * into v_rider from public.riders where id = p_rider_id;
  if v_rider.id is null then
    raise exception 'Rider not found';
  end if;

  if v_rider.vendor_id is null or v_rider.vendor_id != v_vendor_id then
    raise exception 'This rider is not linked to your business';
  end if;

  update public.riders
    set vendor_id = null, updated_at = now()
    where id = v_rider.id;

  insert into public.audit_logs (actor_profile_id, action, entity_type, entity_id)
  values (auth.uid(), 'reject_rider', 'riders', v_rider.id);
end;
$$;

-- unlink_rider (0022) — unlink an already-approved rider from this vendor.
create or replace function public.unlink_rider(p_rider_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_vendor_id uuid;
  v_rider public.riders;
begin
  select id into v_vendor_id from public.vendors where profile_id = auth.uid();
  if v_vendor_id is null then
    raise exception 'Only a vendor account can unlink riders';
  end if;

  select * into v_rider from public.riders where id = p_rider_id;
  if v_rider.id is null then
    raise exception 'Rider not found';
  end if;

  if v_rider.vendor_id is null or v_rider.vendor_id != v_vendor_id then
    raise exception 'This rider is not linked to your business';
  end if;

  update public.riders
    set vendor_id = null, updated_at = now()
    where id = v_rider.id;

  insert into public.audit_logs (actor_profile_id, action, entity_type, entity_id)
  values (auth.uid(), 'unlink_rider', 'riders', v_rider.id);
end;
$$;

-- ----------------------------------------------------------------------------
-- VENDOR CUSTOMERS
-- ----------------------------------------------------------------------------

-- get_vendor_customers — final version: 0027 (0022 -> 0023 -> 0025 -> 0027).
-- Reads orders.outstanding_amount directly instead of recomputing (0027
-- fix: recomputing couldn't see refund-driven forgiveness of an order's debt).
create or replace function public.get_vendor_customers(p_vendor_id uuid)
returns json[]
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller_vendor_id uuid;
  v_results json[];
begin
  select id into v_caller_vendor_id
  from public.vendors
  where id = p_vendor_id and profile_id = auth.uid();

  if v_caller_vendor_id is null then
    raise exception 'Not authorized';
  end if;

  select array_agg(
    json_build_object(
      'id', c.id,
      'profile_id', c.profile_id,
      'full_name', p.full_name,
      'phone', p.phone,
      'email', p.email,
      'pin', c.pin,
      'referral_code', c.referral_code,
      'total_orders', coalesce(
        (select count(*) from public.orders o where o.customer_profile_id = c.profile_id and o.vendor_id = p_vendor_id),
        0
      ),
      'outstanding', coalesce(
        (select sum(o.outstanding_amount)
         from public.orders o
         where o.customer_profile_id = c.profile_id
           and o.vendor_id = p_vendor_id
           and o.status not in ('cancelled','rejected')),
        0
      ),
      'available_credit', coalesce(
        (select w.balance from public.wallets w where w.profile_id = c.profile_id),
        0
      ),
      'address', (
        select a.full_address
        from public.addresses a
        where a.customer_profile_id = c.profile_id
        order by a.is_default desc, a.created_at asc
        limit 1
      ),
      'created_at', p.created_at
    )
  )
  into v_results
  from public.customers c
  join public.profiles p on p.id = c.profile_id
  where c.vendor_id = p_vendor_id;

  return coalesce(v_results, '{}');
end;
$$;

-- reset_customer_pin (0031) — vendor resets the login PIN for one of their
-- own customers. Updates both the auth password hash (the PIN doubles as
-- the customer's Supabase Auth password, see create_pin_customer above) and
-- public.customers.pin, which the vendor UI displays.
create or replace function public.reset_customer_pin(
  p_vendor_id uuid,
  p_customer_profile_id uuid,
  p_new_pin text
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller_vendor_id uuid;
  v_customer_profile_id uuid;
begin
  select id into v_caller_vendor_id
  from public.vendors
  where id = p_vendor_id and profile_id = auth.uid();

  if v_caller_vendor_id is null then
    raise exception 'Not authorized';
  end if;

  select profile_id into v_customer_profile_id
  from public.customers
  where profile_id = p_customer_profile_id and vendor_id = p_vendor_id;

  if v_customer_profile_id is null then
    return false;
  end if;

  if p_new_pin is null or length(p_new_pin) <> 6 then
    raise exception 'PIN must be 6 digits';
  end if;

  update auth.users
  set encrypted_password = extensions.crypt(p_new_pin, extensions.gen_salt('bf')),
      updated_at = now()
  where id = v_customer_profile_id;

  update public.customers
  set pin = p_new_pin
  where profile_id = v_customer_profile_id;

  return true;
end;
$$;

-- ----------------------------------------------------------------------------
-- ORDER LIFECYCLE
-- ----------------------------------------------------------------------------

-- generate_order_number (0003) — human-friendly sequential order number.
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

-- log_order_status_change (0003) — append a tracking_logs row on any status change.
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

-- notify_order_status_change (0003) — push a notifications row on order changes.
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

-- sync_rider_location (0003) — keep riders.current_location in sync for admin heat-maps.
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

-- sync_lat_lng_to_geography (0005) — keep geography(Point,4326) columns in
-- sync with the plain lat/lng doubles the Flutter client actually writes.
create or replace function public.sync_lat_lng_to_geography()
returns trigger
language plpgsql
as $$
begin
  if new.lat is not null and new.lng is not null then
    if tg_table_name = 'addresses' then
      new.location := ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)::geography;
    elsif tg_table_name = 'vendors' then
      new.location := ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)::geography;
    elsif tg_table_name = 'riders' then
      new.current_location := ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)::geography;
    elsif tg_table_name = 'realtime_locations' then
      new.location := ST_SetSRID(ST_MakePoint(new.lng, new.lat), 4326)::geography;
    end if;
  end if;
  return new;
end;
$$;

-- place_order (0006) — atomic order + order_items creation.
create or replace function public.place_order(
  p_address_id uuid,
  p_vendor_id uuid,
  p_items jsonb, -- [{ "product_id": uuid, "quantity": int, "unit_price": numeric, "unit_deposit": numeric }]
  p_payment_method payment_method default 'cod',
  p_is_emergency boolean default false,
  p_coupon_id uuid default null,
  p_discount_amount numeric default 0,
  p_delivery_fee numeric default 0,
  p_scheduled_for timestamptz default null
)
returns public.orders
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_item jsonb;
  v_subtotal numeric := 0;
  v_deposit_total numeric := 0;
  v_customer_id uuid := auth.uid();
begin
  if v_customer_id is null then
    raise exception 'Not authenticated';
  end if;

  if jsonb_array_length(p_items) = 0 then
    raise exception 'Cannot place an order with no items';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_subtotal := v_subtotal + ((v_item->>'unit_price')::numeric * (v_item->>'quantity')::int);
    v_deposit_total := v_deposit_total + ((v_item->>'unit_deposit')::numeric * (v_item->>'quantity')::int);
  end loop;

  insert into public.orders (
    customer_profile_id, vendor_id, address_id, status, is_emergency,
    subtotal, deposit_total, discount_amount, delivery_fee, total_amount,
    coupon_id, payment_method, payment_status, scheduled_for
  ) values (
    v_customer_id, p_vendor_id, p_address_id, 'pending', p_is_emergency,
    v_subtotal, v_deposit_total, p_discount_amount, p_delivery_fee,
    (v_subtotal + v_deposit_total + p_delivery_fee - p_discount_amount),
    p_coupon_id, p_payment_method,
    case when p_payment_method = 'cod' then 'pending' else 'pending' end,
    p_scheduled_for
  )
  returning * into v_order;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (order_id, product_id, quantity, unit_price, unit_deposit)
    values (
      v_order.id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::int,
      (v_item->>'unit_price')::numeric,
      (v_item->>'unit_deposit')::numeric
    );

    update public.products
      set stock_quantity = greatest(stock_quantity - (v_item->>'quantity')::int, 0)
      where id = (v_item->>'product_id')::uuid;
  end loop;

  if p_coupon_id is not null then
    update public.coupons set used_count = used_count + 1 where id = p_coupon_id;
  end if;

  return v_order;
end;
$$;

-- generate_delivery_otp (0010) — generate a 4-digit handoff code on rider assignment.
create or replace function public.generate_delivery_otp()
returns trigger
language plpgsql
as $$
begin
  if new.rider_id is not null and (old.rider_id is null or old.rider_id != new.rider_id) and new.rider_otp is null then
    new.rider_otp := lpad(floor(random() * 10000)::text, 4, '0');
  end if;
  return new;
end;
$$;

-- verify_delivery_otp (0010) — original full delivery-completion RPC (no
-- payment recording). complete_delivery_with_payment (0024) is the payment-
-- aware version used by the current app flow; this one is left intact.
create or replace function public.verify_delivery_otp(p_order_id uuid, p_entered_otp text)
returns public.orders
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_rider_profile_id uuid;
begin
  select o.* into v_order from public.orders o where o.id = p_order_id;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_order.rider_id;
  if v_rider_profile_id is null or v_rider_profile_id != auth.uid() then
    raise exception 'You are not the assigned rider for this order';
  end if;

  if v_order.status not in ('assigned', 'picked_up', 'on_the_way') then
    raise exception 'This order is not ready to be completed';
  end if;

  if v_order.rider_otp is distinct from p_entered_otp then
    raise exception 'Incorrect delivery code — ask the customer to confirm it';
  end if;

  update public.orders
    set status = 'delivered', delivered_at = now()
    where id = p_order_id
    returning * into v_order;

  update public.riders
    set total_deliveries = total_deliveries + 1
    where id = v_order.rider_id;

  return v_order;
end;
$$;

-- zero_outstanding_on_cancel (0026) — zero out outstanding_amount whenever
-- an order lands in cancelled/rejected.
create or replace function public.zero_outstanding_on_cancel()
returns trigger
language plpgsql
security definer
as $$
begin
  if NEW.status in ('cancelled', 'rejected') then
    NEW.outstanding_amount := 0;
  end if;
  return NEW;
end;
$$;

-- ----------------------------------------------------------------------------
-- RATINGS (0013)
-- ----------------------------------------------------------------------------
create or replace function public.recompute_rating_aggregates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider_id uuid := coalesce(new.rated_rider_id, old.rated_rider_id);
  v_vendor_id uuid := coalesce(new.rated_vendor_id, old.rated_vendor_id);
begin
  if v_rider_id is not null then
    update public.riders r
    set rating = coalesce((
      select round(avg(stars)::numeric, 1)
      from public.ratings
      where rated_rider_id = v_rider_id
    ), 5.0)
    where r.id = v_rider_id;
  end if;

  if v_vendor_id is not null then
    update public.vendors v
    set rating = coalesce((
      select round(avg(stars)::numeric, 1)
      from public.ratings
      where rated_vendor_id = v_vendor_id
    ), 5.0)
    where v.id = v_vendor_id;
  end if;

  return null;
end;
$$;

create or replace function public.has_rated_order(p_order_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ratings
    where order_id = p_order_id
      and rater_profile_id = auth.uid()
  );
$$;

-- ----------------------------------------------------------------------------
-- WALLET (0003)
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

-- ----------------------------------------------------------------------------
-- COD SETTLEMENTS
-- ----------------------------------------------------------------------------

-- generate_cod_settlement — final version: 0024 (0015 -> 0024; enriched with
-- order_count/transaction_count/total_cash_collected snapshot columns).
create or replace function public.generate_cod_settlement(
  p_rider_id uuid,
  p_vendor_id uuid,
  p_amount numeric
)
returns json
language plpgsql
security definer
as $$
declare
  v_code text;
  v_id uuid;
  v_outstanding numeric;
  v_collected numeric;
  v_txn_count int;
  v_order_count int;
begin
  loop
    v_code := lpad((floor(random() * 1000000))::text, 6, '0');
    exit when not exists (
      select 1 from public.cod_settlements where code = v_code and status = 'pending'
    );
  end loop;

  -- Snapshot the rider's collected cash + counts for this vendor
  select coalesce(sum(t.amount),0), count(*), count(distinct t.order_id)
  into v_collected, v_txn_count, v_order_count
  from public.payment_transactions t
  where t.rider_id = p_rider_id and t.vendor_id = p_vendor_id
    and t.status = 'active' and t.settled = false
    and t.payment_type in ('full','partial','over');

  insert into public.cod_settlements (
    rider_id, vendor_id, amount, code,
    order_count, transaction_count, total_cash_collected, generated_by
  )
  values (
    p_rider_id, p_vendor_id, p_amount, v_code,
    coalesce(v_order_count,0), coalesce(v_txn_count,0), coalesce(v_collected,0), auth.uid()
  )
  returning id into v_id;

  select coalesce(sum(case when status = 'pending' then amount else 0 end), 0)
  into v_outstanding
  from public.cod_settlements
  where rider_id = p_rider_id and vendor_id = p_vendor_id and status = 'pending';

  return json_build_object(
    'id', v_id,
    'code', v_code,
    'amount', p_amount,
    'outstanding_after', v_outstanding
  );
end;
$$;

-- verify_cod_settlement — final version: 0032 (0015 -> 0024 -> 0032).
-- 0032 fix: previously flipped EVERY currently-unsettled payment_transaction
-- to settled=true regardless of whether the verified amount actually
-- covered them — a rider submitting a partial cash amount (the app's
-- "Submit Cash" screen explicitly allows less than the full outstanding
-- balance) would have their entire unsettled balance silently marked
-- settled and mis-tagged against that one (smaller) settlement, corrupting
-- the settlement-detail audit trail and hiding the uncovered remainder from
-- every future settlement's snapshot. Now only flips the oldest
-- transactions fully covered by the verified amount (whole-transaction
-- units — a single row has no partially-settled state), leaving the rest
-- correctly unsettled for the next settlement.
create or replace function public.verify_cod_settlement(
  p_code text,
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_settlement record;
  v_rider_name text;
  v_outstanding_before numeric;
  v_outstanding_after numeric;
  v_txn_count int;
  v_order_count int;
  v_remaining numeric;
  v_txn record;
begin
  select * into v_settlement
  from public.cod_settlements
  where code = p_code and vendor_id = p_vendor_id and status = 'pending' and expires_at > now();

  if v_settlement is null then
    raise exception 'Invalid or expired settlement code' using errcode = 'P0001';
  end if;

  select coalesce(sum(amount), 0) into v_outstanding_before
  from public.cod_settlements
  where rider_id = v_settlement.rider_id and vendor_id = p_vendor_id and status = 'pending';

  -- Only flip the oldest transactions the verified amount fully covers.
  v_remaining := v_settlement.amount;
  for v_txn in
    select id, amount from public.payment_transactions
    where rider_id = v_settlement.rider_id and vendor_id = p_vendor_id
      and status = 'active' and settled = false
      and payment_type in ('full', 'partial', 'over')
    order by created_at asc
    for update
  loop
    exit when v_remaining < v_txn.amount;
    update public.payment_transactions
      set settled = true, settlement_id = v_settlement.id, updated_at = now()
      where id = v_txn.id;
    v_remaining := v_remaining - v_txn.amount;
  end loop;

  select count(*), count(distinct order_id) into v_txn_count, v_order_count
  from public.payment_transactions where settlement_id = v_settlement.id;

  update public.cod_settlements
  set status = 'verified',
      verified_at = now(),
      verified_by = auth.uid(),
      transaction_count = coalesce(v_txn_count,0),
      order_count = coalesce(v_order_count,0),
      total_cash_settled = v_settlement.amount,
      cash_difference = coalesce(total_cash_collected,0) - v_settlement.amount,
      outstanding_remaining = greatest(v_outstanding_before - v_settlement.amount, 0)
  where id = v_settlement.id;

  v_outstanding_after := v_outstanding_before - v_settlement.amount;

  select p.full_name into v_rider_name
  from public.riders r join public.profiles p on p.id = r.profile_id
  where r.id = v_settlement.rider_id;

  return json_build_object(
    'settlement_id', v_settlement.id,
    'rider_name', coalesce(v_rider_name, 'Unknown Rider'),
    'amount', v_settlement.amount,
    'created_at', v_settlement.created_at,
    'outstanding_before', v_outstanding_before,
    'outstanding_after', v_outstanding_after
  );
end;
$$;

-- get_rider_cod_balance — final version: 0033 (0015 -> 0026 -> 0027 ->
-- 0033). Since 0027 made refunds purely additive (they no longer mutate the
-- original transaction's amount), 'refund' rows must be netted out here
-- explicitly to compute true collected cash. 0033 fix: the legacy fallback
-- fired whenever the transaction sum was <= 0, which now happens
-- legitimately (a delivery collecting Rs. 0 writes a zero-amount row) and
-- would then report phantom cash straight off the orders table — it now
-- keys off the ABSENCE of transactions instead.
create or replace function public.get_rider_cod_balance(
  p_rider_id uuid,
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_outstanding numeric := 0;
  v_pending numeric := 0;
  v_total_submitted numeric := 0;
  v_total_verified numeric := 0;
  v_total_collected numeric := 0;
begin
  -- Settlements created by rider
  select
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0),
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0),
    coalesce(sum(amount), 0),
    coalesce(sum(case when status = 'verified' then amount else 0 end), 0)
  into v_pending, v_outstanding, v_total_submitted, v_total_verified
  from public.cod_settlements
  where rider_id = p_rider_id and vendor_id = p_vendor_id;

  -- Net cash collected: full/partial/over payments minus refunds. Original
  -- transactions are immutable, so refunds must be subtracted explicitly —
  -- they are no longer already "baked into" a reduced original amount.
  select coalesce(
    sum(case when payment_type = 'refund' then -amount else amount end), 0
  ) into v_total_collected
  from public.payment_transactions
  where rider_id = p_rider_id
    and vendor_id = p_vendor_id
    and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund');

  -- Legacy fallback for pre-payment-transactions data. Must key off the
  -- ABSENCE of transactions, not a <= 0 sum: a delivery that collected
  -- nothing legitimately writes a zero-amount row, and the old condition
  -- would then report phantom cash straight off the orders table.
  if not exists (
    select 1 from public.payment_transactions
    where rider_id = p_rider_id and vendor_id = p_vendor_id and status = 'active'
  ) then
    select coalesce(sum(coalesce(amount_paid, total_amount)), 0) into v_total_collected
    from public.orders
    where vendor_id = p_vendor_id
      and rider_id = p_rider_id
      and status in ('delivered', 'completed')
      and payment_method = 'cod';
  end if;

  v_outstanding := greatest(v_total_collected - v_total_verified, 0);

  return json_build_object(
    'outstanding', v_outstanding,
    'pending', v_pending,
    'total_submitted', v_total_submitted,
    'total_verified', v_total_verified,
    'total_collected', v_total_collected
  );
end;
$$;

-- get_vendor_cod_summary (0015) — only ever defined once.
create or replace function public.get_vendor_cod_summary(
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
as $$
declare
  v_todays_verified numeric;
  v_total_verified numeric;
  v_pending_count int;
  v_pending_amount numeric;
  v_today_start timestamptz;
begin
  v_today_start := date_trunc('day', now());

  select
    coalesce(sum(case when status = 'verified' and verified_at >= v_today_start then amount else 0 end), 0),
    coalesce(sum(case when status = 'verified' then amount else 0 end), 0),
    count(case when status = 'pending' then 1 end),
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0)
  into v_todays_verified, v_total_verified, v_pending_count, v_pending_amount
  from public.cod_settlements
  where vendor_id = p_vendor_id;

  return json_build_object(
    'todays_verified', v_todays_verified,
    'total_verified', v_total_verified,
    'pending_count', v_pending_count,
    'pending_amount', v_pending_amount
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- PAYMENT MANAGEMENT
-- ----------------------------------------------------------------------------

-- order_outstanding (0024) — compute an order's outstanding (whole rupees).
create or replace function public.order_outstanding(p_order_id uuid)
returns numeric
language sql
stable
as $$
  select greatest(
    round(coalesce(o.total_amount,0))
      - coalesce(o.amount_paid,0)
      - coalesce(o.credit_applied,0),
    0
  )
  from public.orders o where o.id = p_order_id;
$$;

-- verify_delivery_pin_only (0024) — validate handoff code, NO state change.
create or replace function public.verify_delivery_pin_only(
  p_order_id uuid,
  p_entered_otp text
)
returns boolean
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_rider_profile_id uuid;
begin
  select o.* into v_order from public.orders o where o.id = p_order_id;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_order.rider_id;
  if v_rider_profile_id is null or v_rider_profile_id != auth.uid() then
    raise exception 'You are not the assigned rider for this order';
  end if;

  if v_order.status not in ('assigned','picked_up','on_the_way') then
    raise exception 'This order is not ready to be completed';
  end if;

  if v_order.rider_otp is distinct from p_entered_otp then
    raise exception 'Incorrect delivery code — ask the customer to confirm it';
  end if;

  return true;
end;
$$;

-- complete_delivery_with_payment — final version: 0033 (0024 -> 0033).
-- Records payment + marks delivered ATOMICALLY. 0033 fix: over-payment used
-- to go straight to wallet credit even while the customer still owed money
-- on other orders; it now FIFO-clears their other outstanding orders first
-- and only the true leftover becomes credit.
--
-- Cash-integrity note: each rupee tendered is recorded by EXACTLY ONE
-- payment_transactions row. Pre-0033 the primary row stored the whole
-- tendered amount; adding reallocation rows on top of that would have
-- double-counted the same cash in every collection total. The tender is
-- therefore split across rows — primary row = applied to THIS order, one row
-- per other order the excess cleared, one 'over' row = leftover credited to
-- the wallet — so SUM(rows) == amount tendered. This also repairs
-- `credits_issued`, which used to sum the whole tendered amount of every
-- over-payment instead of just the credited excess.
create or replace function public.complete_delivery_with_payment(
  p_order_id uuid,
  p_entered_otp text,
  p_amount numeric,
  p_receipt_url text default null,
  p_receipt_meta jsonb default '{}'::jsonb,
  p_notes text default null
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_order public.orders;
  v_rider_profile_id uuid;
  v_outstanding numeric;
  v_credit_before numeric;
  v_credit_after numeric;
  v_applied numeric;          -- applied to THIS order
  v_excess numeric;           -- tendered beyond this order's outstanding
  v_remaining_excess numeric; -- excess still unallocated
  v_debt_cleared numeric := 0;
  v_pay_type text;
  v_txn_id uuid;
  v_amount numeric := round(coalesce(p_amount, 0));
  v_other record;
  v_apply numeric;
  v_other_before numeric;
  v_other_after numeric;
  v_other_txn_id uuid;
  v_order_number text;
begin
  -- Lock the order row to prevent double completion / races
  select o.* into v_order from public.orders o where o.id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_order.rider_id;
  if v_rider_profile_id is null or v_rider_profile_id != auth.uid() then
    raise exception 'You are not the assigned rider for this order';
  end if;

  if v_order.status = 'delivered' or v_order.status = 'completed' then
    raise exception 'This order has already been completed';
  end if;

  if v_order.status not in ('assigned','picked_up','on_the_way') then
    raise exception 'This order is not ready to be completed';
  end if;

  if v_order.rider_otp is distinct from p_entered_otp then
    raise exception 'Incorrect delivery code — ask the customer to confirm it';
  end if;

  if v_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  end if;

  v_outstanding := public.order_outstanding(p_order_id);
  v_applied := least(v_amount, v_outstanding);
  v_excess := greatest(v_amount - v_outstanding, 0);

  select coalesce(balance, 0) into v_credit_before
  from public.wallets where profile_id = v_order.customer_profile_id;
  v_credit_before := coalesce(v_credit_before, 0);

  -- Update the order: paid + delivered
  update public.orders
    set amount_paid = coalesce(amount_paid,0) + v_applied,
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - (coalesce(amount_paid,0) + v_applied) - coalesce(credit_applied,0), 0),
        payment_status = case
          when greatest(round(coalesce(total_amount,0)) - (coalesce(amount_paid,0) + v_applied) - coalesce(credit_applied,0), 0) = 0
            then 'paid'::payment_status
          else payment_status
        end,
        status = 'delivered',
        delivered_at = now(),
        updated_at = now()
    where id = p_order_id
    returning * into v_order;

  v_order_number := v_order.order_number;

  update public.riders set total_deliveries = total_deliveries + 1 where id = v_order.rider_id;

  -- Classify THIS order's payment. 'over' is no longer used here: genuine
  -- excess gets its own dedicated row further down.
  if v_amount = 0 then
    v_pay_type := 'partial';
  elsif v_applied >= v_outstanding then
    v_pay_type := 'full';
  else
    v_pay_type := 'partial';
  end if;

  -- Primary transaction — records ONLY what this order absorbed.
  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by
  ) values (
    p_order_id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_applied,
    v_outstanding, greatest(v_outstanding - v_applied, 0), v_credit_before, v_credit_before,
    v_pay_type, p_notes, auth.uid()
  ) returning id into v_txn_id;

  -- Excess clears the customer's OTHER outstanding orders first (FIFO).
  v_remaining_excess := v_excess;
  if v_remaining_excess > 0 then
    for v_other in
      select * from public.orders
      where customer_profile_id = v_order.customer_profile_id
        and vendor_id = v_order.vendor_id
        and id <> p_order_id
        and status not in ('cancelled', 'rejected')
        and coalesce(outstanding_amount, 0) > 0
      order by created_at asc
      for update
    loop
      exit when v_remaining_excess <= 0;

      v_other_before := coalesce(v_other.outstanding_amount, 0);
      v_apply := least(v_remaining_excess, v_other_before);
      v_other_after := greatest(v_other_before - v_apply, 0);

      update public.orders
        set amount_paid = coalesce(amount_paid, 0) + v_apply,
            outstanding_amount = v_other_after,
            payment_status = case when v_other_after = 0 then 'paid'::payment_status else 'partial'::payment_status end,
            updated_at = now()
        where id = v_other.id;

      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by
      ) values (
        v_other.id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_apply,
        v_other_before, v_other_after, v_credit_before, v_credit_before,
        'full',
        'Overpayment from order #' || coalesce(v_order_number, '') || ' applied to outstanding balance',
        auth.uid()
      ) returning id into v_other_txn_id;

      insert into public.payment_audit_logs (
        payment_transaction_id, action, old_amount, new_amount, reason, performed_by
      ) values (
        v_other_txn_id, 'collect_pending', v_other_before, v_other_after,
        'Debt cleared via overpayment reallocation', auth.uid()
      );

      v_debt_cleared := v_debt_cleared + v_apply;
      v_remaining_excess := v_remaining_excess - v_apply;
    end loop;
  end if;

  -- Only what survives every outstanding debt becomes wallet credit.
  if v_remaining_excess > 0 then
    perform public.adjust_wallet_balance(
      v_order.customer_profile_id, v_remaining_excess, 'credit', p_order_id, 'Overpayment credit'
    );
    v_credit_after := v_credit_before + v_remaining_excess;

    insert into public.payment_transactions (
      order_id, customer_profile_id, rider_id, vendor_id, amount,
      outstanding_before, outstanding_after, credit_before, credit_after,
      payment_type, notes, created_by
    ) values (
      p_order_id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_remaining_excess,
      0, 0, v_credit_before, v_credit_after,
      'over', 'Overpayment credited to wallet', auth.uid()
    );
  else
    v_credit_after := v_credit_before;
  end if;

  -- Optional receipt
  if p_receipt_url is not null and length(trim(p_receipt_url)) > 0 then
    insert into public.payment_receipts (
      payment_transaction_id, vendor_id, receipt_type, receipt_url,
      image_hash, gps_lat, gps_lng, device_time, uploaded_by
    ) values (
      v_txn_id, v_order.vendor_id,
      coalesce(p_receipt_meta->>'receipt_type', 'cash'),
      p_receipt_url,
      p_receipt_meta->>'image_hash',
      (p_receipt_meta->>'gps_lat')::numeric,
      (p_receipt_meta->>'gps_lng')::numeric,
      (p_receipt_meta->>'device_time')::timestamptz,
      auth.uid()
    );
  end if;

  insert into public.payment_audit_logs (payment_transaction_id, action, new_amount, reason, performed_by)
  values (v_txn_id, 'create', v_amount, 'Delivery payment collected', auth.uid());

  return json_build_object(
    'transaction_id', v_txn_id,
    'order_id', p_order_id,
    'amount', v_amount,
    'applied', v_applied,
    'debt_cleared', v_debt_cleared,
    'excess_credit', greatest(v_remaining_excess, 0),
    'outstanding_after', greatest(v_outstanding - v_applied, 0),
    'credit_after', v_credit_after,
    'payment_type', v_pay_type
  );
end;
$$;

-- edit_payment — final version: 0027 (0024 -> 0027; guards against editing
-- a transaction that already has a refund recorded against it).
create or replace function public.edit_payment(
  p_transaction_id uuid,
  p_new_amount numeric,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_order public.orders;
  v_new numeric := round(coalesce(p_new_amount, 0));
  v_delta numeric;
  v_rider_profile_id uuid;
  v_already_refunded numeric := 0;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id for update;
  if v_txn.id is null then raise exception 'Payment not found'; end if;
  if v_txn.status = 'deleted' then raise exception 'Payment already deleted'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can edit this payment';
  end if;

  if v_txn.settled then
    raise exception 'This payment is already settled — submit an amendment request instead';
  end if;

  select coalesce(sum(amount), 0) into v_already_refunded
  from public.payment_transactions
  where refunds_transaction_id = v_txn.id and status = 'active';
  if v_already_refunded > 0 then
    raise exception 'This payment already has a refund recorded against it — request an amendment instead';
  end if;

  if v_new < 0 then raise exception 'Amount cannot be negative'; end if;

  v_delta := v_new - v_txn.amount;

  -- Adjust the order's amount_paid by the delta (bounded by outstanding logic)
  select * into v_order from public.orders where id = v_txn.order_id for update;
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid,0) + v_delta, 0),
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) + v_delta,0) - coalesce(credit_applied,0), 0),
        updated_at = now()
    where id = v_txn.order_id;

  update public.payment_transactions
    set amount = v_new, updated_at = now()
    where id = p_transaction_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (p_transaction_id, 'edit', v_txn.amount, v_new, p_reason, auth.uid());

  return json_build_object('transaction_id', p_transaction_id, 'new_amount', v_new);
end;
$$;

-- delete_payment — final version: 0027 (0024 -> 0027; same already-refunded guard).
create or replace function public.delete_payment(
  p_transaction_id uuid,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_rider_profile_id uuid;
  v_already_refunded numeric := 0;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id for update;
  if v_txn.id is null then raise exception 'Payment not found'; end if;
  if v_txn.status = 'deleted' then raise exception 'Payment already deleted'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can delete this payment';
  end if;

  if v_txn.settled then
    raise exception 'This payment is already settled — submit an amendment request instead';
  end if;

  select coalesce(sum(amount), 0) into v_already_refunded
  from public.payment_transactions
  where refunds_transaction_id = v_txn.id and status = 'active';
  if v_already_refunded > 0 then
    raise exception 'This payment already has a refund recorded against it — request an amendment instead';
  end if;

  -- Reverse the order effect
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid,0) - v_txn.amount, 0),
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) - v_txn.amount,0) - coalesce(credit_applied,0), 0),
        payment_status = 'pending'::payment_status,
        updated_at = now()
    where id = v_txn.order_id;

  update public.payment_transactions
    set status = 'deleted', updated_at = now()
    where id = p_transaction_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (p_transaction_id, 'delete', v_txn.amount, 0, p_reason, auth.uid());

  return json_build_object('transaction_id', p_transaction_id, 'status', 'deleted');
end;
$$;

-- request_payment_amendment (0024) — post-settlement edit/delete/refund request.
-- Only ever defined once (the CHECK constraint widening to include 'refund'
-- happened at the table level in 0025, not here).
create or replace function public.request_payment_amendment(
  p_transaction_id uuid,
  p_action text,
  p_amount numeric,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_rider_profile_id uuid;
  v_req_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;
  if p_action not in ('edit','delete') then
    raise exception 'Invalid amendment action';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id;
  if v_txn.id is null then raise exception 'Payment not found'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can request an amendment';
  end if;

  insert into public.payment_amendment_requests (
    payment_transaction_id, rider_id, vendor_id, requested_action, requested_amount, reason
  ) values (
    p_transaction_id, v_txn.rider_id, v_txn.vendor_id, p_action,
    case when p_action = 'edit' then round(coalesce(p_amount,0)) else null end, p_reason
  ) returning id into v_req_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (p_transaction_id, 'amend_request', v_txn.amount, round(coalesce(p_amount,0)), p_reason, auth.uid());

  return json_build_object('request_id', v_req_id, 'status', 'pending');
end;
$$;

-- resolve_payment_amendment — final version: 0029 (0024 -> 0025 -> 0026 ->
-- 0027 -> 0029). Vendor approves/rejects. Refunds are purely additive
-- (never mutate the original transaction) and delete/edit are blocked once
-- a refund is already recorded against the transaction. 0029 additionally
-- fixed a live bug: 0026 started writing review_notes/reviewed_by/updated_at
-- (added to the table in 0029) while still relying on resolved_at/resolved_by
-- for the Dart client's read side, so this version sets both column pairs.
create or replace function public.resolve_payment_amendment(
  p_request_id uuid,
  p_approve bool,
  p_review_notes text default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_req public.payment_amendment_requests;
  v_txn public.payment_transactions;
  v_vendor_profile_id uuid;
  v_refund_amount numeric;
  v_refund_txn_id uuid;
  v_delta numeric;
  v_already_refunded numeric := 0;
  v_available numeric;
begin
  select * into v_req from public.payment_amendment_requests where id = p_request_id for update;
  if v_req.id is null then raise exception 'Amendment request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'Request is already processed'; end if;

  select profile_id into v_vendor_profile_id from public.vendors where id = v_req.vendor_id;
  if v_vendor_profile_id is distinct from auth.uid() then
    raise exception 'Only the vendor can resolve this request';
  end if;

  select * into v_txn from public.payment_transactions where id = v_req.payment_transaction_id for update;

  select coalesce(sum(amount), 0) into v_already_refunded
  from public.payment_transactions
  where refunds_transaction_id = v_txn.id and status = 'active';
  v_available := v_txn.amount - v_already_refunded;

  if p_approve then
    if v_req.requested_action in ('delete', 'edit') and v_already_refunded > 0 then
      raise exception 'This payment already has a refund recorded against it and can no longer be edited or deleted directly';
    end if;

    if v_req.requested_action = 'delete' then
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_txn.amount, 0),
            outstanding_amount = 0,
            updated_at = now()
        where id = v_txn.order_id;
      update public.payment_transactions set status = 'deleted', updated_at = now() where id = v_txn.id;

    elsif v_req.requested_action = 'refund' then
      if v_available <= 0 then
        raise exception 'This payment has already been fully refunded';
      end if;
      v_refund_amount := least(round(coalesce(v_req.requested_amount, v_available)), v_available);

      -- CASH REFUND: Do NOT increase outstanding debt
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_refund_amount, 0),
            outstanding_amount = 0,
            payment_status = case when v_refund_amount >= v_available then 'refunded'::payment_status else payment_status end,
            updated_at = now()
        where id = v_txn.order_id;

      -- DO NOT add wallet credit for cash refunds!

      -- The original transaction is never mutated or marked deleted here
      -- either — see process_refund's header comment (migration 0027) for why.
      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by, refunds_transaction_id
      ) values (
        v_txn.order_id, v_txn.customer_profile_id, v_txn.rider_id, v_txn.vendor_id,
        v_refund_amount,
        0, 0,
        coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0),
        coalesce((select balance from public.wallets where profile_id = v_txn.customer_profile_id), 0),
        'refund', 'Vendor-approved cash refund: ' || coalesce(v_req.reason, ''), auth.uid(), v_txn.id
      ) returning id into v_refund_txn_id;

    else -- edit
      v_delta := round(coalesce(v_req.requested_amount,0)) - v_txn.amount;
      update public.payment_transactions
        set amount = round(coalesce(v_req.requested_amount,0)), updated_at = now()
        where id = v_txn.id;

      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) + v_delta, 0),
            updated_at = now()
        where id = v_txn.order_id;
    end if;

    update public.payment_amendment_requests
      set status = 'approved',
          review_notes = p_review_notes, reviewed_by = auth.uid(), updated_at = now(),
          resolved_at = now(), resolved_by = auth.uid()
      where id = v_req.id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_approve', v_txn.amount, coalesce(v_req.requested_amount, 0), v_req.reason, auth.uid());

  else
    update public.payment_amendment_requests
      set status = 'rejected',
          review_notes = p_review_notes, reviewed_by = auth.uid(), updated_at = now(),
          resolved_at = now(), resolved_by = auth.uid()
      where id = v_req.id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_reject', v_txn.amount, v_txn.amount, p_review_notes, auth.uid());
  end if;

  return json_build_object('success', true, 'status', case when p_approve then 'approved' else 'rejected' end);
end;
$$;

-- apply_customer_credit (0024) — consume wallet credit against a new order.
-- Only ever defined once.
create or replace function public.apply_customer_credit(
  p_order_id uuid,
  p_amount numeric default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_balance numeric;
  v_outstanding numeric;
  v_apply numeric;
  v_txn_id uuid;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then raise exception 'Order not found'; end if;
  if v_order.customer_profile_id is distinct from auth.uid() then
    raise exception 'You can only apply credit to your own order';
  end if;

  select coalesce(balance,0) into v_balance from public.wallets where profile_id = v_order.customer_profile_id;
  v_balance := coalesce(v_balance, 0);
  v_outstanding := public.order_outstanding(p_order_id);

  v_apply := least(v_balance, v_outstanding);
  if p_amount is not null then
    v_apply := least(v_apply, round(p_amount));
  end if;

  if v_apply <= 0 then
    return json_build_object('applied', 0, 'outstanding_after', v_outstanding);
  end if;

  perform public.adjust_wallet_balance(
    v_order.customer_profile_id, v_apply, 'debit', p_order_id, 'Credit applied to order'
  );

  update public.orders
    set credit_applied = coalesce(credit_applied,0) + v_apply,
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - coalesce(amount_paid,0) - (coalesce(credit_applied,0) + v_apply), 0),
        updated_at = now()
    where id = p_order_id;

  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by
  ) values (
    p_order_id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_apply,
    v_outstanding, greatest(v_outstanding - v_apply, 0), v_balance, v_balance - v_apply,
    'credit', 'Wallet credit applied', auth.uid()
  ) returning id into v_txn_id;

  return json_build_object('applied', v_apply, 'outstanding_after', greatest(v_outstanding - v_apply, 0), 'transaction_id', v_txn_id);
end;
$$;

-- get_customer_ledger — final version: 0027 (0024 -> 0026 -> 0027). 0026
-- added the authorization check (originally any authenticated user could
-- pass an arbitrary customer id); 0027 nets out refunds from total_paid.
create or replace function public.get_customer_ledger(p_customer_profile_id uuid)
returns json
language plpgsql
security definer
as $$
declare
  v_total_purchases numeric;
  v_total_paid numeric;
  v_outstanding numeric;
  v_credit numeric;
  v_last_payment timestamptz;
  v_entries json;
begin
  if auth.uid() is distinct from p_customer_profile_id
    and not exists (
      select 1 from public.orders o
      join public.vendors v on v.id = o.vendor_id
      where o.customer_profile_id = p_customer_profile_id and v.profile_id = auth.uid()
    )
  then
    raise exception 'Not authorized';
  end if;

  select coalesce(sum(round(total_amount)), 0) into v_total_purchases
  from public.orders where customer_profile_id = p_customer_profile_id;

  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0) into v_total_paid
  from public.payment_transactions
  where customer_profile_id = p_customer_profile_id
    and status = 'active' and payment_type in ('full','partial','over','credit','refund');

  select coalesce(sum(outstanding_amount), 0) into v_outstanding
  from public.orders where customer_profile_id = p_customer_profile_id;

  select coalesce(balance, 0) into v_credit
  from public.wallets where profile_id = p_customer_profile_id;
  v_credit := coalesce(v_credit, 0);

  select max(created_at) into v_last_payment
  from public.payment_transactions
  where customer_profile_id = p_customer_profile_id and status = 'active';

  select json_agg(e order by e.created_at desc) into v_entries
  from (
    select t.id, t.order_id, o.order_number, t.amount, t.payment_type,
           t.outstanding_before, t.outstanding_after, t.notes, t.status, t.created_at
    from public.payment_transactions t
    join public.orders o on o.id = t.order_id
    where t.customer_profile_id = p_customer_profile_id
  ) e;

  return json_build_object(
    'total_purchases', v_total_purchases,
    'total_paid', v_total_paid,
    'outstanding', v_outstanding,
    'available_credit', v_credit,
    'last_payment_at', v_last_payment,
    'entries', coalesce(v_entries, '[]'::json)
  );
end;
$$;

-- get_settlement_detail (0024) — audit detail for one settlement. Only ever
-- defined once.
create or replace function public.get_settlement_detail(p_settlement_id uuid)
returns json
language plpgsql
security definer
as $$
declare
  v_s public.cod_settlements;
  v_rider_name text;
  v_vendor_name text;
  v_verified_by_name text;
  v_payments json;
begin
  select * into v_s from public.cod_settlements where id = p_settlement_id;
  if v_s.id is null then raise exception 'Settlement not found'; end if;

  select p.full_name into v_rider_name from public.riders r join public.profiles p on p.id = r.profile_id where r.id = v_s.rider_id;
  select business_name into v_vendor_name from public.vendors where id = v_s.vendor_id;
  select full_name into v_verified_by_name from public.profiles where id = v_s.verified_by;

  select json_agg(json_build_object(
    'id', t.id, 'order_id', t.order_id, 'amount', t.amount, 'payment_type', t.payment_type, 'created_at', t.created_at
  )) into v_payments
  from public.payment_transactions t
  where t.settlement_id = p_settlement_id and t.status = 'active';

  return json_build_object(
    'id', v_s.id,
    'code', v_s.code,
    'status', v_s.status,
    'amount', v_s.amount,
    'rider_name', coalesce(v_rider_name, 'Unknown'),
    'vendor_name', coalesce(v_vendor_name, 'Unknown'),
    'verified_by', v_verified_by_name,
    'order_count', v_s.order_count,
    'transaction_count', v_s.transaction_count,
    'total_cash_collected', v_s.total_cash_collected,
    'total_cash_settled', v_s.total_cash_settled,
    'cash_difference', v_s.cash_difference,
    'outstanding_remaining', v_s.outstanding_remaining,
    'created_at', v_s.created_at,
    'expires_at', v_s.expires_at,
    'verified_at', v_s.verified_at,
    'payments', coalesce(v_payments, '[]'::json)
  );
end;
$$;

-- get_vendor_payment_overview (0024) — per-customer financial summary rows.
-- Only ever defined once.
create or replace function public.get_vendor_payment_overview(p_vendor_id uuid)
returns json[]
language plpgsql
security definer
as $$
declare
  v_caller uuid;
  v_results json[];
begin
  select id into v_caller from public.vendors where id = p_vendor_id and profile_id = auth.uid();
  if v_caller is null then raise exception 'Not authorized'; end if;

  select array_agg(row_to_json(x)) into v_results from (
    select
      c.profile_id,
      p.full_name,
      p.phone,
      count(distinct o.id) as total_orders,
      coalesce(sum(round(o.total_amount)), 0) as total_purchases,
      coalesce(sum(o.amount_paid), 0) as total_paid,
      coalesce(sum(o.outstanding_amount), 0) as outstanding,
      coalesce((select balance from public.wallets w where w.profile_id = c.profile_id), 0) as available_credit,
      (select max(t.created_at) from public.payment_transactions t where t.customer_profile_id = c.profile_id and t.status='active') as last_payment_at,
      case
        when coalesce(sum(o.outstanding_amount),0) = 0 and count(o.id) > 0 then 'fully_paid'
        when coalesce(sum(o.amount_paid),0) > 0 then 'partially_paid'
        else 'pending'
      end as payment_status
    from public.customers c
    join public.profiles p on p.id = c.profile_id
    left join public.orders o on o.customer_profile_id = c.profile_id and o.vendor_id = p_vendor_id
    where c.vendor_id = p_vendor_id
    group by c.profile_id, p.full_name, p.phone
  ) x;

  return coalesce(v_results, '{}');
end;
$$;

-- get_vendor_rider_cash_positions — final version: 0032 (0024 -> 0032).
-- 0032 fix: `collected` now nets out 'refund' rows (parity with
-- get_rider_cod_balance/get_vendor_finance_kpis, which had this fix since
-- 0027/0028 while this function never did — the two vendor screens showing
-- rider cash positions displayed different "collected" totals for the same
-- rider whenever refunds existed). Also adds `outstanding` (collected -
-- settled, floor 0) since `pending_settlement` (sum of unverified
-- settlement codes) was being misused by the Dart client as if it were
-- this figure.
create or replace function public.get_vendor_rider_cash_positions(p_vendor_id uuid)
returns json[]
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caller uuid;
  v_results json[];
begin
  select id into v_caller from public.vendors where id = p_vendor_id and profile_id = auth.uid();
  if v_caller is null then
    raise exception 'Not authorized';
  end if;

  select array_agg(row_to_json(x)) into v_results from (
    select
      r.id as rider_id,
      p.full_name as rider_name,
      coalesce((
        select sum(case when t.payment_type = 'refund' then -t.amount else t.amount end)
        from public.payment_transactions t
        where t.rider_id = r.id and t.vendor_id = p_vendor_id and t.status = 'active'
          and t.payment_type in ('full', 'partial', 'over', 'refund')
      ), 0) as collected,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status = 'verified'
      ), 0) as settled,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status = 'pending'
      ), 0) as pending_settlement,
      greatest(
        coalesce((
          select sum(case when t.payment_type = 'refund' then -t.amount else t.amount end)
          from public.payment_transactions t
          where t.rider_id = r.id and t.vendor_id = p_vendor_id and t.status = 'active'
            and t.payment_type in ('full', 'partial', 'over', 'refund')
        ), 0)
        -
        coalesce((
          select sum(s.amount) from public.cod_settlements s
          where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status = 'verified'
        ), 0),
        0
      ) as outstanding
    from public.riders r
    join public.profiles p on p.id = r.profile_id
    where r.vendor_id = p_vendor_id
  ) x;

  return coalesce(v_results, '{}');
end;
$$;

-- get_vendor_finance_kpis — final version: 0033 (0024 -> 0026 -> 0027 ->
-- 0028 -> 0033). Dashboard KPI aggregates. 0033 fixes:
--   * adds `total_sales` (lifetime net cash collected — sales are cash
--     received, never order face value);
--   * `refunds` was missing `status = 'active'`, so deleted refunds
--     inflated it;
--   * `credits_issued` now derives from each row's wallet delta
--     (credit_after - credit_before) instead of summing the whole tendered
--     amount of every over-payment — correct for pre- and post-0033 rows;
--   * `awaiting_settlement` summed EVERY unsettled transaction with no
--     rider filter (money never held by a rider counted as "cash on the
--     road") and read the `settled` boolean, which since 0032 deliberately
--     lags on partial settlements. It is now computed per rider as
--     (collected - verified settlements) floored at zero, making it
--     rider-held cash only and tying it exactly to the sum of
--     get_vendor_rider_cash_positions.outstanding.
create or replace function public.get_vendor_finance_kpis(p_vendor_id uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today_start timestamptz := date_trunc('day', now());
  v_month_start timestamptz := date_trunc('month', now());
  v_todays_collection numeric;
  v_months_collection numeric;
  v_total_sales numeric;
  v_pending_collection numeric;
  v_outstanding_customers int;
  v_credits_issued numeric;
  v_refunds numeric;
  v_partial_count int;
  v_awaiting_settlement numeric;
begin
  if not exists (
    select 1 from public.vendors where id = p_vendor_id and profile_id = auth.uid()
    union
    select 1 from public.riders where vendor_id = p_vendor_id and profile_id = auth.uid()
  ) then
    raise exception 'Not authorized';
  end if;

  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0)
  into v_todays_collection
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund')
    and created_at >= v_today_start;

  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0)
  into v_months_collection
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund')
    and created_at >= v_month_start;

  -- Lifetime sales = every rupee actually collected, net of refunds.
  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0)
  into v_total_sales
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund');

  select coalesce(sum(outstanding_amount), 0) into v_pending_collection
  from public.orders where vendor_id = p_vendor_id and status not in ('cancelled', 'rejected');

  select count(distinct customer_profile_id) into v_outstanding_customers
  from public.orders where vendor_id = p_vendor_id and outstanding_amount > 0 and status not in ('cancelled', 'rejected');

  -- Credit actually issued = the wallet delta each row recorded, not the
  -- whole tendered amount of an over-payment (the pre-0033 bug).
  select coalesce(sum(greatest(coalesce(credit_after, 0) - coalesce(credit_before, 0), 0)), 0)
  into v_credits_issued
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active';

  select coalesce(sum(amount), 0) into v_refunds
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active' and payment_type = 'refund';

  select count(*) into v_partial_count
  from public.payment_transactions
  where vendor_id = p_vendor_id and status = 'active' and payment_type = 'partial';

  -- Cash still physically held by RIDERS: per rider, everything they
  -- collected (net of refunds) minus everything the vendor has verified
  -- receiving from them. Floored per rider so one rider's over-settlement
  -- can't mask another's shortfall. Ties exactly to the sum of
  -- get_vendor_rider_cash_positions.outstanding.
  select coalesce(sum(greatest(q.collected - q.settled, 0)), 0)
  into v_awaiting_settlement
  from (
    select
      coalesce((
        select sum(case when t.payment_type = 'refund' then -t.amount else t.amount end)
        from public.payment_transactions t
        where t.rider_id = r.id and t.vendor_id = p_vendor_id and t.status = 'active'
          and t.payment_type in ('full', 'partial', 'over', 'refund')
      ), 0) as collected,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status = 'verified'
      ), 0) as settled
    from public.riders r
    where r.vendor_id = p_vendor_id
  ) q;

  return json_build_object(
    'todays_collection', greatest(v_todays_collection, 0),
    'months_collection', greatest(v_months_collection, 0),
    'total_sales', greatest(v_total_sales, 0),
    'pending_collection', v_pending_collection,
    'outstanding_customers', v_outstanding_customers,
    'credits_issued', v_credits_issued,
    'refunds', v_refunds,
    'partial_count', v_partial_count,
    'awaiting_settlement', v_awaiting_settlement
  );
end;
$$;

-- get_customer_total_outstanding — final version: 0027 (0025 -> 0027; reads
-- orders.outstanding_amount directly instead of recomputing).
create or replace function public.get_customer_total_outstanding(
  p_customer_profile_id uuid,
  p_vendor_id uuid
)
returns numeric
language sql
stable
security definer
as $$
  select coalesce(sum(o.outstanding_amount), 0)
  from public.orders o
  where o.customer_profile_id = p_customer_profile_id
    and o.vendor_id = p_vendor_id
    and o.status not in ('cancelled','rejected');
$$;

-- process_refund — final version: 0027 (0025 -> 0026 -> 0027). Rider refunds
-- a PRE-settlement transaction. Purely additive: the original transaction's
-- `amount` is never mutated; a new 'refund' row links back to it via
-- refunds_transaction_id. FIFO-reallocates the refund to clear any other
-- outstanding debt for the same customer/vendor before returning the rest.
-- process_refund — final version: 0035 (0025 -> 0026 -> 0027 -> 0035). 0035
-- fix: adds a guard rejecting refund-of-a-refund. Previously nothing
-- checked payment_type, so an unsettled refund row (refunds are never
-- settled) passed every existing guard and could itself be "refunded" —
-- reachable from rider_order_detail_screen.dart, whose refund button was
-- gated only on isEditable (active + unsettled), which a refund row also
-- satisfies. See PaymentTransactionEntity.isRefundable on the Dart side.
create or replace function public.process_refund(
  p_transaction_id uuid,
  p_amount numeric,
  p_reason text
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_txn public.payment_transactions;
  v_rider_profile_id uuid;
  v_customer_profile_id uuid;
  v_vendor_id uuid;
  v_order_id uuid;
  v_already_refunded numeric := 0;
  v_available numeric;
  v_refund_amount numeric;
  v_refund_txn_id uuid;
  v_debt_txn_id uuid;
  v_other_outstanding numeric := 0;
  v_debt_cleared numeric := 0;
  v_amount_returned numeric := 0;
  v_order_outstanding_before numeric := 0;
  v_remaining_to_clear numeric := 0;
  v_apply numeric;
  v_order_rec record;
  v_wallet_balance numeric := 0;
  v_loop_outstanding_before numeric;
  v_loop_outstanding_after numeric;
  v_refunded_order_number text;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required for refund';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id for update;
  if v_txn.id is null then raise exception 'Payment not found'; end if;
  if v_txn.status <> 'active' then raise exception 'Only active payments can be refunded'; end if;
  if v_txn.payment_type = 'refund' then
    raise exception 'A refund cannot itself be refunded';
  end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can process a refund';
  end if;

  if v_txn.settled then
    raise exception 'This payment is already settled — request a refund amendment from the vendor instead';
  end if;

  -- How much of this ORIGINAL transaction has already been refunded
  -- (across possibly more than one prior partial refund)? The original's
  -- own `amount` never changes, so this is always computed live rather
  -- than trusted from a mutated column.
  select coalesce(sum(amount), 0) into v_already_refunded
  from public.payment_transactions
  where refunds_transaction_id = v_txn.id and status = 'active';

  v_available := v_txn.amount - v_already_refunded;
  if v_available <= 0 then
    raise exception 'This payment has already been fully refunded';
  end if;

  v_refund_amount := least(round(coalesce(p_amount, v_available)), v_available);
  if v_refund_amount <= 0 then
    raise exception 'Refund amount must be positive';
  end if;

  v_customer_profile_id := v_txn.customer_profile_id;
  v_vendor_id := v_txn.vendor_id;
  v_order_id := v_txn.order_id;

  select coalesce(balance, 0) into v_wallet_balance from public.wallets where profile_id = v_customer_profile_id;
  v_wallet_balance := coalesce(v_wallet_balance, 0);

  -- Capture this order's outstanding amount BEFORE we zero it out below
  select coalesce(outstanding_amount, 0), order_number into v_order_outstanding_before, v_refunded_order_number
  from public.orders where id = v_order_id;

  -- Get outstanding debt from OTHER orders (excluding this one being refunded)
  select coalesce(sum(outstanding_amount), 0) into v_other_outstanding
  from public.orders
  where customer_profile_id = v_customer_profile_id
    and vendor_id = v_vendor_id
    and status not in ('cancelled', 'rejected')
    and id != v_order_id;

  -- BUSINESS LOGIC:
  -- 1. First, clear other outstanding debt with the refund amount, oldest order first (FIFO)
  -- 2. Only return remaining amount to customer
  -- 3. Remove debt from this order completely (cancel the debt)

  v_debt_cleared := least(v_refund_amount, v_other_outstanding);
  v_amount_returned := v_refund_amount - v_debt_cleared;

  -- This money never actually leaves the rider's hand when it's reallocated
  -- to cover another order's debt — so that order's amount_paid must be
  -- credited (mirroring collect_pending_payment's FIFO allocation), with a
  -- matching payment_transactions row so every collected-cash total stays
  -- in sync with the orders table.
  if v_debt_cleared > 0 then
    v_remaining_to_clear := v_debt_cleared;

    for v_order_rec in
      select * from public.orders
      where customer_profile_id = v_customer_profile_id
        and vendor_id = v_vendor_id
        and status not in ('cancelled', 'rejected')
        and id != v_order_id
        and outstanding_amount > 0
      order by created_at asc
      for update
    loop
      exit when v_remaining_to_clear <= 0;

      v_apply := least(v_remaining_to_clear, v_order_rec.outstanding_amount);
      v_loop_outstanding_before := v_order_rec.outstanding_amount;
      v_loop_outstanding_after := greatest(v_loop_outstanding_before - v_apply, 0);

      update public.orders
        set amount_paid = coalesce(amount_paid, 0) + v_apply,
            outstanding_amount = v_loop_outstanding_after,
            payment_status = case when v_loop_outstanding_after = 0 then 'paid'::payment_status else payment_status end,
            updated_at = now()
        where id = v_order_rec.id;

      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by
      ) values (
        v_order_rec.id, v_customer_profile_id, v_txn.rider_id, v_vendor_id, v_apply,
        v_loop_outstanding_before, v_loop_outstanding_after, v_wallet_balance, v_wallet_balance,
        'full', 'Debt cleared via refund reallocation from order #' || coalesce(v_refunded_order_number, ''),
        auth.uid()
      ) returning id into v_debt_txn_id;

      insert into public.payment_audit_logs (
        payment_transaction_id, action, old_amount, new_amount, reason, performed_by
      ) values (
        v_debt_txn_id, 'collect_pending', v_loop_outstanding_before, v_loop_outstanding_after,
        'Outstanding balance cleared via refund reallocation', auth.uid()
      );

      v_remaining_to_clear := v_remaining_to_clear - v_apply;
    end loop;
  end if;

  -- For this order: remove the paid amount and clear its own debt (the
  -- debt for this order is cancelled/forgiven, not carried forward).
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid, 0) - v_refund_amount, 0),
        outstanding_amount = 0,
        payment_status = case when v_refund_amount >= v_available then 'refunded'::payment_status else payment_status end,
        updated_at = now()
    where id = v_order_id;

  -- The ORIGINAL transaction is never mutated — its `amount` permanently
  -- records the true amount actually collected at the time. This refund
  -- row is the only record of money moving back out, linked via
  -- refunds_transaction_id so future refund attempts against the same
  -- original correctly see how much remains available.
  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by, refunds_transaction_id
  ) values (
    v_txn.order_id, v_txn.customer_profile_id, v_txn.rider_id, v_txn.vendor_id,
    v_refund_amount,
    v_other_outstanding + v_order_outstanding_before,
    v_other_outstanding - v_debt_cleared,
    v_wallet_balance,
    v_wallet_balance,
    'refund', coalesce(p_reason, 'Rider cash refund'), auth.uid(), v_txn.id
  ) returning id into v_refund_txn_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (v_txn.id, 'refund', v_txn.amount, v_available - v_refund_amount, p_reason, auth.uid());

  return json_build_object(
    'refund_transaction_id', v_refund_txn_id,
    'refunded_amount', v_refund_amount,
    'debt_cleared', v_debt_cleared,
    'amount_returned_to_customer', v_amount_returned,
    'new_outstanding', v_other_outstanding - v_debt_cleared
  );
end;
$$;

-- get_customer_wallet_summary (0025) — customer self-service wallet view.
-- Only ever defined once.
create or replace function public.get_customer_wallet_summary()
returns json
language plpgsql
security definer
as $$
declare
  v_profile_id uuid := auth.uid();
  v_balance numeric;
  v_total_outstanding numeric;
  v_pending_order_count int;
  v_transactions json;
begin
  select coalesce(balance, 0) into v_balance
  from public.wallets where profile_id = v_profile_id;
  v_balance := coalesce(v_balance, 0);

  -- Use outstanding_amount column which correctly reflects debt after refunds
  -- The process_refund RPC sets this to 0 for refunded orders
  select coalesce(sum(outstanding_amount), 0),
    count(*) filter (where outstanding_amount > 0)
  into v_total_outstanding, v_pending_order_count
  from public.orders
  where customer_profile_id = v_profile_id
    and status not in ('cancelled','rejected');

  select json_agg(t order by t.created_at desc)
  into v_transactions
  from (
    select wt.id, wt.type, wt.amount, wt.description, wt.order_id,
           o.order_number, wt.created_at
    from public.wallet_transactions wt
    left join public.orders o on o.id = wt.order_id
    where wt.wallet_id = (select id from public.wallets where profile_id = v_profile_id)
    order by wt.created_at desc
    limit 100
  ) t;

  return json_build_object(
    'balance', v_balance,
    'total_outstanding', v_total_outstanding,
    'pending_order_count', v_pending_order_count,
    'transactions', coalesce(v_transactions, '[]'::json)
  );
end;
$$;

-- get_rider_pending_customers (0026) — customers with debt on orders
-- assigned to THIS rider. Only ever defined once.
create or replace function public.get_rider_pending_customers(p_rider_id uuid)
returns json[]
language plpgsql
security definer
as $$
declare
  v_rider_profile_id uuid;
  v_results json[];
begin
  select profile_id into v_rider_profile_id
  from public.riders
  where id = p_rider_id;

  if v_rider_profile_id is distinct from auth.uid() and not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  select array_agg(
    json_build_object(
      'id', c.id,
      'profile_id', c.profile_id,
      'full_name', p.full_name,
      'phone', p.phone,
      'email', p.email,
      'address', (
        select a.full_address
        from public.addresses a
        where a.customer_profile_id = c.profile_id
        order by a.is_default desc, a.created_at asc
        limit 1
      ),
      'outstanding', coalesce(
        (select sum(coalesce(o.outstanding_amount,0))
         from public.orders o
         where o.customer_profile_id = c.profile_id
           and o.rider_id = p_rider_id
           and o.status not in ('cancelled','rejected')),
        0
      )
    )
  )
  into v_results
  from public.customers c
  join public.profiles p on p.id = c.profile_id
  where exists (
    select 1 from public.orders o
    where o.customer_profile_id = c.profile_id
      and o.rider_id = p_rider_id
      and o.status not in ('cancelled','rejected')
      and coalesce(o.outstanding_amount, 0) > 0
  );

  return coalesce(v_results, '{}');
end;
$$;

-- collect_pending_payment — final version: 0027 (0026 -> 0027). Atomic
-- rider-scoped FIFO debt allocation with idempotency-key support. Excess
-- beyond all outstanding debt lands in customer wallet credit.
create or replace function public.collect_pending_payment(
  p_customer_profile_id uuid,
  p_vendor_id uuid,
  p_amount numeric,
  p_receipt_url text default null,
  p_receipt_meta jsonb default '{}'::jsonb,
  p_notes text default null,
  p_idempotency_key text default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_caller_rider_id uuid;
  v_caller_profile_id uuid := auth.uid();
  v_remaining_payment numeric := round(coalesce(p_amount, 0));
  v_order_rec record;
  v_apply numeric;
  v_outstanding_before numeric;
  v_outstanding_after numeric;
  v_credit_before numeric := 0;
  v_credit_after numeric := 0;
  v_excess numeric := 0;
  v_total_settled numeric := 0;
  v_total_debt_remaining numeric := 0;
  v_txn_id uuid;
  v_txn_ids uuid[] := '{}';
  v_existing_txn_id uuid;
begin
  if v_caller_profile_id is null then
    raise exception 'Not authenticated';
  end if;

  if v_remaining_payment <= 0 then
    raise exception 'Payment amount must be positive';
  end if;

  -- Idempotency check: if idempotency key provided, check if transaction already exists
  if p_idempotency_key is not null and length(trim(p_idempotency_key)) > 0 then
    select id into v_existing_txn_id
    from public.payment_transactions
    where notes like '%[idempotency:' || p_idempotency_key || ']%'
    limit 1;

    if v_existing_txn_id is not null then
      select coalesce(balance, 0) into v_credit_after from public.wallets where profile_id = p_customer_profile_id;
      return json_build_object(
        'success', true,
        'duplicate', true,
        'message', 'Payment already processed',
        'settled_amount', p_amount,
        'wallet_credit', v_credit_after
      );
    end if;
  end if;

  -- Get rider ID if caller is a rider
  select id into v_caller_rider_id from public.riders where profile_id = v_caller_profile_id limit 1;

  -- Lock wallets table to get customer wallet balance
  select coalesce(balance, 0) into v_credit_before
  from public.wallets where profile_id = p_customer_profile_id for update;
  v_credit_before := coalesce(v_credit_before, 0);

  -- FIFO Loop over customer's unpaid/partially-paid orders for this vendor allotted to THIS rider (oldest first)
  for v_order_rec in
    select * from public.orders
    where customer_profile_id = p_customer_profile_id
      and vendor_id = p_vendor_id
      and (v_caller_rider_id is null or rider_id = v_caller_rider_id)
      and status not in ('cancelled', 'rejected')
      and outstanding_amount > 0
    order by created_at asc
    for update
  loop
    exit when v_remaining_payment <= 0;

    v_outstanding_before := coalesce(v_order_rec.outstanding_amount, 0);

    if v_outstanding_before > 0 then
      v_apply := least(v_remaining_payment, v_outstanding_before);
      v_outstanding_after := greatest(v_outstanding_before - v_apply, 0);

      -- Update order header
      update public.orders
        set amount_paid = coalesce(amount_paid, 0) + v_apply,
            outstanding_amount = v_outstanding_after,
            payment_status = case when v_outstanding_after = 0 then 'paid'::payment_status else 'partial'::payment_status end,
            updated_at = now()
        where id = v_order_rec.id;

      -- Insert payment transaction
      insert into public.payment_transactions (
        order_id, customer_profile_id, rider_id, vendor_id, amount,
        outstanding_before, outstanding_after, credit_before, credit_after,
        payment_type, notes, created_by
      ) values (
        v_order_rec.id, p_customer_profile_id, v_caller_rider_id, p_vendor_id, v_apply,
        v_outstanding_before, v_outstanding_after, v_credit_before, v_credit_before,
        'full',
        coalesce(p_notes, 'Pending payment collection') ||
          case when p_idempotency_key is not null then ' [idempotency:' || p_idempotency_key || ']' else '' end,
        v_caller_profile_id
      ) returning id into v_txn_id;

      v_txn_ids := array_append(v_txn_ids, v_txn_id);

      -- Upload/Link receipt if provided
      if p_receipt_url is not null and length(trim(p_receipt_url)) > 0 then
        insert into public.payment_receipts (
          payment_transaction_id, vendor_id, receipt_type, receipt_url,
          image_hash, gps_lat, gps_lng, device_time, uploaded_by
        ) values (
          v_txn_id, p_vendor_id,
          coalesce(p_receipt_meta->>'receipt_type', 'cash'),
          p_receipt_url,
          p_receipt_meta->>'image_hash',
          (p_receipt_meta->>'gps_lat')::numeric,
          (p_receipt_meta->>'gps_lng')::numeric,
          (p_receipt_meta->>'device_time')::timestamptz,
          v_caller_profile_id
        );
      end if;

      -- Insert audit log
      insert into public.payment_audit_logs (
        payment_transaction_id, action, old_amount, new_amount, reason, performed_by
      ) values (
        v_txn_id, 'collect_pending', v_outstanding_before, v_outstanding_after,
        'Pending payment collected by rider', v_caller_profile_id
      );

      v_total_settled := v_total_settled + v_apply;
      v_remaining_payment := v_remaining_payment - v_apply;
    end if;
  end loop;

  -- ONLY after all pending orders for this rider are cleared:
  -- Excess funds land in wallet credit!
  if v_remaining_payment > 0 then
    v_excess := v_remaining_payment;
    perform public.adjust_wallet_balance(
      p_customer_profile_id, v_excess, 'credit', null,
      'Excess pending payment credit'
    );
    v_credit_after := v_credit_before + v_excess;
  else
    v_credit_after := v_credit_before;
  end if;

  -- Calculate remaining debt across all active orders
  select coalesce(sum(outstanding_amount), 0) into v_total_debt_remaining
  from public.orders
  where customer_profile_id = p_customer_profile_id
    and vendor_id = p_vendor_id
    and (v_caller_rider_id is null or rider_id = v_caller_rider_id)
    and status not in ('cancelled', 'rejected');

  return json_build_object(
    'success', true,
    'settled_amount', v_total_settled,
    'excess_credit', v_excess,
    'remaining_debt', v_total_debt_remaining,
    'wallet_credit', v_credit_after,
    'transaction_ids', v_txn_ids
  );
end;
$$;
