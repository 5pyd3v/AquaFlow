-- ============================================================================
-- AquaFlow — Payment Management & Settlement Enhancement (Migration 0024)
--
-- Adds an auditable payment layer on top of the existing order + COD
-- settlement system WITHOUT altering any existing flow:
--   * per-order paid / outstanding / credit-applied tracking
--   * payment_transactions (permanent, soft-delete, before/after snapshots)
--   * payment_receipts (one-to-many, receipt metadata + fraud hash)
--   * payment_audit_logs (every mutation logged)
--   * payment_amendment_requests (post-settlement edit/delete workflow)
--   * customer_account_statements (future-proof monthly statements)
--   * additive reconciliation columns on cod_settlements
--   * RPCs for the split delivery flow (PIN verify → pay → deliver atomically)
--   * customer credit via the existing wallets/adjust_wallet_balance()
--
-- All monetary columns introduced here are numeric(12,0) — whole PKR rupees,
-- no paisa — to avoid decimal drift. Idempotent + additive only; safe on
-- existing production data. Existing verify_delivery_otp() is left intact.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Additive order columns (payment tracking)
-- ----------------------------------------------------------------------------
alter table public.orders
  add column if not exists amount_paid numeric(12,0) not null default 0;
alter table public.orders
  add column if not exists outstanding_amount numeric(12,0) not null default 0;
alter table public.orders
  add column if not exists credit_applied numeric(12,0) not null default 0;

-- ----------------------------------------------------------------------------
-- 2. payment_transactions — permanent per-payment record
-- ----------------------------------------------------------------------------
create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  rider_id uuid references public.riders(id) on delete set null,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  amount numeric(12,0) not null check (amount >= 0),
  outstanding_before numeric(12,0) not null default 0,
  outstanding_after numeric(12,0) not null default 0,
  credit_before numeric(12,0) not null default 0,
  credit_after numeric(12,0) not null default 0,
  payment_type text not null check (payment_type in ('full','partial','over','credit','refund','adjustment')),
  status text not null default 'active' check (status in ('active','edited','deleted')),
  settled boolean not null default false,
  settlement_id uuid references public.cod_settlements(id) on delete set null,
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_pay_txn_order on public.payment_transactions(order_id);
create index if not exists idx_pay_txn_customer on public.payment_transactions(customer_profile_id);
create index if not exists idx_pay_txn_rider on public.payment_transactions(rider_id);
create index if not exists idx_pay_txn_vendor on public.payment_transactions(vendor_id);
create index if not exists idx_pay_txn_status on public.payment_transactions(status);
create index if not exists idx_pay_txn_settlement on public.payment_transactions(settlement_id);

-- ----------------------------------------------------------------------------
-- 3. payment_receipts — one-to-many attachments per payment
-- ----------------------------------------------------------------------------
create table if not exists public.payment_receipts (
  id uuid primary key default gen_random_uuid(),
  payment_transaction_id uuid not null references public.payment_transactions(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  receipt_type text not null default 'cash'
    check (receipt_type in ('cash','bank_transfer','signature','delivery_proof','other')),
  receipt_url text not null,
  image_hash text,
  gps_lat numeric,
  gps_lng numeric,
  device_time timestamptz,
  uploaded_at timestamptz not null default now(),
  uploaded_by uuid references public.profiles(id)
);

create index if not exists idx_pay_receipt_txn on public.payment_receipts(payment_transaction_id);
create unique index if not exists uq_pay_receipt_vendor_hash
  on public.payment_receipts(vendor_id, image_hash) where image_hash is not null;

-- ----------------------------------------------------------------------------
-- 4. payment_audit_logs — never lose financial history
-- ----------------------------------------------------------------------------
create table if not exists public.payment_audit_logs (
  id uuid primary key default gen_random_uuid(),
  payment_transaction_id uuid references public.payment_transactions(id) on delete set null,
  action text not null check (action in ('create','edit','delete','amend_request','amend_approve','amend_reject')),
  old_amount numeric(12,0),
  new_amount numeric(12,0),
  reason text,
  performed_by uuid references public.profiles(id),
  performed_at timestamptz not null default now()
);

create index if not exists idx_pay_audit_txn on public.payment_audit_logs(payment_transaction_id);

-- ----------------------------------------------------------------------------
-- 5. payment_amendment_requests — post-settlement edit/delete workflow
-- ----------------------------------------------------------------------------
create table if not exists public.payment_amendment_requests (
  id uuid primary key default gen_random_uuid(),
  payment_transaction_id uuid not null references public.payment_transactions(id) on delete cascade,
  rider_id uuid references public.riders(id) on delete set null,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  requested_action text not null check (requested_action in ('edit','delete')),
  requested_amount numeric(12,0),
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id)
);

create index if not exists idx_pay_amend_vendor_status on public.payment_amendment_requests(vendor_id, status);
create index if not exists idx_pay_amend_rider on public.payment_amendment_requests(rider_id);

