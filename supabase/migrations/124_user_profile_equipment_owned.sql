-- Intent: Add user_profile.equipment_owned (text[]) so a user can tell us what kit they actually have beyond their tier's baseline — the ADD half of the OI-89 capability model, whose SUBTRACT half (equipment_exclusions) already shipped in migration 104.
-- Destructive?: no   -- single ADD COLUMN IF NOT EXISTS, NULLABLE, NO DEFAULT. No row is rewritten, no constraint changes, nothing is dropped.
-- Rollback strategy: inline   -- reverse DDL is at the end of this file
-- Linked diagnose-doc: 2026-08-28-equipment-library-restore-f7b2c4

-- ─────────────────────────────────────────────────────────────────────
-- ⑦ OI-89 — the equipment capability model.
--
-- The effective set a user can train with is:
--
--     EquipmentVocab.tierItems[tier] ∪ equipment_owned − equipment_exclusions
--
-- `equipment_exclusions` (migration 104, 2026-07-17) already carries the
-- SUBTRACT half: "I have a gym membership but I will not use the smith
-- machine." This column carries the ADD half: "I train at home with nothing,
-- but I do own a pull-up bar." Without it the bodyweight tier is a floor with
-- no ceiling — a user who owns one piece of kit has no way to say so, and the
-- hard capability floor would keep refusing them exercises they can do.
--
-- NULLABLE with NO DEFAULT, deliberately, matching equipment_exclusions:
--   * NULL and '{}' both mean "owns nothing extra" to every reader
--     (EquipmentVocab.fromProfile is crash-safe and returns [] for both), so a
--     DEFAULT would buy nothing and would rewrite every existing row.
--   * A NOT NULL default would also make the column indistinguishable from
--     "the user answered the question and said none", which the Profile UI
--     may later want to tell apart.
--
-- ⚠ DEPLOY ORDERING — this migration MUST be applied to prod BEFORE any client
-- that writes the field ships. `user_repository.dart:721-724` upserts a SPREAD
-- of the whole profile map and `_sanitize` (:818-836) does NOT whitelist
-- columns, so a client carrying `equipment_owned` against a database without it
-- gets a PostgREST 400 and the ENTIRE ROW is rejected — the all-null
-- user_profile failure documented at that file's :704-713. Applying early is
-- free (nothing reads the column yet); applying late breaks every profile sync.
-- ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.user_profile
  ADD COLUMN IF NOT EXISTS equipment_owned text[];

COMMENT ON COLUMN public.user_profile.equipment_owned IS
  'OI-89: canonical EquipmentVocab tokens the user owns BEYOND their equipment_access tier baseline. Widens the capability set; equipment_exclusions narrows it. NULL and {} are equivalent to every reader.';

-- ─────────────────────────────────────────────────────────────────────
-- Rollback (inline):
--
--   ALTER TABLE public.user_profile DROP COLUMN IF EXISTS equipment_owned;
--
-- Safe to run only while no shipped client writes the field. After the Profile
-- UI ships, dropping it would make every profile upsert carrying the key fail
-- with a PostgREST 400 — the same ordering hazard as applying it late, in
-- reverse. Prefer leaving the column in place and ignoring it.
-- ─────────────────────────────────────────────────────────────────────
