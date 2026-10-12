-- Phase 4D — PROS FULL DATA FROM SERVER (rating + review_count)
-- BACKGROUND: client feed relies on live pros hydrated from Supabase.
--   Rating/review_count were hardcoded (5.0 / 0) — misleading.
-- GOAL: extend list_approved_professionals() to compute per-pro:
--   * rating = mean of non-null ratings on completed orders
--   * review_count = count of such orders
-- NON-GOALS: no Dart changes here.

drop function if exists public.list_approved_professionals();

create or replace function public.list_approved_professionals()
returns table (
  id              uuid,
  name            text,
  phone           text,
  email           text,
  specialty       text,
  bio             text,
  category_id     text,
  service_ids     jsonb,
  work_images     jsonb,
  zones           jsonb,
  pricing_type    text,
  price_from      numeric,
  badges          jsonb,
  is_verified     boolean,
  status          text,
  created_at      timestamptz,
  rating          numeric,
  review_count    integer
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.id,
    coalesce(pr.full_name, '')::text          as name,
    coalesce(pr.phone, '')::text              as phone,
    coalesce(pr.email, '')::text              as email,
    coalesce(p.specialty, '')::text           as specialty,
    coalesce(p.bio, '')::text                 as bio,
    p.category_id,
    p.service_ids,
    p.work_images,
    p.zones,
    p.pricing_type,
    p.price_from,
    p.badges,
    p.is_verified,
    p.status,
    p.created_at,
    coalesce(
      (select avg(o.rating)
         from public.orders o
        where o.pro_id = p.id
          and o.status = 'completed'
          and o.rating is not null),
      0.0
    )::numeric(3,2) as rating,
    coalesce(
      (select count(*)
         from public.orders o
        where o.pro_id = p.id
          and o.status = 'completed'
          and o.rating is not null),
      0
    )::integer as review_count
  from public.professionals p
  join public.profiles pr on pr.id = p.id
  where p.status = 'approved' and p.is_verified = true
  order by p.created_at desc;
$$;

comment on function public.list_approved_professionals() is
  'Returns APPROVED + VERIFIED professionals joined with profiles. '
  'Includes rating + review_count computed from public.orders. '
  'Readable by any authenticated user. SECURITY DEFINER, STABLE.';

revoke all on function public.list_approved_professionals()
  from public, anon, authenticated;
grant execute on function public.list_approved_professionals()
  to authenticated;

-- Verification (commented)
-- select id, name, specialty, category_id, rating, review_count
-- from public.list_approved_professionals();