-- ----------------------------------------------------------------------------
-- 6. cod_settlements — additive reconciliation columns
-- ----------------------------------------------------------------------------
alter table public.cod_settlements add column if not exists order_count int not null default 0;
alter table public.cod_settlements add column if not exists transaction_count int not null default 0;
alter table public.cod_settlements add column if not exists outstanding_remaining numeric(12,0);
alter table public.cod_settlements add column if not exists total_cash_collected numeric(12,0);
alter table public.cod_settlements add column if not exists total_cash_settled numeric(12,0);
alter table public.cod_settlements add column if not exists cash_difference numeric(12,0);
alter table public.cod_settlements add column if not exists verified_notes text;
alter table public.cod_settlements add column if not exists generated_by uuid references public.profiles(id);
alter table public.cod_settlements add column if not exists verified_by uuid references public.profiles(id);

-- ----------------------------------------------------------------------------
-- 7. customer_account_statements — future-proof monthly statements
-- ----------------------------------------------------------------------------
create table if not exists public.customer_account_statements (
  id uuid primary key default gen_random_uuid(),
  customer_profile_id uuid not null references public.profiles(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  opening_balance numeric(12,0) not null default 0,
  total_purchases numeric(12,0) not null default 0,
  total_paid numeric(12,0) not null default 0,
  total_credits numeric(12,0) not null default 0,
  total_refunds numeric(12,0) not null default 0,
  closing_balance numeric(12,0) not null default 0,
  generated_at timestamptz not null default now(),
  statement_url text,
  unique (customer_profile_id, vendor_id, period_start)
);

create index if not exists idx_cust_statement_customer on public.customer_account_statements(customer_profile_id);
create index if not exists idx_cust_statement_vendor on public.customer_account_statements(vendor_id);

-- ============================================================================
-- RLS
-- ============================================================================
alter table public.payment_transactions enable row level security;
alter table public.payment_receipts enable row level security;
alter table public.payment_audit_logs enable row level security;
alter table public.payment_amendment_requests enable row level security;
alter table public.customer_account_statements enable row level security;

-- payment_transactions: rider/vendor/customer see their own rows
drop policy if exists "pt_rider_select" on public.payment_transactions;
create policy "pt_rider_select" on public.payment_transactions for select
  using (rider_id in (select id from public.riders where profile_id = auth.uid()));
drop policy if exists "pt_vendor_select" on public.payment_transactions;
create policy "pt_vendor_select" on public.payment_transactions for select
  using (vendor_id in (select id from public.vendors where profile_id = auth.uid()));
drop policy if exists "pt_customer_select" on public.payment_transactions;
create policy "pt_customer_select" on public.payment_transactions for select
  using (customer_profile_id = auth.uid());

-- payment_receipts: same scoping via parent txn's vendor + rider/customer
drop policy if exists "pr_vendor_select" on public.payment_receipts;
create policy "pr_vendor_select" on public.payment_receipts for select
  using (vendor_id in (select id from public.vendors where profile_id = auth.uid()));
drop policy if exists "pr_rider_select" on public.payment_receipts;
create policy "pr_rider_select" on public.payment_receipts for select
  using (exists (
    select 1 from public.payment_transactions t
    join public.riders r on r.id = t.rider_id
    where t.id = payment_receipts.payment_transaction_id and r.profile_id = auth.uid()
  ));
drop policy if exists "pr_customer_select" on public.payment_receipts;
create policy "pr_customer_select" on public.payment_receipts for select
  using (exists (
    select 1 from public.payment_transactions t
    where t.id = payment_receipts.payment_transaction_id and t.customer_profile_id = auth.uid()
  ));

-- audit logs: rider (who performed) + vendor (owns the txn) can read
drop policy if exists "pal_select" on public.payment_audit_logs;
create policy "pal_select" on public.payment_audit_logs for select
  using (
    performed_by = auth.uid()
    or exists (
      select 1 from public.payment_transactions t
      join public.vendors v on v.id = t.vendor_id
      where t.id = payment_audit_logs.payment_transaction_id and v.profile_id = auth.uid()
    )
  );

-- amendment requests: rider (owner) + vendor (approver)
drop policy if exists "par_rider_select" on public.payment_amendment_requests;
create policy "par_rider_select" on public.payment_amendment_requests for select
  using (rider_id in (select id from public.riders where profile_id = auth.uid()));
drop policy if exists "par_vendor_select" on public.payment_amendment_requests;
create policy "par_vendor_select" on public.payment_amendment_requests for select
  using (vendor_id in (select id from public.vendors where profile_id = auth.uid()));

-- statements: customer (self) + vendor (owner)
drop policy if exists "cas_customer_select" on public.customer_account_statements;
create policy "cas_customer_select" on public.customer_account_statements for select
  using (customer_profile_id = auth.uid());
drop policy if exists "cas_vendor_select" on public.customer_account_statements;
create policy "cas_vendor_select" on public.customer_account_statements for select
  using (vendor_id in (select id from public.vendors where profile_id = auth.uid()));

-- ============================================================================
-- Helper: compute an order's outstanding (whole rupees)
-- ============================================================================
create or replace function public.order_outstanding(p_order_id uuid)
returns numeric
language sql
stable
as $$
  select greatest(
    round(coalesce(o.total_amount,0))
      - coalesce(o.amount_paid,0)
      - coalesce(o.credit_applied,0),
    0
  )
  from public.orders o where o.id = p_order_id;
$$;

-- ============================================================================
-- RPC: verify_delivery_pin_only — validate handoff code, NO state change
-- ============================================================================
create or replace function public.verify_delivery_pin_only(
  p_order_id uuid,
  p_entered_otp text
)
returns boolean
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_rider_profile_id uuid;
begin
  select o.* into v_order from public.orders o where o.id = p_order_id;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_order.rider_id;
  if v_rider_profile_id is null or v_rider_profile_id != auth.uid() then
    raise exception 'You are not the assigned rider for this order';
  end if;

  if v_order.status not in ('assigned','picked_up','on_the_way') then
    raise exception 'This order is not ready to be completed';
  end if;

  if v_order.rider_otp is distinct from p_entered_otp then
    raise exception 'Incorrect delivery code — ask the customer to confirm it';
  end if;

  return true;
end;
$$;

grant execute on function public.verify_delivery_pin_only(uuid, text) to authenticated;

-- ============================================================================
-- RPC: complete_delivery_with_payment — records payment + marks delivered
--       ATOMICALLY. Over-payment excess → customer wallet credit.
-- ============================================================================
create or replace function public.complete_delivery_with_payment(
  p_order_id uuid,
  p_entered_otp text,
  p_amount numeric,
  p_receipt_url text default null,
  p_receipt_meta jsonb default '{}'::jsonb,
  p_notes text default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_rider_profile_id uuid;
  v_outstanding numeric;
  v_credit_before numeric;
  v_credit_after numeric;
  v_applied numeric;      -- amount applied to this order's outstanding
  v_excess numeric;       -- overpayment → wallet credit
  v_pay_type text;
  v_txn_id uuid;
  v_amount numeric := round(coalesce(p_amount, 0));
begin
  -- Lock the order row to prevent double completion / races
  select o.* into v_order from public.orders o where o.id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_order.rider_id;
  if v_rider_profile_id is null or v_rider_profile_id != auth.uid() then
    raise exception 'You are not the assigned rider for this order';
  end if;

  if v_order.status = 'delivered' or v_order.status = 'completed' then
    raise exception 'This order has already been completed';
  end if;

  if v_order.status not in ('assigned','picked_up','on_the_way') then
    raise exception 'This order is not ready to be completed';
  end if;

  if v_order.rider_otp is distinct from p_entered_otp then
    raise exception 'Incorrect delivery code — ask the customer to confirm it';
  end if;

  if v_amount < 0 then
    raise exception 'Payment amount cannot be negative';
  end if;

  v_outstanding := public.order_outstanding(p_order_id);
  v_applied := least(v_amount, v_outstanding);
  v_excess := greatest(v_amount - v_outstanding, 0);

  -- Wallet credit before/after (over-payment lands in wallet)
  select coalesce(balance, 0) into v_credit_before
  from public.wallets where profile_id = v_order.customer_profile_id;
  v_credit_before := coalesce(v_credit_before, 0);

  if v_excess > 0 then
    perform public.adjust_wallet_balance(
      v_order.customer_profile_id, v_excess, 'credit', p_order_id, 'Overpayment credit'
    );
    v_credit_after := v_credit_before + v_excess;
  else
    v_credit_after := v_credit_before;
  end if;

  -- Classify the payment
  if v_amount = 0 then
    v_pay_type := 'partial';
  elsif v_excess > 0 then
    v_pay_type := 'over';
  elsif v_applied >= v_outstanding then
    v_pay_type := 'full';
  else
    v_pay_type := 'partial';
  end if;

  -- Update the order: paid + delivered
  update public.orders
    set amount_paid = coalesce(amount_paid,0) + v_applied,
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - (coalesce(amount_paid,0) + v_applied) - coalesce(credit_applied,0), 0),
        payment_status = case
          when greatest(round(coalesce(total_amount,0)) - (coalesce(amount_paid,0) + v_applied) - coalesce(credit_applied,0), 0) = 0
            then 'paid'::payment_status
          else payment_status
        end,
        status = 'delivered',
        delivered_at = now(),
        updated_at = now()
    where id = p_order_id
    returning * into v_order;

  update public.riders set total_deliveries = total_deliveries + 1 where id = v_order.rider_id;

  -- Insert the payment transaction (snapshots)
  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by
  ) values (
    p_order_id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_amount,
    v_outstanding, greatest(v_outstanding - v_applied, 0), v_credit_before, v_credit_after,
    v_pay_type, p_notes, auth.uid()
  ) returning id into v_txn_id;

  -- Optional receipt
  if p_receipt_url is not null and length(trim(p_receipt_url)) > 0 then
    insert into public.payment_receipts (
      payment_transaction_id, vendor_id, receipt_type, receipt_url,
      image_hash, gps_lat, gps_lng, device_time, uploaded_by
    ) values (
      v_txn_id, v_order.vendor_id,
      coalesce(p_receipt_meta->>'receipt_type', 'cash'),
      p_receipt_url,
      p_receipt_meta->>'image_hash',
      (p_receipt_meta->>'gps_lat')::numeric,
      (p_receipt_meta->>'gps_lng')::numeric,
      (p_receipt_meta->>'device_time')::timestamptz,
      auth.uid()
    );
  end if;

  insert into public.payment_audit_logs (payment_transaction_id, action, new_amount, reason, performed_by)
  values (v_txn_id, 'create', v_amount, 'Delivery payment collected', auth.uid());

  return json_build_object(
    'transaction_id', v_txn_id,
    'order_id', p_order_id,
    'amount', v_amount,
    'applied', v_applied,
    'excess_credit', v_excess,
    'outstanding_after', greatest(v_outstanding - v_applied, 0),
    'credit_after', v_credit_after,
    'payment_type', v_pay_type
  );
