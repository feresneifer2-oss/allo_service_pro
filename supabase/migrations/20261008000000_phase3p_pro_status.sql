-- ============================================================================
-- PHASE 3P — PROFESSIONAL STATUS: COLUMNS, INSERT POLICY, APPROVE/REJECT RPCs
-- (allo_service_pro)
-- Idempotent + additive — safe to run twice (every DDL statement is guarded).
-- ============================================================================
-- BACKGROUND:
--   * A LIVE migration already ran in Supabase SQL Editor (dashboard) but was
--     NOT recorded in supabase/migrations/ until this file. It added to
--     public.professionals:
--       - status           text not null default 'pending'
--                          CHECK (status in ('pending','approved','rejected'))
--       - rejection_reason text null
--       - approved_at      timestamptz null
--       - INSERT policy    professionals_insert_own_row
--   * This file PERSISTS that state as a real migration (idempotent re-apply:
--     running it against the already-migrated live DB changes nothing) and
--     extends the approval path so the server records the decision.
--
-- GOAL (this phase ONLY):
--   1. Re-apply (idempotently) the three columns + the status allowlist CHECK
--      + the own-row INSERT policy — compatible with the live state.
--   2. Backfill status from is_verified for pre-existing rows (lossless,
--      re-runnable).
--   3. Extend public.admin_provision_professional so an approval ALSO writes
--      status = 'approved' and approved_at = now() on BOTH branches: the
--      insert (new row) and the on-conflict update (existing row).
--   4. Two NEW admin-only RPCs (mirror the Phase 3N shape exactly):
--        - public.admin_reject_professional(uuid, text)
--        - public.admin_reset_professional_to_pending(uuid)
--
-- NON-GOALS (separate phases, untouched here):
--   * The professionals SELECT policy (professionals_select_own_row, Phase 3O)
--     is NOT dropped, altered, or re-created.
--   * No OTHER policy, table, trigger, constraint, or function is created,
--     dropped, or replaced — only the ones named in GOAL 1/3/4.
--   * No profiles / orders / messages / storage change, NO Flutter/Dart
--     change, NO Edge Function, NO secret.
--
-- DESIGN (mirrors Phase 3N + 3O + 3H):
--   * ADDITIVE + IDEMPOTENT: `add column if not exists`, `pg_policies` /
--     `pg_constraint` guards inside `do $$ ... $$`, `create or replace` for
--     the provisioned RPC — a second run is always a no-op.
--   * Authorization FIRST on every RPC: public.is_admin() (Phase 1:
--     SECURITY DEFINER, STABLE, keys off auth.uid() against public.admins) is
--     the SOLE admin source of truth — checked before ANY other work, so a
--     non-admin cannot even probe whether a profile exists (errcode 42501).
--   * VOLATILE (these functions write), SECURITY DEFINER (bypasses the
--     own-row-only RLS for this admin path only),
--     SET search_path = public, pg_temp (pinned: pg_temp LAST so temporary
--     objects cannot shadow public.*; every reference is schema-qualified).
--   * No dynamic SQL anywhere; plpgsql only; fully qualified names.
--   * status / is_verified are NEVER caller parameters: each RPC writes its
--     fixed outcome (approve / reject / reset). The caller only supplies the
--     human rejection reason as text.
--   * REVOKE ALL (PUBLIC, anon, authenticated) first, then GRANT EXECUTE to
--     authenticated only — nobody gets these by default.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.  (Re-running is safe — every step is guarded.)
--   2. Verify read-only (section 10 at the bottom).
--   3. No secret/password/key is required or stored anywhere here.
-- ============================================================================

-- -- 1. Status columns (idempotent) ---------------------------------------------
alter table public.professionals
  add column if not exists status text not null default 'pending',
  add column if not exists rejection_reason text,
  add column if not exists approved_at timestamptz;

-- -- 2. status allowlist CHECK (idempotent) --------------------------------------
-- Guard accepts BOTH this file's canonical name and the auto-generated name a
-- prior live run may have produced, so the live DB does not end up with two
-- identical checks. If neither exists (fresh DB), the canonical one is added.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname in ('professionals_status_allowlist', 'professionals_status_check')
      and conrelid = 'public.professionals'::regclass
  ) then
    alter table public.professionals add constraint professionals_status_allowlist
      check (status in ('pending', 'approved', 'rejected'));
  end if;
