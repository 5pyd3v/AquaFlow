-- ============================================================================
-- AquaFlow — Vendor approves their own riders (Migration 0021)
--
-- A delivery rider signs up choosing a vendor (riders.vendor_id is set at
-- signup by create_email_user) and lands as is_active = false → pending.
-- Previously only an admin could flip profiles.is_active to true. Product
-- decision: the OWNING VENDOR approves their riders, not the admin.
--
-- A vendor cannot UPDATE another user's profiles row directly
-- (profiles_update_own_or_admin, migration 0002), so approval/rejection
-- goes through these narrow SECURITY DEFINER RPCs — the same pattern as
-- link_rider_to_vendor (0009). Each RPC verifies the caller owns the
-- vendor the rider is linked to before touching anything.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Approve a pending rider: flip their profile to active so they can leave
-- the pending-approval screen and reach the rider dashboard.
-- ----------------------------------------------------------------------------
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

grant execute on function public.approve_rider(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- Reject a pending rider: unlink them from this vendor so the request
-- leaves the vendor's list. The rider keeps their (still-inactive)
-- account and can request another vendor.
-- ----------------------------------------------------------------------------
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

grant execute on function public.reject_rider(uuid) to authenticated;
