-- ============================================================================
-- AquaFlow — Vendor Customers RPC (Migration 0022)
--
-- The customers RLS policy only allows a customer to read their own row.
-- Vendors need to list/search all customers linked to them, so we expose
-- a SECURITY DEFINER RPC that returns customer + profile data scoped to
-- the calling vendor's own customer pool.
-- ============================================================================

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
  -- Verify the caller actually owns this vendor
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
        (select count(*) from public.orders o where o.customer_profile_id = c.profile_id),
        0
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

grant execute on function public.get_vendor_customers(uuid) to authenticated;
