-- ============================================================================
-- PHASE 3R — ORDERS: ROW-LEVEL SECURITY POLICIES + OWNERSHIP INDEXES
-- (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
--
-- BACKGROUND (confirmed by a live, read-only audit before this file):
--   * public.orders: RLS ENABLED = true, 0 policies => deny-all for every
--     client-visible role (authenticated included). 0 rows, 0 orphans.
--     Only index today: orders_pkey on (id).
--   * App access patterns (OrdersRepository): SELECT by id and SELECT all
--     (no filter — the layer's contract says "RLS scopes the read"), INSERT
--     with client_id/pro_id stamped from the session identity, UPDATE of
--     status/rating/review_comment by id. The app NEVER deletes (zero
--     .delete() call sites on orders).
--   * public.is_admin() (Phase 1: SECURITY DEFINER, STABLE, no args, keyed
--     off auth.uid() vs public.admins) already exists and is granted to
--     authenticated — reused here exactly as-is.
--
-- GOAL (this phase ONLY):
--   1. Idempotent `enable row level security` on public.orders (already on:
--      re-running this file must remain a no-op).
--   2. Four party policies — SELECT/INSERT/UPDATE for clients + pros.
--   3. One admin SELECT policy on public.is_admin().
--   4. Two performance indexes backing the ownership predicates.
--   5. NO DELETE policy — deletes remain denied by default.
--
-- SECURITY NOTES:
--   * Auth identity from auth.uid() only, never from client input.
--   * INSERT cannot forge another user's client_id (WITH CHECK pins the new
--     row's client_id to auth.uid(); a foreign/empty uuid fails server-side).
--   * UPDATE cannot change ownership (WITH CHECK re-enforces the SAME
--     client_id / pro_id that USING matched on — a row cannot be "moved"
--     to another account during the update).
--   * No DELETE policy — deletes are denied by default (the app has no
--     delete path; nothing legitimate is revoked by omitting it).
--   * Admin SELECT uses existing public.is_admin() from Phase 1 — no new
--     admin table read, no new function, no arguments to spoof.
--
-- NON-GOALS (separate phases, untouched here):
--   * NO status-transition enforcement: RLS policies cannot see OLD/NEW
--     pairs, so `pending -> accepted`-style legality stays where it lives
--     today (RequestStore._isValidTransition, client-side) until a later
--     BEFORE UPDATE trigger / transition-RPC phase.
--   * NO column-level restrictions (not expressible per-user in RLS; the
--     two UPDATE policies are identity-scoped by design).
--   * NO RPC/function changes, NO grant/revoke changes, NO Dart changes,
--     NO tests, NO data backfill (table is empty — confirmed 0 rows).
--   * NO changes to profiles / professionals / admins / messages /
--     pro_availability, and no realtime publication changes (the SELECT
--     policy is what scopes postgres_changes deliveries to owned rows).
--
-- DESIGN (why this shape, and why this order):
--   * IDEMPOTENT EVERYWHERE: every index uses `if not exists`; every policy
--     is guarded by an `pg_policies` existence check; `enable row level
--     security` is a no-op when already enabled. Re-running the whole file
--     is safe and changes nothing.
--   * STEP 1 — INDEXES FIRST: with RLS already on and 0 policies, index
--     creation is pure read-path work; the two ownership predicates get
--     O(log n) lookups from the moment policies exist (only orders_pkey
--     exists today, so every policy re-check would otherwise seq-scan).
--   * STEP 2 — POLICIES SECOND: the live state is ALREADY deny-all, so each
--     policy added here can only RESTORE legitimate access — this file can
--     never open a window with MORE exposure than before (the classic
--     "policies before enable" hole is impossible: RLS is already enabled).
--   * STEP 3 — ENABLE RLS LAST as a documented, idempotent invariant: the
--     file self-heals and states the desired end-state regardless of how
--     the live flag was originally set.
--   * UPDATE is split into a client leg and a pro leg so each carries its
--     own USING + WITH CHECK pair and its own audit trail; a client-only
--     session can never satisfy the pro leg, and vice versa (a session that
--     legitimately owns BOTH sides matches both policies — same net effect
--     as a single OR policy, with clearer intent).
--   * Roles are narrowed to `to authenticated`: anon has no business here
--     (OTP sign-in), and service_role bypasses RLS regardless.
--
-- ORDER OF OPERATIONS (applied in this exact order):
--   Step 1: create the two ownership indexes (if not exists).
--   Step 2: create the five policies (each guarded via pg_policies).
--   Step 3: alter table ... enable row level security (idempotent no-op).
--   Step 4: read-only verification block at the bottom (commented; run it
--           manually in the SQL Editor AFTER applying).
-- ============================================================================

-- -- STEP 1 — ownership indexes (idempotent) ----------------------------------
-- Back the two RLS predicates (and FK-shaped lookups) with O(log n) scans;
-- today only orders_pkey (id) exists on public.orders.
create index if not exists orders_client_id_idx
  on public.orders (client_id);

create index if not exists orders_pro_id_idx
  on public.orders (pro_id);

-- -- STEP 2 — RLS policies (idempotent: one pg_policies guard per policy) ------
-- Identity source: auth.uid() ONLY — never a request body, never an echo of
-- a client-supplied column.
do $$
begin
  -- SELECT — each party reads only the rows it owns. Enables
  -- OrdersRepository.fetchOrders / fetchOrderById / verifyOrderRow and
  -- scopes realtime postgres_changes deliveries to the same rows (RLS is
  -- enforced on the realtime channel too). The admin leg is policy #5.
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'orders'
      and policyname = 'orders_select_own'
  ) then
    create policy orders_select_own on public.orders
      for select to authenticated
      using (client_id = auth.uid() or pro_id = auth.uid());
  end if;

  -- INSERT — a client can only create rows stamped as THEMSELVES; forging
  -- another account's client_id fails WITH CHECK server-side (pro_id is
  -- NOT NULL by schema; the app stamps it with the pro's auth uid at draft
  -- time and refuses an empty uid before any network write).
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'orders'
      and policyname = 'orders_insert_own'
  ) then
    create policy orders_insert_own on public.orders
      for insert to authenticated
      with check (client_id = auth.uid());
  end if;

  -- UPDATE (client leg) — cancel + review (rating / review_comment) on the
  -- client's own orders. USING scopes the matched rows; WITH CHECK forbids
  -- re-stamping ownership in the same UPDATE (no client_id forgery path).
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'orders'
      and policyname = 'orders_update_own_client'
  ) then
    create policy orders_update_own_client on public.orders
      for update to authenticated
      using (client_id = auth.uid())
      with check (client_id = auth.uid());
  end if;

  -- UPDATE (pro leg) — accept / refuse / en_route / arrived / in_progress /
  -- completed on orders assigned to this professional (pro_id IS the pro's
  -- Supabase auth uid since Phase 3L). Same USING/WITH CHECK ownership
  -- pinning: the row can never be re-stamped away from its pro.
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'orders'
      and policyname = 'orders_update_own_pro'
  ) then
    create policy orders_update_own_pro on public.orders
      for update to authenticated
      using (pro_id = auth.uid())
      with check (pro_id = auth.uid());
  end if;

  -- Admin SELECT — dashboard hydration / support reads via the EXISTING
  -- Phase 1 predicate (SECURITY DEFINER, no args, auth.uid() vs admins).
  -- An admin owns no client_id/pro_id of their own, so without this policy
  -- admin aggregates legitimately return nothing.
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename  = 'orders'
      and policyname = 'orders_admin_select'
  ) then
    create policy orders_admin_select on public.orders
      for select to authenticated
      using (public.is_admin());
  end if;

  -- NO DELETE POLICY, on purpose: the app never deletes orders, so DELETE
  -- stays denied by default for every client-visible role.
