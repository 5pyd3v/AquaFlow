-- ============================================================================
-- AquaFlow — place_order RPC (Migration 0006)
--
-- Wraps order + order_items creation in a single atomic transaction.
-- The Flutter client has no multi-statement transaction primitive
-- over PostgREST, so anything that must succeed-or-fail as a unit
-- (an order header plus N line items) goes through an RPC like this
-- one instead of two sequential `.insert()` calls that could leave a
-- half-written order if the second one fails.
-- ============================================================================

create or replace function public.place_order(
  p_address_id uuid,
  p_vendor_id uuid,
  p_items jsonb, -- [{ "product_id": uuid, "quantity": int, "unit_price": numeric, "unit_deposit": numeric }]
  p_payment_method payment_method default 'cod',
  p_is_emergency boolean default false,
  p_coupon_id uuid default null,
  p_discount_amount numeric default 0,
  p_delivery_fee numeric default 0,
  p_scheduled_for timestamptz default null
)
returns public.orders
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_item jsonb;
  v_subtotal numeric := 0;
  v_deposit_total numeric := 0;
  v_customer_id uuid := auth.uid();
begin
  if v_customer_id is null then
    raise exception 'Not authenticated';
  end if;

  if jsonb_array_length(p_items) = 0 then
    raise exception 'Cannot place an order with no items';
  end if;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_subtotal := v_subtotal + ((v_item->>'unit_price')::numeric * (v_item->>'quantity')::int);
    v_deposit_total := v_deposit_total + ((v_item->>'unit_deposit')::numeric * (v_item->>'quantity')::int);
  end loop;

  insert into public.orders (
    customer_profile_id, vendor_id, address_id, status, is_emergency,
    subtotal, deposit_total, discount_amount, delivery_fee, total_amount,
    coupon_id, payment_method, payment_status, scheduled_for
  ) values (
    v_customer_id, p_vendor_id, p_address_id, 'pending', p_is_emergency,
    v_subtotal, v_deposit_total, p_discount_amount, p_delivery_fee,
    (v_subtotal + v_deposit_total + p_delivery_fee - p_discount_amount),
    p_coupon_id, p_payment_method,
    case when p_payment_method = 'cod' then 'pending' else 'pending' end,
    p_scheduled_for
  )
  returning * into v_order;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into public.order_items (order_id, product_id, quantity, unit_price, unit_deposit)
    values (
      v_order.id,
      (v_item->>'product_id')::uuid,
      (v_item->>'quantity')::int,
      (v_item->>'unit_price')::numeric,
      (v_item->>'unit_deposit')::numeric
    );

    update public.products
      set stock_quantity = greatest(stock_quantity - (v_item->>'quantity')::int, 0)
      where id = (v_item->>'product_id')::uuid;
  end loop;

  if p_coupon_id is not null then
    update public.coupons set used_count = used_count + 1 where id = p_coupon_id;
  end if;

  return v_order;
end;
$$;

grant execute on function public.place_order(uuid, uuid, jsonb, payment_method, boolean, uuid, numeric, numeric, timestamptz) to authenticated;
