-- supabase/migrations/048_restore_completeness.sql
-- Restore-completeness schema additions for APK Test #11 Theme A.
-- All additive: 3 new columns on user_progress + 2 new tables.
-- No data deletion, no constraint tightening, no FK changes.
--
-- NOTE: Filename is 048_ because 047_clean_orphan_media_cron.sql already
-- exists in this worktree (applied to prod as 'clean_orphan_media_cron').
-- The migration name passed to apply_migration is '047_restore_completeness'
-- as specified in the task (MCP tracks by name, not filename number).

-- =========================================================================
-- Theme A1 — streak freezes columns on user_progress
-- =========================================================================

ALTER TABLE public.user_progress
  ADD COLUMN IF NOT EXISTS streak_freezes_available INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS streak_freezes_used_dates TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS streak_freezes_last_refill DATE;

COMMENT ON COLUMN public.user_progress.streak_freezes_available IS
  'Number of streak-protection freezes available. Synced to Hive on restore.';
COMMENT ON COLUMN public.user_progress.streak_freezes_used_dates IS
  'Array of YYYY-MM-DD strings (IST) for dates the user has consumed a freeze.';
COMMENT ON COLUMN public.user_progress.streak_freezes_last_refill IS
  'Last date a refill grant was issued. NULL means never refilled (initial state).';

-- =========================================================================
-- Theme A4 — notifications inbox table
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.notifications_inbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notif_type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ,
  archived_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notifications_inbox_user_created
  ON public.notifications_inbox(user_id, created_at DESC);

ALTER TABLE public.notifications_inbox ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'notifications_inbox' AND policyname = 'Users see own notifications'
  ) THEN
    CREATE POLICY "Users see own notifications"
      ON public.notifications_inbox FOR SELECT USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'notifications_inbox' AND policyname = 'Users update own notifications'
  ) THEN
    CREATE POLICY "Users update own notifications"
      ON public.notifications_inbox FOR UPDATE USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'notifications_inbox' AND policyname = 'Users insert own notifications'
  ) THEN
    CREATE POLICY "Users insert own notifications"
      ON public.notifications_inbox FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

COMMENT ON TABLE public.notifications_inbox IS
  'Per-user notification history. Hive-mirrored. Restored on cross-device sign-in.';

-- =========================================================================
-- Theme A5 — saved diet plans table
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.saved_diet_plans (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_json JSONB NOT NULL,
  saved_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.saved_diet_plans ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'saved_diet_plans' AND policyname = 'Users see own diet plan'
  ) THEN
    CREATE POLICY "Users see own diet plan"
      ON public.saved_diet_plans FOR SELECT USING (auth.uid() = user_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'saved_diet_plans' AND policyname = 'Users upsert own diet plan'
  ) THEN
    CREATE POLICY "Users upsert own diet plan"
      ON public.saved_diet_plans FOR ALL USING (auth.uid() = user_id);
  END IF;
END $$;

COMMENT ON TABLE public.saved_diet_plans IS
  'User-saved diet plan map (slot -> planned slot). Hive-mirrored. One row per user.';
