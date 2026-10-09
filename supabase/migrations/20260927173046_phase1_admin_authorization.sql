-- ============================================================================
-- PHASE 1 — SERVER-SIDE ADMIN AUTHORIZATION (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
-- GOAL (this phase ONLY):
--   * Real server-side admin identity rooted in auth.uid().
--   * public.is_admin() becomes the single source of truth reused by later
--     phases (orders / messages / storage / grants / realtime).
--   * Harden public.profiles against role self-promotion WITHOUT breaking
--     the client onboarding flow (client <-> professional choice).
--
-- NON-GOALS (separate phases, untouched here):
--   orders / messages / storage.objects RLS, anon/authenticated GRANT
--   tightening, realtime publication for orders/messages, pro_availability.
--
-- DESIGN (why this shape):
--   * Dedicated public.admins(user_id uuid PK -> auth.users.id): simplest
--     model for the verified live schema (profiles has NO role CHECK and
--     RLS=ON with 0 policies). Admin membership stays OUT of the
--     client-writable profile payload: normal upserts never touch it.
--   * public.is_admin() SECURITY DEFINER + STABLE, takes NO arguments —
--     auth.uid() is the only input — returns boolean, writes nothing.
--   * public.admins: RLS ON with ZERO permissive policies for
--     anon/authenticated (deny by default): roster invisible + immutable
--     via the anon-key API. Membership changes only by operator
--     (dashboard / SQL editor as postgres or service_role).
--   * profiles.role: CHECK allow-list + trigger guard reject 'admin' and
--     any unknown string even before RLS is considered.
--
-- MANUAL STEP (Supabase SQL Editor, as postgres/service_role, after review):
--   1. Run this whole file.
--   2. Enroll the FIRST admin by KNOWN auth.users.id (Dashboard ->
--      Authentication -> Users -> copy operator UUID; NEVER invent one):
--        insert into public.admins (user_id) values ('<OPERATOR-UUID>');
--   3. Verify: select public.is_admin();
--   4. No secret/password/key is required or stored anywhere here.
-- ============================================================================

-- -- 1. Admin roster: one row per administrator ------------------------------
create table if not exists public.admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table public.admins is
  'Server-side admin roster. Membership is the ONLY server-side admin '
  'signal; checked via public.is_admin() keyed off auth.uid().';

alter table public.admins enable row level security;

-- -- 2. is_admin(): the single server-side admin predicate --------------------
-- SECURITY DEFINER is REQUIRED (and safe): the caller's roster row must be
-- readable while the roster itself stays unreadable to anon/authenticated.
-- No arguments -> nothing to spoof; auth.uid() is the only input.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admins a
    where a.user_id = auth.uid()
  );
$$;

comment on function public.is_admin() is
  'Returns true iff the calling auth.uid() is enrolled in public.admins. '
  'Single server-side source of truth for admin authorization.';

-- Locked down: nobody gets it by default; authenticated may EXECUTE only.
revoke all on function public.is_admin() from public, anon, authenticated;
grant execute on function public.is_admin() to authenticated;

-- -- 3. profiles.role hardening: reject 'admin' (and any unknown role) --------
-- The verified live schema has NO CHECK on role. Client onboarding only ever
-- needs 'client' | 'professional'; anything else — 'admin' included — is
-- rejected at the database boundary regardless of RLS.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_role_allowlist'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_role_allowlist
      check (role is null or role in ('client', 'professional'));
  end if;
end $$;

-- Belt & braces for pre-existing rows AND for any RLS policy a later phase
-- might open wider: a trigger that no permissive WITH CHECK can bypass.
create or replace function public.profiles_reject_privileged_role()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.role is not null
     and new.role not in ('client', 'professional') then
    raise exception 'profiles.role % is not permitted', new.role
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function public.profiles_reject_privileged_role() is
  'Write-time guard: only client/professional (or NULL) may land in '
  'profiles.role. Admin membership lives in public.admins, never here.';

drop trigger if exists profiles_reject_privileged_role on public.profiles;

create trigger profiles_reject_privileged_role
  before insert or update of role on public.profiles
  for each row
  execute function public.profiles_reject_privileged_role();

-- -- 4. Least-privilege grants on the new objects (no widening elsewhere) -----
-- admins roster: deny by default — no anon/authenticated access at all.
revoke all on table public.admins from public, anon, authenticated;
-- profiles / orders / messages / storage / pro_availability: untouched here.

