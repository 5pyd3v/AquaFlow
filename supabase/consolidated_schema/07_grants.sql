-- ============================================================================
-- AquaFlow — Consolidated Schema: Grants
--
-- GENERATED REFERENCE — see README.md. Every `grant execute` statement
-- issued across the migration history, one per function (final parameter
-- signature). `grant` is inherently idempotent — safe to re-run.
--
-- Note: current_role/is_admin/owns_vendor/owns_rider (0002), every trigger
-- function, and get_vendor_cod_summary (0015) never received an explicit
-- grant in any migration — they work via Postgres's default PUBLIC execute
-- privilege (which `authenticated`/`anon` inherit unless revoked). Nothing
-- ever revoked it, so no grant statement is needed for them here either.
-- ============================================================================

grant execute on function public.place_order(uuid, uuid, jsonb, payment_method, boolean, uuid, numeric, numeric, timestamptz) to authenticated;

grant execute on function public.link_rider_to_vendor(text) to authenticated;

grant execute on function public.has_rated_order(uuid) to authenticated;

grant execute on function public.verify_delivery_otp(uuid, text) to authenticated;

grant execute on function public.auto_confirm_user(uuid) to authenticated;

grant execute on function public.create_pin_customer(uuid, text, text, text, text) to authenticated;

grant execute on function public.create_email_user(text, text, text, text, text, text, uuid) to anon, authenticated;

grant execute on function public.finalize_customer_account(uuid, uuid, text, text, text) to authenticated;

grant execute on function public.resolve_pin_login(text) to anon, authenticated;

grant execute on function public.approve_rider(uuid) to authenticated;

grant execute on function public.reject_rider(uuid) to authenticated;

grant execute on function public.get_vendor_customers(uuid) to authenticated;

grant execute on function public.unlink_rider(uuid) to authenticated;

grant execute on function public.verify_delivery_pin_only(uuid, text) to authenticated;

grant execute on function public.complete_delivery_with_payment(uuid, text, numeric, text, jsonb, text) to authenticated;

grant execute on function public.edit_payment(uuid, numeric, text) to authenticated;

grant execute on function public.delete_payment(uuid, text) to authenticated;

grant execute on function public.request_payment_amendment(uuid, text, numeric, text) to authenticated;

grant execute on function public.resolve_payment_amendment(uuid, bool, text) to authenticated;

grant execute on function public.apply_customer_credit(uuid, numeric) to authenticated;

grant execute on function public.get_customer_ledger(uuid) to authenticated;

grant execute on function public.get_settlement_detail(uuid) to authenticated;

grant execute on function public.get_vendor_payment_overview(uuid) to authenticated;

grant execute on function public.get_vendor_rider_cash_positions(uuid) to authenticated;

grant execute on function public.get_vendor_finance_kpis(uuid) to authenticated;

grant execute on function public.generate_cod_settlement(uuid, uuid, numeric) to authenticated;

grant execute on function public.verify_cod_settlement(text, uuid) to authenticated;

grant execute on function public.order_outstanding(uuid) to authenticated;

grant execute on function public.get_customer_total_outstanding(uuid, uuid) to authenticated;

grant execute on function public.process_refund(uuid, numeric, text) to authenticated;

grant execute on function public.get_customer_wallet_summary() to authenticated;

grant execute on function public.get_rider_pending_customers(uuid) to authenticated;

grant execute on function public.get_rider_cod_balance(uuid, uuid) to authenticated;

grant execute on function public.collect_pending_payment(uuid, uuid, numeric, text, jsonb, text, text) to authenticated;

grant execute on function public.reset_customer_pin(uuid, uuid, text) to authenticated;
