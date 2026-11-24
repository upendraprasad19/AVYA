-- Intent: Add user_profile.units_system and user_profile.measurement_unit so the units setting and the measurement sheet's cm/in sync per user across devices.
-- Destructive?: no   -- adds two nullable columns with CHECK constraints; no existing row, column or constraint changes.
-- Rollback strategy: inline   -- ALTER TABLE public.user_profile DROP COLUMN units_system, DROP COLUMN measurement_unit; (see the end of this file).
-- Linked diagnose-doc: e9a6c1
--
-- 185_user_profile_unit_prefs.sql
--
-- Diagnose: 2026-11-23-unit-preference-not-synced (e9a6c1), OI-348 walk B9.
--
-- BUG: the Profile Units switch lived in the shared device box
-- (configBox['units_metric']) and the measurement sheet's cm/in in a per-user
-- Hive key; neither was ever pushed, so a second device of the same account
-- showed its own default, and two accounts on one device shared one switch.
--
-- FIX: both become profile fields, pushed by the profile push
-- (sync_profile.dart, `unitPrefsPushEntries`) and restored by the existing
-- `_restoreUserProfile` merge (cloud non-null wins, cloud null never wipes).
-- The client normalises both values before a push (`unit_prefs_rule.dart`), so
-- the CHECKs only ever refuse a hand-written value. NULL = never set (readers
-- default to metric / cm).
--
-- Applied BEFORE the client that pushes these keys ships: an older server
-- would refuse the whole profile upsert with an unknown column.

BEGIN;

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS units_system text
    CONSTRAINT user_profile_units_system_check
    CHECK (units_system IN ('metric', 'imperial')),
  ADD COLUMN IF NOT EXISTS measurement_unit text
    CONSTRAINT user_profile_measurement_unit_check
    CHECK (measurement_unit IN ('cm', 'in'));

COMMENT ON COLUMN public.user_profile.units_system IS
  'OI-348 B9: the user''s units setting, ''metric'' or ''imperial''; NULL = never set (metric). Written by the app''s profile push.';
COMMENT ON COLUMN public.user_profile.measurement_unit IS
  'OI-348 B9: the body-measurements sheet''s last-used unit, ''cm'' or ''in''; NULL = never set. Written by the app''s profile push.';

COMMIT;

-- Inline rollback (run by hand only after the client that pushes these keys
-- is withdrawn, or the profile push will fail on the unknown columns):
-- BEGIN;
-- ALTER TABLE public.user_profile
--   DROP COLUMN IF EXISTS units_system,
--   DROP COLUMN IF EXISTS measurement_unit;
-- COMMIT;
