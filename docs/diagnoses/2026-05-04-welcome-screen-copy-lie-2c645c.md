---
bug_id: 2c645c
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Welcome screen displayed misleading 'no streaks' copy and app.dart showed a 'restart' error message that does not resolve any real issue.
concept: cross_cutting
sot_registry_entry: cross_cutting
writers:
  - { file: lib/features/onboarding/screens/welcome_screen.dart, method_or_widget: WelcomeScreen, line: 1 }
readers:
  - { file: lib/app.dart, method_or_widget: App, line: 1 }
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
proposed_fix: Remove 'no streaks' lie from welcome copy; replace 'restart the app' error in app.dart with actionable message.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 2c645c8b858a688b7119695ecc2723fd06de6179
Subject: fix(copy): replace welcome screen 'no streaks' lie + app.dart 'restart' copy (Test #11 E2+E3)
Files changed: lib/app.dart, lib/features/onboarding/screens/welcome_screen.dart
