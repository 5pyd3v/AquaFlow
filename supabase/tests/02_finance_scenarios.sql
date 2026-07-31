-- ============================================================================
-- AquaFlow — Finance Scenario Tests (TRANSACTIONAL — rolls back)
--
-- Seeds an isolated vendor/riders/customers, drives the REAL payment RPCs,
-- and asserts the exact numbers from the agreed accounting rules. Every
-- change is rolled back, so this is safe to run against any environment
-- (staging strongly preferred regardless).
--
--   psql "$DATABASE_URL" -f supabase/tests/02_finance_scenarios.sql
--
-- Success = "ALL FINANCE SCENARIOS PASSED" notice and no error.
-- Any failed assertion raises and aborts.
-- ============================================================================

begin;

do $$
declare
  -- fixed ids so failures are easy to trace
  v_vendor_profile uuid := 'aaaaaaaa-0000-4000-8000-000000000001';
  v_r1_profile     uuid := 'aaaaaaaa-0000-4000-8000-000000000002';
  v_r2_profile     uuid := 'aaaaaaaa-0000-4000-8000-000000000003';
  v_r3_profile     uuid := 'aaaaaaaa-0000-4000-8000-000000000004';
  v_c1_profile     uuid := 'aaaaaaaa-0000-4000-8000-000000000011';
  v_c2_profile     uuid := 'aaaaaaaa-0000-4000-8000-000000000012';
  v_c3_profile     uuid := 'aaaaaaaa-0000-4000-8000-000000000013';
  v_c4_profile     uuid := 'aaaaaaaa-0000-4000-8000-000000000014';

  v_vendor uuid;
  v_r1 uuid; v_r2 uuid; v_r3 uuid;
  v_addr1 uuid; v_addr2 uuid; v_addr3 uuid; v_addr4 uuid;

  v_o1 uuid;            -- S1/S2: 2000 order, 1500 paid
  v_o2a uuid; v_o2b uuid;   -- S3: 2000 + 2000 = 4000 collected
  v_o3_old uuid; v_o3_new uuid; -- S4: overpay clears debt
  v_o4 uuid;            -- S5: true excess -> credit
  v_o5 uuid;            -- S9: partial pending collection
  v_o6_old uuid; v_o6_new uuid; -- S10: excess partially covers other debt

  v_res json;
  v_bal json;
  v_kpis json;
  v_num numeric;
  v_num2 numeric;
  v_status text;
  v_code text;
  v_awaiting_before numeric;
  v_awaiting_after numeric;

  v_geo geography := ST_GeogFromText('SRID=4326;POINT(74.35 31.52)');
