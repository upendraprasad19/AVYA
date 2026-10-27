---
bug_id: c6a9d3
date: 2026-10-09
batch: coach-history-correctness-client
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  An exercise log deleted on one device left a live cloud row in four cases: the drain tombstoned only the SAME set count (a stale count stayed live), after migration 151 it could tombstone a newer same-count re-log, a re-log after a failed drain was still tombstoned by the stale queue entry, and moveExerciseLogs deleted the source day's Hive key without queueing any cloud delete (OI-218, exlog half), so a restore brought the moved-out day's logs back.
concept: pending_exlog_deletes
sot_registry_entry: pending_exlog_deletes
writers:
  - { file: lib/core/services/workout_write_service.dart, method: "deleteLog", line: 1284 }
  - { file: lib/core/services/workout_write_service.dart, method: "moveExerciseLogs (add source, cancel target)", line: 932 }
  - { file: lib/core/services/workout_write_service.dart, method: "logExercise (cancelFor)", line: 249 }
  - { file: lib/core/services/exlog_key_migrator.dart, method: "runIfNeeded (cancelFor)", line: 139 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_drainPendingExlogDeletes", line: 218 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreExerciseLogs (skips queued deletes)", line: 999 }
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
  U4: PendingExlogDeletes records deleted_at_ms with every entry (re-queuing a triple replaces it with the later time) and gains cancelFor and isQueued; a re-log does NOT cancel a TIMED entry (B-pass 5c19161a, reviewer B F2: a cancel keeps the OLDER cloud version, possibly at another set count, alive, and the highest-count restore then brings the deleted version back over the re-log; the drain's completed_at <= deleted_at_ms filter already spares the newer version), only an entry queued by an older app build with no delete time is cancelled (logExercise, moveExerciseLogs target day, ExlogKeyMigrator; non-throwing and after the index append, B-F1); this REVERSES the plan's U4 'cancel on re-create' for timed entries; BOTH branches of moveExerciseLogs queue the SOURCE day (count = the moved row's local count) AFTER the Hive work (B-F6); the drain sends ONE UPDATE workout_log_exercises SET deleted_at WHERE user_id, workout_log_id, exercise_id, deleted_at IS NULL AND completed_at <= the delete time, with .select(), for every set count (an entry without a time cuts off at drain time = the old all-count behaviour; a time in the future is clamped to now, B-F4); an UPDATE that touches no row KEEPS the entry for one more pass because a creating push already on the wire can land after it and the UPDATE cannot create a tombstone the way the old upsert could (B-F3; the plan's 'the same race exists today' was wrong for that case); a malformed deleted_at_ms reads as no time instead of throwing out of the drain (B-F5); the old fallback upsert is gone. Founder decision 2026-10-06 (corrected after review round 9): the NEWEST action wins. Kill switch configBox disable_exlog_allcount_drain falls back to the old same-count upsert. Residuals recorded (founder-accepted, pre-existing): device clocks that disagree by minutes can misjudge a log made within that skew of the delete; a push already in flight when the delete happened can land after the drain and stay live. The test stub SyncStubServer gained a writeResponders hook and now answers a write that asks for the representation with 200 [] (200 {} for an object Accept) as real PostgREST does, instead of 204 with no body.
regression_test_planned: >-
  test/sync/exlog_delete_u4_behavioral_test.dart (real SyncService against SyncStubServer). Run: TZ=Asia/Kolkata flutter test test/sync/exlog_delete_u4_behavioral_test.dart
mutation_proof: >-
  Rule 21. 15 mutants (time filter removed; deleted_at is-null filter removed; exercise_id filter removed; queue re-read removed; first owner check removed; second owner check removed; kill switch inverted; add() drops the time; cancelFor a no-op; logExercise cancel removed; move source not queued; move target not cancelled; migrator cancel removed; remove() ignores the time; stub representation default off). First pass 13 RED, 2 survived. M5 (the first owner check) is only observable if the account switch lands right after the previous entry's local remove: closed with a test that flips the owner from a Hive watch event on the queue key, re-run RED. M14 was aimed at the wrong occurrence (the identical clause in isQueued); retargeted at remove() it survived for real and was closed with a test that re-queues the same triple while the older entry's UPDATE is on the wire (the older drain must not remove the newer entry), re-run RED. 15 of 15 RED in the end. B-pass fixes mutated too: cancelFor cancelling timed entries again RED x4, empty-pass keep removed RED x2, future cutoff unclamped RED x1, malformed time kept RED x1; the move-queue ordering is a source-position pin (presence-only, the Hive work cannot be made to throw from a test). Driver: scratchpad mutate_u4.py / mutate_u4b.py.
impact_analysis: >-
  Before: see the symptom. After: one live summary per exercise-day is restored with its own sets on the workout day, a push is dated by the workout day and the latest local write, and a delete reaches every older cloud version while a newer re-log survives.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "pending_exlog_deletes.dart, workout_write_service.dart, exlog_key_migrator.dart, sync/sync_workout.dart drain" }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "userBox pending_exlog_deletes entries gain deleted_at_ms; legacy entries without it still drain (drain-time cutoff)" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "no schema change; RLS allows the own-user UPDATE (migration 100, lines 173-180); migration 150 tombstone column deleted_at exists" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "read-only 2026-10-09 (project dedsavbjuwgarrhphgnl): 235 wle rows, 180 live, 0 live duplicate groups, 0 null workout_log_id, 235 of 235 workout_log_id values equal the v5 of the IST date of completed_at, 0 scheduled_workouts with status moved" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration; the optional one-statement data migration for moved-out rows is not needed: 0 scheduled_workouts rows with status moved, so no live moved-out row is leftover" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no Edge Function code in this unit" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "no cron involved" }
  - { tier: 8, name: "RLS policies", status: verified, evidence: "workout_log_exercises UPDATE is allowed for the owner (migration 100); the UPDATE filters on user_id" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "none" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "test/sync/exlog_delete_u4_behavioral_test.dart records the actual PATCH (filters and body) the real drain sends and models a cloud that applies the same filters; no live write is made; live Postgres semantics of the time-filtered UPDATE are the same as any filtered UPDATE (no trigger interplay beyond migration 150/151, which act on deleted_at)" }
