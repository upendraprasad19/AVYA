# OI-191: target weight and calorie targets must agree with the goal, on every door that changes the goal (founder, 2026-11-17 / 2026-11-18)

Branch `oi191-goal-target`, revision 4 (review rounds 1 to 3 applied, section 8). Tier M (§4.12.6: more than two product files,
profile and coach write doors). Execution mode (§4.12.7): inline, one worktree; subagents are used only for the two
plan-review rounds (at most 2 at a time, Sonnet, context-blind). No migration, no Edge Function change, no new stored
profile key, no schema change. §4.6 is not triggered (not payment, sync, auth, an AI prompt or the plan generator), so
no kill switch; rollback is a revert of the PR.

Out of scope, stated with the reason (not deferred work): OI-518 (the Weekly Report's Maintain wording; founder
decision 2026-11-18). The legacy chat onboarding (`onboarding_chat_screen.dart`, route `/onboarding/chat`, "retained for
rollback only", `lib/features/onboarding/CLAUDE.md`) can still store a contradictory pair through
`onboarding_provider.dart:238-243`; it is not reachable from the default flow, and the projection gate (U5) hides any
false projection a pair from it would produce. Edge Function readers of a legacy stored `0.0` target
(`weekly-report/index.ts:216,519`, `future-prediction/index.ts:32`): this batch stops NEW 0.0 writes; changing those two
functions is an Edge Function deploy, which needs its own per-action go (§4.3), and only pre-launch testing accounts hold
a 0.0 (CLAUDE.md §1).

## 1. Founder decisions (2026-11-18, this session)

1. Edit Profile never refuses to edit; at SAVE a contradictory goal / target pair is refused with the ONBOARDING popup
   (reused, nothing new). An empty or non-positive target counts as missing.
2. When the goal changes in Edit Profile and the current target breaks the new goal's rule, the target field is
   prefilled with the onboarding seed (Build +3 kg, Cut -5 kg, Maintain = current). A valid target is never touched.
3. The coach `switchGoal` shows the target and calorie change in its diff preview; APPLY writes goal, target and targets
   together. Copy goes through the Wardroom soul before it ships.
4. ONE shared helper for both doors (seed, recomputed targets, prediction refresh, provider invalidation); ONE
   direction rule the validator and every projection reader share.
5. The coach door's calorie recompute is IN this batch.

## 2. Writers and readers (named before the change)

| Concept | Writer | Reader |
|---|---|---|
| `primary_goal` + `target_weight_kg` pair | onboarding `stats_screen.dart:489` (validated); Edit Profile `_save` `edit_profile_screen.dart:1940-1941` (NOT validated; an empty field is stored as 0.0, `:1897-1899`); coach `_executeSwitchGoal` `tool_dispatcher.dart:1414-1419` (goal only). Also, unchanged by this batch: `LegacyGoalHealer` (goal + targets, no target weight), `completeOnboarding` `onboarding_provider.dart:542`, `plan_screen.dart:571`, the legacy chat path (out of scope above) | projection readers: `nutrition_screen.dart:502-518` `_projectionLine`; `profile/screens/profile/nutrition_targets.dart:15-31`; `subscription_section.dart:253-264` `_nutritionTargetsOnTap` (the ONLY way into `pace_detail_sheet.dart`, sole caller `:265`); `reports_screen.dart:~886-960` callout; `journey_timeline.dart:43-170` (trajectory / ETA / "Goal: Reach"). Display only: `home_screen.dart:990` chart line, `profile_content.dart:20` (passes values to the tap), `profile_completeness_provider.dart:10,74`. Prompt / snapshot: `prediction_service.dart:140`, `ai_snapshot_builder.dart:146,210` |
| derived targets (`daily_calories`, `protein_grams`, `carb_grams` + `carbs_grams`, `fat_grams`) | Edit Profile `_save` -> `recalculateTargets` `profile_provider.dart:238` -> `recomputeDerivedTargets` `profile_target_recompute.dart:88`; `LegacyGoalHealer` `legacy_goal_healer.dart:36-52` (goal and targets in ONE write); coach `_executeSwitchGoal` writes NO targets | `_resolveBaseTargets` `nutrition_provider.dart:112-125` (the STORED value wins; it recomputes only when missing); `NutritionSummaryNotifier.build` `home_provider.dart:~603`; `ai_snapshot_builder.dart:146-227`; `weekly-report/index.ts:371-385` (stored value) |
| prediction stale flag | Edit Profile `_save` `:2226-2257` only, and only when the target moved > 0.1 kg | `ai_coach_provider.dart:1507`, `PredictionService.refreshEnabled` |

Bug-history check (§4.1.5, index rebuilt 2026-11-18, 746 entries): not a recurrence. Precedent reused: `21da5f` (the
legacy-goal heal writes the new goal and its recomputed targets in one `patchProfileWith`). Adjacent, different class:
`f19a7c`, `a4f7e1` (goal-token drift).

## 3. Units

**U1. The rules (`lib/features/onboarding/target_weight_check.dart`, pure; header gains the new rules).**
- `validateTargetWeight`: unchanged except `missing` is also returned for `target <= 0` or `current <= 0` (a stored
  0.0 passed Cut because "0 is below current"; `target_weight_check.dart:44-62`). The check sits next to the `_finite`
  check (`:50`), AFTER the unvalidated-goal early return (`:45-49`), because `target_weight_check_test.dart:81-86`
  requires `ok` for recomp / strength / unknown goals even with a null target. Onboarding behaviour for valid input is
  unchanged; the existing test file is extended, not loosened. `StatsScreen._onCalibrate` (`:470`) also treats a
  weight `<= 0` like a missing weight (its existing 'Check weight and height' snackbar), so a typed `0` current weight
  is not answered with the target message.
- NEW `bool goalTargetAgree({goal, current, target})`: `validateTargetWeight(...) == ok`. A goal with no rule (legacy,
  unknown) agrees. The direction-only gate (used by the reports callout and the journey card).
- NEW `bool canProjectGoalDate({goal, current, target})`: goal is `lose_fat` or `build_muscle`, both weights present,
  finite and > 0, gap > 0.1 kg, AND `goalTargetAgree`. The ONE gate the three duplicated date-projection copies become.
- `targetWeightMessage(check, current, {bool editing = false})`: `editing` swaps only the tail words ("to continue" /
  "and continue" become "to save" / "and save"); onboarding strings are byte-identical (the popup test asserts them).
- The popup moves out of `StatsScreen._showTargetWeightDialog` into a shared top-level
  `Future<void> showTargetWeightDialog(BuildContext, String message)` in
  `lib/features/onboarding/widgets/target_weight_dialog.dart`: same keys (`target_weight_dialog`,
  `target_weight_dialog_close`), `barrierDismissible: true`, awaitable, and it does NOT touch focus; `StatsScreen` keeps
  `await showTargetWeightDialog(...); if (mounted) _targetFocus.requestFocus();`.

**U2. The goal-change patch (`lib/features/profile/services/goal_change_patch.dart`, pure).**
`GoalChange goalChange(Map profile, {required String newGoal, required DateTime now, required bool bodyFatCalcDisabled})`
returns `{patch, seededTarget?, targetFrom, targetTo, caloriesFrom?, caloriesTo?, proteinFrom?, proteinTo?}`:
1. `needsSeed = current weight finite and > 0 AND (stored target is null or <= 0 or validateTargetWeight(newGoal, current,
   stored) != ok)`.
2. `seed = round-to-tenths(seedTargetWeight(goal: newGoal, currentKg: current, storedTarget: null, seededForGoal: null))`;
   it is used ONLY if `validateTargetWeight(newGoal, current, seed) == ok` (the 40..250 clamp can break the rule at the
   edges: current <= 40 for Cut, >= 250 for Build); otherwise no target is written (goal-only) and the Edit Profile save
   check will tell the user.
3. `healed = {...profile, primary_goal: newGoal, target_weight_kg: seed if used}`; `overlay =
   recomputeDerivedTargets(healed, now: now, bodyFatCalcDisabled: ...)` (the FULL `BmrCalculator.toMap` result, dual
   `carb_grams` / `carbs_grams` keys kept). A null overlay (no height, DOB or gender): the patch is goal + seed ONLY, it
   carries NO calorie keys, and the preview omits the "Daily targets" line.
4. `patch = {...overlay, primary_goal, target_weight_kg only when seeded}`. `bodyFatCalcDisabled` is
   `configBox.get('disable_bodyfat_calc') == true`, as `recalculateTargets` reads it; `goalChange` deliberately does NOT
   honour `disable_profile_target_recompute` (Edit Profile's `recalculateTargets` does not either; both doors agree).
   A call whose `newGoal` equals the stored goal still runs the seed and the overlay (idempotent for a consistent
   profile, and it repairs a contradictory one).
`PredictionService.refreshAfterProfileChange({required bool isPro})` takes over the block now inline at
`edit_profile_screen.dart:2226-2257` (PRO regenerates automatic once per IST day and marks stale when the outcome is not
`success`; free marks stale). It has no `ref`, so the CALLERS invalidate `predictionProvider` (free: at once; PRO: after
the async outcome, guarded by `mounted` in Edit Profile; the coach, having no `mounted`, invalidates through its `ref` in
`.whenComplete`). `test/contracts/prediction_refresh_outcome_wiring_test.dart:57-65` pins the old inline regex and is
repointed to `prediction_service.dart`, never loosened.
`invalidateProfileDerivedSurfaces(void Function(ProviderOrFamily) invalidate)` is the ONE provider-set function:
`userProfileProvider`, `userStatsProvider`, `nutritionSummaryProvider`, `dailyNutritionProvider`, `macroTargetsProvider`,
`profileCompletenessProvider` (a seeded target changes the completeness count). Edit Profile calls it (keeping its
extra name providers), the dispatcher calls it.

**U3. Edit Profile (`edit_profile_screen.dart`).**
- Stored-kg rule: `_initialWeightText`, `_initialTargetText`, `_storedWeightKg`, `_storedTargetKg` are captured in
  `initState` AFTER any prefill, and every later prefill (the dropdown `onChanged`) updates all of them together: the
  controller text is set, `_initialTargetText` becomes that text and `_storedTargetKg` becomes the EXACT seed kg
  (tenths-rounded), so an untouched prefilled field saves exactly the seed (a whole-lbs display of 70.0 kg reads as 154
  and would otherwise re-read as 69.85). In `_save`, the 30-300 / 66-661 range checks run on the raw TEXT first (an
  unchanged out-of-range stored weight stays refused as today); then a field whose text still equals its initial text
  uses the stored kg instead of re-converting lbs, so an untouched imperial Save neither refuses a valid pair (75.0 /
  78.0 kg Maintain shows 165 / 172 lbs and re-reads as 3.18 kg apart) nor overwrites `current_weight_kg` with the
  rounded value (an existing drift). A null stored kg with empty text stays null (never 0.0). Edited fields convert as
  today. There is no unit toggle in this screen (`_isMetric` is set once in `initState`).
- Prefill: the goal dropdown `onChanged` (`:547`) and `initState` run `targetPrefill({goal, currentKg, targetText/Kg})`
  (pure, in `goal_change_patch.dart`). Its inputs are the form's CURRENT target value (the text the user sees, not the
  stored map: a user who typed a valid target and then changes the goal must not be overwritten) and the SAME resolved
  weight kg `_save` will use (the stored kg while the weight text is untouched, else the converted text), so the seed
  and the validation agree. When the weight resolves and `needsSeed`, the target controller gets the seed (kg, or whole
  lbs as the form shows). A valid target is untouched. Round trip: `_originalStoredTargetKg` is kept; on a reseed, if
  the field text still equals `_initialTargetText` (a prior prefill, not a user edit) and the original stored target is
  valid for the NEW goal, the original is restored instead of the seed (Cut 71 -> Build -> Cut returns 71, so a valid
  target is never lost; decision 2). The `initState` scope is stated as ANY
  `needsSeed` stored pair, not only a goal change inside the form: a legacy 0.0, a legacy-healed goal
  (`LegacyGoalHealer` heals the goal and the targets at restore but not the target weight), or a pair an older coach
  switch left contradictory all open showing the seed (visible in the field, never silent in what is saved), and each
  case is tested.
- `_save`: an empty field is `null` (not 0.0) and goes to the validator; a non-empty unparseable string keeps today's
  range snackbar, whose text becomes 'between 30 and 300 kg' / '66 and 661 lbs' and whose lower bound now matches the
  weight field (a Cut target of 5 kg is refused as out of range). After the weight and target are in kg and BEFORE
  `setState(() => _isSaving = true)` (`:1910`), run `validateTargetWeight`; a failure shows
  `showTargetWeightDialog(context, targetWeightMessage(check, weight, editing: true))` and returns; nothing is written.
  Focus does not return to the target field afterwards (the field has no FocusNode): accepted.
- Prediction: the `targetWeightChanged`-only condition becomes `goalChanged || targetWeightChanged` and calls
  `refreshAfterProfileChange`. `goalChanged` compares the form's healed `_goal` with the HEALED seed goal
  (`goalFormSeed(...).goal`), not with the raw stored `_originalGoal`, so a legacy `strength` profile does not spend a
  PRO regenerate on every untouched Save. `_originalTargetWeight` stays the stored value (`:382`), so a seeded target
  counts as changed.

**U4. Coach door (`tool_dispatcher.dart`).**
- `_executeSwitchGoal(intent, ref)` (the only caller is `execute` `:173`, where `ref` is in scope). The owner is
  captured as the FIRST statement (`final owner = HiveUserSession.currentOwnerFullId; bool owned() => owner != null &&
  HiveUserSession.currentOwnerFullId == owner;`, the healer's shape `legacy_goal_healer.dart:61`, the injury tool's
  `:727`), but nothing returns before the existing guards, so their message order stays (the legacy-goal refusal, 'Open
  the diff preview first', 'Profile not found.' all precede the sweep: `goal_list_selectable_test.dart:145-165`,
  `oi189 :942`). There is NO pre-sweep owner check: nothing awaits between the capture and the sweep (`:1411`), so such a
  check could never fire. What the capture protects is every point from the capture to the lock: `stillOwner` runs at the lock, so it also
  catches a flip DURING the sweep's own awaits (what stays pre-existing is the sweep itself acting on the new owner's
  box), through `patchProfileWith(stillOwner: owned)`. A source-order pin keeps the capture index below the
  `sweepNonCompletedRowsPastPlanEnd` index (the seam test alone would pass with the capture moved after the sweep). Residue, stated: an owner flip DURING the sweep's own awaits is pre-existing
  (the same exposure as the swap loop) and is not changed here; a pending coach intent cannot survive an account switch
  to be applied under another account (`pending_tool_intents_provider.dart:22` rebuilds on `authUserIdTokenProvider`).
