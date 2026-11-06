---
bug_id: a3e8f1
date: 2026-06-08
batch: regression-prevention-wi1-2026-06-08
status: fixed
blast_radius: account
symptom: >
  workout_log_exercises.set_number and workout_log_sets.set_number carried a CHECK
  bound of <=10 (wle_set_number_realistic / wls_set_number_realistic). >10 sets per
  exercise is legitimate (drop sets, rest-pause, high-volume), and live data already
  held a 15-set row (grandfathered because wls_set_number_realistic was NOT VALID).
  A new >10-set workout hits 23514 on the all-or-nothing per-set upsert in
  sync_workout.dart and silently drops the per-set rows (which back the receipt /
  Train / weekly-report sums); the wle summary row (set_number = sets count) was
  latently at the same risk for an >10-set exercise. Surfaced 2026-06-08 by the
  WI-1 constraint-clamp parity analysis (comparing live CHECK bounds to client
  values).
concept: workout_receipt_rendering
sot_registry_entry: workout_receipt_rendering
writers:
  - { file: supabase/migrations/089_widen_set_number_check.sql, line: 6 }
  - { file: lib/core/services/sync/sync_workout.dart, line: 338 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, line: 326 }
hive_key_prefix: exlog_
hive_key_formula: "exlog_<istDateStr(date)>_<exerciseName hash>"
sync_methods: [syncWorkoutData]
restore_methods: []
cloud_table: workout_log_sets
cloud_columns: [user_id, workout_log_id, exercise_id, set_number, weight_kg, reps, duration_secs, distance_km, completed_at]
contract_test_path: test/contracts/constraint_boundary_clamp_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [wls_reps_out_of_range, wls_duration_out_of_range]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "set_number clamped client-side (would corrupt the set index/count)", absent: true }
proposed_fix: >
  Widen the bound, do NOT clamp. >10 sets is legitimate, so clamping set_number
  (15 -> 10) would corrupt the set index/count. Migration 089 raises both
  wle_set_number_realistic and wls_set_number_realistic from <=10 to <=50 (generous;
  no realistic single-exercise session exceeds it); existing rows (max 15) pass, so
  the constraints re-validate (convalidated=true). Applied to prod dedsavbjuwgarrhphgnl
  2026-06-08 (founder-authorized). Separately, the per-set duration_secs (CHECK <=3600,
  max-observed 60) gained a defensive client clamp in sync_workout.dart to close the
  last constraint-clamp parity gap (an implausible >1h per-set duration is capped, not
  dropped). reps were already clamped to 10000 (diagnose d9a4f2).
regression_test_planned:
  - test/contracts/constraint_boundary_clamp_test.dart
touched_layers_checked:
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 089 applied; pg_constraint confirms wle/wls_set_number_realistic now CHECK (<=50) with convalidated=true (verified post-apply)" }
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "sync_workout.dart per-set upsert gains a duration_secs clamp(0,3600); reps clamp(0,10000) unchanged; set_number deliberately NOT clamped" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "max set_number live = 15 (wls) / 8 (wle); both <= new bound 50, so re-validation passed with no data loss" }
  - { tier: 12, layer: end_to_end_contract, status: verified, evidence: "test/contracts/constraint_boundary_clamp_test.dart green: clamp bounds == live CHECK bounds; set_number not clamped" }
impact_analysis: >
  Account blast radius — workouts with >10 sets of an exercise silently dropped
  their per-set rows on sync (the per-set table backs receipts / Train / weekly
  report). Widening restores them going forward; existing grandfathered rows were
  already present. Same silent-drop class as the reps family (d9a4f2 / e7b3c9 /
  7d3f0a) but the cure is a wider CHECK, not a clamp — the value was legitimate,
  not a glitch. Found by the WI-1 constraint-clamp parity work.
related_bugs: [d9a4f2, e7b3c9, 7d3f0a, b4e2a9, d7c3f1]
recurrence: >
  Constraint-too-tight variant of the cloud-contract silent-drop class. The reps
  bound (10000) was generous enough; the set_number bound (10) was set far below
  legitimate usage. wls_set_number_realistic + wls_duration_secs_realistic were
  added NOT VALID, which hid existing violators (the 15-set row) while still
  rejecting new ones — the classic NOT-VALID blind spot.
---

# set_number CHECK (<=10) too tight: >10-set workouts silently drop per-set rows

See frontmatter for the structured diagnosis. Found by the WI-1 constraint-clamp
parity analysis: comparing live `pg_constraint` bounds against client-written
values showed `workout_log_sets.set_number` max = 15 in live data against a CHECK
of `<=10`. Because `>10` sets is legitimate, the fix is to widen the constraint
(migration 089, `<=50`), not to clamp (which would corrupt the set index/count).
The reps family was already clamped (10000); `duration_secs` gained a defensive
clamp to complete the parity. Regression guard:
`test/contracts/constraint_boundary_clamp_test.dart`.
