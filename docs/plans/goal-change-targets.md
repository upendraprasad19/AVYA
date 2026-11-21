# Goal-change targets, branch B: weigh-in rule, impact dialog, stale-plan banner, Cut protein, real-pace projection

Revision 4 (after plan-review rounds 1, 2 and 3; sections 9, 10 and 11 disposition every finding).
Branch `goal-change-targets` (worktree `.claude/worktrees/goal-change-targets`, based on main 52ab1fb9, after OI-191 #296 and the diet protein rules #297).
Blast radius `account` (`lib/core/**` is account, `docs/blast_radius.yaml:670`; `profile_write_service.dart` is account, `:428`; the profile, nutrition, home, test and
docs paths are feature; no platform-tier file is touched: `user_repository.dart` stays untouched). Process tier: L (§4.12.6), because B2b edits the first-sign-in
merge writer in `auth_session_bootstrapper.dart` (a restore-merge writer); L changes nothing about the pipeline this plan already follows (full x2 plan review, record,
B-pass). §4.6 posture: the bootstrapper's new recompute is reachable only behind the EXISTING kill switch `disable_profile_target_recompute` (plus
`disable_bodyfat_calc` as the `bodyFatCalcDisabled` argument); the old path (no recompute) is the switch-closed path; no NEW switch. No migration, no Edge Function.
Execution mode (§4.12.7): inline, one worktree, never switched mid-batch. Memory: `project_goal_change_targets_diet_batch_2026_11_18.md` holds the observations and the
founder's answers.

## 1. Founder decisions (2026-11-18, already made; not re-asked)

1. Weigh-ins use option C: a smoothed weight (7-day mean); the targets are recomputed ONLY when that mean drifts more than about 2 kg from the weight the stored
   targets were built from.
2. The Edit Profile dialog shows the diet / calorie impact; a pace or lifestyle change gets the prompt too.
3. A saved diet plan whose targets moved shows a BANNER ("targets changed, regenerate?"); it is never regenerated silently and a hand-made swap is never erased.
4. Cut protein base = the higher of the target weight and 90 % of the current weight, times the goal's g/kg.
5. The projected goal date uses the real pace, including within 2 kg of the goal.
6. Left as is: the deficit that ignores the gap to the goal; body fat; free vs PRO; legacy goals. Coach goal switch and target weight vs goal are OI-191 (merged).
7. Process: autonomous; commit, push and open the PR under the standing permission; merge ONLY on the founder's word.

## 2. What the code says today (every line cited was read in this worktree)

**Doors that write the derivation inputs** (`derivedTargetInputKeys`, `profile_target_recompute.dart:12-24`):

| Door | Writes | Recomputes the targets? |
|---|---|---|
| Edit Profile `_save` (`edit_profile_screen.dart:2054-2121`) | all inputs, one `updateProfile`, then `recalculateTargets()` on EVERY save | yes (`profile_provider.dart:239` -> `recomputeDerivedTargets`), from the raw weight in the field |
| Edit Profile body-fat assessment (`edit_profile_screen.dart:1907-1912`) | `body_fat_percent` (+ assessed-at, range) at once, "so it is not lost if the user closes without saving" | no; the form's next Save recomputes. Kept (section 3 B3): Save compares against the form-open snapshot, so its dialog shows the body-fat effect |
| Coach `switchGoal` (`tool_dispatcher.dart:1467`), legacy-goal healer | goal (+ seeded target) | yes (`goalChange`, `legacyGoalHealPatch`, OI-191) |
| Cloud restore (`sync_profile.dart:860-885`) | merged inputs | yes, when `derivedTargetInputsChanged`, honouring `disable_profile_target_recompute` + `disable_bodyfat_calc` |
| **Bootstrapper first-sign-in merge** (`auth_session_bootstrapper.dart:880-893`, the F2 branch: cloud non-null fields over the local profile, `updateProfile(merged, skipSync: true)`) | merged inputs | **NO** (and the later restore sees no input change, so the targets stay stale until the next Save) |
| Body-fat default healer (`body_fat_default_healer.dart:72`) | nulls a fabricated body fat | no, founder-locked ("no silent backfill"): deliberate, unchanged |
| Onboarding commit (`onboarding_provider.dart:522-541`) | first profile | computes once with `BmrCalculator` |
| **Home weigh-in** `WeightLogNotifier.logWeight` (`home_provider.dart:904-935`), reached by `WeightLogSheet._save` AND the coach chat `ConversationalLogHandler._logWeight` | `current_weight_kg` via `updateField` | **NO** |
| Health Connect weight import (`health_sync_service.dart:421-428`) | a `weight_<istToday>` health-box row only when none exists; never `current_weight_kg` | no, and it never reaches the weigh-in door: accepted. Its row DOES enter the next manual weigh-in's 7-day mean |

`pace_preference`, `lifestyle_activity` and `days_per_week` have no writer besides onboarding and Edit Profile (grep over `lib/`). So the founder's "recalculate on weight,
pace, lifestyle and days changes in the write door" is TWO missing doors (the weigh-in and the bootstrapper merge) plus the dialog and the saved plan.

**Saved plan**: `_savePlan` (`diet_plan_screen.dart:364-409`) has no target in scope and stamps only `id`, `created_at`, `food_type`, optional strategy and supplements
stamps, `meals`. A loaded saved plan can be re-saved from the AppBar. `_loadSavedPlan` (`:429-470`) keeps no target. `build()` already watches `macroTargetsProvider`
(`:547`); the saved plan is read once (`_checkedSaved`, `:187-204`). Calories and protein never change with the diet strategy (`effective_macro_targets.dart`
`:10-17`, `:47-76`), and `macroTargetsProvider` applies no per-day override, so the stamped target is the right number for Keto and Low carb too.

