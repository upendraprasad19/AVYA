-- Intent: Add a DELETE-own RLS policy for authenticated users on the chat-media
--   bucket. Live-verified 2026-07-30 (round-2 review, coach-media-consent /
--   OI-25 batch) that chat-media has only 3 policies today — "Service role
--   can read all chat media" (SELECT, service_role), "Users can read own chat
--   media" (SELECT, authenticated, own-only), "Users can upload own chat media"
--   (INSERT, authenticated, own-only) — and NO authenticated-DELETE policy at
--   all. This batch's CoachMediaRepository.saveForLater is the first client
--   code to ever call .remove() against chat-media (to clean up the transient
--   source immediately after a free-tier user consents to a long-term copy,
--   rather than waiting up to 30 days for the clean-orphan-media cron); every
--   such call has been silently RLS-denied, caught, and swallowed to a
--   debugPrint since there was no policy permitting it. Mirrors the shape of
--   coach_media_delete_own (migration 070) exactly, scoped to chat-media.
-- Destructive?: no -- adds a new grant; does not touch existing policies,
--   buckets, or rows. Strictly widens what an owner can already do to their
--   own objects (they can already SELECT + INSERT their own chat-media path).
-- Rollback strategy: inline -- see commented DROP POLICY at end of file
-- Linked diagnose-doc: docs/diagnoses/2026-07-30-coach-media-consent-f4a7c2.md

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'chat_media_delete_own'
  ) THEN
    DROP POLICY "chat_media_delete_own" ON storage.objects;
  END IF;
END $$;

CREATE POLICY "chat_media_delete_own"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'chat-media' AND (storage.foldername(name))[1] = (auth.uid())::text);

-- Rollback (inline, commented):
-- DROP POLICY "chat_media_delete_own" ON storage.objects;
