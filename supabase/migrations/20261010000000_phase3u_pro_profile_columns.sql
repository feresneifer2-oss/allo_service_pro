-- ============================================================================
-- PHASE 3U - SERVER-AUTHORITATIVE PRO PROFILE COLUMNS + SELF-SERVICE RPC
-- (allo_service_pro)
-- Idempotent + additive - safe to run twice (every DDL statement is guarded).
-- ============================================================================
-- BACKGROUND:
--   * Phase 3S moved tokens/paid_until server-side. The follow-up AUDIT found
--     the rest of the pro dossier still local-only or unmapped:
--       - proof_path / selfie_path : files ARE uploaded to Storage, but the
--         pro -> path mapping lives ONLY in local SharedPreferences (lost on
--         clear-data / never visible to another device or to the admin).
--       - work_images (gallery)    : remote handles mirrored locally only.
--       - badges                   : approval evidence inside a local JSON
--         blob (`admin_pending_pros_json`).
--       - zones / pricing_type / price_from : in-memory only (zones are not
--         even persisted locally).
--   * public.professionals already carries: id, is_verified, specialty, bio
--     (baseline + 3N), status, rejection_reason, approved_at (3P),
--     tokens, paid_until (3S).
--
-- GOAL (this phase ONLY):
--   1. Add 7 columns to public.professionals (idempotent):
--      proof_path text, selfie_path text, work_images jsonb, badges jsonb,
--      zones jsonb, pricing_type text (CHECK fixed|quote), price_from numeric.
--   2. NEW user-facing RPC public.pro_update_profile(...) - the pro edits
--      their OWN specialty/bio/pricing/work/zones server-side.
--   3. professional_resubmit_own_proof gains an OPTIONAL p_proof_path
--      parameter (new signature (text); the old () signature is dropped).
--   4. admin_provision_professional additionally clears rejection_reason on
--      approval (a resubmitted pro must not keep the stale reason).
--
-- NON-GOALS (separate phases, untouched here):
--   * NO Dart/Flutter change in this file - the app keeps working until the
--     follow-up batch wires the UI to pro_update_profile.
--   * NO backfill of existing rows (all new columns are nullable/defaulted;
--     old rows read as empty arrays / the column defaults).
--   * NO storage policies, NO storage migration, NO Edge Function, NO change
--     to profiles / orders / messages / token_transactions / pro_availability,
--     NO expiry scheduler.
--   * admin_provision_professional keeps its signature and everything else
--     (tokens grant, status machine, ledger row) EXACTLY as in Phase 3S -
--     only `rejection_reason = null` is added on both upsert branches.
--
-- DESIGN (mirrors Phase 3P + 3Q + 3S):
--   * ADDITIVE + IDEMPOTENT: `add column if not exists`, a pg_constraint
--     guard inside `do $$ ... $$`, `drop function if exists` + `create or
--     replace` for the signature change - a second run is always a no-op.
--   * Authorization FIRST: pro_update_profile keys off auth.uid() ONLY
--     (errcode 42501 before any row is probed - no caller-controlled user);
--     professional_resubmit_own_proof keeps its Phase 3Q state machine
--     verbatim; the admin path stays on public.is_admin().
--   * VOLATILE, SECURITY DEFINER, SET search_path = public, pg_temp (pg_temp
--     LAST; every reference schema-qualified). No dynamic SQL anywhere.
--   * JSON payloads are validated with jsonb_typeof BEFORE they reach a
--     column; the pricing_type allowlist CHECK mirrors the RPC validation.
--   * NO UPDATE RLS policy is added: professionals rows are mutated ONLY
--     through SECURITY DEFINER RPCs (pro self-service + admin approval).
--   * REVOKE ALL (PUBLIC, anon, authenticated) first, then GRANT EXECUTE to
--     authenticated only.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.  (Re-running is safe - every step is guarded.)
--   2. Verify read-only (section 6 at the bottom, commented out).
--   3. No secret/password/key is required or stored anywhere here.
-- ============================================================================