end;
$$;

grant execute on function public.complete_delivery_with_payment(uuid, text, numeric, text, jsonb, text) to authenticated;

-- ============================================================================
-- RPC: edit_payment — pre-settlement free edit; else raise (use amendment)
-- ============================================================================
create or replace function public.edit_payment(
  p_transaction_id uuid,
  p_new_amount numeric,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_order public.orders;
  v_new numeric := round(coalesce(p_new_amount, 0));
  v_delta numeric;
  v_rider_profile_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id for update;
  if v_txn.id is null then raise exception 'Payment not found'; end if;
  if v_txn.status = 'deleted' then raise exception 'Payment already deleted'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can edit this payment';
  end if;

  if v_txn.settled then
    raise exception 'This payment is already settled — submit an amendment request instead';
  end if;

  if v_new < 0 then raise exception 'Amount cannot be negative'; end if;

  v_delta := v_new - v_txn.amount;

  -- Adjust the order's amount_paid by the delta (bounded by outstanding logic)
  select * into v_order from public.orders where id = v_txn.order_id for update;
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid,0) + v_delta, 0),
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) + v_delta,0) - coalesce(credit_applied,0), 0),
        updated_at = now()
    where id = v_txn.order_id;

  update public.payment_transactions
    set amount = v_new, updated_at = now()
    where id = p_transaction_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (p_transaction_id, 'edit', v_txn.amount, v_new, p_reason, auth.uid());

  return json_build_object('transaction_id', p_transaction_id, 'new_amount', v_new);
