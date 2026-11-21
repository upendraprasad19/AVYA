---
bug_id: 81c4e2
date: 2026-11-11
batch: exlog-type-filter-readers
status: fixed
blast_radius: account
symptom: >-
  Three Hive readers filtered exlog_* rows on type == 'exercise_log', a field only the cloud-restore writer stamps.
  The device writer WorkoutWriteService.logExercise never writes it, so on a device with phone-logged history (a
  workout logged in Active Workout or through the coach) the readers saw no rows: (a) the FINISH PR scan in
  ActiveWorkoutNotifier never produced PR lines; (b) BadgeService never counted a phone-logged PR, so the PR badges
  stayed locked; (c) the Profile lifetime volume (WorkoutRepository.getAllExerciseLogKeysForLifetimeSum) ignored
  phone-logged rows.
concept: exlog_rows_read_path
sot_registry_entry: exlog_rows_read_path
writers:
  - file: lib/core/services/workout_write_service.dart
    method: logExercise (the device writer; stamps exercise_name, set_number, weight_kg, volume_kg, is_pr, sets[], never type)
    line: 135
  - file: lib/core/services/sync/sync_workout.dart
    method: _restoreExerciseLogs (the ONLY writer that stamps type 'exercise_log')
    line: 1082
readers:
  - file: lib/core/services/workout_read_service.dart
    method_or_widget: exlogRows (the ONE exlog_ key predicate, defensive copy of every Map value)
    line: 338
  - file: lib/features/train/providers/train_provider.dart
    method_or_widget: ActiveWorkoutNotifier PR scan before FINISH (per-set maxima, keyed by exerciseNameKey, skips rows dated on the session date)
    line: 2086
  - file: lib/core/services/badge_service.dart
    method_or_widget: BadgeService.countBeatenPrs (pure; strictly earlier IST dates, earlier max > 0, no is_pr read)
    line: 96
  - file: lib/core/services/badge_service.dart
    method_or_widget: BadgeService.checkAll (totalPrs through exlogRows + countBeatenPrs)
    line: 138
  - file: lib/features/train/repositories/workout_repository.dart
    method_or_widget: getAllExerciseLogKeysForLifetimeSum (Profile lifetime volume)
    line: 1918
hive_key_prefix: exlog_
hive_key_formula: "workoutBox['exlog_<yyyy-MM-dd IST>_<uuid5 8 hex>'] with exercise_name, weight_kg, volume_kg, sets[]; type only on restored rows"
sync_methods:
  - WorkoutWriteService.logExercise -> _syncExerciseLogs (unchanged)
restore_methods:
  - _restoreExerciseLogs (unchanged; still stamps type, no reader depends on it any more)
cloud_table: workout_log_exercises
cloud_columns: [exercise_name, set_number, weight_kg, volume_kg]
contract_test_path: test/contracts/exlog_type_filter_reader_drift_behavioral_test.dart
ist_handling:
  - WorkoutReadService.istDateForExlogRow gives the IST date of a row (field, else key date); the scan, the badge count and the session date compare IST yyyy-MM-dd strings
  - the PR scan computes the session date with istDateStr(resolveSessionDate(...)), the same date _persistCompletion saves to
provider_invalidations:
  - none (reads only; the existing logExercise invalidation set is unchanged)
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "\\['type'\\]\\s*[!=]=\\s*'exercise_log'", absent: true }
proposed_fix: >-
  One helper, WorkoutReadService.exlogRows(box), is the exlog_ key predicate (key starts with exlog_ and value is a
  Map; yields a copy). The three readers call it and never look at type. The PR scan uses per-set maxima
  (bestPerSetWeight, bestPerSetReps), keys both maps by exerciseNameKey on the write and the lookup side, and skips
  rows dated on the session's own date (a coach log earlier today must not be the "previous best"). The badge count is
  BadgeService.countBeatenPrs: a row counts when its best per-set weight beats the max over strictly earlier IST dates
  of the same exercise and that earlier max is above 0; it no longer reads is_pr (a back-filled heavier earlier row
  leaves a stale flag). Founder decision 2026-11-10: badges count only a PR that beats an earlier log.
