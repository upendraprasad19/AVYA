---
bug_id: e8f4a3
date: 2026-09-18
batch: Task 2 (C2) — ai-coach-ux-tool-integrity spec 2026-09-18
status: fixed
blast_radius: account
symptom: |
  Tool-integrity audit (2026-09-18, spec docs/superpowers/specs/2026-09-18-ai-coach-ux-tool-integrity-design.md)
  found that `_executeRescheduleWeek`'s move path raw-deleted the source
  `schedule_<fromDate>` row after writing the destination (tool_dispatcher.dart:707-711),
  and the drop path raw-deleted too (:719). A raw delete creates a HOLE in the
  streak walk-back — the walker breaks unconditionally on a null row (freeze-proof,
  worse than a miss: diagnose c1a9d4's C1 fix registered `moved`/`dropped` as
  invisible statuses but nothing ever WROTE them). Raw deletes also never reach
  cloud — the destination upsert fans out, the source delete does not, so a
  restore resurrects the workout on BOTH dates (double-counted volume).
concept: streaks
sot_registry_entry: streaks
writers:
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeRescheduleWeek move path (terminal moved row) + drop path (terminal dropped row), line: 707 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: WorkoutWriteService.moveExerciseLogs (exlog re-key on move), line: 665 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: WorkoutRepository._calculateStreak (C1 skip arm — now live for moved/dropped), line: 372 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: WorkoutRepository.completionRateOverWindow (C1 skip arm — now live for moved/dropped), line: 462 }
hive_key_prefix: schedule_ and exlog_
hive_key_formula: schedule_${istDateStr(date)} keeps its row with status moved|dropped + moved_to|dropped_via; exlog_<date>_<uuid5[:8]> re-keyed to the destination date via WorkoutWriteService.exlogKey
sync_methods: []
restore_methods: []
cloud_table: scheduled_workouts
cloud_columns: []
contract_test_path: test/contracts/reschedule_week_terminal_row_test.dart
ist_handling:
  - "All date keys IST: source/destination DateTime built via the dispatcher's existing _utcDateFromIstDateStr (UTC-midnight round-trips through istDateStr); exlog re-key uses WorkoutWriteService.exlogKey which applies istDateStr internally."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Writes go through WorkoutWriteService.upsertScheduled (wrapUserScopedBox-guarded user box) with source: WriteSource.aiCoach — same guard as every other dispatcher write."
forbidden_patterns_checked:
  - { pattern: "over-protection: a day the user genuinely missed (pending, no freeze) still breaks the streak — c1a9d4's guard test pins this", absent: false }
  - { pattern: "no-op self-move duplication: the fromDate != toDate guard is preserved so a same-date move never double-writes", absent: false }
proposed_fix: |
  Replace both raw deletes with TERMINAL source rows written through
  WorkoutWriteService.upsertScheduled (cloud fan-out included):
    - move path: source row re-stamped status='moved', moved_to=<toDate>,
      moved_via='ai_coach', moved_at=<iso> — the fromDate != toDate guard is
      preserved. Then a new WorkoutWriteService.moveExerciseLogs helper (the
      canonical WriteService owns exlog keys — Gate 17 forbids hand-building
      them anywhere else, and the dispatcher must stay a router) re-keys partial
      exlog_<fromDate>_* rows onto the destination date (LOCAL-ONLY; the
      cloud exercise_logs residual is tracked on OI-174).
    - drop path: source row re-stamped status='dropped', dropped_via='ai_coach',
      dropped_at=<iso> — only when a source row exists (the snapshot phase
      already read it).
  The source snapshot phase (:656-666) runs BEFORE the loop, so the move path
  reuses its `from` snapshot for the terminal row — no second read, and the
  A->B + B->A clobber protection is unaffected.
regression_test_planned:
  - test/contracts/reschedule_week_terminal_row_test.dart