end;
$$;

grant execute on function public.edit_payment(uuid, numeric, text) to authenticated;

-- ============================================================================
-- RPC: delete_payment — soft delete pre-settlement; else raise
-- ============================================================================
create or replace function public.delete_payment(
  p_transaction_id uuid,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_rider_profile_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id for update;
  if v_txn.id is null then raise exception 'Payment not found'; end if;
  if v_txn.status = 'deleted' then raise exception 'Payment already deleted'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can delete this payment';
  end if;

  if v_txn.settled then
    raise exception 'This payment is already settled — submit an amendment request instead';
  end if;

  -- Reverse the order effect
  update public.orders
    set amount_paid = greatest(coalesce(amount_paid,0) - v_txn.amount, 0),
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) - v_txn.amount,0) - coalesce(credit_applied,0), 0),
        payment_status = 'pending'::payment_status,
        updated_at = now()
    where id = v_txn.order_id;

  update public.payment_transactions
    set status = 'deleted', updated_at = now()
    where id = p_transaction_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (p_transaction_id, 'delete', v_txn.amount, 0, p_reason, auth.uid());

  return json_build_object('transaction_id', p_transaction_id, 'status', 'deleted');
end;
$$;

grant execute on function public.delete_payment(uuid, text) to authenticated;

-- ============================================================================
-- RPC: request_payment_amendment — post-settlement edit/delete request
-- ============================================================================
create or replace function public.request_payment_amendment(
  p_transaction_id uuid,
  p_action text,
  p_amount numeric,
  p_reason text
)
returns json
language plpgsql
security definer
as $$
declare
  v_txn public.payment_transactions;
  v_rider_profile_id uuid;
  v_req_id uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required';
  end if;
  if p_action not in ('edit','delete') then
    raise exception 'Invalid amendment action';
  end if;

  select * into v_txn from public.payment_transactions where id = p_transaction_id;
  if v_txn.id is null then raise exception 'Payment not found'; end if;

  select profile_id into v_rider_profile_id from public.riders where id = v_txn.rider_id;
  if v_rider_profile_id is distinct from auth.uid() then
    raise exception 'Only the collecting rider can request an amendment';
  end if;

  insert into public.payment_amendment_requests (
    payment_transaction_id, rider_id, vendor_id, requested_action, requested_amount, reason
  ) values (
    p_transaction_id, v_txn.rider_id, v_txn.vendor_id, p_action,
    case when p_action = 'edit' then round(coalesce(p_amount,0)) else null end, p_reason
  ) returning id into v_req_id;

  insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
  values (p_transaction_id, 'amend_request', v_txn.amount, round(coalesce(p_amount,0)), p_reason, auth.uid());

  return json_build_object('request_id', v_req_id, 'status', 'pending');
