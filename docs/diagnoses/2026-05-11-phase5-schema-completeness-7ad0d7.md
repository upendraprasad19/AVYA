---
bug_id: 7ad0d7
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 6 schema-completeness gaps. (H-13) `_restoreCustomExercises/Foods` wrote to legacy LIST keys (`custom_exercises` / `custom_foods`) while every reader scans per-key (`custom_exercise_*` / `custom_food_*`) → restored items vanished from `getCustomExercises()` and never re-synced. (H-14) `syncCommunityItems` had no `.limit()` or pagination — every app launch downloaded the entire approved community library. (H-25/26/27/28) Missing UNIQUE constraints / index across 4 tables — cross-device sync race could create duplicates that double-count. (H-31) `community_reviews` existed on prod but had no migration in source (Dashboard-created). (H-33) Two migration files shared the `050` prefix; filesystem ordering non-deterministic. (H-34) Source vs prod migration count mismatch.
concept: phase5_schema_completeness
sot_registry_entry: schema_completeness
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreCustomExercises + _restoreCustomFoods + syncCommunityItems pagination, line: 2772 }
readers: []
hive_key_prefix: "custom_exercise_*, custom_food_*"
hive_key_formula: "custom_exercise_<cloud_id> / custom_food_<cloud_id> (per-key, NOT legacy list)"
sync_methods: ["syncCommunityItems (paginated 500/page, 10-page ceiling)"]
restore_methods: ["_restoreCustomExercises", "_restoreCustomFoods"]
cloud_table: user_custom_exercises
cloud_columns: [id, user_id, name, created_at, approved_for_library]
contract_test_path: "n/a — schema migrations applied directly; covered by existing migrator + sync tests"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [restore_custom_exercises, restore_custom_foods, sync_community_items]
cross_account_guard: yes
forbidden_patterns_checked: ["custom_restore_writes_to_legacy_list_key", "syncCommunityItems_no_limit_or_pagination", "missing_unique_constraint_on_logical_keyset", "schema_only_in_prod_no_migration_source", "migration_prefix_collision"]
proposed_fix: (H-13) restore now writes per-key entries `custom_exercise_<cloud_id>` / `custom_food_<cloud_id>` matching the writer's prefix scan. Dedup by name (case-insensitive) against existing per-key entries. (H-14) `syncCommunityItems` paginated 500/page with a 10-page ceiling (5000 row hard cap per run). (H-25/26/27/28) migration 057 adds 4 indexes/constraints — `UNIQUE(user_id, lower(name))` on user_custom_{exercises,foods}; `idx(user_id, channel, created_at)` on ai_coach_interactions; `UNIQUE(user_id, date, meal_type)` on nutrition_logs; `UNIQUE(workout_log_id, exercise_id, set_number)` on workout_log_exercises. Each preceded by a dedup CTE keeping latest row. (H-31) migration 058 codifies community_reviews schema from prod (idempotent — CREATE IF NOT EXISTS + DROP+CREATE policies). (H-33) renamed `050_workout_templates_unique_user_name.sql` → `050b_workout_templates_unique_user_name.sql` to resolve numeric-prefix collision; updated dependent contract test. (H-34) reconciled in supabase/migrations/README_RECONCILIATION_2026-05-11.md — every prod entry mapped to a source file (most are Dashboard-renamed entries; one early "add_gdpr_referral_community_tables" bundle was later split into 035+037+049).
regression_test_planned:
  - "existing exlog/nlog migrator tests + restore_completeness_writes_test + templates_unique_constraint_test (updated for rename)"
---
# Audit Phase 5: schema completeness sweep

6 findings closed in one batch — see commit `425bc63` (Phase 3),
`fe340fa` (Phase 4), and the upcoming commit (Phase 5).

## H-13 — custom-item restore wrote to dead key

**Files:** `lib/core/services/sync_service.dart` lines 2772-2847.

Pre-fix: `_restoreCustomExercises` wrote
`customBox['custom_exercises']` (a List). `_syncCustomItems` and all
UI readers scan per-key (`custom_exercise_*`). Restored items lived
only in the list → invisible to writer + UI → never re-synced.

