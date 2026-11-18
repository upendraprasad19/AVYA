---
bug_id: b5d2e8
date: 2026-11-18
batch: oi191-goal-target
status: fixed
blast_radius: account
tier: m_fix
symptom: |
  OI-191 (founder 2026-09-13, decisions 2026-11-18). The target weight and the goal could contradict each other, and the
  calorie / protein targets could fail to follow a goal change.
  - Edit Profile saved any target against any goal (a Build with a target below the current weight, a Cut with one above).
  - Changing the goal in Edit Profile left the old target on screen, so the very next Save wrote the contradiction.
  - The coach `switchGoal` wrote the goal only: the target weight and the calorie / protein targets stayed those of the old goal.
  - Five readers (Nutrition projection line, Profile nutrition targets, the pace sheet entry, the Weekly Report callout,
    the Journey ETA) trusted the raw pair and printed a date for a direction the diet cannot take.
concept: goal_target_weight_agreement
sot_registry_entry: goal_target_weight_agreement
contract_test_path: test/contracts/goal_target_weight_two_doors_behavioral_test.dart
related_bugs: [21da5f]
recurrence: |
  Writer/reader drift class, second-door shape: the onboarding door validated (`validateTargetWeight`, Stats), the two
  later doors did not. Precedent reused: 21da5f healed the goal and its targets in ONE write (`legacyGoalHealPatch`); this
  batch applies the same shape to a live goal change (`goalChange`). Bug-history lookup (CLAUDE.md 4.1.5): docs/diagnoses
  grepped for "target_weight", "primary_goal", "switchGoal", "projectGoalDate", "recomputeDerivedTargets"; f19a7c and
  a4f7e1 are goal-TOKEN drift (a different class), c3f2d8 / f1b6d4 are preview-vs-commit drift. Not a recurrence of those.
writers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_save: validate the pair before _isSaving, then updateProfile + recalculateTargets", line: 1936 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_prefillTargetForGoal / initState prefill (the onboarding seed when the goal breaks the target)", line: 436 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: "_executeSwitchGoal: ONE patchProfileWith (goal + seeded target + recomputed targets), owner re-checked under the lock", line: 1395 }
  - { file: lib/features/profile/services/goal_change_patch.dart, method_or_widget: "goalChange (the one decision of what a goal change writes)", line: 174 }
  - { file: lib/features/onboarding/target_weight_check.dart, method_or_widget: "validateTargetWeight / goalTargetAgree (the one direction rule)", line: 48 }
readers:
  - { file: lib/features/nutrition/screens/nutrition_screen.dart, method_or_widget: "_projectionLine: canProjectGoalDate", line: 501 }
  - { file: lib/features/profile/screens/profile/nutrition_targets.dart, method_or_widget: "the projection line: canProjectGoalDate", line: 18 }
  - { file: lib/features/profile/screens/profile/subscription_section.dart, method_or_widget: "_nutritionTargetsOnTap (the only way into the pace sheet): canProjectGoalDate", line: 253 }
  - { file: lib/features/profile/screens/reports_screen.dart, method_or_widget: "_buildProjectionCallout: projectionCalloutKind", line: 907 }
  - { file: lib/features/profile/screens/profile/journey_timeline.dart, method_or_widget: "the ETA line: journeyEtaAllowed", line: 66 }
hive_key_prefix: "userBox['profile'] keys primary_goal, target_weight_kg, daily_calories, protein_grams, carb_grams, carbs_grams, fat_grams"
hive_key_formula: "HiveService.instance.userBox.get('profile')[<key>] written through ProfileWriteService.patchProfileWith (coach) and UserProfileNotifier.updateProfile (Edit Profile)"
sync_methods:
  - "ProfileWriteService.patchProfileWith / updateProfileFields fire the existing profile sync; no new sync path"
restore_methods:
  - "unchanged: restore merges the cloud profile; a restored contradictory pair is repaired the next time either door runs (prefill or seed)"
cloud_table: user_profile
cloud_columns:
  - primary_goal
  - target_weight_kg
  - daily_calories
  - protein_grams
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key is written by this batch; the prediction refresh keeps its once-per-IST-day gate", line: 1 }
provider_invalidations:
  - "invalidateProfileDerivedSurfaces (lib/features/profile/providers/profile_surface_invalidation.dart): the one list both doors use, on EVERY outcome after the profile write (a failed plan regeneration included)"
  - "predictionProvider after PredictionService.refreshAfterProfileChange"
