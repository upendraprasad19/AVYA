---
bug_id: 8a2e9b
date: 2026-05-05
batch: APK Test #11.1
status: shipped
symptom: 25 additional user-scoped configBox keys remained after the Test #10.1 hotfix (6 keys), and OneSignal player_id was never synced to cloud, causing push unsub to silently no-op on account deletion.
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
cloud_table: user_progress
cloud_columns: [onesignal_player_id]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "UserConfigMigrator v2 migrates 31 total keys; _intentionallyShared pins pending_referral_code + logout_in_progress"
forbidden_patterns_checked: []
proposed_fix: Sweep remaining 25 user-scoped keys to userBox via UserConfigMigrator v2; add OneSignal player_id sync in auth_provider._syncOneSignalPlayerId; fix istDateStr double-shift in ai_coach_repository.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 8a2e9b5e205d03e89a962435e118b845505b489b
Subject: fix: Test #11.1 — full sweep of cross-account leak class
Files changed: lib/core/services/prediction_service.dart, lib/core/services/sync_service.dart, lib/core/services/usage_counter_service.dart, lib/core/services/user_config_migrator.dart (+82 lines)
