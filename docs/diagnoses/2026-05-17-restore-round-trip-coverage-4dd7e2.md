---
bug_id: 4dd7e2
date: 2026-05-17
batch: open-issues OI-09 (restore_completeness symmetric coverage)
status: fixed
symptom: |
  Obs 1 of 2026-05-16 (`daffac`) was a live instance of incomplete
  restore: writer (`WorkoutWriteService.logExercise`) stamped
  `workout_log_id` on every exlog row, but `_restoreExerciseLogs`
  did NOT project that field back to Hive on fresh install. Session-
  scoped receipt readers filtered on `workout_log_id` and rejected
  the restored rows → user observed "View Card does nothing" for
  multi-session days.
  Existing `restore_completeness_writes_test.dart` couldn't catch
  the gap because it only enforces "did we call syncX" — not "did
  restoreX project every writer-emitted field back to Hive".
concept: restore_completeness_symmetric
sot_registry_entry: restore_completeness
writers:
  - { file: lib/core/services/workout_write_service.dart, method: logExercise, line: 186 }
  - { file: lib/core/services/sync/sync_workout.dart, method: _restoreExerciseLogs, line: 553 }
  - { file: lib/core/services/sync/sync_workout.dart, method: _restoreScheduledWorkouts, line: 851 }
readers:
  - { file: test/contracts/restore_round_trip_field_coverage_test.dart, method: per-method projection assertions, line: 30 }
hive_key_prefix: "exlog_"
hive_key_formula: "'exlog_${istDateStr(date)}_${uuidV5(...)}'"
sync_methods: [_syncExerciseLogs]
restore_methods: [_restoreExerciseLogs, _restoreScheduledWorkouts, _restoreScheduleCompletions, _restoreWorkoutTemplates, _restoreWorkoutLogs]
cloud_table: workout_log_exercises
cloud_columns: [workout_log_id, exercise_id, set_number, reps, weight_kg, logging_type, is_pr, completed_at]
contract_test_path: test/contracts/restore_round_trip_field_coverage_test.dart
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, line: 801, fn: istDateStr }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "workoutBox user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "writer-emitted field missing from restore projection", absent_outside_canonical: true }
proposed_fix: |
  New contract test `test/contracts/restore_round_trip_field_coverage_test.dart`
  pins per-method projection coverage:

  1. `_restoreExerciseLogs` MUST project `workout_log_id` (Obs 1 anti-
     regression — pre-fix this was the missing field).
  2. `_restoreExerciseLogs` MUST project every CORE writer-emitted
     field (`exercise_name`, `date`, `workout_log_id`, `logging_type`,
     `is_pr`). Legitimate exceptions (telemetry, transient fields)
     documented in test comments.
  3. `_restoreScheduledWorkouts` MUST embed template metadata (Test
     #15.3 / Bug 4a anti-regression — pre-fix template_id alone was
     restored, losing workout_name + exercises[] + workout_focus).
  4. All 5 core workout-domain restore methods MUST exist
     (`_restoreWorkoutLogs`, `_restoreExerciseLogs`,
     `_restoreScheduledWorkouts`, `_restoreScheduleCompletions`,
     `_restoreWorkoutTemplates`). Removal regresses CLAUDE.md §15.

  Source-grep test using method-slice extraction (brace-matching) so
  the assertions scope to each method's actual body.

  Deferred per-domain extension: nutrition + health restore methods
  could get the same field-coverage assertions. No known Obs-class
  drift in those domains today; extension is a follow-up only if a
  drift surfaces.
regression_test_planned:
  - test/contracts/restore_round_trip_field_coverage_test.dart
---
# Body

## Why writer-side tests alone weren't enough

`restore_completeness_writes_test.dart` (Test #11 batch) verifies
the FAN-OUT path: every Hive-only writer surface has a SyncService
method that pushes it. That's necessary but not sufficient — the
matching restore method must ALSO project every writer-emitted
field back into the restored Hive row. Without symmetry, the
restored row is structurally incomplete and downstream readers
silently see null where they expect values.

Obs 1 of 2026-05-16 was the canonical instance: `_syncExerciseLogs`
pushed `workout_log_id` to cloud; `_restoreExerciseLogs` did NOT
project it back to Hive on fresh install; receipt readers filtered
on the field and rejected every restored row. The audit closed the
specific bug; this test pins the symmetry contract so the same
class can't recur.

## Test architecture

```
_methodSlice(src, methodName)
  └─ brace-matches the method body so assertions scope to its source

For each (writer_method, restore_method) pair:
  1. Extract restore_method body
  2. Assert it contains every CORE field name as a quoted Hive key
  3. Allowlist transient/ephemeral fields (telemetry, optional notes)
```

## Verification

```
$ flutter test test/contracts/restore_round_trip_field_coverage_test.dart
All tests passed! (4 cases)
```

## What this test DOESN'T cover (yet)

- Full per-row integration round-trip (write → cloud → wipe → restore
  → diff). That requires Supabase + Hive integration setup. Source-
  grep is the lighter, CI-friendlier first line of defense.
- Nutrition + health restore methods are presence-checked only, not
  field-coverage-checked. No known Obs-class drift in those domains
  today.
- Cloud column existence is not verified (handled by
  `check_onconflict_live_arbiter.dart` + migration discipline).

## Closing

closes-oi: OI-09
