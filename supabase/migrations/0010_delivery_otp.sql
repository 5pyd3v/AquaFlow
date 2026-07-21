-- ============================================================================
-- AquaFlow — Delivery OTP (Migration 0010)
--
-- Generates a 4-digit handoff code the moment a rider is assigned,
-- and verifies it via a SECURITY DEFINER RPC rather than letting the
-- rider's client read `orders.rider_otp` directly. This means the
-- correct code is never sent to the rider's device at all — only a
-- pass/fail result — which is the actual point of an OTP handoff
-- (the customer reads the code to the rider in person; the rider's
-- app should never be able to look it up).
-- ============================================================================

create or replace function public.generate_delivery_otp()
returns trigger
language plpgsql
as $$
begin
  if new.rider_id is not null and (old.rider_id is null or old.rider_id != new.rider_id) and new.rider_otp is null then
    new.rider_otp := lpad(floor(random() * 10000)::text, 4, '0');
  end if;
  return new;
end;
$$;

create trigger trg_orders_generate_delivery_otp
  before update of rider_id on public.orders
  for each row execute function public.generate_delivery_otp();

create or replace function public.verify_delivery_otp(p_order_id uuid, p_entered_otp text)
returns public.orders
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

  if v_order.status not in ('assigned', 'picked_up', 'on_the_way') then
    raise exception 'This order is not ready to be completed';
  end if;

  if v_order.rider_otp is distinct from p_entered_otp then
    raise exception 'Incorrect delivery code — ask the customer to confirm it';
  end if;

  update public.orders
    set status = 'delivered', delivered_at = now()
    where id = p_order_id
    returning * into v_order;

  update public.riders
    set total_deliveries = total_deliveries + 1
    where id = v_order.rider_id;

  return v_order;
end;
$$;

grant execute on function public.verify_delivery_otp(uuid, text) to authenticated;
