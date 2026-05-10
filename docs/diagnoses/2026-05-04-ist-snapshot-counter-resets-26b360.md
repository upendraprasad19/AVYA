---
bug_id: 26b360
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: AI snapshot and usage counter resets used UTC or device-local dates instead of IST, causing midnight-crossing mismatches for Indian users.
concept: hive_field_name_nlog
sot_registry_entry: hive_field_name_nlog
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: pushSnapshot, line: 1 }
readers:
  - { file: lib/core/services/usage_counter_service.dart, method_or_widget: UsageCounterService, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: [pushSnapshot]
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: [date]
contract_test_path: "n/a — backfill"
ist_handling:
  - { file: lib/core/services/usage_counter_service.dart, method_or_widget: counterKey, line: 1 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Replace UTC/local date extraction with istDateStr() throughout snapshot builder, counter key generation, and counter reset logic.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 26b3607ac52dd43712fe7d76018500eee2872a78
Subject: fix(ist): align AI snapshot + counter resets to IST throughout (Test #11 B1+B2+M3)
Files changed: lib/core/services/sync_service.dart, lib/core/services/usage_counter_service.dart, lib/features/ai_coach/providers/ai_coach_provider.dart
