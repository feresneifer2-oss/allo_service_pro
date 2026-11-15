-- ============================================================================
-- Phase 8E — CHAT MEDIA PRIVATE: convert chat-media bucket to PRIVATE + signed URLs
-- (allo_service_pro)
-- ============================================================================
-- GOAL:
--   * Make the `chat-media` bucket PRIVATE (it was created PUBLIC in Phase 8D).
--   * Add a participant-scoped SELECT policy so both order participants can
--     read chat media via signed URLs.
--   * Upload INSERT policy (chat_media_participant_insert) stays as-is from
--     Phase 8D — participants can still upload.
--
-- DESIGN:
--   * chat-media/<requestId>/… → only readable by client_id or pro_id of that order.
--   * Reads require a signed URL (createSignedUrl) from the Flutter side.
--   * Idempotent: every statement is guarded, re-running is a no-op.
-- ============================================================================

-- ─── STEP 1 — Convert chat-media bucket to PRIVATE ───────────────────────────
update storage.buckets
set public = false
where id = 'chat-media';

-- ─── STEP 2 — Add participant-scoped SELECT policy ───────────────────────────
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'chat_media_participant_select'
  ) then
    create policy chat_media_participant_select on storage.objects
      for select to authenticated
      using (
        bucket_id = 'chat-media'
        and exists (
          select 1 from public.orders o
           where o.id::text = (storage.foldername(name))[1]
             and (o.client_id = auth.uid() or o.pro_id = auth.uid())
        )
      );
  end if;
end $$;

-- ─── VERIFICATION (READ-ONLY, run manually in SQL Editor after applying) -----
--   select id, name, public from storage.buckets where id = 'chat-media';
--   -- expected: chat-media | chat-media | false
--
--   select policyname, cmd from pg_policies
--    where schemaname='storage' and tablename='objects'
--     and bucket_id = 'chat-media'
--    order by policyname;
--   -- expected: chat_media_participant_insert / INSERT,
--   --           chat_media_participant_select / SELECT
-- ============================================================================