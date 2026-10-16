-- ============================================================================
-- Phase 7A — ORDERS AVAILABILITY GATE (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
-- BACKGROUND: clients could create orders for offline pros (bypassing
--   the client-side availability gate via Profile/Booking paths or a
--   custom Supabase client).
-- GOAL: server-side enforcement via BEFORE INSERT trigger on orders.
-- SEMANTICS:
--   * No pro_availability row → ALLOW (fallback: true matches the feed).
--   * Row with is_available = true → ALLOW.
--   * Row with is_available = false → REFUSE (SQLSTATE 'P0001', custom
--     message 'pro_unavailable').
-- NON-GOALS: no UPDATE trigger (accept/refuse later isn't affected); no
--   change to RLS; no Dart change.
-- PATTERN: mirrors public.profiles_reject_privileged_role (phase 1).
-- IDEMPOTENT: `create or replace function` + `drop trigger if exists`
--   make a re-run a no-op.
-- LINKAGE (verified in audit): orders.pro_id → profiles(id) = auth.uid()
--   = pro_availability.pro_id (auth.users.id) — same identity domain.
-- ============================================================================

-- 1. Trigger function --------------------------------------------------------
create or replace function public.orders_block_offline_pro()
returns trigger
language plpgsql
-- security invoker (default) — reads pro_availability under RLS; matches
-- the phase-1 pattern
set search_path = public, pg_temp
as $$
begin
  -- Refuse only when a row EXISTS and explicitly says offline.
  -- Missing row = unknown = allow (fallback: true).
  if exists (
    select 1
    from public.pro_availability pa
    where pa.pro_id = new.pro_id
      and pa.is_available = false
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'pro_unavailable';
  end if;
  return new;
end;
$$;

comment on function public.orders_block_offline_pro() is
  'BEFORE INSERT guard on public.orders: refuses an order whose pro_id '
  'points to a pro with is_available = false. Missing availability row '
  'is treated as available (fallback: true). SQLSTATE P0001, message '
  '"pro_unavailable".';

-- 2. Trigger (idempotent) ----------------------------------------------------
drop trigger if exists orders_block_offline_pro_trg on public.orders;

create trigger orders_block_offline_pro_trg
before insert on public.orders
for each row
execute function public.orders_block_offline_pro();

-- 3. Verification (commented) ------------------------------------------------
-- select tgname, tgtype, tgenabled
--   from pg_trigger
--  where tgrelid = 'public.orders'::regclass
--    and tgname = 'orders_block_offline_pro_trg';
--
-- Test manually (SQL Editor, as a client):
-- -- Set pro offline:
-- update public.pro_availability set is_available = false where pro_id = '<pro_uuid>';
-- -- Attempt insert (expect: P0001 'pro_unavailable'):
-- insert into public.orders (client_id, pro_id, status, ...) values (...);
-- -- Set back online or remove row → insert succeeds.
