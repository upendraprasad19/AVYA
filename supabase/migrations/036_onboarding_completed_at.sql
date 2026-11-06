-- supabase/migrations/036_onboarding_completed_at.sql
--
-- Adds an explicit `onboarding_completed_at` timestamp to user_profile so the
-- restore flow on relogin can decide between "send to home" and "send to
-- onboarding" without ambiguity.
--
-- Backfilled from existing rows where primary_goal IS NOT NULL (primary_goal
-- is captured in onboarding step 02 and never null afterward, so its presence
-- is a reliable proxy for "user finished onboarding at some point in the past").

ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;

UPDATE user_profile
  SET onboarding_completed_at = COALESCE(updated_at, created_at, now())
  WHERE primary_goal IS NOT NULL
    AND onboarding_completed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_profile_onboarding_completed
  ON user_profile (user_id, onboarding_completed_at);
