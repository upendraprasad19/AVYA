---
bug_id: 239999
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: restoreFromCloud did not pull streak freezes, notifications inbox, saved diet plan, rank promotions, or coaching notes, so reinstalling lost all these surfaces.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: restoreFromCloudForUser, line: 1 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: AuthProvider, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: [_restoreFreezes, _restoreNotificationsInbox, _restoreSavedDietPlan, _restoreRankPromotions, _restoreCoachMemory]
cloud_table: user_progress
cloud_columns: [streak_freezes_available, streak_freezes_used_dates]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Add 5 _restoreX() methods to restoreFromCloudForUser; fold SubscriptionService.verifyFromServer(force:true) as the final restore step.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 2399992f509de7aa59f586bb7ccda1c8accf1b27
Subject: feat(sync): restore completeness — 5 surfaces + subscription fold-in (Test #11 A pull)
Files changed: lib/core/services/sync_service.dart (+192 lines), lib/features/auth/providers/auth_provider.dart, test/sync/restore_completeness_test.dart
