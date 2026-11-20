---
bug_id: f2d7b8
date: 2026-11-20
batch: android-play-billing-fallback (ADR-0022, U4a)
status: fixed
tier: s_fix
blast_radius: feature
symptom: |
  The referral share text linked to play.google.com/store/apps/details?id=com.icanbefitter.avya. The Gradle applicationId is com.icanbefitter.icanbefitter, so the link opens a page that does not exist.
concept: referral_share_play_link
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/profile/screens/invite_friends_sheet.dart, method_or_widget: "share text builder", line: 154 }
readers:
  - { file: android/app/build.gradle.kts, method_or_widget: "applicationId", line: 35 }
hive_key_prefix: none
hive_key_formula: "not applicable: display text / a URL string, nothing is stored"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/referral_share_play_id_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "not applicable: static text."
forbidden_patterns_checked:
  - { pattern: "a Play package id typed by hand instead of read from build.gradle.kts", absent: true }
proposed_fix: |
  The link carries `com.icanbefitter.icanbefitter`.
regression_test_planned: |
  test/contracts/referral_share_play_id_test.dart
mutation_proof: |
  Rule 21, backup/mutate/run/restore. M1 the id set back to com.icanbefitter.avya (grep -c confirmed it applied): 1 test RED. Restored. The test reads the applicationId from the Gradle file, so a future rename also fails it.
impact_analysis: |
  Display text / a link only. No stored value changes meaning.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "Link fixed; the test compares the sheet with android/app/build.gradle.kts." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No stored value changes." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: verified, evidence: "Play listing id read from android/app/build.gradle.kts applicationId; no store call made." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No contract touched." }
recurrence: "Not a recurrence: grepped docs/diagnoses for the sentence and for the wrong package id; no earlier diagnose names either."
related_bugs: []
---

# f2d7b8 - referral-share-link-wrong-play-id

## What happened
The id was typed from the app's old working name. The dev flavour adds a `.dev` suffix, which is not shared, so the production id is the one in the link. The test derives the expected id from the Gradle file instead of repeating a literal.
