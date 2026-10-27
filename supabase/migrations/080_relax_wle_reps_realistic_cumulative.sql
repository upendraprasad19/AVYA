-- Intent: Relax workout_log_exercises.wle_reps_realistic to allow CUMULATIVE (summed-across-sets) reps. The client writer (WorkoutWriteService.logExercise) sets reps_completed = Σ set.reps and syncs it into workout_log_exercises.reps, but the old CHECK capped reps at 60 (a per-SET bound). Any exercise whose total reps > 60 (e.g. 5×15=75, 3×25 bodyweight) failed the constraint with 23514 and the summary row silently failed to sync (the catch swallowed it). Per-set realism remains enforced on workout_log_sets.
-- Destructive?: no   -- widens an existing CHECK; no rows rewritten, no data loss. Previously-rejected summary rows can now sync.
-- Rollback strategy: inline   -- reverse DDL (restore the 0..60 cap) commented at file end.
-- Linked diagnose-doc: 7d3f0a
--
-- 080_relax_wle_reps_realistic_cumulative.sql
--
-- Diagnose: 2026-05-31-workout-log-exercises-cumulative-reps-constraint (7d3f0a)
-- Blast radius: account (every user's workout summary rows for high-volume exercises).
--
-- BUG (surfaced by the 2026-05-31 year-simulation harness): the cloud CHECK
--   wle_reps_realistic = (reps IS NULL OR (reps >= 0 AND reps <= 60))
-- assumes `reps` is a PER-SET value, but the canonical writer stores a
-- CUMULATIVE total: WorkoutWriteService.logExercise:134
--   final totalReps = mergedSets.fold<int>(0, (a, s) => a + s.reps);
-- → entry 'reps_completed' = totalReps → sync_workout.dart:252
--   workout_log_exercises.reps = log['reps_completed']  (comment line 167: "reps = cumulative").
-- So any exercise totaling > 60 reps violates the CHECK. SyncService._syncExerciseLogs
-- catches the PostgrestException(23514) and only logs it → the workout_log_exercises
-- SUMMARY row (read by AI features, weekly report, analytics) is silently missing for
-- high-volume exercises. The per-set rows (workout_log_sets, each reps <= 60) still sync.
--
-- FIX: widen the cap to accommodate cumulative totals. A single exercise tops out at
-- ~10 sets × 60 reps = 600; 1000 leaves head-room while still rejecting absurd values.
-- The realistic-per-set guard belongs on workout_log_sets, not on this aggregate column.

ALTER TABLE public.workout_log_exercises DROP CONSTRAINT IF EXISTS wle_reps_realistic;
ALTER TABLE public.workout_log_exercises
  ADD CONSTRAINT wle_reps_realistic CHECK (reps IS NULL OR (reps >= 0 AND reps <= 1000));

-- Rollback (inline — restores the pre-080 per-set-shaped cap):
-- ALTER TABLE public.workout_log_exercises DROP CONSTRAINT IF EXISTS wle_reps_realistic;
-- ALTER TABLE public.workout_log_exercises
--   ADD CONSTRAINT wle_reps_realistic CHECK (reps IS NULL OR (reps >= 0 AND reps <= 60));
