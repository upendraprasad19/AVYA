-- Per-set workout data (F4).
--
-- Rationale: `workout_log_exercises` stores one row per (workout_log, exercise)
-- with `weight_kg = best across sets` and `reps = cumulative`. That loses
-- per-set granularity on restore — a user logging [80×10, 75×8, 70×6] sees
-- only "80 kg best" after logout/login.
--
-- This table adds per-set detail alongside the existing summary table. Summary
-- stays for AI features + analytics; this table powers per-set restore and
-- accurate volume math.
--
-- Plan reference: Part 4 F4 — docs/superpowers/plans/... and the plan file at
-- ~/.claude/plans/merry-sauteeing-tome.md.

CREATE TABLE IF NOT EXISTS public.workout_log_sets (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  workout_log_id    uuid NOT NULL,
    -- Deterministic UUID from the Hive log key; matches workout_logs.id.
    -- FK is intentionally omitted — workout_logs is also append-only
    -- but restore order may upsert logs and sets in interleaved passes.
  exercise_id       text NOT NULL,
    -- Exercise name used as stable identity (matches workout_log_exercises.exercise_id).
  set_number        int NOT NULL,
    -- 1-indexed position of this set within the exercise on that day.
  weight_kg         numeric,
  reps              int,
  duration_secs     int,
  distance_km       numeric,
  completed_at      timestamptz DEFAULT now(),
  created_at        timestamptz DEFAULT now()
);

-- Efficient lookups for the common queries:
--   restore per user since date: (user_id, completed_at DESC)
--   hydrate an exercise log: (workout_log_id, exercise_id, set_number)
CREATE INDEX IF NOT EXISTS idx_workout_log_sets_user_date
  ON public.workout_log_sets(user_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_workout_log_sets_log_exercise
  ON public.workout_log_sets(workout_log_id, exercise_id, set_number);

-- Same-set idempotency: a restore or re-sync must not create duplicate
-- rows. The (workout_log_id, exercise_id, set_number) triple is the
-- natural key.
CREATE UNIQUE INDEX IF NOT EXISTS ux_workout_log_sets_natural_key
  ON public.workout_log_sets(workout_log_id, exercise_id, set_number);

ALTER TABLE public.workout_log_sets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workout_log_sets_select_own" ON public.workout_log_sets
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "workout_log_sets_insert_own" ON public.workout_log_sets
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "workout_log_sets_update_own" ON public.workout_log_sets
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "workout_log_sets_delete_own" ON public.workout_log_sets
  FOR DELETE USING (auth.uid() = user_id);
