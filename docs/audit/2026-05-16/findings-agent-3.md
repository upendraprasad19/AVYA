# Agent 3 Findings — Cluster 4 (DB column-by-column live verification)

**Date:** 2026-05-16 · **Scope:** 32 non-zero tables, 385 columns audited via live MCP execute_sql

**CSV at:** `docs/audit/2026-05-16/db-coverage.csv` (385 rows per Agent 3 report)

## CONFIRMED BUGS

### F3-1.1 — 🚨 `coach_memory.coach_notes` 100% NULL — AI memory lost on reinstall (HIGHEST IMPACT)
- **Live SQL:** `null_count = 4 / total = 4` (all rows).
- **Hive writer:** `ai_coach_repository.dart:787` writes `coachBox['coaching_notes']`.
- **Client cloud sync:** `sync_coach.dart:12-49` `syncCoachMemoryNow` projects 8 muster fields (`committed_at`, `committed_to_lt_cdr`, `induction_completed_at`, `why_now`, `definition_of_winning`, `known_injuries`, `typical_wake_time`, `preferred_workout_time`, `body_part_priorities`) — **no `coach_notes`**.
- **Server:** `grep coach_notes supabase/functions/` returns ONLY type declaration at `_shared/coach_memory.ts:31`. No Edge Function writes the column.
- **Restore:** `sync_coach.dart:202-204` READS `row['coach_notes']` and writes to `coachBox['coaching_notes']` — but cloud is always NULL so nothing comes back.
- **Result:** Hive `coaching_notes` never escapes the device. On reinstall, AI coach has no memory of the user.
- **This is the 9th writer/reader drift instance** — and the most severe.
- **Fix:** add `putIfPresent('coaching_notes')` mapped to cloud column `coach_notes`, e.g.:
```dart
final notes = coach.get('coaching_notes');
if (notes != null) payload['coach_notes'] = notes;
```

### F3-1.2 — 🚨 `users.terms_accepted_at` + `terms_version` 100% NULL — DPDP compliance gap
- **Live SQL:** both columns `null_count = 4, total = 4`.
- Writer in `terms_modal.dart:65-68` writes to userBox; upward sync at `auth_provider.dart:508-516` only fires when userBox value is non-null.
- Per CLAUDE.md §19 APK Test #2 Q2, consent moved to inline checkbox on sign-up form. The checkbox tap never writes `userBox['terms_accepted_at']` — upward sync never fires.
- **DPDP §22 audit gap.**
- **Fix:** in sign-up flow, on SIGN UP tap, write `userBox['terms_accepted_at'] = DateTime.now().toIso8601String()` + `userBox['terms_version'] = AppConstants.termsVersion`. Existing `_ensureLocalUser` upward sync will pick them up.

### F3-1.3 — `workout_schedule_completions.duration_seconds` 100% NULL — writer reads wrong field
- **Live SQL:** `null_count = 11, total = 11`.
- Writer at `sync_workout.dart:424-432` projects `'duration_seconds': entry['duration_seconds']` from Hive `schedule_<date>` entry.
- Schedule entries don't carry `duration_seconds` — that lives on `wlog_<ms>` (workout log row).
- Cross-check: `workout_logs.duration_seconds` is 0/8 NULL (correctly populated). Data exists, just not joined into completion projection.
- **Fix:** writer looks up `wlog_*` by date and reads `duration_seconds` from it.

### F3-1.4 — `nutrition_log_items.food_id` 100% NULL — architectural choice; blocks analytics
- **Live SQL:** `null_count = 7 / 7`.
- Writer (`sync_nutrition.dart:145-179`) explicitly comments "skip food_id entirely" because bundled food DB uses string keys.
- **Fix:** drop the column OR write deterministic UUID-v5 of canonical food id.

## FRAMEWORK_GAP