-- -- 1. Server-authoritative pro dossier columns (idempotent) ---------------------
alter table public.professionals
  add column if not exists proof_path text,
  add column if not exists selfie_path text,
  add column if not exists work_images jsonb not null default '[]'::jsonb,
  add column if not exists badges jsonb not null default '[]'::jsonb,
  add column if not exists zones jsonb not null default '[]'::jsonb,
  add column if not exists pricing_type text default 'fixed',
  add column if not exists price_from numeric default 0;

-- -- 2. pricing_type allowlist CHECK (idempotent via pg_constraint guard) ---------
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'professionals_pricing_type_allowlist'
      and conrelid = 'public.professionals'::regclass
  ) then
    alter table public.professionals
      add constraint professionals_pricing_type_allowlist
      check (pricing_type is null or pricing_type in ('fixed', 'quote'));
  end if;
end $$;

-- -- 3. NEW user-facing RPC: pro self-service profile edit ------------------------
-- Keys off auth.uid() ONLY (no p_user_id parameter): the row acted upon can
-- only ever be the caller's own, so a cross-account edit is not expressible.
-- NULL parameters PRESERVE the stored value (coalesce), so a partial update
-- never blanks a field. pricing_type is validated here AND by the column
-- CHECK; work_images / zones must be JSON arrays (jsonb_typeof) - the same
-- contract the Flutter side sends ('[]' when a list is empty).
-- Fail-closed: missing identity 42501 (before any probe), missing row 23503,
-- bad pricing_type / non-array payload 22023.
create or replace function public.pro_update_profile(
  p_specialty text default null,
  p_bio text default null,
  p_pricing_type text default null,
  p_price_from numeric default null,
  p_work_images jsonb default null,
  p_zones jsonb default null
)
returns table (updated_id uuid)
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  -- 1) Authorization FIRST (the Phase 3Q slot): only an authenticated
  --    identity may act, and only ever on its OWN row.
  if v_uid is null then
    raise exception 'pro_update_profile: no authenticated identity'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 2) The caller must already own a professionals row (mirrors Phase 3Q -
  --    a missing row is a server-side data error, not client input).
  if not exists (
    select 1 from public.professionals where id = v_uid
  ) then
    raise exception 'pro_update_profile: no professionals row for %', v_uid
      using errcode = '23503';  -- foreign_key_violation
  end if;

  -- 3) Validate pricing_type when provided (allowlist mirrors the CHECK).
  if p_pricing_type is not null
     and p_pricing_type not in ('fixed', 'quote') then
    raise exception 'pro_update_profile: invalid pricing_type %', p_pricing_type
      using errcode = '22023';  -- check_violation
  end if;

  -- 4) Validate the JSON payloads are ARRAYS before they reach a column.
  if p_work_images is not null
     and jsonb_typeof(p_work_images) <> 'array' then
    raise exception 'pro_update_profile: work_images must be a JSON array'
      using errcode = '22023';  -- check_violation
  end if;

  if p_zones is not null
     and jsonb_typeof(p_zones) <> 'array' then
    raise exception 'pro_update_profile: zones must be a JSON array'
      using errcode = '22023';  -- check_violation
  end if;

  -- 5) Partial update: NULL means "keep the stored value", never blank.
  --    status / is_verified / approved_at / tokens / paid_until are
  --    DELIBERATELY absent: they are owned by the approval path, never by
  --    a self-service edit.
  update public.professionals pr
  set specialty    = coalesce(p_specialty, pr.specialty),
      bio          = coalesce(p_bio, pr.bio),
      pricing_type = coalesce(p_pricing_type, pr.pricing_type),
      price_from   = coalesce(p_price_from, pr.price_from),
      work_images  = coalesce(p_work_images, pr.work_images),
      zones        = coalesce(p_zones, pr.zones)
  where pr.id = v_uid;

  -- 6) Minimal result: the updated row's id only.
  return query select v_uid;
