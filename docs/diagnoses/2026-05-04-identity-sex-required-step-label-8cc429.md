---
bug_id: 8cc429
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Identity screen allowed proceeding without sex selection and showed wrong step label (missing 01·05 display).
concept: onboarding_completed_at
sot_registry_entry: onboarding_completed_at
writers:
  - { file: lib/features/onboarding/screens/identity_screen.dart, method_or_widget: IdentityScreen, line: 1 }
readers:
  - { file: lib/features/onboarding/screens/identity_screen.dart, method_or_widget: IdentityScreen, line: 1 }
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
proposed_fix: Make sex field required with validation; fix step label to show 01·05 format.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 8cc42954f41ca2c8945fe349a4b9e5bdbe898fdd
Subject: fix(onboarding): Identity sex required + step-label 01·05 (Test #11 E4+E5)
Files changed: lib/features/onboarding/screens/identity_screen.dart, test/onboarding/identity_sex_required_test.dart