end $$;

-- -- STEP 3 — enable RLS (idempotent; already enabled on the live table) -------
alter table public.orders enable row level security;

-- -- STEP 4 — verification (READ-ONLY; run manually AFTER applying) -----------
-- select c.relrowsecurity as rls_enabled
--   from pg_class c
--  where c.oid = 'public.orders'::regclass;
--  -- expected: rls_enabled = true
--
-- select policyname, cmd, roles, qual, with_check
--   from pg_policies
--  where schemaname = 'public' and tablename = 'orders'
--  order by policyname;
--  -- expected: exactly 5 rows — orders_admin_select, orders_insert_own,
--  --            orders_select_own, orders_update_own_client,
--  --            orders_update_own_pro; no DELETE row anywhere
--
-- select indexname from pg_indexes
--  where schemaname = 'public' and tablename = 'orders'
--  order by indexname;
--  -- expected: orders_client_id_idx, orders_pkey, orders_pro_id_idx
--
-- select count(*) from public.orders;
--  -- expected: 0 (unchanged — this file writes no rows)
--
-- Optional behavioral smoke (authenticated sessions, table is empty):
--   * client: INSERT with own client_id  -> succeeds
--   * client: INSERT with foreign client_id -> rejected (42501 / policy)
--   * either: SELECT -> returns only rows owned by the session
--   * either: UPDATE a foreign row -> 0 rows affected
--   * any role: DELETE -> denied (no policy)
-- ============================================================================