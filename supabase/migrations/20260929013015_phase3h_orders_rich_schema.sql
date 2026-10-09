-- ============================================================================
-- PHASE 3H — ORDERS: RICH SCHEMA EVOLUTION (ADDITIVE ONLY) (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
-- GOAL (this phase ONLY):
--   Evolve the EXISTING, EMPTY public.orders table into the rich model the
--   current Flutter app already uses (ServiceRequest / OrdersRepository), by
--   ADDING columns and DECLARATIVE check constraints.
--
-- LIVE BASELINE (verified out-of-band; kept 100% AS-IS — no rename, no drop,
-- no type change, no default change):
--   id uuid PK | client_id uuid -> profiles(id) | pro_id uuid -> profiles(id)
--   status text DEFAULT 'pending' | description text
--   created_at timestamptz DEFAULT timezone('utc', now())
--   RLS enabled, 0 policies, 0 rows.
--
-- NON-GOALS (separate phases, untouched here):
--   * NO triggers, NO functions (RPC), NO RLS policies, NO grant/revoke.
--   * NO realtime publication changes; NO Flutter changes; NO data backfill.
--   * NO changes to profiles / professionals / admins / messages /
--     pro_availability, and no admin-authorization changes.
--
-- DESIGN (why this shape):
--   * ADDITIVE + IDEMPOTENT: `add column if not exists`, every constraint in a
--     pg_constraint existence guard, every NOT NULL hardening in an
--     information_schema guard => a re-run is a no-op.
--   * The 6 live columns stay the ownership/timeline spine; `description` is
--     REUSED as the client's free-text message (no near-duplicate column).
--   * NOT NULL hardening is safe in THIS migration because the table is EMPTY:
--     `add column ... not null` (without default) fails loudly instead of
--     inventing a backfill if rows unexpectedly exist. `client_id`, `pro_id`,
--     `status` and `created_at` are hardened because an order without a party
--     or a status is not representable, and status/created_at already carry
--     server-side defaults live.
--   * These CHECKs are IDENTITY-INDEPENDENT by construction (no auth.uid(),
--     no OLD/NEW provenance). Ownership pinning, status-transition legality
--     and review actor/timing need the caller identity => TRIGGER/RLS scope,
--     explicitly deferred.
--   * NULL semantics: `char_length(NULL) <= N` is NULL and a CHECK passes on
--     NULL, so nullable columns are not forced to be non-empty.
--   * created_at keeps its current shape (client timestamp + server default):
--     the app compares order identity with an exact-instant footprint match
--     (OrdersRepository._sameOrderFootprint) — forcing a server value is a
--     TRIGGER decision, deferred with the rest of the identity hardening.
--
-- PRECONDITION (read-only, BEFORE applying):
--   select count(*) from public.orders;   -- expected: 0
--
-- MANUAL STEP (SQL Editor as postgres/service_role, after review):
--   1. Run this whole file.
--   2. Verify (read-only):
--        select column_name, data_type, is_nullable, column_default
--        from information_schema.columns
--        where table_schema='public' and table_name='orders'
--        order by ordinal_position;
--        select conname, pg_get_constraintdef(oid) from pg_constraint
--        where conrelid='public.orders'::regclass order by conname;
--      Expected: the 6 original columns + the 11 added here, and 12 new
--      constraints whose names start with `orders_`.
--   3. If the app still reports PGRST204 / unknown column afterwards:
--        notify pgrst, 'reload schema';
--   4. Do NOT run INSERT/UPDATE/DELETE test writes from the editor.
-- ============================================================================

-- -- 1. Added columns (all idempotent) ----------------------------------------
-- NOT NULL columns are added WITHOUT a default on purpose: safe on an empty
-- table, loud (an error) if rows unexpectedly exist.
alter table public.orders
  add column if not exists service_title_fr text not null,
  add column if not exists service_title_ar text not null,
  add column if not exists client_name      text,
  add column if not exists pro_name         text,
  add column if not exists scheduled_at     timestamptz not null,
  add column if not exists address          text not null,
  add column if not exists photo_paths      jsonb not null default '[]'::jsonb,
  add column if not exists rating           numeric(2,1),
  add column if not exists review_comment   text,
  add column if not exists payment_method   text default 'cash',
  add column if not exists updated_at       timestamptz not null
                                            default timezone('utc', now());

-- -- 2. Existing nullable columns -> NOT NULL (safe: table is EMPTY) ----------
-- Guarded per column: re-running after a successful apply is a no-op.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'client_id' and is_nullable = 'YES'
  ) then
    alter table public.orders alter column client_id set not null;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'pro_id' and is_nullable = 'YES'
  ) then
    alter table public.orders alter column pro_id set not null;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'status' and is_nullable = 'YES'
  ) then
    alter table public.orders alter column status set not null;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders'
      and column_name = 'created_at' and is_nullable = 'YES'
  ) then
    alter table public.orders alter column created_at set not null;
  end if;
end $$;

-- -- 3. Declarative CHECK constraints (identity-independent only) -------------
do $$
begin
  -- Lifecycle wire values written by the app's statusToWire().
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_status_allowlist'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_status_allowlist
      check (status in ('pending', 'accepted', 'refused', 'en_route',
                        'arrived', 'in_progress', 'completed', 'cancelled'));
  end if;

  -- Review score: numeric(2,1) allows the scale; the CHECK bounds the range.
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_rating_range'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_rating_range
      check (rating is null or (rating >= 0 and rating <= 5));
  end if;

  -- Payment methods accepted by the product model (the app writes 'cash').
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_payment_method_allowlist'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_payment_method_allowlist
      check (payment_method in ('cash', 'd17', 'flouci'));
  end if;

  -- Photo list must be a JSON array (storage paths), bounded in size.
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_photo_paths_is_array'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_photo_paths_is_array
      check (jsonb_typeof(photo_paths) = 'array');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_photo_paths_max_items'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_photo_paths_max_items
      check (jsonb_array_length(photo_paths) <= 10);
  end if;

  -- Length ceilings (NULL passes: see the "NULL semantics" note above).
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_service_title_fr_len'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_service_title_fr_len
      check (char_length(service_title_fr) <= 200);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_service_title_ar_len'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_service_title_ar_len
      check (char_length(service_title_ar) <= 200);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_client_name_len'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_client_name_len
      check (char_length(client_name) <= 120);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_pro_name_len'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_pro_name_len
      check (char_length(pro_name) <= 120);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_address_len'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_address_len
      check (char_length(address) <= 300);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_description_len'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_description_len
      check (char_length(description) <= 2000);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_review_comment_len'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders add constraint orders_review_comment_len
      check (char_length(review_comment) <= 2000);
  end if;
end $$;

-- -- 4. Explicit non-goals (documented, no statements) -------------------------
-- No trigger. No function. No RLS policy. No grant/revoke. No publication
-- change. No rename/drop/type change of the six live columns. No backfill.
-- Ownership pinning, status-transition enforcement and review actor/timing
-- rules are identity-aware and therefore belong to a LATER phase.

