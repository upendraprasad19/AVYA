-- Intent: Widen workout_log_sets.wls_reps_realistic from <=1000 to <=10000 to fit per-set values a migrator duration->reps leak can produce, paired with a client clamp+telemetry guard so out-of-range per-set values are captured, never silently dropped (23514). Completes the #2 reps fix (migration 084 covered the exercises table; this covers the sets table).
-- Destructive?: no   -- widens an existing CHECK; no rows rewritten, no data loss. Previously-rejected high-volume per-set rows can now sync.
-- Rollback strategy: inline   -- reverse DDL (restore the <=1000 cap) commented at file end.
-- Linked diagnose-doc: d9a4f2
--
-- 085_widen_wls_reps_realistic.sql
--
-- Diagnose: 2026-06-06-workout-log-sets-reps-silent-drop (d9a4f2)
-- Blast radius: account (every user's per-set workout rows).
--
-- BUG (live, founder's account d7a67a37, 1530x): workout_log_sets rows with
-- reps > 1000 are rejected by wls_reps_realistic (23514) and the sync catch
-- swallows it -> the per-set row (read by receipt / Train / weekly-report sums)
-- silently never reaches cloud. Source: logging_type_repair_migrator moved a
-- large duration_seconds (e.g. a 1200s hold) INTO a per-set reps value. The wle
-- (exercises) table was widened by migration 084 + clamped; the wls (sets) table
-- was missed -- this completes the fix. The old constraint was also NOT VALID.
--
-- FIX: widen the per-set cap to 10000 (matches wle) as a VALIDATED constraint.
-- The migrator now refuses to move durations > 500 into reps (root cause), and
-- the client clamps per-set reps to [0,10000] + logs op_type wls_reps_out_of_range,
-- so any future out-of-range value is captured + visible instead of silently lost.

ALTER TABLE public.workout_log_sets DROP CONSTRAINT IF EXISTS wls_reps_realistic;
ALTER TABLE public.workout_log_sets
  ADD CONSTRAINT wls_reps_realistic CHECK (reps IS NULL OR (reps >= 0 AND reps <= 10000));

COMMENT ON CONSTRAINT wls_reps_realistic ON public.workout_log_sets IS
  'per-set reps bound [0,10000] (migration 085, diagnose d9a4f2). A migrator '
  'duration->reps leak is now bounded here + clamped client-side, never dropped.';

-- Rollback (inline — restores the pre-085 cap):
-- ALTER TABLE public.workout_log_sets DROP CONSTRAINT IF EXISTS wls_reps_realistic;
-- ALTER TABLE public.workout_log_sets
--   ADD CONSTRAINT wls_reps_realistic CHECK (reps IS NULL OR (reps >= 0 AND reps <= 1000)) NOT VALID;
