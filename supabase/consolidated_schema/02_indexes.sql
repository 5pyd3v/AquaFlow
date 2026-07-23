-- ============================================================================
-- AquaFlow — Consolidated Schema: Indexes
--
-- GENERATED REFERENCE — see README.md. All indexes from 0001 (minus any on
-- an excluded table) plus every index added by later migrations.
-- ============================================================================

-- profiles
create index if not exists idx_profiles_role on public.profiles(role);
create index if not exists idx_profiles_phone on public.profiles(phone);
-- Soft-unique phone (0016) — allows empty-string bootstrapped defaults.
create unique index if not exists idx_profiles_phone_unique
  on public.profiles(phone)
  where phone <> '';

-- vendors
create index if not exists idx_vendors_status on public.vendors(status);
create index if not exists idx_vendors_location on public.vendors using gist(location);

-- riders
create index if not exists idx_riders_status on public.riders(status);
create index if not exists idx_riders_vendor on public.riders(vendor_id);
create index if not exists idx_riders_location on public.riders using gist(current_location);

-- customers (0016)
create index if not exists idx_customers_vendor on public.customers(vendor_id);
create unique index if not exists idx_customers_pin on public.customers(pin) where pin is not null;

-- products
create index if not exists idx_products_vendor on public.products(vendor_id);
create index if not exists idx_products_category on public.products(category_id);
create index if not exists idx_products_available on public.products(is_available);

-- inventory
create index if not exists idx_inventory_vendor on public.inventory(vendor_id);

-- addresses
create index if not exists idx_addresses_customer on public.addresses(customer_profile_id);
create index if not exists idx_addresses_location on public.addresses using gist(location);

-- orders
create index if not exists idx_orders_customer on public.orders(customer_profile_id);
create index if not exists idx_orders_vendor on public.orders(vendor_id);
create index if not exists idx_orders_rider on public.orders(rider_id);
create index if not exists idx_orders_status on public.orders(status);
create index if not exists idx_orders_created_at on public.orders(created_at desc);

-- order_items
create index if not exists idx_order_items_order on public.order_items(order_id);

-- transactions (legacy generic gateway table)
create index if not exists idx_transactions_order on public.transactions(order_id);

-- ratings
create index if not exists idx_ratings_vendor on public.ratings(rated_vendor_id);
create index if not exists idx_ratings_rider on public.ratings(rated_rider_id);
-- One rating per (order, rated rider) / (order, rated vendor) — 0013
create unique index if not exists uq_ratings_order_rider
  on public.ratings(order_id, rated_rider_id)
  where rated_rider_id is not null;
create unique index if not exists uq_ratings_order_vendor
  on public.ratings(order_id, rated_vendor_id)
  where rated_vendor_id is not null;

-- favorites
create unique index if not exists idx_favorites_unique_product on public.favorites(customer_profile_id, product_id) where product_id is not null;
create unique index if not exists idx_favorites_unique_vendor on public.favorites(customer_profile_id, vendor_id) where vendor_id is not null;

-- notifications (restored by 0020)
create index if not exists idx_notifications_profile
  on public.notifications(profile_id, is_read);

-- tracking_logs
create index if not exists idx_tracking_logs_order on public.tracking_logs(order_id);

-- audit_logs
create index if not exists idx_audit_logs_actor on public.audit_logs(actor_profile_id);

-- cod_settlements (0015)
create index if not exists idx_cod_settlements_rider on public.cod_settlements(rider_id);
create index if not exists idx_cod_settlements_vendor on public.cod_settlements(vendor_id);
create index if not exists idx_cod_settlements_code on public.cod_settlements(code) where status = 'pending';
create index if not exists idx_cod_settlements_status on public.cod_settlements(status);

-- payment_transactions (0024, plus refunds index from 0027)
create index if not exists idx_pay_txn_order on public.payment_transactions(order_id);
create index if not exists idx_pay_txn_customer on public.payment_transactions(customer_profile_id);
create index if not exists idx_pay_txn_rider on public.payment_transactions(rider_id);
create index if not exists idx_pay_txn_vendor on public.payment_transactions(vendor_id);
create index if not exists idx_pay_txn_status on public.payment_transactions(status);
create index if not exists idx_pay_txn_settlement on public.payment_transactions(settlement_id);
create index if not exists idx_pay_txn_refunds
  on public.payment_transactions(refunds_transaction_id)
  where refunds_transaction_id is not null;

-- payment_receipts (0024)
create index if not exists idx_pay_receipt_txn on public.payment_receipts(payment_transaction_id);
create unique index if not exists uq_pay_receipt_vendor_hash
  on public.payment_receipts(vendor_id, image_hash) where image_hash is not null;

-- payment_audit_logs (0024)
create index if not exists idx_pay_audit_txn on public.payment_audit_logs(payment_transaction_id);

-- payment_amendment_requests (0024)
create index if not exists idx_pay_amend_vendor_status on public.payment_amendment_requests(vendor_id, status);
create index if not exists idx_pay_amend_rider on public.payment_amendment_requests(rider_id);

-- customer_account_statements (0024)
create index if not exists idx_cust_statement_customer on public.customer_account_statements(customer_profile_id);
create index if not exists idx_cust_statement_vendor on public.customer_account_statements(vendor_id);
