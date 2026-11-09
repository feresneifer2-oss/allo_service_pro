-- ============================================================================
-- Phase 8D — LIVE MEDIA: realtime publication + storage policies
-- (allo_service_pro) — APPLIED 2026-11-09 through the Supabase SQL Editor.
-- Verified after the run: 3 buckets (avatars public, chat-media public,
-- documents private), 5 storage policies, 4 realtime publication tables.
-- IDEMPOTENT: every statement is guarded, so a later `supabase db push` is a
-- no-op.
-- ============================================================================
-- WHAT THE 2026-11-09 DB AUDIT FOUND:
--   * storage.buckets: avatars (public), documents (private), **chat-media
--     MISSING** (the app uploads to a bucket that does not exist).
--   * pg_policies for storage.objects: **ZERO** → every client upload fails,
--     so a professional's proof stays on their phone and admin review is
--     blind. This is the single most damaging finding of the audit.
--   * public tables without RLS: none (good); `admins` has RLS with no policies
--     on purpose (is_admin() is SECURITY DEFINER) — leave it.
--   * supabase_realtime publication: pro_availability + professionals only.
--     `orders` and `messages` were NEVER published → no live order status, no
--     live chat delivery. Silent, because every screen also hydrates on boot.
--
-- IDEMPOTENT: every statement is guarded.
-- ============================================================================


-- ─── STEP 1 — REALTIME: publish orders + messages ───────────────────────────
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname='supabase_realtime' and schemaname='public'
                    and tablename='orders') then
    alter publication supabase_realtime add table public.orders;
  end if;

  if not exists (select 1 from pg_publication_tables
                  where pubname='supabase_realtime' and schemaname='public'
                    and tablename='messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;


-- ─── STEP 2 — STORAGE POLICIES (these are what make uploads work) ───────────
-- Ownership is the FIRST PATH SEGMENT: SupabaseStorageService writes
--   documents/<uid>/<kind>_<ts>.<ext>   and   avatars/<uid>/avatar_<ts>.<ext>
-- so `(storage.foldername(name))[1] = auth.uid()::text` is the exact owner test.

-- documents: the professional writes and reads ONLY their own folder.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='storage'
                  and tablename='objects' and policyname='documents_owner_insert') then
    create policy documents_owner_insert on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'documents'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  if not exists (select 1 from pg_policies where schemaname='storage'
                  and tablename='objects' and policyname='documents_owner_select') then
    create policy documents_owner_select on storage.objects
      for select to authenticated
      using (
        bucket_id = 'documents'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  -- the ADMIN must be able to open any dossier (signed URL = a SELECT).
  if not exists (select 1 from pg_policies where schemaname='storage'
                  and tablename='objects' and policyname='documents_admin_select') then
    create policy documents_admin_select on storage.objects
      for select to authenticated
      using (bucket_id = 'documents' and public.is_admin());
  end if;
end $$;

-- avatars: public READ (the bucket is public; AppImage renders the URL), but
-- the WRITE still needs a policy or the upload is refused.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='storage'
                  and tablename='objects' and policyname='avatars_owner_insert') then
    create policy avatars_owner_insert on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end $$;


-- ─── STEP 3 — chat-media BUCKET: CHOSEN = Option 1 (public) ─────────────────
-- The app uploads chat photos/voice notes to `chat-media/<requestId>/…` and
-- renders them with getPublicUrl. The bucket does not exist yet.
--
-- OPTION 2 (tracked follow-up) — PRIVATE bucket + signed URLs:
--   * uploads stay participant-scoped, reads require a signed URL;
--   * SupabaseStorageService.uploadChatMedia must stop returning getPublicUrl,
--     and the bubble widgets must resolve a signed URL before rendering.
--   Deferred on purpose: see the note on Option 1 below.

-- ── OPTION 1 (CHOSEN) — PUBLIC bucket + participant-only writes ────────────
-- Rationale for shipping this first: chat itself is not E2E-validated yet, and
-- the app renders chat media with getPublicUrl. Making the bucket private
-- BEFORE the signed-URL code exists would break the images even for the SENDER
-- (today the local path is the fallback) — a regression, not a hardening.
-- Tracked debt: migrate to a PRIVATE bucket + signed URLs in a dedicated phase,
-- once chat delivery has been proven on a device.
insert into storage.buckets (id, name, public)
  values ('chat-media', 'chat-media', true)
  on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='storage'
                  and tablename='objects' and policyname='chat_media_participant_insert') then
    create policy chat_media_participant_insert on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'chat-media'
        and exists (
          select 1 from public.orders o
           where o.id::text = (storage.foldername(name))[1]
             and (o.client_id = auth.uid() or o.pro_id = auth.uid()))
      );
  end if;
end $$;


-- ─── VERIFICATION (READ-ONLY, after applying) ──────────────────────────────
--   select tablename from pg_publication_tables
--    where pubname='supabase_realtime' order by tablename;
--   -- expected: messages, orders, pro_availability, professionals
--
--   select policyname, cmd from pg_policies
--    where schemaname='storage' and tablename='objects' order by policyname;
--   -- expected: avatars_owner_insert, documents_admin_select,
--   --           documents_owner_insert, documents_owner_select
--
-- FUNCTIONAL: as a professional, submit the registration wizard → the proof
-- must appear in the `documents` bucket under `<uid>/`; as the admin, open the
-- dossier → the signed URL must render.


-- ─── ROLLBACK ──────────────────────────────────────────────────────────────
--   drop policy if exists avatars_owner_insert     on storage.objects;
--   drop policy if exists documents_owner_insert   on storage.objects;
--   drop policy if exists documents_owner_select   on storage.objects;
--   drop policy if exists documents_admin_select   on storage.objects;
--   alter publication supabase_realtime drop table public.orders;
--   alter publication supabase_realtime drop table public.messages;
