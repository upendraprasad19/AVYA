-- Progress photos metadata (F19).
--
-- Today: progress photos are uploaded to Supabase Storage but no DB table
-- tracks them. URLs aren't indexed by user_id, so a new-device restore has
-- no way to list a user's photos. Effectively local-only despite being a
-- PRO feature.
--
-- This table holds the metadata (user_id + storage path + body area +
-- timestamp + weight snapshot). Actual image bytes stay in Storage;
-- restore fetches metadata rows then lazy-loads images as the user scrolls.
--
-- Plan reference: plan file Part 4 F19.

CREATE TABLE IF NOT EXISTS public.progress_photos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  storage_path    text NOT NULL,
    -- Full path within the progress-photos bucket,
    -- e.g. '<user_id>/2026-04-17_front.jpg'
  body_area       text,
    -- 'front' | 'side' | 'back' | custom label
  taken_at        timestamptz NOT NULL,
    -- When the user took the photo (may differ from upload time)
  weight_kg_at_time  numeric,
    -- Snapshot of current weight at the moment of capture (for comparisons)
  notes           text,
  created_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_progress_photos_user_taken
  ON public.progress_photos(user_id, taken_at DESC);

ALTER TABLE public.progress_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "progress_photos_select_own" ON public.progress_photos
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "progress_photos_insert_own" ON public.progress_photos
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "progress_photos_update_own" ON public.progress_photos
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "progress_photos_delete_own" ON public.progress_photos
  FOR DELETE USING (auth.uid() = user_id);
