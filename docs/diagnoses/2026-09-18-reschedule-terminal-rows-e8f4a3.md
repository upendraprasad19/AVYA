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

## C1-REGRESSION ADDENDUM (2026-09-18, post-push-review)

The review-fix commit (display filter + planner skips via
`isInvisibleToStreak`) used the FULL {paused, moved, dropped} set on the
DISPLAY path. That silently removed PAUSED days from
`currentPhaseCompletionRate`'s denominator (getWeek → getScheduleForDate),
letting a paused week read as fully complete — pinned red by
`test/contracts/phase_adherence_rate_test.dart` ("paused workout counts to
total but is not done"), which reddened both pre-push full-suite runs
(5857 passed / this 1 failed, twice).

FIX: a narrower TERMINAL set `{moved, dropped}`
(`WorkoutScheduleReadService.terminalScheduleStatuses` /
`WorkoutRepository.isTerminalScheduleRow`) now guards the display filter
(getScheduleForDate), the swap auto-complete + ConcurrentEdit guards, the
injury planner and the reschedule planner. `paused` reverts to its PRE-BATCH
semantics everywhere outside the streak walk and the rank completion-rate
gate (where C1's founder rule keeps it invisible): paused = PENDING — never
absent, still protecting phase progression from a paused week reading 100%.

MUTATION: reverting getScheduleForDate's filter to the full
isInvisibleToStreak set reddens the new C1-regression pin ("a PAUSED row
reads PRESENT through getScheduleForDate") while the moved/dropped filter
tests stay green. Recorded in the batch retrospective.

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

## Review-fixes append (2026-09-18, C2 commit 9fec098d review round)

The review found the READER side of this fix was only half-wired: terminal
rows were WRITTEN but `getScheduleForDate` — the read path behind every
display surface — still returned them verbatim.

### Issue 1 (critical): a 'moved' row for TODAY rendered a live Start CTA

- **Writer/reader by file:line:** writer
  `tool_dispatcher._executeRescheduleWeek → WorkoutWriteService.upsertScheduled`
  (terminal stamp, tool_dispatcher.dart:717-727 / 749-759); reader
  `WorkoutScheduleReadService.getScheduleForDate` (workout_schedule_read_service.dart,
  pre-fix :875-899 — only special-cased `completed`) consumed by
  `todayWorkoutProvider` (home_provider.dart:518-527) →
  `home_screen._buildTodayRow` (:789-858, branches only on
  isRestDay/isCompleted, so `moved` fell through to the planned-workout
  render).
- **Fix:** the canonical invisibility predicate
  (`invisibleScheduleStatuses` / `isInvisibleToStreak`) MOVED to
  `WorkoutScheduleReadService` (core, next to the read path that now enforces
  it — avoids a core→features import cycle); `WorkoutRepository`'s statics
  (C1 streak walk + completion rate, tool_dispatcher citation) DELEGATE to it,
  API unchanged. `getScheduleForDate` now filters invisible statuses (terminal
  rows read ABSENT); a new RAW getter `getScheduleRowForDate` serves
  audit/restore callers that need every row.
- **Display readers swept** (all route through `getScheduleForDate`, so the
  one filter covers every one of them): `todayWorkoutProvider` (Home Today
  card), `CalendarWeekNotifier` + `WeeklyCalendar` (Home week strip),
  `getCurrentCalendarWeek` (week-strip snapshot), `getWeek` (train week
  renderer, `week_selector` current-week chips, phase completion rate),
  `holdWeeks` / `holdWeekSessionProgress` / `hold_chip_group` rows,
  `workoutDayForDate` (the START gate — hero cards), `swap_sheet`
  (source/target day labels + 3-rest-day simulation), `swap_service`
  (`isTravelDay` — 'travel' is not an invisible status, unaffected;
  `_simulateSwap` — a moved day now simulates as rest, which is correct:
  the day is empty), `ai_coach_provider` completion check (checks
  'completed' only). Dev `simulation_service` too.
- **Readers verified RAW-safe (deliberately NOT filtered):**
  `sync_workout.dart` restore paths read `workoutBox` keys directly (never
  through `getScheduleForDate`) — untouched. `week_selector._toPastPhases`
  reads `pastPhaseBlocks` rows strictly BEFORE `plan_start_date` — reschedule
  never writes there. `ai_snapshot_builder` raw reads carry `status` verbatim
  in the payload, so the coach sees the terminal status honestly. The streak
  walk + completion rate (C1) iterate raw keys and apply
  `isInvisibleToStreak` themselves — unchanged.
- **Same-class leaks found and fixed in the sweep** (raw `schedule_` readers
  that would ACT on a terminal row as if live):
  `tool_dispatcher._maybeCompleteScheduledDay` would auto-complete a moved
  row (stamping `completed` over the terminal stamp — resurrecting the
  workout on the old date + streak credit) — guarded;
  `tool_dispatcher._executeSwapExercise` would edit exercises inside a
  terminal row — now throws `ConcurrentEditException`;
  `injury_swap_planner.plan` would propose substitutes from a terminal
  row's exercises — skipped.

### Issue 2 (high): planner re-planned terminal rows on a second reschedule

- **Writer/reader by file:line:** writer `reschedule_week` executor (terminal
  stamps above); reader `RescheduleWeekPlanner.plan`
  (reschedule_week_planner.dart pre-fix :100-113 first pass, :131-132 second
  pass — only `completed`/`paused` protected). Second pass relocated/dropped
  the terminal row onto a free available day.
- **Fix:** both passes skip `WorkoutRepository.isInvisibleToStreak` statuses
  entirely (import direction ai_coach→train/repositories has precedent:
  `pattern_detector.dart:2`, `ai_snapshot_builder.dart:32`). The terminal row
  neither appears in the plan nor occupies an available-day slot; the same
  week's LIVE rows plan exactly as before.

### Verification (TDD + mutation)

- New tests: `test/contracts/terminal_row_display_read_path_test.dart`
  (4 behavioral: moved-TODAY reads absent via `getScheduleForDate` +
  `workoutDayForDate`; dropped row in the current week reads absent per-day
  and renders as the `none` placeholder in `getCurrentCalendarWeek`;
  over-filter guard — completed rows still read through; coach `log_set` on a
  moved day leaves the terminal row untouched) + 2 planner tests in
  `test/contracts/reschedule_week_terminal_row_test.dart` (moved + dropped
  rows never re-planned; live planned row still kept; free slot not occupied).
- **Mutation 1 (display):** commenting out the `isInvisibleToStreak` filter
  inside `getScheduleForDate` reddened exactly the 2 filter tests
  (moved-TODAY + dropped-week); the over-filter guard and the log_set guard
  stayed green (correct — they pin different code). Reverted, green.
- **Mutation 2 (planner):** removing BOTH `isInvisibleToStreak` skips (first
  + second pass — together they reproduce the pre-fix behavior) reddened
  BOTH planner tests. Reverted, green. Neutering only the FIRST pass alone
  left the planner tests green — the second pass's skip does the protective
  work for off-available-day rows (which is where a terminal row always sits,
  since the destination day is the one that is available); both skips are
  load-bearing together, recorded so nobody "simplifies" one away.
- Full new+existing terminal/streak/reschedule/swap/hold test set green
  (reschedule_week_terminal_row, terminal_row_display_read_path,
  dispatch_reschedule_pause, dismiss_card_terminal_state,
  hold_display_read_path, today_card_vs_calendar_strip_same_source,
  coach_derived_completion, coach_completion_prompt,
  derive_only_tool_surface, workout_write_service/, streak set,
  swap set, week_selector). `flutter analyze lib/`: zero warnings/errors in
  touched files (45 pre-existing infos elsewhere, none in touched files).

### Trivial doc fix included

`lib/features/train/CLAUDE.md:55` documented the dead
`exerciseName.hashCode` exlog key scheme; corrected to the canonical
`WorkoutWriteService.exlogKey` UUID-v5 form (H-16).

## Review round 1 append (2026-09-18, 10 findings — all fixed in this batch)

Writer/reader pairs named per finding; every fix landed with a behavioral
regression test + a mutation proof (what was mutated → which tests reddened;
all mutations compiled clean and were verified applied by reading the red
output, not just the exit code).

### F1 (HIGH) — moveExerciseLogs never maintained exercise_log_index_<date>

- **Writer/reader:** writer
  `WorkoutWriteService.moveExerciseLogs` (workout_write_service.dart, raw
  `box.put` re-key); reader
  `WorkoutReadService.exerciseLogsForIstDate` (workout_read_service.dart:263)
  — INDEX-FIRST, early-returns on a resolvable non-empty destination index.
  A date that already had logs therefore never saw the moved rows, and the
  source date's index kept dangling keys.
- **Fix:** after each re-key, the new key is appended to
  `exercise_log_index_<toDate>` via the existing `addToExlogIndex`, and the
  old key removed from `exercise_log_index_<fromDate>` via a NEW private
  `_removeFromExlogIndex` (the union helpers never remove — the removal
  mutation belongs INSIDE the writer, not in a read helper; CQRS).
- **Test:** reschedule_week_terminal_row_test "move onto a date that already
  has logs" — seeds BOTH rows + index entries, asserts the canonical read
  returns BOTH rows and the source index drops the moved key.
- **MUTATION:** removed the two index-maintenance lines → the F1 test
  reddened on the canonical read (moved Bench Press invisible; source index
  kept the dangling key). Reverted, green.

### F2 (HIGH) — restore timestamp-merge lacked a terminal-row arm

- **Writer/reader:** writer `SyncService._restoreScheduledWorkouts`
  (sync_workout.dart, the status merge); reader `schedule_<date>` (every
  schedule read). Local 'moved'/'dropped' + cloud 'planned' fell to the
  cloud-authoritative arm → the restore RESURRECTED the moved-away workout.
- **Fix:** symmetric arm —
  `WorkoutScheduleReadService.isTerminalScheduleRow(localStatus) &&
  cloudStatus == 'planned'` → keep local (`mergedStatus = localStatus`).
  Terminal metadata survives via the `...existingMap` spread.
- **Test:** NEW behavioral `test/sync/restore_terminal_row_merge_test.dart`
  — runs the REAL merge path via a new `@visibleForTesting
  restoreScheduledWorkoutsForTest` seam (preFetched rows, no Supabase).
  Local moved + cloud planned → stays moved; dropped variant; control
  (cloud completed still wins over local planned) stays green.
- **MUTATION:** removed the arm → both terminal tests reddened
  (status merged to 'planned'), the control stayed green. Reverted, green.

### F3 (MED) — move collided: raw put OVERWROTE a same-exercise destination row

- **Fix:** destination existing → MERGE: moved row's `sets[]` appended to
  the existing row's sets; existing row's `workout_log_id` kept; the
  set-derived aggregates (`set_number`/`reps_completed`/`weight_kg`/
  `volume_kg`) recomputed from the merged list to logExercise's own
  derived-fields contract — stale aggregates beside a longer `sets[]`
  would be the exact writer/reader drift class this fix exists to kill.
  (Deviation from the finding's "recompute nothing else": documented here
  — recomputing the four aggregates is required for row self-consistency;
  no dedup/logging-type/PR machinery is re-run.)
- **Test:** "move collision" — merged row has 3 sets, set_number 3,
  recomputed reps/weight/volume, keeps `wlog_dest_session`.
- **MUTATION:** replaced the merge branch with the pre-fix overwrite →
  the test reddened (and, because the overwritten row kept the SOURCE
  `date`, the loop re-matched and deleted the destination row too — the
  overwrite bug class is worse than lossless overwrite). Reverted, green.

### F4 (MED) — moved rows carried the SOURCE workout_log_id

- **Fix:** re-stamp `workout_log_id = wlogKey(<toDate>)` when the row
  carries an id (restore-shaped legacy rows may not).
- **Test:** part (c) of the F1 test.
- **MUTATION:** removed the re-stamp → the assertion reddened
  (expected `wlog_2026-09-19`). Reverted, green.

### F5 (MED) — swap sheet dead-end on non-planned days

- **Writer/reader:** reader `CoachSwapSheet._loadToday`
  (swap_exercise_coach_sheet.dart) — no status guard, mirrors the raw+guard
  pattern of `log_workout_sheet.dart:94-100`. Completed → "Today's workout
  is already done — edit it from the Train screen."; moved/dropped/other →
  "No swappable workout scheduled today."
- **Test:** 2 widget tests in compass_redesign_test.dart (moved + completed).
- **MUTATION:** guard disabled (`&& false`) → moved-day test reddened (the
  dead-end picker rendered). Reverted, green.

### F6 (LOW) — reschedule destination guard missed terminal rows

- **Fix:** `WorkoutRepository.isTerminalScheduleRow(destStatus)` refusal
  with message `<date>: destination was rescheduled elsewhere`.
- **Test:** "move onto a TERMINAL destination is refused" (asserts the
  destination stays 'moved' and the source stays 'planned').
- **MUTATION:** refusal disabled → test reddened (success:true, pre-fix
  behavior). Reverted, green.

### F7 (LOW) — move/drop left a stale completion_prompt_<fromDate> card

- **Fix:** both paths call the existing `_resolveCompletionPromptIfPresent`
  (same resolve semantics as the auto-complete backstop — stamp
  `resolved_at` on the LOCAL-ONLY kind-tagged coachBox row).
- **Test:** move + drop prompt tests.
- **MUTATION:** both calls removed → both tests reddened (resolved_at
  null). Reverted, green.

### F8 (LOW) — scheduleForm TOMORROW labeled the source weekday, not today+1

- **Fix:** the destination chip whose DATE == today+1 is labeled TOMORROW.
- **Test:** TOMORROW must sit at index 1 of the destination Wrap while the
  source (today+2) chip keeps its weekday label.
- **MUTATION:** reverted to the `d.$1 == _choice` label → test reddened
  (expected 'TOMORROW', actual 'Saturday' at index 1). Reverted, green.

### F9 (LOW) — log sheet coerced non-numeric input

- **Fix:** `_ExerciseCapture.isComplete` additionally requires each field
  to PARSE (weight double.tryParse, reps/sets int.tryParse) — confirm
  disables on garbage instead of dispatching 0.0/0/1.
- **Test:** enter 'abc' in KG → LOG WORKOUT disabled (WardButton
  onPressed null), no intents; valid prefill stays enabled (control).
- **MUTATION:** reverted to non-empty-only → test reddened (button
  enabled with 'abc'). Reverted, green.

### F10 (LOW, pre-existing) — DateTime.parse(move.toDate!) double-shift trap

`_executeRescheduleWeek` built the destination DateTime with
`DateTime.parse` (device-local midnight — the Test #11.1 trap) while the
moved-out stamp 30 lines below used `_utcDateFromIstDateStr`. Fixed to
`_utcDateFromIstDateStr(move.toDate!) ?? DateTime.now()` (convention
alignment; `weekday` arithmetic unchanged). **No new test — timezone-
dependent; covered by the existing IST contract tests.** Stated here and
in the commit body per the batch instruction.

## Review round 2 append (2026-09-18, 2 material findings — both fixed)

### B1 (MED) — collision merge shrank restore-shaped rows

- **Writer/reader:** writer
  `WorkoutWriteService.moveExerciseLogs`'s collision-merge branch
  (workout_write_service.dart, round-1 code ~:748-772) recomputed
  `set_number`/`reps_completed`/`weight_kg`/`volume_kg` from
  `existingSets + movedSets`. But the restore writer
  (`sync_workout.dart` `_restoreExerciseLogs`, the d4e7c2 asymmetry
  documented in `lib/features/train/CLAUDE.md` hive_field_name_exlog)
  emits exlog rows with TOP-LEVEL AGGREGATES and NO `sets[]` when the
  `workout_log_sets` join is empty (sync_workout.dart ~:777/:803).
  Colliding a move into such a row recomputed DOWNWARD (set_number 3→1,
  reps 30→8, volume 720→480) — silent data loss on real user rows, the
  exact row shape `exlog_aggregate_read_behavioral_test.dart` documents.
- **Fix (preserve-don't-shrink):** each side of the merge contributes
  its sets-derived totals when it CARRIES `sets[]`, and its OWN
  top-level aggregates otherwise (`sideSetCount`/`sideReps`/
  `sideMaxWeight`/`sideVolume` local helpers in the merge branch).
  `set_number` = Σ side counts, `reps_completed` = Σ side reps,
  `weight_kg` = max of side maxima, `volume_kg` = Σ side volumes. When
  both sides carry `sets[]` this is numerically identical to the
  round-1 recompute from the merged list (pinned by the round-1
  collision test, unchanged). `sets[]` is only stamped when non-empty,
  so a both-sides-restore-shaped merge never grows an empty `sets[]`
  onto the surviving row.
- **Test:** reschedule_week_terminal_row_test.dart, round-2 group
  "move collision into a RESTORE-SHAPED destination row GROWS the
  aggregates" — restore-shaped existing (set_number 3 / reps 30 /
  weight 80 / volume 720, no `sets[]`) + sets-carrying moved row →
  asserts set_number 4, reps 38, weight 80.0 (max), volume 1200,
  `sets[]` length 1, destination wlog id kept.
- **MUTATION:** reverted the merge to the round-1 unconditional
  recompute from `mergedSets` (semantically wrong, compiles clean,
  verified applied by reading the red output) → the new test reddened
  `Expected: <4> Actual: <1>` — the exact shrinkage the finding
  describes. Reverted, green (25/25 across the two touched test files;
  62/62 across the full round-2 green set).

**Recorded deviation from the finding's concrete shape:** the sketch's
fallback for "moved row also lacks `sets[]`" said "keep existing
aggregates entirely". Implemented instead as the same per-side sum
(each restore-shaped side contributes its own aggregates). Rationale:
"keep existing entirely" would DELETE the moved row's contribution (the
moved row is consumed by the merge) — the same data-loss class B1
exists to kill, just one step later. The per-side sum is strictly
non-shrinking for the surviving row and lossless for the move, and
cannot double-count (the two rows are distinct workouts keyed by
different dates; restore keys rows by (date, name), so overlapping
aggregates cannot arise).

### B2 (LOW-MED) — swap sheet guard blocked paused days

- **Writer/reader:** reader `CoachSwapSheet._loadToday`
  (swap_exercise_coach_sheet.dart:84 round-1 guard `status != 'planned'`)
  refused PAUSED days, but the dispatcher explicitly keeps paused days
  swappable (tool_dispatcher.dart:263-268 — `_executeSwapExercise`
  guards TERMINAL rows + completed only; "a paused day stays swappable
  exactly as before this batch (paused = pending)"). The sheet was
  stricter than the executor it feeds — a paused day showed the
  dead-end empty state for a swap that would have executed fine.
- **Fix:** `paused` passes the guard (`status != 'planned' && status !=
  'paused'`); completed/moved/dropped/absent stay guarded verbatim, and
  the moved-day + completed-day widget tests are unchanged.
- **Test:** compass_redesign_test.dart, B2 group "paused day renders the
  picker and submits normally" — picker renders with the paused day's
  exercise (pre-fix: dead-end message) and the full two-step flow
  submits ONE reviewable `swap_exercise` intent.
- **MUTATION:** reverted the guard to `status != 'planned'` (compiles
  clean, verified applied) → the new test reddened (`SWAP WHICH
  EXERCISE?` found 0 — the dead-end empty state rendered instead).
  Reverted, green.

### Verification (round 2)

- `flutter analyze` on the four touched files: zero errors/warnings
  (3 pre-existing infos elsewhere, none introduced).
- Green set: reschedule_week_terminal_row_test.dart,
  phase_adherence_rate_test.dart, compass_redesign_test.dart,
  terminal_row_display_read_path_test.dart,
  exlog_aggregate_read_behavioral_test.dart — 62/62.
- docs/sot_registry.yaml `exercise_logs_read_path` moveExerciseLogs
  writer re-pointed (line_range 695-812 → 726-851 after the merge
  branch grew).
