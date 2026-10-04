---
bug_id: a13a01
date: 2026-05-12
batch: APK Test #15.3
status: shipped
symptom: User asks AI coach "how was my workout today?" after partially completing a Pull-day session (logged 4 of 8 prescribed exercises — Lat Pulldown, Dumbbell Row, Hanging Leg Raise, Concentration Curl). Coach replied with the FULL planned 8-exercise list as if everything had been completed, because today_workout.exercises emits the schedule_<date> entry verbatim regardless of how many exlog_* rows exist for the day.
concept: today_workout_snapshot_reads_logged
sot_registry_entry: ai_snapshot_building
writers:
  - { file: lib/core/services/workout_schedule_service.dart, method: writeSchedule_planned_source, line: 1784 }
  - { file: lib/core/services/workout_write_service.dart, method: logExercise_logged_SoT, line: 170 }
readers:
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getTodayWorkout_violating_SoT, line: 1335 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getYesterdayWorkout_violating_SoT, line: 1349 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getThisWeekWorkouts_adjacent_correct_reader, line: 829 }
hive_key_prefix: "exlog_"
hive_key_formula: "'exercise_log_index_<istToday>' + 'exlog_<timestamp>_<hash>'"
sync_methods: ["SyncService.syncWorkoutData"]
restore_methods: ["SyncService._restoreExerciseLogs"]
cloud_table: "workout_log_exercises"
cloud_columns: ["exercise_id", "workout_log_id", "set_number", "reps", "weight_kg"]
contract_test_path: "test/contracts/today_workout_reads_logged_contract_test.dart"
ist_handling:
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, line: 1336, fn: _getTodayWorkout_istDateStr }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, line: 1354, fn: _getYesterdayWorkout_istDateStr }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "schedule\\[.exercises.\\]", absent: true }
  - { pattern: "exercise_log_index_", absent: false }
proposed_fix: "Replace _getTodayWorkout and _getYesterdayWorkout body to iterate exercise_log_index_<istDate> + read each exlog_* entry — same pattern as _getThisWeekWorkouts at line 829-834 which already reads exlog_* rows correctly. Preserve schedule_<date>'s type and status fields (the model still wants type=PULL_A / status=completed) but replace planned exercises[] with logged exercises[]. Empty list when no logs (no plan fallback per founder direction 2026-05-12 Option A — no skipped-X coaching). Each exercise entry exposes: name, sets count, reps_total, top_set_weight_kg, is_pr, logging_type. Symmetric fix to both today + yesterday paths."
regression_test_planned: ["test/contracts/today_workout_reads_logged_contract_test.dart"]
---

# Bug a13a01 — today_workout Reads Planned Schedule, Not Logged Exercises

## Symptom

Founder partially completed a Pull-day session (4 of the 8 prescribed exercises:
Lat Pulldown, Dumbbell Row, Hanging Leg Raise, Concentration Curl). Asked the
AI coach in chat: *"how was my workout today?"* The coach responded with the
FULL planned 8-exercise list — including 4 exercises the user had NOT done —
phrased as if everything had been completed. The snapshot field
`today_workout.exercises` carried the planned 8-item array; Gemini read it
verbatim and described all 8 back to the user.

## Writers

**Planned source (the data the bug emits):**
`WorkoutScheduleService.generateSchedule(...)` →
`workoutBox.put('schedule_<date>', newEntry)` at
`lib/core/services/workout_schedule_service.dart:1784`. Writes `exercises[]`
as the FULL planned session at schedule-generation time (phase rollout, day
rollover, plan regen). `status` flips between `'scheduled' → 'in_progress' →
'completed'` as the user progresses; `exercises[]` is never mutated post-
generation. The planned list stays the full 8 even if the user only logs 4.

**Logged source (the correct SoT — what should drive snapshot):**
`WorkoutWriteService.logExercise(...)` at
`lib/core/services/workout_write_service.dart:170`. Writes one `exlog_*`
row per completed exercise + maintains `exercise_log_index_<istDate>` for
O(1) date-keyed retrieval. Exactly N entries when the user completes N
exercises. This is the canonical post-Test-#6 single-writer-source for
workout logs (CLAUDE.md §15 bullet 1: `WorkoutReceiptData.fromExerciseLogs`
is the only sanctioned reader).

