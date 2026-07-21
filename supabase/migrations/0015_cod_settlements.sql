-- COD Settlements System
-- Run this migration in the Supabase SQL editor

-- 1. Create the cod_settlements table
create table if not exists public.cod_settlements (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.riders(id) on delete cascade,
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  code text not null unique,
  status text not null default 'pending' check (status in ('pending', 'verified', 'expired')),
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  expires_at timestamptz not null default (now() + interval '24 hours')
);

-- Indexes
create index if not exists idx_cod_settlements_rider on public.cod_settlements(rider_id);
create index if not exists idx_cod_settlements_vendor on public.cod_settlements(vendor_id);
create index if not exists idx_cod_settlements_code on public.cod_settlements(code) where status = 'pending';
create index if not exists idx_cod_settlements_status on public.cod_settlements(status);

-- RLS
alter table public.cod_settlements enable row level security;

create policy "Riders see own settlements"
  on public.cod_settlements for select
  using (rider_id in (
    select id from public.riders where profile_id = auth.uid()
  ));

create policy "Vendors see own settlements"
  on public.cod_settlements for select
  using (vendor_id in (
    select id from public.vendors where profile_id = auth.uid()
  ));

-- 2. Generate COD Settlement (called by rider)
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
begin
  -- Generate unique 6-digit code
  loop
    v_code := lpad((floor(random() * 1000000))::text, 6, '0');
    exit when not exists (
      select 1 from public.cod_settlements
      where code = v_code and status = 'pending'
    );
  end loop;

  -- Insert settlement record
  insert into public.cod_settlements (rider_id, vendor_id, amount, code)
  values (p_rider_id, p_vendor_id, p_amount, v_code)
  returning id into v_id;

  -- Calculate outstanding after
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

-- 3. Verify COD Settlement (called by vendor)
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
begin
  -- Find the pending settlement
  select * into v_settlement
  from public.cod_settlements
  where code = p_code
    and vendor_id = p_vendor_id
    and status = 'pending'
    and expires_at > now();

  if v_settlement is null then
    raise exception 'Invalid or expired settlement code'
      using errcode = 'P0001';
  end if;

  -- Get outstanding before verification
  select coalesce(sum(amount), 0) into v_outstanding_before
  from public.cod_settlements
  where rider_id = v_settlement.rider_id
    and vendor_id = p_vendor_id
    and status = 'pending';

  -- Mark as verified
  update public.cod_settlements
  set status = 'verified', verified_at = now()
  where id = v_settlement.id;

  -- Get outstanding after
  v_outstanding_after := v_outstanding_before - v_settlement.amount;

  -- Get rider name
  select p.full_name into v_rider_name
  from public.riders r
  join public.profiles p on p.id = r.profile_id
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

-- 4. Get rider COD balance (per vendor)
create or replace function public.get_rider_cod_balance(
  p_rider_id uuid,
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
as $$
declare
  v_outstanding numeric;
  v_pending numeric;
  v_total_submitted numeric;
  v_total_verified numeric;
  v_total_collected numeric;
begin
  select
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0),
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0),
    coalesce(sum(amount), 0),
    coalesce(sum(case when status = 'verified' then amount else 0 end), 0)
  into v_pending, v_outstanding, v_total_submitted, v_total_verified
  from public.cod_settlements
  where rider_id = p_rider_id and vendor_id = p_vendor_id;

  -- Total collected from completed COD orders assigned to this rider
  select coalesce(sum(total_amount), 0) into v_total_collected
  from public.orders
  where vendor_id = p_vendor_id
    and rider_id = p_rider_id
    and status in ('delivered', 'completed')
    and payment_method = 'cod';

  -- Outstanding = collected - verified
  v_outstanding := v_total_collected - v_total_verified;
  if v_outstanding < 0 then v_outstanding := 0; end if;

  return json_build_object(
    'outstanding', v_outstanding,
    'pending', v_pending,
    'total_submitted', v_total_submitted,
    'total_verified', v_total_verified,
    'total_collected', v_total_collected
  );
end;
$$;

-- 5. Get vendor COD summary
create or replace function public.get_vendor_cod_summary(
  p_vendor_id uuid
)
returns json
language plpgsql
security definer
as $$
declare
  v_todays_verified numeric;
  v_total_verified numeric;
  v_pending_count int;
  v_pending_amount numeric;
  v_today_start timestamptz;
begin
  v_today_start := date_trunc('day', now());

  select
    coalesce(sum(case when status = 'verified' and verified_at >= v_today_start then amount else 0 end), 0),
    coalesce(sum(case when status = 'verified' then amount else 0 end), 0),
    count(case when status = 'pending' then 1 end),
    coalesce(sum(case when status = 'pending' then amount else 0 end), 0)
  into v_todays_verified, v_total_verified, v_pending_count, v_pending_amount
  from public.cod_settlements
  where vendor_id = p_vendor_id;

  return json_build_object(
    'todays_verified', v_todays_verified,
    'total_verified', v_total_verified,
    'pending_count', v_pending_count,
    'pending_amount', v_pending_amount
  );
end;
$$;

-- 6. Scheduled job to expire old settlements (run via pg_cron or Edge Function)
-- This marks settlements as expired if they pass 24h without verification.
-- If you don't have pg_cron, run this periodically via an Edge Function or cron job.
-- SELECT cron.schedule('expire-cod-settlements', '*/15 * * * *',
--   $$UPDATE public.cod_settlements SET status = 'expired' WHERE status = 'pending' AND expires_at < now()$$
-- );
