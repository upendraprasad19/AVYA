---
bug_id: 344121
date: 2026-05-06
batch: APK Test #12.4
status: shipped
symptom: Second cloud-side audit revealed 4 bugs — NutritionWriteService.onStateChanged hook missing, foodLogProvider missing from invalidation set, LoggingTypeRepairMigrator had unhandled edge cases, and app.dart was not wiring the new hook.
concept: sync_fanout_nutrition_domain
sot_registry_entry: sync_fanout_nutrition_domain
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: NutritionWriteService.onStateChanged, line: 1 }
readers:
  - { file: lib/app.dart, method_or_widget: App.initState, line: 1 }
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
proposed_fix: Add NutritionWriteService.onStateChanged hook; wire from app.dart initState to invalidate foodLogProvider; fix LoggingTypeRepairMigrator edge cases.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 344121305413babc008be3aaa0991d96ed4e7b98
Subject: fix: APK Test #12.4 — 4 bugs from second cloud-side audit (1.0.0+11)
Files changed: lib/app.dart (+22 lines), lib/core/services/logging_type_repair_migrator.dart (+285 lines), lib/core/services/nutrition_write_service.dart (+46 lines)