- The profile write becomes `patchProfileWith((current) { oldGoal = current['primary_goal']; ...; return patch; },
  stillOwner: owned)` with `patch = {...goalChange(current, ...).patch, 'goal_changed_at', 'goal_changed_via':
  'ai_coach', 'previous_goal': oldGoal}`. `oldGoal`, `previous_goal`, whether the goal changed and whether the target
  changed are captured from `current` (the lock-time profile, as the healer captures `from` / `applied`); the result's
  `old_goal` (`:1506`, `:1527`) uses them. When `build` never ran (owner changed), those closure variables are unread.
  A `false` return returns a failure, clears the plan cache for `intent.id` and writes no schedule. The new
  `ToolDispatcher.debugBeforeSwitchGoalProfileWrite` seam (after the sweep, before the write, like
  `debugAfterInjurySwapLoop` `:699`) lets the test flip the owner there; the test asserts nothing is written to either
  account, the result is a failure, and the first account's rows WERE swept (the sweep already ran).
- `goalChange` emits the overlay and the seed only when the goal CHANGES (a legacy stored `strength` / `recompose` to a
  selectable goal counts as a change) or a target is seeded: a switch to the same goal on a consistent profile writes the
  audit stamps as today and does not rewrite the stored targets (a stale stored value is not moved silently).
  Consequence, stated: a coach "switch to the goal I already have" does NOT repair a profile whose goal and calories
  disagree (an older coach switch left Build's goal beside Maintain's calories); only an Edit Profile Save
  (`recalculateTargets`) does, and nothing regresses because the coach wrote no targets at all before. Pre-launch
  (CLAUDE.md §1) this is accepted and recorded in the diagnose-doc. The preview lines appear only when a value differs.
