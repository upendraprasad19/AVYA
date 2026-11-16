# Generator Unit 3B: three goals, and 90 minutes for advanced users (OI-487 rest, OI-488)

Board step 3 (t301-t308), unit 3B of `docs/plans/2026-11-15-generator-step3a-goal-training.md` §0. Founder decisions
d4 (2026-11-08), d69-d73 (2026-11-16). Tier L (account profile data, an Edge Function); blast radius `account` for the
profile half, `platform` for `session_budget.dart` / `training_history_analyzer.dart` (plan_engine path), plus the
ai-proxy tools (a deploy with its own go, t306). Execution mode: inline (one worktree, `generator-step3b`).
`plan_generator.dart` is not touched.

## 0. Decisions

| Id | Decision |
|---|---|
| d4 | Strength is removed as a goal from Edit Profile and the coach; its testers become Build with the Strength focus. Edit Profile says Cut / Maintain. |
| d69 | The goal list is Build, Cut, Maintain everywhere a user picks a goal (founder: "We only have build, cut and maintain"). |
| d70 | 90 minutes keys on the PROFILE level the user chose (`fitness_experience`), not the effective level. The 90 chip shows only for Advanced; a stored 90 for anyone else plans as 60. |
| d71 | A Strength-goal tester gets the Strength focus only when their focus is Balanced or empty; a focus they chose is kept. Calories become Build's. |
| d72 | Recomposition testers move to Cut. |
| d73 | Goal names are Build / Cut / Maintain wherever a goal is named (the `FitnessGoals` label table: profile card, coach diffs, Edit Profile). |

Live data (read-only, 2026-11-16, `user_profile` on dedsavbjuwgarrhphgnl): 4 rows `strength` (3 focus `balanced`,
1 `glutes_legs`), 5 rows `recompose` (focus `balanced` x2, `chest_shoulders_arms` x1, null x2), 8 rows at 90 minutes
below advanced (beginner 3, intermediate 5, one of them a `strength` row). All are test accounts (pre-launch).

## 1. What happens today (main bfa93a04)

**Goal token.** Hive `userBox['profile']['primary_goal']`, cloud `user_profile.primary_goal` (text, no CHECK).
`FitnessGoals._byToken` (`lib/core/constants/fitness_goals.dart:60-116`) has five rows: build_muscle, lose_fat,
strength, general_fitness, recompose. No read-time normalizer: a stored `strength` stays `strength` for every reader,
and the engine has a real `strength` plan goal (`split_resolver.dart:178 / 883`, `session_budget.dart:464 / 483 / 497`,
`exercise_selector.dart:239 / 763`).

Writers that can still produce `strength` / `recompose`:
- Edit Profile `_goals` (`edit_profile_screen.dart:143-148`, incl. `'strength': 'Build Strength'`), seeded raw at
  `:238`, saved at `:1886`. `_buildDropdown` (`:890-898`) displays the first option for an unlisted value but keeps
  `_goal`, so a recompose user sees "Build Muscle" and saves `recompose` back.
- Coach: `tool_dispatcher.dart` `_executeSwitchGoal` (`:1292` `isKnown` guard, `:1324` patch) and
  `_executeRegeneratePlanBlock` (`:1037`); server enums `_shared/tools/plan/switchGoal.ts:5-11` and
  `regeneratePlanBlock.ts:8-14` list all five tokens.
- Legacy chat onboarding (`/onboarding/chat`, `app_router.dart:340`): options
  `['build_muscle','lose_fat','general_fitness','strength']` (`onboarding_provider.dart:86-89`).
- `plan_screen._mapGoal` (`:776-783`) has `'strength' => 'strength'` and `'recomp' => 'recompose'` arms, but no
  card emits those keys (`goal_screen.dart:259`) and `GoalScreen.initState` (`:78-87`) maps a legacy route extra to
  Build: dead, not a live writer.
- Older app builds already on test phones (their Edit Profile still offers Strength) and restore
  (`_restoreUserProfile`, `sync_profile.dart:768`, cloud non-null wins per key).

So `strength` / `recompose` remain REACHABLE from outside this build. That is why this unit keeps both rows (as
legacy, not selectable) and keeps the engine's `strength` paths: removing them would change the output for any value
an old build writes, and the round-1 measurement put the test and fixture churn at about 70 files (golden persona
grid 1,010 -> 770, audit 2,304 -> 1,728, every gate that cites them) for code that the heal below makes unused.