end;
$$;

grant execute on function public.request_payment_amendment(uuid, text, numeric, text) to authenticated;

-- ============================================================================
-- RPC: resolve_payment_amendment — vendor approves/rejects
-- ============================================================================
create or replace function public.resolve_payment_amendment(
  p_request_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_req public.payment_amendment_requests;
  v_txn public.payment_transactions;
  v_vendor_profile_id uuid;
  v_delta numeric;
begin
  select * into v_req from public.payment_amendment_requests where id = p_request_id for update;
  if v_req.id is null then raise exception 'Amendment request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'This request is already resolved'; end if;

  select profile_id into v_vendor_profile_id from public.vendors where id = v_req.vendor_id;
  if v_vendor_profile_id is distinct from auth.uid() then
    raise exception 'Only the vendor can resolve this request';
  end if;

  select * into v_txn from public.payment_transactions where id = v_req.payment_transaction_id for update;

  if p_approve then
    if v_req.requested_action = 'delete' then
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) - v_txn.amount, 0),
            outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) - v_txn.amount,0) - coalesce(credit_applied,0), 0),
            updated_at = now()
        where id = v_txn.order_id;
      update public.payment_transactions set status = 'deleted', updated_at = now() where id = v_txn.id;
    else -- edit
      v_delta := round(coalesce(v_req.requested_amount,0)) - v_txn.amount;
      update public.orders
        set amount_paid = greatest(coalesce(amount_paid,0) + v_delta, 0),
            outstanding_amount = greatest(round(coalesce(total_amount,0)) - greatest(coalesce(amount_paid,0) + v_delta,0) - coalesce(credit_applied,0), 0),
            updated_at = now()
        where id = v_txn.order_id;
      update public.payment_transactions set amount = round(coalesce(v_req.requested_amount,0)), updated_at = now() where id = v_txn.id;
    end if;

    update public.payment_amendment_requests
      set status = 'approved', resolved_at = now(), resolved_by = auth.uid()
      where id = p_request_id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_approve', v_txn.amount, round(coalesce(v_req.requested_amount, 0)), coalesce(p_reason, v_req.reason), auth.uid());
  else
    update public.payment_amendment_requests
      set status = 'rejected', resolved_at = now(), resolved_by = auth.uid()
      where id = p_request_id;

    insert into public.payment_audit_logs (payment_transaction_id, action, old_amount, new_amount, reason, performed_by)
    values (v_txn.id, 'amend_reject', v_txn.amount, v_txn.amount, coalesce(p_reason, 'Rejected'), auth.uid());
  end if;

  return json_build_object('request_id', p_request_id, 'approved', p_approve);
end;
$$;

grant execute on function public.resolve_payment_amendment(uuid, boolean, text) to authenticated;

-- ============================================================================
-- RPC: apply_customer_credit — consume wallet credit against a new order
-- ============================================================================
create or replace function public.apply_customer_credit(
  p_order_id uuid,
  p_amount numeric default null
)
returns json
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_balance numeric;
  v_outstanding numeric;
  v_apply numeric;
  v_txn_id uuid;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then raise exception 'Order not found'; end if;
  if v_order.customer_profile_id is distinct from auth.uid() then
    raise exception 'You can only apply credit to your own order';
  end if;

  select coalesce(balance,0) into v_balance from public.wallets where profile_id = v_order.customer_profile_id;
  v_balance := coalesce(v_balance, 0);
  v_outstanding := public.order_outstanding(p_order_id);

  v_apply := least(v_balance, v_outstanding);
  if p_amount is not null then
    v_apply := least(v_apply, round(p_amount));
  end if;

  if v_apply <= 0 then
    return json_build_object('applied', 0, 'outstanding_after', v_outstanding);
  end if;

  perform public.adjust_wallet_balance(
    v_order.customer_profile_id, v_apply, 'debit', p_order_id, 'Credit applied to order'
  );

  update public.orders
    set credit_applied = coalesce(credit_applied,0) + v_apply,
        outstanding_amount = greatest(round(coalesce(total_amount,0)) - coalesce(amount_paid,0) - (coalesce(credit_applied,0) + v_apply), 0),
        updated_at = now()
    where id = p_order_id;

  insert into public.payment_transactions (
    order_id, customer_profile_id, rider_id, vendor_id, amount,
    outstanding_before, outstanding_after, credit_before, credit_after,
    payment_type, notes, created_by
  ) values (
    p_order_id, v_order.customer_profile_id, v_order.rider_id, v_order.vendor_id, v_apply,
    v_outstanding, greatest(v_outstanding - v_apply, 0), v_balance, v_balance - v_apply,
    'credit', 'Wallet credit applied', auth.uid()
  ) returning id into v_txn_id;

  return json_build_object('applied', v_apply, 'outstanding_after', greatest(v_outstanding - v_apply, 0), 'transaction_id', v_txn_id);
