-- audit-2026-05-11 H-25/H-26/H-27/H-28 — schema completeness.
--
-- 4 constraints/indexes were missing on tables where the
-- application already treats the keyset as logically UNIQUE. The
-- gap meant cross-device sync race could produce duplicate rows
-- that double-counted in receipts, AI snapshot, and rate-limit
-- triggers. Adding the constraints + index closes the class.
--
-- Each ADD UNIQUE is preceded by a dedup CTE that deletes
-- duplicates keeping the latest row (by created_at / id desc).
-- If a row violates the new constraint, the migration fails loudly
-- BEFORE the constraint is added — the dedup makes that path
-- impossible.

-- ─────────────────────────────────────────────────────────────
-- H-25 — UNIQUE(user_id, lower(name)) on user_custom_exercises
--                                       user_custom_foods
-- ─────────────────────────────────────────────────────────────

WITH ranked_dup AS (
  SELECT
    id,
    user_id,
    LOWER(name) AS lname,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, LOWER(name)
      ORDER BY created_at DESC NULLS LAST, id DESC
    ) AS rn
  FROM public.user_custom_exercises
  WHERE user_id IS NOT NULL AND name IS NOT NULL
)
DELETE FROM public.user_custom_exercises
WHERE id IN (SELECT id FROM ranked_dup WHERE rn > 1);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_user_custom_exercises_user_name
  ON public.user_custom_exercises (user_id, LOWER(name))
  WHERE user_id IS NOT NULL AND name IS NOT NULL;

WITH ranked_dup AS (
  SELECT
    id,
    user_id,
    LOWER(name) AS lname,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, LOWER(name)
      ORDER BY created_at DESC NULLS LAST, id DESC
    ) AS rn
  FROM public.user_custom_foods
  WHERE user_id IS NOT NULL AND name IS NOT NULL
)
DELETE FROM public.user_custom_foods
WHERE id IN (SELECT id FROM ranked_dup WHERE rn > 1);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_user_custom_foods_user_name
  ON public.user_custom_foods (user_id, LOWER(name))
  WHERE user_id IS NOT NULL AND name IS NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- H-26 — index on ai_coach_interactions(user_id, channel, created_at)
--
-- The food-text rate-limit trigger COUNT(*)s rows for the user in a
-- specific channel within a time window. The existing
-- (user_id, created_at) index doesn't cover `channel` → trigger
-- does a heap scan per INSERT. As volume grows this becomes the
-- p99-latency culprit on the food-text path.
-- ─────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_ai_coach_user_channel_created
  ON public.ai_coach_interactions (user_id, channel, created_at);

-- ─────────────────────────────────────────────────────────────
-- H-27 — UNIQUE(user_id, date, meal_type) on nutrition_logs
--
-- App layer treats (user_id, date, meal_type) as a UNIQUE key per
-- the WriteService SoT contract. Cross-device sync race could
-- produce two rows; UI then renders both, double-counting macros.
-- ─────────────────────────────────────────────────────────────

WITH ranked_dup AS (
  SELECT
    id,
    user_id,
    date,
    meal_type,
    ROW_NUMBER() OVER (
      PARTITION BY user_id, date, meal_type
      ORDER BY created_at DESC NULLS LAST, id DESC
    ) AS rn
  FROM public.nutrition_logs
  WHERE user_id IS NOT NULL
    AND date IS NOT NULL
    AND meal_type IS NOT NULL
)
DELETE FROM public.nutrition_logs
WHERE id IN (SELECT id FROM ranked_dup WHERE rn > 1);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_nutrition_logs_user_date_meal
  ON public.nutrition_logs (user_id, date, meal_type)
  WHERE user_id IS NOT NULL
    AND date IS NOT NULL
    AND meal_type IS NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- H-28 — UNIQUE(workout_log_id, exercise_id, set_number) on
--        workout_log_exercises
--
-- Per CLAUDE.md §11 "Exercise Log Cloud Contract" each
-- (workout_log_id, exercise_id, set_number) tuple is UNIQUE by
-- intent. Pre-fix only the PK constraint existed; concurrent sync
-- pushes from two devices could produce duplicates.
-- ─────────────────────────────────────────────────────────────

WITH ranked_dup AS (
  SELECT
    id,
    workout_log_id,
    exercise_id,
    set_number,
    ROW_NUMBER() OVER (
      PARTITION BY workout_log_id, exercise_id, set_number
      ORDER BY completed_at DESC NULLS LAST, id DESC
    ) AS rn
  FROM public.workout_log_exercises
  WHERE workout_log_id IS NOT NULL
    AND exercise_id IS NOT NULL
    AND set_number IS NOT NULL
)
DELETE FROM public.workout_log_exercises
WHERE id IN (SELECT id FROM ranked_dup WHERE rn > 1);

CREATE UNIQUE INDEX IF NOT EXISTS uniq_workout_log_exercises_wlog_ex_set
  ON public.workout_log_exercises (workout_log_id, exercise_id, set_number)
  WHERE workout_log_id IS NOT NULL
    AND exercise_id IS NOT NULL
    AND set_number IS NOT NULL;

COMMENT ON INDEX public.uniq_user_custom_exercises_user_name IS
  'audit-2026-05-11 H-25 — enforces UNIQUE(user_id, lower(name)) to prevent cross-device sync duplicates.';
COMMENT ON INDEX public.uniq_user_custom_foods_user_name IS
  'audit-2026-05-11 H-25 — enforces UNIQUE(user_id, lower(name)) to prevent cross-device sync duplicates.';
COMMENT ON INDEX public.idx_ai_coach_user_channel_created IS
  'audit-2026-05-11 H-26 — supports the food-text rate-limit trigger COUNT(*) probe.';
COMMENT ON INDEX public.uniq_nutrition_logs_user_date_meal IS
  'audit-2026-05-11 H-27 — UNIQUE(user_id, date, meal_type) per WriteService SoT.';
COMMENT ON INDEX public.uniq_workout_log_exercises_wlog_ex_set IS
  'audit-2026-05-11 H-28 — UNIQUE(workout_log_id, exercise_id, set_number) per CLAUDE.md §11.';