impact_analysis: |
  Write-path change only, inside the reschedule_week executor. The destination
  write is untouched; the source row goes from absent to a terminal row. Every
  reader of schedule_<date> that special-cases status already treats unknown
  statuses safely: the C1 skip arms (streak walk + completion rate) now become
  LIVE for moved/dropped (they were registered proactively in Task 1 but never
  written). The Train screen renders a moved/dropped row as a non-completed
  entry on a past date — same visual class as paused, which the founder
  already accepted as the correct terminal presentation. exlog re-keying moves
  partial logs with the day so a moved day keeps its logged exercises and the
  all-logged completion backstop still sees them on the destination date.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "tool_dispatcher.dart _executeRescheduleWeek move+drop paths rewritten to terminal rows + workout_write_service.dart moveExerciseLogs; flutter analyze on both touched files: zero warnings/zero new issues." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Behavioral contract test seeds schedule_<from>/schedule_<to>/exlog_<from>_<hash> rows in the real workoutBox via the shared harness, dispatches a real reschedule_week ToolIntent, and asserts the terminal-row/exlog re-key end state (pre-fix the source-row assertions fail with null)." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No schema change — schedule status is a free-form Hive field; no migration." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Terminal rows go through WorkoutWriteService.upsertScheduled, which fans out syncWorkoutData/pushSnapshot to cloud scheduled_workouts exactly like every other scheduled write; the raw deletes they replace had NO cloud path at all, so cloud coverage strictly improves. Cloud exlog tombstone residual for the moved-out date is tracked on OI-174 and deliberately not in this fix." }
mutation_proven:
  mutated: "Move path reverted to the pre-fix raw delete (box.delete('schedule_<fromDate>') in place of the terminal-row write) — semantically wrong, compiles clean"
  result: "Terminal-row assertions reddened: source row read back null where status 'moved' + moved_to were expected (the exact pre-fix defect). Reverted, all green."
  confirmed_applied: "failures observed in the run output (not a compile error, not a zero-red run)"
---

## Summary

The 2026-09-18 tool-integrity audit (spec C2) found that `reschedule_week`'s
executor destroyed the source `schedule_<date>` row with a raw Hive delete on
both the move and drop paths. Task 1 (C1, diagnose `c1a9d4`) already made the
streak walker and completion-rate reader skip `moved`/`dropped` terminal rows —
but nothing wrote them, and the raw delete was the WORSE outcome: a null row
breaks the streak walk unconditionally, freeze-proof, and never reaches cloud
so a restore resurrects the workout on both the old and new date.

## Root cause

Writer/reader drift by omission, second half of the C1 pair: C1 fixed the
READERS (they now know `moved`/`dropped`), but the WRITER
(`_executeRescheduleWeek`, tool_dispatcher.dart) still raw-deleted instead of
writing the terminal status the readers expect. The delete bypassed
WorkoutWriteService entirely — no `updated_at_ms` stamp, no sync fan-out, no
cloud tombstone.

## Fix

- **Move path:** the source row (already snapshotted before the loop) is
  re-stamped `status:'moved'`, `moved_to`, `moved_via:'ai_coach'`,
  `moved_at` and written through `upsertScheduled` with the existing
  `fromDate != toDate` guard preserved. A new `moveExerciseLogs` helper on
  WorkoutWriteService re-keys
  partial `exlog_<fromDate>_*` rows onto the destination date using the
  canonical `WorkoutWriteService.exlogKey` (UUID-v5 hash — H-16), so logged
  exercises travel with the day.
- **Drop path:** the source row is re-stamped `status:'dropped'`,
  `dropped_via:'ai_coach'`, `dropped_at` via `upsertScheduled`, only when a
  source row exists.

## Verification

- RED phase: pre-fix, the terminal-row assertions failed — source row null
  after the move (expected `status:'moved'` + `moved_to`), and the drop-path
  source row null (expected `status:'dropped'`). The destination + exlog
  re-key assertions behaved per the then-current code.
- GREEN phase: all tests pass post-fix.
- Mutation-proof: move path reverted to the raw delete — terminal-row
  assertions reddened on the null source row. Reverted, green.
- `flutter analyze` on the touched file: zero warnings.

## Plan deviation recorded here (implementer, 2026-09-18)

The plan's test sketch computed the re-keyed exlog key as
`exlog_<toDate>_<name.hashCode.toUnsigned(32).toRadixString(16)>`. The REAL
key contract is UUID-v5 (`WorkoutWriteService.exlogKey`, H-16 —
`name.hashCode` was replaced 2026-05-11 because it is not stable across
platforms/VMs and would fork duplicate logical entries on restore). The
implementation and test both use `exlogKey` — the plan text was written
against the dead pre-H-16 scheme.

## Related bugs

- `c1a9d4` (2026-09-18, Task 1/C1) — the reader half of this pair: the
  `invisibleScheduleStatuses` skip arms this fix's terminal rows feed.
- OI-174 — cloud exlog/schedule tombstone residual for the moved-out date
  (upsert fan-out covers the row; the cloud-side delete of the old date
  remains tracked there, unchanged by this fix).
