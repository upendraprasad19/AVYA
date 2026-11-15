---
bug_id: 40a426
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: V4 plan generator had 38 cascade fallback failures (universalPool picks) because the exercise library pool was too shallow for advanced slot targets.
concept: cross_cutting
sot_registry_entry: cross_cutting
writers:
  - { file: assets/data/exercise_library.json, method_or_widget: exercise_library, line: 1 }
readers:
  - { file: lib/core/services/seed_service.dart, method_or_widget: SeedService, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: [movement_pattern, target_focus, equipment_tier, suitable_for]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Expand V4 exercise pool by adding 9 exercises and fixing 10 attribute gaps; verify with sample_plans_report.dart (target 0 attempt3/universalPool/none).
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 40a426bea14d5652de59464af3d7cad0ad660a50
Subject: fix(exercise_library): expand V4 exercise pool to eliminate 38 cascade failures (0 remaining)
Files changed: assets/data/exercise_library.json, lib/core/services/seed_service.dart
