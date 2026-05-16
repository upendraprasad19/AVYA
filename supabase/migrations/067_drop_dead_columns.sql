-- Migration 067 — audit-2026-05-16 / E.12 — drop dead columns.
--
-- Audit Agent 3 (cluster 4 DB column-by-column) flagged 17 columns across
-- 7 column-groups as DEAD_SCHEMA_CANDIDATE: 100% NULL across all live rows
-- (live SQL verified 2026-05-16), zero writers in the codebase, zero readers.
--
-- Founder approved Phase D mass cleanup. CASCADE NOT NEEDED — these are all
-- nullable columns with no FK / index dependencies, only the tables'
-- regular default-NULL semantics.
--
-- Per `feedback_migration_apply_record_pair.md`: `backups/applied_migrations.json`
-- updated in same commit set.

BEGIN;

-- ── Group 2.1 — workout_logs legacy per-exercise columns ──
-- Post-Test-#6 these moved to `workout_log_exercises` + `workout_log_sets`.
-- No client writer projects them; cloud column was dead.
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS scheduled_workout_id;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS template_id;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS exercise_id;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS sets_completed;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS reps_completed;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS weight_kg;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS distance_km;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS rpe;

-- ── Group 2.2 — workout_templates metadata never collected via UI ──
ALTER TABLE public.workout_templates DROP COLUMN IF EXISTS description;
ALTER TABLE public.workout_templates DROP COLUMN IF EXISTS estimated_duration_mins;

-- ── Group 2.3 — template_exercises fields the builder UI doesn't surface ──
-- `exercise_id` was gated `if (isUuid)` projection (bundled exercises have
-- string IDs → always NULL). Drop the column.
ALTER TABLE public.template_exercises DROP COLUMN IF EXISTS exercise_id;
ALTER TABLE public.template_exercises DROP COLUMN IF EXISTS rest_seconds;
ALTER TABLE public.template_exercises DROP COLUMN IF EXISTS prescribed_weight;
ALTER TABLE public.template_exercises DROP COLUMN IF EXISTS prescribed_time_secs;
ALTER TABLE public.template_exercises DROP COLUMN IF EXISTS notes;

-- ── Group 2.4 — user_progress.experience_last_calculated (no writers) ──
ALTER TABLE public.user_progress DROP COLUMN IF EXISTS experience_last_calculated;

-- ── Group 2.5 — user_preferences.biggest_obstacle (no writers) ──
ALTER TABLE public.user_preferences DROP COLUMN IF EXISTS biggest_obstacle;

-- ── Group 2.6 — ai_coach_interactions.was_helpful (no thumbs-up UI) ──
ALTER TABLE public.ai_coach_interactions DROP COLUMN IF EXISTS was_helpful;

-- ── Group 2.7 — workout_log_exercises.notes (no per-exercise notes UI) ──
ALTER TABLE public.workout_log_exercises DROP COLUMN IF EXISTS notes;

-- Total dropped: 17 columns across 7 tables.

COMMIT;

-- Verification (read-only sanity check; should return 0 rows):
-- SELECT table_name, column_name FROM information_schema.columns
-- WHERE table_schema='public' AND column_name IN (
--   'scheduled_workout_id', 'template_id', 'sets_completed', 'reps_completed',
--   'weight_kg', 'distance_km', 'rpe', 'description',
--   'estimated_duration_mins', 'exercise_id', 'rest_seconds',
--   'prescribed_weight', 'prescribed_time_secs', 'notes',
--   'experience_last_calculated', 'biggest_obstacle', 'was_helpful')
-- AND table_name IN ('workout_logs', 'workout_templates',
--   'template_exercises', 'user_progress', 'user_preferences',
--   'ai_coach_interactions', 'workout_log_exercises');
