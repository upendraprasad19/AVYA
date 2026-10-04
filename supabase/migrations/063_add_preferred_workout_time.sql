-- APK Test #15.4 / B2c — new profile column to capture muster Q4's
-- preferred_workout_time answer. Stored as "HH:MM" text matching the
-- existing wake_up_time column shape.
--
-- closes-diagnose: 8c4ee3
ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS preferred_workout_time TEXT;

COMMENT ON COLUMN user_profile.preferred_workout_time IS
  'User-stated preferred workout start time. Format "HH:MM" 24-hour. '
  'Captured by muster Q4 (post-onboarding). NULL = not yet collected.';