regression_test_planned:
  - test/contracts/exlog_type_filter_reader_drift_behavioral_test.dart
  - test/contracts/exlog_type_field_read_ban_test.dart
related_bugs:
  - 89d56c  # graduationStatsProvider: the same type filter (docs/diagnoses/2026-05-22-graduation-total-sets-drift-89d56c.md)
  - 39ead9  # OI-39: the train provider reading through the read service (docs/diagnoses/2026-05-17-oi-39-train-provider-via-read-service-39ead9.md)
  - cb1ab1  # PR cumulative (docs/diagnoses/2026-05-16-pr-cumulative-bug-cb1ab1.md)
recurrence: |
  At least the third instance of the exact filter. 89d56c fixed it in graduationStatsProvider (2026-05-22); the same
  comparison stayed in three other readers because the fix was a per-site edit, not a shared predicate or a ban.
  Writer/reader drift class: two writers of one row family emit different field subsets (restore stamps type, the device
  writer does not; see also d4e7c2 for duration_seconds). Guard added this time: test/contracts/
  exlog_type_field_read_ban_test.dart bans the quoted literal 'exercise_log' in lib/ (comments stripped), except the
  restore writer's one map entry in sync_workout.dart. A reader needs the literal to filter on it, whatever the
  spelling (B-pass F1: a comparison-shape regex missed the pre-fix lifetime-volume spelling). Its scanner is proven on
  inline fixtures, and three mutants turned it red (see Mutation evidence). The known-good shape applied: one shared
  predicate that every reader calls.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "exlogRows + three call sites (workout_read_service.dart:338, train_provider.dart:2086, badge_service.dart:138, workout_repository.dart:1918); countBeatenPrs pure; 25 behavioral tests + 3 ban-scanner tests; mutation table below." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "Behavioral tests on real Hive write device-shaped exlog_ rows (no type field) and restore-shaped rows, then read them through the PR scan, checkAll and the lifetime sum; a non-exlog key and a non-Map value are skipped." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "Client-only fix; no schema change." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud data touched; Hive reads only. Not checked live." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function change." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request or response shape changes; the push and restore of exercise logs are untouched. No live trace was run." }
impact_analysis: >-
  A phone-logged PR now produces a PR line on FINISH (beating the best from strictly earlier dates), counts toward the
  PR badges only when it beats an earlier log (a first-ever log never counts), and phone-logged volume is included in
  the Profile lifetime volume. Restored rows behave as before. Badges already unlocked stay unlocked (monotonic).
---

# Three readers filter exlog rows on a field only the restore writer stamps (81c4e2)

## Root cause
`sync_workout.dart:1082` stamps `type: 'exercise_log'` on restored rows. `WorkoutWriteService.logExercise` (line 135)
does not. `ActiveWorkoutNotifier`'s PR scan, `BadgeService.checkAll` and
`WorkoutRepository.getAllExerciseLogKeysForLifetimeSum` each skipped every row whose `type` was not `exercise_log`, so
on a device whose history was logged on the phone they iterated nothing. `graduationStatsProvider` had the same
filter fixed in 89d56c by a per-site edit.

## Fix
- `WorkoutReadService.exlogRows` (the one key predicate); the three readers call it.
- PR scan: per-set maxima, `exerciseNameKey` on both sides, session-date rows skipped.
- `BadgeService.countBeatenPrs`: counts a row whose `bestPerSetWeight` beats the max over strictly earlier IST dates,
  earlier max > 0; no `is_pr` read.
- Guard: `test/contracts/exlog_type_field_read_ban_test.dart`.

