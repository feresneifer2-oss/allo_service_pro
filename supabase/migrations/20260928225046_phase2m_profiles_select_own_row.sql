-- ============================================================================
-- PHASE 2M — PROFILES SELECT RLS POLICY ONLY (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
-- ROOT CAUSE THIS PHASE FIXES:
--   * PostgreSQL evaluates the SELECT policies of the target table when an
--     INSERT ... ON CONFLICT (id) DO UPDATE has to decide whether the
--     conflicting row is visible to the statement.
--   * ProfileRepository.upsertProfile() calls upsert(onConflict: 'id'), which
--     PostgREST emits as INSERT ... ON CONFLICT (id) DO UPDATE. With RLS on
--     and NO permissive SELECT policy on public.profiles, that visibility
--     check fails as well (42501) even though the INSERT and UPDATE policies
--     now exist (profiles_insert_own_row / profiles_update_own_row).
--
-- GOAL (this phase ONLY):
--   * Allow an authenticated user to SELECT ONLY their own row in
--     public.profiles.
--
-- NON-GOALS (separate phases, untouched here):
--   The existing INSERT (profiles_insert_own_row) and UPDATE
--   (profiles_update_own_row) policies, any DELETE policy, table grants,
--   columns, constraints, triggers, functions, admin authorization,
--   orders / messages / storage / pro_availability, Flutter code.
--
-- DESIGN (why this shape):
--   * Exactly ONE policy, SELECT-only, for the authenticated role.
--   * USING (auth.uid() = id): a row is readable ONLY when its primary key is
--     the caller's own auth.uid() — no other user's profile ever enters a
--     SELECT, nor the ON CONFLICT visibility probe above.
--   * No caller-supplied field is trusted: auth.uid() is server-side.
--   * Idempotent guard (pg_policies check, same shape as Phase 2G / 2L) so
--     re-running the file is safe and never duplicates the policy.
--   * No GRANT changes and no policy for anon: only `authenticated` can reach
--     this policy.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.
--   2. Verify (read-only):
--        select policyname, cmd, roles, qual, with_check
--        from pg_policies
--        where schemaname = 'public' and tablename = 'profiles'
--        order by policyname;
--      Expected — three rows:
--        profiles_insert_own_row / INSERT / {authenticated} / null / (auth.uid() = id)
--        profiles_select_own_row / SELECT / {authenticated} / (auth.uid() = id) / null
--        profiles_update_own_row / UPDATE / {authenticated} / (auth.uid() = id) / (auth.uid() = id)
--   3. Do NOT run any INSERT/UPDATE/DELETE test writes from the editor;
--      runtime verification happens on the next real sign-in.
-- ============================================================================

-- -- 1. Own-row SELECT policy (exactly one) -----------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profiles_select_own_row'
  ) then
    create policy profiles_select_own_row
      on public.profiles
      for select
      to authenticated
      using (auth.uid() = id);
  end if;
end $$;

-- -- 2. Explicit non-goals (documented, no statements) -------------------------
-- No DELETE policy. No change to profiles_insert_own_row or
-- profiles_update_own_row. No GRANT changes. No column / constraint /
-- trigger / function changes.
