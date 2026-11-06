---
bug_id: d9a4f2
date: 2026-06-06
batch: wls-reps-fix
status: fixed
blast_radius: account
symptom: >
  workout_log_sets PER-SET rows with reps > 1000 were silently dropped: the cloud
  CHECK wls_reps_realistic (<= 1000) rejected them with 23514 and the sync catch
  swallowed it, so the per-set row (read by receipt / Train / weekly-report sums)
  never reached cloud. Live on the founder's account (d7a67a37) 1530x. The #2 fix
  (migration 084) widened the EXERCISES table (wle) but missed the SETS table.
concept: exercise_logs_read_path
sot_registry_entry: sync_fanout_workout_domain
writers: >
  logging_type_repair_migrator.dart moved duration_seconds (e.g. a 1200s hold)
  INTO a per-set reps value on bodyweight_reps repair; that value synced into
  workout_log_sets.reps at sync/sync_workout.dart per-set projection, unclamped
  (the #2 clamp only guarded the exercises summary row).
readers: >
  WorkoutReceiptCard, Train expanded view, and the weekly-report Edge Function sum
  per-set rows from workout_log_sets. A dropped per-set row undercounts the set.
hive_key_prefix: exlog_
hive_key_formula: not_applicable (no new key — existing exlog_* rows)
sync_methods: syncWorkoutData
restore_methods: not_applicable
cloud_table: workout_log_sets
cloud_columns: reps
contract_test_path: test/contracts/cloud_sync_fixes_2026_06_05_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: wls_reps_out_of_range
cross_account_guard: not_applicable (natural key includes user_id; unchanged)
forbidden_patterns_checked:
  - "the per-set upsert writing the raw sm['reps'] instead of the clamped value — the writer now clamps to [0,10000] and logs wls_reps_out_of_range."
  - "the live wls_reps_realistic CHECK capping reps below 10000 — migration 085 sets <=10000."
  - "the migrator moving a duration > 500 into reps — gated by _kMaxPlausibleReps."
proposed_fix: >
  Three layers: (1) ROOT — logging_type_repair_migrator only moves a duration->reps
  value when it is <= _kMaxPlausibleReps (500); a larger value is almost certainly
  a real duration and is stripped, not fabricated as a huge rep count. (2) GUARD —
  sync/sync_workout.dart clamps per-set reps to [0,10000] and emits
  wls_reps_out_of_range. (3) CONSTRAINT — migration 085 widens wls_reps_realistic
  from <=1000 to <=10000 (matches wle).
regression_test_planned: >
  test/safety/logging_type_repair_migrator_test.dart (large duration NOT moved to
  reps); test/contracts/cloud_sync_fixes_2026_06_05_test.dart (per-set clamp +
  migration 085 <=10000). Migration 085 verified live (pg_get_constraintdef).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "migrator threshold _kMaxPlausibleReps=500 on all 3 bodyweight_reps moves; sync_workout clamps per-set reps + logs wls_reps_out_of_range; flutter analyze clean" }
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 085 applied; pg_get_constraintdef = reps <= 10000" }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "085 in backups/applied_migrations.json" }
impact_analysis: >
  Account blast radius — every user whose migrator moved a large duration into a
  per-set reps value lost that set's cloud row, undercounting receipt / Train /
  weekly-report sums. The migrator threshold stops producing the bad value; the
  clamp+telemetry makes any future out-of-range value visible; migration 085 lets
  legitimate high values sync. Completes migration 084 (which covered only the
  exercises table). Found via the live +33 audit of the founder's account.
---

# workout_log_sets reps > 1000 silently dropped (23514) — completes the wle fix

## What happened
Per-set rows (workout_log_sets.reps) exceeding the cloud cap wls_reps_realistic
<= 1000 were rejected (23514), the sync catch swallowed it, and the per-set row
silently never synced — 1530x on the founder's account. The #2 fix (migration
084 + clamp) closed this on the EXERCISES table (wle) but missed the SETS table.

## Root cause
logging_type_repair_migrator, repairing a bodyweight_reps row, moved a large
duration_seconds (e.g. a 1200s hold) INTO a per-set reps value. The per-set sync
projection wrote it unclamped (the #2 clamp only guarded the exercises summary).

## Fix
Three layers: (1) the migrator only moves a duration into reps when it is small
enough to plausibly BE a rep count (<= _kMaxPlausibleReps = 500); larger values
are stripped, not fabricated. (2) sync_workout clamps per-set reps to [0,10000] +
logs wls_reps_out_of_range. (3) migration 085 widens wls_reps_realistic to 10000.

## Verification
pg_get_constraintdef -> reps <= 10000 (085 live); analyze clean; the migrator
test pins that a large duration is NOT moved to reps; the contract test pins the
per-set clamp.

## See also
- migration 085_widen_wls_reps_realistic.sql
- diagnose e7b3c9 (the wle counterpart this completes)
- lib/core/services/logging_type_repair_migrator.dart (threshold)
- lib/core/services/sync/sync_workout.dart (per-set clamp)
