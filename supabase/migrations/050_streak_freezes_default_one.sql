-- 050_streak_freezes_default_one.sql
-- APK Test #14 — cloud default for streak_freezes_available was 2 (legacy
-- conservative middle-ground from migration 048). Per founder direction
-- 2026-05-10, free baseline is 1 and PRO clients overwrite to 3 within
-- seconds of first launch via _refillIfNewWeek. Change default to 1 so a
-- fresh user_progress row matches free-tier baseline; PRO users still
-- ladder up correctly because the client refill path is authoritative.
--
-- Idempotent. Existing rows keep their current values; ALTER COLUMN SET
-- DEFAULT only affects NEW INSERTs.
--
-- closes-diagnose: 2026-05-10-cloud-default-d4e5f6

ALTER TABLE public.user_progress
  ALTER COLUMN streak_freezes_available SET DEFAULT 1;

COMMENT ON COLUMN public.user_progress.streak_freezes_available IS
  'Streak freezes available (APK Test #14). Default 1 (free baseline). '
  'PRO clients overwrite to 3 on first refill via _refillIfNewWeek '
  'ladder semantics (+1/week, capped at max).';
