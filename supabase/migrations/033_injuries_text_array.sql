-- 033: Migrate user_profile.injuries from `text` to `text[]`.
--
-- Bug (pre-2026-04-24): onboarding_provider synced the injuries List as
-- `profile['injuries']?.toString()`, producing the string "[none]".
-- The stringified value then overwrote the local Dart List on cross-
-- device restore, and the profile-completeness provider's `val is List`
-- check failed, flagging "Injuries" as missing indefinitely.
--
-- Fix:
--   1. (client) completeOnboarding now carries the List through to Hive
--      and the sync passes it as-is (supabase_flutter serialises to
--      text[] literal).
--   2. (server) convert the column to a proper text[] so round-trips
--      preserve the list.
--
-- Backfill covers four legacy shapes:
--   "['none']" / "[none]"   → split on comma + strip brackets/quotes
--   "[]"                    → ['none'] (default)
--   NULL / empty string     → ['none']
--   bare value (e.g. "knee") → ['knee']   (single-item array)

ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS injuries_new TEXT[];

-- Backfill from the legacy text column. Idempotent: re-running is safe
-- because injuries_new is rewritten from injuries on every run until the
-- old column is dropped.
UPDATE user_profile SET injuries_new =
  CASE
    WHEN injuries IS NULL OR injuries = '' OR injuries = '[]' THEN
      ARRAY['none']::TEXT[]
    WHEN injuries LIKE '[%]' THEN
      -- strip "[" and "]" and single-quotes + spaces, then split on ,
      string_to_array(
        regexp_replace(injuries, '^\[|\]$|''|"| ', '', 'g'),
        ','
      )
    ELSE ARRAY[injuries]::TEXT[]  -- bare single value stored as-is
  END
WHERE injuries_new IS NULL OR injuries_new = '{}'::TEXT[];

-- Swap columns atomically.
ALTER TABLE user_profile DROP COLUMN IF EXISTS injuries;
ALTER TABLE user_profile RENAME COLUMN injuries_new TO injuries;
ALTER TABLE user_profile
  ALTER COLUMN injuries SET DEFAULT ARRAY['none']::TEXT[];

COMMENT ON COLUMN user_profile.injuries IS
  'Array of body-part codes (none / knee / back / shoulder / hip / wrist / ankle). ["none"] = "no injuries" (valid answer, not absence of data).';
