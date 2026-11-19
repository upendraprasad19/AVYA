---
bug_id: a7d3e9
date: 2026-11-18
batch: goal-change-targets
status: fixed
blast_radius: account
tier: l_fix
symptom: |
  Founder observations (2026-11-17/18, APK + web), after OI-191 made the goal change move the targets:
  - A weigh-in on Home never moved the calorie / protein targets: the weight changed and the targets stayed those of the old weight.
  - Edit Profile saved a pace / lifestyle / weight change and recomputed the targets silently; only a workout change prompted anything.
  - The saved diet chart kept showing numbers built for old targets, with no sign that they were old.
  - A Cut with a far target weight got LESS protein than a Build of the same body (the base was the target weight alone).
  - The projected date within 2 kg of the target ignored the chosen pace (forced slow, four-week floor), disagreeing with the calorie target.
  - The first sign-in merge took the cloud weight beside the phone's calorie target and the later restore saw no input change.
concept: weigh_in_target_refresh
sot_registry_entry: weigh_in_target_refresh
contract_test_path: test/contracts/weigh_in_target_refresh_behavioral_test.dart
related_bugs: [b5d2e8, 3cbbce, c3f2d8]
recurrence: |
  Writer/reader drift class again (a derived value, the targets, with more than one writer of its inputs). Bug-history lookup
  (CLAUDE.md 4.1.5): docs/diagnoses/INDEX.md grepped for recompute, weigh, projection, protein, stale. b5d2e8 (OI-191) made the goal
  doors move the targets together with the goal and is the direct precedent (`goalChange`, `recomputeDerivedTargets`, one write);
  3cbbce (ProfileWriteService, A4) is the single-writer chokepoint reused here (`patchProfileWith`); c3f2d8 (body fat) is the reason a
  recompute must never default or backfill an input (the first-sign-in merge recomputes only on a non-empty local profile and only
  when an input changed). OI-150 (restore recompute) is the restore-side twin. Recurrence: yes, the weigh-in door and the first-sign-in
  merge were the two doors OI-191 did not reach.
