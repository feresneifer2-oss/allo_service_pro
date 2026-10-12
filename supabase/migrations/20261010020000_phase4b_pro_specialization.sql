-- ============================================================================
-- PHASE 4B - PRO SPECIALIZATION (category_id + service_ids)
-- (allo_service_pro)
-- Idempotent + additive - safe to run twice (every DDL statement is guarded).
-- ============================================================================
-- BACKGROUND:
--   * Pros currently store their category as a FREE-TEXT label
--     (professionFr / professionAr) and their services as ONE comma-joined
--     text column (`specialty`, chips joined client-side). Search matches by
--     fuzzy label `contains` (professionals_repository.forService /
--     search_service) and LIVE approved pros carry EMPTY serviceIds lists -
--     matching precision depends on label wording, not on stable ids.
--   * public.professionals already carries: id, is_verified, specialty, bio
--     (baseline + 3N), status, rejection_reason, approved_at (3P),
--     tokens, paid_until (3S), proof_path, selfie_path, work_images,
--     badges, zones, pricing_type, price_from (3U).
--
-- GOAL (this phase ONLY):
--   1. Add 2 columns to public.professionals (idempotent):
--      category_id text (ServicesCatalog.categories ids: 'home', 'auto',
--      'health', 'beauty', ...) and service_ids jsonb array of text
--      (CatalogType ids: ['auto:electricien', 'auto:diagnostic']).
--   2. Indexes: B-tree on category_id, GIN on service_ids (jsonb containment).
--   3. Extend the Phase 3U RPC public.pro_update_profile(...) with OPTIONAL
--      p_category_id / p_service_ids (new 8-param signature; the old 6-param
--      signature is dropped first).
--   4. admin_provision_professional is untouched: it never reads/writes these
--      columns, so a NULL/empty value is preserved by omission.
--
-- NON-GOALS (separate phases, untouched here):
--   * NO Dart/Flutter change in this file - existing call sites keep working:
--     extra params are appended with default null and the current
--     profile_repository.dart calls use NAMED arguments.
--   * NO backfill: existing rows keep category_id NULL / service_ids '[]';
--     they are populated when a pro next edits their profile.
--   * NO change to the `specialty` text column or professionFr/Ar labels
--     (kept for display + fuzzy fallback).
--   * NO home/search UI change, NO catalog table in Supabase (the catalogs
--     stay Dart-side; the ids above reference them by convention).
--
-- DESIGN (mirrors Phase 3P + 3S + 3U):
--   * ADDITIVE + IDEMPOTENT: `add column if not exists`, `create index if not
--     exists`, `drop function if exists` + `create or replace` for the
--     signature change - a second run is always a no-op.
--   * Authorization FIRST: pro_update_profile keys off auth.uid() ONLY
--     (errcode 42501 before any row is probed - no caller-controlled user);
--     NULL parameters preserve the stored value (coalesce), so a caller can
--     update only the specialization fields.
--   * JSON payloads are validated with jsonb_typeof BEFORE they reach a
--     column (service_ids must be an array, mirroring work_images/zones).
--   * VOLATILE, SECURITY DEFINER, SET search_path = public, pg_temp (pg_temp
--     LAST; every reference schema-qualified). No dynamic SQL anywhere.
--   * NO UPDATE RLS policy is added: professionals rows are mutated ONLY
--     through SECURITY DEFINER RPCs (pro self-service + admin approval).
--   * REVOKE ALL (PUBLIC, anon, authenticated) first, then GRANT EXECUTE to
--     authenticated only.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.  (Re-running is safe - every step is guarded.)
--   2. Verify read-only (section 4 at the bottom, commented out).
--   3. No secret/password/key is required or stored anywhere here.
-- ============================================================================

-- -- 1. Specialization columns (idempotent) ------------------------------------
alter table public.professionals
  add column if not exists category_id text;

alter table public.professionals
  add column if not exists service_ids jsonb not null default '[]'::jsonb;

-- -- 2. Indexes (idempotent) ---------------------------------------------------
-- B-tree: equality lookups ("all pros of category 'auto'").
-- GIN: jsonb containment '@>' ("pros offering service 'auto:electricien'").
create index if not exists professionals_category_id_text_idx
  on public.professionals(category_id);

create index if not exists professionals_service_ids_gin_idx
  on public.professionals using gin(service_ids);

-- -- 3. pro_update_profile gains p_category_id + p_service_ids ------------------
-- The Phase 3U signature (text,text,text,numeric,jsonb,jsonb) is REPLACED by
-- the 8-param signature below. The old signature is dropped FIRST (create or
-- replace cannot change a parameter list); the drop is guarded by `if exists`
-- so a re-run is a no-op. Every Phase 3U validation and the coalesce
-- never-blanks semantics are preserved VERBATIM; the two new parameters obey
-- the same rules (NULL preserves, non-array service_ids rejected with 22023).
drop function if exists public.pro_update_profile(text,text,text,numeric,jsonb,jsonb);

