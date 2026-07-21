-- ============================================================================
-- AquaFlow — Harden the auth.users → profiles trigger (Migration 0014)
--
-- Fixes: "Database error saving new user" on phone OTP sign-up.
--
-- Two Supabase-specific gotchas were blowing up the auth insert:
--
--   1. `handle_new_auth_user` and `ensure_role_subrow` are SECURITY
--      DEFINER but did not pin `search_path`. On Postgres 15+ (current
--      Supabase), SECURITY DEFINER functions invoked from the auth
--      schema hit an "unstable search_path" failure when they reference
--      unqualified public.* tables. That single condition surfaces to
--      the client as "Database error saving new user" because the whole
--      auth.users insert rolls back.
--
--   2. `ensure_role_subrow` runs inside the same transaction as the
--      auth insert. If ANY downstream write (referral-code collision,
--      a stray NOT NULL, RLS quirk, etc.) throws, the sign-up fails.
--      The client (`_fetchOrBootstrapProfile`) already bootstraps sub-
--      rows on first login, so trigger-side failures must never abort
--      auth. We wrap the sub-row insert in a BEGIN…EXCEPTION so it
--      logs a warning and lets auth proceed.
--
-- Idempotent — safe to re-run.
-- ============================================================================

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role user_role;
begin
  begin
    v_role := coalesce(
      (new.raw_user_meta_data->>'role')::user_role,
      'customer'
    );
  exception when others then
    v_role := 'customer';
  end;

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
      true
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

-- Re-create the auth trigger to be sure it points at the updated
-- function (defensive; `create or replace function` already keeps the
-- trigger bound, but this makes the migration self-contained).
drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

drop trigger if exists trg_profiles_ensure_subrow on public.profiles;
create trigger trg_profiles_ensure_subrow
  after insert or update of role on public.profiles
  for each row execute function public.ensure_role_subrow();
