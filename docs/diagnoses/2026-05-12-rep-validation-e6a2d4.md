---
bug_id: e6a2d4
date: 2026-05-12
batch: APK Test #15.1
status: in_progress
symptom: "LAST: 50KG · 135 REPS" rendered above Leg Extension in active workout screen — 135 reps per set is unrealistic. Cloud `workout_log_exercises` had 3 corrupt rows from May 7 with set_number=15 + reps=110-150 (bulk-completion aggregates misinterpreted as per-set).
concept: workout_log_exercises_input_validation
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: _validateSetInputs / _validateRepsBound, line: 1322 }
  - { file: supabase/migrations/060_workout_log_exercises_realistic_bounds.sql, method_or_widget: ALTER TABLE ADD CONSTRAINT, line: 16 }
readers:
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: build (LAST hint above input), line: 1 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncWorkoutLogExercises, line: 1 }
hive_key_prefix: exlog_
hive_key_formula: "'exlog_${istDateStr}_${hash(name)}'"
sync_methods: [_syncWorkoutLogExercises]
restore_methods: [_restoreWorkoutLogExercises]
cloud_table: workout_log_exercises
cloud_columns:
  - reps
  - set_number
contract_test_path: test/contracts/rep_input_validation_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: |
  Two-layer fix:

  Layer 1 — Cloud. Migration 060 adds CHECK constraints:
    wle_reps_realistic       CHECK (reps IS NULL OR reps BETWEEN 0 AND 60)
    wle_set_number_realistic CHECK (set_number IS NULL OR set_number BETWEEN 0 AND 10)
  These are the canonical defenders. Any write violating the bound
  23514s, so no corrupt data can reach the database again.

  Layer 2 — Client. active_workout_screen _validateRepsBound(reps)
  surfaces the bound inline ("Reps must be ≤ 60 per set. Typo?") so
  the user gets feedback at input time instead of after a sync attempt
  fails with a confusing 23514. weight_reps / bodyweight_reps /
  weighted_bodyweight all route through the same helper (DRY).

  Plus one-shot SQL cleanup at fix time: DELETE FROM
  workout_log_exercises WHERE user_id = 'd7a67a37-...' AND (reps > 60
  OR set_number > 8). 3 rows removed (Leg Extension / Leg Curl / Leg
  Press all from May 7 21:20 UTC).
regression_test_planned:
  - test/contracts/rep_input_validation_test.dart
---

# Bug E — Reps in 100s / no input validation

## Symptom

Founder saw "LAST: 50KG · 135 REPS" rendered above today's Leg Extension entry. 135 reps per set is impossible — typo or bulk-completion confusion. Cloud query for the user_id with `reps > 50 OR reps IS NULL` returned 3 rows from May 7 21:20 UTC, all with `set_number=15` + `reps=110-150` on Leg Press / Leg Curl / Leg Extension. These were the bulk retroactive completions where weekly totals were typed into per-set fields.

## Root cause

Two-fold:

1. **No input bound** in active_workout_screen — the reps TextField accepted any integer. A typo of "135" instead of "15" went through without warning.
2. **No cloud CHECK constraint** — `workout_log_exercises.reps` accepted any value, so the corrupt rows persisted in cloud and resurfaced as "LAST: X reps" hints on subsequent sessions.

## Fix

### Layer 1 — Cloud (canonical)

Migration 060: `ALTER TABLE workout_log_exercises ADD CONSTRAINT wle_reps_realistic CHECK (reps IS NULL OR reps BETWEEN 0 AND 60)` + same shape for `set_number BETWEEN 0 AND 10`. Idempotent via `IF NOT EXISTS` guard. Applied via Supabase MCP at fix time.

### Layer 2 — Client (UX)

`active_workout_screen.dart` — new `_validateRepsBound(int reps)` helper with `_repsMin = 1`, `_repsMax = 60` constants. Called from `_validateSetInputs` for the three reps-bearing logging types (weight_reps, bodyweight_reps, weighted_bodyweight). Error message hints at typo: "Reps must be ≤ 60 per set. Typo? Cloud rejects values above this."

### One-shot historical cleanup

`DELETE FROM workout_log_exercises WHERE user_id = 'd7a67a37-...' AND (reps > 60 OR set_number > 8)` — removed the 3 corrupt rows from May 7. Founder's UI will now show realistic LAST hints.

## Verification

- 5 source-grep tests pass: migration SQL contains both CHECKs; client has constants + helper + ≥3 callers; clear error copy.
- Cloud cleanup confirmed: post-DELETE, founder's user has 0 rows with reps > 60 or set_number > 8.

## Related

- `feedback_no_deferrals.md` — Bug E ships with the rest of the batch.

## Skills evolution

This is the first time we've added a server-side CHECK constraint as a defense against bad user input. Adding to `docs/sot_registry.yaml` (in the skills-evolution sub-batch): every numeric user-input column on workout/nutrition tables should have a documented realistic bound + CHECK constraint. If the bound is "unbounded by design," that's documented explicitly.
