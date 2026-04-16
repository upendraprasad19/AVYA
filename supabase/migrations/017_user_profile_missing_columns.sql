-- Add profile fields that exist in the Flutter app but have no Supabase column.
-- All nullable so existing rows are unaffected; new syncs populate them.
--
-- Why: the Hive profile captures lifestyle_activity, session_duration_minutes,
-- physique_focus (set via onboarding + Edit Profile), body_fat_percent and
-- body_fat_assessed_at (set via AI body-composition assessment), but these
-- were not mirrored in user_profile. Prior syncs silently dropped them.

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS lifestyle_activity        text,
  ADD COLUMN IF NOT EXISTS session_duration_minutes  int,
  ADD COLUMN IF NOT EXISTS physique_focus            text,
  ADD COLUMN IF NOT EXISTS body_fat_percent          numeric,
  ADD COLUMN IF NOT EXISTS body_fat_assessed_at      timestamptz;

COMMENT ON COLUMN public.user_profile.lifestyle_activity IS
  'Daily activity level outside the gym (desk_job, active_job, physical_job, retired, student). Written by onboarding.';
COMMENT ON COLUMN public.user_profile.session_duration_minutes IS
  'Preferred workout duration in minutes (30/45/60). Set via Edit Profile. NOTE: post-V4 the plan generator no longer reads this; retained for user preference display and future re-use.';
COMMENT ON COLUMN public.user_profile.physique_focus IS
  'Workout bias (balanced, chest, back, legs, shoulders, arms, core). Set via Edit Profile.';
COMMENT ON COLUMN public.user_profile.body_fat_percent IS
  'Estimated body fat % from AI body-composition assessment. Feeds Katch-McArdle BMR when present.';
COMMENT ON COLUMN public.user_profile.body_fat_assessed_at IS
  'Timestamp of the most recent body-composition assessment.';
