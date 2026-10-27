---
bug_id: 3f8a91
date: 2026-05-12
batch: Audit 2026-05-12 P0-A + P0-B
status: in_progress
symptom: |
  Production telemetry `client_errors` shows 31 × `upsert_exercise_log`
  + 16 × `upsert_nutrition_log` PostgrestException 23505 over 24h. The
  parent summary row (workout_log_exercises / nutrition_logs) fails to
  insert because the natural UNIQUE index trips before `id` does. The
  per-set rows in `workout_log_sets` (and per-item rows in
  `nutrition_log_items`) succeed inside their own try-block — orphans
  accumulate. 45 sets for Leg Press / Leg Curl / Leg Extension live
  with no parent row in cloud. AI weekly report cannot see them.
concept: cloud_upsert_natural_key_contract
sot_registry_entry: workout_log_exercises_sync, nutrition_logs_sync
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncExerciseLogs, line: 1413 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncNutritionLogs, line: 1687 }
readers:
  - { file: supabase/functions/weekly-recalc/index.ts, method_or_widget: server, line: 1 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: server, line: 1 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getMealsToday, line: 1 }
hive_key_prefix: exlog_, nlog_
hive_key_formula: "exlog_<istDate>_<exerciseNameHash> / nlog_<key>"
sync_methods:
  - SyncService._syncExerciseLogs
  - SyncService._syncNutritionLogs
restore_methods:
  - SyncService._restoreExerciseLogs
  - SyncService._restoreNutritionLogs
cloud_table: workout_log_exercises, nutrition_logs
cloud_columns:
  - id (PK)
  - workout_log_id
  - exercise_id
  - set_number
  - user_id
  - date
  - meal_type
contract_test_path: test/contracts/sync_onconflict_natural_key_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - upsert_exercise_log
    - upsert_nutrition_log
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "onConflict: 'id'", absent: true }
  - { pattern: 'onConflict: "id"', absent: true }
proposed_fix: |
  Switch both upserts to the natural-key onConflict target:
  - `workout_log_exercises` → `onConflict: 'workout_log_id,exercise_id,set_number'`
  - `nutrition_logs` → `onConflict: 'user_id,date,meal_type'`

  PostgREST will now generate `ON CONFLICT (natural_key) DO UPDATE`
  which matches the partial unique index. Legacy rows with mismatching
  deterministic `id` but matching natural key get merged into the
  canonical row. PK `id` stays unique but no longer the conflict target.
regression_test_planned:
  - test/contracts/sync_onconflict_natural_key_test.dart
---

# Audit 2026-05-12 P0-A + P0-B — sync onConflict natural-key contract

`closes-diagnose: 3f8a91`

## Symptom

Production `client_errors` shows 31 × `upsert_exercise_log` + 16 × `upsert_nutrition_log` PostgrestException 23505 rows over the last 24h (audit 2026-05-12). Per-set / per-item rows succeed in their own try-blocks while the parent summary row fails — orphan rows accumulate.

## User-visible impact

- Exercises re-logged under a slightly different Hive key produce a new deterministic `id` UUID. The summary row in `workout_log_exercises` fails to insert (23505 on the natural unique), but the per-set rows in `workout_log_sets` succeed. Result: 45 sets for Leg Press / Leg Curl / Leg Extension have no parent row → invisible to weekly AI report.
- Nutrition logs: the parent `nutrition_logs` insert fails, but per-item rows in `nutrition_log_items` succeed → calories without source attribution.

## Root cause

PostgREST's `onConflict` parameter is a HINT — it tells PostgREST which named constraint/unique to target for the `ON CONFLICT` clause. Passing `'id'` translates to `ON CONFLICT (id) DO UPDATE`. PostgreSQL itself then evaluates the row against every UNIQUE constraint. If a DIFFERENT unique trips first, PG raises 23505 instead of merging.

The live schema (verified 2026-05-12 via `pg_indexes`) has:
- `workout_log_exercises`: partial UNIQUE `uniq_workout_log_exercises_wlog_ex_set` on `(workout_log_id, exercise_id, set_number)`
- `nutrition_logs`: partial UNIQUE `uniq_nutrition_logs_user_date_meal` on `(user_id, date, meal_type)`

Both indexes match the "one row per natural identity" semantics the app actually wants. The PK `id` is structural plumbing; the natural keys are the truth.

## Reproducer

1. Log Push Up. Sync.
2. Edit + rename to "Pushup". Sync.
3. Hive key changes → deterministic `id` differs.
4. INSERT tries `ON CONFLICT (id) DO UPDATE`. No `id` collision.
5. But natural UNIQUE on `(workout_log_id, exercise_id, set_number)` trips. PG raises 23505.
6. Per-set rows succeed (already use natural-key onConflict) → orphan.

## Fix applied

Same-file (`lib/core/services/sync_service.dart`) edit, 2 onConflict targets changed + 2 comment blocks added. Plus `test/contracts/sync_onconflict_natural_key_test.dart` source-grep contract pinning the new targets so regression is impossible.

## Codex agent stanza

- agent_id: claude-opus-4-7-audit-2026-05-12
- preamble_version: docs/agent_brief_preamble.md@v3
- writer_file_line: lib/core/services/sync_service.dart:1413,1687
- reader_file_line: supabase/functions/weekly-recalc/index.ts, supabase/functions/weekly-report/index.ts
- evidence: live `client_errors` PostgrestException counts (24h window 2026-05-11 to 2026-05-12) and `pg_indexes` live schema verification
- fix_locality: same-file (sync_service.dart) — 2 lines changed, 2 multi-line comments added
- risk: low — natural-key path matches per-set / per-item siblings which have always used natural-key onConflict
