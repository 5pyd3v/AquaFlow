-- ============================================================================
-- AquaFlow — Vendor Reset Customer PIN (Migration 0031)
--
-- Customers authenticate with phone + 6-digit PIN, where the PIN also
-- backs their Supabase Auth password (see create_pin_customer in
-- 0030_fix_gotrue_null_columns.sql). Vendors previously had no way to
-- change a customer's PIN if it was forgotten or needed rotating — this
-- adds a SECURITY DEFINER RPC that lets a vendor reset the PIN for one
-- of their own customers, updating both the auth password hash and the
-- public.customers.pin column that the app displays.
-- ============================================================================

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
  -- Verify the caller actually owns this vendor.
  select id into v_caller_vendor_id
  from public.vendors
  where id = p_vendor_id and profile_id = auth.uid();

  if v_caller_vendor_id is null then
    raise exception 'Not authorized';
  end if;

  -- Verify the customer belongs to this vendor.
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

grant execute on function public.reset_customer_pin(uuid, uuid, text) to authenticated;
