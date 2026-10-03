---
bug_id: 2026-05-16-schedule-completion-duration
date: 2026-05-16
batch: APK Test #16.1 / Phase E.4
status: in_progress
symptom: |
  `workout_schedule_completions.duration_seconds` is 100% NULL in cloud
  across all production users (11/11 rows; verified by Agent 3 live SQL
  in `docs/audit/2026-05-16/findings-agent-3.md` § F3-1.3).

  The column should reflect how long the user actually trained on each
  completed scheduled workout. Cross-check: `workout_logs.duration_seconds`
  is 0/8 NULL — the data exists in the right Hive row, just not joined
  into the schedule-completion projection. Analytics, weekly reports, and
  any future "average session length" insight read this column and see
  zero signal across the entire user base.
concept: workout_schedule_completion_cloud_projection
sot_registry_entry: workout_schedule_completions
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _syncScheduleCompletions, line: 410 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: markCompleted (writes wlog_<dateStr>.duration_seconds), line: 375 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: upsert payload at workout_schedule_completions, line: 442 }
  - { file: docs/audit/2026-05-16/findings-agent-3.md, method_or_widget: live SQL null-count audit, line: 30 }
hive_key_prefix: schedule_
hive_key_formula: schedule_<istDateStr(date)>
sync_methods:
  - SyncService._syncScheduleCompletions
restore_methods: []
cloud_table: workout_schedule_completions
cloud_columns:
  - user_id
  - scheduled_date
  - day_of_week
  - workout_name
  - duration_seconds
  - completed_at
contract_test_path: test/contracts/schedule_completion_duration_writer_to_reader_test.dart
ist_handling:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: schedule entry date is IST per CLAUDE.md §15, line: 420 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: wlogKey = wlog_${istDateStr(date)}, line: 833 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - upsert_schedule_completion
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "entry['duration_seconds']", absent: true }
  - { pattern: "'duration_seconds': null", absent: true }
proposed_fix: |
  In `_syncScheduleCompletions` (`lib/core/services/sync/sync_workout.dart`),
  before constructing the upsert payload, look up the matching workout-log
  row by IST date and pull `duration_seconds` from there:

  ```dart
  final wlog = workoutBox.get('wlog_$date');
  final durationSeconds =
      wlog is Map ? (wlog['duration_seconds'] as num?)?.toInt() : null;
  ```

  Project the field only when non-null, matching this file's convention
  for optional cloud columns (cf. `_syncStreaks` which uses `if (... != null)`
  guards). Absence on the wire is preferable to explicit null because the
  cloud column is nullable and we want to distinguish "writer omitted"
  from "writer sent null".

  The schedule entry's `date` field is already an IST date string
  (CLAUDE.md §15 + writer `WorkoutWriteService.markCompleted` writes
  `wlog_${istDateStr(date)}` per `workout_write_service.dart:833`), so
  reusing it as the wlog lookup key preserves the IST convention end to
  end. No new helper required.

  Why this is the right writer-side fix (not a server-side join): the
  cloud schema intentionally denormalises `duration_seconds` onto
  `workout_schedule_completions` so downstream Edge Functions (weekly
  recap, AI snapshot) can avoid a JOIN. The writer is the join boundary
  by design — this fix restores that contract.

  Risk: zero — single callsite in `lib/`, no other writer projects this
  column (verified via grep). The 11 historical NULL rows stay NULL; no
  backfill is in scope for this batch.
regression_test_planned:
  - test/contracts/schedule_completion_duration_writer_to_reader_test.dart
---

# Bug 2026-05-16-schedule-completion-duration — workout_schedule_completions duration_seconds 100% NULL

## Symptom

`workout_schedule_completions.duration_seconds` is NULL on every
production row (11/11 across 4 test users). Founder-facing impact is
latent: no current UI reads this column directly. The cloud projection
exists to feed analytics + the AI snapshot's "average session length"
signal, both of which now see zero variance across the user base.