- Right after the write succeeded (every later outcome, including "Goal updated but plan regenerate failed"):
  `invalidateProfileDerivedSurfaces(ref.invalidate)` and `PredictionService.refreshAfterProfileChange` when the goal or
  the target changed; `pushSnapshot` stays where it is. The success-only tail call (`tool_dispatcher.dart:264-270`)
  stays harmless. This mirrors the injury tool (`:213-218`). The new calls must not land between the two strings
  `tool_dispatcher_telemetry_gaps_test.dart:162-193` pins ('Profile already changed but plan regen totally failed' and
  "'Goal updated but plan regenerate failed:" with `ErrorTelemetry.logEvent` and `'tool_dispatch_switch_goal_failed'`
  between them).
- `PredictionService.refreshAfterProfileChange` returns its Future (callers invalidate `predictionProvider` after the
  outcome; the coach in `.whenComplete` inside a try/catch, its `ref` can be disposed by then) and captures
  `HiveUserSession.currentOwnerFullId` before the call, skipping `markStale` when the owner changed (today
  `markStale` would stamp the NEW account's box after an account switch; pre-existing in Edit Profile, fixed in the
  shared place).
- `SwitchGoalDiff` mounts a small public widget `GoalTargetsPreview(GoalChange)` below the goal banner: a "Target weight"
  line (only when the seed moves it) and a "Daily targets" line (calories and protein, only when the overlay exists and
  differs), worded as an estimate ("about"), because the apply recomputes under the lock from the lock-time profile
  (weight logs can move `current_weight_kg` between preview and APPLY); the result data carries the APPLIED numbers. The
  `goalChange` call sits after the `_refused` return (so the legacy-refusal widget test, which has no Hive, still works)
  and is wrapped so a failure never breaks the plan preview. Copy reviewed with the Wardroom soul before it ships.