end;
$$;

comment on function public.pro_update_profile(text, text, text, numeric, jsonb, jsonb) is
  'User-facing (auth.uid() ONLY, no user parameter): partial self-service '
  'update of the caller''s OWN public.professionals dossier - specialty, bio, '
  'pricing_type (fixed|quote, validated), price_from, work_images and zones '
  '(both must be JSON arrays). NULL parameters preserve the stored value; '
  'status/is_verified/approved_at/tokens/paid_until are never touched here. '
  'Fails closed: 42501 without an identity, 23503 without a row, 22023 on '
  'invalid payloads. SECURITY DEFINER + VOLATILE, search_path pinned to '
  'public, pg_temp. Returns (updated_id).';

revoke all on function public.pro_update_profile(text, text, text, numeric, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.pro_update_profile(text, text, text, numeric, jsonb, jsonb)
  to authenticated;

-- -- 4. professional_resubmit_own_proof: OPTIONAL proof path on re-submission -----
-- The Phase 3Q signature () is REPLACED by (text) so a rejected pro can
-- attach a FRESH verification document when re-submitting. The old signature
-- is dropped FIRST (create or replace cannot change a signature); the drop is
-- guarded by `if exists` so a re-run is a no-op. The Phase 3Q state machine
-- is preserved VERBATIM: rejected -> pending (re-review), pending -> pending
-- (idempotent no-op), approved / NULL / unknown status -> 42501.
-- p_proof_path semantics: NULL or blank -> the stored proof_path is left
-- untouched; non-empty (trimmed) -> it replaces proof_path in the same UPDATE
-- as the reset.
drop function if exists public.professional_resubmit_own_proof();

create or replace function public.professional_resubmit_own_proof(
  p_proof_path text default null
)
returns table (
  professional_id uuid
)
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_status text;
begin
  -- 1) Authorization FIRST (the Phase 3P is_admin() slot): only an
  --    authenticated identity may act, and only ever on its OWN row.
  if v_uid is null then
    raise exception
      'professional_resubmit_own_proof: no authenticated identity'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 2) Row exists (mirrors Phase 3P step 2 — a missing row is a server-side
  --    data error, not client input).
  if not exists (
    select 1
    from public.professionals pr
    where pr.id = v_uid
  ) then
    raise exception
      'professional_resubmit_own_proof: no public.professionals row for %',
      v_uid
      using errcode = '23503';  -- foreign_key_violation
  end if;

  -- 3) State machine: read the CURRENT status, then gate the transition.
  select pr.status into v_status
  from public.professionals pr
  where pr.id = v_uid;

  -- An APPROVED professional can never fall back into review — this
  -- self-service path refuses the downgrade (same errcode as the admin gate).
  if v_status = 'approved' then
    raise exception
      'professional_resubmit_own_proof: an approved professional cannot be reset to pending'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- Fail-closed: ONLY the two allowed states proceed — 'rejected' (the real
  -- re-review) and 'pending' (idempotent no-op). NULL / any unexpected value
  -- is refused rather than silently rewritten.
  if v_status is null or v_status not in ('rejected', 'pending') then
    raise exception
      'professional_resubmit_own_proof: status % cannot be reset to pending',
      coalesce(v_status, '<null>')
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 4) Reset: a FIXED outcome — full return to the pre-review state. The
  --    previous rejection reason and approval stamp are deliberately CLEARED
  --    so a fresh review starts clean (parity with the admin reset). When a
  --    fresh proof path travels with the re-submission it replaces the old
  --    one; an absent/blank path keeps the stored value untouched.
  update public.professionals pr
  set status           = 'pending',
      rejection_reason = null,
      approved_at      = null,
      is_verified      = false,
      proof_path       = case
                           when p_proof_path is not null
                                and btrim(p_proof_path) <> ''
                             then btrim(p_proof_path)
                           else pr.proof_path
                         end
  where pr.id = v_uid;

  -- 5) Minimal result: the updated row's id only.
  return query
    select pr.id
    from public.professionals pr
    where pr.id = v_uid;