## User-visible impact

None directly today. Downstream impact: any weekly-recap or AI-coach
prompt that includes "average session length" or "trend in duration"
returns null / undefined, so Gemini either fabricates the value or
omits it. The bigger meta-impact is that we ship a denormalised cloud
column that has no useful data — the contract between writer and
analytics consumers is broken silently.

## Root cause

`_syncScheduleCompletions` (`lib/core/services/sync/sync_workout.dart`
L410+) iterates `schedule_<date>` rows in Hive and upserts each
completed entry to `workout_schedule_completions`. Pre-fix projection:

```dart
'duration_seconds': entry['duration_seconds'],
```

`entry` is the `schedule_<date>` Hive row. That row's writers
(`WorkoutScheduleService` for plan-generator-created entries +
`WorkoutWriteService.markCompleted` for the status flip at L354-369)
never set `duration_seconds` on the schedule entry. The field lives on
the sibling `wlog_<istDateStr(date)>` workout-log row (written at
`workout_write_service.dart:375` inside the same `markCompleted` call).

Result: `entry['duration_seconds']` is always null → cloud column
receives explicit null on every upsert → 100% NULL post 11+ writes.

This is the 10th writer/reader drift instance in the running tally
(`feedback_writer_reader_field_drift_recurring.md`). Sub-class:
**cross-Hive-row drift** — the projection joined the wrong Hive key
within the same domain. Distinct from the cloud-column-rename class
(coach_notes / coaching_notes, F3-1.1) and the field-name-collision
class (workout_log_exercises set_number, APK Test #8).

## Fix

Look up the wlog row by IST date before projecting, read
`duration_seconds` from it, and project conditionally:

```dart
final wlog = workoutBox.get('wlog_$date');
final durationSeconds =
    wlog is Map ? (wlog['duration_seconds'] as num?)?.toInt() : null;

// ...

final payload = <String, dynamic>{
  // ... existing fields ...
  if (durationSeconds != null) 'duration_seconds': durationSeconds,
  // ...
};
```

IST handling: the schedule entry's `date` field is already an IST
date string (written by `WorkoutScheduleService` + asserted by every
read path per CLAUDE.md §15). `WorkoutWriteService.wlogKey` is
`wlog_${istDateStr(date)}` so the keys agree by construction.

## Test

`test/contracts/schedule_completion_duration_writer_to_reader_test.dart`
— source-grep contract test mirroring
`test/contracts/coach_notes_upward_sync_test.dart`. Three assertions:

1. `_syncScheduleCompletions` contains a `workoutBox.get('wlog_...')`
   lookup that appears BEFORE the upsert call (anti-regression against
   refactors that reorder method-body sections).
2. The OLD broken pattern `entry['duration_seconds']` is absent from
   the method body.
3. The projection of `'duration_seconds'` is guarded by a non-null
   check (matches this file's `_syncStreaks` convention for nullable
   cloud columns).

## Backfill

Not in scope. The 11 historical NULL rows stay NULL — no production
consumer reads this column today, and the IST date alignment makes a
deterministic backfill SQL trivial (`UPDATE wsc SET duration_seconds =
wl.duration_seconds FROM workout_logs wl WHERE wsc.user_id = wl.user_id
AND wsc.scheduled_date = wl.date`) if a future batch needs the
historical signal. Filed as a follow-up note in the batch retrospective
rather than blocking this fix.

## Cross-contract risk

Verified single callsite — `grep workout_schedule_completions lib/`
returns only `sync_workout.dart`. No restore path reads this table
(per `restoreFromCloudForUser` enumeration in CLAUDE.md §15
"Restore-completeness sync"; this column is denormalised analytics
data, not user state). No Edge Function currently queries it either
(`grep -r workout_schedule_completions supabase/functions/` returns
zero hits — confirming the latent-analytics framing above).
