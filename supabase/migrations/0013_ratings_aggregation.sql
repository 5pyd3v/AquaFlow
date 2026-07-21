-- ============================================================================
-- AquaFlow — Post-delivery ratings: integrity + auto-aggregation (Migration 0013)
--
-- The `ratings` table (0001) and its RLS (0002) already exist, but there
-- was nothing keeping vendors.rating / riders.rating in sync with the
-- reviews customers leave, and nothing stopping a customer from rating
-- the same order twice. This migration closes both gaps:
--
--   1. Uniqueness — one rating per (order, rated rider) and per
--      (order, rated vendor), so re-opening the rating sheet updates
--      rather than duplicates.
--   2. Aggregation trigger — after any insert/update/delete on ratings,
--      recompute the affected rider's / vendor's average `rating` from
--      the underlying rows. Ratings default to 5.0 until the first real
--      review lands.
--   3. `has_rated_order` RPC — cheap check the client uses to decide
--      whether to auto-open the rating sheet on a delivered order.
-- ============================================================================

-- 1. Prevent duplicate ratings for the same target on the same order.
--    Partial unique indexes because either rated_*_id may be null.
create unique index if not exists uq_ratings_order_rider
  on public.ratings(order_id, rated_rider_id)
  where rated_rider_id is not null;

create unique index if not exists uq_ratings_order_vendor
  on public.ratings(order_id, rated_vendor_id)
  where rated_vendor_id is not null;

-- 2. Recompute aggregate ratings whenever a row changes.
create or replace function public.recompute_rating_aggregates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rider_id uuid := coalesce(new.rated_rider_id, old.rated_rider_id);
  v_vendor_id uuid := coalesce(new.rated_vendor_id, old.rated_vendor_id);
begin
  if v_rider_id is not null then
    update public.riders r
    set rating = coalesce((
      select round(avg(stars)::numeric, 1)
      from public.ratings
      where rated_rider_id = v_rider_id
    ), 5.0)
    where r.id = v_rider_id;
  end if;

  if v_vendor_id is not null then
    update public.vendors v
    set rating = coalesce((
      select round(avg(stars)::numeric, 1)
      from public.ratings
      where rated_vendor_id = v_vendor_id
    ), 5.0)
    where v.id = v_vendor_id;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_ratings_aggregate on public.ratings;
create trigger trg_ratings_aggregate
  after insert or update or delete on public.ratings
  for each row execute function public.recompute_rating_aggregates();

-- 3. Has the current user already rated this order?
create or replace function public.has_rated_order(p_order_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ratings
    where order_id = p_order_id
      and rater_profile_id = auth.uid()
  );
$$;

grant execute on function public.has_rated_order(uuid) to authenticated;
