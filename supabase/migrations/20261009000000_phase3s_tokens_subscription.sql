-- ============================================================================
-- PHASE 3S - SERVER-SIDE SUBSCRIPTION + TOKEN LEDGER
-- (allo_service_pro)
-- Idempotent + additive - safe to run twice (every DDL statement is guarded).
-- ============================================================================
-- BACKGROUND:
--   * Tokens today are CLIENT-SIDE ONLY: the Flutter app seeds
--     tokens = 150 in local state, deducts 10 on order accept, and mirrors
--     the value bidirectionally with the admin UI. There is no server-side
--     column, no ledger and no enforcement - any client can accept
--     unlimited orders. The subscription (paid_until) is likewise local;
--     the paywall keys off a local 'expired' status only.
--   * Phase 3P established public.is_admin(), status/approved_at and the
--     approve/reject/reset RPCs. This phase EXTENDS the same path so an
--     approval also grants the one-time 150-token signup bonus server-side.
--
-- GOAL (this phase ONLY):
--   1. public.professionals: add tokens (integer not null default 0,
--      CHECK >= 0) and paid_until (timestamptz null).
--   2. New append-only ledger table public.token_transactions (FKs, kind
--      allowlist, two partial UNIQUE indexes used as idempotency keys).
--   3. RLS on the ledger: SELECT own + SELECT admin. NO write policies -
--      clients never write the ledger; only SECURITY DEFINER RPCs do.
--   4. Three new RPCs:
--        - public.admin_set_subscription(uuid, timestamptz) -> void
--        - public.admin_adjust_tokens(uuid, integer)        -> integer
--        - public.pro_accept_order(uuid)                    -> integer
--   5. public.admin_provision_professional gains the one-time 150-token
--      signup grant (INSERT path) + its 'signup_grant' ledger row.
--
-- NON-GOALS (separate phases, untouched here):
--   * NO Dart/Flutter change in this file - the app keeps working until the
--     follow-up phase switches reads/writes over to these RPCs.
--   * NO backfill of EXISTING professionals' local token balances (kind
--     'backfill' is reserved for that future step).
--   * NO expiry scheduler/cron: paid_until is a plain timestamp evaluated
--     at call time. No Edge Function, no secret, no storage, no profiles /
--     orders / messages schema change (the two FKs below target tables that
--     already exist).
--
-- DESIGN (mirrors Phase 3N + 3P + 3Q):
--   * ADDITIVE + IDEMPOTENT: `add column if not exists`,
--     `create table/index if not exists`, `pg_constraint` / `pg_policies`
--     guards inside `do $$ ... $$`, `create or replace` for every RPC -
--     a second run is always a no-op.
--   * Authorization FIRST on every admin RPC: public.is_admin() (Phase 1)
--     is checked before ANY other work (errcode 42501), so a non-admin
--     cannot even probe whether a row exists. pro_accept_order keys off
--     auth.uid() and refuses any caller who is not the order's pro.
--   * VOLATILE (these functions write), SECURITY DEFINER (bypasses the
--     own-row-only RLS for these paths only),
--     SET search_path = public, pg_temp (pinned: pg_temp LAST so temporary
--     objects cannot shadow public.*; every reference is schema-qualified).
--   * No dynamic SQL anywhere; plpgsql only; fully qualified names.
--   * The two partial UNIQUE indexes are the idempotency keys: a replayed
--     approval can never double-grant and a replayed accept can never
--     double-charge.
--   * REVOKE ALL (PUBLIC, anon, authenticated) first, then GRANT EXECUTE to
--     authenticated only - nobody gets these by default.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.  (Re-running is safe - every step is guarded.)
--   2. Verify read-only (section 9 at the bottom, commented out).
--   3. No secret/password/key is required or stored anywhere here.
-- ============================================================================

-- -- 1. Token + subscription columns on public.professionals (idempotent) ---------
alter table public.professionals
  add column if not exists tokens integer not null default 0;

alter table public.professionals
  add column if not exists paid_until timestamptz;

-- -- 2. tokens non-negative CHECK (idempotent via pg_constraint guard) ------------
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'professionals_tokens_non_negative'
      and conrelid = 'public.professionals'::regclass
  ) then
    alter table public.professionals add constraint professionals_tokens_non_negative
      check (tokens >= 0);
  end if;
end $$;