begin
  -- ------------------------------------------------------------------
  -- Seed identities
  -- ------------------------------------------------------------------
  insert into auth.users (id, instance_id, email, aud, role,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token,
    email_confirmed_at, created_at, updated_at)
  select u.id, '00000000-0000-0000-0000-000000000000', u.email, 'authenticated', 'authenticated',
         '', '', '', '', '', '', '', '', now(), now(), now()
  from (values
    (v_vendor_profile, 'fin-test-vendor@example.test'),
    (v_r1_profile,     'fin-test-r1@example.test'),
    (v_r2_profile,     'fin-test-r2@example.test'),
    (v_r3_profile,     'fin-test-r3@example.test'),
    (v_c1_profile,     'fin-test-c1@example.test'),
    (v_c2_profile,     'fin-test-c2@example.test'),
    (v_c3_profile,     'fin-test-c3@example.test'),
    (v_c4_profile,     'fin-test-c4@example.test')
  ) as u(id, email);

  insert into public.profiles (id, full_name, email, phone, role, is_verified, is_active)
  values
    (v_vendor_profile, 'Test Vendor', 'fin-test-vendor@example.test', '+920000000001', 'vendor',   true, true),
    (v_r1_profile,     'Rider One',   'fin-test-r1@example.test',     '+920000000002', 'rider',    true, true),
    (v_r2_profile,     'Rider Two',   'fin-test-r2@example.test',     '+920000000003', 'rider',    true, true),
    (v_r3_profile,     'Rider Three', 'fin-test-r3@example.test',     '+920000000004', 'rider',    true, true),
    (v_c1_profile,     'Customer One','fin-test-c1@example.test',     '+920000000011', 'customer', true, true),
    (v_c2_profile,     'Customer Two','fin-test-c2@example.test',     '+920000000012', 'customer', true, true),
    (v_c3_profile,     'Customer3',  'fin-test-c3@example.test',     '+920000000013', 'customer', true, true),
    (v_c4_profile,     'Customer 4',  'fin-test-c4@example.test',     '+920000000014', 'customer', true, true);

  insert into public.vendors (profile_id, business_name) values (v_vendor_profile, 'Fin Test Water')
  returning id into v_vendor;

  insert into public.riders (profile_id, vendor_id) values (v_r1_profile, v_vendor) returning id into v_r1;
  insert into public.riders (profile_id, vendor_id) values (v_r2_profile, v_vendor) returning id into v_r2;
  insert into public.riders (profile_id, vendor_id) values (v_r3_profile, v_vendor) returning id into v_r3;

  insert into public.customers (profile_id, vendor_id) values
    (v_c1_profile, v_vendor), (v_c2_profile, v_vendor),
    (v_c3_profile, v_vendor), (v_c4_profile, v_vendor);

  insert into public.addresses (customer_profile_id, full_address, location) values (v_c1_profile, 'Addr 1', v_geo) returning id into v_addr1;
  insert into public.addresses (customer_profile_id, full_address, location) values (v_c2_profile, 'Addr 2', v_geo) returning id into v_addr2;
  insert into public.addresses (customer_profile_id, full_address, location) values (v_c3_profile, 'Addr 3', v_geo) returning id into v_addr3;
  insert into public.addresses (customer_profile_id, full_address, location) values (v_c4_profile, 'Addr 4', v_geo) returning id into v_addr4;

  -- ==================================================================
  -- S1 — Order Rs.2000, customer hands over Rs.1500.
  --      => Rs.1500 is sales, Rs.500 becomes debt.
  -- ==================================================================
  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, outstanding_amount, payment_method, rider_otp)
  values ('FIN-TEST-S1', v_c1_profile, v_vendor, v_r1, v_addr1,
          'assigned', 2000, 2000, 'cod', '111111')
  returning id into v_o1;

  perform set_config('request.jwt.claim.sub', v_r1_profile::text, true);
  v_res := public.complete_delivery_with_payment(v_o1, '111111', 1500);

  select amount_paid, outstanding_amount into v_num, v_num2 from public.orders where id = v_o1;
  if v_num <> 1500 then raise exception 'S1: expected amount_paid 1500, got %', v_num; end if;
  if v_num2 <> 500 then raise exception 'S1: expected outstanding 500, got %', v_num2; end if;

  -- sales recognised so far for this rider = 1500 (not the 2000 order value)
  v_bal := public.get_rider_cod_balance(v_r1, v_vendor);
  if (v_bal->>'total_collected')::numeric <> 1500 then
    raise exception 'S1: expected rider collected 1500, got %', v_bal->>'total_collected';
  end if;

  -- cash conservation: rows booked for this order sum to exactly what was tendered
  select coalesce(sum(amount), 0) into v_num from public.payment_transactions
  where order_id = v_o1 and status = 'active';
  if v_num <> 1500 then raise exception 'S1: cash conservation broken, rows sum to %', v_num; end if;

  -- ==================================================================
  -- S2 — Rider later collects the Rs.500 debt => it becomes sales too.
  -- ==================================================================
  perform public.collect_pending_payment(v_c1_profile, v_vendor, 500);

  select amount_paid, outstanding_amount into v_num, v_num2 from public.orders where id = v_o1;
  if v_num <> 2000 then raise exception 'S2: expected amount_paid 2000, got %', v_num; end if;
  if v_num2 <> 0 then raise exception 'S2: expected outstanding 0, got %', v_num2; end if;

  v_bal := public.get_rider_cod_balance(v_r1, v_vendor);
  if (v_bal->>'total_collected')::numeric <> 2000 then
    raise exception 'S2: expected rider collected 2000 after debt collection, got %', v_bal->>'total_collected';
  end if;

  -- ==================================================================
  -- S3 — Rider collects Rs.4000, settles Rs.3500
  --      => settled 3500, unsettled 500.
  -- ==================================================================
  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, outstanding_amount, payment_method, rider_otp)
  values ('FIN-TEST-S3A', v_c2_profile, v_vendor, v_r2, v_addr2, 'assigned', 2000, 2000, 'cod', '222222')
  returning id into v_o2a;
  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, outstanding_amount, payment_method, rider_otp)
  values ('FIN-TEST-S3B', v_c2_profile, v_vendor, v_r2, v_addr2, 'assigned', 2000, 2000, 'cod', '333333')
  returning id into v_o2b;

  perform set_config('request.jwt.claim.sub', v_r2_profile::text, true);
  perform public.complete_delivery_with_payment(v_o2a, '222222', 2000);
  perform public.complete_delivery_with_payment(v_o2b, '333333', 2000);

  v_bal := public.get_rider_cod_balance(v_r2, v_vendor);
  if (v_bal->>'total_collected')::numeric <> 4000 then
    raise exception 'S3: expected collected 4000, got %', v_bal->>'total_collected';
  end if;

  v_res := public.generate_cod_settlement(v_r2, v_vendor, 3500);
  v_code := v_res->>'code';

  perform set_config('request.jwt.claim.sub', v_vendor_profile::text, true);
  perform public.verify_cod_settlement(v_code, v_vendor);

  v_bal := public.get_rider_cod_balance(v_r2, v_vendor);
  if (v_bal->>'total_verified')::numeric <> 3500 then
    raise exception 'S3: expected settled 3500, got %', v_bal->>'total_verified';
  end if;
  if (v_bal->>'outstanding')::numeric <> 500 then
    raise exception 'S3: expected unsettled 500, got %', v_bal->>'outstanding';
  end if;

  -- the vendor-facing per-rider card must agree with the rider's own view
  select (p->>'outstanding')::numeric into v_num
  from unnest(public.get_vendor_rider_cash_positions(v_vendor)) as p
  where (p->>'rider_id')::uuid = v_r2;
  if v_num <> 500 then raise exception 'S3: vendor card shows unsettled %, expected 500', v_num; end if;

  -- ==================================================================
  -- S4 — Customer owes Rs.500; overpays Rs.500 on a new order.
  --      => the extra clears the debt. It must NOT become wallet credit.
  -- ==================================================================
  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, amount_paid, outstanding_amount, payment_method, delivered_at)
  values ('FIN-TEST-S4-OLD', v_c3_profile, v_vendor, v_r3, v_addr3,
          'delivered', 500, 0, 500, 'cod', now() - interval '1 day')
  returning id into v_o3_old;

  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, outstanding_amount, payment_method, rider_otp)
  values ('FIN-TEST-S4-NEW', v_c3_profile, v_vendor, v_r3, v_addr3,
          'assigned', 1000, 1000, 'cod', '444444')
  returning id into v_o3_new;

  perform set_config('request.jwt.claim.sub', v_r3_profile::text, true);
  v_res := public.complete_delivery_with_payment(v_o3_new, '444444', 1500);

  if (v_res->>'debt_cleared')::numeric <> 500 then
    raise exception 'S4: expected debt_cleared 500, got %', v_res->>'debt_cleared';
  end if;
  if (v_res->>'excess_credit')::numeric <> 0 then
    raise exception 'S4: expected excess_credit 0 (debt first), got %', v_res->>'excess_credit';
  end if;

  select outstanding_amount into v_num from public.orders where id = v_o3_new;
  if v_num <> 0 then raise exception 'S4: new order outstanding %, expected 0', v_num; end if;
  select outstanding_amount into v_num from public.orders where id = v_o3_old;
  if v_num <> 0 then raise exception 'S4: old debt outstanding %, expected 0 (cleared)', v_num; end if;

  select coalesce(balance, 0) into v_num from public.wallets where profile_id = v_c3_profile;
  if coalesce(v_num, 0) <> 0 then
    raise exception 'S4: wallet credit should stay 0 when debt exists, got %', v_num;
  end if;

  -- cash conservation across BOTH orders: exactly the Rs.1500 tendered
  select coalesce(sum(amount), 0) into v_num from public.payment_transactions
  where status = 'active' and order_id in (v_o3_new, v_o3_old);
  if v_num <> 1500 then
    raise exception 'S4: cash conservation broken — rows sum to % (double counting?)', v_num;
  end if;

  -- ==================================================================
  -- S5 — Genuine excess with NO other debt => wallet credit, and the
  --      'over' row records only the excess (not the whole tender).
  -- ==================================================================
  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, outstanding_amount, payment_method, rider_otp)
  values ('FIN-TEST-S5', v_c4_profile, v_vendor, v_r3, v_addr4, 'assigned', 1000, 1000, 'cod', '555555')
  returning id into v_o4;

  v_res := public.complete_delivery_with_payment(v_o4, '555555', 1200);

  if (v_res->>'excess_credit')::numeric <> 200 then
    raise exception 'S5: expected excess_credit 200, got %', v_res->>'excess_credit';
  end if;
  select coalesce(balance, 0) into v_num from public.wallets where profile_id = v_c4_profile;
  if v_num <> 200 then raise exception 'S5: expected wallet 200, got %', v_num; end if;

  select coalesce(sum(amount), 0) into v_num from public.payment_transactions
  where order_id = v_o4 and status = 'active' and payment_type = 'over';
  if v_num <> 200 then
    raise exception 'S5: over-row should record only the 200 excess, got % (credits_issued bug)', v_num;
  end if;

  select coalesce(sum(amount), 0) into v_num from public.payment_transactions
  where order_id = v_o4 and status = 'active';
  if v_num <> 1200 then raise exception 'S5: cash conservation broken, rows sum to %', v_num; end if;

  -- ==================================================================
  -- S6 — "Unsettled" must count RIDER-held cash only. A payment with no
  --      rider attached must not move the figure.
  -- ==================================================================
  perform set_config('request.jwt.claim.sub', v_vendor_profile::text, true);
  v_kpis := public.get_vendor_finance_kpis(v_vendor);
  v_awaiting_before := (v_kpis->>'awaiting_settlement')::numeric;

  insert into public.payment_transactions (order_id, customer_profile_id, rider_id, vendor_id,
    amount, outstanding_before, outstanding_after, credit_before, credit_after, payment_type, notes)
  values (v_o4, v_c4_profile, null, v_vendor, 9999, 0, 0, 0, 0, 'full', 'riderless payment');

  v_kpis := public.get_vendor_finance_kpis(v_vendor);
  v_awaiting_after := (v_kpis->>'awaiting_settlement')::numeric;

  if v_awaiting_before <> v_awaiting_after then
    raise exception 'S6: riderless payment leaked into unsettled (% -> %)', v_awaiting_before, v_awaiting_after;
  end if;

  -- ==================================================================
  -- S7 — KPI tie-out: awaiting_settlement must equal the sum of the
  --      per-rider cards the vendor sees.
  -- ==================================================================
  select coalesce(sum((p->>'outstanding')::numeric), 0) into v_num
  from unnest(public.get_vendor_rider_cash_positions(v_vendor)) as p;

  if v_num <> v_awaiting_after then
    raise exception 'S7: KPI unsettled % != sum of rider cards %', v_awaiting_after, v_num;
  end if;

  -- ==================================================================
  -- S8 — Sales are cash, not order value. Vendor total_sales must equal
  --      the sum of every active payment row, net of refunds.
  -- ==================================================================
  select coalesce(sum(case when payment_type = 'refund' then -amount else amount end), 0)
  into v_num
  from public.payment_transactions
  where vendor_id = v_vendor and status = 'active'
    and payment_type in ('full', 'partial', 'over', 'refund');

  if (v_kpis->>'total_sales')::numeric <> v_num then
    raise exception 'S8: total_sales % != summed cash %', v_kpis->>'total_sales', v_num;
  end if;

  -- ==================================================================
  -- S9 — REGRESSION (migration 0034): a PARTIAL pending-payment
  --      collection must not blow up on the payment_status enum.
  --
  --      S2 above collected the debt in full, so it took the
  --      `outstanding = 0 -> 'paid'` branch and never executed the
  --      `else 'partial'` branch. That gap let
  --      `invalid input value for enum payment_status: "partial"` survive
  --      from migration 0026 all the way to production. This scenario
  --      deliberately leaves a balance so the else-branch runs.
  -- ==================================================================
  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, amount_paid, outstanding_amount, payment_method, delivered_at)
  values ('FIN-TEST-S9', v_c1_profile, v_vendor, v_r1, v_addr1,
          'delivered', 1000, 0, 1000, 'cod', now() - interval '2 hours')
  returning id into v_o5;

  perform set_config('request.jwt.claim.sub', v_r1_profile::text, true);
  perform public.collect_pending_payment(v_c1_profile, v_vendor, 400);

  select amount_paid, outstanding_amount into v_num, v_num2 from public.orders where id = v_o5;
  if v_num <> 400 then raise exception 'S9: expected amount_paid 400, got %', v_num; end if;
  if v_num2 <> 600 then raise exception 'S9: expected outstanding 600, got %', v_num2; end if;

  select payment_status::text into v_status from public.orders where id = v_o5;
  if v_status <> 'partial' then
    raise exception 'S9: expected payment_status partial, got %', v_status;
  end if;

  -- ==================================================================
  -- S10 — REGRESSION (migration 0034): overpayment whose excess only
  --       PARTIALLY covers another order. S4 cleared the old debt
  --       exactly, again taking the 'paid' branch; this one leaves a
  --       remainder so the reallocation else-branch runs.
  -- ==================================================================
  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, amount_paid, outstanding_amount, payment_method, delivered_at)
  values ('FIN-TEST-S10-OLD', v_c2_profile, v_vendor, v_r2, v_addr2,
          'delivered', 900, 0, 900, 'cod', now() - interval '3 hours')
  returning id into v_o6_old;

  insert into public.orders (order_number, customer_profile_id, vendor_id, rider_id, address_id,
                             status, total_amount, outstanding_amount, payment_method, rider_otp)
  values ('FIN-TEST-S10-NEW', v_c2_profile, v_vendor, v_r2, v_addr2,
          'assigned', 500, 500, 'cod', '666666')
  returning id into v_o6_new;

  perform set_config('request.jwt.claim.sub', v_r2_profile::text, true);
  -- tender 800: 500 clears the new order, 300 of the 900 old debt
  v_res := public.complete_delivery_with_payment(v_o6_new, '666666', 800);

  if (v_res->>'debt_cleared')::numeric <> 300 then
    raise exception 'S10: expected debt_cleared 300, got %', v_res->>'debt_cleared';
  end if;

  select outstanding_amount, payment_status::text into v_num, v_status
  from public.orders where id = v_o6_old;
  if v_num <> 600 then raise exception 'S10: expected old debt 600 remaining, got %', v_num; end if;
  if v_status <> 'partial' then
    raise exception 'S10: expected old order payment_status partial, got %', v_status;
  end if;

  -- still no double counting when the excess only partly lands
  select coalesce(sum(amount), 0) into v_num from public.payment_transactions
  where status = 'active' and order_id in (v_o6_new, v_o6_old);
  if v_num <> 800 then
    raise exception 'S10: cash conservation broken — rows sum to %, tendered 800', v_num;
  end if;

  raise notice 'ALL FINANCE SCENARIOS PASSED';
end;
$$;

rollback;
