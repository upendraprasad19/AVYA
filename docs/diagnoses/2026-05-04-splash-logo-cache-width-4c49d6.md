---
bug_id: 4c49d6
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Logo rendered at full resolution on splash without cacheWidth hint, causing unnecessarily large decode on low-memory devices.
concept: cross_cutting
sot_registry_entry: cross_cutting
writers:
  - { file: lib/features/onboarding/screens/mission_brief_screen.dart, method_or_widget: MissionBriefScreen, line: 1 }
readers:
  - { file: lib/features/auth/screens/splash_screen.dart, method_or_widget: SplashScreen, line: 1 }
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
proposed_fix: Add cacheWidth/cacheHeight hints to logo Image widgets so Flutter decodes at display resolution rather than full asset resolution.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 4c49d6709dcfe931127c96d0e1c95d1b32d4a165
Subject: perf(splash): cacheWidth on logo render — asset untouched (Test #11 H2)
Files changed: lib/features/onboarding/screens/mission_brief_screen.dart
