---
bug_id: 519075
date: 2026-05-06
batch: APK Test #12.2
status: shipped
symptom: Cloud-side audit surfaced multiple failures — logging_type repair migrator needed systematic rebuild, razorpay 409 detection was dead code (FunctionException class), sync had IST gaps, train screen had stale receipt rendering.
concept: hive_field_name_exlog
sot_registry_entry: hive_field_name_exlog
writers:
  - { file: lib/core/services/logging_type_repair_migrator.dart, method_or_widget: LoggingTypeRepairMigrator, line: 1 }
readers:
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: RazorpayService, line: 1 }
hive_key_prefix: "exlog_"
hive_key_formula: "null"
sync_methods: [syncWorkoutData]
restore_methods: []
cloud_table: workout_log_exercises
cloud_columns: [logging_type, exercise_id]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [currentPlanProvider, workoutStatsProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Rebuild LoggingTypeRepairMigrator; move 409 already_pro detection to FunctionException catch block; fix IST gaps in sync; fix receipt rendering in train screen.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 519075188e79551754596d854514f0c49b4ca1be
Subject: fix: APK Test #12.2 — full-scope hotfix from cloud-side audit (1.0.0+9)
Files changed: lib/core/services/logging_type_repair_migrator.dart (+262 lines), lib/core/services/razorpay_service.dart (+99 lines), lib/core/services/sync_service.dart, lib/features/auth/providers/auth_provider.dart, lib/features/train/screens/train_screen.dart, lib/features/train/widgets/workout_receipt_card.dart
