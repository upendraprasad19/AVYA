---
bug_id: 8d85c2
date: 2026-05-17
batch: audit-2026-05-17 / OI-02 + OI-08 closure (post-+27 PR cumulative bug architectural follow-up)
status: fixed
symptom: |
  The reader side of the workout / nutrition / health domains had no
  canonical home. Each consumer re-implemented the same semantic inline.
  When the PR cumulative bug shipped on APK +27 (founder install
  2026-05-16) the per-set MAX semantic existed in TWO places —
  `WorkoutRepository.loadAllExercisePRs` (long-standing) and the
  file-private `_bestPerSetReps` / `_bestPerSetDuration` helpers added
  to `train_screen.dart` during the +27 fix. A third callsite would
  inevitably re-implement it inline and may diverge. This is the same
  architectural asymmetry that produced the pre-Test-#6 workout/nutrition
  writer/reader drift class — symmetrical writer-side WriteServices
  exist; the reader side never grew the matching primitive.
concept: workout_read_service
sot_registry_entry: workout_read_service
writers:
  - { file: lib/core/services/workout_read_service.dart, method: bestPerSetReps, line: 66 }
  - { file: lib/core/services/workout_read_service.dart, method: bestPerSetDuration, line: 89 }
  - { file: lib/core/services/workout_read_service.dart, method: bestPerSetWeight, line: 117 }
  - { file: lib/core/services/nutrition_read_service.dart, method: totalMacrosForDate, line: 56 }
  - { file: lib/core/services/nutrition_read_service.dart, method: totalMacrosFromItems, line: 92 }
  - { file: lib/core/services/health_read_service.dart, method: latestWeightKg, line: 30 }
  - { file: lib/core/services/health_read_service.dart, method: sleepHoursForDate, line: 60 }
  - { file: lib/core/services/health_read_service.dart, method: waterMlForDate, line: 75 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method: loadAllExercisePRs, line: 611 }
  - { file: lib/features/train/screens/train_screen.dart, method: _buildExpandedExercises, line: 887 }
  - { file: lib/features/nutrition/repositories/nutrition_repository.dart, method: dailyMacros, line: 46 }
hive_key_prefix: "exlog_, nlog_, weight_, sleep_log_, water_ml_"
hive_key_formula: "delegated — see per-domain WriteServices for the per-key formula"
sync_methods: [_syncExerciseLogs, _syncNutritionLogs, _syncWeightLogs, _syncSleepLogs]
restore_methods: [_restoreExerciseLogs, _restoreNutritionLogs, _restoreWeightLogs, _restoreSleepLogs]
cloud_table: "n/a — read-side service; per-domain cloud tables documented under their WriteService concepts"
cloud_columns: []
contract_test_path: test/contracts/workout_read_service_per_set_semantic_test.dart
ist_handling:
  - { file: lib/core/services/workout_read_service.dart, method: istDateForExlogRow, line: 138 }
  - { file: lib/core/services/health_read_service.dart, method: sleepHoursForDate, line: 60 }
  - { file: lib/core/services/health_read_service.dart, method: waterMlForDate, line: 75 }
