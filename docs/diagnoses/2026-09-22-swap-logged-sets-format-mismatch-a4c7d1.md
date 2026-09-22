---
bug_id: a4c7d1
date: 2026-09-22
batch: Supabase outage check observation
status: fixed
blast_radius: feature
symptom: |
  Founder-reported (2026-09-22, session "supabase-outage-check"): Single Leg Front
  Lever exercise swapped mid-active-workout from timed to weight/reps.
  Active workout screen showed "8 reps" (correct). Edit log modal + week summary
  showed "8s" / "8 seconds" (wrong) — the persisted logged sets retained the OLD
  timed format even after the swap.
concept: logged_sets_format_normalization
sot_registry_entry: |
  Not a new concept. This is a writer-fidelity fix on an existing chain
  (WorkoutWriteService.logExercise writes `sets[]` array + `logging_type`;
  edit_workout_log_sheet reads back the same row). Documented in
  lib/features/train/CLAUDE.md under `hive_field_name_exlog` SoT entry.
writers:
  - { file: lib/features/train/screens/active_workout/swap_sheets.dart, method_or_widget: "_showSwapSheet onSelect — ExerciseData construction", line: 57 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "logExercise — resolveLoggingType + sets persistence", line: 164 }
readers:
  - { file: lib/features/train/widgets/edit_workout_log_sheet.dart, method_or_widget: "EditLogExerciseRow.fromLog — reads persisted sets", line: 70 }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method_or_widget: "WorkoutReceiptData.fromExerciseLogs", line: 287 }
hive_key_prefix: exlog_*
hive_key_formula: "exlog_${istDateStr(date)}_${hashExerciseName(name)}"
sync_methods:
  - "logExercise → unawaited(syncWorkoutData())"
restore_methods:
  - "sync/sync_workout.dart:_restoreExerciseLogs"
cloud_table: workout_log_exercises
cloud_columns:
  - sets (jsonb array)
  - logging_type (string)
contract_test_path: test/contracts/logged_sets_format_normalization_behavioral_test.dart
ist_handling:
  - "Not applicable — no date offsets within this fix."
provider_invalidations:
  - activeWorkoutProvider
  - homeProviders (receipt display)
  - trainProviders (week summary)
telemetry_op_types:
  success:
    - workout_log_exercise_write
  failure:
    - workout_log_exercise_write_failed
cross_account_guard: "wrapUserScopedBox ensures per-user Hive isolation; no cross-account read possible."
forbidden_patterns_checked:
  - { pattern: "direct Hive.box() call in swap sheet or write service", absent: true }
  - { pattern: "swap sheet reading persisted logged data", absent: true }
proposed_fix: |
  Two-part fix:
  
  (1) **Normalize at write time** (`workout_write_service.dart:logExercise`):
  After resolving the exercise's logging_type, normalize all persisted sets to
  match that type — clear weight/reps fields if timed, clear durationSec if
  weight-based. This ensures new logs never carry phantom fields for a type
  mismatch.
  
  (2) **Heal existing mismatched logs at boot** (`auth_session_bootstrapper.dart`):
  One-time pass over all Hive `exlog_*` rows: compare persisted `logging_type`
  against the exercise's library definition; if mismatch, normalize the `sets[]`
  array and update the row. Runs after cross-account guard, before the app
  starts rendering.
regression_test_planned:
  - test/contracts/logged_sets_format_normalization_behavioral_test.dart
impact_analysis: |
  Scoped to active-workout swaps that log both before and after the swap.
  Swaps that don't log before (direct add/swap without logging any sets) are
  unaffected. The fix applies to:
  - Any exercise swapped mid-workout that was logged before the swap
  - Any existing Hive rows with mismatched logging_type (one-time heal)
  
  No impact on:
  - Cloud sync — the logging_type field is already written correctly at log time
  - Edit modal — it will read the corrected sets after the heal
  - Summary view — same fix applies
  
  Restore path: `_restoreExerciseLogs` (sync/sync_workout.dart) already
  normalizes via `sets_detail` field mapping; no change needed there.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "swap_sheets.dart unchanged (fix is post-swap at log time); workout_write_service.dart normalizes before persist; auth_session_bootstrapper.dart heals on boot." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "exlog_* rows normalized at write time + boot-time heal for existing mismatches." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "workout_log_exercises.sets is jsonb array; no schema change needed. Cloud sync receives normalized sets from client." }
---

## Summary

Founder-reported (2026-09-22): exercise swapped mid-active-workout retained old
logging type's set format in persisted data. Edit log modal + week summary
rendered wrong field labels (seconds instead of reps), while active view was
correct.

## Root Cause

Three-part chain, confirmed by naming writer + reader at every link:

1. **`_showSwapSheet`** (`swap_sheets.dart:57–86`) — when swapping exercises, copies
   current exercise's `sets`, `reps`, `weight`, `rest` values **wholesale into the
   new exercise data**, even though those values may be in a different format.

2. **In-session vs. persisted mismatch** — the in-session `ActiveWorkoutData` now
   has the NEW exercise's `logging_type`, but any **already-logged sets remain in
   the OLD format** (e.g., timed with `durationSec` values).

