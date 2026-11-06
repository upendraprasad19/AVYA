---
bug_id: d9b546
date: 2026-05-06
batch: APK Test #12.5
status: shipped
symptom: PRO unlock still failed systemically across multiple code paths; logging_type repair migrator was not library-aware, repairing to wrong types for exercises present in the library.
concept: subscription_payment_grace_window
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: lib/core/services/logging_type_repair_migrator.dart, method_or_widget: LoggingTypeRepairMigrator, line: 1 }
readers:
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: RazorpayService, line: 1 }
hive_key_prefix: "exlog_"
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: workout_log_exercises
cloud_columns: [logging_type]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [subscriptionInfoProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Library-aware LoggingTypeRepairMigrator v3 that looks up exercise_library before deciding repair type; PRO unlock systemic fix across razorpay_service, subscription_service, train_provider.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: d9b5462bc04d7462facf6485e99258cd31b87f80
Subject: feat: APK Test #12.5 batch — PRO unlock systemic fix + library-aware logging_type (1.0.0+12)
Files changed: lib/core/services/logging_type_repair_migrator.dart (+102 lines), lib/core/services/razorpay_service.dart (+118 lines), lib/core/services/subscription_service.dart (+29 lines), lib/core/services/workout_write_service.dart (+100 lines), lib/features/train/providers/train_provider.dart (+18 lines)