end;
$$;

grant execute on function public.apply_customer_credit(uuid, numeric) to authenticated;

-- ============================================================================
-- RPC: get_customer_ledger — accounting-style ledger for one customer
-- ============================================================================
create or replace function public.get_customer_ledger(p_customer_profile_id uuid)
returns json
language plpgsql
security definer
as $$
declare
  v_total_purchases numeric;
  v_total_paid numeric;
  v_outstanding numeric;
  v_credit numeric;
  v_last_payment timestamptz;
  v_entries json;
begin
  select coalesce(sum(round(total_amount)), 0) into v_total_purchases
  from public.orders where customer_profile_id = p_customer_profile_id;

  select coalesce(sum(amount), 0) into v_total_paid
  from public.payment_transactions
  where customer_profile_id = p_customer_profile_id
    and status = 'active' and payment_type in ('full','partial','over','credit');

  select coalesce(sum(outstanding_amount), 0) into v_outstanding
  from public.orders where customer_profile_id = p_customer_profile_id;

  select coalesce(balance, 0) into v_credit
  from public.wallets where profile_id = p_customer_profile_id;
  v_credit := coalesce(v_credit, 0);

  select max(created_at) into v_last_payment
  from public.payment_transactions
  where customer_profile_id = p_customer_profile_id and status = 'active';

  select json_agg(e order by e.created_at desc) into v_entries
  from (
    select t.id, t.order_id, o.order_number, t.amount, t.payment_type,
           t.outstanding_before, t.outstanding_after, t.notes, t.status, t.created_at
    from public.payment_transactions t
    join public.orders o on o.id = t.order_id
    where t.customer_profile_id = p_customer_profile_id
  ) e;

  return json_build_object(
    'total_purchases', v_total_purchases,
    'total_paid', v_total_paid,
    'outstanding', v_outstanding,
    'available_credit', v_credit,
    'last_payment_at', v_last_payment,
    'entries', coalesce(v_entries, '[]'::json)
  );
end;
$$;

grant execute on function public.get_customer_ledger(uuid) to authenticated;

-- ============================================================================
-- RPC: get_settlement_detail — audit detail for one settlement
-- ============================================================================
create or replace function public.get_settlement_detail(p_settlement_id uuid)
returns json
language plpgsql
security definer
as $$
declare
  v_s public.cod_settlements;
  v_rider_name text;
  v_vendor_name text;
  v_verified_by_name text;
  v_payments json;
begin
  select * into v_s from public.cod_settlements where id = p_settlement_id;
  if v_s.id is null then raise exception 'Settlement not found'; end if;

  select p.full_name into v_rider_name from public.riders r join public.profiles p on p.id = r.profile_id where r.id = v_s.rider_id;
  select business_name into v_vendor_name from public.vendors where id = v_s.vendor_id;
  select full_name into v_verified_by_name from public.profiles where id = v_s.verified_by;

  select json_agg(json_build_object(
    'id', t.id, 'order_id', t.order_id, 'amount', t.amount, 'payment_type', t.payment_type, 'created_at', t.created_at
  )) into v_payments
  from public.payment_transactions t
  where t.settlement_id = p_settlement_id and t.status = 'active';

  return json_build_object(
    'id', v_s.id,
    'code', v_s.code,
    'status', v_s.status,
    'amount', v_s.amount,
    'rider_name', coalesce(v_rider_name, 'Unknown'),
    'vendor_name', coalesce(v_vendor_name, 'Unknown'),
    'verified_by', v_verified_by_name,
    'order_count', v_s.order_count,
    'transaction_count', v_s.transaction_count,
    'total_cash_collected', v_s.total_cash_collected,
    'total_cash_settled', v_s.total_cash_settled,
    'cash_difference', v_s.cash_difference,
    'outstanding_remaining', v_s.outstanding_remaining,
    'created_at', v_s.created_at,
    'expires_at', v_s.expires_at,
    'verified_at', v_s.verified_at,
    'payments', coalesce(v_payments, '[]'::json)
  );
end;
$$;

grant execute on function public.get_settlement_detail(uuid) to authenticated;

-- ============================================================================
-- RPC: get_vendor_payment_overview — per-customer financial summary rows
-- ============================================================================
create or replace function public.get_vendor_payment_overview(p_vendor_id uuid)
returns json[]
language plpgsql
security definer
as $$
declare
  v_caller uuid;
  v_results json[];
