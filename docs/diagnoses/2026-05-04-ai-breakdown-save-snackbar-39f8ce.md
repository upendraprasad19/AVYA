---
bug_id: 39f8ce
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: AI breakdown card silently disappeared after save with no user feedback, making users believe the meal was not logged.
concept: hive_field_name_nlog
sot_registry_entry: hive_field_name_nlog
writers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: AiBreakdownNotifier.saveMeal, line: 1 }
readers:
  - { file: lib/features/nutrition/widgets/ai_breakdown_card.dart, method_or_widget: AiBreakdownCard, line: 1 }
hive_key_prefix: "nlog_"
hive_key_formula: "null"
sync_methods: [syncNutritionData]
restore_methods: []
cloud_table: nutrition_logs
cloud_columns: [total_calories, items]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [foodLogProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: AiBreakdownNotifier.saveMeal returns Future<WriteResult>; show snackbar + haptic on success; add _saving guard to prevent double-tap.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 39f8cecea536ddd365997960100b12bc1cbb3f23
Subject: fix(nutrition): AI breakdown save confirms with snackbar (Test #11 L1)
Files changed: lib/core/services/write_result.dart, lib/features/nutrition/providers/nutrition_provider.dart, lib/features/nutrition/widgets/ai_breakdown_card.dart, test/features/nutrition/ai_breakdown_save_confirmation_test.dart
