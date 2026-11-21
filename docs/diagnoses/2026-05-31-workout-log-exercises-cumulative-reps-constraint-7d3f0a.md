---
bug_id: 7d3f0a
date: 2026-05-31
batch: year-simulation-2026-05-31
status: fixed
symptom: >
  Surfaced by the year-simulation harness: SyncService._syncExerciseLogs logs
  repeated PostgrestException(code 23514, "new row for relation
  workout_log_exercises violates check constraint wle_reps_realistic") for
  exercises whose total reps exceed 60 (e.g. 5×15=75). The per-set rows
  (workout_log_sets) sync fine; the per-exercise SUMMARY row silently fails to
  reach cloud (the catch swallows it), so AI features / weekly report /
  analytics that read workout_log_exercises undercount high-volume exercises.
concept: exercise_logs_read_path
sot_registry_entry: exercise_logs_read_path
blast_radius: account
writers:
  - { file: lib/core/services/workout_write_service.dart, method: logExercise (totalReps = mergedSets.fold(+s.reps)), line: 134 }
  - { file: lib/core/services/sync/sync_workout.dart, method: _syncExerciseLogs (reps = log['reps_completed']), line: 252 }
readers:
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method: aggregates per-exercise reps for the AI snapshot, line: 920 }
  - { file: supabase/migrations/080_relax_wle_reps_realistic_cumulative.sql, method: ALTER CONSTRAINT wle_reps_realistic, line: 1 }
hive_key_prefix: "exlog_"
hive_key_formula: "'exlog_' + istDateStr(date) + '_' + exerciseName.hashCode.toUnsigned(32).toRadixString(16)"
sync_methods: [syncWorkoutData]
restore_methods: [_restoreWorkoutLogs]
cloud_table: workout_log_exercises
cloud_columns: [id, workout_log_id, user_id, exercise_name, logging_type, set_number, reps, weight_kg, volume_kg]
contract_test_path: test/contracts/workout_log_exercises_cumulative_reps_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [sync_exercise_logs]
cross_account_guard: >
  workout_log_exercises RLS scopes rows to auth.uid()=user_id; the upsert
  carries user_id from the session. No cross-account exposure — this is a
  per-user write-rejection bug.
forbidden_patterns_checked:
  - { pattern: "wle_reps_realistic caps cumulative reps at 60", absent: true }
proposed_fix: >
  The cloud CHECK wle_reps_realistic = (reps IS NULL OR reps BETWEEN 0 AND 60)
  was written assuming `reps` is a PER-SET value, but the canonical writer
  (WorkoutWriteService.logExercise:134) stores reps_completed = Σ set.reps
  (CUMULATIVE), which sync_workout.dart:252 maps to workout_log_exercises.reps.
  Any exercise totaling > 60 reps (5×15, 3×25 bodyweight, etc. — extremely
  common) violated the CHECK → 23514 → SyncService._syncExerciseLogs caught +
  logged it (op_type sync_exercise_logs) but the summary row never landed.
  Migration 080 widens the cap to <= 1000 (a single exercise tops out ~10×60 =
  600); per-set realism stays enforced on workout_log_sets. No data rewrite —
  previously-rejected summary rows now sync on the next push.
regression_test_planned:
  - test/contracts/workout_log_exercises_cumulative_reps_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: verified, evidence: "WorkoutWriteService.logExercise:134 totalReps=fold(+s.reps); sync_workout.dart:252 reps=reps_completed (cumulative by design — comment line 167)" }
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 080 applied via Management API; pg_get_constraintdef now returns reps BETWEEN 0 AND 1000 (was 0 AND 60)" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "no rewrite needed; high-rep summary rows that 23514'd before now upsert successfully on next sync (verified via year-sim re-drive)" }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "backups/applied_migrations.json paired with 080 (sha256:d8f1e6f1c2...)" }
  - { tier: 12, layer: end_to_end_contract, status: fixed_in_this_batch, evidence: "year-sim writes 5×15 (75-rep) exercises; pre-080 these 23514'd, post-080 workout_log_exercises summary rows land" }
impact_analysis: >
  Account-tier silent data loss. No crash, no user-visible error — the catch
  in _syncExerciseLogs swallows the 23514. Per-set rows (workout_log_sets) were
  always fine (each set's reps <= 60). Only the per-exercise SUMMARY row was
  lost, for any exercise totaling > 60 reps. Consumers of workout_log_exercises
  (AI coach snapshot, weekly report volume, analytics) undercounted those
  exercises. This is the exact class the user asked about ("why are we getting
  bugs after audits?") — static schema audits never cross-checked the CUMULATIVE
  writer semantic against the per-set-shaped CHECK, and a single workout silently
  dropping one summary row is invisible without a multi-week replay. The
  simulation harness surfaced it by logging high-volume exercises across weeks.
---

# 7d3f0a — workout_log_exercises cumulative reps rejected by wle_reps_realistic

## What happened
`WorkoutWriteService.logExercise` records `reps_completed = Σ set.reps`
(cumulative across all sets — `workout_write_service.dart:134`).
`SyncService._syncExerciseLogs` maps that to `workout_log_exercises.reps`
(`sync_workout.dart:252`, comment line 167: "reps = cumulative"). The cloud
CHECK `wle_reps_realistic` allowed only `0 <= reps <= 60` — a **per-set** bound.
So any exercise with total reps > 60 (5×15 = 75, 3×25 bodyweight = 75, 4×20 =
80, …) violated the constraint with PostgrestException `23514`. The catch in
`_syncExerciseLogs` logged it (`op_type=sync_exercise_logs`) and continued — the
**summary row silently never synced**.

## Why it was invisible
The per-set rows (`workout_log_sets`, each ≤ 60 reps) always synced, so receipts
+ per-set history looked complete. Only the aggregate summary row was lost, and
only for high-volume exercises — and the error was swallowed. No static audit
caught it because the writer's *cumulative* semantic was never cross-checked
against the per-set-shaped CHECK. A single workout silently dropping one summary
row is undetectable without a multi-week data replay — which is exactly what the
year-simulation harness did.

## Fix
Migration 080: `wle_reps_realistic` widened to `reps BETWEEN 0 AND 1000`
(a single exercise tops out ~10 sets × 60 = 600). Per-set realism stays on
`workout_log_sets`. No data rewrite; previously-rejected summary rows sync on
the next push.

## Verification
`pg_get_constraintdef` after 080 → `CHECK ((reps IS NULL) OR ((reps >= 0) AND
(reps <= 1000)))`. Year-sim re-drive logs 75-rep exercises; pre-080 they
23514'd, post-080 their `workout_log_exercises` rows land. Contract test
`workout_log_exercises_cumulative_reps_test.dart` pins the writer's cumulative
semantic (a 5×15 log → `reps_completed == 75`).