**Physique focus.** `physique_focus` ∈ {balanced, glutes_legs, chest_shoulders_arms, strength}; Edit Profile offers the
Strength chip (`edit_profile_screen.dart:1183-1190`); 3A made it real (`training_history_analyzer.dart:122-139`).
No CHECK on the column (migration 017).

**Session minutes.** Edit Profile chips `[30, 45, 60, 90]` for every level (`edit_profile_screen.dart:1136`), seeded by
`SessionBudget.initialSessionDuration` (`session_budget.dart:59`). Readers of the stored value:
`TrainingHistoryAnalyzer.sessionMinutesFromProfile` (`:228`, raw) used by `plan_generator.dart:174 / 286 / 294`,
`swap_service.dart:555`, `workout_schedule_read_service.dart:227 / 786`; two raw reads passed as the `param` (which wins
over the profile value, `session_budget.dart:40-52`): `pro_phase_advance.dart:215`, `simulation_service.dart:615`
(dev). Edit Profile's reschedule passes its in-form value (`edit_profile_screen.dart:2017`). Only Edit Profile writes
the key (plus restore; onboarding and the coach do not). `fitness_experience` can be absent (defaults differ by reader:
`pro_phase_advance` 'intermediate', `auth_session_bootstrapper` 'beginner').

## 2. Design

### 2.1 Selectable goals vs legacy goals (d69)

`FitnessGoals` keeps all five rows (every reader, the engine and the golden are unchanged). New members:
- `FitnessGoals.selectableTokens = ['build_muscle', 'lose_fat', 'general_fitness']` (the onboarding cards' order) and
  `isSelectable(token)`;
- `FitnessGoals.legacyTargets = {'strength': 'build_muscle', 'recompose': 'lose_fat'}` (d4 / d72): where a legacy
  value goes. A test pins `selectableTokens` LITERALLY (a new goal row never becomes selectable silently) and pins
  `legacyTargets.keys == tokens - selectableTokens == kLegacyReachableOnlyGoalTokens` (the gate lib's set).

Every goal picker and goal check uses the selectable list:
- Edit Profile `_goals` = `selectableTokens` with `label` (the hard-coded map goes);
- the coach "compass" form's switch chips (`compass_form_sheet.dart:249`, today `FitnessGoals.tokens` with the raw
  token as its label) = `selectableTokens` with `label`;
- legacy chat onboarding drops `'strength'` from its options (`onboarding_provider.dart:89`); its label switch
  (`onboarding_chat_screen.dart:873-880`) is a display reader and keeps the legacy arms;
- the coach dispatcher's two guards (`tool_dispatcher.dart:1038`, `:1288`) become `isSelectable`, with a friendly
  refusal ("That goal isn't offered any more. Choose Build, Cut or Maintain."); `SwitchGoalDiff`
  (`switch_goal_diff.dart:54-62`) does not run the regenerate planner for a non-selectable goal and shows that same
  sentence instead of a preview, and `RegeneratePlanDiff._compute` (`regenerate_plan_diff.dart:36-52`) does the same
  when its optional `goal` is set and not selectable, so the user never sees a plan diff that the confirm then refuses
  (the live coach can still propose `strength` / `recompose` until ai-proxy is redeployed, §2.6). The sheet's APPLY
  stays enabled (`tool_confirm_sheet.dart:43-58, 123`); pressing it reaches the dispatcher, whose `isSelectable` guard
  runs before the cached-plan check (`tool_dispatcher.dart:1038`, `:1288` then `:1296`), so the sheet closes with the
  same sentence as a snackbar and nothing is written;
- the server enums list the three (§2.6). Gate Check 4 (`check_goal_token_exhaustiveness.dart:109-149`) compares each
  enum with `tokens - kLegacyReachableOnlyGoalTokens` instead of `tokens`; the comparison moves into
  `goal_token_exhaustiveness_lib.dart` as a pure `serverGoalEnumProblems(...)` with tests (missing, phantom, a legacy
  token listed, a legacy token absent is fine). The gate is `grandfathered` in `gate_test_ledger.yaml:544`, so no new
  ledger state. `ai_proxy_goal_enum_parity_test.dart`'s two equality tests compare with the selectable set (its
  sanity test, `recompose` is a token, stays true).