### F3-1.5 — Latent partial-UNIQUE arbiter trap (Test #16 P0-A class residual)
- **Live SQL:** `uniq_user_custom_exercises_user_name (user_id, lower(name)) WHERE (user_id IS NOT NULL AND name IS NOT NULL)` + `uniq_user_custom_foods_user_name` (same shape).
- Writer (`sync_community.dart:127`) uses `onConflict: 'id'`. If `(user_id, lower(name))` re-inserts with NEW deterministic `id`, Postgres trips 23505.
- Comments at `sync_community.dart:99,220-223` show this was a prior bug — same class as Migration 064 closed elsewhere.
- **Fix:** extend `scripts/check_onconflict_live_arbiter.dart` to warn on tables where a non-arbiter partial UNIQUE could trip during `onConflict: 'id'` upserts.

## DEAD_SCHEMA_CANDIDATES (~17 columns across 7 column-groups)

### F3-2.1 — `workout_logs` 8 legacy per-exercise columns 100% NULL each
`scheduled_workout_id, template_id, exercise_id, sets_completed, reps_completed, weight_kg, distance_km, rpe`. Post-Test-#6 these moved to `workout_log_exercises` + `workout_log_sets`. Drop candidates. (rpe already flagged in audit P2-F.)

### F3-2.2 — `workout_templates.description` + `estimated_duration_mins` (4/4 NULL each)
Template-builder UI never exposes these inputs.

### F3-2.3 — `template_exercises.exercise_id, rest_seconds, prescribed_weight, prescribed_time_secs, notes` (all 18/18 NULL)
Same: builder UI doesn't surface; writer projects conditionally.

### F3-2.4 — `user_progress.experience_last_calculated` (4/4 NULL) — zero writers in entire codebase.

### F3-2.5 — `user_preferences.biggest_obstacle` (2/2 NULL) — only the projection at `sync_profile.dart:194`, no UI writer.

### F3-2.6 — `ai_coach_interactions.was_helpful` (27/27 NULL) — no thumbs-up/down UI.

### F3-2.7 — `workout_log_exercises.notes` (72/72 NULL) — writer projects, but no UI for per-exercise notes.

## LOW_USAGE (do NOT act)

Columns reflecting tester behavior, not bugs. Writers all healthy:
- `coach_memory` 8 muster fields (4/4 NULL) — 3-question muster never completed by 4 test users
- `user_profile.preferred_workout_time` (4/4) — mirror of muster
- `user_profile.body_fat_assessed_at` (4/4) — AI body-composition never run
- `water_logs.urine_color / urine_status` (13/13) — no urine logged
- `user_stat_snapshots.photos / measurements` (6/6) — no photos / no measurements
- `ai_coach_interactions.snapshot_id` (21/27), `tokens_used` (17/27), `tool_calls` (26/27) — partial; `in_app_orphan` failure-path skips these
- `workout_log_exercises.distance_km` (72/72), `workout_log_sets.distance_km` (221/221) — no cardio-with-distance

## Type-drift check (9 columns) — PASS

All Dart writer types match cloud column types. Zero drift detected. Includes `user_profile.injuries → text[]` ✅.

## `onConflict` arbiter audit — PASS

Migration 064 verified holding. All current arbiters back a matching non-partial UNIQUE/PK. Two latent partial UNIQUEs (F3-1.5) remain on `user_custom_exercises` + `user_custom_foods`.

## Summary

| Class | Count |
|---|---|
| CONFIRMED_BUG | 4 (1.1 coach_notes / 1.2 terms / 1.3 schedule duration / 1.4 food_id) |
| FRAMEWORK_GAP | 1 (1.5 latent partial-UNIQUE) |
| DEAD_SCHEMA_CANDIDATE | 7 column-groups / ~17 columns |
| LOW_USAGE (not act) | 7 column-groups |
| Type drift | 0 |
| onConflict mismatches | 0 |

**Highest impact:** F3-1.1 (coach_notes) — AI memory lost on reinstall. Top-priority Phase E fix.
