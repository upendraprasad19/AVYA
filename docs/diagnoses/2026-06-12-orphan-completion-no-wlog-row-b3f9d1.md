---
bug_id: b3f9d1
date: 2026-06-12
batch: audit-2026-06-10
status: fixed
blast_radius: account
symptom: >
  Quarterly audit (L1 lens) finding F1, confirmed post-f1c8e4. The
  orphan-completion restore branch (_restoreScheduleCompletions, the "no local
  schedule row for this date" / out-of-plan-window case in sync_workout.dart,
  e9b4a2/d9d201c) synthesizes a schedule_<date> row (status='completed',
  type='logged') that satisfies the streak walk — but it wrote NO wlog_<date>
  row. The count/history readers (getWeeklyWorkoutCounts → reports "This Week"
  tile + 4-week frequency chart, getWorkoutLogs, BadgeService.totalWorkouts,
  AiSnapshotBuilder) filter type=='workout_log' (the wlog_ row), so an orphan
  completion restored ONLY via workout_schedule_completions — i.e. when the
  SEPARATE workout_logs restore path (_restoreWorkoutLogs) had no row for that
  date (a partial-sync divergence) — was uncounted. Streak was correct; the
  weekly count / history / badge / AI snapshot missed it.
concept: orphan_completion_wlog_completeness
sot_registry_entry: hive_field_name_wlog
writers: >
  sync/sync_workout.dart _restoreScheduleCompletions (synthesize branch — now
  also writes an additive wlog_<date> row mirroring the canonical f1c8e4 shape).
  Canonical live writer is WorkoutWriteService.markCompleted (writes both rows).
readers: >
  workout_repository.dart getWeeklyWorkoutCounts / getWorkoutLogs;
  badge_service.dart totalWorkouts; ai_snapshot_builder.dart — all filter
  type=='workout_log'.
hive_key_prefix: "wlog_"
hive_key_formula: "wlog_$date (date = the IST date of the cloud completion)"
sync_methods: [_syncWorkoutLogs]
restore_methods: [_restoreScheduleCompletions, _restoreWorkoutLogs]
cloud_table: workout_schedule_completions
cloud_columns: "scheduled_date, workout_name, completed_at, duration_seconds (read to synthesize; the wlog row is local-only — no new cloud write)"
contract_test_path: test/contracts/orphan_completion_synthesizes_wlog_test.dart
ist_handling: >
  `date` is the IST date of the cloud completion (already an IST date-key); the
  wlog key wlog_$date matches WorkoutWriteService.wlogKey. completed_at is an
  instant timestamp (unchanged).
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["sync_service_if_12 (restore_schedule_completions)"]
cross_account_guard: true
forbidden_patterns_checked:
  - "_restoreScheduleCompletions synthesize branch writing only a schedule_ row — now also writes an additive wlog_<date> row (type:'workout_log') so the orphan completion is counted."
  - "unconditional wlog overwrite — the synthesize wlog write is additive (skip-if-local-exists), never clobbering a real logged session."
proposed_fix: >
  In the _restoreScheduleCompletions synthesize branch, after putting the
  schedule_ row, ALSO put an additive wlog_<date> row (type:'workout_log' +
  workout_name + date + duration_seconds + completed_at + completed_at_ms +
  source) when no local wlog row exists — so the orphan completion reaches the
  type=='workout_log' count/history readers. Local-wins (skip-if-local-exists)
  so it never overwrites a real logged session's richer row.
regression_test_planned: >
  test/contracts/orphan_completion_synthesizes_wlog_test.dart — scoped
  source-grep on _restoreScheduleCompletions (the file writes type:'workout_log'
  elsewhere, so scope to the synthesize branch + strip comments): asserts the
  branch writes wlog_$date + type:'workout_log' + the additive
  get(wlogKey)==null guard.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "additive wlog_ write in synthesize branch; flutter analyze clean; Gate 19 (wlog field-drift) green" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "orphan_completion_synthesizes_wlog_test 3/3; the synthesized wlog row uses the canonical f1c8e4 fields so all type=='workout_log' readers count it" }
impact_analysis: >
  Account blast radius, low severity (rare partial-sync divergence; no data loss).
  The streak (schedule_ rows) was already correct; this closes the count/history
  completeness leg for an orphan completion present in workout_schedule_completions
  but absent from workout_logs. Sibling/continuation of f1c8e4 (which fixed the
  LIVE markCompleted wlog shape) — this fix makes the RESTORE synthesize path
  produce the same counted wlog row. Found by the L1 lens; the e9b4a2 diagnose had
  already flagged a behavioral_test_required follow-up for this asymmetry.
---

# Orphan-completion restore writes no countable wlog row (b3f9d1)

## What happened
`_restoreScheduleCompletions`' synthesize branch (the "no local schedule row" /
out-of-plan-window case) wrote a `schedule_<date>` row (type='logged') that the
streak walk reads, but no `wlog_<date>` row. The count/history readers filter
`type=='workout_log'` (the wlog_ row), so an orphan completion restored only via
`workout_schedule_completions` (when `workout_logs` had no row for that date) was
uncounted in "This Week" / history / badge total / AI snapshot.

## Root cause
The synthesize branch was aligned to markCompleted's *schedule* branch only.
markCompleted writes BOTH a schedule_ and a wlog_ row; the restore synthesize path
wrote only the schedule_ row, and the separate `_restoreWorkoutLogs` path covers
the wlog_ row only when the cloud `workout_logs` row exists.

## Fix
After the schedule_ put, additively put a `wlog_<date>` row (canonical f1c8e4
shape: `type:'workout_log'` + completed_at) when no local wlog row exists.

## Verification
- `test/contracts/orphan_completion_synthesizes_wlog_test.dart` 3/3.
- `flutter analyze` clean; Gate 19 (wlog field-drift) green.

## See also
- lib/core/services/sync/sync_workout.dart (`_restoreScheduleCompletions`, `_restoreWorkoutLogs`)
- docs/diagnoses/2026-06-12-markcompleted-wlog-missing-type-f1c8e4.md (the live-writer sibling)
