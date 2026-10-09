-- ============================================================================
-- PHASE 3O — PROFESSIONALS SELECT RLS POLICY ONLY (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
-- ROOT CAUSE THIS PHASE FIXES:
--   * public.professionals carries RLS with ZERO policies (see Phase 3N), so
--     an authenticated professional can NEVER read their own row and the app
--     has no server-side answer for `is_verified` during login / session
--     routing — the approval state could only come from local (potentially
--     stale) storage, which the pending-approval gate must not trust.
--
-- GOAL (this phase ONLY):
--   * Allow an authenticated user to SELECT ONLY their own row in
--     public.professionals (id = their auth.uid()), so the client can read
--     `is_verified` and treat the server as the approval authority.
--
-- NON-GOALS (separate phases, untouched here):
--   Any INSERT/UPDATE/DELETE policy (none exist and none are added), the
--   admin-only RPC admin_provision_professional (is_verified stays written
--   ONLY server-side by that path), profiles / orders / messages / storage /
--   pro_availability policies, columns, constraints, triggers, functions,
--   Flutter code.
--
-- DESIGN (mirrors Phase 2M):
--   * Exactly ONE policy, SELECT-only, for the authenticated role.
--   * USING (auth.uid() = id): a row is readable ONLY when its primary key is
--     the caller's own auth.uid — no other professional's row ever enters a
--     SELECT. No caller-supplied field is trusted; auth.uid() is server-side.
--   * Idempotent guard (pg_policies check, same shape as Phase 2G / 2L / 2M)
--     so re-running the file is safe and never duplicates the policy.
--   * One explicit, idempotent SELECT grant keeps the read working even when
--     the baseline table was created outside the migration pipeline (grants
--     are NOT inherited in that case).
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.
--   2. Verify (read-only):
--        select policyname, cmd, roles, qual, with_check
--        from pg_policies
--        where schemaname = 'public' and tablename = 'professionals'
--        order by policyname;
--      Expected — one row:
--        professionals_select_own_row / SELECT / {authenticated} /
--        (auth.uid() = id) / null
--   3. As an authenticated professional (after sign-in), confirm a plain
--      `select id, is_verified from public.professionals where id = auth.uid()`
--      returns exactly 0 (never-verified) or 1 row — never another pro's row.
-- ============================================================================

-- -- 1. Own-row SELECT grant (idempotent) --------------------------------------
grant select on table public.professionals to authenticated;

-- -- 2. Own-row SELECT policy (exactly one) ------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'professionals'
      and policyname = 'professionals_select_own_row'
  ) then
    create policy professionals_select_own_row
      on public.professionals
      for select
      to authenticated
      using (auth.uid() = id);
  end if;
end $$;
