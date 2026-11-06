---
bug_id: f4c9e1
date: 2026-05-12
batch: APK Test #15.1
status: in_progress
symptom: After completing today's morning workout via the active-workout flow, the Edit Workout Log sheet shows "No exercise logs for this day" — blank. Cloud workout_log_exercises HAS the 5 rows for the founder on 2026-05-11 (completed_at 05:19 UTC = May 11 10:49 IST). Local Hive also has them at correct keys.
concept: exercise_logs_read_path
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: logExercise, line: 166 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: getExerciseLogsForDate, line: 479 }
  - { file: lib/features/train/widgets/edit_workout_log_sheet.dart, method_or_widget: _loadRows where(id is String), line: 67 }
hive_key_prefix: exlog_
hive_key_formula: "'exlog_${istDateStr(date)}_${lower(exerciseName).hashCode.toRadixString(16)}'"
sync_methods: [_syncWorkoutLogExercises]
restore_methods: [_restoreWorkoutLogExercises]
cloud_table: workout_log_exercises
cloud_columns: [id, exercise_name, reps, weight_kg, set_number, completed_at]
contract_test_path: test/contracts/edit_log_id_injection_test.dart
ist_handling:
  - { file: lib/features/train/repositories/workout_repository.dart, line: 480, fn: getExerciseLogsForDate }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "map\\['type'\\] != 'exercise_log'", absent: true }
proposed_fix: |
  Bug class: writer↔reader contract drift. The Test #6 WriteService
  rewrite (workout_write_service.dart:166-179) writes exlog map values
  WITHOUT an `id` field — `id` IS the Hive key. Pre-Test-#6 readers
  iterated `box.toMap()` and saw the key directly; the post-Test-#6
  indexed-path reader (`getExerciseLogsForDate`) returns value maps
  via `box.get(id)` and never re-injects the key. Then
  EditWorkoutLogSheet._loadRows filters `where(log['id'] is String)` —
  every row stripped, empty list, "No exercise logs."

  Fix in workout_repository.dart:
    1. Indexed-path branch: after `final raw = box.get(id)`, do
       `final m = Map<String, dynamic>.from(raw); m['id'] = id; logs.add(m);`
    2. Legacy fallback branch: same pattern — `map['id'] = key`.
    3. Replace `map['type'] != 'exercise_log'` filter with
       `map['exercise_name'] == null` (since WriteService doesn't write
       `type` but always writes `exercise_name`).
regression_test_planned:
  - test/contracts/edit_log_id_injection_test.dart
---

# Bug F — Edit Workout Log shows blank "No exercise logs for this day"

## Symptom

Founder completed today's morning workout (5 exercises: Leg Extension, Barbell Back Squat, Jump Rope, Leg Curl Lying, Handstand Hold) via active-workout flow on 2026-05-11. Cloud `workout_log_exercises` has all 5 rows with `completed_at = 2026-05-11 05:19:43 UTC` (= 10:49 IST). User tapped "Edit Logs" → sheet showed "No exercise logs for this day" — blank.

## Root cause

Writer↔reader contract drift introduced when Test #6's WorkoutWriteService rewrite removed/never-set an `id` value field on the exlog map. The Hive key IS the id (`exlog_<dateStr>_<hash>`). Pre-Test-#6 readers iterated `box.toMap()` directly and saw the key. The post-Test-#6 indexed-path reader in `WorkoutRepository.getExerciseLogsForDate` returns value maps via `box.get(id)` and never re-injects the key.

```dart
// PRE-FIX:
final raw = _hive.workoutBox.get(id);  // id is Hive key from index
if (raw is Map) {
  logs.add(Map<String, dynamic>.from(raw));  // ← lost: no id on map
}
```

Then `EditWorkoutLogSheet._loadRows` filters every row by `log['id'] is String` — strips everything → empty list → blank UI.

Legacy fallback has a SECOND latent issue: filters by `map['type'] != 'exercise_log'`. WriteService never writes `type` either, so the fallback would also drop every row if ever invoked. Today the indexed path always has the data so the fallback never runs — but the contract is broken there too.

This is the canonical class CLAUDE.md §15 warns about: "field renames must update consumers in the same PR." Test #6 changed the map shape; 2 consumers were not updated. Bug latent since then; surfaced now because the founder happened to use the Edit sheet path for the first time on this APK build (other consumers — receipt, AI snapshot — iterate `box.toMap()` and key off the Hive key directly).

## Fix

`workout_repository.dart:getExerciseLogsForDate`:

```dart
// Indexed path:
final raw = _hive.workoutBox.get(id);
if (raw is Map) {
  final m = Map<String, dynamic>.from(raw);
  m['id'] = id;          // ← inject Hive key
  logs.add(m);
}

// Legacy fallback:
if (map['exercise_name'] == null) continue;  // ← was: type != 'exercise_log'
map['id'] = key;                              // ← inject Hive key
```

After this fix, EditWorkoutLogSheet's `where(log['id'] is String)` filter works correctly — every row passes through. Other consumers (receipt, AI snapshot) keep working unchanged because they never relied on the `id` field.

## Verification

- 4 source-grep tests pass:
  - Indexed path injects `m['id'] = id`
  - Fallback injects `map['id'] = key`
  - `map['type'] != 'exercise_log'` filter absent inside getExerciseLogsForDate body
  - Fallback uses `exercise_name == null` as discriminator

## Skills evolution

This is the SECOND Hive-field-name contract drift to surface from Test #6 (first was Test #8 receipt fields). Adding to skills-evolution sub-batch: a new gate script `scripts/check_id_injection_on_returned_maps.dart` that source-greps every `box.get(key)` in repository classes and asserts the returned map either (a) carries an `id` field set OR (b) the consumer iterates `box.toMap()` directly.

Codifying as `feedback_id_must_be_injected_on_get.md`.

## Related

- `feedback_source_of_truth_audit.md` — bug class codified after Test #12 same pattern
- audit-batch H-42 cohort 6 (commit `c0b9999`) — added telemetry that surfaced widget errors, but the Edit sheet's empty state isn't a widget error, so this wasn't captured by the new telemetry
