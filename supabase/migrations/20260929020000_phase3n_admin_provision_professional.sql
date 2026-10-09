-- ============================================================================
-- PHASE 3N — ADMIN-ONLY PROFESSIONAL PROVISIONING RPC (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
-- GOAL (this phase ONLY):
--   * Exactly ONE SECURITY DEFINER RPC — public.admin_provision_professional —
--     that lets an authenticated ADMIN create/verify a row in
--     public.professionals, with the admin check enforced SERVER-SIDE.
--
-- NON-GOALS (separate phases, untouched here):
--   * public.professionals RLS stays ON with ZERO policies (no policy added).
--   * NO table INSERT/UPDATE grants for authenticated/anon — the ONLY grants
--     in this file are EXECUTE on the function itself.
--   * NO profiles role-constraint/trigger changes, NO orders changes,
--     NO Flutter changes, NO Edge Functions, NO other functions/triggers.
--
-- LIVE BASELINE (trusted, verified out-of-band — kept AS-IS):
--   public.professionals(id uuid PK -> public.profiles(id),
--                         is_verified boolean, specialty text, bio text,
--                         RLS ON, 0 policies).
--   Assumption (prompt-guaranteed): any OTHER professionals columns are
--   nullable or defaulted, so this 4-column upsert needs no backfill values.
--
-- DESIGN (why this shape):
--   * Authorization FIRST: public.is_admin() (Phase 1: SECURITY DEFINER,
--     STABLE, no args, reads public.admins via auth.uid()) is the SOLE admin
--     source of truth — checked before ANY other work, so a non-admin cannot
--     even probe whether a profile exists.
--   * VOLATILE (this function writes — STABLE would be wrong), SECURITY
--     DEFINER (bypasses the 0-policy table for this admin path only),
--     SET search_path = public, pg_temp (pinned: pg_temp LAST so temporary
--     objects cannot shadow public.*; every reference is schema-qualified).
--   * No dynamic SQL anywhere; plpgsql only, fully qualified names.
--   * is_verified is NEVER a caller parameter: the admin-only path always
--     yields true. No pro_code / role / any client-controlled authorization
--     field is accepted (nothing to spoof, nothing to widen).
--   * Idempotent upsert on conflict (id): a repeated call re-verifies
--     (is_verified := true) while an incoming NULL specialty/bio PRESERVES
--     the stored value instead of blanking it.
--   * Minimal result: (professional_id, professional_is_verified) only —
--     no email, no phone, no tokens, no roster data.
--   * REVOKE ALL (PUBLIC, anon, authenticated) first, then GRANT EXECUTE to
--     authenticated only — nobody gets it by default.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.  (NOT executed by Phase 3N — preparation only.)
--   2. Verify read-only (section 4 at the bottom).
--   3. No secret/password/key is required or stored anywhere here.
-- ============================================================================

-- -- 1. The RPC: admin-only professional provisioning -------------------------
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

  -- 3) Create-or-verify: idempotent upsert.
  --    is_verified := true UNCONDITIONALLY (not caller-controlled);
  --    NULL incoming specialty/bio keeps the previously stored value.
  insert into public.professionals as pr (id, specialty, bio, is_verified)
  values (p_user_id, p_specialty, p_bio, true)
  on conflict (id) do update
    set specialty   = coalesce(excluded.specialty, pr.specialty),
        bio         = coalesce(excluded.bio,       pr.bio),
        is_verified = true;

  -- 4) Minimal non-sensitive result: UUID + verified flag only.
  return query
    select pr.id, pr.is_verified
    from public.professionals pr
    where pr.id = p_user_id;
end;
$$;

comment on function public.admin_provision_professional(uuid, text, text) is
  'Admin-only (public.is_admin()): creates/verifies a public.professionals '
  'row for p_user_id. SECURITY DEFINER + VOLATILE, search_path pinned to '
  'public, pg_temp. is_verified always becomes true; no caller-controlled '
  'authorization field; NULL specialty/bio preserves the stored value. '
  'Returns (professional_id, professional_is_verified).';

-- -- 2. Least-privilege EXECUTE (the ONLY grants in this file) -----------------
revoke all on function public.admin_provision_professional(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_provision_professional(uuid, text, text)
  to authenticated;

-- -- 3. Explicit non-goals (documented, no statements) -------------------------
-- No RLS policy (public.professionals keeps 0). No table grant/revoke of any
-- kind. No trigger. No profiles constraint/trigger change. No orders change.
-- No Flutter change. No Edge Function. No secret.

-- -- 4. Read-only verification (AFTER a human applies this file) ---------------
--   -- exactly one function, volatile + security definer + pinned search_path:
--   select p.oid::regprocedure                        as fn,
--          p.provolatile                               as vol,    -- expect 'f'
--          p.prosecdef                                 as secdef, -- expect true
--          pg_get_function_identity_arguments(p.oid)   as args,   -- uuid,text,text
--          coalesce(p.proconfig, '{}')                 as config
--   from pg_proc p
--   where p.oid = 'public.admin_provision_professional(uuid,text,text)'::regprocedure;
--
--   -- professionals still has ZERO policies and no new table grants:
--   select polname, polcmd from pg_policies
--   where schemaname = 'public' and tablename = 'professionals';  -- expect 0

