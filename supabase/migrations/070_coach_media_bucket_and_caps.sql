-- Migration 070 — Storage hardening (OI-23 + OI-24, 2026-05-17).
--
-- ── OI-23 ─────────────────────────────────────────────────────────────
-- Create `coach-media` Storage bucket. Founder decided 2026-05-17:
-- "i intend to store coach uploaded media. We ask user does he want to
-- store the pic for future reference and on consent we save it."
--
-- Flow design (client-side, to be implemented in a follow-up batch):
--   1. User uploads photo to AI coach → lands in `chat-media/<uid>/...`
--      (transient bucket; 30-day cleanup via clean-orphan-media for
--      free users).
--   2. After AI analysis returns, app prompts: "Save this photo for
--      future reference?"
--   3. On consent → app copies blob from chat-media into
--      `coach-media/<uid>/...` (long-term retention).
--   4. `delete-account` Edge Function purges both buckets on hard
--      delete (docs/architecture/payment.md already lists coach-media in the purge
--      list — it was a pending bucket reference until now).
--
-- ── OI-24 ─────────────────────────────────────────────────────────────
-- Add bucket-level file_size_limit + allowed_mime_types to the four
-- existing private/public buckets that lack them. Defense-in-depth
-- alongside the client-side caps documented in docs/architecture/subscription.md:
--   - avatars:           1 MB, image/jpeg + image/png + image/webp
--   - banners:           2 MB, image/jpeg + image/png + image/webp
--   - progress-photos:   8 MB, image/jpeg + image/png + image/webp
--   - chat-media: already 2 MiB cap — extend to match (5 MB) to align
--     with ai-media-proxy server-side MAX_IMAGE_BYTES.
--
-- A compromised or rooted client cannot bypass these — Storage REST API
-- enforces them at the gateway.

-- ── A. Create coach-media bucket (OI-23) ──────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'coach-media',
  'coach-media',
  false,                              -- private; auth required
  5242880,                            -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
SET file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types,
    public = EXCLUDED.public;

-- Owner-only policies — mirrors progress_photos shape (path layout
-- `<user_id>/<filename>`; pinned by `test/contracts/chat_media_signed_url_test.dart`
-- + `test/contracts/ai_media_proxy_user_scope_test.dart` (retired root §19
-- entry #21, Class A per the 2026-05-18 declutter audit).

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'coach_media_select_own'
  ) THEN
    DROP POLICY "coach_media_select_own" ON storage.objects;
  END IF;
END $$;

CREATE POLICY "coach_media_select_own"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'coach-media' AND (storage.foldername(name))[1] = (auth.uid())::text);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'coach_media_insert_own'
  ) THEN
    DROP POLICY "coach_media_insert_own" ON storage.objects;
  END IF;
END $$;

CREATE POLICY "coach_media_insert_own"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'coach-media' AND (storage.foldername(name))[1] = (auth.uid())::text);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'coach_media_delete_own'
  ) THEN
    DROP POLICY "coach_media_delete_own" ON storage.objects;
  END IF;
END $$;

CREATE POLICY "coach_media_delete_own"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'coach-media' AND (storage.foldername(name))[1] = (auth.uid())::text);

-- ── B. Bucket-level size + MIME caps for existing buckets (OI-24) ────
UPDATE storage.buckets
SET file_size_limit = 1048576,         -- 1 MB
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'avatars';

UPDATE storage.buckets
SET file_size_limit = 2097152,         -- 2 MB
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'banners';

UPDATE storage.buckets
SET file_size_limit = 8388608,         -- 8 MB (PRO progress photos go up to 3000×3000 95%)
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'progress-photos';

UPDATE storage.buckets
SET file_size_limit = 5242880,         -- 5 MB (matches ai-media-proxy MAX_IMAGE_BYTES)
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'chat-media';

COMMENT ON COLUMN storage.buckets.file_size_limit IS
  'OI-24 hardening (2026-05-17): all 4 existing buckets capped. '
  'avatars=1MB, banners=2MB, progress-photos=8MB, chat-media=5MB. '
  'Defense-in-depth against rooted clients bypassing client-side caps.';
