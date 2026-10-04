---
bug_id: a16c1a
date: 2026-05-16
batch: APK Test #16.1 (Agent A)
status: in_progress
symptom: |
  Founder on +24 APK install (May 14 2026) reported two problems
  observed live in the production app:

  1. Train screen rendered 26+ exercise rows under May 14 when only
     4 exercises had actually been logged. Phantom rows appeared with
     subtly different `exlog_*` Hive keys for the same exercise on
     the same IST date.
  2. "VIEW CARD →" button on the home weekly-calendar today/yesterday
     tile did nothing — `onViewCard` resolved to null because
     `WorkoutReceiptData.fromExerciseLogs(DateTime.now())` returned
     null even though the workoutBox had 26+ exlog_* rows for the
     date.
concept: exlog_key_sot
sot_registry_entry: exlog_hive_key
writers:
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: exlogKey, line: 823 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _restoreExerciseLogs, line: 571 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: logSetWithPrRescan, line: 1097 }
readers:
  - { file: lib/features/train/widgets/workout_receipt_card.dart, method_or_widget: fromExerciseLogs, line: 288 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: getExerciseLogsForDate, line: 1097 }
  - { file: lib/core/services/exlog_key_migrator.dart, method_or_widget: runIfNeeded, line: 23 }
hive_key_prefix: exlog_
hive_key_formula: "exlog_<istDateStr>_<uuidV5(name.toLowerCase().trim())[0:8]>"
sync_methods:
  - SyncService.syncWorkoutData
restore_methods:
  - SyncService._restoreExerciseLogs
cloud_table: workout_log_exercises, workout_log_sets
cloud_columns:
  - workout_log_id
  - exercise_id
  - exercise_name
  - completed_at
  - set_number
contract_test_path: test/contracts/exlog_key_canonical_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
  - { file: lib/core/services/workout_write_service.dart, line: 801, fn: WorkoutWriteService.istDateStr }
provider_invalidations:
  - todayWorkoutProvider
  - currentPlanProvider
  - calendarWeekProvider
  - allExercisePRsProvider
telemetry_op_types:
  success:
    - exlog_key_migrator_run
  failure: []
cross_account_guard: HiveUserSession.openForUser must complete before migrator runs (existing RestoringScreen order is correct).
forbidden_patterns_checked:
  - { pattern: "'exlog_${ms}_${name.hashCode}'", absent: true }
  - { pattern: "'exlog_${dateStr}_${name.hashCode}'", absent: true }
  - { pattern: "'exlog_${...}'", absent: false }
