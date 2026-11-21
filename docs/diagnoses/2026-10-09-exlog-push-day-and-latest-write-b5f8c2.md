---
bug_id: b5f8c2
date: 2026-10-09
batch: coach-history-correctness-client
status: fixed
tier: m_fix
blast_radius: platform
symptom: >-
  An exercise-log push derived workout_log_id from log['date'] ?? '' so a row without a date landed in the shared v5('workout_') bucket; it sent a restored row's old created_at as completed_at even after a later edit or move (so a cross-device delete filtered by time would tombstone the newer version); the non-collision move did not stamp a write time; and duplicate explicit set_numbers in sets_detail collapsed into one per-set row on the (user, workout_log_id, exercise_id, set_number) key (OI-313 day drift is fixed on the read side, L1b and U2).
concept: exlog_workout_day
sot_registry_entry: exlog_workout_day
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method: "_syncExerciseLogs", line: 334 }
  - { file: lib/core/services/workout_write_service.dart, method: "moveExerciseLogs (non-collision branch stamps updated_at_ms)", line: 950 }
readers:
  - { file: lib/core/services/sync/exlog_restore_rules.dart, method_or_widget: "ExlogWorkoutDays.forToday (inverts workoutLogIdForDate)", line: 1 }
  - { file: supabase/functions/_shared/exercise_day.ts, method_or_widget: "the server day resolver (L1b)", line: 1 }
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
contract_test_path: test/sync/exlog_push_u3_behavioral_test.dart
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
  U3: the day is date, else the date in the Hive key, else the IST day of created_at (the readers' own fallback, B-pass A F2), else NO push (logged as sync_skipped_exlog_no_day); the same day derives workout_log_id; completed_at = latestWriteIso(resolved, updated_at_ms), i.e. max(resolved, updated_at_ms) (the shared resolver is NOT changed, it also feeds workout_logs); the non-collision move stamps updated_at_ms; uniquePerSetNumbers renumbers the whole list 1..N when an explicit set_number repeats and leaves gapped legacy sets alone. Readers take the day from workout_log_id, never from completed_at. Accepted by the founder (2026-10-06, R11C-1): a move or edit of an old PR row into today or yesterday can trigger one extra New PR push that day (one per user per IST day).
regression_test_planned: >-
  test/sync/exlog_push_u3_behavioral_test.dart (real SyncService against SyncStubServer). Run: TZ=Asia/Kolkata flutter test test/sync/exlog_push_u3_behavioral_test.dart
mutation_proof: >-
  Rule 21. 9 mutants (latestWriteIso ignores updated_at_ms; isAfter flipped; duplicates never renumbered; always renumber; key-date fallback removed; no-day skip removed; move stamp removed; push ignores latestWriteIso; renumber not wired): 9 of 9 RED on the first run, none survived. Driver: scratchpad mutate_u3.py.
impact_analysis: >-
  Before: see the symptom. After: one live summary per exercise-day is restored with its own sets on the workout day, a push is dated by the workout day and the latest local write, and a delete reaches every older cloud version while a newer re-log survives.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/core/services/sync/sync_workout.dart _syncExerciseLogs, exlog_push_rules.dart, workout_write_service.dart moveExerciseLogs" }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "a moved row now carries updated_at_ms; no Hive key or shape change" }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "no schema change; completed_at and workout_log_id are existing workout_log_exercises columns" }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "read-only 2026-10-09 (project dedsavbjuwgarrhphgnl): 235 wle rows, 180 live, 0 live duplicate groups, 0 null workout_log_id, 235 of 235 workout_log_id values equal the v5 of the IST date of completed_at, 0 scheduled_workouts with status moved" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no Edge Function code in this unit" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "no cron involved" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "own-user writes unchanged" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "none" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "test/sync/exlog_push_u3_behavioral_test.dart drives the real push against SyncStubServer and reads the recorded write bodies; no live call" }
recurrence: "partial recurrence of APK Test #12.7 (completed_at preservation); OI-313"
related_bugs: [e6a2d4]
---

# exlog push day and latest write

## What was wrong

An exercise-log push derived workout_log_id from log['date'] ?? '' so a row without a date landed in the shared v5('workout_') bucket; it sent a restored row's old created_at as completed_at even after a later edit or move (so a cross-device delete filtered by time would tombstone the newer version); the non-collision move did not stamp a write time; and duplicate explicit set_numbers in sets_detail collapsed into one per-set row on the (user, workout_log_id, exercise_id, set_number) key (OI-313 day drift is fixed on the read side, L1b and U2).

## Fix

U3: the day is date, else the date in the Hive key, else NO push (logged as sync_skipped_exlog_no_day); the same day derives workout_log_id; completed_at = latestWriteIso(resolved, updated_at_ms), i.e. max(resolved, updated_at_ms) (the shared resolver is NOT changed, it also feeds workout_logs); the non-collision move stamps updated_at_ms; uniquePerSetNumbers renumbers the whole list 1..N when an explicit set_number repeats and leaves gapped legacy sets alone. Readers take the day from workout_log_id, never from completed_at. Accepted by the founder (2026-10-06, R11C-1): a move or edit of an old PR row into today or yesterday can trigger one extra New PR push that day (one per user per IST day).

## Verification

Plan: `docs/plans/coach-history-correctness-client.md` (v9, converged in 11 review rounds). Live read-only check 235 wle rows, 180 live, 0 live duplicate groups, 0 null workout_log_id, 235 of 235 workout_log_id values equal the v5 of the IST date of completed_at, 0 scheduled_workouts with status moved. Tests and mutation proof as in the front matter. The device-level restore check needs a founder-built APK and is a `blocked_on_user` row in `docs/audit/coach-history-correctness-client.closure.yaml`.