## Mutation evidence (rule 21)
Each mutant applied, confirmed with `grep -c`, run, then restored by reverse edit. Test file:
`exlog_type_filter_reader_drift_behavioral_test.dart` (25 tests green unmutated).

| id | file | edit | result | red count |
|---|---|---|---|---|
| P1 | badge_service.dart | checkAll: exlogRows call replaced by a values loop filtering m['type']=='exercise_log' | RED (checkAll device-row test) | 1 |
| P2 | train_provider.dart | PR scan: helper replaced by a values loop with the type filter | RED (4 PR scan tests) | 4 |
| P3 | workout_repository.dart | lifetime sum: helper replaced by the type condition | RED (lifetime-volume test) | 1 |
| P10 | workout_read_service.dart exlogRows | drop startsWith('exlog_') | RED (helper test, non-exlog-key checkAll test, lifetime test) | 3 |
| P11 | exlogRows | drop the Map check (raw as Map) | RED (helper test) | 1 |
| P4 | badge_service.dart countBeatenPrs | drop `earlierMax > 0` | RED (pure first-ever / 0 kg cases, checkAll first-ever) | 12 |
| P5 | countBeatenPrs | drop `w > earlierMax` (keep `earlierMax > 0`) | RED (later LIGHTER, stale is_pr pure, stale checkAll) | 3 |
| P6 | countBeatenPrs | date compare `<` to `<=` (self included) | RED, but NOT the same-date test: including self makes earlierMax equal w, so the same-date case still yields 0. Red on 5 other tests. | 5 |
| P6b | countBeatenPrs | `<=` excluding self (`!identical(other, r)`), the mutant that actually models "same-date counts as earlier" | RED (same-date test) | 1 |
| P7 | train_provider.dart PR scan | per-set reps ignored (average restored for rows with a per-set list) | RED (both bodyweight 12/10/8 tests) | 2 |
| P8 | train_provider.dart PR scan | weight from row-level weight_kg, not bestPerSetWeight (hand-built fixture) | RED (per-set weight fixture) | 1 |
| P9 | countBeatenPrs | count rows with is_pr==true instead of comparing weights | RED (stale-is_pr fixtures, pure and checkAll, plus first-ever) | 7 |
| P12 (R6B-F2) | train_provider.dart PR scan | remove the session-date skip (same-day rows count as earlier) | RED (same-day-only no-PR test, same-day-110 mirror test) | 2 |
| P13 (extra) | train_provider.dart lookup | weight lookup `exercise.name.toLowerCase()` instead of exerciseNameKey | RED (trailing-space test) | 1 |

The plan's literal P6 (`<=` including self) is equivalent for the same-date case; P6b is the real same-date mutant.
Survivors: none.

**Coordinator re-verification.** Removing `earlierMax > 0 &&` in `BadgeService.countBeatenPrs` reddened 12 tests (13
passed, 12 failed); restored byte-identically.

**Ban test.** The first version banned the comparison SHAPE (`['type'] ==/!= 'exercise_log'`, both operand orders).
Reintroducing `raw['type'] == 'exercise_log'` in `badge_service.dart` turned it red (2 passed, 1 failed). The B-pass
(F1) showed that a regex on that shape misses the pre-fix lifetime-volume spelling
`final type = v['type']?.toString(); if (type != 'exercise_log') continue;`. The test now bans the quoted literal
itself, except the restore writer's single map entry (exactly one hit in `sync_workout.dart`). Mutants, each restored
by sha256:

| id | edit | result |
|---|---|---|
| B-M1 | the pre-fix spelling re-added in the `workout_repository.dart` lifetime loop | RED (3 passed, 1 failed); the old regex would not match it |
| B-M2 | a Dart 3 map-pattern reader `{'type': 'exercise_log'} => true` added to `sync_workout.dart` | RED (3 passed, 1 failed) |
| B-M3 | the scanner regex reverted to the old comparison shape | RED (1 passed, 3 failed: the spelling fixtures) |
