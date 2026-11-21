---
bug_id: f631f0
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Profile screen called Supabase and Edge Functions directly from widget code, bypassing the repository pattern and making the calls untestable and hard to audit.
concept: cross_cutting
sot_registry_entry: cross_cutting
writers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: EditProfileScreen, line: 1 }
readers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: EditProfileScreen, line: 1 }
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
proposed_fix: Extract direct Supabase calls (submissions, soft-delete, assess-body-composition) from profile screens into SubmissionsRepository.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: f631f018b112b01c77f74c620794fbb82ed6a31b
Subject: refactor(profile): extract direct Supabase + Edge Function calls to repositories (Test #11 K)
Files changed: lib/features/profile/screens/edit_profile_screen.dart (+50 changes across profile screens)
