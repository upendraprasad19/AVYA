---
bug_id: b621c6
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Four pre-existing test failures in rank_service_test and sync_gap_test reflected outdated test assumptions from pre-Test #6 architecture.
concept: sync_fanout_workout_domain
sot_registry_entry: sync_fanout_workout_domain
writers:
  - { file: test/services/rank_service_test.dart, method_or_widget: rank_service_test, line: 1 }
readers:
  - { file: test/sync/sync_gap_test.dart, method_or_widget: sync_gap_test, line: 1 }
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
proposed_fix: Update rank_service_test static gate mirrors and sync_gap_test DeleteNutritionLogNotifier to match Test #6 WriteService architecture.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: b621c6d9f9448734b1c2be2955b7d93d93af0638
Subject: test(stale): align sync_gap + rank_service tests to post-Test #6 architecture (Test #11 J1+J2)
Files changed: test/services/rank_service_test.dart, test/sync/sync_gap_test.dart