## Readers

**Bug origin (violating SoT):**
`AiCoachRepository._getTodayWorkout()` at
`lib/features/ai_coach/repositories/ai_coach_repository.dart:1335-1344`.
Reads `workoutBox.get('schedule_$today')` and emits the planned `exercises[]`
verbatim:

```dart
return {
  'type': (schedule['type'] ?? schedule['workout_name'] ?? 'UNKNOWN') as String,
  'status': (schedule['status'] ?? 'pending') as String,
  'exercises': (schedule['exercises'] as List?) ?? const [],
};
```

Symmetric defect at `_getYesterdayWorkout` line 1349 (same code shape; omits
`exercises` from return but inherits the same planned-source thinking).

**Adjacent correct reader (the pattern to replicate):**
`AiCoachRepository._getThisWeekWorkouts()` at line 829-834. After the
Test #8 / Theme D drift fix, this method iterates `workoutBox.toMap()`,
filters by Hive key prefix `exlog_`, and emits `today_exercises[]` from the
LOGGED rows. Capped at 5 names. Already lives in the same file but has a
narrower scope (week-level summary, not per-day detail).

## Root Cause

The Test #8 / Theme D field-rename drift audit (commit `1cbc78e` 2026-05-03)
swept `_getMealsToday`, `_getNutritionTrend7d`, `_getThisWeekWorkouts`, and
`_getPersonalRecords` for missing-`type`-field drift. That audit was triggered
by the WorkoutWriteService field rename (`sets_completed` → `set_number`) —
a Hive-field-name-rename signal. `_getTodayWorkout` and `_getYesterdayWorkout`
were introduced LATER (APK Test #4 / A4, ~2026-04-27) and read from a
different Hive box prefix (`schedule_*`, not `exlog_*` / `nlog_*`). The
drift audit was field-rename-shaped — it did not surface
structural-plan-vs-logged-source-of-truth mismatches because there was no
field rename to detect.

The defect is structural: the reader picks the planned source when the
logged source is the correct SoT for "what was actually done today."
Gemini's prompt says "use today_workout to describe what the user did" —
the reader contractually returns "what the user planned to do."

## Prior Fix History

- **Test #8 / Theme D / commit `1cbc78e` (2026-05-03):** field-rename drift
  audit. Closed 4 readers (`_getMealsToday`, `_getNutritionTrend7d`,
  `_getThisWeekWorkouts`, `_getPersonalRecords`). Did not touch
  `_getTodayWorkout` / `_getYesterdayWorkout` (no field-rename trigger).
- **Test #11.1 (2026-05-05):** `istDateStr(istNow())` double-shift fix
  touched both `_getTodayWorkout` and `_getYesterdayWorkout` for IST
  correctness but preserved the planned-source bug.

## Fix (Option A — locked with founder 2026-05-12)

`today_workout.exercises` returns only what was actually logged. No plan
fallback. No "you skipped X" coaching for now (deferred to a future batch
that may add a separate `skipped_today` snapshot key without changing
`today_workout` semantics).

Replace `_getTodayWorkout` body to iterate `exercise_log_index_<istToday>`
+ read each `exlog_*` row. Preserve `type` + `status` from the
`schedule_<date>` entry (model still benefits from `type=PULL_A` /
`status=completed`) but rebuild `exercises[]` from logged rows. Each
exercise exposes: `name`, `sets` (count), `reps_total` (sum across sets),
`top_set_weight_kg` (max across sets), `is_pr`, `logging_type`. Empty list
when no logs — no fallback to the planned list. Apply the same fix
symmetrically to `_getYesterdayWorkout`.

## Regression Test

`test/contracts/today_workout_reads_logged_contract_test.dart` — three tests
driving the production `AiCoachRepository.instance.buildAiContext()` end-to-end:
1. Partial-completion scenario: 8 planned, 4 logged → `exercises.length == 4`,
   names match logged set, `is_pr` propagates, `sets` count from exlog.
2. No-logs scenario: schedule exists but `exercise_log_index_*` absent →
   `exercises == []`, `status == 'scheduled'` preserved.
3. Symmetric `_getYesterdayWorkout` scenario: 5 planned, 2 logged → 2
   exercises returned, in logged order.
