-- 064_fix_partial_unique_arbiter.sql
--
-- 2026-05-15 — close PostgREST 42P10 "no unique or exclusion constraint
-- matching the ON CONFLICT specification" trap on 3 tables.
--
-- Root cause: client `upsert(..., onConflict: '<natural_key_cols>')` translates
-- to `ON CONFLICT (<cols>) DO UPDATE`. PostgreSQL's arbiter resolver requires
-- a UNIQUE index whose definition exactly matches the inferred columns. The
-- 3 existing partial indexes carry `WHERE (col IS NOT NULL AND ...)`
-- predicates which the planner can NOT prove from the table schema (all 4
-- columns below are NULLABLE in prod). The arbiter therefore rejects the
-- partial index and raises 42P10 even though the (user_id, date, ...) tuple
-- the client sent is non-null. Symptom: 47 client_errors rows for one user
-- in a 60-second window on 2026-05-15 04:10 UTC.
--
-- Fix: backfill the (already-empty) NULL columns, ALTER COLUMN ... SET NOT
-- NULL so the schema asserts what the writer has always assumed, then
-- replace each partial UNIQUE index with the equivalent non-partial UNIQUE
-- index (same columns, same name, no WHERE clause). With NOT NULL columns
-- + plain UNIQUE, PostgREST's arbiter resolves cleanly on every upsert.
--
-- Pre-flight verification 2026-05-15 (Supabase MCP execute_sql):
--   V1: workout_logs.date IS NULL            → 0 rows
--   V2: workout_logs.exercise_name IS NULL   → 0 rows
--   V3: workout_log_exercises.workout_log_id IS NULL → 0 rows
--   V4: nutrition_logs.meal_type IS NULL     → 0 rows
-- Backfill is a defensive no-op safety net for any rows that may slip in
-- between pre-flight + migration apply. The fallback values match writer
-- contracts:
--   workout_logs.date           → logged_at::date  (writer always derives
--                                   from logged_at — see WorkoutWriteService
--                                   _writeCloudWorkoutLog projection).
--   workout_logs.exercise_name  → 'unknown'        (last-resort sentinel;
--                                   no real row should ever hit this).
--   workout_log_exercises.workout_log_id → 'wlog_' || extract(epoch from
--                                   created_at)::bigint::text  (mirrors
--                                   `wlogKey(date)` shape used by writer).
--   nutrition_logs.meal_type    → 'snack'          (matches client default
--                                   in NutritionWriteService when caller
--                                   omits meal_type).
--
-- closes-diagnose: 76c8f4

-- ---------------------------------------------------------------------------
-- Step 1: Backfill NULL columns (defensive no-op given pre-flight counts).
-- ---------------------------------------------------------------------------

UPDATE public.workout_logs
   SET date = logged_at::date
 WHERE date IS NULL
   AND logged_at IS NOT NULL;

-- If both date AND logged_at were null (shouldn't exist), stamp today so the
-- NOT NULL assertion below succeeds.
UPDATE public.workout_logs
   SET date = CURRENT_DATE
 WHERE date IS NULL;

UPDATE public.workout_logs
   SET exercise_name = 'unknown'
 WHERE exercise_name IS NULL;

UPDATE public.workout_log_exercises
   SET workout_log_id =
       'wlog_' || extract(epoch from COALESCE(created_at, now()))::bigint::text
 WHERE workout_log_id IS NULL;

UPDATE public.nutrition_logs
   SET meal_type = 'snack'
 WHERE meal_type IS NULL;

-- ---------------------------------------------------------------------------
-- Step 2: ALTER COLUMN ... SET NOT NULL on all 4 columns.
-- ---------------------------------------------------------------------------

ALTER TABLE public.workout_logs
  ALTER COLUMN date          SET NOT NULL,
  ALTER COLUMN exercise_name SET NOT NULL;

ALTER TABLE public.workout_log_exercises
  ALTER COLUMN workout_log_id SET NOT NULL;

ALTER TABLE public.nutrition_logs
  ALTER COLUMN meal_type SET NOT NULL;

-- ---------------------------------------------------------------------------
-- Step 3: Drop the 3 partial UNIQUE indexes and replace with non-partial.
-- ---------------------------------------------------------------------------

DROP INDEX IF EXISTS public.uniq_workout_logs_user_date_name;
DROP INDEX IF EXISTS public.uniq_workout_log_exercises_wlog_ex_set;
DROP INDEX IF EXISTS public.uniq_nutrition_logs_user_date_meal;

CREATE UNIQUE INDEX uniq_workout_logs_user_date_name
  ON public.workout_logs (user_id, date, exercise_name);

CREATE UNIQUE INDEX uniq_workout_log_exercises_wlog_ex_set
  ON public.workout_log_exercises (workout_log_id, exercise_id, set_number);

CREATE UNIQUE INDEX uniq_nutrition_logs_user_date_meal
  ON public.nutrition_logs (user_id, date, meal_type);

-- ---------------------------------------------------------------------------
-- Step 4: COMMENT each new index referencing the diagnose-doc.
-- ---------------------------------------------------------------------------

COMMENT ON INDEX public.uniq_workout_logs_user_date_name IS
  '2026-05-15 (closes-diagnose: 76c8f4) — non-partial UNIQUE so PostgREST '
  'ON CONFLICT (user_id, date, exercise_name) arbiter resolves. Replaces '
  'partial index whose WHERE (... IS NOT NULL) predicate triggered 42P10.';

COMMENT ON INDEX public.uniq_workout_log_exercises_wlog_ex_set IS
  '2026-05-15 (closes-diagnose: 76c8f4) — non-partial UNIQUE so PostgREST '
  'ON CONFLICT (workout_log_id, exercise_id, set_number) arbiter resolves. '
  'Replaces partial index whose WHERE (... IS NOT NULL) predicate '
  'triggered 42P10.';

COMMENT ON INDEX public.uniq_nutrition_logs_user_date_meal IS
  '2026-05-15 (closes-diagnose: 76c8f4) — non-partial UNIQUE so PostgREST '
  'ON CONFLICT (user_id, date, meal_type) arbiter resolves. Replaces '
  'partial index whose WHERE (... IS NOT NULL) predicate triggered 42P10.';
