---
bug_id: d83505
date: 2026-09-29
batch: schedule-status-single-writer
status: fixed
blast_radius: feature
symptom: |
  Founder-reported (screenshot, 2026-09-29): a workout completed on 2026-09-28
  (Monday, "Calisthenics Day", logged via the app that same morning) rendered
  as NOT DONE on the Train tab on 2026-09-29. Founder asked to investigate
  only (no build), check the live DB, and asked whether this connects to the
  just-shipped reps/secs-invalidation fixes.

  Live verification (2026-09-29, before any repair):
    scheduled_workouts: status='planned', completed_at=null,
      template_id='977963e0-5887-49a4-b813-c93f0aa4711c' (user_id
      d7a67a37-0b05-4f0a-b13c-388bff3cb59b, scheduled_date=2026-09-28).
    user_progress.plan_json->schedules->schedule_2026-09-28: status='planned',
      completed_at=null, completed_at_ms=1790568319994, completed_via='app',
      source='cloud_restore', template_id='tmpl_3c001e68', exercises intact
      (3 real logged exercises + warmup/cooldown).

  The `source: 'cloud_restore'` stamp and the intact completed_at_ms/
  completed_via alongside a demoted status is the exact fingerprint of a
  RESTORE MERGE that kept the completion evidence but overwrote the status
  field — not a fresh write, not a delete, not a different bug class.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: "markCompleted -- the live completion writer, sets status+completed_at_ms+completed_via, never the legacy ISO completed_at on a schedule row", line: 492 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreScheduledWorkouts -- timestamp-aware restore-merge writer, the guard that was dead 2026-05-10 to 2026-09-27", line: 2238 }
  - { file: lib/core/services/sync/schedule_completion_time.dart, method_or_widget: "scheduledCompletedAtIso -- the Task 14 resolver _restoreScheduledWorkouts now calls instead of reading completed_at directly", line: 47 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: todayWorkoutProvider, line: 531 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: workoutDayForDate, line: 632 }
  - { file: lib/features/home/widgets/weekly_calendar.dart, method_or_widget: "WeeklyCalendar -- isCompleted = status == 'completed'", line: 62 }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods:
  - SyncService._syncScheduledWorkouts
restore_methods:
  - SyncService._restoreScheduledWorkouts
cloud_table: "scheduled_workouts (relational, server-queryable) and user_progress.plan_json (JSONB client-restore mirror) -- both independently corrupted by the same restore pass and both independently repaired live in this batch"
cloud_columns:
  - status
  - completed_at
  - scheduled_date
contract_test_path: test/contracts/sync_schedule_completion_payload_hash_index_writer_to_reader_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 88, fn: istDateStr }
  - { file: lib/core/services/sync/schedule_completion_time.dart, line: 47, fn: scheduledCompletedAtIso }
provider_invalidations:
  - todayWorkoutProvider
  - calendarWeekProvider
  - currentPlanProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a -- wrapUserScopedBox ensures per-user Hive isolation on the client; the live-prod repair in this batch was scoped by an explicit user_id WHERE clause, verified before and after against that one account only."
forbidden_patterns_checked:
  - { pattern: "existingMap['completed_at'] read directly in _restoreScheduledWorkouts (the pre-Task-14 shape)", absent: true }
