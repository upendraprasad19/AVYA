-- Intent: Correct exercise_library E260 Incline Dumbbell Press — its first coaching cue says "Set bench to 30-45 degree incline" unconditionally, yet equipment_needed claimed only dumbbells, so it was offered to home_dumbbells users who have no bench.
-- Destructive?: no   -- single-row UPDATE of one array column; no schema change, no deletion.
-- Rollback strategy: inline   -- reverse UPDATE is at the end of this file
-- Linked diagnose-doc: 2026-08-28-equipment-library-restore-f7b2c4

-- ─────────────────────────────────────────────────────────────────────
-- ⑦ OI-89, B-pass finding 2.
--
-- Migration 125 re-seeded this table from the bundled asset minutes before this
-- one, and 125 is APPLIED and therefore immutable — so this is a new number
-- rather than an edit to it (the OI-135 ledger-hash drift class).
--
-- Found by running check_equipment_audit.dart with --all-tiers. Its default was
-- BODYWEIGHT-TIER ONLY, and that scope was the blind spot: a row over-tagged in
-- `equipment_needed` rather than in `equipment_tier` is not bodyweight-tier to
-- begin with, so the narrow scan could never reach it. E260 was the one real
-- defect among 18 gym-tier findings (the other 17 are comparison prose —
-- "superior to dumbbell", "without a barbell" — now recorded with reasons in
-- equipment_audit_lib.dart's acceptedMentions). The gate's default is all-tiers
-- as of the same commit, so the next one cannot hide the same way.
--
-- Keyed on `name`, not the deterministic UUID, so this reads correctly against
-- the row a human would look up. The name is unique in this table.
-- ─────────────────────────────────────────────────────────────────────

UPDATE public.exercise_library
   SET equipment_needed = ARRAY['dumbbells','bench']::text[]
 WHERE name = 'Incline Dumbbell Press'
   AND equipment_needed = ARRAY['dumbbells']::text[];

-- ─────────────────────────────────────────────────────────────────────
-- Rollback (inline):
--
--   UPDATE public.exercise_library
--      SET equipment_needed = ARRAY['dumbbells']::text[]
--    WHERE name = 'Incline Dumbbell Press';
--
-- Reverting re-opens the defect: home_dumbbells users would again be offered an
-- incline press with nothing to incline on.
-- ─────────────────────────────────────────────────────────────────────
