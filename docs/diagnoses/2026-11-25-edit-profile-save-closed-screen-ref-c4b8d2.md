---
bug_id: c4b8d2
date: 2026-11-25
batch: oi348-walk-rest (A20 device walk, AAB +50)
status: fixed
tier: s_fix
blast_radius: feature
symptom: |
  Edit Profile Save, founder walk 2026-11-25 17:42 IST (the A20 injury save): `profile_edit_save_failed` with 'Bad state: Using "ref" when a widget is about to or has been unmounted is unsafe'. `_save` awaits the profile write, the target recompute and, after the "Reschedule Workouts?" dialog, the whole plan regeneration, and then called the screen's `ref` with no `mounted` check. When the screen is closed in the meantime (back gesture, a restore redirect; the phone's restore steps ran 8 to 41 s that minute) the Save throws half way. Which line threw was not logged. What a closed screen skipped depended on the line: the target recompute, the profile-derived provider refreshes, the final Train / Home plan refresh, and every step after it (the plan and snapshot push, the prediction refresh, the success message).
concept: edit_profile_save_provider_calls
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_save: updateProfile, recalculateTargets, the impact read, invalidateProfileDerivedSurfaces, the name providers, the plan providers (now through the app-wide ProviderContainer captured when the Save starts)", line: 2022 }
readers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "userProfileProvider notifier updateProfile (93) and recalculateTargets (255), and every provider the Save invalidates (macro targets, home greeting, current plan, today workout, calendar week, AI insight, prediction)", line: 93 }
hive_key_prefix: none
hive_key_formula: "not applicable: the Save's writes are unchanged; only the handle used for provider calls after an await changed"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/profile/edit_profile_save_closed_screen_test.dart
ist_handling: []
provider_invalidations: "unchanged set; every call after the first await now goes through the container (userProfileProvider notifier calls, invalidateProfileDerivedSurfaces, the three name providers, currentPlan / todayWorkout / calendarWeek / aiInsight, and predictionProvider after its refresh, which a closed screen used to skip)."
telemetry_op_types:
  success: []
  failure: [profile_edit_save_failed, profile_edit_reschedule_skipped_closed, edit_profile_prediction_invalidate]
cross_account_guard: "unchanged: the reschedule block keeps its `mounted` check (a closed screen does not regenerate a plan, so a sign-out between the dialog and the regeneration never writes another account's schedule). In _save the one `ref` call left (the reschedule block's profile read) sits directly behind a `mounted` check; the body-fat flow no longer uses `ref` after an await (d7a2e4)."
forbidden_patterns_checked:
  - { pattern: "a WidgetRef call after an await in Edit Profile `_save` with no mounted check", absent: true }
proposed_fix: |
  Capture `ProviderScope.containerOf(context, listen: false)` when the Save starts and use it (read / invalidate) for every provider call that follows an await. The `ref` call left (the reschedule block's profile read) stays behind an immediate `mounted` check with no await between. Context uses (dialogs, snackbar, navigation) were already guarded. Plan review round 1 added: the prediction card's invalidate also goes through the container (it was behind `mounted`, so a closed screen kept the old card), and a reschedule that could not be asked because the screen had closed is recorded (`profile_edit_reschedule_skipped_closed`). The plan keeps its old days in that case, and a later Save sees no change to ask about: what should happen then is a product call, not made here.
regression_test_planned: |
  test/profile/edit_profile_save_closed_screen_test.dart: the REAL EditProfileScreen against real Hive, SAVE tapped, the screen replaced through the router before the Save's first real await resumes, the app's ProviderScope kept. A pace edit: the targets are recomputed (daily_calories leaves 2000) and no unmounted-ref failure reaches either telemetry sink (`profile_edit_save_failed` or the per-provider non-fatal of the surface refresh). A 5-days edit with a stored plan: the same, and no dialog opens on a closed screen.
mutation_proof: |
  Rule 21, backup/mutate/run/restore (files compared by hash after). Fixed code: 3 of 3 pass. Pre-fix shape (every container. back to ref.): 2 RED. One line at a time back to ref: the recompute (MA1) RED, the impact read (MA2) RED, the profile-derived surfaces tear-off (MB1) RED only after the test also read the surface refresh's own non-fatal (the helper catches each failure, so the first version of the test stayed green: not proof), the name providers (MB2) RED, currentPlan (MC1) RED, aiInsight (MC2) RED. Two earlier versions of the test were discarded: one replaced the whole ProviderScope (the container died with it, an unrealistic scenario) and one let the screen finish its exit transition after the Save had resumed (4 of the 6 lines stayed green).
  Plan review round 1 (2026-11-26), 3 more, each 1 RED: the prediction invalidate put back behind `mounted`; the skipped-reschedule event renamed; the F5 call commented out (the F5 test now ignores comment lines).
impact_analysis: |
  Feature blast radius, one screen. No write path or stored value changes. A Save with the screen open behaves as before (the existing edit_profile tests pass). A Save whose screen closed now finishes the profile write, the target recompute, the provider refreshes (the prediction card included) and the profile and snapshot push. It still does NOT reschedule the plan: the question cannot be shown, and the skip is now recorded.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "_save uses the captured container after its first await; new test 3/3 green; the existing edit_profile_* tests (target impact, goal target, plan changed, coach-extraction lock) pass; flutter analyze and the pre-commit gates pass." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "The closed-screen test reads the profile map back from real Hive after the Save: the pace edit and the recomputed daily_calories are there." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "client_errors on 2026-11-25 12:12:55 UTC holds the event; user_profile.injuries for the account reads ['knee'] (the save did land)." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No contract touched." }
recurrence: "Not a recurrence of a diagnosed bug: grepped docs for the message; only docs/plans/train-coach-log-refresh.md mentions it (another screen). The class (a WidgetRef used after an await with no mounted check) is the same one the hold-week and keep-training callers solved with a container captured before the await (keep_training_phase1_action.dart:33)."
related_bugs: []
---

# c4b8d2 - Edit Profile Save threw when its screen was closed mid-save

## What happened
`_save` ran its provider calls through the screen's `ref` after awaits that can last more than ten seconds (the plan regeneration). A closed screen's `ref` throws, so the Save failed half way and reported `profile_edit_save_failed`.

## Fix
Use the app-wide `ProviderContainer`, captured when the Save starts, for every provider call after the first await. Dialogs, the snackbar and navigation keep their `mounted` guards.

## Plan review round 2 (2026-11-26)
The skip event covered only a screen closed BEFORE the question. A screen removed while the question is up (the dialog sits on the root navigator, the screen in a nested one) made a tap on Reschedule do nothing, with no record. It now logs the same `profile_edit_reschedule_skipped_closed`. Test: "the screen removed while the reschedule question is open" (a ShellRoute reproduces the two navigators); mutation (the teardown branch made unreachable): 1 RED.

## Follow-up caught by CI (2026-11-26)
The fix renamed `ref.invalidate(aiInsightProvider)` to `container.invalidate(aiInsightProvider)`. The source-grep contract `test/providers/ai_insight_invalidation_test.dart` (F5) still searched for the old spelling and went red in CI shard 4/4 (the only failure of the whole suite). I repointed it, not loosened it: it now requires `container.invalidate(aiInsightProvider)` AND forbids `ref.invalidate(aiInsightProvider)` in `edit_profile_screen.dart`. Mutation: put `ref.invalidate(...)` back in the screen: the test went red (1 failure); the file was restored (empty diff). I did not grep `test/` for the old literal before the rename (CLAUDE.md section 4.9, source-grep contracts row).
