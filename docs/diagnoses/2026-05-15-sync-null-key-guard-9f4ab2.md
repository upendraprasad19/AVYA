---
bug_id: 9f4ab2
date: 2026-05-15
batch: Audit 2026-05-15 belt-and-suspenders null-key guard
status: in_progress
symptom: |
  Hypothetical (defence-in-depth) — no production occurrence yet.

  If the natural-key columns on `workout_logs`, `workout_log_exercises`,
  `workout_log_sets`, or `nutrition_logs` ever become NULLable (schema
  regression) AND a Hive row is missing one of those fields, the cloud
  upsert would either 23502 (silently swallowed by the outer try/catch)
  or worse — silently merge unrelated rows onto a single null-keyed
  cloud row, producing data loss with no audit trail.

  This guard wires belt-and-suspenders client-side validation: when any
  natural-key column on a Hive source-row is null/empty, the upsert is
  skipped and a `sync_skipped_null_natural_key` event is emitted to
  `client_errors` so production occurrences are auditable from day 1.
concept: sync_natural_key_guard
sot_registry_entry: workout_log_exercises_sync, nutrition_logs_sync
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _syncWorkoutLogs, line: 113 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _syncExerciseLogs_summary, line: 232 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _syncExerciseLogs_per_set, line: 271 }
  - { file: lib/core/services/sync/sync_nutrition.dart, method_or_widget: _syncNutritionLogs, line: 134 }
readers:
  - { file: supabase/functions/weekly-recalc/index.ts, method_or_widget: server, line: 1 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: server, line: 1 }
hive_key_prefix: wlog_, exlog_, nlog_
hive_key_formula: "wlog_<istDate>, exlog_<istDate>_<exerciseNameHash>, nlog_<localKey>"
sync_methods:
  - SyncService._syncWorkoutLogs
  - SyncService._syncExerciseLogs
  - SyncService._syncNutritionLogs
restore_methods:
  - SyncService._restoreWorkoutLogs
  - SyncService._restoreExerciseLogs
  - SyncService._restoreNutritionLogs
cloud_table: workout_logs, workout_log_exercises, workout_log_sets, nutrition_logs
cloud_columns:
  - user_id
  - date
  - exercise_name
  - workout_log_id
  - exercise_id
  - set_number
  - meal_type
contract_test_path: test/contracts/sync_natural_key_guard_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - sync_skipped_null_natural_key
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "log['date']", absent: false }
  - { pattern: "log['workout_name']", absent: false }
  - { pattern: "log['meal_type']", absent: false }
proposed_fix: |
  At each of the 4 upsert sites, read the natural-key column(s) into
  local `String?` guards, `.trim()` them, and if any are null or empty:

    unawaited(ErrorTelemetry.logEvent(
      'sync_skipped_null_natural_key',
      message: 'table=<name> key=<hiveKey> <col>_null=<bool> ...',
    ));
    continue;

  The Hive row is preserved (no destructive cleanup) so a subsequent
  sync with a corrected source-row will succeed. The telemetry op_type
  `sync_skipped_null_natural_key` lands in `client_errors.op_type` and
  can be alerted on if the count starts climbing.

  Per-set rows in `workout_log_sets` get a two-tier guard: the parent
  natural-key (workout_log_id, exercise_id) is validated for the whole
  batch, and individual rows with a null `set_number` are dropped from
  the batch with their own telemetry emission so per-set noise is
  distinguishable from parent-key drops.
regression_test_planned:
  - test/contracts/sync_natural_key_guard_test.dart
---

# Audit 2026-05-15 — sync natural-key guard

`closes-diagnose: 9f4ab2`

## Symptom

Defence-in-depth — no production occurrence yet. Adds belt-and-suspenders
guards at the 4 upsert sites where natural-key onConflict targets were
introduced by audit 2026-05-12 P0-A + P0-B (closes-diagnose 3f8a91).

## User-visible impact

None today. Hypothetical: if a cloud schema migration ever drops the
NOT NULL constraint on `date` / `exercise_name` / `meal_type` /
`workout_log_id` / `exercise_id` / `set_number`, PostgREST would happily
merge multiple unrelated rows onto a single null-keyed cloud row. The
existing 23502 catch path would not protect us. This guard ensures
client-side bookkeeping skips + logs the row before it can be sent.

## Root cause

Belt-and-suspenders only — there is no live root cause. Codified because
the 2026-05-12 audit demonstrated that PostgREST's `onConflict` is a
hint, not a contract: the natural keys live in indexes the client cannot
inspect at sync time. Guarding on the client gives us auditable
telemetry the moment a regression appears.

## Reproducer

There is no live reproducer. Synthetic: craft a Hive row with
`{date: null, workout_name: 'Push Up'}`, call `syncWorkoutData()`, and
observe a `sync_skipped_null_natural_key` event in `client_errors`
instead of a 23502 error.

## Fix applied

4 upsert sites in `lib/core/services/sync/sync_workout.dart` (3 calls)
and `lib/core/services/sync/sync_nutrition.dart` (1 call) now read the
natural-key columns into local `String?` guards before the upsert. On
null/empty, `unawaited(ErrorTelemetry.logEvent('sync_skipped_null_natural_key', ...))`
is emitted and the loop `continue`s.

Contract test `test/contracts/sync_natural_key_guard_test.dart` source-
greps each site (using `_sync_service_source.dart`'s concatenated facade
since the part-file split landed in `refactor/sync-service-part-split`).

## Codex agent stanza

- agent_id: claude-opus-4-7-audit-2026-05-15-a2
- preamble_version: docs/agent_brief_preamble.md@v3
- writer_file_line: lib/core/services/sync/sync_workout.dart:113, lib/core/services/sync/sync_workout.dart:232, lib/core/services/sync/sync_workout.dart:271, lib/core/services/sync/sync_nutrition.dart:134
- reader_file_line: supabase/functions/weekly-recalc/index.ts, supabase/functions/weekly-report/index.ts
- evidence: 2026-05-12 audit (closes-diagnose 3f8a91) demonstrated PostgREST onConflict semantics + 47 × 23505 errors over 24h before natural-key switch. This patch adds defence-in-depth at the client write site so a future schema regression cannot reproduce that silent-merge failure mode.
- fix_locality: same-domain (sync_workout.dart, sync_nutrition.dart) — 4 local-guard blocks, ~80 lines of additions including comments
- risk: low — guards are pre-upsert; on healthy data, the trim/length checks pass and the upsert runs unchanged