proposed_fix: |
  No NEW client/server code change in this batch -- the actual code defect
  was already fixed on main by an EARLIER, unrelated commit (ebddb44c,
  2026-09-27, "fix(sync): resolve the real workout-completion time, never
  now()", Task 14 of day-swapper-sync-load, closes-diagnose f4c7a9). That
  commit replaced _restoreScheduledWorkouts's direct
  `existingMap['completed_at']` read with
  `ScheduleCompletionTime.scheduledCompletedAtIso(existingMap)`, which falls
  back to `completed_at_ms` when the legacy ISO field is absent -- exactly
  the fix this recurrence would otherwise have proposed. Confirmed via
  `git log -S` + `git merge-base --is-ancestor` that ebddb44c is already an
  ancestor of this worktree's HEAD.

  This batch's actual contribution, three parts:

  1. **SoT registry correction** (docs/sot_registry.yaml,
     workout_completion_status): the writers list cited
     `workout_schedule_service.dart markCompleted` -- a THIN SHIM whose real
     target, `WorkoutScheduleWriteService.markCompleted`
     (workout_schedule_write_service.dart:73), turns out to have ZERO live
     callers (verified via `grep -rn markWorkoutCompleted lib/` -- the only
     hits are the dead definition chain and a comment in train_provider.dart
     documenting its own replacement). The registry never listed
     `_restoreScheduledWorkouts` as a writer at all, despite it being the
     one that actually corrupted this row. `behavioral_test_path` pointed at
     a 100%-source-grep file
     (test/contracts/workout_completion_status_writer_to_reader_test.dart)
     even though genuine behavioral coverage already existed under a
     DIFFERENT registered concept
     (sync_schedule_completion_payload_hash_index). Fixed: writers list now
     names the real live writer + the restore-merge writer with accurate
     notes, and behavioral_test_path points at the canonical Task-14
     behavioral test.

  2. **Supplementary behavioral test**
     (test/sync/restore_terminal_row_merge_test.dart, new group "F1"):
     the existing Task-14 test proves `status` survives; this adds
     assertions that `completed_at_ms` and `completed_via` survive the
     `...existingMap` spread untouched, and that the legacy `completed_at`
     field gets backfilled by the merge (a side effect of the fix nothing
     previously asserted). Mutation-proven against the exact pre-Task-14
     derivation (see regression_test_planned).

  3. **Live-prod data repair**, founder-authorized ("Ok confirmed") per
     CLAUDE.md §4.3's "live prod apply needs its own explicit go": Task 14
     stops the corruption for FUTURE restores but does not retroactively
     heal rows already corrupted before it landed. Repaired both cloud
     representations for user_id d7a67a37-0b05-4f0a-b13c-388bff3cb59b,
     scheduled_date 2026-09-28: scheduled_workouts.status -> 'completed' +
     completed_at derived from the surviving completed_at_ms
     (1790568319994 -> 2026-09-28T04:05:19Z UTC / 2026-09-28 09:35 IST);
     user_progress.plan_json->schedules->schedule_2026-09-28.status ->
     'completed' + completed_at backfilled the same way, every other field
     (completed_at_ms, completed_via, exercises, template_id) left
     untouched. Verified via RETURNING on both UPDATEs (see Fix section).
     The next Hive restore on the founder's device will now read
     cloud-authoritative 'completed' for this date; no local repair is
     needed separately since the client's own restore logic (once it runs
     on a build carrying Task 14) is cloud-consistent again.
