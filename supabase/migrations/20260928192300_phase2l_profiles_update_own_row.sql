-- ============================================================================
-- PHASE 2L — PROFILES UPDATE RLS POLICY ONLY (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
-- ROOT CAUSE THIS PHASE FIXES:
--   * INSERT under authenticated + auth.uid() = id succeeds.
--   * INSERT ... ON CONFLICT (id) DO UPDATE fails with 42501, because
--     ProfileRepository.upsertProfile() calls upsert(onConflict: 'id') and
--     public.profiles has an INSERT policy but NO UPDATE policy: the conflict
--     branch IS an UPDATE, and with RLS on and no permissive UPDATE policy it
--     is denied by default -> "new row violates row-level security policy".
--
-- GOAL (this phase ONLY):
--   * Allow an authenticated user to UPDATE ONLY their own row in
--     public.profiles — exactly what the upsert's DO UPDATE branch needs.
--
-- NON-GOALS (separate phases, untouched here):
--   The existing INSERT policy (profiles_insert_own_row), SELECT / DELETE
--   policies on profiles, table grants, columns, constraints, triggers,
--   functions, admin authorization, orders / messages / storage /
--   pro_availability, Flutter code.
--
-- DESIGN (why this shape):
--   * Exactly ONE policy, UPDATE-only, for the authenticated role.
--   * USING (auth.uid() = id): which EXISTING row may be updated — only the
--     caller's own row.
--   * WITH CHECK (auth.uid() = id): the RESULTING row must still belong to the
--     caller — a profile can never be re-assigned to another user id.
--   * Both expressions are server-side (auth.uid()); no caller-supplied field
--     (email, phone, role, full_name) is ever trusted.
--   * Idempotent guard (pg_policies check, same shape as Phase 2G) so
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
--      Expected — two rows:
--        profiles_insert_own_row / INSERT / {authenticated} / null / (auth.uid() = id)
--        profiles_update_own_row / UPDATE / {authenticated} / (auth.uid() = id) / (auth.uid() = id)
--   3. Do NOT run any INSERT/UPDATE/DELETE test writes from the editor;
--      runtime verification happens on the next real sign-in.
-- ============================================================================

-- -- 1. Own-row UPDATE policy (exactly one) -----------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'profiles'
      and policyname = 'profiles_update_own_row'
  ) then
    create policy profiles_update_own_row
      on public.profiles
      for update
      to authenticated
      using (auth.uid() = id)
      with check (auth.uid() = id);
  end if;
end $$;

-- -- 2. Explicit non-goals (documented, no statements) -------------------------
-- No SELECT policy. No DELETE policy. No change to profiles_insert_own_row.
-- No GRANT changes. No column / constraint / trigger / function changes.
