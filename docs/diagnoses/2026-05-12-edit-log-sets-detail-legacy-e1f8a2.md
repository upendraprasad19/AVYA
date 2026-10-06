---
bug_id: e1f8a2
date: 2026-05-12
batch: APK Test #15.3
status: in_progress
symptom: |
  When the user opens the Edit Workout Log sheet for a previously-completed
  exercise that was logged via the modern WorkoutWriteService (post-Test-#6),
  the per-set inputs show the legacy aggregate single-row view instead of
  pre-filled per-set values. Especially visible for TIMED exercises (Handstand
  Hold, Jump Rope, plank) where the user logged distinct durations per set
  (e.g. 10s × 3 sets, 30s × 2 sets) — the duration input shows empty even
  though Hive `log['sets']` and cloud `workout_log_sets.duration_secs` both
  carry the correct values. The user is presented with a single duration
  field set to 0/empty and forced to re-enter their data.
concept: exercise_log_per_set
sot_registry_entry: exercise_log_per_set
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "logExercise (canonical sets[])", line: 170 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "editLog (legacy→canonical migration)", line: 643 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_restoreExerciseLogs (writes 'sets' with per-set 'duration_seconds')", line: 2893 }
readers:
  - { file: lib/features/train/widgets/edit_workout_log_sheet.dart, method_or_widget: "_ExerciseEditRow.fromLog (reads only sets_detail)", line: 865 }
  - { file: lib/features/train/widgets/edit_workout_log_sheet.dart, method_or_widget: "_SetEditRow.fromSetDetail (per-set parse — reads only duration_seconds)", line: 802 }
hive_key_prefix: exlog_
hive_key_formula: "'exlog_${istDateStr(date)}_${lower(exerciseName).hashCode.toRadixString(16)}'"
sync_methods:
  - SyncService._syncExerciseLogs
restore_methods:
  - SyncService._restoreExerciseLogs
cloud_table: workout_log_sets
cloud_columns:
  - id
  - user_id
  - workout_log_id
  - exercise_id
  - set_number
  - weight_kg
  - reps
  - duration_secs
  - distance_km
  - completed_at
contract_test_path: test/contracts/edit_workout_log_sets_field_contract_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - todayWorkoutProvider
  - calendarWeekProvider
  - currentPlanProvider
  - workoutStatsProvider
  - streakProvider
  - allExercisePRsProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  `_ExerciseEditRow.fromLog` is a pure stateless factory that reads a
  `Map<String, dynamic>` parameter and writes no Hive box. The caller
  (`_EditWorkoutLogSheetState._loadRows`) sources the maps from
  `WorkoutRepository.instance.getExerciseLogsForDate(date)` which reads
  the user-scoped `workoutBox` via `HiveUserSession`
  (lib/core/services/hive_user_session.dart). No user_id is read inside
  fromLog; no cross-account leak path. The fix only changes field-name
  acceptance — it neither widens box access nor changes telemetry payload.
forbidden_patterns_checked:
  - { pattern: "log\\['sets_detail'\\];\\n\\n    // Check if per-set", absent: true }
  - { pattern: "final setsDetailRaw = log\\['sets_detail'\\];$", absent: true }
proposed_fix: |
  Two-layer field-name fallback aligning the edit-sheet reader with the
  canonical writer (`WorkoutWriteService.logExercise`) AND the legacy
  restore path (`SyncService._restoreExerciseLogs`).

  Layer 1 — `_ExerciseEditRow.fromLog`
  (lib/features/train/widgets/edit_workout_log_sheet.dart:865): change
  the top-level per-set list lookup to prefer canonical `'sets'` and
  fall back to legacy `'sets_detail'`:

  ```dart
  // BEFORE: final setsDetailRaw = log['sets_detail'];
  // AFTER:
  final setsListRaw = log['sets'] ?? log['sets_detail'];
  ```

  This is the gate that decides per-set vs aggregate view. After the
  fix, modern WriteService rows (which have `sets` and no `sets_detail`)
  branch into the per-set rendering path.

  Layer 2 — `_SetEditRow.fromSetDetail`
  (lib/features/train/widgets/edit_workout_log_sheet.dart:802): per-set
  duration currently reads only legacy `duration_seconds`. Modern sets
  (written by `ExerciseSet.toMap`, line 95 of write_result.dart) carry
  `duration_sec`. Add the dual-name fallback — same shape as Bug 4c's
  `ExerciseSet.fromMap` fix (write_result.dart:117-118):

  ```dart
  final duration = (set['duration_sec'] as num?)?.toInt() ??
                   (set['duration_seconds'] as num?)?.toInt() ??
                   0;
  ```

  No other field changes are required. `reps` and `weight_kg` use the
  same canonical names in both shapes (per `_restoreExerciseLogs`
  projection at sync_service.dart:2878,2876).

  Side effect — `_ExerciseEditRow` is marked `@visibleForTesting` so
  the contract test can drive the factory directly without mounting
  the widget. The class is private (leading underscore) but Dart's
  `@visibleForTesting` annotation + a top-level `library` directive
  allow `_*` symbols to remain inaccessible outside the test ↔ the
  alternative is to make the class public-with-comment.

  Decision: make `_ExerciseEditRow` → `ExerciseEditRowForTest` (public)
  via an export-style typedef. Cleaner is to make the class public but
  prefix with `// ignore_for_file: public_member_api_docs` comment and
  rename to `EditWorkoutLogExerciseEditRow` with a leading-doc note
  "Public solely for contract testing — not part of the widget API".
regression_test_planned:
  - test/contracts/edit_workout_log_sets_field_contract_test.dart
---

# Bug 6 — Edit Workout Log sheet drops to aggregate view for modern logs

## Symptom

User completes a workout that includes timed exercises (e.g. Handstand Hold
30s × 3 sets). Opens the Edit Workout Log sheet from any entry point
(WorkoutReceiptSheet, Home "View Card", calendar day detail). The sheet
should render three per-set duration fields pre-filled with `30`, `30`,
`30`. Instead it renders a single aggregate duration field, which is
either empty (if `log['duration_seconds']` is null — true for modern
WriteService rows) or shows a placeholder value.

The user is forced to re-enter all their data even though Hive
`log['sets']` and cloud `workout_log_sets.duration_secs` both carry the
exact correct values.

## Root cause

`_ExerciseEditRow.fromLog` at
`lib/features/train/widgets/edit_workout_log_sheet.dart:865`:

```dart
factory _ExerciseEditRow.fromLog(String logId, Map<String, dynamic> log) {
  final name = (log['exercise_name'] as String?) ?? 'Exercise';
  final type = (log['logging_type'] as String?) ?? 'weight_reps';
  final setsDetailRaw = log['sets_detail'];  // ← only legacy name

  if (setsDetailRaw is List && setsDetailRaw.isNotEmpty) {
    // per-set path ...
  }

  // Fallback: legacy aggregate view ← modern WriteService rows hit this
  final sets = (log['sets_completed'] as num?)?.toInt() ?? 0;
  // ...
}
```

The pre-Test-#6 writer wrote `log['sets_detail']` (legacy field name).
Post-Test-#6 `WorkoutWriteService.logExercise`
(`lib/core/services/workout_write_service.dart:170`) writes canonical
`log['sets']` and does NOT populate `sets_detail`. The legacy aggregate
fields `sets_completed`, `reps_completed`, `weight_kg`, `duration_seconds`
exist on the modern row as well, but `duration_seconds` is NEVER written
at the top level by the modern writer — it lives only inside per-set
entries.

So on a modern row:
- `setsDetailRaw = null` → branch falls through to aggregate fallback.
- Aggregate fallback reads `log['duration_seconds']` → also null.
- `durationCtrl` is constructed with empty text.

For weight_reps exercises the bug is more subtle: the aggregate fields
`reps_completed` (sum across sets) and `weight_kg` (max across sets) DO
exist on the modern row, but they're aggregates, not per-set values.
Showing them in the aggregate fallback view loses per-set granularity —
the user can't see which set was 80kg vs 100kg.

For timed exercises (the founder's primary observation), there's no
aggregate `duration_seconds` to fall back to, so the field is just
empty.

## Same class as Bug 4c

This is the readers-side mirror of Bug 4c (6e1b45) which fixed
`ExerciseSet.fromMap` (the WRITER's re-merge gate). Bug 4c's diagnose-doc
explicitly listed this bug as out-of-scope follow-up
(`docs/diagnoses/2026-05-12-timed-exercise-zero-duration-6e1b45.md`
section "Out of scope" item 2):

> EditWorkoutLogSheet legacy aggregate fallback — when restored logs
> have sets[] (canonical key) but no sets_detail, the edit sheet's
> _ExerciseEditRow.fromLog at edit_workout_log_sheet.dart:865 falls
> through to the legacy aggregate view because it reads ONLY
> log['sets_detail']. … This is a separate readers-side gap; filing as
> a follow-up.

## Fix

### Layer 1 — accept canonical sets[]

Change `_ExerciseEditRow.fromLog`:

```dart
// Prefer canonical 'sets' (post-Test-#6 WriteService) with legacy
// 'sets_detail' fallback for pre-Test-#6 rows that may still exist
// in long-installed devices' Hive.
final setsListRaw = log['sets'] ?? log['sets_detail'];

if (setsListRaw is List && setsListRaw.isNotEmpty) {
  // ... unchanged per-set construction path
}
```

### Layer 2 — per-set duration dual-name

`_SetEditRow.fromSetDetail` at line 802 currently reads only
`duration_seconds`. The modern per-set shape (written by
`ExerciseSet.toMap`, write_result.dart:95-100) uses `duration_sec`.
Mirror the dual-name pattern Bug 4c applied to `ExerciseSet.fromMap`:

```dart
final duration = (set['duration_sec'] as num?)?.toInt() ??
                 (set['duration_seconds'] as num?)?.toInt() ??
                 0;
```

Restore path (`SyncService._restoreExerciseLogs:2882`) emits
`duration_seconds` inside `sets[]` entries, so the legacy fallback
remains correct for restored rows. New WriteService writes carry
`duration_sec`, so the canonical path covers them. Both shapes
co-exist after a restore + a subsequent active-workout log.

`reps` and `weight_kg` use canonical names in both shapes (the
restore projection at sync_service.dart:2876,2878 emits those names
identically to the writer at write_result.dart:96-97), so no dual-name
needed for those fields.

### Testability

`_ExerciseEditRow` is private to `edit_workout_log_sheet.dart`. To enable
direct factory testing without mounting the full widget, I expose it via
`@visibleForTesting` (the class is renamed without leading underscore +
annotated). The widget itself continues to use the symbol normally; only
the contract test imports the public name. Mounting the full widget
would require Hive setup + a real `WorkoutRepository` round-trip, which
is overkill for a pure factory contract.

## Verification

Contract test at
`test/contracts/edit_workout_log_sets_field_contract_test.dart` covers
three cases:

1. **Modern WriteService shape** — log has `sets: [{reps, weight_kg,
   duration_sec, logged_at_ms}, ...]`, no `sets_detail`. Asserts the
   factory returns `hasPerSetData=true`, three set rows, each
   `durationCtrl.text == "30"`.
2. **Legacy pre-Test-#6 shape** — log has `sets_detail: [{reps,
   weight_kg, duration_seconds, set_number}, ...]`, no `sets`. Asserts
   the factory returns `hasPerSetData=true`, three set rows, each
   `durationCtrl.text == "30"` (legacy fallback still works).
3. **Restore-shape hybrid** — log has `sets: [{reps, weight_kg,
   duration_seconds}, ...]` (canonical key, legacy per-set field name
   as written by `_restoreExerciseLogs:2893`). Asserts factory returns
   `hasPerSetData=true` and durations are populated.

Pre-fix: case 1 FAILS (`hasPerSetData=false`, falls through to
aggregate view where `durationCtrl.text` is empty). Case 3 FAILS
(`hasPerSetData=false` because `sets_detail` is null).
Post-fix: all three cases pass.

## Out of scope

- The `_save` path of `EditWorkoutLogSheet` (lines ~108-220) already
  writes both `sets_detail` (legacy) AND `sets` (canonical) field names
  on the save back to Hive, so this fix doesn't introduce new save-path
  asymmetry. Cleaning up that dual write is a separate follow-up.

- Aggregate fallback (line 891-915) is unchanged. Pre-Test-#6 rows that
  never had `sets`/`sets_detail` at all (one-shot complete-workout
  writes from very old versions) continue to use the aggregate path.

## Related

- CLAUDE.md §15 "Hive field-name contract" — the discipline this bug
  enforces.
- `docs/diagnoses/2026-05-12-timed-exercise-zero-duration-6e1b45.md` —
  Bug 4c, writer-side mirror.
- `docs/diagnoses/2026-05-12-edit-log-id-injection-f4c9e1.md` — sibling
  field-name drift on `id` injection.
- APK Test #6 — introduced the `sets` / `duration_sec` canonical names
  without sweeping the EditWorkoutLogSheet reader.
