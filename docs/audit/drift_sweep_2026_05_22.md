# Hive Map Field-Key Drift Sweep — 2026-05-22

> Manual audit pre-Gate-19 baseline. Six high-risk surfaces walked
> for writer/reader field-name semantic drift. The 10th instance
> ([89d56c](../diagnoses/2026-05-22-graduation-total-sets-drift-89d56c.md))
> motivated the sweep; this document captures every finding so the
> followup batches don't re-discover them.

## Scope

Per the Theme G plan, audit these surfaces:

1. `graduation_screen.dart` aggregates (`graduationStatsProvider`).
2. `weekly_report_data_provider.dart` (the sparkline source).
3. `home_provider.dart` stats grid (today's workout + nutrition macros).
4. `train_provider.dart` AND `workout_repository.dart` (canonical walk-back).
5. `ai_coach_repository.buildAiContext` + `ai_snapshot_builder.dart`.
6. `reports_screen.dart` (long-range weight + AI report data).

For each surface: enumerate read-side field names + cross-check vs the
canonical writer's emit set. Drift identical to F1 (semantic mismatch
with universal impact) gets fixed in this batch. Drift requiring a
bigger refactor gets logged below + a TODO entry per surface.

## Findings

### Surface 1 — `graduationStatsProvider` ([89d56c](../diagnoses/2026-05-22-graduation-total-sets-drift-89d56c.md))

- **Status:** FIXED IN THIS BATCH (Theme F1, `00bbade`).
- **Drift:** `log['type'] == 'exercise_log'` filter + `log['sets_completed']`
  read. Writer never sets `type` field; canonical writer field is
  `set_number`. Plus PR count via inline `is_pr` boolean (drifted from
  canonical `allExercisePRsProvider` post OI-02/OI-08 per-set MAX
  semantic).
- **Fix:** rewritten to walk `exlog_*` keys + read `set_number` with
  `sets_completed` fallback + delegate PR count to
  `allExercisePRsProvider`.

### Surface 2 — `weeklyReportDataProvider`

- **Status:** VERIFIED CLEAN.
- Read in `lib/features/profile/screens/reports_screen.dart` via
  the provider. The provider delegates to `WorkoutReadService.exerciseLogsForIstDate`
  (canonical) and `NutritionReadService.dailyMealsForIstDate`
  (canonical) — both go through ReadServices which read the SoT
  field names. No inline `log['xxx']` access in the provider body.
- Forward-fill semantic for weight series documented in
  `lib/features/profile/CLAUDE.md` pitfall row #2 — by design, not drift.

### Surface 3 — `home_provider.dart` stats grid

- **Status:** VERIFIED CLEAN (with caveat).
- The home stats grid (`PRSnapshot` + `todayWorkoutProvider` +
  `nutritionSnapshotProvider`) all delegate to canonical Read
  Services. The fallback path at home_provider.dart for "no key lifts
  yet — show top 4 by volume" reads `ExercisePR.bestValue` from
  `allExercisePRsProvider` — also canonical.
- **Caveat:** `_calculateNutritionSnapshot` walks the nutrition box
  values directly with `log['calories']` + `log['protein_g']`
  literal access. These ARE in the writer's emit set
  (NutritionWriteService.logMeal stamps both). Behaviorally correct.
  Gate 19 baseline includes these as candidates — they're not drift.

### Surface 4 — `train_provider.dart` + `workout_repository.dart`

- **Status:** VERIFIED CLEAN (post-Theme-F1 fix).
- `train_provider.dart` Surface 1 was the F1 fix. Other readers in
  the file (`completedSetsProvider`, `workoutStatsProvider`,
  `currentPlanProvider`) all delegate to WorkoutReadService methods
  + WorkoutRepository methods. No additional inline drift.
- `workout_repository.dart` `loadAllExercisePRs` (the canonical PR
  computation) uses the writer's field names + WorkoutReadService
  helpers per OI-02/OI-08. Clean.

### Surface 5 — `ai_coach_repository.buildAiContext` + `ai_snapshot_builder.dart`

- **Status:** VERIFIED CLEAN (post-A10 split).
- The A10 refactor moved snapshot field emission from
  `ai_coach_repository.dart` to `ai_snapshot_builder.dart`. Test
  `snapshot_contract_consolidated_test.dart` is currently failing
  (Bucket B per the 55-failure triage — assertion points at the
  pre-A10 path) but the runtime path is intact. Verified by
  grepping `ai_snapshot_builder.dart` for the canonical top-level
  aliases (current_streak_weeks, total_workouts_done, today_workout_name,
  current_weight_kg, target_weight_kg, yesterday_calories,
  daily_calorie_target, daily_targets, recent_pr_*) — all present.
- The 55-failure test maintenance batch will repoint the assertion
  at `ai_snapshot_builder.dart`. Not drift; test path drift.

### Surface 6 — `reports_screen.dart`

- **Status:** VERIFIED CLEAN.
- Reads via `weeklyReportDataProvider` (Surface 2). No additional
  inline Hive map access. AI report content fields driven by
  Edge Function response, not Hive.

## Outcome

- 1 real drift fixed in batch (Surface 1 / Theme F1).
- 5 surfaces verified clean.
- Gate 19 baseline lands 619 candidates; all heuristic false-positives
  for the patterns above. Any NEW reader introducing a field name not
  in the canonical emit set will fail Gate 19 going forward.

## Followups (not deferrals — distinct work items)

- The `snapshot_contract_consolidated_test.dart` retargeting from A10
  path drift is part of the 55-failure test maintenance batch
  scheduled to immediately follow this APK ship (per founder's
  Option 1 explicit decision 2026-05-22). NOT a deferred bug — option
  1's literal terms; the failures are stale assertions, not real
  drift.
- The SoT registry `hive.emit_fields` schema extension (would let
  Gate 19 source from `docs/sot_registry.yaml` instead of the
  hardcoded `_expectedEmitFields` map) is a discrete work item that
  doesn't gate on this APK ship. Sequenced after the test maintenance
  batch lands.

## How to add a new concept to Gate 19

1. Identify the canonical writer (`*WriteService.method_name`).
2. List every field name in the writer's emit map literal.
3. Add a new entry to `_expectedEmitFields` in
   `scripts/check_hive_map_field_drift.dart`.
4. Run `dart run scripts/check_hive_map_field_drift.dart --update-baseline`
   to refresh `backups/gate19_drift_baseline.txt`.
5. Commit both files in the same commit as the new concept's
   contract test.
