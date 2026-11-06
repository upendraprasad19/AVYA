---
bug_id: f9acbc
date: 2026-05-03
batch: APK Test #11
status: shipped
symptom: MissionBriefScreen crashed or showed wrong state when navigated to in readOnly mode because the readOnly param was absent.
concept: onboarding_completed_at
sot_registry_entry: onboarding_completed_at
writers:
  - { file: lib/features/onboarding/screens/mission_brief_screen.dart, method_or_widget: MissionBriefScreen, line: 1 }
readers:
  - { file: lib/features/onboarding/screens/mission_brief_screen.dart, method_or_widget: MissionBriefScreen, line: 1 }
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
proposed_fix: Add readOnly param to MissionBriefScreen constructor; guard CTA display on readOnly flag.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: f9acbce147fb5ee4f4b95d716a9461c656151305
Subject: fix(onboarding): MissionBriefScreen readOnly param
Files changed: lib/features/onboarding/screens/mission_brief_screen.dart
