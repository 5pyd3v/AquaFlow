-- ============================================================================
-- AquaFlow — Vendor can read + unlink their riders (Migration 0022)
--
-- Follow-up to 0021. Two RLS gaps were blocking the vendor-approves-rider
-- flow from actually working:
--
-- 1. profiles visibility: getMyRiders embeds profiles(full_name, phone,
--    is_active), but a vendor could only read a profiles row for itself,
--    an admin, or a shared-order counterpart (0002 + 0007). A freshly
--    self-registered rider linked to the vendor has no shared order yet,
--    so the embedded profile came back NULL — the rider showed as a
--    generic "Rider", and is_active was unreadable, so the pending
--    approval UI never appeared. This adds an ownership-scoped read.
--
-- 2. unlink was broken: riders_update_own_or_vendor_or_admin (0002) has a
--    USING clause but no WITH CHECK. Postgres then applies USING to the
--    NEW row too. Setting vendor_id = null makes owns_vendor(null) false,
--    so the UPDATE is rejected by RLS and the unlink silently fails.
--    A narrow SECURITY DEFINER RPC (same pattern as link_rider_to_vendor,
--    0009, and approve/reject_rider, 0021) does the unlink safely.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. A vendor may read the profile of any rider linked to their business.
-- ----------------------------------------------------------------------------
create policy "profiles_visible_to_owning_vendor"
  on public.profiles for select
  using (
    exists (
      select 1 from public.riders r
      where r.profile_id = profiles.id
        and public.owns_vendor(r.vendor_id)
    )
  );

-- ----------------------------------------------------------------------------
-- 2. Unlink an already-approved rider from this vendor.
-- ----------------------------------------------------------------------------
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

grant execute on function public.unlink_rider(uuid) to authenticated;
