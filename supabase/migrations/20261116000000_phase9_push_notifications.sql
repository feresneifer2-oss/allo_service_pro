-- ============================================================================
-- Phase 9 — PUSH NOTIFICATIONS: store OneSignal player IDs
-- (allo_service_pro)
-- ============================================================================
-- GOAL:
--   * Add `onesignal_player_id text` to `public.professionals` so the server
--     can target a specific professional's device for push notifications.
--   * Add `onesignal_player_id text` to `public.profiles` for client-side
--     device targeting.
--   * Idempotent: every statement is guarded, re-running is a no-op.
-- ============================================================================

-- ─── STEP 1 — professionals table ────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'professionals'
      and column_name = 'onesignal_player_id'
  ) then
    alter table public.professionals
      add column onesignal_player_id text;
  end if;
end $$;

-- ─── STEP 2 — profiles table ─────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'onesignal_player_id'
  ) then
    alter table public.profiles
      add column onesignal_player_id text;
  end if;
end $$;

-- ─── VERIFICATION (READ-ONLY; run manually in SQL Editor after applying) -----
--   select column_name, data_type
--   from information_schema.columns
--   where table_schema = 'public'
--     and table_name in ('professionals', 'profiles')
--     and column_name = 'onesignal_player_id'
--   order by table_name;
--   -- expected: 2 rows (professionals.onesignal_player_id / text,
--   --           profiles.onesignal_player_id / text)
-- ============================================================================