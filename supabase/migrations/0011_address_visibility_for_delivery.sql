-- ============================================================================
-- AquaFlow — Delivery-address visibility for riders/vendors (Migration 0011)
--
-- Same category of gap as migration 0007 (profiles): `addresses_owner_only`
-- (0002) only lets the owning customer read their own address. But a
-- rider obviously needs the delivery coordinates for an order assigned
-- to them, and a vendor needs them too (their own order list joins
-- addresses for display). Adding a narrow, order-scoped read policy
-- rather than opening `addresses` up broadly.
-- ============================================================================

create policy "addresses_visible_via_assigned_order"
  on public.addresses for select
  using (
    exists (
      select 1 from public.orders o
      where o.address_id = addresses.id
        and (public.owns_rider(o.rider_id) or public.owns_vendor(o.vendor_id))
    )
  );