Fix: write per-key entries `custom_exercise_<cloud_id>` (deterministic
v5 UUID from the cloud row). Dedup by lower-case name against
existing per-key entries in customBox. Same pattern for foods.

## H-14 — `syncCommunityItems` unbounded download

**File:** `lib/core/services/sync_service.dart:3412-3490`.

Pre-fix: two PostgREST queries with `.eq('approved', true)` and no
`.limit()` or `.range()`. Every cold start downloaded the FULL
approved community library. At 1000 items = ~500KB / launch.

Fix: 500 rows / page, 10-page ceiling (5000 max per run). Order by
`created_at ASC` so retries cover earliest-unseen rows first;
`since` cutoff (`last_community_sync`) keeps each run bounded.

## H-25/26/27/28 — UNIQUE + index sweep

**Migration:** `supabase/migrations/057_schema_unique_indexes_h25_h26_h27_h28.sql`.

Each constraint is preceded by a dedup CTE that deletes duplicate
rows keeping the latest (by `created_at DESC NULLS LAST, id DESC`).
This makes the subsequent `CREATE UNIQUE INDEX` impossible to fail
on existing prod data.

- **H-25** `UNIQUE(user_id, lower(name))` on
  `user_custom_exercises` + `user_custom_foods`.
- **H-26** `INDEX(user_id, channel, created_at)` on
  `ai_coach_interactions` to support the food-text rate-limit
  trigger's `COUNT(*)` probe (existing index didn't cover `channel`).
- **H-27** `UNIQUE(user_id, date, meal_type)` on `nutrition_logs`
  — matches the WriteService SoT contract.
- **H-28** `UNIQUE(workout_log_id, exercise_id, set_number)` on
  `workout_log_exercises` — matches CLAUDE.md §11.

Applied to prod 2026-05-11.

## H-31 — `community_reviews` schema codified

**Migration:** `supabase/migrations/058_community_reviews_schema_in_source.sql`.

Pre-fix: table existed on prod but had no migration in source
(Dashboard-created). A fresh prod clone would have no record of
how to recreate it.

Fix: idempotent `CREATE TABLE IF NOT EXISTS` + RLS + 3 policies
(`DROP POLICY IF EXISTS ... CREATE POLICY ...`). No-op on prod;
clean install on a fresh DB.

## H-33 — `050` prefix collision

Pre-fix: two source files both prefixed `050_*`. Filesystem listing
order was non-deterministic.

Fix: renamed the workout-templates file →
`050b_workout_templates_unique_user_name.sql`. Updated dependent
test (`test/contracts/templates_unique_constraint_test.dart`) +
`backups/applied_migrations.json`.

## H-34 — source vs prod count reconciliation

**Doc:** `supabase/migrations/README_RECONCILIATION_2026-05-11.md`.

Reconciles the prod migration list (53 rows) against the source
directory (57 numbered + 3 timestamp-prefixed = 60 files):

- **Dashboard-renamed entries (13)** — applied via Dashboard SQL
  editor instead of `db push`. Schemas identical to source; only
  the registered migration name differs.
- **Bundled-then-split (1)** — `add_gdpr_referral_community_tables`
  was an early bundle; later split across 035+037+049 in source.
  Schema match is identical.
- **Idempotent / superseded (2)** — source files that didn't
  produce a distinct prod row.

The doc establishes the rule going forward: every applied migration
must use `supabase db push` OR MCP `apply_migration` with the EXACT
source filename, and every apply must update
`backups/applied_migrations.json` in the same commit per
`feedback_migration_apply_record_pair.md`.

## Deploys

Migrations applied to prod: 057, 058.

Suite: 1569 pass / 0 fail / 2 skip.

## Related

- `feedback_migration_apply_record_pair.md` (project memory)
- CLAUDE.md §15 (sync fan-out contract — H-13 closes the restore
  side of the same contract WriteServices own on the write side)
- 7ad0c1 / 052 (Phase 1 subscriptions RLS lockdown — same migration
  hygiene as 058)
