---
bug_id: 69276a
date: 2026-05-06
batch: APK Test #12.3
status: shipped
symptom: subscriptionInfoProvider was not invalidated on cold-start subscription state writes (verify, downgrade), so PRO status changes did not propagate to the UI until next hot restart.
concept: subscription_state
sot_registry_entry: subscription_state
writers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: SubscriptionService.writeSubscriptionState, line: 1 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: AuthProvider, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [plan, end_date]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [subscriptionInfoProvider, trialInfoProvider, messageLimitProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: New SubscriptionService.onStateChanged static hook; fired from writeSubscriptionState() and _downgradeLocally(); wired from app.dart initState to invalidate all subscription providers.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 69276a6594e962d7b24af80bfea16d6a3871f7e7
Subject: fix: APK Test #12.3 — cold-start subscriptionInfoProvider invalidation (1.0.0+10)
Files changed: lib/core/services/subscription_service.dart, lib/app.dart, test/subscription/state_changed_hook_test.dart
