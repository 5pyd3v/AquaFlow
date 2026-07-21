-- ============================================================================
-- AquaFlow — Auto-create role sub-rows (Migration 0008)
--
-- Slice 1 created a `profiles` row on sign-up but never the matching
-- `vendors` / `riders` / `customers` row that the role-specific
-- dashboards actually query. This closes that gap at the same trigger
-- that already fires on `auth.users` insert, and also covers the
-- "complete profile" path (first OTP/Google login, where role is only
-- known once the user picks it) via a second trigger on `profiles`.
-- ============================================================================

-- Business name isn't known until the vendor fills in their business
-- profile (a later onboarding step) — allow it to start null instead
-- of forcing a placeholder string into a real business field.
alter table public.vendors alter column business_name drop not null;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
as $$
declare
  v_role user_role;
begin
  v_role := coalesce((new.raw_user_meta_data->>'role')::user_role, 'customer');

  insert into public.profiles (id, full_name, email, phone, role, is_verified, is_active)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email,
    coalesce(new.raw_user_meta_data->>'phone', new.phone, ''),
    v_role,
    false,
    true
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- Whenever a profile's role is set (on insert, or on update once the
-- complete-profile screen fills it in), make sure the matching
-- sub-table row exists. Idempotent via `on conflict do nothing` so it
-- is always safe to fire more than once for the same profile.
-- ----------------------------------------------------------------------------
create or replace function public.ensure_role_subrow()
returns trigger
language plpgsql
security definer
as $$
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
    insert into public.customers (profile_id, referral_code)
    values (new.id, upper(substr(replace(new.id::text, '-', ''), 1, 8)))
    on conflict (profile_id) do nothing;
  end if;

  return new;
end;
$$;

create trigger trg_profiles_ensure_subrow
  after insert or update of role on public.profiles
  for each row execute function public.ensure_role_subrow();

-- Backfill for any profiles that already exist without a sub-row
-- (relevant if this migration runs after some sign-ups already happened).
insert into public.vendors (profile_id, business_name, status)
select id, nullif(full_name, ''), 'pending' from public.profiles
where role = 'vendor'
on conflict (profile_id) do nothing;

insert into public.riders (profile_id, status)
select id, 'offline' from public.profiles
where role = 'rider'
on conflict (profile_id) do nothing;

insert into public.customers (profile_id, referral_code)
select id, upper(substr(replace(id::text, '-', ''), 1, 8)) from public.profiles
where role = 'customer'
on conflict (profile_id) do nothing;
