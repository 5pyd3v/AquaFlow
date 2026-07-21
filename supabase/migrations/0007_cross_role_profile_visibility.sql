-- ============================================================================
-- AquaFlow — Cross-role profile visibility for active orders (Migration 0007)
--
-- Fixes a real gap: `profiles_select_own_or_admin` (0002) only lets a
-- user read their own profile row. But the customer app needs to show
-- the assigned rider's name/phone once a rider is assigned, and the
-- rider app needs the customer's name/phone to make a delivery. This
-- adds a narrow, order-scoped exception instead of opening `profiles`
-- up broadly.
-- ============================================================================

create policy "profiles_visible_via_shared_order"
  on public.profiles for select
  using (
    exists (
      select 1 from public.orders o
      left join public.vendors v on v.id = o.vendor_id
      left join public.riders r on r.id = o.rider_id
      where (o.customer_profile_id = auth.uid() or v.profile_id = auth.uid() or r.profile_id = auth.uid())
        and (profiles.id = o.customer_profile_id or profiles.id = v.profile_id or profiles.id = r.profile_id)
    )
  );
