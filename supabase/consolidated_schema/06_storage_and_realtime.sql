-- ============================================================================
-- AquaFlow — Consolidated Schema: Storage Buckets/Policies & Realtime
--
-- GENERATED REFERENCE — see README.md. Buckets from 0004, with the
-- delivery-proofs bucket flipped to public (0026) folded into the base
-- insert. Realtime publication membership from 0012 (messages excluded —
-- the messages table itself was dropped in 0017 and never recreated).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Storage buckets (0004, delivery-proofs public flag from 0026)
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/png','image/jpeg','image/webp']),
  ('products', 'products', true, 5242880, array['image/png','image/jpeg','image/webp']),
  ('delivery-proofs', 'delivery-proofs', true, 5242880, array['image/png','image/jpeg']),
  ('vendor-documents', 'vendor-documents', false, 10485760, array['application/pdf','image/png','image/jpeg'])
on conflict (id) do nothing;

-- Idempotent safety net in case the bucket already exists from an older run
-- of this file with public still false (mirrors 0026's UPDATE).
update storage.buckets set public = true where id = 'delivery-proofs';

-- Avatars: any signed-in user may upload/update only their own file, keyed
-- by `{profile_id}/avatar.jpg`; public read for display everywhere.
drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatars_owner_write" on storage.objects;
create policy "avatars_owner_write" on storage.objects
  for insert with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars_owner_update" on storage.objects;
create policy "avatars_owner_update" on storage.objects
  for update using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- Product images: public read, vendor-owned write scoped to their vendor_id folder.
drop policy if exists "products_public_read" on storage.objects;
create policy "products_public_read" on storage.objects
  for select using (bucket_id = 'products');

drop policy if exists "products_vendor_write" on storage.objects;
create policy "products_vendor_write" on storage.objects
  for insert with check (
    bucket_id = 'products'
    and public.owns_vendor(((storage.foldername(name))[1])::uuid)
  );

-- Delivery proofs: bucket is public (0026), but the participants-scoped read
-- policy from 0004 is still present (neither migration ever dropped it) —
-- both policies are OR'd together for select, so this is additive, not
-- contradictory.
drop policy if exists "delivery_proofs_participants_read" on storage.objects;
create policy "delivery_proofs_participants_read" on storage.objects
  for select using (
    bucket_id = 'delivery-proofs'
    and exists (
      select 1 from public.orders o
      where o.id::text = (storage.foldername(name))[1]
        and (o.customer_profile_id = auth.uid() or public.owns_vendor(o.vendor_id) or public.owns_rider(o.rider_id) or public.is_admin())
    )
  );

drop policy if exists "delivery_proofs_rider_write" on storage.objects;
create policy "delivery_proofs_rider_write" on storage.objects
  for insert with check (
    bucket_id = 'delivery-proofs'
    and exists (
      select 1 from public.orders o
      where o.id::text = (storage.foldername(name))[1] and public.owns_rider(o.rider_id)
    )
  );

-- Unconditional public read (0026) — added when the bucket itself was
-- flipped to public; supersedes the participants-only restriction for select.
drop policy if exists "delivery_proofs_public_read" on storage.objects;
create policy "delivery_proofs_public_read" on storage.objects
  for select using (bucket_id = 'delivery-proofs');

-- Vendor documents (business license, rider CNIC/license): private, owner + admin only.
drop policy if exists "vendor_documents_owner_read" on storage.objects;
create policy "vendor_documents_owner_read" on storage.objects
  for select using (
    bucket_id = 'vendor-documents'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );

drop policy if exists "vendor_documents_owner_write" on storage.objects;
create policy "vendor_documents_owner_write" on storage.objects
  for insert with check (
    bucket_id = 'vendor-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ----------------------------------------------------------------------------
-- Realtime replication (0012, notifications re-added by 0020)
--
-- `messages` was also added to the publication in 0012, but the `messages`
-- table itself was dropped in 0017 and never recreated — omitted here.
-- ----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'realtime_locations'
  ) then
    alter publication supabase_realtime add table public.realtime_locations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
