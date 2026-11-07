-- ============================================================================
-- Phase 8B — MESSAGES: schema alignment + RLS (allo_service_pro)
-- PROPOSAL — NOT APPLIED, NOT IN supabase/migrations/ ON PURPOSE.
-- Supersedes docs/proposed/phase8a_messages_rls.sql (written from the migration
-- files alone, before the live table was inspected — its premise was wrong).
-- ============================================================================
-- WHAT THE LIVE INSPECTION ACTUALLY SHOWED (2026-11-07):
--   * public.messages EXISTS with: id uuid PK, order_id uuid, sender_id uuid,
--     content text NOT NULL, created_at timestamptz NOT NULL.
--   * RLS is ALREADY ENABLED (relrowsecurity = true) and there are NO policies
--     → deny-all. The table is NOT readable by anybody: the "every message is
--     exposed" reading of the earlier audit was WRONG.
--   * 0 rows.
--   * anon / authenticated hold the full Supabase default grant set, including
--     TRUNCATE — which bypasses RLS entirely.
--
-- THE REAL DEFECT: the table does not match the wire contract the app writes.
--   app sends: id (epoch-ish STRING), request_id, sender_id, sender_name,
--              body, is_customer, type, media_path, voice_duration_sec,
--              latitude, longitude, created_at
--   table has: id (uuid), order_id, sender_id, content, created_at
--   ⇒ EVERY chat INSERT was rejected by Postgres. Chat has never persisted.
--
-- SCOPE: renames + additive columns + one CHECK + three policies + grant
--   cleanup. NO data migration (the table is empty). NO app change beyond the
--   message id, which now uses the EXISTING v4 generator
--   (RequestStore.newClientId) so `id` stays a real uuid.
-- IDEMPOTENT: every step is guarded.
-- ============================================================================


-- ─── STEP 0 — PRE-CHECK (READ-ONLY) ─────────────────────────────────────────
--   select c.relrowsecurity from pg_class c
--    where c.oid = 'public.messages'::regclass;                -- true
--   select count(*) from public.messages;                       -- 0
--   select column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema='public' and table_name='messages'
--    order by ordinal_position;
--
-- ABORT IF count(*) > 0: the renames below would carry rows you have not
-- inspected. The current state (0) makes this migration risk-free.


-- ─── STEP 1 — RENAMES (align the names with the wire contract) ──────────────
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='messages'
                and column_name='order_id')
     and not exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='messages'
                and column_name='request_id') then
    alter table public.messages rename column order_id to request_id;
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='messages'
                and column_name='content')
     and not exists (select 1 from information_schema.columns
              where table_schema='public' and table_name='messages'
                and column_name='body') then
    alter table public.messages rename column content to body;
  end if;
end $$;


-- ─── STEP 2 — ADDITIVE COLUMNS ──────────────────────────────────────────────
-- `id` and `request_id`/`sender_id` KEEP their uuid type: the app now sends a
-- v4 uuid for the message id, so no type change (and no lossy cast) is needed.
alter table public.messages
  add column if not exists sender_name        text,
  add column if not exists is_customer        boolean not null default false,
  add column if not exists type               text    not null default 'text',
  add column if not exists media_path         text,
  add column if not exists voice_duration_sec integer not null default 0,
  add column if not exists latitude           double precision,
  add column if not exists longitude          double precision;

-- `body`: the app always writes it (empty string for media-only messages), so
-- NOT NULL is safe and matches the renamed `content` constraint.
alter table public.messages alter column body set not null;

-- Allowed message kinds — the four ChatMessageType values.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'messages_type_check') then
    alter table public.messages
      add constraint messages_type_check
      check (type in ('text', 'voice', 'photo', 'location'));
  end if;
end $$;

-- Lookup index: the history query is `.eq('request_id', …).order('created_at')`.
create index if not exists messages_request_created_idx
  on public.messages (request_id, created_at);


-- ─── STEP 3 — RLS POLICIES (participants of the order) ──────────────────────
-- `messages.request_id` IS the order id; a participant is that order's client
-- or its pro — the same predicate the orders policies use.
do $$
begin
  if not exists (select 1 from pg_policies
                  where schemaname='public' and tablename='messages'
                    and policyname='messages_select_participant') then
    create policy messages_select_participant on public.messages
      for select to authenticated
      using (
        exists (select 1 from public.orders o
                 where o.id = messages.request_id
                   and (o.client_id = auth.uid() or o.pro_id = auth.uid()))
      );
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname='public' and tablename='messages'
                    and policyname='messages_insert_participant') then
    create policy messages_insert_participant on public.messages
      for insert to authenticated
      with check (
        sender_id = auth.uid()
        and exists (select 1 from public.orders o
                     where o.id = messages.request_id
                       and (o.client_id = auth.uid() or o.pro_id = auth.uid()))
      );
  end if;

  if not exists (select 1 from pg_policies
                  where schemaname='public' and tablename='messages'
                    and policyname='messages_admin_select') then
    create policy messages_admin_select on public.messages
      for select to authenticated
      using (public.is_admin());
  end if;
end $$;

alter table public.messages enable row level security;

-- NO update / delete policy, on purpose: the app never edits or deletes a
-- message once sent (ChatStore only inserts and reads).


-- ─── STEP 4 — GRANT CLEANUP (least privilege) ───────────────────────────────
-- `anon` should never touch chat, and TRUNCATE bypasses RLS entirely.
revoke all on table public.messages from anon;
revoke truncate, references, trigger on table public.messages from authenticated;


-- ─── STEP 5 — VERIFICATION (READ-ONLY, after applying) ──────────────────────
--   select c.relrowsecurity from pg_class c
--    where c.oid='public.messages'::regclass;                    -- true
--   select policyname, cmd from pg_policies
--    where schemaname='public' and tablename='messages'
--    order by policyname;                                        -- 3 rows
--   select column_name, data_type from information_schema.columns
--    where table_schema='public' and table_name='messages'
--    order by ordinal_position;                                  -- no order_id/content
--
-- FUNCTIONAL (as a real client JWT, NOT service_role):
--   1. client A opens their own order chat → history loads.
--   2. client A reads another order's chat → 0 rows (not an error).
--   3. client A sends a message → INSERT succeeds; the row is visible to the
--      pro of that order and to nobody else.
--   4. client A forges sender_id = '<other uid>' → INSERT must FAIL.
--
-- REALTIME (the messages channel is RLS-aware):
--   select tablename from pg_publication_tables
--    where pubname='supabase_realtime' and tablename='messages';


-- ─── ROLLBACK ──────────────────────────────────────────────────────────────
--   drop policy if exists messages_select_participant on public.messages;
--   drop policy if exists messages_insert_participant on public.messages;
--   drop policy if exists messages_admin_select        on public.messages;
--   drop index  if exists messages_request_created_idx;
--   alter table public.messages drop constraint if exists messages_type_check;
--   alter table public.messages rename column request_id to order_id;
--   alter table public.messages rename column body to content;
--   -- added columns may stay (nullable / defaulted) or be dropped explicitly.
--
-- NOTE (accepted debt): `sender_name` is denormalized. Chat reads are the
-- hottest path in the app and a join on every history page is not worth it;
-- if names must stay canonical, resolve them from `profiles` at read time
-- instead of storing them.
