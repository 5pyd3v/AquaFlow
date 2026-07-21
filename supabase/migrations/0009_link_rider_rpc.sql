-- ============================================================================
-- AquaFlow — link_rider_to_vendor RPC (Migration 0009)
--
-- A rider signs up independently (self-service, no vendor chosen yet).
-- A vendor "claims" them by phone number. Direct `UPDATE riders` from
-- the vendor doesn't satisfy `owns_vendor(vendor_id)` while
-- `vendor_id` is still null (there's nothing to own yet), so this
-- narrow SECURITY DEFINER RPC does the lookup + link in one atomic,
-- audited step instead of loosening the riders RLS policy.
-- ============================================================================

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

grant execute on function public.link_rider_to_vendor(text) to authenticated;

-- Vendors also need to be able to *unlink* a rider they own — a plain
-- update satisfies `owns_vendor(vendor_id)` already (vendor_id is
-- currently set to their own vendor), so no RPC needed for that
-- direction; the existing `riders_update_own_or_vendor_or_admin`
-- policy (0002) already covers it.
