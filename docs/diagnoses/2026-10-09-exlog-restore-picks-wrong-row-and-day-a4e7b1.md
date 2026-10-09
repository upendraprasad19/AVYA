---
bug_id: a4e7b1
date: 2026-10-09
batch: coach-history-correctness-client
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  Restoring exercise logs from the cloud kept the first row it saw per exercise (the read is newest-first, so the newest write won whatever its set count), joined every per-set row including sets above the summary's count, dated the restored log by completed_at (the write time, so an edited or moved old log landed on the day it was last written), dated the PR list by created_at, and wrote back an exercise whose delete was still queued for the cloud.
concept: exlog_workout_day
sot_registry_entry: exlog_workout_day
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method: "_syncExerciseLogs (workout_log_id from the log date; U3)", line: 334 }
readers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: "_restoreExerciseLogs", line: 928 }
  - { file: lib/core/services/sync/exlog_restore_rules.dart, method_or_widget: "selectLiveSummaries / rankedSetRows / ExlogWorkoutDays", line: 1 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "loadAllExercisePRs", line: 779 }
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
contract_test_path: test/sync/exlog_restore_u2_behavioral_test.dart
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
  U2 of plan docs/plans/coach-history-correctness-client.md: selectLiveSummaries picks one live summary per (workout_log_id, exercise_id) by highest set_number (ties: later completed_at, created_at, id); rankedSetRows trims the per-set join to the summary's count by rank (count <= 0 takes all, gapped legacy {1,2,4} at count 3 keeps set 4); the day is the date whose UUID v5 equals workout_log_id (map 2020-01-01 to today + 400 days, the same horizon as the server readers), with completed_at only as the fallback, and ONE day drives the Hive key, date, the wlog_ fallback and the day index (IST midnight built from DateTime.utc minus 5h30, never a local DateTime(y, m, d)); an entry queued in PendingExlogDeletes is neither written nor fingerprinted; the PR list reads the day through WorkoutReadService.istDateForExlogRow (same-day PRs now list by exercise name, B-pass A F7); a row restored under the OLD rules sits under the key of the day it was last WRITTEN, so the restore re-keys it onto the workout day (WorkoutWriteService.rekeyRestoredExerciseLog, only when its workout_log_id equals the cloud id) instead of writing a second row beside it (B-pass A F1); selectLiveSummaries compares completed_at / created_at as instants, not text (A F5). Residuals: a cloud row whose workout_log_id is outside 2020-01-01..today+400 or is the missing-date bucket falls back to completed_at (plan-accepted horizon, 0 such live rows); a stray cloud summary an old build pushed under a write-day id is left alone because tombstoning it by time could delete a legitimate same-day row. Kill switch configBox disable_exlog_restore_dedupe restores the old behaviour verbatim (permanent emergency switch, the oi83 precedent). Plan correction: the v9 plan said the old restore kept the OLDEST summary; _fetchAllRows orders newest-first, so the NEWEST write won (found while writing the kill-switch test; the fix and its selector are unaffected).
regression_test_planned: >-
  test/sync/exlog_restore_u2_behavioral_test.dart (real SyncService against SyncStubServer). Run: TZ=Asia/Kolkata flutter test test/sync/exlog_restore_u2_behavioral_test.dart
mutation_proof: >-
  Rule 21. 8 mutants over the rules file, the restore wiring, the PR reader and the kill switch (count compare flipped; rank cut removed; workout day not applied; queued-delete skip removed; PR reader back to created_at; kill switch inverted; tombstone skip removed; IST midnight shift removed). First pass 7 RED, 1 survived: dropping the 5h30 shift is equivalent for the date KEY (UTC midnight is still the same IST day) but not for the INSTANT; closed with a pure test pinning ExlogWorkoutDays.istMidnight('2026-09-01') == DateTime.utc(2026, 8, 31, 18, 30), re-run RED. The east-of-IST hazard itself (a local DateTime(y, m, d)) is invisible to a CI pinned to IST, so it was mutated and run under TZ=Pacific/Auckland: RED x7 there. Driver: scratchpad mutate_u2.py (mutant list, one edit each, file restored after every run).