**Weight entries are read four ways today**: `WeightHistoryNotifier` (`home_provider.dart:685-695`: any key with `type == 'weight_log'` or a `weight_kg`, no
per-date dedupe, no range check), `WeightLogSheet.initState` (`weight_log_sheet.dart:55-66`), `HealthReadService.latestWeightKg` (`health_read_service.dart:36-56`:
prefix `weight_`, excludes `weight_log_`, w > 0), and `ai_snapshot_builder.dart:1027` / `stat_snapshot_service.dart:431` (`type == 'weight_log'` only). They disagree
already; this plan does not unify them (the chart must not change). The mean gets its own strict reader (B2).

**Protein** (`bmr_calculator.dart:221-231`): `proteinBaseKg = (goal == 'lose_fat' && target > 0 && target < weight) ? target : weight`, `x proteinPerKg`, clamped to
`[50, round(kcal * 0.4 / 4)]`. Callers of `calculateTargets` (`user_repository.dart:1146`, `nutrition_provider.dart:149`, `plan_screen.dart:709`,
`onboarding_provider.dart:486`, `profile_target_recompute.dart:140`, `nutrition_repository.dart:571`) all route through it; TWO of them (`nutrition_provider.dart:148-156`,
`nutrition_repository.dart:570-583`, the fallbacks that run when stored targets are missing) pass NO `targetWeightKg`.

**Projection** (`bmr_calculator.dart:300-340`): a gap of 2 kg or less is forced to the SLOW rate with a 4-week floor while the calories use the chosen pace. Readers:
`nutrition_screen.dart:516`, `profile/screens/profile/nutrition_targets.dart:19`, `pace_detail_sheet.dart:11` (the only three). Nothing under `docs/`, `lib/**/CLAUDE.md`
or `supabase/` quotes the rule; the pins are the doc comment at `bmr_calculator.dart:296` (and the protein comments at `:176-178` and `:221-222`), the code at `:310` and `test/bmr_calculator_pace_test.dart:111-118`
(historical planning files under `docs/superpowers/` are not live docs and stay).

## 3. Units

### B1 — calculator and its fallbacks

- Cut protein base: for `lose_fat` with `0 < target < weight`, `base = max(target, 0.9 * weight)`; otherwise unchanged. The 40 %-of-calories cap and the 50 g floor
  stay, so "Cut >= Build per current kg" holds in the UNCAPPED region (a low-calorie Cut can hit the cap before Build does: a 70 kg woman whose Cut is floored to 1200 kcal
  caps at 120 g against Build 126 g, as before). Examples: 75 kg, target 65 -> 67.5 -> 135 g (was 130); 100 kg, target 70 -> 90 -> 180 g raw (was 140; the cap may bind);
  target 72 at 75 kg -> 72 -> 144 g, unchanged.
- The two fallback derivations (`nutrition_provider.dart:148-156`, `nutrition_repository.dart:570-583`) pass `targetWeightKg` from the profile, so a profile with missing
  stored targets gets the same rule. The repository one returns calories only, so the change is observable only through the provider (`resolveNutritionTargetsForTest`);
  it is made for consistency and not claimed as a behavioural pin.
- Projection: delete the within-2-kg block. `weeks = max(1.0, gap / (currentKg * rate))`, `rate` = the chosen pace clamped to `_paceMaxRate`, for every gap; `gap == 0`
  stays 0 weeks. Calories and projection share the pace RATE; the calorie floor (1200 / 1500) and cap (5000) can still make the achieved deficit smaller than the projected
  one (recorded residual; the deficit is not touched, founder).

### B2 — weigh-in rule

Pure module `lib/features/profile/services/weigh_in_target_refresh.dart`:

- `recentWeighInKgs(boxEntries, todayIst)`: the strict reader of the mean. An entry counts when its key is `weight_<YYYY-MM-DD>` AND its value is a map with
  `type == 'weight_log'` (what `HealthWriteService.logWeight`, the cloud restore `sync_health.dart:479-486` and Health Connect all write) AND `weight_kg` a number in (0, 500];
  its IST date is in `[today - 6, today]` inclusive (future-dated rows excluded); one value per date (the key is the date). `smoothedWeightKg` = their mean. Zero
  qualifying entries -> the caller uses the raw weigh-in it just wrote.
- `weighInTargetRefresh(profile, rawKg, smoothedKg, now, bodyFatCalcDisabled)`: `basis = profile['targets_basis_weight_kg'] ?? profile['current_weight_kg']` (the value
  BEFORE this weigh-in; the builder runs on the pre-write profile). No basis -> nothing. The drift is compared in integer TENTHS of a kg
  (`(smoothed * 10).round() - (basis * 10).round()`, absolute, `> 20`), never as a raw double (`64.4 - 62.4` is `2.000000000000007`): exactly 2.0 kg does not recompute, 2.1
  does. Over the band -> `recomputeDerivedTargets({...profile, 'current_weight_kg': smoothed})`; its overlay (which carries the new basis) is the patch; a null overlay
  (incomplete profile) -> nothing. Inside the band with no stored basis -> seed ONLY `targets_basis_weight_kg = basis`. Inside the band with a stored basis -> nothing.
  Result: patch, `targetsMoved`, calories / protein from -> to.
- `recomputeDerivedTargets` adds ONE overlay key, `targets_basis_weight_kg` (the weight it computed from), so every door that applies the overlay keeps the basis in step
  with the targets in the SAME write. Local only (the push whitelist `sync_profile.dart:178-215` never sends it; the restore merge starts from the local map; sign-out
  clears the user box; `carb_grams` is the precedent). Not an input (not in `derivedTargetInputKeys`).
