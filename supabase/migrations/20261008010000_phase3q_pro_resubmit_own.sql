-- ============================================================================
-- PHASE 3Q — PROFESSIONAL SELF-RESUBMISSION: USER-FACING RPC
-- (allo_service_pro)
-- Idempotent + additive — safe to run twice (create or replace).
-- ============================================================================
-- BACKGROUND:
--   * Phase 3P added the ADMIN-only reset RPC
--     public.admin_reset_professional_to_pending(uuid), gated on is_admin().
--     The RE-submission flow, however, is triggered by the PROFESSIONAL
--     THEMSELVES (verification gate → AdminStore.resubmitProof) — an admin
--     RPC cannot serve it, and public.professionals has NO UPDATE RLS policy
--     (only Phase 3O's SELECT + Phase 3P's INSERT own-row policies), so until
--     now there was NO server-side path for a rejected pro to return their own
--     row to 'pending' at all (local-only re-submissions desynced from the
--     authoritative status on the next read).
--
-- GOAL (this phase ONLY):
--   1. One NEW user-facing RPC:
--        public.professional_resubmit_own_proof()
--      A self-service mirror of the admin reset: the CALLER'S OWN row only
--      (auth.uid(), never a parameter), 'rejected' → 'pending' (plus the
--      idempotent 'pending' → 'pending'), with the stale rejection reason,
--      approval stamp and verified flag cleared for a clean re-review.
--
-- NON-GOALS (separate phases, untouched here):
--   * No existing migration, function, policy, table, trigger, constraint,
--     profile, order, message or storage object is created, dropped or
--     replaced — ONLY this new function + its grants are added here.
--   * No Flutter/Dart change in this file (the Dart caller ships in the app
--     layer), NO Edge Function, NO secret.
--
-- DESIGN (mirrors Phase 3P's admin_reset_professional_to_pending):
--   * ADDITIVE + IDEMPOTENT: `create or replace` — a second run is a no-op.
--   * Authorization FIRST: `auth.uid()` IS the identity (this is NOT an admin
--     path): a missing authenticated identity is refused with errcode 42501
--     BEFORE any row is probed — the exact slot where Phase 3P checks
--     is_admin().
--   * No p_user_id parameter exists: the row acted upon can ONLY be the
--     caller's own — the value is never caller-controlled, so a cross-account
--     reset is not expressible even in principle.
--   * STATE MACHINE (fail-closed): only 'rejected' → 'pending' (the re-review
--     contract) and 'pending' → 'pending' (idempotent no-op) are allowed.
--     'approved' is refused with 42501 (a professional can never un-approve
--     themselves), and any NULL/unknown status is refused too rather than
--     silently rewritten. status / is_verified are NEVER parameters: the
--     function writes its fixed outcome.
--   * VOLATILE (writes), SECURITY DEFINER (bypasses the zero-UPDATE-policy
--     own-row RLS for this self-service path only),
--     SET search_path = public, pg_temp (pinned: pg_temp LAST so temporary
--     objects cannot shadow public.*; every reference is schema-qualified).
--   * No dynamic SQL; plpgsql only; fully qualified names.
--   * REVOKE ALL (PUBLIC, anon, authenticated) first, then GRANT EXECUTE to
--     authenticated only — nobody gets this by default.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.  (Re-running is safe — every step is idempotent.)
--   2. Verify read-only (section 3 at the bottom).
--   3. No secret/password/key is required or stored anywhere here.
-- ============================================================================

-- -- 1. Self-service resubmission RPC -------------------------------------------
create or replace function public.professional_resubmit_own_proof()
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
  --    so a fresh review starts clean (parity with the admin reset).
  update public.professionals pr
  set status           = 'pending',
      rejection_reason = null,
      approved_at      = null,
      is_verified      = false
  where pr.id = v_uid;

  -- 5) Minimal result: the updated row's id only.
  return query
    select pr.id
    from public.professionals pr
    where pr.id = v_uid;
end;
$$;

comment on function public.professional_resubmit_own_proof() is
  'User-facing (auth.uid() ONLY, no parameters): resets the caller''s own '
  'public.professionals row to status=pending with rejection_reason=null, '
  'approved_at=null and is_verified=false. Allowed transitions: rejected -> '
  'pending (re-review) and pending -> pending (idempotent no-op); approved -> '
  'anything is refused (42501), as is any NULL/unknown status. SECURITY '
  'DEFINER + VOLATILE, search_path pinned to public, pg_temp. Returns '
  '(professional_id).';

-- -- 2. Least-privilege EXECUTE (the ONLY function grant in this file) ------------
revoke all on function public.professional_resubmit_own_proof()
  from public, anon, authenticated;
grant execute on function public.professional_resubmit_own_proof()
  to authenticated;

-- -- 3. Read-only verification (AFTER a human applies this file) -----------------
--   -- the function: volatile + security definer + pinned search_path + NO args:
--   select p.oid::regprocedure                        as fn,
--          p.provolatile                               as vol,    -- expect 'f'
--          p.prosecdef                                 as secdef, -- expect true
--          pg_get_function_identity_arguments(p.oid)   as args,   -- expect ''
--          coalesce(p.proconfig, '{}')                 as config
--   from pg_proc p
--   where p.oid = 'public.professional_resubmit_own_proof()'::regprocedure;
--
--   -- execute is granted to authenticated ONLY (no PUBLIC/anon leftover):
--   select grantee, privilege_type
--   from information_schema.routine_privileges
--   where routine_schema = 'public'
--     and routine_name = 'professional_resubmit_own_proof'
--   order by grantee;   -- expect: authenticated / EXECUTE
--
--   -- professionals policies UNCHANGED (Phase 3P end-state — exactly TWO):
--   select policyname, cmd from pg_policies
--   where schemaname = 'public' and tablename = 'professionals'
--   order by policyname;   -- expect: professionals_insert_own_row / INSERT,
--                           --         professionals_select_own_row / SELECT
--
--   -- behavioural smoke test (as an AUTHENTICATED pro session): a 'rejected'
--   -- row flips to 'pending' with rejection_reason/approved_at cleared; a
--   -- second run is an idempotent no-op; an 'approved' row raises 42501:
--   --   select * from public.professional_resubmit_own_proof();