-- -- 3. The ledger table + idempotency indexes (idempotent) -----------------------
-- Append-only log of every balance change. The two partial UNIQUE indexes are
-- the idempotency keys: one signup_grant per pro, one accept_fee per order.
create table if not exists public.token_transactions (
  id          uuid primary key default gen_random_uuid(),
  pro_id      uuid not null references public.professionals(id) on delete cascade,
  order_id    uuid references public.orders(id) on delete set null,
  delta       integer not null,
  kind        text not null check (kind in
                ('signup_grant','accept_fee','admin_adjust','backfill')),
  created_at  timestamptz not null default now()
);

-- Belt-and-braces: a table created by an earlier manual run still ends up
-- with the kind allowlist under its canonical auto-generated name.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'token_transactions_kind_check'
      and conrelid = 'public.token_transactions'::regclass
  ) then
    alter table public.token_transactions add constraint token_transactions_kind_check
      check (kind in ('signup_grant','accept_fee','admin_adjust','backfill'));
  end if;
end $$;

create unique index if not exists token_transactions_trial_once
  on public.token_transactions(pro_id) where kind = 'signup_grant';

create unique index if not exists token_transactions_accept_once
  on public.token_transactions(order_id) where kind = 'accept_fee';

create index if not exists token_transactions_pro_id_idx
  on public.token_transactions(pro_id);

-- -- 4. RLS on the ledger: SELECT own + SELECT admin, nothing else ---------------
-- enable + grant are idempotent (re-granting an existing grant is a no-op).
alter table public.token_transactions enable row level security;

grant select on table public.token_transactions to authenticated;

-- A pro may audit their own balance history.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename  = 'token_transactions'
      and policyname = 'token_transactions_select_own'
  ) then
    create policy token_transactions_select_own
      on public.token_transactions
      for select
      to authenticated
      using (pro_id = auth.uid());
  end if;
end $$;

-- Admins see the whole ledger (single source of truth: public.is_admin()).
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename  = 'token_transactions'
      and policyname = 'token_transactions_admin_select'
  ) then
    create policy token_transactions_admin_select
      on public.token_transactions
      for select
      to authenticated
      using (public.is_admin());
  end if;
end $$;

-- NO INSERT/UPDATE/DELETE policy is created: clients never write the ledger;
-- only the SECURITY DEFINER RPCs below do (they bypass RLS by design).

-- -- 5. New RPC: admin-only subscription grant -----------------------------------
create or replace function public.admin_set_subscription(
  p_pro_id uuid,
  p_until timestamptz
)
returns void
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
begin
  -- 1) Authorization FIRST (same guard, same errcode as admin_provision_*).
  if not public.is_admin() then
    raise exception
      'admin_set_subscription: caller is not an administrator'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 2) Identity checks (mirrors Phase 3P step 2).
  if p_pro_id is null then
    raise exception
      'admin_set_subscription: p_pro_id must not be null'
      using errcode = '23502';  -- not_null_violation
  end if;

  --    Setting a subscription must never silently CREATE a row.
  if not exists (
    select 1 from public.professionals pr where pr.id = p_pro_id
  ) then
    raise exception
      'admin_set_subscription: no professionals row for %', p_pro_id
      using errcode = '23503';  -- foreign_key_violation
  end if;

  -- 3) Write: paid_until is ONLY written here, never caller-reachable
  --    through any other path. p_until = null revokes the subscription.
  update public.professionals
  set paid_until = p_until
  where id = p_pro_id;
end;
$$;

revoke all on function public.admin_set_subscription(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function public.admin_set_subscription(uuid, timestamptz)
  to authenticated;

comment on function public.admin_set_subscription(uuid, timestamptz) is
  'Admin-only (public.is_admin()): sets paid_until (null revokes) on the '
  'public.professionals row of p_pro_id. SECURITY DEFINER + VOLATILE, '
  'search_path pinned to public, pg_temp. Returns void.';

-- -- 6. New RPC: admin-only token adjustment -------------------------------------
create or replace function public.admin_adjust_tokens(
  p_pro_id uuid,
  p_delta integer
)
returns integer
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare v_new integer;
begin
  -- 1) Authorization FIRST.
  if not public.is_admin() then
    raise exception
      'admin_adjust_tokens: caller is not an administrator'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 2) Identity checks.
  if p_pro_id is null or p_delta is null then
    raise exception
      'admin_adjust_tokens: null arguments'
      using errcode = '23502';  -- not_null_violation
  end if;

  -- 3) Apply the delta floored at 0 (the professionals_tokens_non_negative
  --    CHECK can never trip because greatest(0, ...) clamps first). The
  --    ledger records the REQUESTED delta, verbatim - the clamp is visible
  --    by comparing professionals.tokens against the running sum.
  update public.professionals
  set tokens = greatest(0, tokens + p_delta)
  where id = p_pro_id
  returning tokens into v_new;

  if v_new is null then
    raise exception
      'admin_adjust_tokens: no professionals row for %', p_pro_id
      using errcode = '23503';  -- foreign_key_violation
  end if;

  insert into public.token_transactions (pro_id, delta, kind)
  values (p_pro_id, p_delta, 'admin_adjust');

  return v_new;