**U5. Readers.** `nutrition_screen._projectionLine`, `nutrition_targets` and `_nutritionTargetsOnTap` are all the same
profile-based gate and replace their inline copy with `canProjectGoalDate` (same null and `> 0.1` rules for a valid
pair; stricter only for non-finite input). The pace sheet is reachable only through that tap. The two trend-based readers
use the direction-only `goalTargetAgree` with THEIR OWN current weight (the last weigh-in), and gate ONLY the sentence
that promises a date. Their decisions are extracted into two pure functions in `target_weight_check.dart` so the
branch ORDER is testable: `projectionCalloutKind({goal, firstW, lastW, weeksDiff, target}) -> adjust | reached | eta |
none` (the callout's existing branch order, with the gate inside the `eta` arm only) and `journeyEtaAllowed({goal,
lastValue, target})`; both readers call them. The behaviour described next is the extracted functions' behaviour: `reports_screen._buildProjectionCallout` keeps its first two branches (the "Adjust your ..." line
and "You've reached your goal weight!") exactly as today and gates only the final ETA return with
`goalTargetAgree(goal: goal, current: lastW, target: targetWeight)` (`goal` is already a local, `:904`), returning
`SizedBox()` when it fails; `journey_timeline.dart` gates only `etaText` (`:57-64`) with `goalTargetAgree(goal: goal,
current: last.value, target: targetWeight)` (`goal` is a parameter, `:11`). Not gated: the "Lost / Gained X kg" line
(weigh-ins only), "Goal: Reach Xkg" and "Log your weight daily" (display). So Maintain users keep today's behaviour
except when the last weigh-in is more than 3 kg outside the Maintain window (the ETA is then hidden; OI-518 owns the
Maintain wording; the journey card never shows an ETA for `general_fitness` today), and a Cut user at or below the target
still sees "reached". The Home weight chart
still draws the stored target as a line: a number the user set, not a projection, and Edit Profile can no longer store a
contradictory one.

## 4. Value-semantics sweep (§4.1.5 point 3)

New 0.0 writes stop (an empty field is refused). Legacy 0.0 rows remain in Hive and the cloud and the readers keep
tolerating them: `reports_screen.dart:739` (`> 0`), `journey_timeline.dart:43,147`, `profile_completeness_provider.dart:74`,
`morning-alert/message.ts:61` (truthy: depends on 0 meaning unset, harmlessly); harmed by a legacy 0.0 and unchanged here
(reason in the out-of-scope paragraph): `weekly-report`, `future-prediction`. Tests naming the key (sweep before the first
edit, repoint never loosen): `onboarding_hive_session_open_before_write_test`, `diet_strategy_targets_writer_to_reader_test`
(`:314`), `onboarding_required_fields_test` (`:47`), `ai_snapshot_builder_only_test`, `snapshot_contract_consolidated_test`,
`stats_target_weight_popup_test`, `local_onboarding_evidence_behavioral_test`, `resume_route_resolver_test`,
`auth_restore_test`, `sync_service_test`, `snapshot_compaction_test`. Source-grep pins on code this batch moves:
`oi189_plan_end_bound_behavioral_test.dart:935-945` (`switchBody.indexOf('patchProfile(')` is -1 once the call is
`patchProfileWith(`: repoint to `patchProfileWith(`, keep sweep-before-write, add a source-order pin: owner capture before the sweep),
`prediction_refresh_outcome_wiring_test.dart:57-65`, `edit_profile_sync_test.dart:17-32`,
`coach_extraction_locked_fields_writer_to_reader_test.dart:~171`, `profile_write_service_only_test.dart` (assertions
re-read at build), `ai_proxy_goal_enum_parity_test.dart:131` (a 1600-char window from `_executeSwitchGoal(` must still contain
`FitnessGoals.isSelectable(`, so the owner capture stays small), `goal_list_selectable_test.dart:103-110,145-165`,
`tool_dispatcher_telemetry_gaps_test.dart:162-193`, `test/services/prediction_refresh_outcome_test.dart` (re-read at
build), and the docs `docs/architecture/functionality-flow.md` line 77 (ONB-06, the popup) which gains an Edit Profile
row. No test names `JourneyTimeline`, `nutrition_targets`, `_nutritionTargetsOnTap`, `_projectionLine` or
`_buildProjectionCallout`, so U5 has no pin to repoint and `projection_gate_single_source_test.dart` is its only
coverage. `grep -rn "patchProfile(" test/` and `grep -rn "_showTargetWeightDialog" lib test docs` run before
the first edit.

## 5. Tests (each fails without its fix; each mutated once, §4.4 rule 21)

- `test/onboarding/target_weight_check_test.dart` (extended): `canProjectGoalDate`, `goalTargetAgree`, the `<= 0`
  missing cases for the three validated goals (a Cut with 0.0 is `missing`; an unvalidated goal with a null target stays
  `ok`), the `editing` copy variant, onboarding strings unchanged; `stats_target_weight_popup_test.dart` stays green
  untouched (keys, `barrierDismissible`, focus return, the three strings).
- `test/contracts/goal_change_patch_test.dart` (new, pure; fixtures carry height, DOB, gender, lifestyle, weight, so the
  overlay exists): valid target kept; Cut -> Build, Build -> Cut, Maintain seeds equal 78.3 as an exact one-decimal
  double; clamp-edge fixture (current 40 for Cut, 250 for Build) writes no target; incomplete profile (no DOB) has NO
  `daily_calories` key; a same-goal call on a consistent profile emits no overlay; overlay equals
  `recomputeDerivedTargets` of the healed profile built from the SAME inputs (the oracle is the shared function's inputs,
  not a re-derivation); seed-before-overlay is observable only on a CUT profile with a stored target (Cut's protein base
  reads the target, `bmr_calculator.dart:222-225`), so that fixture exists; `targetPrefill` table (metric and imperial,
  the exact seed kg).
- `test/contracts/goal_target_weight_two_doors_behavioral_test.dart` (new). Coach door, real Hive (harness of
  `oi189_plan_end_bound_behavioral_test.dart`; owner `openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')`): Cut 75 kg
  target 71 (with height, DOB, gender, lifestyle) -> Build writes target 78.0 and the Build overlay; a valid target
  survives; a same-goal call writes no overlay; the owner flipped inside `debugBeforeSwitchGoalProfileWrite` writes
  nothing to either account and returns a failure, with the first account's rows swept (the oi189 pattern
  `coach_injury_profile_write_behavioral_test.dart:172-187`); invalidation happens on the all-schedule-failed outcome;
  the prediction refresh takes the free path (`SubscriptionService.isPro()` false; no network), and `markStale` is
  skipped after an owner change. Edit Profile door (widget; the first pump of this screen in `test/`): harness copied
  from `test/widgets/diet_plan_screen_no_modal_test.dart` (the first test renders every font family with no
  path_provider mock; Hive opens lazily in the second test on a temp dir through `test/helpers/hive_test_setup.dart`;
  Hive I/O inside `tester.runAsync`), plus: `userProfileProvider` seeded with a full profile,
  `DietStrategyFlags.debugEnabledOverride = false` (else `initState` reads `macroTargetsProvider` and `build` watches
  `subscriptionInfoProvider`), `SupabaseService.clientOverrideForTest` (`_save` reads `client.auth` at `:2024`), a
  `GoRouter` ancestor (a successful Save ends in `context.go('/profile')`), the fire-and-forget `SyncService` calls
  tolerated signed-out, a tall `tester.view.physicalSize` (the goal and target fields sit far down the ListView; Save is
  in the app bar). Cases: goal -> Build prefills 78.0; typed 70 + Save shows `target_weight_dialog` and writes nothing;
  an empty target shows the missing message; an untouched PREFILLED field saves exactly the seed kg (metric and
  imperial); imperial untouched Save of a Maintain 75 / 78 pair shows no popup and leaves `current_weight_kg` /
  `target_weight_kg` byte-equal; a legacy 0.0 opens as the seed; an unchanged out-of-range stored weight is still
  refused; a legacy `strength` profile whose stored target is already valid for Build: an untouched Save does NOT call the
  prediction refresh, and the same profile with a target that breaks Build (the field opens on the seed) DOES; Cut 71 ->
  Build -> Cut restores 71 (not a reseed); a typed valid target survives a goal change. The pure functions the
  screen calls (`targetPrefill`, the `_save` check) are tested directly as well; if a pump stub proves unworkable at
  build, the failing stub is named in the diagnose-doc and the pure tests stay, never silently dropped.
- `test/contracts/projection_gate_single_source_test.dart` (new): the three date-projection files contain no inline
  `(currentKg - targetKg).abs()` gate and call `canProjectGoalDate`, and the callout and journey call
  `projectionCalloutKind` / `journeyEtaAllowed` (presence only); behavioural, through the extracted functions (the
  4-way outcome, so branch order is observable): Cut at 78 / target 78 -> `reached`; Cut lastW 77 / target 78 -> `none`;
  Build lastW 77 / target 75 -> `none`; Cut moving the wrong way -> `adjust`; a Maintain user with lastW within 3 kg of
  the target -> `eta` (and `none` beyond 3 kg, the stated exception); `journeyEtaAllowed` false for a contradictory
  pair; the "Lost / Gained" text is not routed through it.
- `test/ai_coach/goal_targets_preview_test.dart` (new): `GoalTargetsPreview` shows the two lines for a breaking target,
  neither for a valid one nor for an incomplete profile (no `daily_calories`); a source-pin test that `SwitchGoalDiff`
  mounts it after the `_refused` return. No planner fake is needed (`RegeneratePlanPlanner.instance` is a private-
  constructor singleton).
- Mutations, named before running: U2 skip the seed; U2 seed after the overlay (Cut fixture); U2 drop the re-validate of
  the seed; U2 emit the overlay on a same-goal call; U3 drop the round-trip restore; U3 delete the `_save` check; U3 drop the `onChanged` prefill; U3
  capture the initial text BEFORE the prefill; U3 re-convert unchanged imperial fields; U4 delete the overlay; U4 swap
  `patchProfileWith` back to `patchProfile` (caught by the owner-flip test only); U4 drop the every-outcome
  invalidation; U5 revert one profile reader to its inline gate; U5 move the callout gate above the reached branch (red through `projectionCalloutKind`); U4 move the owner capture after the sweep (red through the source-order pin).
  Each mutation confirmed APPLIED with `grep -c`, red count recorded in the diagnose-doc.

## 6. Registry, docs, process

SoT registry (before editing: `grep -n "daily_calories\|target_weight_kg" docs/sot_registry.yaml`, and run the SoT gates, to see
which existing concepts list `tool_dispatcher.dart` or `recomputeDerivedTargets` and need the new keys): new concept `goal_target_weight_agreement` (writers: the three doors; readers: the projection sites above;
`behavioral_test_path:` the two-doors test; `fields_read` includes the cloud mirror `sync_profile.dart:211-212`,
`stat_snapshot_service.dart`, `ai_snapshot_builder.dart`). Nested CLAUDE.md: `lib/features/profile/CLAUDE.md` (Edit
Profile contract, imperial rule), `lib/features/ai_coach/CLAUDE.md` (`switchGoal` writes goal, target and targets, owner
check, every-outcome invalidation), `lib/features/onboarding/CLAUDE.md` (the shared dialog and the gates). Diagnose-doc
`docs/diagnoses/2026-11-18-goal-target-weight-agreement-<id>.md` (full template: second-door class; `related_bugs:`
`21da5f`) with `touched_layers_checked` (tiers 1, 2, 12 fixed or verified; 3-11 not applicable, stated). OI-191's text is
corrected (it said calories follow the goal on Save: true for Edit Profile only) and the entry is archived with
`closes-oi: OI-191`. Gate loop before each review round with a draft diff: `flutter analyze --no-fatal-infos` (whole
project) and the pre-commit gates; the full suite from CI via `land_pr.sh --ci-only` (§4.12.8). B-pass `/code-review`
before the merge; the merge and the device check wait for the founder.

## 7. Risks

Round 3 found no design issue; the remaining risk is execution: the first pump of `EditProfileScreen` (stubs named in section 5).

## 8. Review dispositions (every finding applied)

Round 1 (2 reviewers, 10 P1 and 14 P2). A-P1-1 oi189 pin -> section 4. A-P1-2 owner capture -> U4. A-P1-3 lock-time
`oldGoal` -> U4. A-P1-4 every-outcome invalidation, `profileCompletenessProvider`, prediction invalidation by callers ->
U2, U4. A-P1-5 / B-P1-1 stored 0.0 and non-positive targets -> U1, U2. A-P1-6 incomplete profile -> U2, U4. A-P2-7 seed
clamp edges and rounding -> U2. A-P2-8 preview is an estimate -> U4. A-P2-9 keep the full overlay -> U2. A test
observability notes -> section 5. A missed readers / writers -> section 2. B-P1-2 imperial rounding -> U3. B-P1-3
callout and Maintain -> U5. B-P2-a empty vs unparseable -> U3. B-P2-b seed -> U2. B-P2-c legacy prefill -> U3. B-P2-d
popup copy -> U1. B-P2-e prediction pin -> section 4. B-P2-f first pump -> section 5. B-P2-g dialog move -> U1. B-P2-h
sweep list -> section 4. B-P2-i journey card, chat onboarding, sync `_hasNumber` -> U5, the out-of-scope paragraph.

Round 2 (2 reviewers, 3 new P1 introduced by revision 2, 17 P2). 2A-P1-1 the pre-sweep owner check is dead code (no
await between the capture and the sweep, `tool_dispatcher.dart:1365-1412`; verified) -> U4 drops it, keeps the capture
and `stillOwner`, the seam test asserts the first account's rows were swept, the mutation is removed; the residue is
stated (an owner flip during the sweep's own awaits is pre-existing; pending intents rebuild on an account switch).
2A-P2-1 message order and capture-first -> U4. 2A-P2-2 pins (`ai_proxy_goal_enum_parity`, `goal_list_selectable`,
`tool_dispatcher_telemetry_gaps`, `prediction_refresh_outcome`) -> section 4. 2A-P2-3 helper returns its Future, skips
`markStale` after an owner change, free path in tests -> U4, section 5. 2A-P2-4 immutable map: `goalChange` copies ->
U2. 2A-P2-5 same-goal call -> U4. 2A-P2-6 preview widget instead of faking the singleton planner -> U4, section 5.
2A-P2-7 registry: grep `daily_calories|target_weight_kg` in `docs/sot_registry.yaml` and run the SoT gates at build
-> section 6. 2A-P2-8 preview-to-APPLY drift -> U4 residue. 2B-P1-1 initial text captured after the prefill, exact seed
kg -> U3. 2B-P1-2 callout gate placement and the callout's own `lastW` -> U5. 2B-P1-3 pump stub list named -> section
5. 2B-P2-1 U1 check position -> U1. 2B-P2-2 Stats weight 0 -> U1. 2B-P2-3 prefill scope stated -> U3. 2B-P2-4
`goalChanged` against the healed goal -> U3. 2B-P2-6 range text and lower bound -> U3. 2B-P2-7 focus accepted -> U3.
2B-P2-8 line numbers (`:1910`) -> U3. 2B-P2-9 `functionality-flow.md` ONB-06 -> section 4. 2B-P2-10 / 11 no pins for
U5, none for the validator beyond two files -> section 4.

Round 3 (1 reviewer, narrow: only revision 3's changed text; 1 P1, 6 P2; verdict: no new design finding). R3-P1-1 U5's
tests ran on pure gates and could not see branch order, so two mutants survived -> U5 extracts `projectionCalloutKind` /
`journeyEtaAllowed`, tests assert the 4-way outcome. R3-P2-1 `targetPrefill` inputs -> U3. R3-P2-2 Cut-Build-Cut round
trip -> U3 restore. R3-P2-3 Maintain wording beyond 3 kg -> U5. R3-P2-4 same-goal consequence -> U4. R3-P2-5 capture
wording and source-order pin -> U4, section 4. R3-P2-6 legacy strength fixtures (valid and breaking target) -> section 5.