begin
  select id into v_caller from public.vendors where id = p_vendor_id and profile_id = auth.uid();
  if v_caller is null then raise exception 'Not authorized'; end if;

  select array_agg(row_to_json(x)) into v_results from (
    select
      c.profile_id,
      p.full_name,
      p.phone,
      count(distinct o.id) as total_orders,
      coalesce(sum(round(o.total_amount)), 0) as total_purchases,
      coalesce(sum(o.amount_paid), 0) as total_paid,
      coalesce(sum(o.outstanding_amount), 0) as outstanding,
      coalesce((select balance from public.wallets w where w.profile_id = c.profile_id), 0) as available_credit,
      (select max(t.created_at) from public.payment_transactions t where t.customer_profile_id = c.profile_id and t.status='active') as last_payment_at,
      case
        when coalesce(sum(o.outstanding_amount),0) = 0 and count(o.id) > 0 then 'fully_paid'
        when coalesce(sum(o.amount_paid),0) > 0 then 'partially_paid'
        else 'pending'
      end as payment_status
    from public.customers c
    join public.profiles p on p.id = c.profile_id
    left join public.orders o on o.customer_profile_id = c.profile_id and o.vendor_id = p_vendor_id
    where c.vendor_id = p_vendor_id
    group by c.profile_id, p.full_name, p.phone
  ) x;

  return coalesce(v_results, '{}');
end;
$$;

grant execute on function public.get_vendor_payment_overview(uuid) to authenticated;

-- ============================================================================
-- RPC: get_vendor_rider_cash_positions — per-rider cash reconciliation
-- ============================================================================
create or replace function public.get_vendor_rider_cash_positions(p_vendor_id uuid)
returns json[]
language plpgsql
security definer
as $$
declare
  v_caller uuid;
  v_results json[];
begin
  select id into v_caller from public.vendors where id = p_vendor_id and profile_id = auth.uid();
  if v_caller is null then raise exception 'Not authorized'; end if;

  select array_agg(row_to_json(x)) into v_results from (
    select
      r.id as rider_id,
      p.full_name as rider_name,
      coalesce((
        select sum(t.amount) from public.payment_transactions t
        where t.rider_id = r.id and t.vendor_id = p_vendor_id and t.status='active'
          and t.payment_type in ('full','partial','over')
      ), 0) as collected,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status='verified'
      ), 0) as settled,
      coalesce((
        select sum(s.amount) from public.cod_settlements s
        where s.rider_id = r.id and s.vendor_id = p_vendor_id and s.status='pending'
      ), 0) as pending_settlement
    from public.riders r
    join public.profiles p on p.id = r.profile_id
    where r.vendor_id = p_vendor_id
  ) x;

  return coalesce(v_results, '{}');
end;
$$;

grant execute on function public.get_vendor_rider_cash_positions(uuid) to authenticated;

-- ============================================================================
-- RPC: get_vendor_finance_kpis — dashboard KPI aggregates
-- ============================================================================
create or replace function public.get_vendor_finance_kpis(p_vendor_id uuid)
returns json
language plpgsql
security definer
as $$
declare
  v_caller uuid;
  v_today_start timestamptz := date_trunc('day', now());
  v_month_start timestamptz := date_trunc('month', now());
  v_todays_collection numeric;
  v_months_collection numeric;
  v_pending_collection numeric;
  v_outstanding_customers int;
  v_credits_issued numeric;
  v_refunds numeric;
  v_partial_count int;
  v_awaiting_settlement numeric;
begin
  select id into v_caller from public.vendors where id = p_vendor_id and profile_id = auth.uid();
  if v_caller is null then raise exception 'Not authorized'; end if;

  select coalesce(sum(amount),0) into v_todays_collection
  from public.payment_transactions
  where vendor_id = p_vendor_id and status='active'
    and payment_type in ('full','partial','over') and created_at >= v_today_start;

  select coalesce(sum(amount),0) into v_months_collection
  from public.payment_transactions
  where vendor_id = p_vendor_id and status='active'
    and payment_type in ('full','partial','over') and created_at >= v_month_start;

  select coalesce(sum(outstanding_amount),0) into v_pending_collection
  from public.orders where vendor_id = p_vendor_id;

  select count(distinct customer_profile_id) into v_outstanding_customers
  from public.orders where vendor_id = p_vendor_id and outstanding_amount > 0;

  select coalesce(sum(amount),0) into v_credits_issued
  from public.payment_transactions
  where vendor_id = p_vendor_id and status='active' and payment_type = 'over';

  select coalesce(sum(amount),0) into v_refunds
  from public.payment_transactions
  where vendor_id = p_vendor_id and payment_type = 'refund';

  select count(*) into v_partial_count
  from public.payment_transactions
  where vendor_id = p_vendor_id and status='active' and payment_type = 'partial';

  select coalesce(sum(amount),0) into v_awaiting_settlement
  from public.payment_transactions
  where vendor_id = p_vendor_id and status='active' and settled = false
    and payment_type in ('full','partial','over');

  return json_build_object(
    'todays_collection', v_todays_collection,
    'months_collection', v_months_collection,
    'pending_collection', v_pending_collection,
    'outstanding_customers', v_outstanding_customers,
    'credits_issued', v_credits_issued,
    'refunds', v_refunds,
    'partial_count', v_partial_count,
    'awaiting_settlement', v_awaiting_settlement
  );