end $$;

-- -- 3. Backfill status from is_verified (idempotent, lossless) ------------------
-- Pre-Phase-3P rows all carry the column default 'pending'. Promote the ALREADY
-- verified rows to 'approved' (stamping approved_at once, never overwriting an
-- existing stamp). Rows already 'approved' or explicitly 'rejected' are NEVER
-- touched — no rejection can be lost, and a re-run matches zero rows.
update public.professionals pr
set status      = 'approved',
    approved_at = coalesce(pr.approved_at, now())
where pr.is_verified = true
  and pr.status = 'pending';

-- -- 4. Own-row INSERT grant + policy (idempotent, mirrors Phase 3O) -------------
-- Explicit grant: the baseline table may have been created outside the
-- migration pipeline, in which case grants are NOT inherited.
grant insert on table public.professionals to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'professionals'
      and policyname = 'professionals_insert_own_row'
  ) then
    create policy professionals_insert_own_row
      on public.professionals
      for insert
      to authenticated
      with check (auth.uid() = id);
  end if;
end $$;

-- -- 5. The provisioning RPC, now recording approval in status/approved_at -------
-- Same signature and return shape as Phase 3N (create-or-replace: idempotent).
-- The ONLY change: the approval decision is now ALSO written into
-- status/approved_at on BOTH branches of the upsert.
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

  -- 3) Create-or-verify AND approve: idempotent upsert.
  --    is_verified := true, status := 'approved' and approved_at := now() are
  --    written HERE, never caller-controlled — a brand-new row AND an existing
  --    row (possibly stale pending/rejected) both end approved. NULL incoming
  --    specialty/bio keeps the previously stored value.
  insert into public.professionals as pr
    (id, specialty, bio, is_verified, status, approved_at)
  values (p_user_id, p_specialty, p_bio, true, 'approved', now())
  on conflict (id) do update
    set specialty   = coalesce(excluded.specialty, pr.specialty),
        bio         = coalesce(excluded.bio,       pr.bio),
        is_verified = true,
        status      = 'approved',
        approved_at = now();

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
  'approved_at=now()). SECURITY DEFINER + VOLATILE, search_path pinned to '
  'public, pg_temp. is_verified always becomes true; no caller-controlled '
  'authorization field; NULL specialty/bio preserves the stored value. '
  'Returns (professional_id, professional_is_verified).';

-- -- 6. New RPC: admin-only rejection --------------------------------------------
create or replace function public.admin_reject_professional(
  p_user_id uuid,
  p_reason text
)
returns table (
  professional_id uuid
)
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
begin
  -- 1) Authorization FIRST: only an authenticated admin may proceed
  --    (same guard, same errcode as admin_provision_professional).
  if not public.is_admin() then
    raise exception
      'admin_reject_professional: caller is not an administrator'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 2) Identity checks (mirrors Phase 3N step 2).
  if p_user_id is null then
    raise exception
      'admin_reject_professional: p_user_id must not be null'
      using errcode = '23502';  -- not_null_violation
  end if;

  --    The target must already be a provisioning candidate — rejecting must
  --    never silently CREATE a row (unlike the provision upsert).
  if not exists (
    select 1
    from public.professionals pr
    where pr.id = p_user_id
  ) then
    raise exception
      'admin_reject_professional: no public.professionals row for %', p_user_id
      using errcode = '23503';  -- foreign_key_violation
  end if;

  -- 3) Reject: a FIXED outcome. status / is_verified are hard-coded here;
  --    p_reason is free text stored verbatim (column is nullable, so a caller
  --    passing null still gets a consistent rejected row).
  update public.professionals pr
  set status           = 'rejected',
      rejection_reason = p_reason,
      is_verified      = false
  where pr.id = p_user_id;

  -- 4) Minimal result: the updated row id only — no email, no reason echo,
  --    no roster data.
  return query
    select pr.id
    from public.professionals pr
    where pr.id = p_user_id;
end;
$$;

comment on function public.admin_reject_professional(uuid, text) is
  'Admin-only (public.is_admin()): sets status=rejected, rejection_reason and '
  'is_verified=false on the public.professionals row of p_user_id. SECURITY '
  'DEFINER + VOLATILE, search_path pinned to public, pg_temp. status and '
  'is_verified are never caller-controlled. Returns (professional_id).';