telemetry_op_types:
  success: []
  failure: ["profile_edit_save_failed (existing)", "switch_goal diff preview load failure (existing)"]
cross_account_guard: "coach door: HiveUserSession.currentOwnerFullId captured first, patchProfileWith(stillOwner:) re-checks it under the profile lock, a false return writes nothing and clears the cached plan; PredictionService.refreshAfterProfileChange keeps its owner guard"
forbidden_patterns_checked:
  - { pattern: "an inline (currentKg - targetKg).abs() gate in a projection reader", absent: true }
  - { pattern: "a stored 0.0 target treated as a valid Cut target", absent: true }
  - { pattern: "an imperial untouched Save refused or drifting the stored kg (75.0 / 78.0 read back as 74.84 / 78.02)", absent: true }
  - { pattern: "goal, target and targets written by separate patches at the coach door", absent: true }
proposed_fix: |
  Plan docs/plans/oi191-goal-target-weight.md (revision 4), record docs/plan-reviews/oi191-goal-target.md (3 rounds).
  - U1: one direction rule (`target_weight_check.dart`): missing / non-positive, goalTargetAgree, canProjectGoalDate,
    projectionCalloutKind, journeyEtaAllowed; one popup (`showTargetWeightDialog`) shared with Stats.
  - U2: `goalChange` (`goal_change_patch.dart`): seed only when the target cannot stand beside the new goal, then the whole
    recomputed overlay, in one patch.
  - U3: Edit Profile prefill + stored-kg rule + Save check (existing popup, "Save" wording).
  - U4: coach `switchGoal`: one owner-checked write, preview lines, invalidation + prediction refresh on every outcome.
  - U5: the five readers ask the shared rule.
regression_test_planned: |
  test/contracts/goal_target_weight_two_doors_behavioral_test.dart (coach door + Edit Profile oracle);
  test/profile/edit_profile_goal_target_test.dart (11 widget tests); test/contracts/goal_change_patch_test.dart (25);
  test/onboarding/target_weight_check_test.dart (53); test/contracts/projection_gate_single_source_test.dart;
  test/ai_coach/goal_targets_preview_test.dart; pins repointed in oi189_plan_end_bound_behavioral_test.dart and
  prediction_refresh_outcome_wiring_test.dart.
