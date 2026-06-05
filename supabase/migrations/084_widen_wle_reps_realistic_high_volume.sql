-- Intent: Widen workout_log_exercises.wle_reps_realistic from <=1000 to <=10000 to fit very-high-volume CUMULATIVE reps. Paired with a client clamp+telemetry guard so out-of-range values are captured, never silently dropped (23514).
-- Destructive?: no   -- widens an existing CHECK; no rows rewritten, no data loss. Previously-rejected high-volume summary rows can now sync.
-- Rollback strategy: inline   -- reverse DDL (restore the <=1000 cap) commented at file end.
-- Linked diagnose-doc: e7b3c9
--
-- 084_widen_wle_reps_realistic_high_volume.sql
--
-- Diagnose: 2026-06-05-workout-log-reps-silent-drop (e7b3c9)
-- Blast radius: account (every user's high-volume workout summary rows).
--
-- BUG (live, founder's account d7a67a37, 78x over 4 days): workout_log_exercises
-- SUMMARY rows with reps > 1000 are rejected by wle_reps_realistic (23514) and
-- the sync catch swallows it -> the summary row (read by AI features, weekly
-- report, analytics) silently never reaches cloud. Two vectors fed reps > 1000:
--   (a) the canonical writer stores reps_completed = SUM(set.reps) — a CUMULATIVE
--       total (WorkoutWriteService.logExercise:134). Migration 080 widened the
--       cap 60 -> 1000 assuming ~600 max, but real high-volume sessions exceed it.
--   (b) logging_type_repair_migrator moved duration_seconds INTO reps (seconds,
--       e.g. a 1200s hold, stamped as a rep count). Fixed client-side in this
--       batch (the migrator now strips phantom duration, never moves it to reps).
--
-- FIX: widen the cumulative cap to 10000 (a 1-hour bodyweight session tops out
-- well under this; 6-figure values are still rejected as garbage). The client
-- now ALSO clamps reps to [0, 10000] and logs op_type wle_reps_out_of_range, so
-- any future out-of-range value is captured + visible instead of silently lost.
-- Per-set realism stays enforced on workout_log_sets (wls_reps_realistic).

ALTER TABLE public.workout_log_exercises DROP CONSTRAINT IF EXISTS wle_reps_realistic;
ALTER TABLE public.workout_log_exercises
  ADD CONSTRAINT wle_reps_realistic CHECK (reps IS NULL OR (reps >= 0 AND reps <= 10000));

COMMENT ON CONSTRAINT wle_reps_realistic ON public.workout_log_exercises IS
  'reps is the CUMULATIVE per-exercise total (sum of set reps); bound [0,10000] '
  '(migration 084, diagnose e7b3c9). Per-set realism is on workout_log_sets.';

-- Rollback (inline — restores the migration 080 cap):
-- ALTER TABLE public.workout_log_exercises DROP CONSTRAINT IF EXISTS wle_reps_realistic;
-- ALTER TABLE public.workout_log_exercises
--   ADD CONSTRAINT wle_reps_realistic CHECK (reps IS NULL OR (reps >= 0 AND reps <= 1000));
