-- ============================================================================
-- Phase 8C — PROFESSIONALS realtime publication (allo_service_pro)
-- APPLIED 2026-11-09 through the Supabase SQL Editor.
-- ============================================================================
-- REQUIRED BY: the R8 channel in SupabaseRealtimeService
--   (`realtime:public:professionals:<uid>`). A table that is not part of the
--   `supabase_realtime` publication emits NO postgres_changes event, so without
--   this an admin approval could only reach the waiting professional on boot,
--   on a resume that escaped the 5-minute sync TTL, or on a connectivity
--   change — never while they sat on the verification gate.
--
-- IDEMPOTENT: the guard makes a later `supabase db push` a no-op.
-- ============================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'professionals'
  ) then
    alter publication supabase_realtime add table public.professionals;
  end if;
end $$;


-- ─── VERIFY (READ-ONLY) ─────────────────────────────────────────────────────
--   select tablename from pg_publication_tables
--    where pubname = 'supabase_realtime'
--    order by tablename;
--   -- expected: messages, orders, pro_availability, professionals
--
-- SECURITY: delivery stays RLS-scoped. `professionals_select_own_row`
-- (phase 3O) is what limits the subscriber to its OWN row; the channel adds a
-- server-side filter (`id=eq.<own uid>`) on top, so another professional's
-- status can never be delivered to this device.