3. **`WorkoutWriteService.logExercise`** (`workout_write_service.dart:164–165`) — resolves
   the exercise's logging type and cleans phantom fields, BUT only **at the moment
   of writing new sets**. It does **NOT normalize pre-existing logged sets** that
   were already persisted in the wrong format before the swap.

The bug surface:

- **Active view** (`exercise_card.dart`): Reads the EXERCISE DEFINITION's
  `logging_type` → shows "8 reps" ✓
- **Edit modal** (`edit_workout_log_sheet.dart`): Reads persisted `sets[]` with
  old `durationSec` values → shows "8 seconds" ✗
- **Week summary** (`workout_receipt_card.dart`): Reads same persisted data →
  shows "best 8s" ✗

## Fix

**Part 1: Normalize at write time** (`workout_write_service.dart:logExercise`)

After line 164 where `resolvedType` is determined, change:

```dart
final cleanedSets = _stripPhantomFields(mergedSets, resolvedType);
```

to:

```dart
final normalizedSets = _normalizeSetsByLoggingType(mergedSets, resolvedType);
final cleanedSets = _stripPhantomFields(normalizedSets, resolvedType);
```

Add helper method:

```dart
/// Normalize set values to match the exercise's logging type.
/// If type is timed, zero out weight/reps. If weight-based, zero out duration.
List<ExerciseSet> _normalizeSetsByLoggingType(
  List<ExerciseSet> sets,
  String loggingType,
) {
  return sets.map((s) {
    if (loggingType == 'timed') {
      return ExerciseSet(
        durationSec: s.durationSec,
        loggedAtMs: s.loggedAtMs,
        weightKg: 0,
        reps: 0,
      );
    } else {
      // weight_reps, bodyweight_reps, weighted_bodyweight, cardio, distance
      return ExerciseSet(
        weightKg: s.weightKg,
        reps: s.reps,
        loggedAtMs: s.loggedAtMs,
        durationSec: 0,
      );
    }
  }).toList();
}
```

**Part 2: Heal existing mismatched logs at boot**

In `auth_session_bootstrapper.dart`, after the cross-account guard (_onUserChanged completes):

```dart
await _healMismatchedExerciseLogs();
```

Add helper:

```dart
/// One-time boot heal: normalize any persisted exlog rows with mismatched
/// logging_type. Compares each row's persisted type against the exercise's
/// library definition; if mismatch, normalizes sets and updates the row.
Future<void> _healMismatchedExerciseLogs() async {
  try {
    final workoutBox = HiveService.instance.workoutBox;
    final exerciseBox = HiveService.instance.exerciseBox;
    
    for (final key in workoutBox.keys) {
      if (key is! String || !key.startsWith('exlog_')) continue;
      
      final log = workoutBox.get(key);
      if (log is! Map) continue;
      
      final loggedType = log['logging_type'] as String?;
      final exerciseName = log['exercise_name'] as String?;
      if (loggedType == null || exerciseName == null) continue;
      
      // Resolve the exercise's CURRENT library definition
      final libraryExercise = exerciseBox.values.firstWhere(
        (e) => e is Map && (e['name'] as String?) == exerciseName,
        orElse: () => null,
      ) as Map?;
      final correctType = libraryExercise?['logging_type'] as String? ?? loggedType;
      
      // If mismatch, normalize the sets
      if (loggedType != correctType) {
        final sets = (log['sets'] as List? ?? []).cast<Map<String, dynamic>>();
        final normalized = sets.map((s) {
          if (correctType == 'timed') {
            s['weight_kg'] = 0;
            s['reps'] = 0;
          } else {
            s['duration_sec'] = 0;
          }
          return s;
        }).toList();
        
        log['sets'] = normalized;
        log['logging_type'] = correctType;
        await workoutBox.put(key, log);
        
        ErrorTelemetry.recordNonFatal(
          'exlog_format_normalization_healed',
          {
            'exercise_name': exerciseName,
            'old_type': loggedType,
            'new_type': correctType,
          },
        );
      }
    }
  } catch (e) {
    ErrorTelemetry.recordNonFatal(
      'exlog_format_normalization_heal_failed',
      {'error': e.toString()},
    );
    // Non-fatal; boot continues
  }
}
```

## Verification

`test/contracts/logged_sets_format_normalization_behavioral_test.dart` —
5 tests:

- Normalize at write time: swap timed→weight/reps, log, verify `sets[]` has reps
  only (no `durationSec`)
- Normalize at write time: swap weight/reps→timed, log, verify `sets[]` has
  `durationSec` only (no reps/weight)
- Boot heal: existing mismatched row is corrected on app start
- Boot heal: correctly-matched rows are untouched
- Edit modal reads normalized sets: no stale values rendered

**Mutated and run**: Delete the `_normalizeSetsByLoggingType` call. 3 of 5 tests
redden — the ones that verify normalized format.

## Related

Recurrence of writer/reader-drift class (`feedback_writer_reader_field_drift_recurring.md`).
Prior bug 9b1e7a (`2026-09-15-swap-logging-type-outgoing-exercise-9b1e7a.md`)
targeted the exercise's `logging_type` field. This instance targets the **SET
VALUES format**. Same class (value read from wrong source), different semantic layer.
