---
bug_id: 0f8d54
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Usage counters incremented on meal save rather than on API call, so users who analysed without saving saw incorrect 'remaining' counts diverging from server rate-limit trigger.
concept: hive_field_name_nlog
sot_registry_entry: hive_field_name_nlog
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: NutritionWriteService.logMeal, line: 1 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: FoodLogNotifier, line: 1 }
hive_key_prefix: "nlog_"
hive_key_formula: "null"
sync_methods: [syncNutritionData]
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [channel]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [foodLogProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Move counter increments to API-call sites (food_logger_section, ScanMealNotifier, cart_auditor_section, tool_dispatcher); remove increment from WriteService.logMeal.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 0f8d547357df39e39d444224be5c582235cf3dff
Subject: fix(nutrition): counters increment on API call + cart wired + real quantityG (Test #11 M1+M2+M4)
Files changed: lib/core/services/nutrition_write_service.dart, lib/features/ai_coach/services/tool_dispatcher.dart, lib/features/nutrition/providers/nutrition_provider.dart
