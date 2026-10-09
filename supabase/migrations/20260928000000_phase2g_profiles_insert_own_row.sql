-- ============================================================================
-- PHASE 2G — PROFILES INSERT RLS POLICY ONLY (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
-- GOAL (this phase ONLY):
--   * Allow an authenticated user to create ONLY their own row in
--     public.profiles.
--
-- NON-GOALS (separate phases, untouched here):
--   SELECT / UPDATE / DELETE policies on profiles, table grants, columns,
--   constraints, triggers, functions, admin authorization, orders / messages /
--   storage, Flutter code.
--
-- DESIGN (why this shape):
--   * Exactly ONE policy, INSERT-only, for the authenticated role.
--   * WITH CHECK (auth.uid() = id): the ONLY authorization input is the
--     server-side auth.uid() matched against the row's primary key. E-mail,
--     phone, role and every other caller-supplied field are NEVER trusted.
--   * Idempotent guard (pg_policies check) so re-running is safe.
--   * No GRANT changes: the anon key still cannot INSERT (policy is FOR
--     authenticated only); existing grants are untouched.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.
--   2. Verify (read-only):
--        select policyname, cmd, roles, with_check
--        from pg_policies
--        where schemaname = 'public' and tablename = 'profiles';
--      Expected: exactly one row — profiles_insert_own_row / INSERT /
--      {authenticated} / (auth.uid() = id).
--   3. Do NOT run any INSERT/UPDATE/DELETE test writes from the editor;
--      runtime verification happens on the next real sign-in (Phase 2E retry).
-- ============================================================================

-- -- 1. Own-row INSERT policy (exactly one) -----------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profiles_insert_own_row'
  ) then
    create policy profiles_insert_own_row
      on public.profiles
      for insert
      to authenticated
      with check (auth.uid() = id);
  end if;
end $$;

-- -- 2. Explicit non-goals (documented, no statements) -------------------------
-- No SELECT policy. No UPDATE policy. No DELETE policy. No GRANT changes.
-- No column / constraint / trigger / function changes.
