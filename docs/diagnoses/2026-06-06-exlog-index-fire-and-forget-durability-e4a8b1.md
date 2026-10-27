---
bug_id: e4a8b1
date: 2026-06-06
batch: restore-clobber-fix
status: fixed
blast_radius: account
symptom: >
  A just-logged exercise vanished from the Train/receipt UI after the user closed
  + reopened the app ("the logged exercise was gone"), while the schedule change
  and the weight log from the same session survived. Live on the founder's account
  (d7a67a37, APK +28) after logging today's back-day workout.
concept: exercise_logs_read_path
sot_registry_entry: exercise_logs_read_path
writers: >
  WorkoutWriteService.logExercise (workout_write_service.dart): the exlog ROW is
  written with `await box.put(key, entry)` (durable) but the per-day index update
  `_appendToIndex` was a `void` helper doing a fire-and-forget
  `box.put(indexKey, list)` (dropped Future), called WITHOUT await. _rescanAllPrsFor
  had the same fire-and-forget is_pr put.
readers: >
  workout_read_service.dart exerciseLogsForIstDate finds a day's logs via the
  `exercise_log_index_<date>` list. If that index entry never flushed to disk, the
  reader cannot find the (orphaned, still-on-disk) row → the log shows as "gone".
hive_key_prefix: exlog_
hive_key_formula: "exercise_log_index_<istDate> (per-day index list of exlog_ keys); rows keyed exlog_<istDate>_<uuidv5(name)>"
sync_methods: syncWorkoutData
restore_methods: not_applicable (the cloud restore was investigated + RULED OUT — no exlog delete in the restore, and cloud lacked today's row so it could not overwrite it)
cloud_table: workout_log_exercises
cloud_columns: not_applicable (local Hive write-durability bug; no column change)
contract_test_path: test/contracts/workout_write_durable_index_test.dart
ist_handling: not_applicable (the index key is already IST date-keyed at write)
provider_invalidations: not_applicable (write-durability; invalidation unchanged)
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (write goes through wrapUserScopedBox; unchanged)
forbidden_patterns_checked:
  - "a fire-and-forget box.put for exercise_log_index (void _appendToIndex + dropped Future) — now Future<void> + awaited."
  - "an unawaited _appendToIndex call in logExercise — now awaited."
  - "a fire-and-forget is_pr put in _rescanAllPrsFor — now Future<void> + awaited at both call sites (editLog, deleteLog)."
proposed_fix: >
  Make both fire-and-forget Hive puts durable. _appendToIndex is now `Future<void>`
  and awaits its `box.put(indexKey, list)`, and logExercise awaits it.
  _rescanAllPrsFor is now `Future<void>` and awaits its is_pr put, awaited at both
  call sites (editLog, deleteLog). The index/flag reaches disk before the writer
  returns (and before the UI paints), so an app close cannot lose it. The cloud
  restore was investigated and ruled out as the cause.
regression_test_planned: >
  test/contracts/workout_write_durable_index_test.dart — source-grep contract
  pinning that _appendToIndex + _rescanAllPrsFor are async + their puts awaited +
  their call sites awaited. A behavioral kill-before-flush test is NOT feasible
  (Hive's box close flushes pending writes, so a clean close+reopen cannot
  reproduce the process-kill race) — the await is the regressable durability
  surface.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "_appendToIndex + _rescanAllPrsFor are Future<void> + awaited; both call sites await; flutter analyze clean on the file" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "the exercise_log_index + is_pr writes are now durable before the writer returns; workout_write_durable_index_test pins the awaits" }
impact_analysis: >
  Account blast radius — any user who logged an exercise and closed the app before
  Hive flushed the index lost that log from the UI (the row survived on disk but
  was unindexed; re-logging re-added the index entry). The schedule + weight
  survived because their writes were awaited. Awaiting the index + is_pr writes
  makes them durable before the writer returns. Found via the founder's live +28
  report + telemetry; the cloud restore was investigated and ruled out. NOTE: a
  separate >1 min boot (an unconditional full cloud-restore on every cold-start) is
  a PERF issue, NOT this data-loss — flagged for a follow-up (returning-user guard).
---

# Just-logged exercise vanishes after restart — fire-and-forget index write (e4a8b1)

## What happened
The founder logged a back-day workout, saw it, closed + reopened the app (a >1 min
boot), and the logged exercise was GONE — while the schedule change + the weight
log from the same session survived. Re-logging worked.

## Root cause
`WorkoutWriteService.logExercise` writes the exlog ROW with `await box.put` (line
186, durable) but updated the per-day index via `_appendToIndex` — a `void` helper
doing a fire-and-forget `box.put(indexKey, list)` (line 330, dropped Future),
called WITHOUT `await` (line 189). The in-memory box updated (so the UI showed the
log), but the index disk-write was in-flight; on an app close before Hive flushed,
the index entry was lost. On reopen, the reader (`exerciseLogsForIstDate`, which
finds logs via `exercise_log_index_<date>`) could not find the orphaned,
still-on-disk row → "gone". The schedule + weight writes are awaited → durable →
survived. `_rescanAllPrsFor` (the is_pr rescan) had the same fire-and-forget put.

The cloud restore was investigated and RULED OUT: it has no exlog delete/sweep,
and cloud lacked today's row (the log never synced — network `Failed host lookup`),
so the restore could not have overwritten it.

## Fix
`_appendToIndex` + `_rescanAllPrsFor` are now `Future<void>` and `await` their
`box.put`s; every call site awaits them. The index/flag reaches disk before the
writer returns + before the UI paints, so an app close cannot lose it.

## Verification
- `test/contracts/workout_write_durable_index_test.dart` pins the awaits.
- `flutter analyze` clean on the file; existing workout-write contract tests pass.
- A behavioral kill-before-flush test is not feasible (Hive close flushes pending).

## See also
- lib/core/services/workout_write_service.dart (`_appendToIndex`, `_rescanAllPrsFor`, `logExercise`)
- lib/core/services/workout_read_service.dart (`exerciseLogsForIstDate` — reads the index)
- FOLLOW-UP (separate, NOT this bug): the >1 min boot = an unconditional full
  cloud-restore on every cold-start (perf) → a returning-user guard.
