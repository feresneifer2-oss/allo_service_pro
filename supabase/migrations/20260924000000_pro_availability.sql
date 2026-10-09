-- ============================================================================
-- pro_availability — PERSISTENT ONLINE / OFFLINE STATUS OF EVERY CRAFTSMAN
-- ("SNEY3I") SHARED IN REAL TIME WITH THE CLIENT FEED.
-- ============================================================================
-- WHY A TABLE (and not an ephemeral presence channel):
--   • the pro's choice is DURABLE — a force-close / restart / device switch
--     re-opens with the last known status instead of a factory default;
--   • a client that opens the list LATER still sees the last known state
--     (no dependency on the pro's socket being alive at that instant);
--   • the write/read path mirrors `orders` / `messages` exactly:
--     failure-tolerant repositories + a postgres_changes channel + RLS.
--
-- MAPPING (client side: lib/features/pro_dashboard/data/pro_availability_repository.dart)
--   pro_id       ← auth.users.id  (SupabaseAuthService.currentUserId)
--   pro_code     ← ProfessionalModel.id shown to clients ('PRO-XXXXX')
--   is_available ← ProProfileStore.isAvailable (the dashboard's green/red dot)
--   updated_at   ← wall-clock of the last toggle (observability)
--
-- SECURITY MODEL:
--   • SELECT: any AUTHENTICATED identity may read the board — the client feed
--     has to know who is online. Only the public code + a boolean are exposed:
--     no PII lives in this table.
--   • INSERT / UPDATE: the owner only (`auth.uid() = pro_id`) — a device can
--     never flip somebody else's status.
--   • DELETE: not granted (a row is a durable statement, not a session).
--
-- APPLY: supabase db push  |  psql -f <this file>  |  SQL editor (idempotent).
-- ============================================================================

create table if not exists public.pro_availability (
  pro_id       uuid primary key references auth.users (id) on delete cascade,
  pro_code     text,
  is_available boolean not null default false,
  updated_at   timestamptz not null default now()
);

-- One row per public code. PARTIAL index: a pro whose `pro_code` was not
-- issued yet (NULL) must never collide with another un-coded row.
create unique index if not exists pro_availability_pro_code_key
  on public.pro_availability (pro_code)
  where pro_code is not null;

comment on table public.pro_availability is
  'Durable craftsman online/offline presence, broadcast over Realtime.';

alter table public.pro_availability enable row level security;

-- REPLICA IDENTITY FULL: UPDATE payloads carry the COMPLETE new row (not just
-- the changed columns), so the client's `payload.newRecord` decode never needs
-- to merge a partial tuple.
alter table public.pro_availability replica identity full;

-- ── Privileges (RLS below still scopes every row) ───────────────────────────
grant select, insert, update on public.pro_availability to authenticated;
revoke delete on public.pro_availability from authenticated;

-- ── Policies (recreated so the file can be re-applied safely) ──────────────
drop policy if exists "pro_availability_read" on public.pro_availability;
create policy "pro_availability_read" on public.pro_availability
  for select to authenticated using (true);

drop policy if exists "pro_availability_self_insert" on public.pro_availability;
create policy "pro_availability_self_insert" on public.pro_availability
  for insert to authenticated with check (auth.uid() = pro_id);

drop policy if exists "pro_availability_self_update" on public.pro_availability;
create policy "pro_availability_self_update" on public.pro_availability
  for update to authenticated
  using (auth.uid() = pro_id)
  with check (auth.uid() = pro_id);

-- ── Realtime broadcast ─────────────────────────────────────────────────────
-- Idempotent: `alter publication ... add table` throws when the table is
-- already a member, so membership is checked first.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pro_availability'
  ) then
    alter publication supabase_realtime add table public.pro_availability;
  end if;
end $$;
