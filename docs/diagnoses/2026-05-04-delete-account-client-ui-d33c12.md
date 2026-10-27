---
bug_id: d33c12
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: No client-side account deletion UI existed for DPDP §17 compliance; users had no way to request hard erasure of their data.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: lib/features/profile/screens/delete_account_screen.dart, method_or_widget: DeleteAccountScreen, line: 1 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: AppRouter, line: 1 }
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
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: New 2-step delete_account_screen with blast-radius page and type-name+DELETE confirm; Hive clear + global signOut on success; route at /profile/delete-account.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: d33c123ff272fcbc43a034e0d9d075b2fa17abc1
Subject: feat(privacy): hard-delete account 2-step confirm UI (Test #11 H1 client)
Files changed: lib/features/profile/screens/delete_account_screen.dart (new 574 lines), lib/core/router/app_router.dart, lib/features/profile/screens/profile_screen.dart, lib/shared/repositories/user_repository.dart
