-- 060_workout_log_exercises_realistic_bounds.sql
-- APK Test #15.1 / Bug E — add CHECK constraints to workout_log_exercises so
-- impossible per-set values can't reach cloud. Founder's account had 3
-- corrupt rows from May 7 with set_number=15 + reps=110-150 — bulk-completion
-- aggregates misinterpreted as per-set values. Those rows were cleaned via a
-- one-shot DELETE at fix time; this constraint prevents recurrence.
--
-- Bounds (per-set, weight_reps semantics):
--   reps:       0..60   (60 = extreme bodyweight high-rep cardio set)
--   set_number: 0..10   (10 = ultra-volume bodybuilding scheme)
--
-- Both NULL-tolerant (some logging_types don't populate either column).
--
-- Idempotent via IF NOT EXISTS guard. ALTER TABLE ADD CONSTRAINT throws if
-- the constraint already exists; the DO block makes it safe to re-run.
--
-- closes-diagnose: 2026-05-12-rep-validation-e6a2d4

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'wle_reps_realistic'
      AND conrelid = 'public.workout_log_exercises'::regclass
  ) THEN
    ALTER TABLE public.workout_log_exercises
      ADD CONSTRAINT wle_reps_realistic
      CHECK (reps IS NULL OR reps BETWEEN 0 AND 60);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'wle_set_number_realistic'
      AND conrelid = 'public.workout_log_exercises'::regclass
  ) THEN
    ALTER TABLE public.workout_log_exercises
      ADD CONSTRAINT wle_set_number_realistic
      CHECK (set_number IS NULL OR set_number BETWEEN 0 AND 10);
  END IF;
END
$$;

COMMENT ON CONSTRAINT wle_reps_realistic ON public.workout_log_exercises IS
  'Bug E / APK Test #15.1 — per-set reps must be in [0, 60]. Catches the '
  'bulk-completion-aggregate confusion that produced reps=110-150 in May 7 '
  'corruption.';

COMMENT ON CONSTRAINT wle_set_number_realistic ON public.workout_log_exercises IS
  'Bug E / APK Test #15.1 — set_number must be in [0, 10]. Catches the '
  'set_number=15 corruption from same May 7 incident.';