proposed_fix: |
  Three writers were producing `exlog_*` keys with DIFFERENT formulas:

    1. CANONICAL (workout_write_service.dart:823) —
       `exlog_<istDateStr>_<uuidV5(name)[0:8]>`
    2. ROGUE A (sync/sync_workout.dart:587) —
       `exlog_<utc-substring>_<name.hashCode>`  (used by
       `_restoreExerciseLogs`). Comment falsely claimed parity with
       the canonical helper.
    3. ROGUE B (workout_repository.dart:1133) —
       `exlog_<millisecondsSinceEpoch>_<name.hashCode>` (used by
       `logSetWithPrRescan`, called from AI coach `logPR` tool).

  hashCode is platform-unstable (Dart spec says nothing about cross-
  isolate stability). The `ms` prefix made every re-log a fresh key.
  Together they explain both symptoms: 26+ phantom rows for the same
  exercise (every restore + every PR claim creating new keys), AND
  View Card silently no-oping (rogue restore writing the index key
  under UTC date while the receipt reader looks up IST date — after
  18:30 IST the two disagree).

  Fix in 4 layers:

  A. **Rogue writers rewritten** to delegate to
     `WorkoutWriteService.exlogKey(date, name)`. The sync rogue also
     now uses `WorkoutWriteService.istDateStr` for the index key so
     the index agrees with the canonical key's date component.

  B. **Migrator v7 → v8.** The existing `ExlogKeyMigrator` already
     handled both legacy shapes correctly (it iterates every
     `exlog_*` key and regroups by canonical key from each row's
     stored `name + date` fields, merging `sets[]` and rebuilding
     the date index). Bumping the guard flag forces a one-shot
     re-run on next launch to heal devices that already accumulated
     rogue rows.

  C. **`syncWorkoutData()` fire after migration.** RestoringScreen
     fires fire-and-forget `SyncService.syncWorkoutData()` once
     the migrator actually did work. Cloud `workout_log_exercises`
     keyed by natural columns absorbs the canonical Hive write
     without dedup conflicts.

  D. **Build gate + contract test.** New
     `scripts/check_exlog_key_canonical.dart` (mirrored by
     `test/contracts/exlog_key_canonical_test.dart`) source-greps
     `lib/` and fails on any future `'exlog_${...}'` interpolation
     outside the canonical helper + the migrator. Prevents
     regression — the recurring writer/reader drift class noted in
     `feedback_writer_reader_field_drift_recurring.md` (this is the
     7th instance since Test #6).

  E. **Receipt-builder backstop.** `WorkoutReceiptData.fromExerciseLogs`
     now scans `workoutBox` for any `exlog_*` row whose stored `date`
     matches the requested IST date when the
     `exercise_log_index_<date>` lookup is missing/empty. Defence-in-
     depth for the window between rogue-write and next-launch
     migration.
regression_test_planned:
  - test/contracts/exlog_key_canonical_test.dart
  - test/contracts/exlog_migrator_handles_rogue_shapes_test.dart
  - test/contracts/receipt_legacy_rows_fallback_test.dart
---

# APK Test #16.1 — exlog_* key single-source-of-truth

`closes-diagnose: a16c1a`

## Symptom

Founder reported on +24 APK install (May 14 2026):

- Train screen rendered 26+ exercise rows for May 14 when only 4
  exercises had been logged.
- Home weekly-calendar VIEW CARD button silently no-opped for today
  + yesterday despite the same 26+ rows being in workoutBox.

## User-visible impact

- Train/receipt rendering is the SoT for "what did I do today" — 26
  rows of phantom data destroyed trust in the log.
- View Card no-op blocked the post-workout share moment (a growth
  surface — workout cards are the primary social-share output).

## Root cause

Three writers producing `exlog_*` Hive keys with three different
formulas. See proposed_fix block above for the full taxonomy.

This is the 7th writer/reader drift instance since Test #6
(`feedback_writer_reader_field_drift_recurring.md`). The recurring
class is: a new writer is added without an SoT registry update + a
gate test pinning the contract, so the next refactor or hotfix
introduces a parallel writer with a subtly-different shape, and
readers silently disagree.

## Reproducer

Synthetic: write three rows with the three different key shapes for
the same `(date, exerciseName)`. Without the fix, all three coexist
in workoutBox; after fix-A the migrator merges them on next launch
into the single canonical key.

Live: install pre-fix APK +24, complete a workout, close and reopen
the app (triggers `_restoreExerciseLogs` re-syncing the same row
under a rogue key). Repeat across days — phantom rows compound.

## Fix applied

1. `lib/core/services/sync/sync_workout.dart:571` —
   `_restoreExerciseLogs` now calls
   `WorkoutWriteService.exlogKey(dateForKey, name)` and writes the
   index under `WorkoutWriteService.istDateStr(dateForKey)`.
2. `lib/features/train/repositories/workout_repository.dart:1132` —
   `logSetWithPrRescan` now calls
   `WorkoutWriteService.exlogKey(logDate, exerciseName)` and guards
   the date-index append against duplicate insertion (since the key
   is now deterministic, re-logs would otherwise duplicate the
   index entry).
3. `lib/core/services/exlog_key_migrator.dart:21` — guard flag bumped
   `exlog_key_migration_v7` → `_v8`. Existing migrator logic already
   correctly handles both rogue shapes (it re-derives canonical key
   from each row's stored `name + date` fields).
4. `lib/features/auth/screens/restoring_screen.dart:158` — fires
   `unawaited(SyncService.instance.syncWorkoutData())` when the
   migrator actually did work (i.e. flag was false before this call).
5. `lib/features/train/widgets/workout_receipt_card.dart:288` —
   defence-in-depth fallback when
   `exercise_log_index_<istDate>` is missing.
6. `scripts/check_exlog_key_canonical.dart` + sibling test in
   `test/contracts/exlog_key_canonical_test.dart` — gate + test pin
   the SoT rule.
7. `test/contracts/exlog_migrator_handles_rogue_shapes_test.dart` —
   behavioural test for the migrator with synthetic mixed-shape
   keys covering canonical / rogue-A / rogue-B / legacy-no-sets[]
   cases + idempotency.
8. `test/contracts/receipt_legacy_rows_fallback_test.dart` — pins
   the receipt-builder fallback when the IST date index is absent.

## Codex agent stanza

- agent_id: claude-opus-4-7-apk-test-16-1-agent-a
- preamble_version: docs/agent_brief_preamble.md@v3
- writer_file_line: lib/core/services/sync/sync_workout.dart:571, lib/features/train/repositories/workout_repository.dart:1132
- reader_file_line: lib/features/train/widgets/workout_receipt_card.dart:288, lib/features/train/repositories/workout_repository.dart, lib/core/services/exlog_key_migrator.dart:23
- evidence: founder observation on +24 APK install May 14 2026 — Train screen showed 26+ exercise rows when 4 were logged; View Card silently no-opped on today + yesterday. Two rogue writers grepped at sync/sync_workout.dart:587 (hashCode based) and workout_repository.dart:1133 (ms+hashCode based) — both bypassed WorkoutWriteService.exlogKey at workout_write_service.dart:823.
- fix_locality: cross-domain (sync/sync_workout.dart, workout_repository.dart, exlog_key_migrator.dart, restoring_screen.dart, workout_receipt_card.dart) — 5 file edits totalling ~70 lines of code changes + 1 new script + 3 new tests + 1 diagnose doc
- risk: medium — migrator merge logic concatenates sets[] in updated_at_ms order. For high-dup-count rows (founder's 26+ for one workout) the merged set list grows large but still represents real data (no truncation). Downstream readers tolerate large sets[]. Risk would materialise only if (a) some legacy rows had corrupted updated_at_ms causing reorder, or (b) a future writer added sets[] containing stale-pointer references; neither is plausible given the field is a plain JSON list of primitives.
