---
bug_id: b0fd76
date: 2026-05-08
batch: APK Test #12.9
status: shipped
symptom: Telemetry payload had no contract (any shape was accepted, breaking structured log queries); restore had a race condition where stale tmpl_* keys from earlier broken restores accumulated and caused duplicate templates across APK upgrades.
concept: error_telemetry_helper
sot_registry_entry: error_telemetry_helper
writers:
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: ErrorTelemetry, line: 1 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreWorkoutTemplates, line: 1 }
hive_key_prefix: "tmpl_"
hive_key_formula: "null"
sync_methods: [syncWorkoutData]
restore_methods: [_restoreWorkoutTemplates]
cloud_table: client_errors
cloud_columns: [op_type, detail, user_id, created_at]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [templates_stale_keys_swept]
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Add telemetry payload contract (required op_type field, typed detail shape); _restoreWorkoutTemplates sweeps stale tmpl_* keys not in the canonical set after restore; gated by canonicalKeys.isNotEmpty.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: b0fd76934bdbab74e5ac58156d9bbf83234493d5
Subject: feat: APK Test #12.9 — telemetry payload contract + restore race + templates sweep (1.0.0+16)
Files changed: lib/core/services/error_telemetry.dart (+33 lines), plus sync_service.dart template sweep logic
