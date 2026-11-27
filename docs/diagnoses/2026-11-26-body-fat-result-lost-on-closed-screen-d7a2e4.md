---
bug_id: d7a2e4
date: 2026-11-26
batch: oi348-walk-rest (found by plan review round 1 of the c4b8d2 closed-screen fix)
status: fixed
tier: m_fix
blast_radius: platform
symptom: |
  Edit Profile, AI body-fat assessment: leaving the screen while the AI call is running drops the result. The assess-body-composition function marks the month's one assessment as used (user_preferences.coaching_notes.last_bf_assessed_at, index.ts:221-225) and does not store the result, so the app's `if (!mounted) return;` after the call threw away the only copy, and the next attempt is refused for 30 days. A second, smaller path: leaving while the photo was being read made the screen's dead `ref` throw before the call; the catch only tried to show a message, so nothing was recorded. Found by reading the code (plan review round 1, finding on the `ref.read` after `file.readAsBytes()`; the dropped result was found while checking it). No user report.
concept: body_fat_assessment_persist
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_runBfAssessment, through the new saveBodyFatAssessment (UserProfileNotifier.updateProfileIf)", line: 1886 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_save: the body_fat_percent / body_fat_assessed_at entries of the update map", line: 2145 }
readers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "initState body-fat seed and _followStoredBodyFat", line: 366 }
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "recalculateTargets (body fat into the targets)", line: 255 }
hive_key_prefix: profile
hive_key_formula: "unchanged: userBox['profile'] body_fat_percent / body_fat_assessed_at / body_fat_range, written through ProfileWriteService.patchProfileWith (updateProfileIf)"
sync_methods: [syncProfileNow]
restore_methods: []
cloud_table: user_profile
cloud_columns: [body_fat_percent, body_fat_assessed_at]
contract_test_path: test/profile/edit_profile_save_closed_screen_test.dart
ist_handling: []
provider_invalidations: "none new: updateProfile updates userProfileProvider"
telemetry_op_types:
  success: []
  failure: [body_fat_assessment, body_fat_assessment_owner_changed, body_fat_assessment_superseded]
cross_account_guard: "saveBodyFatAssessment checks, under the profile write lock, that HiveUserSession.currentOwnerFullId still equals the owner read before the call; otherwise it records body_fat_assessment_owner_changed and writes nothing."
forbidden_patterns_checked:
  - { pattern: "a return between the assess-body-composition result and its save in _runBfAssessment", absent: true }
proposed_fix: |
  Capture the app-wide ProviderContainer and the signed-in user id after the photo is picked. Return (spending nothing) if the screen closed while the photo was read. After the result, update the field only when mounted, then always call saveBodyFatAssessment, which refuses another account. The success message stays behind mounted. The catch now records a non-fatal instead of only showing a message.
regression_test_planned: |
  test/profile/edit_profile_save_closed_screen_test.dart: saveBodyFatAssessment stores the result in real Hive with the screen closed; mirror: with another account id nothing is written and the event is logged. Since plan review round 2 the real AI Assess button is driven end to end (the photo picker answered on its channel, the function served from a loopback server): screen closed during the call, another account signed in during the call, a refusal; plus the stored result surviving SAVE (reopened form, and during the diet-strategy question) and the typed-value mirrors.
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

## Plan review round 2 (2026-11-26): storing the result was not enough

1. **A reopened form wrote the old value back.** Leave during the call, open Edit Profile again (it
   shows the old value), the result lands and is stored, then SAVE wrote the form's old percent and
   date over it. The same happened on one screen when the result landed while SAVE was waiting on
   the diet-strategy question (its update map was already built). Fix: SAVE writes either body-fat
   key only when the form's value differs from what the form took from the profile
   (`_seededBfText` / `_seededBfAssessedAt`), and an untouched field follows a later stored value
   (`_followStoredBodyFat`).
2. **Two one-line mutants of the first fix stayed green** (`mounted && await save...`, and
   `ownerNow: ownerAtStart`): the tests called the helper, and a source pin only banned the word
   `return`. The pin is replaced by tests that tap the real AI Assess button, answer the photo
   picker on its channel and serve the function from a loopback server.
3. The owner is now `HiveUserSession.currentOwnerFullId` (whose local profile the write lands in),
   read before the call and at the save; the form is not filled with a result for another owner.
4. The refusal messages that never showed are a separate, older bug: b9e4c3.

Mutation results for round 2 (mutate/run/restore, restore verified by bytes). RED counts in the
closed-screen file: SAVE writing an untouched body fat 1; the form never following a stored result
1; the follow overwriting a typed value 1; SAVE never writing body fat 2; the result dropped when
the screen closed 1; the owner compared with itself 1; the form filled for another owner 1.
During the same run one unrelated test of this file ("the screen closed right after SAVE") also
went red once. It passed in four unchanged runs afterwards; it waited a fixed time for the Save's
disk writes, so it now waits until the new targets are stored (bounded) before judging.

## Code review (B-pass, 2026-11-27): three more ways the first fix was wrong

1. **A newer value was overwritten.** Leave during the call, open Edit Profile again, type a body
   fat and SAVE, and the late AI result replaced it with no message. Before this batch the late
   result was dropped, so this was introduced here. Now the result is written only while the
   stored percent is still what it was when the assessment started; otherwise
   `body_fat_assessment_superseded` is logged and the newer value stays. The month's assessment is
   spent either way. This is a behaviour choice the founder can reverse.
2. **The account was checked before the write queued.** The write waits for the profile lock, so
   the check moved inside it (`patchProfileWith(stillOwner:)`).
3. **A re-send could lose the result.** The function records the month's use before it answers;
   `callFunction` re-sends after a gateway 502/503/504, and the second send is refused. The call
   is now `spendsQuotaPerCall: true` (one send).

Tests: `test/profile/body_fat_assessment_save_test.dart` (the lock held across the save), the
"value saved while the call ran" screen test, and "a gateway error is not sent a second time".
Mutation results (mutate/run/restore, restore verified by hash), 1 RED each: the newer-value
guard removed; the owner check replaced with `true`; the one-send flag removed.