impact_analysis: |
  Account tier (profile writes, coach tool dispatch). The app is pre-launch with testers only (CLAUDE.md section 1), so a
  stored contradictory pair is repaired the next time a door runs; no migration, no schema, no Edge Function.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "target_weight_check, goal_change_patch, profile_surface_invalidation, prediction_service, tool_dispatcher, switch_goal_diff, goal_targets_preview, edit_profile_screen, five readers; flutter analyze whole project and the gate loop run before the push" }
  - { layer: hive_local_state, status: verified, evidence: "the widget and behavioral tests write userBox['profile'] and read the stored keys back (daily_calories moves, target_weight_kg 78.0 exact, imperial 75.0 / 78.0 unchanged)" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column, table or migration; the four cloud columns exist and are written by the existing profile sync" }
  - { layer: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function changed; legacy readers of a 0.0 target are stated under accepted residue" }
  - { layer: client_server_contract, status: verified, evidence: "the coach card is the same switch_goal intent; only the client write and preview changed" }
---

## Root cause

- **Writers:** `edit_profile_screen._save` wrote `target_weight_kg` and `primary_goal` with no cross-check, and its goal
  dropdown never touched the target field; `tool_dispatcher._executeSwitchGoal` patched `primary_goal` only.
- **Readers:** the five projection readers computed a date from the unsigned gap, so a contradictory pair read as a
  promise the diet could not keep; `recalculateTargets` ran on Edit Profile only, so the coach door left calories on the
  old goal.
- **Missing input:** the direction rule existed once, at onboarding (`validateTargetWeight`); nothing shared it.

## Fix

See `proposed_fix`. Execution mode: inline (section 4.12.7). Decisions of the founder (2026-11-18): Edit Profile never
blocks editing, refuses to SAVE a contradiction with the onboarding popup; an empty or non-positive target is missing;
a goal change prefills the onboarding seed only when the current target breaks the new goal; the coach previews and
applies target and calories together; ONE shared rule; the Weekly Report's Maintain wording is OI-518.

## Accepted consequences

- A same-goal coach switch on a consistent profile writes the goal only: it does not repair stale calories (nothing
  changed that would have made them stale).
- An owner flip DURING the plan-window sweep's own awaits is pre-existing and unchanged; the lock-time `stillOwner`
  check catches the profile write itself.
- The legacy chat onboarding and the legacy Edge Function readers of a stored `0.0` target are unchanged (the pair they
  would read is repaired the next time Edit Profile opens or the coach switches).
- After the popup, focus is not returned to the target field (the shared dialog touches no focus; Stats keeps its own
  focus handling).

## Wardroom copy review

`lib/shared/widgets/wardroom/CLAUDE.md` holds the palette and primitives and no copy-voice rules, so the preview words
(`lib/core/copy/goal_change_copy.dart`: "ALSO CHANGES", "Target weight 71.0 kg → 78.0 kg", "Build needs a target above your
current 75.0 kg.", "Daily calories about 2,000 → 2,600 kcal") use the app's own vocabulary (`FitnessGoals.label`, target
weight, calories, protein), are plain and factual, carry no exclamation or emoji, and say "about" because the apply
recomputes under the lock. Popup wording is the onboarding popup's, with "Save" in place of "Continue" (`editing: true`).
Self-attested.

## Mutations

Each mutant was applied to the committed file by `scratchpad/mut/run.py` (the script asserts its anchor occurs exactly
once and the file length changed, so every mutation APPLIED), the suite run, and the file restored from the in-memory copy;
a `grep -c` of each anchor confirmed the restore. Suite A = `goal_change_patch_test`, `target_weight_check_test`,
`goal_target_weight_two_doors_behavioral_test`, `projection_gate_single_source_test`, `goal_targets_preview_test`,
`oi189_plan_end_bound_behavioral_test`, `prediction_refresh_outcome_wiring_test` (137 tests after the stored-kg test was
added); suite B = `edit_profile_goal_target_test` (11 widget tests).

| ID | Mutation | Suite | Result |
|---|---|---|---|
| M1 | the recompute overlay deleted (`goalChange`) | A | red (7) |
| M2 | the seeded target not written | A | red (10) |
| M3 | the recompute reads the profile BEFORE the seed and goal are merged | A | red (3) |
| M4 | the overlay written on a same-goal consistent profile | A | red (2) |
| M5 | the round-trip restore (Cut 71 to Build to Cut) removed | A | red (1) |
| M6 | the stored-kg rule removed from `resolveFieldKg` | A | **survived** (all green); new pure tests "resolveFieldKg" in `goal_change_patch_test.dart`: red (1) |
| M6b | same mutant | B | red (1: the imperial untouched Save) |
| M7 | the Save check (`targetCheck != ok`) deleted | B | red (2) |
| M8 | the goal dropdown's prefill call dropped | B | red (3) |
| M9 | the initial target text captured before the prefill | B | red (1) |
| M10 | `goalChanged` judged against the raw stored goal (legacy strength) | B | red (1) |
| M11 | `stillOwner` always true (coach door) | A | red (2) |
| M12 | the every-outcome invalidation removed | A | red (1) |
| M13 | the owner captured after the sweep instead of first | A | red (3) |
| M14 | one reader's gate (`canProjectGoalDate` in Nutrition) removed | A | red (1) |
| M15 | the callout gate moved above the adjust / reached branches | A | red (1) |
| M16 | `journeyEtaAllowed` always true | A | red (1) |

Not mutated: "swap `patchProfileWith` to `patchProfile`": the owner-flip test (M11) is the protection and the
`oi189_plan_end_bound_behavioral_test` pin names `patchProfileWith(`. Harness findings worth keeping: a successful Save in
a `testWidgets` leaves work behind that waits on the dead fake zone, so `box.close()` of the next boot hangs forever (the
test closes the session in `addTearDown` while the zone is alive and drains real time between pumps); a test
`SupabaseClient` needs `autoRefreshToken: false` or its timer fails the next invariants check.

## B-pass round 1 (2 fresh Sonnet seats, HEAD df5bea73, CI green): every finding closed

Seat A (coach door, shared patch, prediction, preview) and seat B (Edit Profile, the rule, the readers). Thirteen
findings, none P0 / P1, six P2, seven P3. Each is either fixed with a test or stated as a consequence; none is deferred.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| A1 | P2 | the every-outcome invalidation had only a source-order pin (the success tail already invalidates `userProfileProvider`, so the success test passed with the call deleted) | fixed: `goal_target_weight_two_doors_behavioral_test.dart` "a failed plan regeneration still refreshes the profile readers" (a bad-date schedule, the tail never runs) and `profile_surface_invalidation_test.dart` (the list, once each, one failure never stops the rest) |
| A2 | P2 | the PRO prediction branches and the `goalChanged \|\| targetSeeded` gate had regex pins only | fixed: seam `PredictionService.debugPredict`; tests for PRO success, PRO failure, the once-per-IST-day skip, free, an account switch in flight, and the gate in both halves (goal change with a fitting target; seed with no goal change; same goal and consistent = not stale) |
| A3 | P3 | `markStale` / `clearStale` dropped the Future; the `predictionProvider` invalidate failure was a `debugPrint` only | fixed: both write through `unawaited(...catchError(recordNonFatal))`; the invalidate catch records `switch_goal_prediction_invalidate` |
| A4 | P3 | a corrupt stored value (non-numeric target, a calculator throw) would throw inside the lock-time build, after the sweep | fixed: `goalChange` reads the target with `is num` and falls back to goal + seed when the overlay throws; three tests in `goal_change_patch_test.dart` |
| A5 | P3 | the coach result did not carry the new writes | fixed: `target_weight_kg`, `daily_calories`, `protein_grams` in the result data when written (one `resultData` map for success and partial success) |
| A6 | P3 | the coach preview was always kilograms | fixed: `GoalChangeCopy` and `GoalTargetsPreview` take `metric` (the `units_metric` setting); test in `goal_targets_preview_test.dart` |
| A7 | P3 | the long line; `disable_profile_target_recompute` does not govern the new writer | fixed (line); stated: that switch governs only `LegacyGoalHealer` (`legacy_goal_healer.dart`), Edit Profile's `recalculateTargets` never read it, and the coach door follows Edit Profile, so both doors agree |
| B1 | P2 | the refusal popup printed kilograms to an imperial user | fixed: `targetWeightMessage(..., metric:)` (default kg, onboarding bytes unchanged); Edit Profile passes `_isMetric`; unit tests and a widget test |
| B2 | P2 | the daily weigh-in (`home_provider.dart:932`, `updateField('current_weight_kg')`) writes the pair unchecked, so a Cut user who reached the goal (weigh-in at or below the target) breaks the strict rule through no edit of theirs | stated consequence + test: opening Edit Profile shows the new seed (66.5 for 71.5 kg) in the field, visibly, and a Save with it succeeds; clearing it is refused like any contradiction. Founder rule (2026-11-18): the target must agree with the goal on every Save. A reached goal asking for a new target is the intended product behaviour; the weigh-in is not changed (it is not a goal or target door) |
| B3 | P3 | re-selecting the goal already chosen re-ran the prefill and overwrote a typed target | fixed: `onChanged` returns when the value is the current goal; widget test |
| B4 | P3 | the new lower range bound blocked a Save of an untouched stored target below 30 kg | fixed: the typing-range check runs only for an edited target; widget test (stored 28.0) |
| B5 | P2 | mirror cases with no test (imperial prefill and round trip, empty weight on goal change, weight edited after the goal change, legacy strength with a breaking target, a stored contradictory pair, Maintain 3.0 / 3.1) and two weak assertions | fixed: eleven widget tests added; the calorie assertion now compares to the recompute oracle |
| B6 | P3 | half-tenth rounding (`round()`) accepts a Cut 0.05 kg below and may refuse a Build 0.05 kg above | stated: the founder's rule is "compare in integer tenths"; the fields allow two decimals, a gap under a tenth is not a goal |

Mutations of this round (same harness; each applied, run, restored; every one red): N1 owner compare dropped (2), N2
outcome inverted (5), N3 invalidate replaced by a no-op (3), N4 one provider dropped from the list (3), N5a gate `&&`
(3), N5b gate goal-change only (2), N5c gate seed only (2), N6 message ignores the unit (3), N7 re-select guard removed
(1), N8 untouched-range guard removed (1), N9a overlay try removed (3), N9b cast restored (2), N10 preview ignores the
unit (2), N11 result data dropped (2), N12 open-time prefill removed (4), N13 pound text at one decimal (1). Two
guards the first round missed were found by these: the gate (`||`) had no behavioral test in either half (N5), and the
failure-path invalidation was unobservable on the success path (N3).
