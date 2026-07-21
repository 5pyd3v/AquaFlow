-- ============================================================================
-- AquaFlow — Storage Buckets (Migration 0004)
-- ============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/png','image/jpeg','image/webp']),
  ('products', 'products', true, 5242880, array['image/png','image/jpeg','image/webp']),
  ('delivery-proofs', 'delivery-proofs', false, 5242880, array['image/png','image/jpeg']),
  ('vendor-documents', 'vendor-documents', false, 10485760, array['application/pdf','image/png','image/jpeg'])
on conflict (id) do nothing;

-- Avatars: any signed-in user may upload/update only their own file,
-- keyed by `{profile_id}/avatar.jpg`; public read for display everywhere.
create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

create policy "avatars_owner_write" on storage.objects
  for insert with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_update" on storage.objects
  for update using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Product images: public read, vendor-owned write scoped to their vendor_id folder.
create policy "products_public_read" on storage.objects
  for select using (bucket_id = 'products');

create policy "products_vendor_write" on storage.objects
  for insert with check (
    bucket_id = 'products'
    and public.owns_vendor(((storage.foldername(name))[1])::uuid)
  );

-- Delivery proofs: private, only order participants can read; rider uploads.
create policy "delivery_proofs_participants_read" on storage.objects
  for select using (
    bucket_id = 'delivery-proofs'
    and exists (
      select 1 from public.orders o
      where o.id::text = (storage.foldername(name))[1]
        and (o.customer_profile_id = auth.uid() or public.owns_vendor(o.vendor_id) or public.owns_rider(o.rider_id) or public.is_admin())
    )
  );

create policy "delivery_proofs_rider_write" on storage.objects
  for insert with check (
    bucket_id = 'delivery-proofs'
    and exists (
      select 1 from public.orders o
      where o.id::text = (storage.foldername(name))[1] and public.owns_rider(o.rider_id)
    )
  );

-- Vendor documents (business license, rider CNIC/license): private, owner + admin only.
create policy "vendor_documents_owner_read" on storage.objects
  for select using (
    bucket_id = 'vendor-documents'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );

create policy "vendor_documents_owner_write" on storage.objects
  for insert with check (
    bucket_id = 'vendor-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