impact_analysis: >-
  Before: see the symptom. After: one live summary per exercise-day is restored with its own sets on the workout day, a push is dated by the workout day and the latest local write, and a delete reaches every older cloud version while a newer re-log survives.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/core/services/sync/sync_workout.dart _restoreExerciseLogs, exlog_restore_rules.dart, workout_repository.dart loadAllExercisePRs" }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "restored rows now land under exlogKey(workout day, name) and the exercise_log_index of that day; local-wins unchanged (a present row is never overwritten)" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "no schema change; backups/live_schema_columns.json lists workout_log_exercises and workout_log_sets columns the restore reads" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "read-only 2026-10-09 (project dedsavbjuwgarrhphgnl): 235 wle rows, 180 live, 0 live duplicate groups, 0 null workout_log_id, 235 of 235 workout_log_id values equal the v5 of the IST date of completed_at, 0 scheduled_workouts with status moved" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration in this unit; migration 155 (single live row) is the prerequisite and is applied" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no Edge Function code in this unit" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "no cron involved" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "restore reads are own-user RLS reads, unchanged" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "none" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "test/sync/exlog_restore_u2_behavioral_test.dart drives the real SyncService through restoreExerciseLogsForSyncDomain() against SyncStubServer.pagedTables (filters, order, offset/limit, 1000-row clamp); no live call" }
recurrence: "recurrence of e6a2d4 (restore completeness / monotonic class) and of the writer/reader drift class; prior fix docs/plan-reviews/oi83-restore-monotonic.md"
related_bugs: [e6a2d4, e1c8b4, e8f4a3]
---

# exlog restore picks wrong row and day

## What was wrong

Restoring exercise logs from the cloud kept the first row it saw per exercise (the read is newest-first, so the newest write won whatever its set count), joined every per-set row including sets above the summary's count, dated the restored log by completed_at (the write time, so an edited or moved old log landed on the day it was last written), dated the PR list by created_at, and wrote back an exercise whose delete was still queued for the cloud.

## Fix

U2 of plan docs/plans/coach-history-correctness-client.md: selectLiveSummaries picks one live summary per (workout_log_id, exercise_id) by highest set_number (ties: later completed_at, created_at, id); rankedSetRows trims the per-set join to the summary's count by rank (count <= 0 takes all, gapped legacy {1,2,4} at count 3 keeps set 4); the day is the date whose UUID v5 equals workout_log_id (map 2020-01-01 to today + 400 days, the same horizon as the server readers), with completed_at only as the fallback, and ONE day drives the Hive key, date, the wlog_ fallback and the day index (IST midnight built from DateTime.utc minus 5h30, never a local DateTime(y, m, d)); an entry queued in PendingExlogDeletes is neither written nor fingerprinted; the PR list reads the day through WorkoutReadService.istDateForExlogRow. Kill switch configBox disable_exlog_restore_dedupe restores the old behaviour verbatim (permanent emergency switch, the oi83 precedent). Plan correction: the v9 plan said the old restore kept the OLDEST summary; _fetchAllRows orders newest-first, so the NEWEST write won (found while writing the kill-switch test; the fix and its selector are unaffected).

## Verification

Plan: `docs/plans/coach-history-correctness-client.md` (v9, converged in 11 review rounds). Live read-only check 235 wle rows, 180 live, 0 live duplicate groups, 0 null workout_log_id, 235 of 235 workout_log_id values equal the v5 of the IST date of completed_at, 0 scheduled_workouts with status moved. Tests and mutation proof as in the front matter. The device-level restore check needs a founder-built APK and is a `blocked_on_user` row in `docs/audit/coach-history-correctness-client.closure.yaml`.
