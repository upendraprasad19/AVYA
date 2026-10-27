---
bug_id: 2026-05-16-logpr-bypass
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.5.1
status: fixed
regression_test: test/contracts/tool_dispatcher_log_pr_uses_writeservice_test.dart
symptom: >-
  The AI coach `logPR` tool (one of 24 tools registered in
  `_shared/tools/registry.ts`) routes user-claimed PR attempts through the
  legacy `WorkoutRepository.logSetWithPrRescan` method instead of the
  canonical `WorkoutWriteService.logExercise`. The canonical writer enforces:
---

## Symptom

The AI coach `logPR` tool (one of 24 tools registered in `_shared/tools/registry.ts`) routes user-claimed PR attempts through the legacy `WorkoutRepository.logSetWithPrRescan` method instead of the canonical `WorkoutWriteService.logExercise`. The canonical writer enforces:

- Per-(date, exerciseName) mutex (workout_write_service.dart:85 `_acquireLock(lockKey)`).
- 60-second per-set dedup against existing rows on the exlog key (workout_write_service.dart:113-117).
- Stamping `workout_log_id` for receipt scoping (Test #12 / Task A-2).
- Batched cloud sync via `unawaited(SyncService.instance.syncWorkoutData())` + `pushSnapshot()`.
- Atomic PR rescan via `_rescanPrFor` (workout_write_service.dart:183, 300).

By bypassing the WriteService, the AI-coach-tool path skipped the mutex (race window for two near-simultaneous claims), the cross-set dedup (could write duplicate rows for the same effort), and missed coordinated invalidation.

## Root cause

The dispatcher was written before `WorkoutWriteService` existed (pre-Test-#6). `_executeLogSet` was migrated to the WriteService in Test #6 (visible at `tool_dispatcher.dart:312-318` with comment "Plan A A-11: route through WorkoutWriteService.logExercise"), but `_executeLogPR` was a sibling method that nobody moved.

`logSetWithPrRescan` (workout_repository.dart:1133) was also identified as ONE OF THE 3 ROGUE `exlog_*` key formulas in APK Test #16.1 / Bug A (commit a16c1a) — that fix routed the key construction through canonical `exlogKey(date, name)` but did NOT move the caller to the WriteService.

So this is the 8th writer/reader drift instance per `feedback_writer_reader_field_drift_recurring.md`:

1. Test #6 — receipt rendering field drift
2. Test #8 — coaching_notes vs coach_notes  (later instance)
3. Test #11 — sync fan-out drift (FoodLogNotifier vs NutritionWriteService)
4. Test #12 — formatDateKey IST vs UTC
5. Test #15.3 / Bug 1 — last_performance reads sum-not-first-set
6. Test #15.3 / Bug 6 — edit sheet reads sets_detail not sets
7. Test #16.1 / Bug A — 3 rogue exlog_* key formulas
8. **THIS ONE** — logPR tool bypassed WorkoutWriteService

## Fix

`lib/features/ai_coach/services/tool_dispatcher.dart` `_executeLogPR` method:

- **Before:** called `WorkoutRepository.instance.logSetWithPrRescan(exerciseId, exerciseName, weightKg, reps, sets: 1, date)`.
- **After:** calls `WorkoutWriteService.instance.logExercise(date, exerciseName, sets: [ExerciseSet(weightKg, reps, loggedAtMs: nowMs)], source: WriteSource.aiCoach)`.

PR detection still happens automatically — `WorkoutWriteService.logExercise:183` internally calls `_rescanPrFor` after writing the exlog row. Same `is_pr` semantics, canonical path.

## Verification

- New contract test: `test/contracts/tool_dispatcher_log_pr_uses_writeservice_test.dart` (4 sub-tests).
  - `dispatcher source file exists` ✓
  - `_executeLogPR method body uses WorkoutWriteService.instance.logExercise` ✓
  - `_executeLogPR method body does NOT call legacy logSetWithPrRescan` ✓
  - `_executeLogPR passes a single ExerciseSet` ✓
- Test result: 4/4 PASS (verified via `flutter test`).

## Follow-ups

- `WorkoutRepository.logSetWithPrRescan` itself remains in the codebase. Phase E.6 (WorkoutScheduleService refactor) will leave that method as dead-but-not-deleted; a sweep candidate for a future cleanup batch IF no other callers remain after the schedule-service refactor. Tracked but not in this batch's deletion list.

## Class lesson

When migrating one method on a class to a new canonical writer (`_executeLogSet` → WriteService in Test #6), sweep all sibling methods on the same class for the same pattern. The repo-pattern grep is fast — would have caught this 7 batches earlier.