provider_invalidations: [allExercisePRsProvider, currentPlanProvider, workoutStatsProvider, nutritionSummaryProvider, dailyNutritionProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "user-scoped Hive (workoutBox, nutritionBox, healthBox) — guarded by HiveUserSession + authUserIdTokenProvider rebuild chain at the Repository layer; ReadServices themselves are stateless and inherit the guard from the box they read"
forbidden_patterns_checked:
  - { pattern: "file-private _bestPerSetReps outside WorkoutReadService", absent: true }
  - { pattern: "file-private _bestPerSetDuration outside WorkoutReadService", absent: true }
  - { pattern: "inline Atwater fallback (4*P + 4*C + 9*F) outside NutritionReadService / nutrition_write_source.dart", absent: true }
proposed_fix: |
  Introduce three canonical READ services mirroring the writer-side
  pattern:

  1. `lib/core/services/workout_read_service.dart` — owns the per-set
     MAX semantic for `exlog_*` rows. Static methods `bestPerSetReps`,
     `bestPerSetDuration`, `bestPerSetWeight`, `istDateForExlogRow`.
     Instance method `exerciseLogsForIstDate(istDate)` does the
     indexed lookup + workoutBox scan fallback.

  2. `lib/core/services/nutrition_read_service.dart` — owns daily
     macro summation (with `is_saved_meal` exclusion) and per-item
     Atwater fallback summation. Date-key formula mirrors
     `NutritionWriteService.logMeal` verbatim (raw `date.year/.month/.day`
     — no IST shift; the writer doesn't shift and the reader must
     agree).

  3. `lib/core/services/health_read_service.dart` — owns
     `latestWeightKg`, `sleepHoursForDate`, `waterMlForDate`. IST date
     keys via `istDateStr(date)` matching `HealthWriteService`.

  Migrations:
  - `WorkoutRepository.loadAllExercisePRs` switch statement collapsed
    from ~90 lines of inline per-set math to 4 lines of delegation
    (one per non-cardio logging_type).
  - `train_screen.dart` file-private `_bestPerSetReps` /
    `_bestPerSetDuration` helpers DELETED; 2 callsites delegate to
    `WorkoutReadService.bestPerSetReps` / `.bestPerSetDuration`.
  - `NutritionRepository.dailyMacros` collapses to a single delegation
    + map-widening; public API preserved so transitive consumers
    (`nutrition_provider`, `home_provider`) require no changes.

  Registry: 3 new concepts (`workout_read_service`,
  `nutrition_read_service`, `health_read_service`) appended; 6 existing
  concepts (`workout_receipt_rendering`, `workout_log_edit_surface`,
  `weekly_report_data`, `hive_field_name_exlog`,
  `exercise_personal_records`, `weight_logs`) had the new service
  files added to their `reader_allow_files:` so the Phase 2
  reader-manifest gate passes.
regression_test_planned:
  - test/contracts/workout_read_service_per_set_semantic_test.dart
  - test/contracts/nutrition_read_service_total_macros_test.dart
  - test/contracts/health_read_service_test.dart
oi_closed: OI-02
---
# Body

## Symptom

Architectural / structural — no user-visible bug at the time of this
fix. The trigger was the post-+27 OI-02 audit finding: the PR
cumulative bug shipped because the per-set MAX semantic existed in
exactly TWO places (`loadAllExercisePRs` + `train_screen._bestPerSetReps`)
and a third callsite would inevitably re-implement it inline.

The +27 install screenshot ("Push Up 100 reps, Hanging Leg Raise 85
reps, Jump Rope 5m 30s" — all cumulative SUMs) was the canonical
failure mode this batch eliminates by making the semantic
non-reimplementable.

## Root cause

Architecture-gap. The writer side has had canonical WriteServices
since Test #6 (2026-05-01) — `WorkoutWriteService`,
`NutritionWriteService`, and (since 2026-05-16) `HealthWriteService`.
The reader side never grew the matching primitive. The PR cumulative
bug surfaced because `WorkoutRepository.loadAllExercisePRs` had inline
per-set math AND a sibling helper pair in `train_screen.dart` did the
same job — drift was a matter of when, not if.

OI-02 + OI-08 capture the same class of finding at two scopes:
- OI-08 is the immediate PR semantic centralisation (this batch's
  workout slice).
- OI-02 is the architecture-wide symmetric ReadService pattern
  (workout + nutrition + health).

OI-08 is subsumed by OI-02 — the workout slice of OI-02 IS OI-08.

## Fix

3 new files (zero new domain logic — every method is a 1:1 lift of
inline math from an existing reader):

- `lib/core/services/workout_read_service.dart` — 182 lines.
- `lib/core/services/nutrition_read_service.dart` — 127 lines.
- `lib/core/services/health_read_service.dart` — 82 lines.

3 migrations (existing readers now delegate):

- `WorkoutRepository.loadAllExercisePRs` — switch arms collapsed.
- `train_screen.dart` — file-private helpers deleted.
- `NutritionRepository.dailyMacros` — single-line delegation.

3 contract tests pinning the new semantics:

- `test/contracts/workout_read_service_per_set_semantic_test.dart`
  (15 cases — Map shape edge cases, legacy fallback rules, per-set
  MAX correctness).
- `test/contracts/nutrition_read_service_total_macros_test.dart`
  (6 cases — `is_saved_meal` exclusion, Atwater fallback, non-Map
  entry tolerance).
- `test/contracts/health_read_service_test.dart` (9 cases — latest
  weight ordering, sleep aliases, water int coercion).

Registry update:
- 3 new concepts appended.
- 6 existing concepts get `lib/core/services/{workout,health}_read_service.dart`
  added to `reader_allow_files:` so the Phase 2 reader-manifest gate
  passes (verified via `dart run scripts/check_reader_manifest_complete.dart`).

## Verification

- `flutter analyze --no-fatal-infos` — 67 pre-existing info-level
  issues; zero in changed files.
- `flutter test test/contracts/workout_read_service_per_set_semantic_test.dart
  test/contracts/nutrition_read_service_total_macros_test.dart
  test/contracts/health_read_service_test.dart` — 30 / 30 pass.
- `dart run scripts/check_reader_manifest_complete.dart` — OK.
- Full suite: pre-existing flake in
  `test/widgets/chat_bubble_photo_failure_test.dart` (passes in
  isolation; pre-existing on `main` per stash-baseline check).
  No new failures introduced by this batch.

## Closes

OI-02 (architecture-gap — no symmetric ReadServices for workout /
nutrition / health domains).

OI-08 (subsumed — PR per-set MAX semantic duplicated across 2 files
is the workout slice of OI-02).
