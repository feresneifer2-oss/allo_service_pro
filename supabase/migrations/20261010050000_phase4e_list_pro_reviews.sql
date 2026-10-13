-- ============================================================================
-- PHASE 4E — LIST PRO REVIEWS (per-review)  (allo_service_pro)
-- Prepared, NOT executed. Review + apply manually in Supabase SQL Editor.
-- ============================================================================
--
-- BACKGROUND: The pro profile shows only the AGGREGATE (rating, review_count)
--   computed server-side (Phase 4D). Individual reviews live on each completed
--   order row (rating / review_comment / client_name — Phase 3H). A client
--   reading a pro's page is NOT the order's client_id or pro_id, so the
--   orders_select_own RLS policy (client_id = auth.uid() OR pro_id =
--   auth.uid()) hides those rows from them. A SECURITY DEFINER RPC is the
--   established pattern (Phase 4C/4D) to expose a curated, read-only view.
--
-- GOAL (this phase ONLY):
--   1. public.list_pro_reviews(p_pro_id uuid, p_limit integer) — returns the
--      individual reviews of a given professional: completed orders carrying a
--      non-null rating, newest first. Readable by ANY authenticated user.
--
-- NON-GOALS (separate phases, untouched here):
--   * NO column changes, NO RLS policy changes, NO grant changes on tables.
--   * NO Dart change here (repository + UI are a later batch).
--   * NO change to list_approved_professionals() (Phase 4C/4D).
--
-- DESIGN (mirrors Phase 4C/4D exactly):
--   * SECURITY DEFINER + STABLE + SET search_path = public, pg_temp (pinned:
--     pg_temp LAST, every reference schema-qualified, no dynamic SQL).
--   * Read-only projection: NO secret column is returned — only the review
--     payload a public pro profile already aggregates (client_name, rating,
--     review_comment, created_at). Client name falls back to 'Client' when the
--     order carried none, so the caller never leaks a null.
--   * The limit is clamped server-side: greatest(1, least(p_limit, 100)) — a
--     caller can never request 0 rows or an unbounded page.
--   * REVOKE ALL (public, anon, authenticated) first, then GRANT EXECUTE to
--     authenticated only — nobody gets this by default.
-- ============================================================================

drop function if exists public.list_pro_reviews(uuid);

create or replace function public.list_pro_reviews(
  p_pro_id uuid,
  p_limit  integer default 20
)
returns table (
  order_id       uuid,
  client_name    text,
  rating         numeric,
  review_comment text,
  created_at     timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    o.id                                as order_id,
    coalesce(o.client_name, 'Client')::text as client_name,
    o.rating,
    o.review_comment,
    o.created_at
  from public.orders o
  where o.pro_id = p_pro_id
    and o.status = 'completed'
    and o.rating is not null
  order by o.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;

comment on function public.list_pro_reviews(uuid, integer) is
  'Returns individual reviews for a given professional (completed orders '
  'with a non-null rating), newest first, limit clamped to [1,100]. '
  'Readable by any authenticated user. SECURITY DEFINER + STABLE, '
  'search_path pinned to public, pg_temp. Returns (order_id, client_name, '
  'rating, review_comment, created_at).';

-- Least-privilege EXECUTE (the only function grant in this file).
revoke all on function public.list_pro_reviews(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.list_pro_reviews(uuid, integer)
  to authenticated;

-- -- Read-only verification (run manually AFTER applying) ----------------------
-- select * from public.list_pro_reviews('0bf852a5-628c-4179-a4a8-05b39e1df67b');
--
-- select oid::regprocedure, p.provolatile, p.prosecdef, coalesce(p.proconfig, '{}')
--   from pg_proc p
--  where p.oid = 'public.list_pro_reviews(uuid,integer)'::regprocedure;
--  -- expected: vol = 's' (STABLE), secdef = true, search_path pinned
--
-- select proname, proacl from pg_proc where proname = 'list_pro_reviews';
--  -- expected: EXECUTE granted to authenticated only
-- ============================================================================
