-- Migration 068 — drift-fix batch (2026-05-24)
-- Source spec: docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md
-- Preflight:   docs/audit/2026-05-24-drift-fix-preflight.md
--
-- F4 workout:   rename workout_logs.exercise_name → workout_name
-- F4 nutrition: add nutrition_log_items.fiber
--
-- The workout uniqueness on (user_id, date, exercise_name) is enforced
-- by a stand-alone UNIQUE INDEX (`uniq_workout_logs_user_date_name`),
-- NOT a table constraint — confirmed via live pg_constraint + pg_indexes
-- query in preflight. Migration drops the index, renames the column,
-- recreates a new index targeting the renamed column.

BEGIN;

-- ============================================================================
-- F4 workout — rename column via DROP INDEX → RENAME COLUMN → CREATE INDEX
-- ============================================================================

DROP INDEX IF EXISTS public.uniq_workout_logs_user_date_name;

ALTER TABLE public.workout_logs RENAME COLUMN exercise_name TO workout_name;

CREATE UNIQUE INDEX uniq_workout_logs_user_date_workout_name
  ON public.workout_logs (user_id, date, workout_name);

COMMENT ON COLUMN public.workout_logs.workout_name IS
  'Workout session name (e.g. "Push A"). Renamed from exercise_name 2026-05-24 (drift-fix F4) — the value was always a session label, never a per-exercise identifier. Per-exercise data lives in workout_log_exercises.';

-- ============================================================================
-- F4 nutrition — add fiber column (additive only; legacy rows default 0)
-- ============================================================================

ALTER TABLE public.nutrition_log_items
  ADD COLUMN IF NOT EXISTS fiber NUMERIC DEFAULT 0;

COMMENT ON COLUMN public.nutrition_log_items.fiber IS
  'Per-item fiber (g). Populated by NutritionWriteService→sync_nutrition projection (added 2026-05-24 drift-fix F4). Legacy rows default 0 — no backfill source (no fiber column existed pre-migration).';

COMMIT;
