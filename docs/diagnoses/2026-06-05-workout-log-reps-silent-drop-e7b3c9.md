---
bug_id: e7b3c9
date: 2026-06-05
batch: cloud-sync-fixes
status: fixed
blast_radius: account
symptom: >
  workout_log_exercises SUMMARY rows with reps > 1000 were silently dropped:
  the cloud CHECK wle_reps_realistic (<= 1000) rejected them with 23514 and the
  sync catch swallowed it, so the per-exercise summary row (read by AI features,
  weekly report, analytics) never reached cloud. Live on the founder's account
  (d7a67a37) 78x over 4 days.
concept: exercise_logs_read_path
sot_registry_entry: workout_receipt_rendering
writers: >
  WorkoutWriteService.logExercise (workout_write_service.dart:134) sets
  reps_completed = SUM(set.reps) — a CUMULATIVE total. Synced into
  workout_log_exercises.reps at sync/sync_workout.dart:263. A SECOND vector:
  logging_type_repair_migrator.dart moved duration_seconds INTO reps (seconds
  stamped as a rep count), blowing past the cap.
readers: >
  AI snapshot (ai_snapshot_builder.dart buildAiContext), weekly-report Edge
  Function, and analytics read workout_log_exercises.reps. They saw missing
  summary rows for any high-volume exercise.
hive_key_prefix: exlog_
hive_key_formula: not_applicable (no new key — existing exlog_* rows)
sync_methods: syncWorkoutData
restore_methods: not_applicable
cloud_table: workout_log_exercises
cloud_columns: reps
contract_test_path: test/contracts/cloud_sync_fixes_2026_06_05_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: wle_reps_out_of_range
cross_account_guard: not_applicable (natural key includes user_id; unchanged)
forbidden_patterns_checked:
  - "the exercise-log upsert writing the raw reps_completed instead of the clamped value — the writer now clamps to [0,10000] and logs wle_reps_out_of_range; pinned by cloud_sync_fixes_2026_06_05_test.dart + workout_log_exercises_cumulative_reps_test.dart."
  - "the live wle_reps_realistic CHECK capping reps below 10000 (would silently drop high-volume cumulative rows) — migration 084 sets <=10000."
proposed_fix: >
  Two layers (the logging_type_repair_migrator's duration->reps move is left
  UNCHANGED — it is intentional repair behaviour, APK Test #12.5 /
  logging_type_repair_migrator_test "v3"; a large value it produces is now
  bounded downstream rather than dropped): (1) GUARD — sync/sync_workout.dart
  clamps reps to [0,10000] and emits op_type wle_reps_out_of_range, so an
  out-of-range value (cumulative overflow OR a migrator-moved large duration) is
  CAPTURED + visible instead of silently rejected. (2) CONSTRAINT — migration
  084 widens wle_reps_realistic from <=1000 to <=10000 to fit very-high-volume
  cumulative reps (per-set realism stays on workout_log_sets).
regression_test_planned: >
  test/contracts/cloud_sync_fixes_2026_06_05_test.dart — asserts the migrator
  never moves duration into reps, and the sync writer clamps + logs
  wle_reps_out_of_range. Migration 084 verified live (pg_get_constraintdef shows
  reps <= 10000).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "migrator strips duration (no duration->reps); sync_workout clamps reps + logs wle_reps_out_of_range; flutter analyze clean" }
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 084 applied; pg_get_constraintdef = reps <= 10000" }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "084 in backups/applied_migrations.json (hash 1886af16, applier claude)" }
impact_analysis: >
  Account blast radius — every user with a high-volume exercise lost the cloud
  summary row for it. Widening the cap + the migrator fix stop the loss; the
  clamp+telemetry guard makes any future out-of-range value visible instead of
  silent. Rows already rejected never reached cloud but survive in local Hive
  and re-sync once the client carrying this fix lands. Found via the live audit
  of the founder's account.
---

# workout_log_exercises reps > 1000 silently dropped (23514)

## What happened
High-volume exercises' summary rows (reps = Σ set reps) exceeded the cloud cap
`wle_reps_realistic <= 1000` → 23514 → the sync catch swallowed it → the summary
row silently never synced.

## Root cause
Two vectors pushed reps over 1000: (a) the cumulative writer (reps_completed =
SUM(set.reps)); migration 080 widened to 1000 assuming ~600 max. (b)
`logging_type_repair_migrator` moved `duration_seconds` (e.g. 1200s) INTO reps.

## Fix
The migrator's duration→reps move is intentional (APK Test #12.5) and left
unchanged; the silent-drop is closed downstream instead: the exercise-log sync
clamps reps to [0,10000] + logs `wle_reps_out_of_range`, and migration 084 widens
the cap to 10000. A large value (cumulative overflow OR a migrator-moved
duration) now syncs (clamped/visible) instead of being silently rejected.

## Verification
`pg_get_constraintdef` → `reps <= 10000` (084 applied live); analyze clean;
`cloud_sync_fixes_2026_06_05_test.dart` pins the migrator + clamp.

## See also
- migration `084_widen_wle_reps_realistic_high_volume.sql`
- `lib/core/services/sync/sync_workout.dart` (clamp guard)
- `lib/core/services/logging_type_repair_migrator.dart`
