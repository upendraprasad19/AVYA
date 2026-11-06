---
bug_id: a8f1c2
date: 2026-05-12
batch: APK Test #15.3
status: in_progress
symptom: "Active workout screen pre-fills REPS input with 85 on every set of Hanging Leg Raise (4 prescribed sets × 14 reps, bodyweight). 85 is the sum of the user's previous 7-set session [10,15,10,15,10,10,15]; weight_kg field similarly carries the max of the previous session's per-set weights instead of the first set's weight."
concept: last_performance_per_set_semantics
sot_registry_entry: exercise_log_writer_to_reader
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: logExercise (reps_completed = SUM of per-set reps), line: 134 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: logExercise (writes sets[] per-set array), line: 170 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: logExercise (writes reps_completed total), line: 172 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: logExercise (writes weight_kg as MAX), line: 173 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: _getLastPerformance (reads log['reps_completed'] as per-set value — BUG), line: 74 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: _getLastPerformance (reads log['weight_kg'] as per-set value — BUG), line: 73 }
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: _initControllers (pre-fills every set's reps controller), line: 1151 }
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: _initControllers (pre-fills every set's weight controller), line: 1160 }
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: build (LAST hint badge), line: 1626 }
  - { file: lib/features/train/widgets/expandable_day_card.dart, method_or_widget: build ("Last: NkG × R" line), line: 261 }
hive_key_prefix: exlog_
hive_key_formula: "'exlog_${istDateStr}_${hash(name)}'"
sync_methods: [syncWorkoutData]
restore_methods: [restoreWorkoutData]
cloud_table: workout_log_exercises
cloud_columns:
  - reps
  - weight_kg
  - set_number
contract_test_path: test/contracts/last_performance_per_set_contract_test.dart
ist_handling: []
provider_invalidations:
  - lastPerformanceProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - "log['reps_completed'] as per-set value"
  - "log['weight_kg'] as per-set value"
proposed_fix: |
  Reader-side semantic fix. The writer correctly stores both the
  aggregates (reps_completed = sum, weight_kg = max) AND the per-set
  array (sets[]). The reader was conflating the two.

  In `_getLastPerformance` (train_provider.dart), replace the bogus
  per-set read of `log['reps_completed']` and `log['weight_kg']` with
  a first-set lookup against `log['sets']`:

      final sets = log['sets'];
      int? lastReps;
      double? lastWeight;
      if (sets is List && sets.isNotEmpty) {
        final firstSet = sets.first;
        if (firstSet is Map) {
          lastReps = (firstSet['reps'] as num?)?.toInt();
          lastWeight = (firstSet['weight_kg'] as num?)?.toDouble();
        }
      }

  Legacy rows (pre-APK-Test-#6, before WorkoutWriteService) lack the
  `sets[]` array — fall through to null so UI shows empty input
  boxes instead of pre-filling a misleading aggregate.

  Per-set key shape `{weight_kg, reps, [duration_sec], logged_at_ms}`
  matches `ExerciseSet.toMap()` in `write_result.dart:95-100`.

  CLAUDE.md §15 Hive field-name contract previously pinned that
  `reps_completed` exists on `exlog_*` rows but did NOT pin the
  per-set vs aggregate semantics. The new contract test fills that
  gap — it asserts that the reader returns first-set values, not
  summed/max aggregates.
regression_test_planned:
  - test/contracts/last_performance_per_set_contract_test.dart
---

# Bug 1 (APK Test #15.3) — Hanging Leg Raise pre-fills 85 reps on every set

## Symptom

Founder on active workout screen for Hanging Leg Raise (4 sets prescribed × 14 reps, bodyweight). Every set's REPS input pre-fills `85` instead of either the prescribed `14` or empty. 85 is the SUM of the previous session's 7 sets `[10,15,10,15,10,10,15]`. The "LAST: 85 REPS" hint above the input is also nonsense — no one does 85 hanging leg raises in a single set.

The same class of bug afflicts `weight_kg`: stored as `MAX` across the previous session's sets, surfaced as a per-set pre-fill. Less absurd visually for bodyweight exercises (weight=0), but for `weight_reps` exercises like Bench Press, the heaviest set's weight would pre-fill every set's input, making warm-up sets impossible.

## Root cause

After APK Test #6 (2026-05-01) the `WorkoutWriteService` rewrite changed the **semantics** of two fields on `exlog_*` Hive entries:

- `reps_completed` — was per-set; became **SUM** of all sets' reps (`workout_write_service.dart:134`).
- `weight_kg` — was per-set; became **MAX** across all sets (`workout_write_service.dart:135-136`).

The writer also added the per-set array `sets[]` (`workout_write_service.dart:170`), which carries the truthy per-set values for downstream consumers.

The reader `_getLastPerformance` in `train_provider.dart` was not updated. It kept reading `log['reps_completed']` (now a sum) and `log['weight_kg']` (now a max) and treating them as per-set values. The UI consumer `active_workout_screen._initControllers` then dutifully pre-filled every set's input field with that value.

CLAUDE.md §15 "Hive field-name contract" sub-section enumerated the field NAMES (`reps_completed`, `weight_kg`, `sets[]`) but did NOT pin their per-set vs aggregate SEMANTICS — so the rename pre-flight check passed for ~11 days while the bug sat dormant.

## Fix

Replace the per-set read of `log['reps_completed']` / `log['weight_kg']` with a first-set lookup against `log['sets']`. Legacy rows without `sets[]` fall back to null (UI shows empty inputs). See `proposed_fix` above for the exact diff.

**Code-review follow-up (commit f6bf88e → this commit):** the sibling `lastSets` read in the same function had the SAME class of writer/reader drift. It was reading `log['sets_completed']`, but `WorkoutWriteService` normalizes incoming `sets_completed` → `set_number` (workout_write_service.dart:617-619) and the canonical write at line 171 only emits `set_number`. Modern rows had `lastSets == null` silently. Fixed by reading `set_number` first with `sets_completed` as legacy fallback. Same class as the primary `reps_completed`/`weight_kg` aggregate-vs-per-set drift — sibling fields needed sibling attention.

## Verification

- New contract test `test/contracts/last_performance_per_set_contract_test.dart` asserts:
  - Modern row with `sets: [{reps: 10, weight_kg: 0}, ...]` totaling 85 → `lastReps == 10`, `lastWeight == 0.0`.
  - Legacy row without `sets[]` → `lastReps == null`, `lastWeight == null`.
  - Empty `sets: []` → `lastReps == null`, `lastWeight == null` (sets.isNotEmpty guard).
  - `sets: [42, "junk"]` (non-map elements) → null (`first is Map` guard).
  - `sets: [{weight_kg: null, reps: null}]` → null (`as num?`?.toX() casts propagate null).
  - Modern row with `set_number: 7` → `lastSets == 7` (canonical reader path).
  - Legacy row with only `sets_completed: 4` → `lastSets == 4` (fallback path).
- Existing audit of LastPerformanceData consumers: `active_workout_screen.dart:1147,1610,1856` + `expandable_day_card.dart:217` all treat the values as per-set pre-fill / "LAST" hint. No consumer expects aggregates. Fix is reader-only.

## Related

- CLAUDE.md §19 will gain an entry: "Hanging Leg Raise pre-fills sum of last session's reps" → "Reader treated aggregate as per-set value. Always read per-set values from `log['sets'][0]`, never from top-level `reps_completed` / `weight_kg`."
- `feedback_source_of_truth_audit.md` — same class as the Test #8 receipt drift (`set_number` vs `sets_completed`). The writer→reader contract test gap continues to surface 11+ days after a WriteService rewrite.