writers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "WeightLogNotifier.logWeight: ONE patchProfileWith (raw weight + refresh), own try/catch, kill switch", line: 928 }
  - { file: lib/features/profile/services/weigh_in_target_refresh.dart, method_or_widget: "weighInTargetRefresh / recentWeighInKgs (7-day mean, 2 kg band, difference rounded to tenths)", line: 122 }
  - { file: lib/features/profile/services/profile_target_recompute.dart, method_or_widget: "recomputeDerivedTargets: the overlay carries targets_basis_weight_kg", line: 161 }
  - { file: lib/features/profile/services/profile_cloud_merge.dart, method_or_widget: "mergeCloudProfileWithTargets (first-sign-in merge, real local profile only, fail-open recompute)", line: 36 }
  - { file: lib/core/utils/bmr_calculator.dart, method_or_widget: "calculateTargets protein base; projectGoalDate real pace", line: 226 }
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: "_savePlan / _generateFreshPlan / _loadSavedPlan: the target stamp", line: 377 }
readers:
  - { file: lib/features/home/widgets/weight_log_sheet.dart, method_or_widget: "_save: snackbar with the exact numbers when WeightLogResult.targetsMoved", line: 100 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_save: targetImpactFor(open snapshot, after) -> dialog / reschedule dialog section", line: 2132 }
  - { file: lib/features/nutrition/screens/diet_plan_screen_swap.dart, method_or_widget: "_staleBanner: staleTargetsOf(stamp, targets on screen)", line: 359 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "hydrateFromCloud F2 branch calls mergeCloudProfileWithTargets", line: 888 }
hive_key_prefix: "userBox['profile'] keys current_weight_kg, targets_basis_weight_kg, daily_calories, protein_grams; configBox['saved_diet_plan'] keys diet_target_calories, diet_target_protein"
hive_key_formula: "HiveService.instance.userBox.get('profile')[<key>] via ProfileWriteService.patchProfileWith; MigratedKey.write('saved_diet_plan', planData) via UserRepository.saveDietPlan"
sync_methods:
  - "ProfileWriteService.patchProfileWith fires the existing profile push (targets_basis_weight_kg is not in the explicit push whitelist, so it stays local); the plan's two stamp keys travel in the whole plan_json (syncSavedDietPlan)"
restore_methods:
  - "unchanged: restore merges the cloud profile and recomputes on an input change (OI-150); the stamp keys come back with plan_json; an unstamped plan shows no banner"
cloud_table: user_profile
cloud_columns:
  - current_weight_kg
  - daily_calories
  - protein_grams
ist_handling:
  - { file: lib/features/profile/services/weigh_in_target_refresh.dart, method_or_widget: "the window is today-6..today on the IST date string passed in (istDateStr at the caller)", line: 66 }
provider_invalidations:
  - "invalidateProfileDerivedSurfaces(ref.invalidate, source: 'weigh_in') after a weigh-in that moved the targets; the banner follows macroTargetsProvider invalidation"
telemetry_op_types:
  success: []
  failure: ["weigh_in_target_refresh (own try/catch)", "bootstrapper_profile_merge_recompute (own try/catch)"]
cross_account_guard: "logWeight captures HiveUserSession.currentOwnerFullId before the first await and patchProfileWith(stillOwner:) re-checks it under the profile lock; a false return writes nothing (test: an owner change at debugBeforeProfileWrite)"
forbidden_patterns_checked:
  - { pattern: "a weigh-in written as updateField('current_weight_kg') followed by a second profile write", absent: true }
  - { pattern: "a recompute that defaults or backfills a missing input (body fat, height)", absent: true }
  - { pattern: "_savePlan stamping the targets read at save time", absent: true }
  - { pattern: "raw != on a floating point or timestamp input to decide a user-visible dialog", absent: true }
proposed_fix: |
  Plan docs/plans/goal-change-targets.md (revision 4), record docs/plan-reviews/goal-change-targets.md (3 rounds).
  - B1: Cut protein base = max(target, 0.9 x current weight); the projection uses the chosen pace at every distance (floor one week);
    the two fallback derivations pass the target weight.
  - B2: a weigh-in recomputes only when the 7-day mean drifts more than 2 kg (the difference rounded to tenths) from targets_basis_weight_kg; ONE patch;
    readers and the snapshot follow the recompute.
  - B2b: the first-sign-in merge recomputes on a non-empty local profile when an input changed, fail-open.
  - B3: Edit Profile reports a moved target with exact numbers (open-time snapshot, normalised input comparison; a rebase of the targets on a
    different weight counts as a real change).
  - B4: the saved diet chart carries the targets it was built for; a banner offers Regenerate, never regenerates by itself.
regression_test_planned: |
  test/contracts/cut_protein_base_test.dart, test/bmr_calculator_pace_test.dart, test/contracts/weigh_in_target_refresh_test.dart,
  test/contracts/weigh_in_target_refresh_behavioral_test.dart, test/contracts/bootstrapper_profile_merge_recompute_test.dart,
  test/contracts/progress_restore_freeze_merge_behavioral_test.dart (call site), test/contracts/derivation_inputs_changed_for_dialog_test.dart,
  test/profile/edit_profile_target_impact_test.dart, test/home/weight_sheet_target_snackbar_test.dart, test/nutrition/diet_plan_stale_targets_test.dart,
  test/nutrition/diet_plan_stale_banner_screen_test.dart; pin repointed in test/contracts/weight_log_invalidation_awaitable_test.dart.
impact_analysis: |
  Account tier (profile writes, the first-sign-in merge writer, the weigh-in door). The app is pre-launch with testers only (CLAUDE.md
  section 1): no existing-user migration; an existing profile moves at its next recompute (a Save, a drift weigh-in, a goal change).
  No migration, no schema, no Edge Function.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "bmr_calculator, home_provider, weight_log_sheet, weigh_in_target_refresh, profile_target_recompute, profile_cloud_merge, auth_session_bootstrapper, target_impact, edit_profile_screen, diet_plan_screen(+swap), diet_plan_stale_targets, nutrition_provider and nutrition_repository fallbacks" }
  - { layer: hive_local_state, status: verified, evidence: "behavioural tests write userBox['profile'] / healthBox and read the stored keys back (basis seeded, targets and basis moved in one write, raw weight kept on a throw); the saved plan stamp is read back from Hive in the banner screen test" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column, table or migration; targets_basis_weight_kg is local only and absent from the push whitelist" }
  - { layer: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function changed; supabase/functions grepped for protein derivation (none: weekly-report, future-prediction, switchGoal mention lose_fat only)" }
  - { layer: client_server_contract, status: verified, evidence: "the profile push body is unchanged; the plan_json gains two top-level keys that round-trip with the whole plan (sync_restore_completeness)" }
---

## Root cause

- **Writers:** `WeightLogNotifier.logWeight` wrote `current_weight_kg` only (`updateField`), so the weight moved and the
  targets did not; `AuthSessionBootstrapper.hydrateFromCloud` merged cloud inputs over local ones with no recompute (and the later
  restore saw no input change because the merge was already written); `BmrCalculator.calculateTargets` took the target weight alone
  as the Cut protein base.
- **Readers:** Edit Profile recomputed on every Save but said nothing; the Diet chart read its saved plan with no notion of the
  targets it was built for; `projectGoalDate` forced the slow pace within 2 kg.
- **Missing input:** nothing recorded the weight the stored targets were built from, so a recompute could not tell a real drift from noise.

## Fix

See `proposed_fix`. Execution mode: inline (section 4.12.7), tier L. Founder decisions (2026-11-18): weigh-ins use a 7-day mean and
recompute only past about 2 kg; Edit Profile shows the diet / calorie impact; the saved plan shows a banner and is never regenerated
silently; Cut protein base = higher of target weight and 90 % of current weight; the projection uses the real pace; left as is: the
deficit ignoring the gap, body fat, free vs PRO, legacy goals.

## Accepted consequences

- **Cross-device restore (B-pass seat A, accepted in plan section 3 B2):** device B's launch restore recomputes from the raw cloud weight
  (`sync_profile.dart:862-889`, OI-150's contract), so a second device can rebuild the targets from one reading and rewrite its basis. Changing
  the restore path would move the batch to platform tier (sync engine) and reopen OI-150's contract: that is the founder's call, and it is stated in the final report.

- A single reading is the whole mean when it is the week's only weigh-in (a weekly weigher gets no smoothing); a later reading pulls
  it back. Cross-device: device B's restore recomputes from the RAW weight and its basis becomes the raw weight.
- An UNSTAMPED saved plan (every plan saved before this change) shows no banner and stays unstamped when re-saved; a stamp appears
  only after Regenerate then Save.
- Regenerate on the banner discards unsaved hand swaps on screen (the AppBar refresh does the same today); the banner says so.
- The body-fat assessment door still persists body fat and recomputes nothing; the form's Save reports the effect (open-time snapshot).
- The `_regenerations++` mutant of the banner's Regenerate is EQUIVALENT in the tested scenario: the plan is rebuilt for the new
  targets, which differ from the saved plan's, so the seed shift is invisible there.

## Wardroom copy review

`TargetImpactCopy` ("Targets updated", "Daily calories 2,000 -> 1,775 kcal", "Protein 144 -> 130 g", "Your saved diet chart still
shows the old numbers.", "Regenerating replaces the plan on screen.") uses the app's own vocabulary, is plain and factual, carries no
emoji and no exclamation, and gives exact numbers (the targets are already saved, so no "about"). Self-attested.

## Mutations

Each mutant was applied with an anchor asserted to occur exactly once and a restore from the in-memory copy (`git status` after each
batch shows no stray file). "red (n)" is the failing-test count printed when the runner's last progress line came out: exact for the
pure and behavioural files, **at least n** for a widget file (a failing widget test with Hive hangs the runner on the close, so only
the first failure is counted).

| ID | Mutation | Result |
|---|---|---|
| B1-1 | Cut protein base = target (no 90 % floor) | red (4) |
| B1-2 | the provider fallback drops `targetWeightKg` | red (1) |
| B1-3 | projection without the one-week floor | red (1) |
| B2-1 | the refresh try/catch removed | red (1) |
| B2-2 | the failed-health-write guard dropped | red (1) |
| B2-3 | the kill switch ignored | red (1) |
| B2-4 | the basis key dropped from the overlay | red (4) |
| B2-5 | the band compared as raw doubles | red (2) |
| B2-6 | the raw weigh-in used instead of the mean | red (1) |
| B2-7 | a second `updateField` write after the patch | red (1) |
| B2b-1 | the merge recompute catch removed | red (1) |
| B2b-2 | null `existing` treated as empty | red (2) |
| B2b-3 | the input-changed guard dropped | red (1) |
| B2b-4 | the bootstrapper builds `merged` inline again | red (1) |
| B3-1 | `before` read at Save time instead of the open snapshot | red (1) |
| B3-2 | raw `!=` for DOB and height | red (1) |
| B3-3 | the info dialog never shown | red (1) |
| B3-4 | `impactShown` not set (second dialog after the reschedule dialog) | red (1) |
| B3-5 | `&&` for `||` in "moved" | red (2) |
| B4-1 | `_savePlan` stamps the targets read at save time | red (1) | 
| B4-2 | `_loadSavedPlan` drops the stamp | red (5) |
| B4-3 | `&&` for `||` in `staleTargetsOf` | red (3) |
| B4-4 | the fallback guard ignored | red (1) |
| B4-5 | Regenerate does not generate | red (1) |
| B4-6 | Regenerate does not count `_regenerations` | survives (equivalent, see accepted consequences) |
| BP-1 | no `pushSnapshot` after a recompute | red (1) |
| BP-2 | no `invalidateProfileDerivedSurfaces` after a recompute | red (1) |
| BP-3 | the body-fat switch hard-coded false at the weigh-in door | red (1) |
| BP-4 | the body-fat argument dropped inside `weighInTargetRefresh` | red (2) |
| BP-5 | the band rounds each side before the difference | survived the first run; cases 82.06 vs 80.04 and 82.04 vs 79.96 added, then red (1) |
| BP-6 | a NaN / zero / String basis not treated as absent | red (1) |
| BP-7 | stray keys count as a real local profile | red (1) |
| BP-8 | raw `!=` compare in the merge | red (1) |
| BP-9 | the body-fat argument dropped in the merge | red (1) |
| BP-10 | bootstrapper kill switch hard-coded false | red (1) |
| BP-11 | bootstrapper body-fat switch hard-coded false | red (1) |
| BP-12 | the dialog's "to" line prints the old number | red (at least 1) |
| BP-13 | an in-band rebase is not an impact | red (at least 1) |
| BP-14 | the snackbar's from / to swapped | red (at least 1) |
| BP-15 | the snackbar's ternary inverted | red (at least 2) |