end;
$$;

revoke all on function public.admin_adjust_tokens(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.admin_adjust_tokens(uuid, integer)
  to authenticated;

comment on function public.admin_adjust_tokens(uuid, integer) is
  'Admin-only (public.is_admin()): applies p_delta to public.professionals.'
  'tokens (clamped to >= 0), logs the requested delta to '
  'public.token_transactions (kind=admin_adjust) in the SAME transaction, '
  'and returns the new balance. SECURITY DEFINER + VOLATILE, search_path '
  'pinned to public, pg_temp.';

-- -- 7. New RPC: pro order acceptance (10-token fee, free while subscribed) -------
-- Single server-side gate for accept: fee, subscription bypass and status
-- transition all happen in ONE transaction - the client can no longer skip
-- the fee or accept a non-pending order. Replay-safe: an already-accepted
-- order returns the current balance without charging again.
create or replace function public.pro_accept_order(
  p_order_id uuid
)
returns integer
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_status text;
  v_pro_id uuid;
  v_is_paid boolean;
  v_balance integer;
begin
  -- 1) Identity FIRST: no signed-in user, no acceptance.
  if v_uid is null then
    raise exception
      'pro_accept_order: no authenticated identity'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  if p_order_id is null then
    raise exception
      'pro_accept_order: p_order_id must not be null'
      using errcode = '23502';  -- not_null_violation
  end if;

  -- 2) Load the order; missing row => 23503 (no probing).
  select o.status, o.pro_id
  into v_status, v_pro_id
  from public.orders o
  where o.id = p_order_id;

  if v_pro_id is null then
    raise exception
      'pro_accept_order: no orders row for %', p_order_id
      using errcode = '23503';  -- foreign_key_violation
  end if;

  --    A pro may only accept THEIR OWN order (ownership check before any write).
  if v_pro_id <> v_uid then
    raise exception
      'pro_accept_order: caller is not the pro for this order'
      using errcode = '42501';  -- insufficient_privilege
  end if;

  -- 3) Idempotency: an already-accepted order is a no-op that returns the
  --    current balance - a retry can never double-charge.
  if v_status = 'accepted' then
    select tokens into v_balance
    from public.professionals
    where id = v_uid;
    return v_balance;
  end if;

  if v_status <> 'pending' then
    raise exception
      'pro_accept_order: order status is %, expected pending', v_status
      using errcode = '22023';  -- check_violation
  end if;

  -- 4) Read the fee inputs in one snapshot: active subscription bypasses
  --    the fee entirely (paid_until > now()), everyone else pays 10.
  select (paid_until is not null and paid_until > now()),
         coalesce(tokens, 0)
  into v_is_paid, v_balance
  from public.professionals
  where id = v_uid;

  if v_is_paid then
    update public.orders
    set status = 'accepted'
    where id = p_order_id;
    return v_balance;
  end if;

  -- 5) Insufficient balance: refuse BEFORE touching anything (the raised
  --    exception rolls back the whole function - nothing is written).
  if v_balance < 10 then
    raise exception
      'pro_accept_order: insufficient tokens (% < 10)', v_balance
      using errcode = '22023';  -- check_violation
  end if;

  -- 6) Charge + accept + log, atomically (one transaction): the professionals
  --    row and the ledger row can never disagree.
  update public.professionals
  set tokens = tokens - 10
  where id = v_uid
  returning tokens into v_balance;

  update public.orders
  set status = 'accepted'
  where id = p_order_id;

  insert into public.token_transactions (pro_id, order_id, delta, kind)
  values (v_uid, p_order_id, -10, 'accept_fee');

  return v_balance;
end;
$$;

revoke all on function public.pro_accept_order(uuid)
  from public, anon, authenticated;