end;
$$;

comment on function public.professional_resubmit_own_proof(text) is
  'User-facing (auth.uid() ONLY, no user parameter): resets the caller''s own '
  'public.professionals row to status=pending with rejection_reason=null, '
  'approved_at=null and is_verified=false, and — when p_proof_path is '
  'non-empty — replaces proof_path with the fresh verification document '
  '(NULL/blank keeps the stored path). Allowed transitions: rejected -> '
  'pending (re-review) and pending -> pending (idempotent no-op); approved -> '
  'anything is refused (42501), as is any NULL/unknown status. SECURITY '
  'DEFINER + VOLATILE, search_path pinned to public, pg_temp. Returns '
  '(professional_id).';

revoke all on function public.professional_resubmit_own_proof(text)
  from public, anon, authenticated;
grant execute on function public.professional_resubmit_own_proof(text)
  to authenticated;

-- -- 5. admin_provision_professional: approval ALSO clears the stale reason -------
-- Phase 3U delta over the Phase 3S definition (create or replace: the EXECUTE
-- grants from Phase 3N/3P/3S carry over untouched): `rejection_reason = null`
-- on BOTH upsert branches — an explicit NULL in the INSERT column list and in
-- the DO UPDATE set-list — so a resubmitted pro never keeps the previous
-- rejection reason after approval. Everything else (signature, is_admin()
-- guard, profiles existence check, status/approved_at/is_verified writes,
-- the one-time 150-token signup grant and its unique 'signup_grant' ledger
-- row) is UNCHANGED from Phase 3S.
create or replace function public.admin_provision_professional(
  p_user_id uuid,
  p_specialty text default null,
  p_bio text default null
)
returns table (
  professional_id uuid,
  professional_is_verified boolean
)
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_preexisting boolean := false;
  v_grant_id    uuid;
begin
  -- 1) Authorization FIRST: only an authenticated admin may proceed.
  --    is_admin() keys off auth.uid() against public.admins (readable here
  --    because we are SECURITY DEFINER); a signed-out caller has no
  --    auth.uid(), gets false, and is refused before touching anything.
  if not public.is_admin() then
    raise exception
      'admin_provision_professional: caller is not an administrator'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 2) The target must be a real profile (mirrors the FK that
  --    public.professionals.id -> public.profiles(id) would raise anyway).
  if p_user_id is null then
    raise exception
      'admin_provision_professional: p_user_id must not be null'
      using errcode = '23502';  -- not_null_violation
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
  ) then
    raise exception
      'admin_provision_professional: no public.profiles row for %', p_user_id
      using errcode = '23503';  -- foreign_key_violation
  end if;

  -- 2b) Snapshot whether the professionals row already exists (Phase 3S):
  --     decides which branch credits the one-time signup bonus below.
  select exists (
    select 1 from public.professionals pr where pr.id = p_user_id
  ) into v_preexisting;

  -- 3) Create-or-verify AND approve: idempotent upsert.
  --    is_verified := true, status := 'approved', approved_at := now() and
  --    rejection_reason := null are written HERE, never caller-controlled —
  --    a brand-new row AND an existing row (possibly stale pending/rejected)
  --    both end approved with a clean slate. NULL incoming specialty/bio
  --    keeps the previously stored value. tokens = 150 applies to the INSERT
  --    branch only (the conflict branch never touches it).
  insert into public.professionals as pr
    (id, specialty, bio, is_verified, status, approved_at, rejection_reason, tokens)
  values (p_user_id, p_specialty, p_bio, true, 'approved', now(), null, 150)
  on conflict (id) do update
    set specialty        = coalesce(excluded.specialty, pr.specialty),
        bio              = coalesce(excluded.bio,       pr.bio),
        is_verified      = true,
        status           = 'approved',
        approved_at      = now(),
        rejection_reason = null;

  -- 3b) One-time signup grant ledger row. ON CONFLICT DO NOTHING +
  --     token_transactions_trial_once => replayed approvals are no-ops and
  --     a second grant is impossible.
  insert into public.token_transactions (pro_id, delta, kind)
  values (p_user_id, 150, 'signup_grant')
  on conflict do nothing
  returning id into v_grant_id;

  --     Only credit when the ledger row is NEW and the row pre-dates
  --     Phase 3S: a fresh INSERT already carries tokens = 150 (crediting
  --     again would double it), a replay finds the ledger row and skips.
  if v_grant_id is not null and v_preexisting then
    update public.professionals pr
    set tokens = coalesce(pr.tokens, 0) + 150
    where pr.id = p_user_id;
  end if;

  -- 4) Minimal non-sensitive result: UUID + verified flag only.
  return query
    select pr.id, pr.is_verified
    from public.professionals pr
    where pr.id = p_user_id;