end;
$$;

grant execute on function public.get_vendor_finance_kpis(uuid) to authenticated;

-- ============================================================================
-- Extend generate_cod_settlement / verify_cod_settlement (additive columns)
-- Keeps the original JSON contract; only enriches the stored row + flips
-- covered payment_transactions to settled on verify.
-- ============================================================================
create or replace function public.generate_cod_settlement(
  p_rider_id uuid,
  p_vendor_id uuid,
  p_amount numeric
)
returns json
language plpgsql
security definer
as $$
declare
  v_code text;
  v_id uuid;
  v_outstanding numeric;
  v_collected numeric;
  v_txn_count int;
  v_order_count int;
begin
  loop
    v_code := lpad((floor(random() * 1000000))::text, 6, '0');
    exit when not exists (
      select 1 from public.cod_settlements where code = v_code and status = 'pending'
    );
  end loop;

  -- Snapshot the rider's collected cash + counts for this vendor
  select coalesce(sum(t.amount),0), count(*), count(distinct t.order_id)
  into v_collected, v_txn_count, v_order_count
  from public.payment_transactions t
  where t.rider_id = p_rider_id and t.vendor_id = p_vendor_id
    and t.status = 'active' and t.settled = false
    and t.payment_type in ('full','partial','over');

  insert into public.cod_settlements (
    rider_id, vendor_id, amount, code,
    order_count, transaction_count, total_cash_collected, generated_by
  )
  values (
    p_rider_id, p_vendor_id, p_amount, v_code,
    coalesce(v_order_count,0), coalesce(v_txn_count,0), coalesce(v_collected,0), auth.uid()
  )
  returning id into v_id;

  select coalesce(sum(case when status = 'pending' then amount else 0 end), 0)
  into v_outstanding
  from public.cod_settlements
  where rider_id = p_rider_id and vendor_id = p_vendor_id and status = 'pending';

  return json_build_object(
    'id', v_id,
    'code', v_code,
    'amount', p_amount,
    'outstanding_after', v_outstanding
  );
end;
$$;

grant execute on function public.generate_cod_settlement(uuid, uuid, numeric) to authenticated;

create or replace function public.verify_cod_settlement(
  p_code text,
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
as $$
declare
  v_settlement record;
  v_rider_name text;
  v_outstanding_before numeric;
  v_outstanding_after numeric;
  v_txn_count int;
  v_order_count int;
begin
  select * into v_settlement
  from public.cod_settlements
  where code = p_code and vendor_id = p_vendor_id and status = 'pending' and expires_at > now();

  if v_settlement is null then
    raise exception 'Invalid or expired settlement code' using errcode = 'P0001';
  end if;

  select coalesce(sum(amount), 0) into v_outstanding_before
  from public.cod_settlements
  where rider_id = v_settlement.rider_id and vendor_id = p_vendor_id and status = 'pending';

  -- Flip the rider's covered (unsettled) payments to settled, tag them
  update public.payment_transactions
    set settled = true, settlement_id = v_settlement.id, updated_at = now()
    where rider_id = v_settlement.rider_id and vendor_id = p_vendor_id
      and status = 'active' and settled = false
      and payment_type in ('full','partial','over');

  select count(*), count(distinct order_id) into v_txn_count, v_order_count
  from public.payment_transactions where settlement_id = v_settlement.id;

  update public.cod_settlements
  set status = 'verified',
      verified_at = now(),
      verified_by = auth.uid(),
      transaction_count = coalesce(v_txn_count,0),
      order_count = coalesce(v_order_count,0),
      total_cash_settled = v_settlement.amount,
      cash_difference = coalesce(total_cash_collected,0) - v_settlement.amount,
      outstanding_remaining = greatest(v_outstanding_before - v_settlement.amount, 0)
  where id = v_settlement.id;

  v_outstanding_after := v_outstanding_before - v_settlement.amount;

  select p.full_name into v_rider_name
  from public.riders r join public.profiles p on p.id = r.profile_id
  where r.id = v_settlement.rider_id;

  return json_build_object(
    'settlement_id', v_settlement.id,
    'rider_name', coalesce(v_rider_name, 'Unknown Rider'),
    'amount', v_settlement.amount,
    'created_at', v_settlement.created_at,
    'outstanding_before', v_outstanding_before,
    'outstanding_after', v_outstanding_after
  );
end;
$$;

grant execute on function public.verify_cod_settlement(text, uuid) to authenticated;

-- ============================================================================
-- End of migration 0024
-- ============================================================================
