---
bug_id: d7bae4
date: 2026-10-09
batch: coach-history-correctness-client
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  The exercise-log delete drain had no owner check: it iterated a copy of the queue, and its queue key (v5 of workout_<date> plus the exercise name) is user-independent, so an account swap during a drain let the next account's identical entry be sent under the old user id or locally removed. Passes are not serialised either, so a re-log that cancelled an entry could be overtaken by a drain already holding its copy.
concept: pending_exlog_deletes
sot_registry_entry: pending_exlog_deletes
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method: "_drainPendingExlogDeletes", line: 218 }
readers:
  - { file: lib/core/services/pending_exlog_deletes.dart, method_or_widget: "read / isQueued / remove", line: 1 }
hive_key_prefix: exlog_
hive_key_formula: "WorkoutWriteService.exlogKey(date, exerciseName) (unchanged)"
sync_methods:
  - _syncExerciseLogs
  - _drainPendingExlogDeletes
restore_methods:
  - _restoreExerciseLogs
cloud_table: workout_log_exercises
cloud_columns:
  - workout_log_id
  - exercise_id
  - set_number
  - completed_at
  - deleted_at
contract_test_path: test/sync/exlog_delete_u4_behavioral_test.dart
ist_handling:
  - "the workout day is the date whose UUID v5 equals workout_log_id; the IST midnight of a day is built as DateTime.utc(y, m, d) minus 5h30, never a local DateTime(y, m, d)"
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - sync_drain_pending_exlog_deletes
cross_account_guard: "the drain checks ownerChangedSince(userId) at each write sink; PendingExlogDeletes keys are user-independent"
forbidden_patterns_checked:
  - { pattern: "completed_at used to decide the day of a restored exercise log", absent: true }
  - { pattern: "the old fallback tombstone upsert in the default drain path", absent: true }
proposed_fix: >-
  U4 (the drain-sink half): ownerChangedSince(userId) is checked immediately before the cloud UPDATE and again before each local PendingExlogDeletes.remove (at the write sink, never at function entry), and the queue is re-read (isQueued, exact triple and time) immediately before the UPDATE so an entry cancelled by a re-log since the drain took its copy is not sent. remove() matches the exact triple AND deleted_at_ms so a newer re-queue is not removed by an older drain.
regression_test_planned: >-
  test/sync/exlog_delete_u4_behavioral_test.dart (real SyncService against SyncStubServer). Run: TZ=Asia/Kolkata flutter test test/sync/exlog_delete_u4_behavioral_test.dart
mutation_proof: >-
  Rule 21, shared with c6a9d3: mutants M4 (re-read removed), M5 (first owner check removed), M6 (second owner check removed) and M14 (remove ignores the time) are the drain-sink cases; all RED after the M5 and M14 test additions described in c6a9d3.
impact_analysis: >-
  Before: see the symptom. After: one live summary per exercise-day is restored with its own sets on the workout day, a push is dated by the workout day and the latest local write, and a delete reaches every older cloud version while a newer re-log survives.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "sync/sync_workout.dart _drainPendingExlogDeletes, pending_exlog_deletes.dart" }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "the queue key is user-independent; the remove is now guarded by the owner check and the exact time" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema change" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "no data repair needed" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no Edge Function code" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "no cron" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "none" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "none" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "test/sync/exlog_delete_u4_behavioral_test.dart flips HiveUserSession.debugCurrentUidResolverForTests between entries, during the UPDATE and right after a local remove (Hive watch) and asserts what the real drain sent and kept" }
recurrence: "recurrence of debugging class 2.44 (an in-flight op plus an account swap, a write at the sink); see .claude/skills/debugging/bug-classes.md 2.44"
related_bugs: [e1c8b4]
---

# exlog drain after account swap

## What was wrong

The exercise-log delete drain had no owner check: it iterated a copy of the queue, and its queue key (v5 of workout_<date> plus the exercise name) is user-independent, so an account swap during a drain let the next account's identical entry be sent under the old user id or locally removed. Passes are not serialised either, so a re-log that cancelled an entry could be overtaken by a drain already holding its copy.

## Fix

U4 (the drain-sink half): ownerChangedSince(userId) is checked immediately before the cloud UPDATE and again before each local PendingExlogDeletes.remove (at the write sink, never at function entry), and the queue is re-read (isQueued, exact triple and time) immediately before the UPDATE so an entry cancelled by a re-log since the drain took its copy is not sent. remove() matches the exact triple AND deleted_at_ms so a newer re-queue is not removed by an older drain.

## Verification

Plan: `docs/plans/coach-history-correctness-client.md` (v9, converged in 11 review rounds). Live read-only check 235 wle rows, 180 live, 0 live duplicate groups, 0 null workout_log_id, 235 of 235 workout_log_id values equal the v5 of the IST date of completed_at, 0 scheduled_workouts with status moved. Tests and mutation proof as in the front matter. The device-level restore check needs a founder-built APK and is a `blocked_on_user` row in `docs/audit/coach-history-correctness-client.closure.yaml`.
