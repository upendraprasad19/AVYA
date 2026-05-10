---
bug_id: 979a8e
date: 2026-05-06
batch: APK Test #12.1
status: shipped
symptom: PRO upgrade did not reflect immediately in train screen; train expanded view showed 0 sets; macros displayed incorrectly — three stacked bugs from the first on-device audit.
concept: subscription_state
sot_registry_entry: subscription_state
writers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: SubscriptionService.writeSubscriptionState, line: 1 }
readers:
  - { file: lib/features/home/widgets/today_workout_card.dart, method_or_widget: TodayWorkoutCard, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [plan, end_date]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [subscriptionInfoProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Fix subscriptionInfoProvider invalidation; fix train_screen set counting to read set_number from exlog; fix macros display.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 979a8e0ee543b66a9ac46ea344045de159c2b805
Subject: fix: APK Test #12.1 hotfix — PRO unlock + train view 0 sets + macros + 1.0.0+8
Files changed: lib/core/services/subscription_service.dart, lib/core/services/workout_write_service.dart, lib/features/home/widgets/today_workout_card.dart, lib/features/train/screens/train_screen.dart
