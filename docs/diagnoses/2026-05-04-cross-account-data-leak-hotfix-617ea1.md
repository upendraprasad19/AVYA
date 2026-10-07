---
bug_id: 617ea1
date: 2026-05-04
batch: APK Test #10.1
status: shipped
symptom: User-scoped data (isPro flag, prediction text, localActivationAt) persisted in shared configBox and leaked to the next account signed in on the same device.
concept: user_scoped_hive_keys
sot_registry_entry: user_scoped_hive_keys
writers:
  - { file: lib/core/services/user_config_migrator.dart, method_or_widget: UserConfigMigrator, line: 1 }
readers:
  - { file: lib/core/services/migrated_key.dart, method_or_widget: MigratedKey, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "MigratedKey.read/write routes user-scoped keys through per-user userBox; intentionallyShared list exempts pending_referral_code and logout_in_progress"
forbidden_patterns_checked: []
proposed_fix: New MigratedKey helper; new UserConfigMigrator one-shot migration; 6 critical configBox keys moved to userBox; razorpay_service localActivationAt write routed.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 617ea15d433305110dc8b847d7f31cc2175e2280
Subject: fix: cross-account data leak hotfix (Test #10.1)
Files changed: lib/core/services/user_config_migrator.dart (new), lib/core/services/migrated_key.dart (new), lib/core/services/sync_service.dart, lib/core/services/usage_counter_service.dart