-- -- 7. New RPC: admin-only reset back to pending ---------------------------------
create or replace function public.admin_reset_professional_to_pending(
  p_user_id uuid
)
returns table (
  professional_id uuid
)
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
begin
  -- 1) Authorization FIRST: only an authenticated admin may proceed.
  if not public.is_admin() then
    raise exception
      'admin_reset_professional_to_pending: caller is not an administrator'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 2) Identity checks (mirrors Phase 3N step 2).
  if p_user_id is null then
    raise exception
      'admin_reset_professional_to_pending: p_user_id must not be null'
      using errcode = '23502';  -- not_null_violation
  end if;

  if not exists (
    select 1
    from public.professionals pr
    where pr.id = p_user_id
  ) then
    raise exception
      'admin_reset_professional_to_pending: no public.professionals row for %',
      p_user_id
      using errcode = '23503';  -- foreign_key_violation
  end if;

  -- 3) Reset: a FIXED outcome — full return to the pre-review state. The
  --    previous rejection text and approval stamp are deliberately CLEARED so
  --    a fresh review starts clean.
  update public.professionals pr
  set status           = 'pending',
      rejection_reason = null,
      approved_at      = null,
      is_verified      = false
  where pr.id = p_user_id;

  -- 4) Minimal result: the updated row id only.
  return query
    select pr.id
    from public.professionals pr
    where pr.id = p_user_id;
end;
$$;

comment on function public.admin_reset_professional_to_pending(uuid) is
  'Admin-only (public.is_admin()): resets the public.professionals row of '
  'p_user_id to status=pending with rejection_reason=null, approved_at=null '
  'and is_verified=false. SECURITY DEFINER + VOLATILE, search_path pinned to '
  'public, pg_temp. Returns (professional_id).';

-- -- 8. Least-privilege EXECUTE (the ONLY function grants in this file) ----------
-- REVOKE first (nothing gets these by default), then GRANT to authenticated.
revoke all on function public.admin_provision_professional(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_provision_professional(uuid, text, text)
  to authenticated;

revoke all on function public.admin_reject_professional(uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_reject_professional(uuid, text)
  to authenticated;

revoke all on function public.admin_reset_professional_to_pending(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_reset_professional_to_pending(uuid)
  to authenticated;

-- -- 9. Explicit non-goals (documented, no statements) ---------------------------
-- The Phase 3O SELECT policy professionals_select_own_row stays AS-IS (no drop,
-- no alter, no recreate). No OTHER policy/table/trigger/constraint/function is
-- touched beyond sections 1-7. No profiles / orders / messages / storage
-- change. No Flutter change. No Edge Function. No secret.

-- -- 10. Read-only verification (AFTER a human applies this file) ----------------
--   -- the three columns exist with the expected defaults/nullability:
--   select column_name, data_type, is_nullable, column_default
--   from information_schema.columns
--   where table_schema = 'public' and table_name = 'professionals'
--     and column_name in ('status', 'rejection_reason', 'approved_at')
--   order by column_name;
--
--   -- exactly TWO professionals policies: this file's INSERT + Phase 3O's SELECT:
--   select policyname, cmd from pg_policies
--   where schemaname = 'public' and tablename = 'professionals'
--   order by policyname;   -- expect: professionals_insert_own_row / INSERT,
--                           --         professionals_select_own_row / SELECT
--
--   -- all three functions: volatile + security definer + pinned search_path:
--   select p.oid::regprocedure                        as fn,
--          p.provolatile                               as vol,    -- expect 'f'
--          p.prosecdef                                 as secdef, -- expect true
--          pg_get_function_identity_arguments(p.oid)   as args,
--          coalesce(p.proconfig, '{}')                 as config
--   from pg_proc p
--   where p.oid in (
--     'public.admin_provision_professional(uuid,text,text)'::regprocedure,
--     'public.admin_reject_professional(uuid,text)'::regprocedure,
--     'public.admin_reset_professional_to_pending(uuid)'::regprocedure
--   );
--
--   -- backfill left no verified row behind in 'pending':
--   select count(*) as stale_verified_pending
--   from public.professionals
--   where is_verified = true and status = 'pending';   -- expect 0