recurrence: "recurrence of e1c8b4 / OI-246 (a local delete that never reaches the cloud) for the moved-out day and the stale count; e8f4a3 accepted this residual"
related_bugs: [e1c8b4, e8f4a3]
---

# exlog delete never reaches newest version

## What was wrong

An exercise log deleted on one device left a live cloud row in four cases: the drain tombstoned only the SAME set count (a stale count stayed live), after migration 151 it could tombstone a newer same-count re-log, a re-log after a failed drain was still tombstoned by the stale queue entry, and moveExerciseLogs deleted the source day's Hive key without queueing any cloud delete (OI-218, exlog half), so a restore brought the moved-out day's logs back.

## Fix

U4: PendingExlogDeletes records deleted_at_ms with every entry (re-queuing a triple replaces it with the later time) and gains cancelFor and isQueued; a re-log does NOT cancel a TIMED entry (B-pass 5c19161a, reviewer B F2: a cancel keeps the OLDER cloud version, possibly at another set count, alive, and the highest-count restore then brings the deleted version back over the re-log; the drain's completed_at <= deleted_at_ms filter already spares the newer version), only an entry queued by an older app build with no delete time is cancelled (logExercise, moveExerciseLogs target day, ExlogKeyMigrator; non-throwing and after the index append, B-F1); this REVERSES the plan's U4 'cancel on re-create' for timed entries; BOTH branches of moveExerciseLogs queue the SOURCE day (count = the moved row's local count) AFTER the Hive work (B-F6); the drain sends ONE UPDATE workout_log_exercises SET deleted_at WHERE user_id, workout_log_id, exercise_id, deleted_at IS NULL AND completed_at <= the delete time, with .select(), for every set count (an entry without a time cuts off at drain time = the old all-count behaviour; a time in the future is clamped to now, B-F4); an UPDATE that touches no row KEEPS the entry for one more pass because a creating push already on the wire can land after it and the UPDATE cannot create a tombstone the way the old upsert could (B-F3; the plan's 'the same race exists today' was wrong for that case); a malformed deleted_at_ms reads as no time instead of throwing out of the drain (B-F5); the old fallback upsert is gone. Founder decision 2026-10-06 (corrected after review round 9): the NEWEST action wins. Kill switch configBox disable_exlog_allcount_drain falls back to the old same-count upsert. Residuals recorded (founder-accepted, pre-existing): device clocks that disagree by minutes can misjudge a log made within that skew of the delete; a push already in flight when the delete happened can land after the drain and stay live. The test stub SyncStubServer gained a writeResponders hook and now answers a write that asks for the representation with 200 [] (200 {} for an object Accept) as real PostgREST does, instead of 204 with no body.

## Verification

Plan: `docs/plans/coach-history-correctness-client.md` (v9, converged in 11 review rounds). Live read-only check 235 wle rows, 180 live, 0 live duplicate groups, 0 null workout_log_id, 235 of 235 workout_log_id values equal the v5 of the IST date of completed_at, 0 scheduled_workouts with status moved. Tests and mutation proof as in the front matter. The device-level restore check needs a founder-built APK and is a `blocked_on_user` row in `docs/audit/coach-history-correctness-client.closure.yaml`.
