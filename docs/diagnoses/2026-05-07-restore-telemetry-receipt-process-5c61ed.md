---
bug_id: 5c61ed
date: 2026-05-07
batch: APK Test #12.6
status: shipped
symptom: Multiple issues — restore stack had HiveUserSession ordering bugs causing 30+ cold-start restore failures logged to client_errors; receipt chips needed per-set rendering; 5 IST drift sites remained; process bootstrap docs (sot_registry, naming_conventions, pre-commit hook) were missing.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: restoreFromCloudForUser, line: 1 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: AuthProvider, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: [syncWorkoutData, syncNutritionData]
restore_methods: [restoreFromCloudForUser]
cloud_table: workout_log_exercises
cloud_columns: [exercise_id, set_number, reps, weight_kg]
contract_test_path: "n/a — backfill"
ist_handling:
  - { file: lib/features/train/screens/active_workout_screen.dart, method_or_widget: ActiveWorkoutScreen, line: 1 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [restore_exercises, restore_nutrition, restore_profile]
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Fix HiveUserSession bootstrap ordering in restoreFromCloudForUser; add receipt per-set chips; sweep 5 IST drift sites; install pre-commit hook; create sot_registry.yaml and naming_conventions.md.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 5c61edc6cfe1e901d9eff611228f9226fd26fde9
Subject: feat: APK Test #12.6 — restore stack + telemetry + receipt chips + process bootstrap (1.0.0+13)
Files changed: lib/features/nutrition/widgets/todays_meals_card.dart, lib/features/profile/providers/profile_provider.dart, lib/features/train/screens/active_workout_screen.dart, lib/features/train/widgets/workout_receipt_card.dart, scripts/pre-commit.sh, scripts/setup-hooks.sh, supabase/functions/_shared/tools/progress/getProgressSummary.ts, test/contracts/ (5 new test files)