grant execute on function public.pro_accept_order(uuid)
  to authenticated;

comment on function public.pro_accept_order(uuid) is
  'Pro-side: accepts own pending order in ONE transaction - charges the '
  '10-token fee (waived while paid_until > now()), flips status to '
  'accepted and logs kind=accept_fee (unique per order, so replays are '
  'no-ops). Returns the new token balance. SECURITY DEFINER + VOLATILE, '
  'search_path pinned to public, pg_temp.';

-- -- 8. The provisioning RPC now ALSO grants the 150-token signup bonus -----------
-- Same signature and return shape as Phase 3N/3P (create or replace: idempotent;
-- existing EXECUTE grants from Phase 3N/3P carry over untouched). Changes vs
-- Phase 3P:
--   * the INSERT branch now sets tokens = 150 (new accounts start credited),
--   * tokens is DELIBERATELY absent from the DO UPDATE set-list - a
--     re-approval NEVER resets or re-grants the balance,
--   * a 'signup_grant' ledger row is written after the upsert,
--     ON CONFLICT DO NOTHING - the partial unique index
--     token_transactions_trial_once makes every replay a no-op,
--   * a row created BEFORE Phase 3S (never credited, no ledger row) gets
--     its one-time +150 here, keyed by that same ledger row, so ledger and
--     balance can never disagree.
-- The is_admin() guard, the profiles existence check, status='approved',
-- approved_at=now() and is_verified=true are unchanged from Phase 3P.
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
  --    is_verified := true, status := 'approved' and approved_at := now() are
  --    written HERE, never caller-controlled — a brand-new row AND an existing
  --    row (possibly stale pending/rejected) both end approved. NULL incoming
  --    specialty/bio keeps the previously stored value. tokens = 150 applies
  --    to the INSERT branch only (the conflict branch never touches it).
  insert into public.professionals as pr
    (id, specialty, bio, is_verified, status, approved_at, tokens)
  values (p_user_id, p_specialty, p_bio, true, 'approved', now(), 150)
  on conflict (id) do update
    set specialty   = coalesce(excluded.specialty, pr.specialty),
        bio         = coalesce(excluded.bio,       pr.bio),
        is_verified = true,
        status      = 'approved',
        approved_at = now();

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
  'approved_at=now()) AND grants the one-time 150-token signup bonus '
  '(INSERT sets tokens=150; the kind=signup_grant ledger row is unique per '
  'pro, so replays never double-grant and never reset the balance). '
  'SECURITY DEFINER + VOLATILE, search_path pinned to public, pg_temp. '
  'is_verified always becomes true; no caller-controlled authorization '
  'field; NULL specialty/bio preserves the stored value. '
  'Returns (professional_id, professional_is_verified).';

-- -- 9. READ-ONLY VERIFICATION (commented out — run by hand in SQL Editor) --------
-- Every row must return present = true / n = 1.
--
-- -- 9a. Columns + table exist:
-- select 'professionals.tokens'   as item,
--        count(*)                 as n
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name   = 'professionals'
--   and column_name  = 'tokens'
-- union all
-- select 'professionals.paid_until', count(*)
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name   = 'professionals'
--   and column_name  = 'paid_until'
-- union all
-- select 'table token_transactions', count(*)
-- from information_schema.tables
-- where table_schema = 'public'
--   and table_name   = 'token_transactions';
--
-- -- 9b. The 4 RPCs exist:
-- select p.proname, count(*)
-- from pg_proc p
-- join pg_namespace n on n.oid = p.pronamespace
-- where n.nspname = 'public'
--   and p.proname in ('admin_set_subscription',
--                     'admin_adjust_tokens',
--                     'pro_accept_order',
--                     'admin_provision_professional')
-- group by p.proname
-- order by p.proname;   -- expect 4 rows
--
-- -- 9c. The 2 ledger policies exist (+ zero write policies):
-- select policyname, cmd
-- from pg_policies
-- where schemaname = 'public'
--   and tablename  = 'token_transactions'
-- order by policyname;
-- -- expect exactly 2 rows: token_transactions_admin_select (select),
-- --                        token_transactions_select_own  (select)
--
-- -- 9d. Optional consistency spot-checks (no join, no assumptions):
-- select pr.id, pr.tokens, pr.paid_until,
--        (select count(*) from public.token_transactions t
--          where t.pro_id = pr.id) as ledger_rows
-- from public.professionals pr
-- limit 20;
