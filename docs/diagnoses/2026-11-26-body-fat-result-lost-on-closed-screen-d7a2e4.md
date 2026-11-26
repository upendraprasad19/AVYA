---
bug_id: d7a2e4
date: 2026-11-26
batch: oi348-walk-rest (found by plan review round 1 of the c4b8d2 closed-screen fix)
status: fixed
tier: m_fix
blast_radius: feature
symptom: |
  Edit Profile, AI body-fat assessment: leaving the screen while the AI call is running drops the result. The assess-body-composition function marks the month's one assessment as used (user_preferences.coaching_notes.last_bf_assessed_at, index.ts:221-225) and does not store the result, so the app's `if (!mounted) return;` after the call threw away the only copy, and the next attempt is refused for 30 days. A second, smaller path: leaving while the photo was being read made the screen's dead `ref` throw before the call; the catch only tried to show a message, so nothing was recorded. Found by reading the code (plan review round 1, finding on the `ref.read` after `file.readAsBytes()`; the dropped result was found while checking it). No user report.
concept: body_fat_assessment_persist
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_runBfAssessment, through the new saveBodyFatAssessment (UserProfileNotifier.updateProfile)", line: 1852 }
readers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "userProfileProvider (body_fat_percent, body_fat_assessed_at, body_fat_range)", line: 92 }
hive_key_prefix: profile
hive_key_formula: "unchanged: userBox['profile'] body_fat_percent / body_fat_assessed_at / body_fat_range, written by the same updateProfile call as before"
sync_methods: [syncProfileNow]
restore_methods: []
cloud_table: user_profile
cloud_columns: [body_fat_percent, body_fat_assessed_at]
contract_test_path: test/profile/edit_profile_save_closed_screen_test.dart
ist_handling: []
provider_invalidations: "none new: updateProfile updates userProfileProvider"
telemetry_op_types:
  success: []
  failure: [body_fat_assessment, body_fat_assessment_owner_changed]
cross_account_guard: "saveBodyFatAssessment writes only when the signed-in user id equals the one captured before the call; otherwise it records body_fat_assessment_owner_changed and writes nothing."
forbidden_patterns_checked:
  - { pattern: "a return between the assess-body-composition result and its save in _runBfAssessment", absent: true }
proposed_fix: |
  Capture the app-wide ProviderContainer and the signed-in user id after the photo is picked. Return (spending nothing) if the screen closed while the photo was read. After the result, update the field only when mounted, then always call saveBodyFatAssessment, which refuses another account. The success message stays behind mounted. The catch now records a non-fatal instead of only showing a message.
regression_test_planned: |
  test/profile/edit_profile_save_closed_screen_test.dart: saveBodyFatAssessment stores the result in real Hive with the screen closed; mirror: with another account id nothing is written and the event is logged; source pin: nothing returns between reading the result and the save. The image picker and the AI call are not driven end to end (no platform fake for them in this suite).
mutation_proof: |
  See the "Mutation results" section below.
impact_analysis: |
  One screen. The stored fields and their writer (updateProfile, which pushes the profile) are unchanged. With the screen open the flow is as before. With the screen closed the result is now kept instead of lost. The server's 30-day limit is unchanged.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "_runBfAssessment + saveBodyFatAssessment; closed-screen tests pass; flutter analyze 0 errors 0 warnings." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The closed-screen test reads body_fat_percent back from real Hive; the other-account mirror reads null." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No cloud row changed by this fix itself; the profile push is the existing one." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "Read supabase/functions/assess-body-composition/index.ts: it upserts only last_bf_assessed_at and returns the result. No change, no deploy." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "The photo is sent in the request; nothing is stored." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Request and response fields unchanged." }
recurrence: "Same class as c4b8d2 (a closed Edit Profile screen dropping work after an await), in a second flow of the same file."
related_bugs: [c4b8d2]
---

# d7a2e4 - A body-fat assessment was lost when the screen closed during it

## What happened
The AI call can take many seconds. The function counts it as this month's assessment before replying, and keeps no copy of the result. The app returned early when the screen had closed, so the result was gone for 30 days.

## Fix
The save runs through the app-wide container whether or not the screen is still open, only for the account that asked for it.

## Mutation results

Rule 21, mutate/run/restore from a saved byte copy (restore verified by bytes). Owner check weakened: 1 RED. A `return` put back before the save: 1 RED (the source pin). Fixed code: all 7 tests of the file pass.
