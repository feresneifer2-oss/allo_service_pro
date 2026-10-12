-- Phase 4C — CLIENT CAN READ APPROVED PROS
-- BACKGROUND: professionals RLS only has 'professionals_select_own_row'
--   (auth.uid() = id). Clients cannot read other pros. Since Phase 4B,
--   the release build shows ONLY live pros (mock removed) → empty feed.
-- GOAL:
--   1. New SELECT policy: authenticated can read approved + verified pros.
--   2. RPC list_approved_professionals() returns all public pro data
--      (joined with profiles for name/phone/email).
-- NON-GOALS:
--   - No changes to existing professionals_select_own_row.
--   - No changes to insert/update policies.
--   - No Dart changes here (separate batch).

-- 1. New SELECT policy (additive — old policy stays)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'professionals'
      and policyname = 'professionals_select_approved'
  ) then
    create policy professionals_select_approved
      on public.professionals
      for select
      to authenticated
      using (status = 'approved' and is_verified = true);
  end if;
end $$;

-- 2. RPC to fetch approved pros with joined profile data
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
  created_at      timestamptz
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
    p.created_at
  from public.professionals p
  join public.profiles pr on pr.id = p.id
  where p.status = 'approved' and p.is_verified = true
  order by p.created_at desc;
$$;

comment on function public.list_approved_professionals() is
  'Returns the list of APPROVED + VERIFIED professionals joined with their '
  'profiles (name, phone, email). Readable by any authenticated user. '
  'SECURITY DEFINER, STABLE, search_path pinned.';

-- 3. Grant execute to authenticated only
revoke all on function public.list_approved_professionals()
  from public, anon, authenticated;
grant execute on function public.list_approved_professionals()
  to authenticated;

-- 4. Verification (commented)
-- select policyname from pg_policies
--   where schemaname='public' and tablename='professionals'
--   order by policyname;
-- -- expected: professionals_select_approved + professionals_select_own_row
--
-- select oid::regprocedure from pg_proc
--   where proname = 'list_approved_professionals';
