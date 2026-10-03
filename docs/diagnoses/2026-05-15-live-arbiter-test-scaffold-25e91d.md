---
bug_id: 25e91d
date: 2026-05-15
batch: APK Test #15.5 — live-arbiter test scaffold (agent A6)
status: in_progress
symptom: |
  Source-grep contract tests (test/contracts/sync_onconflict_natural_key_test.dart
  and siblings) pin the client `onConflict:` string but cannot prove the
  live Postgres schema has a UNIQUE / EXCLUDE constraint the arbiter
  resolver will accept. This blind spot caused two production incidents
  in two weeks:
    - 2026-05-12 (`3f8a91`): client onConflict was 'id' but live had a
      natural-key UNIQUE → 31+16 errors / 24h, orphan per-set rows.
    - 2026-05-15 (`76c8f4`): client switched to the natural key in
      `3f8a91` but the natural-key UNIQUEs were PARTIAL with
      WHERE (... IS NOT NULL); arbiter rejected → 47 errors / 60s.
  Closes the writer to DB-target drift test gap; future onConflict
  regressions caught pre-merge.
concept: cloud_upsert_natural_key_contract
sot_registry_entry: workout_log_exercises_sync, nutrition_logs_sync
writers:
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _syncWorkoutLogs, line: 134 }
  - { file: lib/core/services/sync/sync_workout.dart, method_or_widget: _syncExerciseLogs, line: 254 }
  - { file: lib/core/services/sync/sync_nutrition.dart, method_or_widget: _syncNutritionLogs, line: 121 }
readers:
  - { file: test/sql/onconflict_live_arbiter.sql, method_or_widget: live_arbiter_test, line: 1 }
  - { file: scripts/check_onconflict_live_arbiter.dart, method_or_widget: live_arbiter_runner, line: 1 }
hive_key_prefix: n/a
hive_key_formula: "n/a — this scaffold tests cloud-side schema, not Hive"
sync_methods:
  - SyncService._syncWorkoutLogs
  - SyncService._syncExerciseLogs
  - SyncService._syncNutritionLogs
  - SyncService._syncWaterLogs
  - SyncService._syncDailySteps
  - SyncService._syncStreaks
  - SyncService._syncSavedMeals
  - SyncService._syncWorkoutTemplates
  - SyncService._syncTemplateExercises
  - SyncService._syncScheduledWorkouts
  - SyncService._syncCustomExercises
  - SyncService._syncCustomFoods
restore_methods:
  - SyncService.restoreFromCloudForUser
cloud_table: workout_logs, workout_log_exercises, workout_log_sets, nutrition_logs, nutrition_log_items, water_logs, daily_steps, streaks, scheduled_workouts, workout_schedule_completions, workout_templates, template_exercises, user_saved_meals, user_custom_exercises, user_custom_foods, user_profile, user_progress, saved_diet_plans, notifications_inbox, sleep_logs, weight_logs, body_measurements, progress_photos, community_reviews, coach_memory, ai_coach_interactions
cloud_columns:
  - user_id, date, exercise_name
  - workout_log_id, exercise_id, set_number
  - user_id, date, meal_type
  - user_id, date
  - user_id, scheduled_date
  - user_id, week_start
  - user_id, name
  - template_id, order_index
  - user_id
  - id
contract_test_path: test/sql/onconflict_live_arbiter.sql
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations: []
telemetry_op_types:
  success:
    - live_arbiter_check_ok
  failure:
    - live_arbiter_check_fail
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "onConflict: 'id'", absent: false }
  - { pattern: "WHERE.*IS NOT NULL.*UNIQUE", absent: true }
