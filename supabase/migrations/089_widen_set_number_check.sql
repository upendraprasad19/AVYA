-- Intent: Widen wle_set_number_realistic + wls_set_number_realistic from <=10 to <=50. The <=10 bound is too tight — >10 sets per exercise is legitimate (drop sets, rest-pause, high-volume circuits), and the live data already holds a 15-set row (grandfathered because wls_set_number_realistic was NOT VALID). New >10-set workouts hit 23514 on the all-or-nothing per-set upsert and silently drop their per-set rows (which back the receipt / Train / weekly-report sums). Clamping set_number would corrupt the set index/count, so the bound is widened instead. 50 is generous; no realistic single-exercise session exceeds it.
-- Destructive?: no   -- DROP + re-ADD each CHECK with a WIDER bound; all existing rows (max set_number=15) satisfy <=50, so re-validation passes and no data is lost
-- Rollback strategy: inline   -- reverse DDL (re-add the <=10 bound) commented at file end
-- Linked diagnose-doc: a3e8f1

ALTER TABLE public.workout_log_exercises DROP CONSTRAINT IF EXISTS wle_set_number_realistic;
ALTER TABLE public.workout_log_exercises
  ADD CONSTRAINT wle_set_number_realistic
  CHECK ((set_number IS NULL) OR ((set_number >= 0) AND (set_number <= 50)));

ALTER TABLE public.workout_log_sets DROP CONSTRAINT IF EXISTS wls_set_number_realistic;
ALTER TABLE public.workout_log_sets
  ADD CONSTRAINT wls_set_number_realistic
  CHECK ((set_number IS NULL) OR ((set_number >= 0) AND (set_number <= 50)));

-- Rollback (inline):
-- ALTER TABLE public.workout_log_exercises DROP CONSTRAINT IF EXISTS wle_set_number_realistic;
-- ALTER TABLE public.workout_log_exercises ADD CONSTRAINT wle_set_number_realistic CHECK ((set_number IS NULL) OR ((set_number >= 0) AND (set_number <= 10)));
-- ALTER TABLE public.workout_log_sets DROP CONSTRAINT IF EXISTS wls_set_number_realistic;
-- ALTER TABLE public.workout_log_sets ADD CONSTRAINT wls_set_number_realistic CHECK ((set_number IS NULL) OR ((set_number >= 0) AND (set_number <= 10))) NOT VALID;