regression_test_planned: |
  test/sync/restore_terminal_row_merge_test.dart, new group "F1 (original
  d9b2c5 arm)": seeds a local schedule_2026-09-28-shaped row with
  status='completed' via completed_at_ms ONLY (no legacy completed_at,
  matching markCompleted's real write shape), stubs a stale cloud
  status='planned' row for the same date, runs the real restore path via
  SyncService.instance.restoreScheduledWorkoutsForTest, and asserts the
  merged row keeps status='completed', completed_at_ms and completed_via
  survive untouched, and the legacy completed_at field is backfilled.

  Mutation-proven (2026-09-29): reverted
  lib/core/services/sync/sync_workout.dart's
  `ScheduleCompletionTime.scheduledCompletedAtIso(existingMap)` call to the
  exact pre-Task-14 shape (`existingMap['completed_at'] as String?`), ran
  the full test file -- the new F1 test went RED (Expected: 'completed',
  Actual: 'planned') while the 3 pre-existing F2 tests in the same file
  stayed GREEN (confirming the mutation is scoped correctly and not merely
  breaking compilation). Confirmed the mutation was actually applied via
  `grep -c` before running (1 hit). Reverted; re-ran; all 4 tests green
  again; `git diff` on the file confirmed a clean revert (0 lines).
impact_analysis: |
  Scope of the ORIGINAL defect (already fixed on main since 2026-09-27,
  ebddb44c): any local completion recorded via completed_at_ms only (i.e.
  every completion made by the live markCompleted writer, which is to say
  every real completion in this app's history -- see writers above) was
  vulnerable to demotion by ANY stale cloud 'planned'/'rest' row arriving on
  a subsequent restore, for the full window 2026-05-10 (d9b2c5, when the
  guard was introduced) to 2026-09-27 (ebddb44c, when its derivation was
  fixed). The false-confidence mechanism: the only tests naming this guard
  during that whole window (T3 in
  test/contracts/logout_login_round_trip_test.dart,
  test/contracts/restore_non_destructive_test.dart) are source-greps on the
  conditional's literal text, which the eventual fix does not change --
  so none of them ever caught it. The fix that eventually landed was found
  via a completely unrelated live-timestamp audit (spec §1.6 of the
  day-swapper-sync-load plan, investigating WRONG COMPLETION TIMESTAMPS, not
  wrong statuses) and repaired this dead branch only as a side effect of
  sharing the same root cause (completed_at ISO never set on a schedule
  row). See the debugging skill catalog entry this batch appends (§5
  self-evolution) for the generalized lesson.

  Scope of what THIS batch found/fixed: the founder's specific 2026-09-28
  row is the only known currently-corrupted instance (this is the founder's
  own account, and it surfaced from a direct founder report, not a sweep --
  no cross-account sweep for other similarly-corrupted rows was run in this
  batch; if warranted, a live query counting scheduled_workouts rows with
  status='planned' but a NEWER completed-shaped wlog_<date>/exlog_<date>
  entry for the same date+user would find any others, but is out of scope
  here since it wasn't asked for and no other report exists).

  No impact on: any restore that has always been correctly cloud-wins
  (local genuinely still planned) or correctly local-wins via the TERMINAL
  (moved/dropped) arm added later (test/sync/restore_terminal_row_merge_test.dart
  group F2, unaffected by this batch). No further APK/build action is
  required by this batch -- the code fix is already on main; this batch is
  registry + test + data-repair only.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "The code fix (ScheduleCompletionTime.scheduledCompletedAtIso call site in _restoreScheduledWorkouts, sync_workout.dart:2337-2338) was verified ALREADY PRESENT on this worktree's HEAD via direct Read, and confirmed via `git merge-base --is-ancestor ebddb44c HEAD` to originate from commit ebddb44c (2026-09-27), not from any change made in this batch. No lib/ file was left modified by this batch (git diff on lib/ is empty after the mutation-proof revert)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "This batch made no Hive-schema or writer change. The founder's own local Hive state was not touched -- the live-prod repair targets cloud rows only; the client's existing restore logic (once running a build with Task 14) will read the repaired cloud-authoritative 'completed' status and self-correct locally on the next restore." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No DDL. Both repairs are plain UPDATEs against existing columns (scheduled_workouts.status/completed_at, user_progress.plan_json)." }
  - { tier: 4, name: "Postgres data", status: fixed_in_this_batch, evidence: "Live BEFORE state confirmed via SELECT (both scheduled_workouts and user_progress.plan_json showed status='planned', completed_at=null for user_id d7a67a37-0b05-4f0a-b13c-388bff3cb59b, scheduled_date=2026-09-28). Both repaired via UPDATE ... RETURNING, AFTER state confirmed in the same call: scheduled_workouts now status='completed', completed_at='2026-09-28 04:05:19.994+00'; plan_json->schedules->schedule_2026-09-28 now status='completed', completed_at='2026-09-28T04:05:19Z', every other field (completed_at_ms, completed_via, exercises, template_id, week_number) unchanged from before the repair." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration in this batch. Migration 149's completed-day guard trigger (private.scheduled_workouts_completed_guard) was checked and confirmed NOT to block this repair -- it only blocks a SQL UPDATE that DEMOTES an already-'completed' row (OLD.status='completed' AND NEW.status IS DISTINCT FROM OLD.status); this repair goes 'planned' -> 'completed', the opposite direction, unaffected." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function reads or writes scheduled_workouts.status or user_progress.plan_json in a way this fix touches." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron job involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No RLS change; the repair ran via the MCP execute_sql tool (service-role context), scoped by an explicit user_id filter verified in both the SELECT and the UPDATE...RETURNING." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Traced the full writer/reader chain by file:line (writers/readers above) before proposing anything, per CLAUDE.md §4.1. Confirmed the push-side writer (_syncScheduledWorkouts) is NOT independently broken -- SyncSkipIndex.pushIfChanged correctly forgets its fingerprint on failure/false-return so it retries; the FK-recovery dance for template_id resolution is a separate, real-but-unproven fragility, flagged but not implicated in this specific incident." }
recurrence: d9b2c5 (2026-05-10, docs/diagnoses/2026-05-10-restore-overwrite-d9b2c5.md)
related_bugs: [d9b2c5, f4c7a9]
---

# A source-grep-guarded dead branch survived its own bug class's actual fix, by a day

## Summary

The founder's 2026-09-28 "Calisthenics Day" workout, completed that morning,
showed as not-done on 2026-09-29. Live DB checks on both cloud
representations of the day (`scheduled_workouts` and
`user_progress.plan_json`) showed the exact fingerprint of a restore-merge
demotion: `status='planned'`, `completed_at=null`, but `completed_at_ms`,
`completed_via` and the real exercise list all still intact, plus a
`source: 'cloud_restore'` stamp on the JSON copy. That fingerprint means a
restore pass overwrote `status` while preserving the completion evidence --
not a fresh write, not corruption, not a different bug shape.

## Root cause, named by writer + reader before any fix was proposed (§4.1)

**Writer:** `SyncService._restoreScheduledWorkouts`
(`lib/core/services/sync/sync_workout.dart:2238`). On every restore/relaunch
it decides, per scheduled day, whether to keep the local status or take the
cloud's. The keep-local-completed branch requires a local completion
TIMESTAMP to judge freshness:

```dart
if (localStatus == 'completed' &&
    (cloudStatus == 'planned' || cloudStatus == 'rest') &&
    localCompletedAt != null &&
    localCompletedAt.isNotEmpty) {
  mergedStatus = 'completed';
  mergedCompletedAt = localCompletedAt;
}
```

**The actual live completion writer:** `WorkoutWriteService.markCompleted`
(`lib/core/services/workout_write_service.dart:492`) sets
`status='completed'` + `completed_at_ms` + `completed_via` together in one
Hive map mutation. It never writes the legacy ISO `completed_at` field on a
schedule row -- that field only ever appears on the separate `wlog_<date>`
row.

**The gap:** `localCompletedAt` was derived, before 2026-09-27, by reading
`existingMap['completed_at']` DIRECTLY -- a field the live writer never
populates. So for every real on-device completion since this guard was
introduced (`d9b2c5`, 2026-05-10), `localCompletedAt` was ALWAYS null, and
the keep-local branch's own condition could never be true. A stale cloud
`'planned'` row -- the ordinary state immediately after a completion, before
the push-side fan-out lands -- silently demoted the local completion on the
very next restore. Dead for ~4.5 months.

## Why this diagnose-doc exists even though the code was already fixed

Commit `ebddb44c` (2026-09-27, "fix(sync): resolve the real
workout-completion time, never now()", Task 14 of `day-swapper-sync-load`,
closes-diagnose `f4c7a9`) already replaced the direct read with
`ScheduleCompletionTime.scheduledCompletedAtIso(existingMap)`, which falls
back to `completed_at_ms` -- exactly the fix this recurrence would otherwise
propose. Confirmed via `git merge-base --is-ancestor ebddb44c HEAD`: it is
already on this branch's base, landed two days before the founder's report.

That commit ALSO shipped a genuinely behavioral, mutation-proven test for
this exact scenario
(`test/contracts/sync_schedule_completion_payload_hash_index_writer_to_reader_test.dart`,
group "restore carve-out uses the same resolver (plan D3)") -- found and
fixed as a side effect of an unrelated live-timestamp audit (`f4c7a9`), not
by anyone deliberately targeting this dead branch.

So the founder's report is fully explained by **build lag, not a live code
defect**: the last recorded APK/AAB build is `1.0.0+47`
(`3f24c52e`, recorded 2026-09-24 23:08:45 +0530) -- three days BEFORE
`ebddb44c` (2026-09-27 14:48:44 +0530). The founder's installed app predates
the fix. `main` today already has both the fix and its test.

This batch's job, then, was not "write the fix" -- it was:
1. Verify precisely that the fix is real, on main, and tested (this doc).
2. Fix the SoT registry, which still pointed at a dead writer and a
   source-grep-only test file, and never listed the actual culprit as a
   writer at all -- a genuine gap independent of Task 14.
3. Add supplementary field-survival test coverage Task 14's own test
   doesn't check.
4. Repair the founder's specific already-corrupted row on both cloud
   representations, since Task 14 does not retroactively heal existing bad
   data.

## Architecture note: "why 3 writers for the same thing?"

Investigated per founder's follow-up question. Not really 3 writers for one
fact:

- **1 live local writer:** `WorkoutWriteService.markCompleted` -- the
  canonical completion writer, reached from the active-workout finish flow
  and the AI coach's auto-completion path.
- **2 legitimate cloud projections**, not duplicates: `scheduled_workouts`
  (relational, for server-side SQL by Edge Functions/cron) and
  `user_progress.plan_json` (the client's own full-fidelity restore mirror).
  Per `docs/architecture/sync.md`'s "Restore conflict policy", the merge
  logic in `_restoreScheduledWorkouts` is a DELIBERATE design choice (cross-
  device completion learning), not redundant scaffolding -- an earlier
  suggestion this session to strip status-decision logic out of it was
  wrong and was retracted after checking that doc.
- **1 genuinely dead THIRD implementation:**
  `WorkoutScheduleWriteService.markCompleted`
  (`lib/core/services/workout_schedule_write_service.dart:73`, reached via
  the `WorkoutScheduleService.markCompleted` shim and
  `WorkoutRepository.markWorkoutCompleted`) independently sets
  `status='completed'` + the legacy ISO `completed_at` (never
  `completed_at_ms`/`completed_via`) via a DIFFERENT write path
  (`WorkoutWriteService.upsertScheduled`, not `markCompleted`). Verified via
  `grep -rn markWorkoutCompleted lib/`: the only hits are the dead
  definition chain itself and a comment in `train_provider.dart:1928`
  documenting its own historical replacement
  ("Replaces repo.saveWorkoutLog + repo.markWorkoutCompleted."). Zero live
  callers. Not removed in this batch -- flagged in the SoT registry and
  here for a founder decision on cleanup, since deleting it expands this
  batch's scope beyond what was authorized and has its own (small) test
  fallout to check first.

The real recurring risk is not "too many writers" -- it's that TWO of the
paths above (the live writer and the restore-merge writer) each
independently need to agree on how a completion timestamp is represented,
and that agreement silently broke for 4.5 months with no test catching it
until an unrelated bug hunt tripped over it.

## Fix

See `proposed_fix` above (three parts: registry correction, supplementary
test, live data repair). No `lib/` production code changed in this batch.

## Related / recurrence

Third instance of this exact concept drifting:
- **d9b2c5** (2026-05-10) -- introduced the keep-local-completed guard,
  fixing the FIRST way this class of bug manifested (an FK violation left
  cloud stale).
- **f4c7a9** (2026-09-26/27) -- fixed a DIFFERENT symptom (wrong completion
  timestamps sent to the cloud) and, as a side effect of sharing the same
  root defect, also fixed d9b2c5's guard, which had been dead the whole
  time.
- **d83505** (this doc, 2026-09-29) -- the founder-visible fallout of the
  gap between f4c7a9 landing on main and it reaching a built APK, plus the
  registry/test gaps that survived f4c7a9's own fix.

Appended to `.claude/skills/debugging/SKILL.md`'s bug-class catalog per §5
self-evolution: a source-grep test asserting on a guard's literal
conditional text gives no signal when the guard's INPUT DERIVATION changes
underneath it, and — the sharper, less obvious half — that gap can survive
not just months of untouched code but also a LATER, unrelated fix that
happens to touch the exact same lines for a different reason, because the
source-grep's tokens don't care why the surrounding code changed.
