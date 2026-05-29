---
bug_id: 7c2a8b
date: 2026-05-29
batch: audit-2026-05-29
status: fixed_in_this_batch
symptom: >
  After any cloud restore (reinstall, new device, logout then login) every
  workout session name ("Push A", "Pull B") is replaced by the literal
  "Workout" in home history, receipt headers, and the AI snapshot.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
blast_radius: platform
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method: _syncWorkoutLogs, line: 133 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _restoreWorkoutLogs, line: 542 }
hive_key_prefix: wlog_
hive_key_formula: wlog_ + istDateStr(date)
sync_methods: [_syncWorkoutLogs]
restore_methods: [_restoreWorkoutLogs]
cloud_table: workout_logs
cloud_columns: [user_id, date, workout_name, sets_completed, duration_seconds]
contract_test_path: test/sync/restore_field_canonical_test.dart
ist_handling:
  - { file: lib/core/services/sync/sync_workout.dart, line: 531, fn: _restoreWorkoutLogs }
provider_invalidations: []
telemetry_op_types:
  success: [restore_workout_logs]
  failure: [restore_workout_logs]
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "exercise_name read inside _restoreWorkoutLogs body", absent: true }
proposed_fix: >
  Change the _restoreWorkoutLogs Hive write to read map['workout_name'] instead
  of the dead map['exercise_name']. Migration 068b renamed the cloud column
  exercise_name to workout_name; the write side already emits workout_name, so
  the restore reader was the only remaining consumer of the dead name.
regression_test_planned:
  - test/sync/restore_field_canonical_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "sync_workout.dart:542 now reads map['workout_name']" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "restored wlog_ row now carries the real session label" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "migration 068b renamed workout_logs.exercise_name to workout_name; live column confirmed" }
impact_analysis: >
  The write side (upsert, line 133) emits workout_name with onConflict on
  workout_name, so cloud rows hold the correct session label. Only the restore
  reader read the dead exercise_name key, yielding null on every post-068b row
  and falling back to "Workout". Effect is display-only (session label) on the
  restore path; per-exercise sets/reps in workout_log_exercises are unaffected.
  No data loss; corrected by a one-line field read plus a scoped regression test.
---

# 7c2a8b — restore read the dead exercise_name column

## What happened
Migration `068b` renamed `workout_logs.exercise_name` to `workout_name`
(the value was always a session label, never a per-exercise id). The write
projection (`_syncWorkoutLogs`, line 133) was updated to emit `workout_name`
with `onConflict: user_id,date,workout_name`. But the restore reader
(`_restoreWorkoutLogs`, line 542) still read `map['exercise_name']` — absent on
every post-rename cloud row — so it fell back to the literal `'Workout'`,
relabelling every restored session.

## Root cause
Writer/reader drift on the RESTORE leg (the recurring class —
`feedback_writer_reader_field_drift_recurring.md`). The drift-fix batch updated
the write side and added a write-side test, but never pinned the restore
round-trip, so the dead read survived.

## Fix
`map['exercise_name']` → `map['workout_name']` at line 542. Added a scoped
source contract (D3 group in `restore_field_canonical_test.dart`) asserting
`_restoreWorkoutLogs` reads `workout_name` and never `exercise_name`.

## Verification
Live schema confirms `workout_logs.workout_name` exists (renamed by 068b).
`flutter analyze` + `flutter test` green (see batch verification).
