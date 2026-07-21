-- ============================================================================
-- AquaFlow — Development Seed Data
-- Run against a local/staging project only. Assumes migrations 0001-0004
-- have already been applied. Auth users referenced here must be created
-- first via Supabase Auth (dashboard or `supabase.auth.admin.createUser`)
-- since `profiles.id` is a foreign key into `auth.users`.
-- ============================================================================

insert into public.companies (id, name, contact_email, contact_phone)
values ('11111111-1111-1111-1111-111111111111', 'AquaFlow Pvt Ltd', 'ops@aquaflow.app', '+923001112222')
on conflict do nothing;

insert into public.categories (id, name, icon_name, sort_order) values
  ('22222222-2222-2222-2222-222222222201', 'Mineral Water', 'water_drop', 1),
  ('22222222-2222-2222-2222-222222222202', 'Purified Water', 'opacity', 2),
  ('22222222-2222-2222-2222-222222222203', 'Alkaline Water', 'science', 3),
  ('22222222-2222-2222-2222-222222222204', 'Empty Bottles', 'inventory_2', 4)
on conflict do nothing;

insert into public.coupons (code, description, discount_percent, min_order_amount, valid_until)
values
  ('WELCOME50', 'Rs. 50 off your first order', null, 300, now() + interval '90 days'),
  ('AQUA10', '10% off orders above Rs. 1000', 10, 1000, now() + interval '30 days')
on conflict do nothing;

-- NOTE: The blocks below are commented out because they depend on real
-- auth.users rows existing first. Uncomment and fill in real UUIDs after
-- creating test accounts via Supabase Auth (see README "Seeding test data").
--
-- insert into public.profiles (id, full_name, email, phone, role, is_verified)
-- values ('<vendor-auth-uid>', 'Al-Barakah Water Suppliers', 'vendor@example.com', '+923001234567', 'vendor', true);
--
-- insert into public.vendors (profile_id, company_id, business_name, status, location, address)
-- values (
--   '<vendor-auth-uid>',
--   '11111111-1111-1111-1111-111111111111',
--   'Al-Barakah Water Suppliers',
--   'approved',
--   ST_SetSRID(ST_MakePoint(72.2831, 33.7551), 4326)::geography, -- Wah Cantt
--   'Wah Cantt, Punjab, Pakistan'
-- );
