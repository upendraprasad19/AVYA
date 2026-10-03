---
bug_id: a2f9e1
date: 2026-05-12
batch: APK Test #15.1
status: in_progress
symptom: Home renders "Something went wrong" ErrorState after the user schedules a custom template for today. Crash repeats on every cold-start. Telemetry shows 5x widget_error_fallback with message "type 'String' is not a subtype of type 'int?' in type cast".
concept: schedule_exercise_field_types
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreWorkoutTemplates, line: 3896 }
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: _normalizeExercises, line: 1649 }
readers:
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: _buildTodayRow, line: 712 }
  - { file: lib/features/home/widgets/day_detail_sheet.dart, method_or_widget: build, line: 222 }
  - { file: lib/features/train/screens/template_builder_screen.dart, method_or_widget: build, line: 287 }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods: [_syncWorkoutTemplates, _syncScheduledWorkouts]
restore_methods: [_restoreWorkoutTemplates, _restoreWorkoutPlan]
cloud_table: template_exercises
cloud_columns: [prescribed_sets, prescribed_reps]
contract_test_path: test/contracts/schedule_exercise_field_types_test.dart
ist_handling: []
provider_invalidations: [todayWorkoutProvider, currentPlanProvider, calendarWeekProvider]
telemetry_op_types:
  success: []
  failure: [widget_error_fallback]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "'sets':\\s*ex\\['prescribed_sets'\\]\\?\\.toString\\(\\)", absent: true }
proposed_fix: |
  Two writer-side fixes:
  1. sync_service.dart `_restoreWorkoutTemplates` — replace
     `'sets': ex['prescribed_sets']?.toString() ?? '3'` with
     `'sets': _coerceInt(ex['prescribed_sets'], fallback: 3)`. New
     top-level helper `_coerceInt` accepts int/num/String/null and
     returns int.
  2. workout_schedule_service.dart `_normalizeExercises` — defensive
     inline coercion before writing the schedule, so legacy Hive rows
     already carrying stringified sets are corrected on first
     assignTemplateToDate.
  Readers (home_screen, day_detail_sheet, template_builder_screen)
  keep their `as int?` casts unchanged.
regression_test_planned:
  - test/contracts/schedule_exercise_field_types_test.dart
---

# Bug A — Map cast crash on scheduled template

## Symptom

After scheduling a custom template (e.g. "Back Day A") for today, home rendered the ErrorState ("Something went wrong / Tap to retry"). Crash repeated on every cold-start. Telemetry captured 5x `widget_error_fallback` events between 05:20 and 06:33 UTC on 2026-05-11, all with message:

```
type 'String' is not a subtype of type 'int?' in type cast
```

## Root cause

`_restoreWorkoutTemplates` (lib/core/services/sync_service.dart:3896) shaped cloud `template_exercises` rows into local Hive `tmpl_*` shape, stringifying `prescribed_sets`:

```dart
'sets': ex['prescribed_sets']?.toString() ?? '3',
```

Result: every cloud-restored template carried `'sets'` as `String` in local Hive. When the user invoked `assignTemplateToDate`, the template's exercises flowed through `_normalizeExercises` (workout_schedule_service.dart:1656), which passed `m['sets']` through with no coercion:

```dart
'sets': m['sets'] ?? m['prescribed_sets'] ?? m['default_sets'] ?? 3,
```

The schedule entry now had `exercises[i]['sets'] = '3'` (String). Home's `_buildTodayRow` reads `(ex['sets'] as int?)` — the cast crashed, ErrorState rendered, repeated on every cold start until the user manually removed the template.

## Fix

### Writer 1 — `_restoreWorkoutTemplates` coerces at cloud-restore time

New top-level helper in `sync_service.dart`:

```dart
int _coerceInt(dynamic value, {required int fallback}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return fallback;
}
```

`_restoreWorkoutTemplates` now writes:

```dart
'sets': _coerceInt(ex['prescribed_sets'], fallback: 3),
```

`reps` deliberately stays as a String (exercise library uses ranges like "8-12" which a single int can't represent).

### Writer 2 — `_normalizeExercises` defensive coercion (legacy data)

The cloud-side fix protects new restores, but legacy Hive rows already on the founder's device still carry stringified sets. `_normalizeExercises` now coerces inline:

```dart
final rawSets = m['sets'] ?? m['prescribed_sets'] ?? m['default_sets'] ?? 3;
final int setsInt;
if (rawSets is int) setsInt = rawSets;
else if (rawSets is num) setsInt = rawSets.toInt();
else if (rawSets is String) setsInt = int.tryParse(rawSets) ?? 3;
else setsInt = 3;
// later: 'sets': setsInt,
```

So even if a stringified value sneaks through from any source, the schedule entry that hits home_screen has a proper int.

## Verification

- 5 source-grep contract tests pass:
  - `_coerceInt` helper exists
  - `_restoreWorkoutTemplates` uses `_coerceInt(ex['prescribed_sets']`
  - Forbidden `prescribed_sets?.toString()` pattern absent
  - `_normalizeExercises` has int / num / String coercion branches
  - `_normalizeExercises` assigns `setsInt` (coerced) to `'sets'` key
- Founder install: scheduling a template no longer crashes home + cold-start succeeds.

## Related

- `feedback_source_of_truth_audit.md` — writer/reader pairs named at file:line.
- audit-batch H-42 cohort 6 (commit `c0b9999`) — added `widget_error_fallback` telemetry that surfaced this bug.
