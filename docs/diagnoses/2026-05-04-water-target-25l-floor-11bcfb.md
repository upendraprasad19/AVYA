---
bug_id: 11bcfb
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Four UI sites hardcoded 3000 ml for water target instead of computing it from user weight and activity, causing incorrect 100% at 3L for light users.
concept: water_target
sot_registry_entry: water_target
writers:
  - { file: lib/core/services/water_target_service.dart, method_or_widget: WaterTargetService.currentTargetMl, line: 1 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: waterTargetProvider, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [waterTargetProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Create WaterTargetService with formula + 2.5L floor + manual override; wire all 4 UI sites to read from it via waterTargetProvider.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 11bcfb1594cd30a9b29c31bdfacd25d44f318950
Subject: fix(nutrition): wire water target read-path with 2.5L floor + override (Test #11 E1)
Files changed: lib/core/services/water_target_service.dart (new), lib/features/nutrition/providers/nutrition_provider.dart, hydration_card.dart, home_screen.dart, nutrition_screen.dart, water_quick_sheet.dart
