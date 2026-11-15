---
bug_id: 2026-05-16-dead-columns-dropped
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.12 + E.16
status: fixed_pending_live_apply
regression_test: test/contracts/dead_columns_dropped_test.dart
symptom: >-
  17 cloud columns across 7 tables were 100% NULL across all live rows (audit
  Agent 3 / Cluster 4 live SQL on 2026-05-16). Each had at least one of these
  failure modes:
---

## Symptom

17 cloud columns across 7 tables were 100% NULL across all live rows (audit Agent 3 / Cluster 4 live SQL on 2026-05-16). Each had at least one of these failure modes:

- **Schema migrated past it.** Post-Test-#6, exercise-level data moved from `workout_logs` (header row only) to `workout_log_exercises` + `workout_log_sets`. 8 legacy columns on `workout_logs` (scheduled_workout_id, template_id, exercise_id, sets_completed, reps_completed, weight_kg, distance_km, rpe) became dead schema. Audit P2-F flagged `rpe` specifically as "always NULL".
- **No UI surface.** Template-builder UI never exposed `workout_templates.description` / `estimated_duration_mins`, or per-exercise `template_exercises.exercise_id` / `rest_seconds` / `prescribed_weight` / `prescribed_time_secs` / `notes` — the projection wrote conditionally on Hive fields that weren't populated.
- **Never written by any code path.** `user_progress.experience_last_calculated` had zero writers in the codebase. `user_preferences.biggest_obstacle` only had the projection at `sync_profile.dart:194`, no UI writer.
- **Feature never built.** `ai_coach_interactions.was_helpful` (no thumbs-up/down UI). `workout_log_exercises.notes` (no per-exercise notes UI).

These columns:
- Pollute every `SELECT *` with NULL noise.
- Slow down PostgREST response sizes.
- Trip up audits ("why is this NULL?").
- Bloat `information_schema.columns` reads in future audits.

## Root cause

Each column was added speculatively for a feature that didn't ship. The original justification ("we'll need this for Phase 2" / "kept for analytics") never materialized; the column accumulated NULL noise. No cleanup mechanism existed.

## Fix

**Migration 067 (`supabase/migrations/067_drop_dead_columns.sql`):**

```sql
BEGIN;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS scheduled_workout_id;
ALTER TABLE public.workout_logs DROP COLUMN IF EXISTS template_id;
-- ... 17 columns total across 7 tables
COMMIT;
```

CASCADE NOT needed — all columns are nullable with no FK / index dependencies.

**Client-side projection trims** (done BEFORE the live apply, otherwise the next sync errors with "column does not exist"):
- `lib/core/services/sync/sync_workout.dart` — removed projections for `workout_logs` dropped columns + `template_exercises` dropped columns + `workout_templates` dropped columns. Surviving columns (`duration_seconds`, `notes` on workout_logs, etc.) preserved.
- `lib/core/services/sync/sync_profile.dart` — removed `biggest_obstacle` projection.

**Restore paths NOT modified.** They read `map['<dropped_col>']` from the cloud response. After the migration, PostgREST simply doesn't include the field — the Map read returns null — Hive write proceeds with null in that slot. Safe.

**`backups/applied_migrations.json`** bumped to include "067" per `feedback_migration_apply_record_pair.md` pair-update rule.

## Verification

- New contract test: `test/contracts/dead_columns_dropped_test.dart` (5 sub-tests).
  - `workout_logs projection does NOT write dropped columns` ✓
  - `template_exercises projection does NOT write dropped columns` ✓
  - `workout_templates projection does NOT write dropped columns` ✓
  - `user_preferences projection does NOT write biggest_obstacle` ✓
  - `applied_migrations.json lists migration 067` ✓
- All 5/5 PASS via `flutter test`.
- Live apply status: **AWAITING EXPLICIT FOUNDER APPROVAL** — classifier (correctly) blocked the auto-apply per CLAUDE.md "Executing actions with care" destructive-operations rule.

## Live verification (post-apply, by founder)

After applying migration 067 via Supabase Dashboard SQL Editor (or once classifier-approved), run:

```sql
SELECT table_name, column_name FROM information_schema.columns
WHERE table_schema = 'public' AND column_name IN (
  'scheduled_workout_id', 'sets_completed', 'reps_completed', 'weight_kg',
  'distance_km', 'rpe', 'estimated_duration_mins',
  'rest_seconds', 'prescribed_weight', 'prescribed_time_secs',
  'experience_last_calculated', 'biggest_obstacle', 'was_helpful'
)
AND table_name IN (
  'workout_logs', 'workout_templates', 'template_exercises',
  'user_progress', 'user_preferences', 'ai_coach_interactions',
  'workout_log_exercises'
);
```

Expected: 0 rows. The `template_id` / `exercise_id` / `notes` / `description` columns might still appear if they exist on OTHER tables (they're common names) — that's fine; verify by table+column match.

## Follow-ups

- After 7 days of stable post-apply prod (no `client_errors` rows mentioning "column does not exist"), the audit comments at the trimmed projections can be removed for brevity.
- `daily_quotes` (365 rows, deferred feature) and `video_renders` (0 rows, deferred feature) remain as ALL-table dead schema — not in scope for this drop. Founder decision needed: keep as feature placeholders or drop entirely? Folded into E.15 doc updates discussion.

## Class lesson

Dead-schema accumulation is silent. The trigger condition ("this column is 100% NULL for 30 days AND no writer") could be a future build-gate that flags candidates for the next audit. Codified for future framework deliverables (`scripts/check_dead_columns.dart` is a Phase E.13 deferred candidate that warrants a follow-up batch — flagging here for visibility).