- `WeightLogNotifier.logWeight` becomes ONE `ProfileWriteService.patchProfileWith` after the health write: the builder returns `{'current_weight_kg': raw, ...refresh}`
  (`current_weight_kg` keeps the RAW weigh-in; every reader of it is unchanged). It captures `HiveUserSession.currentOwnerFullId` before the first await (the
  `tool_dispatcher.dart` pattern). **The whole refresh (strict reader, mean, `weighInTargetRefresh`) runs in its own try / catch inside the builder**: any throw (a corrupt
  stored height makes `recomputeDerivedTargets` throw at its `as num?` cast (`profile_target_recompute.dart`, before `calculateTargets`); `patchProfileWith` rethrows from inside the lock) records `recordNonFatal` and returns `{'current_weight_kg': raw}` only,
  so the raw weight is always written exactly as today (`goal_change_patch.dart:200-218` is the precedent). The refresh is skipped when `HealthWriteService.logWeight`
  returned a failed `WriteResult` (today's code ignores the result and still writes the raw weight: that stays) and when the kill switch `disable_profile_target_recompute`
  is set (then the profile written is the old `updateField` result, `updated_at` aside); `disable_bodyfat_calc` is only the `bodyFatCalcDisabled` argument, as in `recalculateTargets`.
- It returns `WeightLogResult {wrote, targetsMoved, caloriesFrom/To, proteinFrom/To}` (was `Future<void>`). When the targets moved: `invalidateProfileDerivedSurfaces` and
  `unawaited(SyncService.instance.pushSnapshot())` (the health write's own push ran before the profile patch, so the server snapshot would keep the old calories).
  `WeightLogSheet._save` adds one factual line to its snackbar when `targetsMoved` (exact numbers, B3 copy); `ConversationalLogHandler` awaits and ignores it. `wrote == false`
  (owner changed) -> no success line for the profile part. A test seam `WeightLogNotifier.debugBeforeProfileWrite` (awaited after the health write, before the patch; the
  `ToolDispatcher.debugBeforeSwitchGoalProfileWrite` precedent) lets a test change the Hive owner where a real account switch would land.
- Edit Profile keeps recomputing from the weight in its field and sets the basis to it (overlay).
- Cross-device residual (accepted): device A recomputes from the mean and pushes; device B's restore sees the changed raw weight and recomputes from the RAW weight
  (`sync_profile.dart:877`), so B stores a slightly different calorie number and its basis becomes the raw weight.

### B2b — bootstrapper first-sign-in merge

The F2 branch (`auth_session_bootstrapper.dart:880-893`) merges the cloud row over the local profile with no recompute. Fix: a pure helper in a NEW file
`lib/features/profile/services/profile_cloud_merge.dart` (not in `profile_target_recompute.dart`: its registry reason, `blast_radius_sync_engine_platform_test.dart:312-318`, says the file only computes on merge winners, which a cloud-over-local merge would falsify), `mergeCloudProfileWithTargets(existing, cloud, now, bodyFatCalcDisabled, recomputeDisabled)`:
the existing per-key merge (cloud non-null wins, `id` / `email` set by the caller afterwards), then `recomputeDerivedTargets` over the merged map **only when `existing` is a
NON-EMPTY map** and `derivedTargetInputsChanged(existing, merged)`; overlay applied only when non-null. **The recompute runs inside its own try / catch** (a non-numeric local `height_cm` makes `recomputeDerivedTargets` throw at its `as num?` cast, and the F2 branch sits in the `try` that ends at `auth_session_bootstrapper.dart:1071`, so an uncaught throw would skip `updateProfile(merged)`, the `onboarding_completed` write and the progress hydrate): on a throw it records `recordNonFatal` and returns the plain merge, the fail-open shape of the restore path (`sync_profile.dart:~850-885`). The change predicate is `derivedTargetInputsChanged` (raw `!=`): a local ISO-timestamp `date_of_birth` against the cloud's `YYYY-MM-DD` counts as changed and recomputes once at the first merge, exactly as the restore path does today (accepted, bounded to one recompute, and the overlay is what Edit Profile would store). A null or empty `existing` (a fresh device) keeps the cloud targets
verbatim: with `{}` every cloud input key counts as changed and the helper would recompute and override the cloud calories, the "silent backfill" the guard exists to prevent
(`profile_target_recompute.dart:33-46`); the restore path escapes it only because the bootstrapper already wrote the merge. The kill switches are passed in as booleans read at
the call site from `configBox` (`disable_profile_target_recompute`, via the public `LegacyGoalHealer.recomputeKillSwitch`, not the `@visibleForTesting`
`SyncService.kDisableProfileTargetRecomputeKey`, which would be a `warning -` outside its library; `disable_bodyfat_calc`). The bootstrapper calls the helper instead of
building `merged` inline.

### B3 — Edit Profile impact line

- `TargetImpact` (pure): from / to daily calories and protein; `before` = the profile snapshot captured when the form OPENS (`initState`, a copy of `UserRepository.instance.getProfile()`), not the profile read just before `updateProfile`: the
  body-fat assessment door persists `body_fat_percent` and recomputes nothing while the form is open (`edit_profile_screen.dart:1907-1912`), so a read taken at Save time would
  already hold the body fat and the dialog would stay silent about the calorie change that Save then applies. Against the open-time snapshot the Save's dialog shows it, `after` = the profile after `recalculateTargets()` (both awaited inside `_save`, no race).
- Shown only when the numbers moved AND a derivation input really changed in this Save, judged by a NEW pure `derivationInputsChangedForDialog(openSnapshot, afterWrite)`, NOT
  by `derivedTargetInputsChanged` (its `!=` fires on an unchanged form): onboarding stores `date_of_birth` as an ISO timestamp (`identity_screen.dart:506`,
  `plan_screen.dart:565`) and Edit Profile re-saves `YYYY-MM-DD` (`edit_profile_screen.dart:2043-2046`), and the height field shows whole cm (`toStringAsFixed(0)`, `:277-282`),
  so a stored 177.8 re-saves as 178. The new function compares `date_of_birth` by its first 10 characters, `height_cm` within 0.5, every other number within 0.05, text
  after trim, lists as lists. (A Save whose only change is such a re-derivation still recomputes, as today, silently: the existing behaviour, not a new one.)
- Placement: the info dialog is awaited after the push / prediction block and just before the success snackbar and `context.go`, guarded by `mounted`; `_isSaving` stays true
  meanwhile. If the reschedule dialog opens, its content gains an "Already updated" section with the same lines (its buttons concern the workouts only, the targets are
  already saved) and no second dialog follows. A Save that also changes the diet strategy can show the strategy confirm first and this dialog after, in sequence, never
  stacked (accepted: `confirmEditProfileDietStrategy` returns `true` without a dialog on the `sameShown` path, so its result cannot say whether a dialog was shown, and the
  nutrition service is not changed for it).
- Copy: exact numbers ("Daily calories 2,000 -> 1,775 kcal", "Protein 144 -> 130 g"), a new small `TargetImpactCopy` beside `GoalChangeCopy` (its lines say "about", true for
  the coach's estimate, false here); plus one sentence when a saved plan exists ("Your saved diet chart still shows the old numbers."); title "Targets updated". Plain
  factual wording in the vocabulary of the app (precedent `GoalChangeCopy`).
- Existing tests: only `test/profile/edit_profile_goal_target_test.dart` pumps `EditProfileScreen` and taps SAVE (`tapSave` pumps and never settles, its store assertions run
  before the dialog). A lingering dialog does not hang it, but the fixtures that move targets now leave one open: those tests dismiss it. Found by running `test/profile` and
  `test/contracts/*edit_profile*` before the commit.

### B4 — stale saved-plan banner

- Naming: the stamps are `diet_target_calories` and `diet_target_protein` (the family of `diet_strategy` / `diet_supplements`; `target_calories` collides with the per-meal
  `_MealPlan.targetCalories`). Two new top-level keys; the item schema is untouched; the cloud copy carries them (whole `plan_json` round-trips, `sync_restore_completeness`;
  no test pins the plan's top-level key set).
- Screen state `_planStamp` (a `({int calories, int protein})?`; NOT `_planTargets`, which is already a method in `diet_plan_screen_swap.dart:283`, and an instance field
  would shadow the extension member and break `:313` / `:328`), maintained like `_planStrategy` / `_planSupplements`: `_generateFreshPlan` sets it from the two ints it built
  the plan for (`:284-285`, `calorieTarget` / `proteinTarget`), and to null when the profile is absent (`usingFallback`, below), so every fresh-generate path replaces it; `_loadSavedPlan` sets it from the saved stamps (null for an unstamped plan); `_savePlan`
  writes it (omitting the keys when null), so Save can never launder a stale plan with the new numbers. `_generateFreshPlan`'s body must not contain `HiveService`
  (`diet_plan_curated_switch_test.dart:52`): the stamp code uses `UserRepository` / `resolveBaseMacroPack` only.
- Pure decision `staleTargetsOf(stamp, current, {required bool usingFallback})` in `services/diet_plan_stale_targets.dart`: null when the stamp is null or `usingFallback`,
  else the pair when the rounded calories OR the rounded protein differ. `usingFallback = resolveBaseMacroPack(UserRepository.instance.getProfile()) == null` (the signal
  `_buildTotalsRow` already evaluates every build, `diet_plan_screen_swap.dart:327`; the same base is also read at `:312` in `_planTotalLine` and at `:163`); `daily_calories` missing is NOT the test, because `_resolveBaseTargets` recomputes real
  numbers from weight, height and gender when the stored four-pack is incomplete.
- `build()` evaluates it every build against `macroTargetsProvider`. The banner follows INVALIDATION, not profile writes: `MacroTargetsNotifier` watches only the auth token,
  the subscription and the restore tick, so the writers that call `invalidateProfileDerivedSurfaces` (Edit Profile, the coach `switchGoal`, the new weigh-in path) refresh
  it; a bare `updateProfile` does not. Tests invalidate the provider explicitly. The banner is `widgets/diet_plan_stale_banner.dart`: the two number lines ("Calories 2,000
  -> 1,775", "Protein 144 -> 130 g"), the sentence "Regenerating replaces the plan on screen.", a "Regenerate" button and a dismiss; stable `ValueKey`s; dismissal is per visit and
  keyed to the (stamp, current) pair, so a later move shows it again. Wardroom palette and DM Sans only.
- "Regenerate" calls a method in the part file `diet_plan_screen_swap.dart` that does `_regenerations++; _generateFreshPlan();` plus the "Save to keep it" snackbar
  (`diet_plan_curated_switch_test.dart:68-80` requires the AppBar button's exact `onPressed: () { _regenerations++; _generateFreshPlan();` and EXACTLY ONE
  `_regenerations++` in `diet_plan_screen.dart`; a second inline literal would turn it red, and that part file must not contain `_savePlan` or `saveDietPlan`, pinned at
  `diet_plan_chart_v3_screen_test.dart` ~880-890). Every fresh-generate path replaces `_planStamp` (a fallback profile sets it to null, never leaves an old value). The new plan is UNSAVED (`_saved = false`), the old saved plan stays stale in
  Hive and keeps feeding the Nutrition-tab hints until the user taps Save; the banner returns on the next visit if the user did not save. Regenerate over unsaved hand swaps
  discards them (the AppBar refresh does the same today); the banner sentence says so, and that is the explicit tap the founder's "never erased silently" asks for.
- An UNSTAMPED saved plan (every plan saved before this change, including the founder's own) shows no banner and stays unstamped when re-saved; a stamp appears only after
  Regenerate then Save. The diagnose doc and the device-check note say so.
- Gate 43: `diet_plan_screen.dart` is 743 lines (limit 800; the part files do not count); the call-site additions are about 25 lines, the logic lives in the new files and the
  part file.

## 4. Writers and readers named before the change (§4.1)

| Concept | Writers | Readers |
|---|---|---|
| calorie / protein targets | `BmrCalculator.calculateTargets` via Edit Profile `recalculateTargets`, `goalChange`, legacy healer, restore recompute, onboarding, the two fallbacks, and (new) the weigh-in patch and the bootstrapper merge | `macroTargetsProvider` / `_resolveNutritionTargets`, Home `NutritionSummaryNotifier`, coach snapshot, Diet chart, profile card, the two new B3 / B4 surfaces |
| `targets_basis_weight_kg` (new, local) | `recomputeDerivedTargets` overlay; the weigh-in seed | only `weighInTargetRefresh` |
| `current_weight_kg` | Edit Profile, weigh-in (raw), restore, bootstrapper, onboarding | unchanged (25 files) |
| `diet_target_calories` / `diet_target_protein` (new) | `diet_plan_screen._savePlan` from `_planStamp` | `_loadSavedPlan` -> `staleTargetsOf` in `build()`; the cloud copy |
| goal projection | `BmrCalculator.projectGoalDate` | the three screens in section 2 |

## 5. Value-semantics sweep (§4.1.5 point 3)

- Stored values whose meaning changes: Cut `protein_grams` (the new rule is higher for a Cut with a target below 90 % of the weight) and the projected date. Existing
  profiles are not rewritten (they move at their next recompute: a Save, a drift weigh-in, a goal change); founder launch note, every account is a testing account.
- NO existing test derives a Cut protein from a target weight: `test/bmr_calculator_test.dart` and `bmr_calculator_pace_test.dart` never pass `targetWeightKg`, and the only
  `targetWeightKg:` in `test/` is a `build_muscle` fixture in `profile_edit_recompute_consistency_test.dart:33` (unaffected). Every B1 protein test is NEW. The tests that
  store a Cut protein literal (`protein_grams: 150` in `goal_targets_preview_test`, `goal_change_patch_test`, `goal_target_weight_two_doors_behavioral_test`,
  `edit_profile_goal_target_test`) are seeds, not derived, and the ones using `recomputeDerivedTargets` as their oracle follow the change (`goal_change_patch_test.dart:117-132`:
  target 70 at 75 kg, `max(70, 67.5) = 70`, its "seed vs stale differ" assertion holds). The one existing assertion that breaks is
  `test/bmr_calculator_pace_test.dart:111-118` (80 -> 79 aggressive, `>= 4.0`; the new rule gives about 1.7): rewritten. `supabase/functions/` derives no protein
  (`weekly-report`, `future-prediction` and `switchGoal` mention `lose_fat` only). `docs/architecture/functionality-flow.md:76` quotes "protein 1.8 / 2.0 / 1.6 g/kg": gets a
  Cut-base sentence. Nothing live quotes the 2 kg projection rule except the doc comment at `bmr_calculator.dart:296`. The two protein comments become false and are rewritten with the code: the `targetWeightKg` parameter doc (`bmr_calculator.dart:176-178`, "protein is calculated from target weight") and the inline comment at `:221-222` ("use target weight ... so that overweight users don't get inflated protein").
- Source-grep pins on code this batch changes (each REPOINTED in the same commit, never loosened, §4.9): `weight_log_invalidation_awaitable_test.dart:38`
  (`Future<void> logWeight(double weightKg) async` -> the new signature; the two `await ...logWeight` pins at `:53` / `:77` still match); `diet_plan_curated_switch_test.dart:52`
  (`_generateFreshPlan` body has no `HiveService`) and `:68-80` (the AppBar regenerate regex and exactly one `_regenerations++` in `diet_plan_screen.dart`);
  `diet_plan_chart_v3_screen_test.dart` ~880-890 (`diet_plan_screen_swap.dart` has no `_savePlan` / `saveDietPlan`); `diet_strategy_selector_test.dart:515-531` (counts of
  `'diet_strategy'` and `'diet_strategy':`: the `diet_target_*` keys do not match; no second `planData['diet_strategy']` read);
  `blast_radius_sync_engine_platform_test.dart:312-319` (`profile_target_recompute.dart` keeps its declined reason because it gains only the overlay key; the bootstrapper, an engine file, imports the NEW `profile_cloud_merge.dart`, so that test and `docs/blast_radius.yaml` prong 3 (~600-620) are run and the file is classified HONESTLY by what they say: it merges cloud with local, so it is not declined on the "computation on winners" reason).
- SoT registry: `check_sot_registry_parity.dart` fails a commit with `[stale-line-range]` when a cited method leaves its range, so EVERY entry citing the touched files is
  recomputed from anchors per commit: `home_provider.dart` (`weight_logs` / `health_write_service` 677-965 and 904-938, `exercise_personal_records` 968-979),
  `diet_plan_screen.dart` (`diet_plan_saved_loaded` 357-420 / 173-202 / 422-536, `diet_supplements` 129-172, `diet_preference_vocabulary` 173-263, `diet_strategy_targets` 96-127,
  `diet_plan_generation_quality`), `edit_profile_screen.dart` (`_save` 1856-2294 and 1856-1996), `profile_target_recompute.dart`, `bmr_calculator.dart`,
  `auth_session_bootstrapper.dart`. The `diet_plan_saved_loaded` prose ("the plan map gains ONE top-level key, food_type", about `sot_registry.yaml:1658`) is already stale and is
  rewritten (food_type, strategy and supplements stamps, the two target stamps). New concept `weigh_in_target_refresh`.
- Overlay key set: `profile_target_recompute_test.dart:37-52` uses `containsAll`, so it stays green when the overlay gains the key; a NEW exact assertion pins the key
  (a mutant dropping it would otherwise survive). `goal_change_patch_test.dart:163` asserts the patch keys only in the no-recompute case: unchanged.
- `projectGoalDate` readers: the three screens; `logWeight` callers: the weight sheet and `ConversationalLogHandler._logWeight` only (both await and ignore the result;
  `simulation_service` and onboarding call `HealthWriteService` directly); no test constructs `WeightLogNotifier` or overrides `weightLogNotifierProvider`.

## 6. Tests (each named with the mutant that must redden it; every mutation confirmed applied with `grep -c`, rule 21)

All regression tests live under `test/contracts/` (the §4.1 rule) unless a widget test belongs next to its screen. Behavioural harness for `WeightLogNotifier`: built from
scratch on the shape of `goal_target_weight_two_doors_behavioral_test.dart:50-110` (`GuardedBox.testBypassOwnership`, `HiveUserSession.openForUser`,
`SyncService.pausedForSimulation = true`, `BadgeService.checkAll` runs for real on the opened per-user boxes, as it does in that file: it has no seam); with the ownership bypass on, `stillOwner` is the only guard, exercised through
`WeightLogNotifier.debugBeforeProfileWrite`. "One write" is observed with `ProfileWriteService.debugOnFireSync` (counts once per patch; static, reset in `tearDown`).

- B1 (all new, section 5): Cut 75 kg target 65 -> 135 g (mutant: base = target); target 72 -> 144 g (mutant: always `0.9 * weight`); Build / Maintain unchanged; Cut >= Build per
  current kg for target weights 40 % to 100 % of current, asserted against `min(raw, cap)` per goal (uncapped fixtures plus the capped 70 kg example that records the exception).
  Projection (rewrite of `bmr_calculator_pace_test.dart:111-118`): aggressive 80 -> 79 is FASTER than slow (mutant: the old forced-slow block), the 1-week floor, `gap == 0`, 85 -> 80
  values unchanged. Provider fallback: a Cut profile with a target and no stored targets resolves the new-rule protein through `resolveNutritionTargetsForTest` (mutant: the
  fallback drops `targetWeightKg`).
- B2 pure `weigh_in_target_refresh_test.dart`: the band in integer tenths (2.0 no, 2.1 yes, and `64.4` against `62.4`, the float trap; mutant: plain `>` on doubles); seed without a
  basis; the 12-week 0.4 kg-a-week sequence (first recompute at week 6, second at week 12); incomplete profile -> nothing; mean over a 7-day window with gaps, a future-dated
  row, a `weight_log_` key, a non-`weight_log` type, 0 and 501 kg, same-day overwrite, a mean that is not exactly representable; zero qualifying entries -> raw.
  Behavioural `weigh_in_target_refresh_behavioral_test.dart` (the real `WeightLogNotifier` on real Hive): an in-band weigh-in writes the raw weight AND seeds the basis, calories
  unchanged (mutant: returns a null patch, so the weight is not written); a drift weigh-in moves calories, protein and the basis in ONE `debugOnFireSync` count (mutant: an
  `updateField` for the weight then a second patch); the coach-chat door does the same; an owner change at `debugBeforeProfileWrite` -> `wrote == false`, nothing written; a failed
  health write skips the refresh and keeps the raw weight; a profile whose `height_cm` is a String makes the refresh throw and the raw weight is STILL written and `logWeight` does not
  throw (mutant: remove the catch); with `disable_profile_target_recompute` set the profile after a weigh-in equals the old `updateField` write with `updated_at` excluded (both stamp it; OFF identity);
  the overlay carries `targets_basis_weight_kg` (mutant: key dropped).
- B2b pure `bootstrapper_profile_merge_recompute_test.dart`: local data plus a cloud weight recomputes and writes the basis; a profile with a String `height_cm` still produces the plain merge and `updateProfile` is still reached (mutant: remove the catch); `existing == null` and `existing == {}` keep the cloud
  targets verbatim (mutant: treat null as `{}`); no input change -> no recompute (body-fat healer lock); both switches; a null overlay leaves the map as merged. Call site: one case
  next to `progress_restore_freeze_merge_behavioral_test.dart:685` (it already drives the real `hydrateFromCloud`): a local profile plus a cloud weight ends with recomputed targets
  (mutant: the bootstrapper builds `merged` inline again).
- B3 pure `derivation_inputs_changed_for_dialog_test.dart`: an ISO-timestamp `date_of_birth` against `YYYY-MM-DD` of the same day is unchanged; a fractional height within 0.5 is
  unchanged; a weight change, a pace change, a lifestyle change are changes (mutants: raw `!=` on the date; exact height). Widget test on Edit Profile (existing harness,
  `tester.runAsync` for Hive taps, font warm-up first, §4.9): a pace-only edit shows "Targets updated" with from -> to numbers; an assessment persisted while the form is open (`body_fat_percent` written through `updateProfile`) followed by an otherwise untouched Save shows the dialog with the open-time numbers (mutant: `before` read at Save time); a workout-field edit with a plan shows the
  "Already updated" section inside the reschedule dialog and no second dialog; an unchanged Save of an ISO-DOB / fractional-height profile with stale targets shows NO dialog; a
  phone-number-only edit shows none; the three `moved` fixtures (calories only, protein only, equal) kill an `&&` / `||` swap. The existing fixtures that now leave a dialog open
  dismiss it.
- B4 pure `diet_plan_stale_banner_test.dart` (`staleTargetsOf`): three fixtures calories-only / protein-only / equal (kills `&&`/`||`), a rounding case 2400.4 vs 2400,
  `usingFallback`, a profile with weight / height / gender but no stored targets (the banner is neither suppressed nor spurious there). Widget test on the Diet chart
  (`diet_plan_chart_v3_screen_test.dart` harness: font warm-up, `_tapReal`, `seed`, `_savedPlan`, `_pack`): a stamped saved plan with a different target shows the banner; the same
  target none; an UNSTAMPED plan none and `debugDietPlanGenerations == 0` (the saved-plan path really ran; the plan is seeded through `UserRepository.saveDietPlan` so it passes the
  three `savedPlanMatches*`); a target that moves while the screen is open shows it after the test invalidates `macroTargetsProvider`; Regenerate adds one generation (mutant:
  `_regenerations` not incremented), removes the banner and leaves the saved plan in Hive unchanged; a fresh plan generated, the target changed, then Save stamps the GENERATION-time
  numbers (mutant: stamps `ref.read` at save time; targets that differ from each other and from 2400 / 184); a LOADED stale stamped plan re-saved keeps the OLD stamp and the banner
  stays (mutant: `_savePlan` writes the current target); an unstamped loaded plan re-saved gets no `diet_target_*` keys; dismissal returns when the target moves again.
- Docs / gates: SoT registry (concepts `profile_target_recompute` overlay, the bmr targets concept, `goal_target_weight_agreement` projection fields, `weight_logs` /
  `WeightLogNotifier`, `diet_plan_saved_loaded`, new `weigh_in_target_refresh` with `behavioral_test_path` and sibling `behavioral_test_path_*` keys that resolve, ranges from anchors per
  commit); `docs/naming_conventions.md` (`targets_basis_weight_kg`, `diet_target_calories` / `diet_target_protein` ("target stamp", cross-referenced to the existing `diet_strategy*`
  "stamp" row), `weigh-in drift`, `stale plan banner`; no collisions, grep-checked); nested CLAUDE.md rows in `lib/features/profile/CLAUDE.md` and `lib/features/nutrition/CLAUDE.md`
  (grep the sentences before editing: other tests source-grep them); `functionality-flow.md:76`. The context-artifact budget is a no-op unless a tracked file is touched
  (`kTrackedArtifacts` does not list the two nested files, naming, the registry or functionality-flow); re-run `dart run scripts/check_context_artifact_budget.dart` anyway.

## 7. Process

- Bug history first (§4.1.5): build the local indexes, grep `docs/diagnoses/INDEX.md` for target recompute, weigh-in, projection, protein base, saved plan staleness; cite
  `3cbbce` (profile write doors), `b5d2e8` (OI-191), `c3f2d8` (body-fat), OI-150 (restore recompute) in the diagnose doc's `related_bugs:` / `recurrence:`.
- One full-template diagnose doc for the batch (`docs/diagnoses/<date>-<slug>-<6 hex id>.md`: `bug_id`, `blast_radius: account`, `tier`, `sot_registry_entry` naming an existing
  concept, an existing `contract_test_path`, `touched_layers_checked`; it states that an unstamped saved plan shows no banner until Regenerate then Save): the founder's observations are
  bugs and the class is writer/reader drift, so §4.1 and rule 22 apply whatever the commit prefix; the commits that fix a bug are `fix(...)` with `closes-diagnose: <id>`.
- `docs/audit/goal-change-targets.closure.yaml` (Gate 40, runs on every commit): created only when EVERY entry is terminal (after the B-pass findings are dispositioned): one entry
  per item (B1, B1 fallbacks, B2, B2b, B3, B4, docs and registry), one per door row classified `verified_clean` (body-fat assessment door, Health Connect import, body-fat healer), one
  per plan-review and B-pass finding; `closed_in_commit` needs `commit:` plus `verification:` or `notes:` (a branch label until the SHAs exist), `verified_clean` needs `evidence:`
  or `notes:`, `closed_count` recomputed, no `deferred:` key.
- Before the first review dispatch with a diff: whole-project `flutter analyze --no-fatal-infos`, the pre-commit gate loop, commit, open the PR (not a draft), `sh scripts/land_pr.sh
  <pr> --ci-only` in the background, dispatch only on `result: ci-green` (§4.12.8). Then the self-initiated `/code-review` B-pass before any merge (§4.3, `account`; the record's
  `bpass:` field is required only from `platform`), with `docs/plan-reviews/goal-change-targets.md` (rounds >= 2, `ground_truth_verified`, `verdict: converged`).
- Merge only on the founder's word, via `sh scripts/land_pr.sh <pr>`.

## 8. Risks

- A weigh-in can now move the calorie target (founder-chosen). Bounded by the 2 kg band on a 7-day mean; shown on the weight snackbar; `disable_profile_target_recompute`
  switches it off and any throw in the refresh falls back to the plain raw-weight write.
- A single wild reading is the whole mean when it is the week's only weigh-in (a weekly weigher gets no smoothing; a daily weigher is lagged by about 3 days). A second reading
  pulls the mean back and a later drift recompute corrects the targets. Accepted (founder chose the plain 7-day mean).
- Seeding the basis from the pre-weigh-in `current_weight_kg` assumes no unrecomputed weight write happened since the targets were built. The doors that break it (the body-fat
  assessment, a pre-B2b bootstrapper merge) are narrow; testing accounts only.
- Edit Profile re-derives from the raw weight in its field and the weigh-in from the mean: after an in-band weigh-in, any Save can move calories by about 10-30 kcal;
  B3 shows the dialog only when a derivation input really changed, so the silent re-derivation is the existing behaviour, not a new one. Cross-device: see B2.
- Regenerate on the banner discards unsaved hand swaps on screen (same as the AppBar refresh); the banner says so.
- `edit_profile_screen.dart` is on the Gate 43 allow-list (2461 lines); new logic goes in new files.
- The projection change moves the "~N wks" within 2 kg of the goal earlier, never later.

## 9. Round-1 dispositions (21 rows, 2 seats)

| Finding | Disposition | Landed in |
|---|---|---|
| A1 `logWeight` return type breaks the source-grep pin | repointed; registry rewritten | 5 |
| A2 B3 dialog placement hangs existing tests | placed before the snackbar / `go`, `mounted`, tests updated | 3 B3, 6 |
| A3 door table incomplete | body-fat door kept (Save compares stored targets), bootstrapper merge FIXED (B2b), healer deliberate, Health Connect accepted, fallbacks fixed | 2, 3 |
| A4 no single reader for weight entries | strict dedicated reader, chart untouched, zero entries -> raw | 2, 3 B2 |
| A5 kill switches | both honoured, OFF-identity test | 3 B2, 6 |
| A6 "Cut >= Build" false when the cap binds | claim scoped, test against `min(raw, cap)` | 3 B1, 6 |
| A7 projection wording, phantom doc sweep | softened, sweep corrected | 2, 3 B1 |
| A8 result flag, snapshot staleness | `wrote`, `pushSnapshot` when moved | 3 B2 |
| A9 basis seeding assumption | hand-run, stated | 8 |
| A10 dialog label, "about", redundancy, noise | "Already updated", exact copy, input-changed gate, strategy-confirm skip | 3 B3 |
| A11 registry / overlay-pin housekeeping | listed | 5, 6 |
| B1 stamp launders a stale plan | `_planTargets` state, stamp from it | 3 B4 |
| B2 comparison timing, clearing, regenerate, dismissal, rounding | in `build()`, shared regenerate body, keyed dismissal, ints, fallback suppressed | 3 B4 |
| B3 "no diagnose docs" wrong | full diagnose doc, `fix(...)` commits | 7 |
| B4 plan-review record, B-pass, blast radius, §4.12.8 | added | header, 7 |
| B5 source-grep pin on `Future<void> logWeight` | repointed | 5 |
| B6 false claims in section 5 | corrected, derived-vs-stored test list | 2, 5 |
| B7 B1 cap carve-out, floor residual | scoped, recorded | 3 B1 |
| B8 tests would pass for the wrong reason | mutants named per test | 6 |
| B9 registry / naming / nested-doc / ledger obligations | listed with shapes | 6, 7 |
| B10 B4 smaller points | pure decision in its own file, line margin | 3 B4 |

## 10. Round-2 dispositions (2 seats: A = B1/B2/B2b/B3, B = B4 and process; 5 P1, 14 P2)

| Finding | Disposition | Landed in |
|---|---|---|
| A1 a throw in the builder loses the raw weight | the refresh has its own try / catch, test with a String height | 3 B2, 6 |
| A2 B2b recomputes on a fresh device (`existing` null / `{}`) | non-empty `existing` only; fixtures for null and `{}` | 3 B2b, 6 |
| A3 DOB format makes "input changed" fire on an unchanged form | a new normalizing comparison for the dialog | 3 B3, 6 |
| A4 height rounding, a second false positive | height within 0.5 in the same function | 3 B3 |
| A5 strategy-confirm skip not implementable | dropped, accepted as two dialogs in sequence | 3 B3 |
| A6 band comparison float-fragile | integer tenths | 3 B2, 6 |
| A7 kill-switch wording, cross-device mismatch | clarified, residual recorded | 3 B2 |
| A8 `@visibleForTesting` constant, unpinned call site, engine-import test | public `LegacyGoalHealer.recomputeKillSwitch`, call-site case, re-run | 3 B2b, 5, 6 |
| A9 repository fallback is a no-op for protein | reworded, no behavioural claim | 3 B1, 6 |
| A10 existing-test impact overstated | reworded to a lingering dialog | 3 B3 |
| B1 `_planTargets` is already a method | field renamed `_planStamp` | 3 B4 |
| B2 source-grep pins on `diet_plan_screen.dart` | Regenerate lives in the part file; pins listed | 3 B4, 5 |
| B3 fallback rule mis-specified | `usingFallback` from `resolveBaseMacroPack` | 3 B4 |
| B4 `macroTargetsProvider` does not follow writes | stated; tests invalidate | 3 B4, 6 |
| B5 unstamped plans, launder test, Regenerate over swaps | stated, tests added, banner copy | 3 B4, 6, 8 |
| B6 three false statements in section 5 | corrected | 5 |
| B7 registry ranges incomplete | every citing entry | 5 |
| B8 test seams that do not exist | harness described, `debugBeforeProfileWrite` added | 6, 3 B2 |
| B9 process obligations misdescribed | budget no-op, diagnose fields, closure timing, tier L, §4.6 posture | header, 7 |

## 11. Round-3 dispositions (1 fresh seat on revision 3: 1 P1, 8 P2)

| Finding | Disposition | Landed in |
|---|---|---|
| P1 B2b has no fail-open around the recompute | own try / catch returning the plain merge; String-height fixture and mutant | 3 B2b, 6 |
| P2 body-fat assessment door: dialog silent because `before` already holds the body fat | `before` is the form-open snapshot; test and mutant | 2, 3 B3, 6 |
| P2 "22 findings" vs 21 rows | heading corrected | 9 |
| P2 `BadgeService.checkAll` has no seam | harness says it runs for real | 6 |
| P2 helper in `profile_target_recompute.dart` falsifies its declined reason | helper moved to new `profile_cloud_merge.dart`; engine-file importer test and prong 3 run, classified honestly | 3 B2b, 5 |
| P2 B2b predicate raw `!=` DOB false positive | accepted and stated (one recompute at first merge, as the restore path) | 3 B2b |
| P2 stale B1 comments (`bmr_calculator.dart:176-178`, `:221-222`) | added to the repoint list | 5 |
| P2 `_planStamp` contradiction | fallback sets null; every fresh path replaces it; `:327` cited | 3 B4 |
| P2 citation drift, throw location, `updated_at` in the OFF-identity test | `:239`, `:284-285`, the `as num?` cast, `updated_at` excluded | 2, 3, 6 |
