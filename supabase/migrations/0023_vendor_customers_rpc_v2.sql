-- ============================================================================
-- AquaFlow — Vendor Customers RPC v2 (Migration 0023)
--
-- Adds the customer's default delivery address to the vendor customer list
-- so the vendor dashboard can show proper contact + location details.
-- Supersedes the json_build_object shape from migration 0022.
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

grant execute on function public.get_vendor_customers(uuid) to authenticated;
