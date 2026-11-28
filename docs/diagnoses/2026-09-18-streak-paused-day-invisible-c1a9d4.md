---
bug_id: c1a9d4
date: 2026-09-18
batch: Task 1 (C1) — ai-coach-ux-tool-integrity spec 2026-09-18
status: fixed
blast_radius: account
symptom: |
  Tool-integrity audit (2026-09-18, spec docs/superpowers/specs/2026-09-18-ai-coach-ux-tool-integrity-design.md)
  found that a PAST scheduled day paused via the AI-coach pausePlan tool
  (WorkoutScheduleService.pauseRange) fell through to the streak walk's missed
  arm: it broke the streak and consumed a freeze. A user who pauses their plan
  for a vacation and returns comes back to a DEAD streak (or a burned freeze),
  even though pausing is a legitimate choice, not a miss. The same hole would
  apply to the `moved`/`dropped` terminal rows Task 2 introduces in place of
  rescheduleWeek's raw deletes (a deleted/terminal row must never fall to the
  missed arm — the raw-delete class was freeze-proof, worse than a miss).
concept: streaks
sot_registry_entry: streaks
writers:
  - { file: lib/core/services/workout_schedule_write_service.dart, method_or_widget: WorkoutScheduleWriteService.pauseRange, line: 140 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeRescheduleWeek (Task 2 — terminal rows), line: 707 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: WorkoutRepository._calculateStreak (decl :309; C1 skip), line: 372 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: WorkoutRepository.completionRateOverWindow (decl :440; C1 skip), line: 462 }
hive_key_prefix: schedule_
hive_key_formula: schedule_${istDateStr(date)} with status field (paused/moved/dropped)
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/streak_paused_day_not_missed_test.dart
ist_handling:
  - "Date keys already IST via istDateStr/formatDateKey — no new date surface; paused day exclusion uses the same keys as the existing walk."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — read-path change only; no new Hive key or cloud column.
forbidden_patterns_checked:
  - { pattern: "over-protection: a genuinely MISSED day (pending, no freeze) still breaks the streak", absent: false }
proposed_fix: |
  Add a shared invisible-status set to WorkoutRepository —
  invisibleScheduleStatuses = {paused, moved, dropped} + static
  isInvisibleToStreak(String?) — and skip such rows in BOTH the streak
  walk-back (after the `status == 'travel'` line) and completionRateOverWindow
  (after the `status == 'rest'` line). Same set, both readers, so the two can
  never drift apart again.
regression_test_planned:
  - test/contracts/streak_paused_day_not_missed_test.dart
impact_analysis: |
  Strictly a read-path narrowing: paused/moved/dropped rows stop counting as
  misses. No writer changes, no Hive key changes, no schema changes, no
  freeze-state changes (a paused day is skipped BEFORE the consume guard, so
  it can never consume). Rank completion-rate gates (TRAIN-38 etc.) become
  slightly EASIER for a user who pauses — that is the founder's explicit
  intent. Over-protection is guarded by the test's third case: a genuinely
  missed (pending) day with no freeze still breaks at streak=1.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "workout_repository.dart: isInvisibleToStreak helper + 2 skip guards; flutter analyze on the file: no issues." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Behavioral contract test seeds real schedule_* rows in workoutBox via the shared harness and asserts currentStreak()/completionRateOverWindow() read them correctly (4 tests, all green post-fix)." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change — paused status already round-trips through scheduled_workouts via the existing sync; no new column or table." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "No wire change: the fix alters only which local rows the streak/rate READERS consider; sync fan-out and cloud rows untouched." }
mutation_proven:
  mutated: "isInvisibleToStreak neutered to `=> false;` (semantically wrong, compiles clean)"
  result: "3 of 4 tests reddened — paused-day streak 2→1, moved/dropped streak 2→1, completionRate 0.5→0.333; the missed-day-still-breaks guard stayed GREEN, proving no over-protection in the mutated state either"
  confirmed_applied: "failures observed in the run output (not a compile error, not a zero-red run)"
---

## Summary

The 2026-09-18 tool-integrity audit (spec C1) found that a paused past
scheduled day was scored as a MISS by the streak walk-back and by
`completionRateOverWindow`. Founder rule: **paused = invisible**. A user
pausing their plan for two weeks returned to a broken streak and a burned
freeze — pausing is a choice, not a miss, and the old behaviour guaranteed a
dead streak after every vacation.

## Root cause

`_calculateStreak`'s status handling had arms for `travel` (invisible) and
`rest`/`off` types (invisible), then fell everything else through to
`completed` → not-completed-today → frozen → consume → **missed break**. A
row with `status='paused'` hit the missed arm: streak broke (or a freeze was
consumed). `completionRateOverWindow` similarly counted a paused day in the
DENOMINATOR but never the numerator, dragging the rank completion-rate gates
(TRAIN-38 SubLt ≥0.80) down for every paused week. Writer/reader drift by
omission: `pauseRange` (workout_schedule_write_service.dart:140) writes the status,
but the readers were never extended to know it.

## Fix

Shared static set + predicate on `WorkoutRepository`
(workout_repository.dart:111-125): `invisibleScheduleStatuses =
{'paused','moved','dropped'}` + `isInvisibleToStreak()`. Both readers skip
such rows — `_calculateStreak` right after the `travel` guard
(workout_repository.dart:372-373), `completionRateOverWindow` right after the
`rest` guard (workout_repository.dart:462-463). One set, two readers — the
streak walk and the rank rate can never drift apart on which statuses are
invisible. `moved`/`dropped` are in the set PROACTIVELY for Task 2's terminal
rows (rescheduleWeek's raw-delete replacement), so a reschedule can never
create a freeze-proof hole in the walk.

## Verification

- RED phase: paused-day test failed 2→1 (streak), moved/dropped 2→1, rate
  0.667→(expected 0.5); missed-day-still-breaks PASSED pre-fix (pins existing
  behaviour).
- GREEN phase: all 4 tests pass.
- Mutation-proof: `isInvisibleToStreak` neutered to `=> false;` — 3 tests
  reddened (2→1, 2→1, 0.5→0.333), missed-day guard stayed green. Mutation
  confirmed applied by the observed failures (semantically-wrong,
  compile-clean code). Reverted, all 4 green again.
- `flutter analyze lib/features/train/repositories/workout_repository.dart` —
  no issues.

## Plan deviation recorded here (implementer, 2026-09-18)

The plan's rate test seeded day-2 as `completed` while its own comments
require `1 completed / 2 counted = 0.5` (and "Pre-fix: 1/3 ≈ 0.33") —
arithmetically unreachable with two completed days (pre-fix actual was
0.667, post-fix 1.0). Corrected the SEED to `pending` (scheduled, not
completed) so the assertion measures exactly the plan's stated intent;
documented inline in the test with a PLAN-SEED CORRECTION comment.

SoT note: this batch's +20-line insert (the `isInvisibleToStreak` helper)
shifted sibling-method line ranges in workout_repository.dart; the SoT
parity gate flagged 3 stale `line_range`s (getWorkoutLogs /
getRecentWorkoutCompletionHours / totalLifetimeVolumeKg), re-pointed in this
same commit (Task 10 Step 2 pulled forward).

## Related bugs

- `9c3d7a` (2026-09-16 future-prediction-streak-zero-schedule-collapse) —
  sibling streak-walk fragility class.
- Task 2 (C2, same batch) — rescheduleWeek's raw deletes create the same
  invisible-hole class; the `moved`/`dropped` statuses this fix registers are
  the terminal rows Task 2 writes.