- `plan_screen._mapGoal` and `target_weight_check.dart` are NOT changed: their `strength` / `recomp` arms are dead (the
  three cards are the only emitter, `goal_screen.dart:259`, and `GoalScreen.initState` maps a legacy extra to Build),
  the gate allowlists both tokens, and `recompose_goal_targets_test.dart:91-100` pins the `recomp` arm.

### 2.2 Stored-value heal (d4, d71, d72)

`lib/core/services/legacy_goal_healer.dart`:
- pure `legacyGoalPatch(Map profile) -> Map<String, dynamic>?`: `primary_goal` in `FitnessGoals.legacyTargets` ->
  `{'primary_goal': target}`, plus `'physique_focus': 'strength'` when the old goal is `strength` and the stored focus
  is null, empty or `balanced` (d71); otherwise null.
- `LegacyGoalHealer.run(String? uid, {required String? Function() liveUid})` (ref-free, never throws, no AWAITED
  network: the local write is the heal, and its normal profile push is what carries it to the cloud):
  1. return when the kill switch `configBox['disable_legacy_goal_heal']` is set, or `uid` is null, or the owner check
     fails. The check is the wrapper's own: `liveUid == uid && HiveUserSession.currentOwnerFullId == uid`, where the
     wrapper passes `liveUid: _liveUserId` (`sync_service.dart:644-647`, which honours the test resolver
     `HiveUserSession.debugCurrentUidResolverForTests` before `currentUser?.id`; `shouldSettleRestoreMarker` is called
     the same way at `:1989`). `run(uid, liveUid: () => _liveUserId)` takes the resolver, not a value, so the re-check
     in step 2 reads it live (the closure is built inside `SyncService`, so the private getter is legal).
  2. one write through a new `ProfileWriteService.patchProfileWith(Map<String, dynamic>? Function(Map<String, dynamic>
     current) build, {required bool Function() stillOwner}) -> Future<bool>` (the healer passes its `owned()` closure:
     the expected uid against the live-uid resolver and `HiveUserSession.currentOwnerFullId`; a false `stillOwner()`
     returns false without touching the box or throwing; true means it wrote):
     under the service's existing `_withLock` it re-checks the owner FIRST (an `expectedUid` and the live-uid
     resolver; `HiveService.userBox` throws a `StateError` on an auth / Hive disagreement, `guarded_box.dart:170-176`,
     so the check runs before the box is touched), then re-reads the profile, calls `build` (synchronous), and writes
     only a non-null patch (merge, `updated_at`), then fires the same fire-and-forget `syncProfileNow` push as
     `patchProfile` (`profile_write_service.dart:138-142`, outside the lock and after the restore core returned, so
     outside `RestoreFailureCollector`'s zone; a failed push is queued by `_syncUserProfile`). Reading, deciding and writing
     under one lock closes the read-then-write window (a user saving Edit Profile meanwhile is either fully before or
     fully after; after it, the goal is selectable and `build` returns null).
  3. `build` = `legacyGoalPatch(current)`, plus the targets: `recomputeDerivedTargets({...current, ...patch}, now:,
     bodyFatCalcDisabled: <disable_bodyfat_calc>)` (`profile_target_recompute.dart:88`) unless
     `SyncService.kDisableProfileTargetRecomputeKey` is set; a non-null overlay joins the patch (d71 / d72 accept the
     calorie change). The overlay includes `carb_grams` (singular), which is a Hive-only key
     (`_resolveNutritionTargets` reads it; not a `user_profile` column); the profile push (`sync_profile.dart:212-254`,
     `_hasValue`-filtered) sends only its own key list, so nothing unknown reaches the cloud.
  4. telemetry event `legacy_goal_healed` (old -> new goal, focus set or kept); a non-fatal on any throw
     (`legacy_goal_heal`).
- Why no cloud-first write (round 2): a cloud-first update added an unbounded network await inside the restore
  wrapper (it would hold the background heal's tick bump and, on a fresh install, entry to Home) and a second
  read-modify-write. The push makes the cloud converge. If it fails, the cloud keeps the legacy value; the next
  `/restoring` restore merges it back (cloud non-null wins, `sync_profile.dart:819-826`; `primary_goal` is a
  derivation input, so the merge also recomputes the LEGACY targets into Hive with `skipSync: true`) and the heal then
  moves both again. In that window (only after a failed push, or an old build re-writing the value) a mounted Home can
  read the legacy state until the heal and the tick bump. `restoreLightweightAlways` (`sync_service.dart:1625`) and the
  other restore entry points (`:1867`, `:2144`, `:2331`) merge the profile but do not heal, so a legacy value they
  bring in waits for the next `/restoring` launch. Accepted (test accounts; the engine serves a legacy value as today).
- `scripts/check_profile_write_service_only.dart` allows only two files to `userBox.put('profile'`; the healer writes
  through `ProfileWriteService`, unlike `BodyFatDefaultHealer` (cloud-first, no sync), which is not its model.
- Call site: `SyncService.restoreFromCloudForUser` (`sync_service.dart:2016-2026`), on `result.succeeded`, with the
  `uid` the wrapper captured before awaiting, as its own step after the completed-title heal and NOT behind
  `shouldHealAfterRestore` (the title heal's switch). `/restoring` is the only post-auth route (`splash_screen.dart:312`,
  `sign_in_screen.dart:229`, `confirm_email_screen.dart:108`) and reaches the wrapper at `restoring_screen.dart:116`,
  for every sign-in method. It runs after the profile merge and before the background heal bumps
  `restoreCompletedTick` (`heal_after_restore.dart:81`); `HiveTabScaffoldMixin._onRestoreCompleted`
  (`hive_tab_scaffold.dart:209`) then refreshes the tabs (Home invalidates `userProfileProvider`, Nutrition
  `macroTargetsProvider`). On the foreground (fresh install) path the providers are built after it.
- Accepted: a restore that reports success while `_restoreUserProfile` swallowed its own error
  (`sync_profile.dart:915`) heals the local profile as it stands (every reader uses that same profile).
- The current plan is NOT regenerated by the heal: the schedule keeps its rows until the next regeneration (phase
  advance, an Edit Profile save that reschedules, a coach regenerate), which then reads Build / Cut. Stated
  consequence for 4 + 5 test accounts.

### 2.3 Edit Profile

- Goal: the dropdown lists the three (§2.1). The form's goal and focus are seeded from `healed = {...profile,
  ...?legacyGoalPatch(profile)}`, and `_goal` falls back to `general_fitness` when the healed value is still not
  selectable (junk, null), so an unhealed `strength` profile opens on Build with the Strength focus (or its own
  focus). `_originalGoal` / `_originalPhysiqueFocus` (`:320`, `:326`) take the RAW stored values, so
  `computePlanChanged` (`:2008-2027`) sees the change and offers the reschedule. The change text (`:2034-2036`) labels
  both sides with `FitnessGoals.isKnown(t) ? FitnessGoals.label(t) : t` (today it reads `_goals[...]`, which would
  print `null` for a legacy original).
- Edit Profile's save always writes `primary_goal` and recomputes the targets, so saving ANY field on an unhealed
  account heals the goal there too (the same d71 / d72 change).
- Labels (d73): `FitnessGoals` labels become `build_muscle` Build, `lose_fat` Cut, `general_fitness` Maintain (the
  onboarding card titles, `goal_screen.dart:55-67`); `strength` / `recompose` keep `Strength` / `Recomposition`. The
  hard-coded goal names go to `FitnessGoals.label`: `switch_goal_diff.dart:283-299` `_humanGoal` and
  `regenerate_plan_diff.dart:262-275` (keeping their `'unknown' -> 'Not set'` arm), `perform_sign_out.dart:45-65`
  `_formatGoal` (the profile header: "Building Muscle" becomes "Build"; d73 names the profile card). The
  onboarding chat labels and `wardroom_copy.dart`'s card copy stay. No test asserts a current label string (grep of
  `test/`, round 2).
- Minutes (OI-488, d70): options `[30, 45, 60]` plus `90` when `_fitnessExperience == 'advanced'` (the in-form value,
  so the chip follows the experience chips); choosing a non-advanced experience while 90 is selected sets
  `_sessionDuration` to 60. The seed goes through §2.4's rule; `_originalSessionDuration` (`:325`, today `= _sessionDuration`) is
  read separately as the RAW resolved value (`SessionBudget.resolveMinutes(profileValue: profile['session_duration_minutes'])`), so a stored 90 shown as 60 is a change that the first save writes and offers to reschedule (the
  only way a stored 90 is rewritten: no silent write).

### 2.4 Session minutes rule (OI-488, d70)

`SessionBudget.minutesForLevel(Object? stored, Object? level) -> Object?`: when `level != 'advanced'` (exact
lowercase token; null, absent, other strings included) and `resolveMinutes(profileValue: stored) > 60`, return 60;
else return `stored` unchanged (every other input keeps today's resolution, null -> 60, garbage -> 60). Readers:
- `TrainingHistoryAnalyzer.sessionMinutesFromProfile()` returns
  `minutesForLevel(profile['session_duration_minutes'], profile['fitness_experience'])` (generator
  `plan_generator.dart:174 / 286 / 294`, `swap_service.dart:555`, `workout_schedule_read_service.dart:227 / 786`); its
  doc comment (`:218-227`, "returned UNTOUCHED") changes;
- `pro_phase_advance.dart:215` and `simulation_service.dart:615` (their `param` wins, so they would bypass it);
- `SessionBudget.initialSessionDuration(profile)` (Edit Profile seed).
Not capped, by design: the pure pass-through pushes (`sync_service.dart:1449`, `onboarding_provider.dart:959`), the
key list `user_repository.dart:1478`, the completeness provider. The level is the stored profile token, not the
generator's effective level (d70). `repeatMinutesRose` (`workout_schedule_read_service.dart:274 / 885`) compares
resolved minutes that both pass the cap; 90 -> 60 is a fall, so no accessories are appended.

### 2.5 Engine

Untouched. A `strength` / `recompose` value an old build writes is served exactly as today until the heal moves it.

### 2.6 Coach (t306)

- `switchGoal.ts` / `regeneratePlanBlock.ts`: enums -> the three tokens; `switchGoal`'s description (`:31`) names
  Build, Cut and Maintain and says a user asking for strength training is pointed to Build with the Strength focus
  (set in Edit Profile).
- Deno: `_shared/tools/__tests__/switchGoal_test.ts:23-35` ("all 5 valid goals", loops `strength` / `recompose`) and
  `regeneratePlanBlock_test.ts:25-34` (`goal: "recompose"`) become the three plus reject cases for both legacy
  tokens; `deno check --node-modules-dir=none` on `ai-proxy/index.ts`. (`write_claim_detector_test.ts:97` is prose,
  not an enum pin: unchanged.)
- Deploy: ai-proxy only (both tools are bundled there), after the merge, on the founder's explicit go, per the
  edge-function-deploy-rollback skill. Until then the live coach can still propose `strength` / `recompose`; the new
  client shows the refusal sentence in place of a preview (§2.1).
- Server readers left alone, with reasons: `morning-alert/message.ts:119` (a `strength` copy branch: reads a value
  the heal removes), `future-prediction/index.ts` (a `strength` taglines key, same), `weekly-report/index.ts:373-389`
  (no legacy branch), `proactive-coach-promotion/congrats.ts:25` (`gain_strength`, a token that never existed,
  unrelated). No Edge Function writes `primary_goal` (`restore-user-snapshot` only selects).

## 3. Tests (each behavioural unless stated)

- `test/contracts/legacy_goal_heal_behavioral_test.dart`: the pure rule's table (strength x focus null / '' /
  balanced / glutes_legs / chest_shoulders_arms / strength; recompose x every focus; each selectable goal, null and an
  unknown token -> null); the healer on real Hive: one write with goal + focus + targets (calories are Build's /
  Cut's), `carb_grams` in Hive, the recompute kill switch leaves targets out, the heal kill switch writes nothing, a
  second run writes nothing, a null uid / foreign live uid / foreign Hive owner writes nothing, an owner change
  between the call and the lock writes nothing (`patchProfileWith` re-check), a goal saved selectable before the lock
  is left alone; the wrapper runs it only on a succeeded restore, with the captured uid, and with the title-heal switch
  closed.
- `test/contracts/fitness_goals_selectable_test.dart`: `selectableTokens` literally `[build_muscle, lose_fat,
  general_fitness]`, `legacyTargets.keys == tokens - selectableTokens == kLegacyReachableOnlyGoalTokens`, targets
  selectable, labels Build / Cut / Maintain.
- `test/contracts/session_minutes_by_level_test.dart`: `minutesForLevel` table (90 x beginner / intermediate /
  advanced / null / 'Advanced' / garbage; 60, 45, 30, null, '90', 120 with each level); `sessionMinutesFromProfile` on
  real Hive; `pro_phase_advance`'s param path; Edit Profile widget: no 90 chip for intermediate, 90 for advanced,
  Advanced -> Intermediate with 90 selected shows 60 selected.
- Edit Profile widget: the goal dropdown lists exactly Build / Cut / Maintain; a stored `strength` / balanced
  profile opens on Build + Strength focus and saves `build_muscle` + `strength`; a stored `strength` / glutes_legs
  keeps glutes_legs; a stored `recompose` opens on Cut; the change text reads "Strength -> Build", never `null`.
- Coach: the compass form offers three chips with labels; `SwitchGoalDiff` with `new_goal: strength` and
  `RegeneratePlanDiff` with `goal: recompose` show the refusal and never call the planner; the dispatcher refuses
  `strength` / `recompose` with the friendly sentence BEFORE the cache check (no "Open the diff preview first") and
  accepts `lose_fat`.
- Healer through the wrapper: `restoreFromCloudForUser` with the test uid resolver heals a legacy profile (real-Hive
  heal tests set BOTH resolvers, `HiveUserSession.debugCurrentUidResolverForTests` and `guarded_box`'s
  `debugAuthUidResolverForTests`, so an owner case fails at the plan's check and not by a box `StateError`); a failed
  push followed by a restore that merges `strength` back is healed again (the window is that one restore).
- Edit Profile: a stored 90 for an intermediate user, an unrelated-field save: 60 is written and the reschedule offer
  appears.
- Gate lib: `serverGoalEnumProblems` cases (missing, phantom, legacy listed, legacy absent ok); the allowlist test
  unchanged.
- Existing tests that move: `test/plan_engine_v4/session_minutes_resolution_test.dart:66-70` (`initialSessionDuration`
  of 90.0 with no level now 60: the fixture gains `fitness_experience: 'advanced'` and a no-level row asserting 60)
  and `:158-162` (`sessionMinutesFromProfile` "untouched" 75 with no level: same split);
  `ai_proxy_goal_enum_parity_test.dart` (selectable set); the two Deno tool tests. The other 90-minute fixtures pass 90
  as the `param` and are unaffected (round 2 checked `session_set_budget_wiring_test`,
  `swap_exercise_rest_follows_incoming_archetype_test:184-187`, `balanced_week_behavioral_test:898`); the full CI run
  is the check for the rest.
- Mutations (rule 21): focus rule overwrites glutes_legs; recompose -> build; the owner re-check inside the lock
  removed; the targets left out of the patch; call site behind `shouldHealAfterRestore`; `minutesForLevel` keyed
  `== 'beginner'`; the 90-chip condition inverted; the `pro_phase_advance` bypass restored; Check 4 back to `tokens`;
  dispatcher back to `isKnown`; compass back to `tokens`; either diff's refusal removed; the owner check moved after
  the box read.

## 4. Docs

Diagnose `docs/diagnoses/2026-11-16-goal-list-and-minutes-<id>.md`; SoT: `session_duration_minutes` (the level rule,
its readers), new `legacy_goal_heal` (writer the healer, readers every `primary_goal` reader), `goal_training` line
cites if shifted; `docs/naming_conventions.md` (the kill switch `disable_legacy_goal_heal`, `legacy_goal_healed`
event, `patchProfileWith`); nested CLAUDE.md: profile (session minutes row, goal list), core/services (healer in the
migrators list), ai_coach (the goal-enum pitfall row: the selectable set), onboarding (`:120`: legacy tokens no longer
in the coach switch-goal) (`docs/blast_radius.yaml`: the healer and `fitness_goals.dart` take exact platform rules, because the sync engine reaches them; round 4's "`lib/core/services/**` covers it" was wrong, found by CI's `blast_radius_sync_engine_platform_test.dart`), plan_engine (Inputs line: strength is a
legacy value). OI-487 / OI-488 close after the device check (t308); a new OI (minted) tracks deleting the legacy rows
and the engine's `strength` paths once no build that offers Strength remains in use (`upstream_blocked`, reopen when
every tester runs a 3B build: the founder confirms).

## 5. Review log

- Round 1 (2026-11-16, Sonnet, context-blind): not converged, 2 P0 + 6 P1 against the first draft (an alias in
  `FitnessGoals.of` plus deletion of the engine's strength paths). P0-1: `CardioFinisher` takes the RAW goal
  (`plan_generator.dart:375`), so an alias leaves recompose on `hate_cardio`. P0-2: the deletion's test blast radius
  (persona grid 1,010 -> 770, audit 2,304 -> 1,728, ~70 files, `day_floor_off_hashes.json`). P1: the heal had no
  target-recompute mechanism; its call site was coupled to the title-heal switch; raw-token readers; writers not turned
  into steps (chat onboarding, `_mapGoal`); Edit Profile's `_original*` seeds; re-push by old builds. Resolution: keep
  the rows and the engine (old builds still write the values; §1), split selectable from legacy (§2.1), carry the
  recompute in the heal's own write, move the call site out from behind the title-heal switch, seed Edit Profile from
  the healed view with raw originals (§2.3).
- Round 2 (2026-11-16, Sonnet, context-blind, on the round-1 draft): not converged, 7 P1 + 4 P2, no P0; the core
  design held. P1: no owner guard in the healer; an unbounded network await (cloud-first update) inside the restore
  wrapper; a read-then-write window; the Edit Profile change text printing `null` for a legacy original; two
  `session_minutes_resolution_test` cases; the `_mapGoal` arm removal reddening `recompose_goal_targets_test.dart:91`;
  the compass form offering every token. P2: the diff widgets' hard-coded names, the Deno test list,
  `naming_conventions.md`, cites (`carb_grams` is Hive-only; only Home invalidates `userProfileProvider`). Resolution:
  the heal is local-only (no network) and decides and writes under the profile lock with an owner re-check
  (`patchProfileWith`, §2.2); the change text labels through `FitnessGoals`; the compass form and `SwitchGoalDiff`
  use the selectable set and refuse early; `_mapGoal` / `target_weight_check` stay as they are; tests and docs added
  to §3 / §4.
- Round 3 (2026-11-16, Sonnet, context-blind, on the round-2 draft): not converged, 2 P1 + 5 P2, all small; the
  local heal, the lock and the selectable / legacy split held (no deadlock: `_withLock` ops are Hive-only; the overlay
  is complete; the change-text and label sweep match). P1: the owner check read `currentUser` directly, which misses
  the wrapper's test resolver (`_liveUserId`), and `HiveService.userBox` throws on disagreement; `RegeneratePlanDiff`
  had no early refusal. P2: the APPLY button on a refusal; "local only" vs the profile push; the convergence claim
  (the merge recomputes legacy targets; lightweight restores do not heal); `_originalSessionDuration` must be read
  raw; onboarding CLAUDE.md `:120`, blast-radius tier. Resolution: §2.1, §2.2 and §2.3 as now written, §3 / §4 rows
  added.
- Round 4 (2026-11-16, Sonnet, context-blind, on the round-3 draft): CONVERGED, no P0 / P1. The three round-3
  resolutions verified closed (owner check through `_liveUserId`, check-before-box; the `RegeneratePlanDiff` insertion
  point and the dispatcher's guard-before-cache order; the raw `_originalSessionDuration`); no new import cycle
  (`sync_service.dart` already imports both profile services); blast radius covered. P2: `patchProfileWith`'s final
  signature and its mismatch behaviour; the two test resolvers. P3: no blast-radius row needed. Folded in above.
- CI on the first push (2026-11-16): `blast_radius_sync_engine_platform_test.dart` failed: the sync engine now reaches
  `legacy_goal_healer.dart` and, through it, `fitness_goals.dart`, both below platform. Both take exact platform rules
  (the heal runs inside the restore wrapper and decides what the profile push sends; `legacyTargets` is its table) and
  join the test's `_engine` list.