create or replace function public.pro_update_profile(
  p_specialty text default null,
  p_bio text default null,
  p_pricing_type text default null,
  p_price_from numeric default null,
  p_work_images jsonb default null,
  p_zones jsonb default null,
  p_category_id text default null,
  p_service_ids jsonb default null
)
returns table (updated_id uuid)
language plpgsql volatile security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- 1) Authorization FIRST: no identity -> 42501 (before any row is probed).
  if v_uid is null then
    raise exception 'pro_update_profile: no authenticated identity'
      using errcode = '42501';
  end if;

  -- 2) Own-row precondition: the caller must have a professionals row.
  if not exists (select 1 from public.professionals where id = v_uid) then
    raise exception 'pro_update_profile: no professionals row for %', v_uid
      using errcode = '23503';
  end if;

  -- 3) Validate scalar + JSON payloads BEFORE they reach a column.
  if p_pricing_type is not null
     and p_pricing_type not in ('fixed', 'quote') then
    raise exception 'pro_update_profile: invalid pricing_type %', p_pricing_type
      using errcode = '22023';
  end if;

  if p_work_images is not null
     and jsonb_typeof(p_work_images) <> 'array' then
    raise exception 'pro_update_profile: work_images must be a JSON array'
      using errcode = '22023';
  end if;

  if p_zones is not null
     and jsonb_typeof(p_zones) <> 'array' then
    raise exception 'pro_update_profile: zones must be a JSON array'
      using errcode = '22023';
  end if;

  if p_service_ids is not null
     and jsonb_typeof(p_service_ids) <> 'array' then
    raise exception 'pro_update_profile: service_ids must be a JSON array'
      using errcode = '22023';
  end if;

  -- 4) Partial update: NULL parameters preserve the stored value.
  update public.professionals pr
  set specialty    = coalesce(p_specialty, pr.specialty),
      bio          = coalesce(p_bio, pr.bio),
      pricing_type = coalesce(p_pricing_type, pr.pricing_type),
      price_from   = coalesce(p_price_from, pr.price_from),
      work_images  = coalesce(p_work_images, pr.work_images),
      zones        = coalesce(p_zones, pr.zones),
      category_id  = coalesce(p_category_id, pr.category_id),
      service_ids  = coalesce(p_service_ids, pr.service_ids)
  where pr.id = v_uid;

  -- 5) Minimal result: the updated row's id only.
  return query select v_uid;
end;
$$;

comment on function public.pro_update_profile(text, text, text, numeric, jsonb, jsonb, text, jsonb) is
  'User-facing (auth.uid() ONLY, no user parameter): partial self-service '
  'update of the caller''s OWN public.professionals dossier - specialty, bio, '
  'pricing_type (fixed|quote, validated), price_from, work_images and zones '
  '(both must be JSON arrays), plus ID-based specialization: category_id '
  '(ServicesCatalog category id, e.g. ''auto'') and service_ids (JSON array '
  'of CatalogType ids, e.g. ["auto:electricien"]). NULL parameters preserve '
  'the stored value; status/is_verified/approved_at/tokens/paid_until are '
  'never touched here. Fails closed: 42501 without an identity, 23503 '
  'without a row, 22023 on invalid payloads. SECURITY DEFINER + VOLATILE, '
  'search_path pinned to public, pg_temp. Returns (updated_id).';

revoke all on function public.pro_update_profile(text, text, text, numeric, jsonb, jsonb, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.pro_update_profile(text, text, text, numeric, jsonb, jsonb, text, jsonb)
  to authenticated;

-- -- 4. Verification (read-only - run manually after the migration) ------------
-- select column_name, data_type, column_default
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name = 'professionals'
--   and column_name in ('category_id', 'service_ids')
-- order by column_name;
-- -- expect exactly 2 rows:
-- --   category_id | text              | (null)
-- --   service_ids | jsonb             | '[]'::jsonb
-- --
-- select indexname
-- from pg_indexes
-- where schemaname = 'public'
--   and tablename = 'professionals'
--   and (indexname like '%category%' or indexname like '%service%')
-- order by indexname;
-- -- expect exactly 2 rows:
-- --   professionals_category_id_text_idx
-- --   professionals_service_ids_gin_idx
-- --
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args
-- from pg_proc p
-- join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname = 'pro_update_profile';
-- -- expect exactly ONE row (the old 6-param signature is gone):
-- --   pro_update_profile(text,text,text,numeric,jsonb,jsonb,text,jsonb)
-- --
-- select routine_name, grantee
-- from information_schema.routine_privileges
-- where routine_schema = 'public'
--   and routine_name = 'pro_update_profile'
-- order by routine_name, grantee;   -- expect: authenticated only
-- --
-- -- Behavioural smoke test (as an AUTHENTICATED pro session):
-- --   select * from public.pro_update_profile(p_category_id => 'auto');
-- --   select * from public.pro_update_profile(
-- --     p_service_ids => '["auto:electricien","auto:diagnostic"]'::jsonb);
-- --   select * from public.pro_update_profile(
-- --     p_service_ids => '{"a":1}');   -- expect errcode 22023 (not an array)
-- ============================================================================
