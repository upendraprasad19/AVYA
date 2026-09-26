---
bug_id: acdcfb
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: FoodLogNotifier wrote flat-totals nlog_* rows without items[] array, so cloud nutrition_log_items got 0 rows for those logs and AI coach/weekly-report saw no meal items.
concept: hive_field_name_nlog
sot_registry_entry: hive_field_name_nlog
writers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: FoodLogNotifier.logFood, line: 1 }
readers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: NutritionWriteService.logMeal, line: 1 }
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
proposed_fix: FoodLogNotifier.logFood delegates to NutritionWriteService.logMeal with a single FoodItem built from the food map; items[] array now always written.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: acdcfbc10638345872c080ab55f0ed1c4392b5ed
Subject: fix(nutrition): FoodLogNotifier writes via WriteService with items[] (Test #11 C1)
Files changed: lib/features/nutrition/providers/nutrition_provider.dart