end;
$$;

comment on function public.admin_provision_professional(uuid, text, text) is
  'Admin-only (public.is_admin()): creates/verifies a public.professionals '
  'row for p_user_id AND records the approval (status=approved, '
  'approved_at=now(), rejection_reason=null — the stale reason is cleared on '
  're-approval) AND grants the one-time 150-token signup bonus (INSERT sets '
  'tokens=150; the kind=signup_grant ledger row is unique per pro, so replays '
  'never double-grant and never reset the balance). SECURITY DEFINER + '
  'VOLATILE, search_path pinned to public, pg_temp. is_verified always '
  'becomes true; no caller-controlled authorization field; NULL '
  'specialty/bio preserves the stored value. '
  'Returns (professional_id, professional_is_verified).';

-- -- 6. RLS: NO change ---------------------------------------------------------------
-- professionals_select_own_row (Phase 3O) already SELECTs ALL columns,
-- including the seven added here. professionals_insert_own_row (Phase 3P)
-- covers the own-row INSERT. There is deliberately NO UPDATE policy on
-- public.professionals: rows are mutated ONLY through SECURITY DEFINER RPCs
-- (pro_update_profile / professional_resubmit_own_proof for the pro,
-- admin_provision_professional for the admin).

-- -- 7. READ-ONLY VERIFICATION (commented out — run by hand in SQL Editor) ----------
-- -- 7a. The 7 new columns exist:
-- select column_name
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name   = 'professionals'
--   and column_name in ('proof_path', 'selfie_path', 'work_images',
--                       'badges', 'zones', 'pricing_type', 'price_from')
-- order by column_name;            -- expect 7 rows
-- --
-- -- 7b. The pricing_type CHECK exists:
-- select conname
-- from pg_constraint
-- where conname = 'professionals_pricing_type_allowlist';   -- expect 1 row
-- --
-- -- 7c. The two function signatures exist (and the old () is gone):
-- select p.proname,
--        pg_get_function_identity_arguments(p.oid) as args
-- from pg_proc p
-- join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname in ('pro_update_profile', 'professional_resubmit_own_proof')
-- order by 1, 2;
-- -- expect exactly two rows:
-- --   professional_resubmit_own_proof(text)
-- --   pro_update_profile(text,text,text,numeric,jsonb,jsonb)
-- --
-- -- 7d. EXECUTE granted to authenticated ONLY for the three user/admin RPCs:
-- select routine_name, grantee
-- from information_schema.routine_privileges
-- where routine_schema = 'public'
--   and routine_name in ('pro_update_profile',
--                        'professional_resubmit_own_proof',
--                        'admin_provision_professional')
-- order by routine_name, grantee;  -- each: authenticated only
-- --
-- -- 7e. Behavioural smoke test (as an AUTHENTICATED pro session):
-- --   select * from public.pro_update_profile(p_specialty => 'Plomberie');
-- --   select * from public.professional_resubmit_own_proof('documents/<uid>/proof.png');
-- --   select * from public.professional_resubmit_own_proof();  -- keeps path
