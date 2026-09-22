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
contract_test_path: test/contracts/logged_sets_format_normalization_test.dart
regression_test_planned:
  - Write-time: swap exercise → log new sets → verify sets format normalized
  - Boot-time: existing mismatch → app startup → heal fires → verify normalization
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

Added helper method `_normalizeSetsByLoggingType` that clears incompatible fields
based on the resolved logging type before persisting.

**Part 2: Heal existing mismatched logs at boot**

Added `_healMismatchedExerciseLogs()` method in `auth_session_bootstrapper.dart`
that runs once at boot to normalize any existing exlog rows with mismatched
logging_type.

## Related

Recurrence of writer/reader-drift class (`feedback_writer_reader_field_drift_recurring.md`).
Prior bug 9b1e7a (`2026-09-15-swap-logging-type-outgoing-exercise-9b1e7a.md`)
targeted the exercise's `logging_type` field. This instance targets the **SET
VALUES format**. Same class (value read from wrong source), different semantic layer.
