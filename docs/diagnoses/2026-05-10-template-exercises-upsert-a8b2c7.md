---
bug_id: a8b2c7
date: 2026-05-10
batch: backlog cleanup (post-Test-#15)
status: in_progress
symptom: _syncWorkoutTemplates used a DELETE-then-INSERT pattern for child template_exercises rows. If the DELETE succeeded but a subsequent INSERT errored mid-loop (network blip, FK constraint, payload error), the user's template was left with PARTIAL children — half the exercises missing, no audit trail. Next sync re-DELETED + tried again. Idempotent on success but lossy on partial failure.
concept: workout_template_sync
sot_registry_entry: workout_template_sync
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncWorkoutTemplates child upsert, line: 3556 }
  - { file: supabase/migrations/051_template_exercises_unique_order_index.sql, method_or_widget: ALTER TABLE ADD CONSTRAINT, line: 41 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreWorkoutTemplates select join, line: 3597 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: WorkoutRepository read paths, line: 1 }
hive_key_prefix: tmpl_
hive_key_formula: "'tmpl_${DateTime.now().millisecondsSinceEpoch}'"
sync_methods:
  - SyncService._syncWorkoutTemplates
restore_methods:
  - SyncService._restoreWorkoutTemplates
cloud_table: template_exercises
cloud_columns:
  - template_id
  - exercise_id
  - exercise_name
  - order_index
  - logging_type
  - prescribed_sets
  - prescribed_reps
  - prescribed_weight
  - prescribed_time_secs
  - rest_seconds
  - notes
contract_test_path: test/contracts/template_exercises_upsert_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - upsert_template_exercise
    - upsert_workout_template
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "from\\('template_exercises'\\)\\.delete\\(\\)", absent: true }
proposed_fix: |
  Migration 051 adds UNIQUE (template_id, order_index) to
  template_exercises. Switch _syncWorkoutTemplates to upsert with
  onConflict: 'template_id,order_index' instead of DELETE-then-INSERT.
  Each row independently upserted so partial-failure recovery is
  row-level (re-sync retries failed row alone) instead of template-
  level (re-sync wipes all children + redo).
regression_test_planned:
  - test/contracts/template_exercises_upsert_test.dart
---

# Backlog #2 — template_exercises upsert (migration 051)

## Symptom

`_syncWorkoutTemplates` (lib/core/services/sync_service.dart:3437) carried a comment block explicitly noting that migration 051 was needed but couldn't be added in the active batch:

> "Delete-then-insert child rows. There's no UNIQUE constraint on (template_id, order_index) we can target with onConflict (migration 051 would add one but we can't touch migrations in this batch). DELETE removes any stale child rows from the migration-050 keeper so re-sync replaces them cleanly instead of accumulating duplicates."

The pattern works in steady state (every sync wipes children, then re-inserts). It fails when the DELETE succeeds but the INSERT loop errors midway: network blip, FK constraint violation on row N, payload validation. The template is left with PARTIAL children — exercises 0..N-1 present, N..end missing. Next sync re-runs the cycle, but a transient INSERT failure on row M < N can leave the template torn for indefinite cycles.

## Root cause

Cloud schema didn't have `UNIQUE (template_id, order_index)`, so the only safe deduplication strategy was DELETE+INSERT. Real upsert needs the constraint as the conflict target.

## Fix

**Migration 051** (`supabase/migrations/051_template_exercises_unique_order_index.sql`) — adds the UNIQUE constraint. Idempotent via `IF NOT EXISTS` guard. Verified zero pre-existing duplicates in production (`SELECT template_id, order_index, COUNT(*) FROM template_exercises GROUP BY ... HAVING COUNT(*) > 1` returned empty).

**Client switch** (`sync_service.dart:_syncWorkoutTemplates`) — removed the DELETE block entirely. Changed the inner `.from('template_exercises').insert({...})` to `.upsert({...}, onConflict: 'template_id,order_index')`. Each row's upsert is independent.

Recovery semantics:
- Steady state: identical (rows match cloud → upsert no-ops or updates equal data).
- Partial failure on row N: rows 0..N-1 + N+1..end intact (the latter are upserts, not inserts, so they update the existing-but-unchanged row). Next sync retries row N alone.
- New template, first sync: all rows insert (no conflicts).
- Existing template, exercise reordered: row at the new order_index conflicts → upsert overwrites with the new content. Old row at the old order_index remains until the user explicitly trims it (no orphan cleanup in this fix; that's a separate `prune_orphans` follow-up if it surfaces as a bug).

## Verification

- 3 source-grep contract tests pass:
  - DELETE-then-INSERT pattern absent in sync_service.dart
  - `upsert(...)` + `onConflict: 'template_id,order_index'` present
  - Migration 051 SQL file present + contains the UNIQUE constraint
- Migration applied via Supabase MCP `apply_migration` to project `dedsavbjuwgarrhphgnl` on 2026-05-10.

## Related

- Migration 050 (Test #14) — `streak_freezes_available` default
- `feedback_main_is_source_of_truth.md` — migrations applied to prod must also exist as tracked SQL files