proposed_fix: |
  Two new deliverables that exercise every onConflict pair found in
  `lib/core/services/sync/*` against the live Postgres:

  1. `test/sql/onconflict_live_arbiter.sql`
     A single SQL file that wraps `INSERT ... ON CONFLICT (...) DO
     UPDATE` for 26 unique (table, columns) pairs inside one
     `BEGIN ... ROLLBACK` transaction. Each upsert sits in its own
     `BEGIN ... EXCEPTION WHEN OTHERS THEN ... END` block and writes a
     row into a temp `_v_results(label, status, sqlstate, msg)` table.
     Final `SELECT * FROM _v_results` is the test report. Nothing
     persists because of the outer ROLLBACK.

  2. `scripts/check_onconflict_live_arbiter.dart`
     Pure-Dart CLI (no new deps; uses `dart:io HttpClient`) that:
       - reads the SQL file
       - resolves the Supabase Management API PAT (CLI flag → env
         `SUPABASE_ACCESS_TOKEN_FITNESS` → repo file at
         `supabase/.supabase/supabase access token.txt` → fallback env)
       - POSTs to `/v1/projects/<ref>/database/query`
       - parses the returned JSON rows
       - exits 0 when every row has `status='ok'`, exits 1 with the
         failing rows printed otherwise.

  Expected outcomes:
    PRE migration 064 (today's expected baseline before agent A1 ships):
      workout_logs              (user_id, date, exercise_name)              → FAIL 42P10
      workout_log_exercises     (workout_log_id, exercise_id, set_number)   → FAIL 42P10
      nutrition_logs            (user_id, date, meal_type)                  → FAIL 42P10
      Every other onConflict pair                                            → OK

    POST migration 064:
      All onConflict pairs → OK.

  Future regressions of either layer (writer renames the key OR a
  migration drops/partializes an arbiter index) trip the gate. The
  Dart runner is intended for the `/build-apk` Gate set or the
  pre-commit hook; this commit ships the scaffold only — wiring it
  into the gate set is a separate batch.
regression_test_planned: |
  Two-layer regression test:
    - test/sql/onconflict_live_arbiter.sql exercises every (table,
      onConflict-cols) pair against live Postgres in a rolled-back
      transaction.
    - scripts/check_onconflict_live_arbiter.dart parses the result
      and exits non-zero on any 'fail' row. Intended for /build-apk
      Gate 15 (live-schema arbiter check) — wiring deferred to a
      follow-up since this batch is scaffold-only.
---

# Live-schema onConflict arbiter test scaffold

## What changed

Two new files, no production code touched:

- `test/sql/onconflict_live_arbiter.sql` — 26 `INSERT ... ON CONFLICT`
  test cases inside `BEGIN ... ROLLBACK`. Each case wraps the upsert in
  a per-case `BEGIN ... EXCEPTION ... END` so one failure doesn't abort
  the rest; results accumulate in a temp `_v_results` table that is
  `SELECT`ed at the end.
- `scripts/check_onconflict_live_arbiter.dart` — Dart CLI that runs the
  SQL via the Supabase Management API and exits 0 / 1 / 2.

## (table, onConflict-columns) inventory

Discovered via `Grep "onConflict" lib/core/services/sync/`:

| # | Table                            | onConflict columns                            | Source           |
|---|----------------------------------|-----------------------------------------------|------------------|
| 1 | `coach_memory`                   | `user_id`                                     | sync_coach       |
| 2 | `ai_coach_interactions`          | `id`                                          | sync_coach       |
| 3 | `nutrition_logs`                 | `user_id,date,meal_type`                      | sync_nutrition   |
| 4 | `nutrition_log_items`            | `id`                                          | sync_nutrition   |
| 5 | `water_logs`                     | `user_id,date`                                | sync_nutrition   |
| 6 | `user_saved_meals`               | `id`                                          | sync_nutrition   |
| 7 | `community_reviews`              | `id`                                          | sync_community   |
| 8 | `user_custom_exercises`          | `id`                                          | sync_community   |
| 9 | `user_custom_foods`              | `id`                                          | sync_community   |
| 10 | `user_profile`                  | `user_id`                                     | sync_profile     |
| 11 | `user_progress`                 | `user_id`                                     | sync_workout, sync_restore_completeness |
| 12 | `notifications_inbox`           | `id`                                          | sync_restore_completeness |
| 13 | `sleep_logs`                    | `id`                                          | sync_health      |
| 14 | `weight_logs`                   | `id`                                          | sync_health      |
| 15 | `body_measurements`             | `id`                                          | sync_health      |
| 16 | `progress_photos`               | `id`                                          | sync_health      |
| 17 | `daily_steps`                   | `user_id,date`                                | sync_health      |
| 18 | `workout_logs`                  | `user_id,date,exercise_name`                  | sync_workout     |
| 19 | `workout_log_exercises`         | `workout_log_id,exercise_id,set_number`       | sync_workout     |
| 20 | `workout_log_sets`              | `workout_log_id,exercise_id,set_number`       | sync_workout (via WriteService) |
| 21 | `workout_schedule_completions`  | `user_id,scheduled_date`                      | sync_workout     |
| 22 | `streaks`                       | `user_id,week_start`                          | sync_workout     |
| 23 | `workout_templates`             | `user_id,name`                                | sync_workout     |
| 24 | `template_exercises`            | `template_id,order_index`                     | sync_workout     |
| 25 | `scheduled_workouts`            | `user_id,scheduled_date`                      | sync_workout     |
| 26 | `saved_diet_plans`              | `user_id`                                     | sync_restore_completeness |

## Pre vs post migration 064

Migration `064_fix_partial_unique_arbiter.sql` (agent A1, same day) backfills NULLs, `SET NOT NULL`s 4 columns, drops the 3 partial UNIQUE indexes, and recreates them as plain UNIQUE indexes. Until it lands the arbiter check fails for those 3 pairs.

## How the runner authenticates

The Dart script reads `supabase/.supabase/supabase access token.txt` by default (the same gitignored PAT used by `.claude/deploy_via_api.js`) and POSTs to `https://api.supabase.com/v1/projects/dedsavbjuwgarrhphgnl/database/query` with `{"query": "<sql>"}`. CLI flag and env-var overrides exist for CI.

## Why source-grep alone is insufficient

`test/contracts/sync_onconflict_natural_key_test.dart` proves the client SAID "natural key" — it cannot prove Postgres ACCEPTS the natural key. The 2026-05-15 incident (`76c8f4`) is the canonical proof: the source-grep test was green for 3 days while production threw 42P10 because the unique indexes were partial.

## Follow-ups

- Wire `scripts/check_onconflict_live_arbiter.dart` into `/build-apk` as Gate 15.
- Consider an opt-in pre-commit hook variant for engineers who can reach the Management API.
- If a future Edge Function adds upserts with `onConflict:`, append matching cases to the SQL file (one block per pair).
