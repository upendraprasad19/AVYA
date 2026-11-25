---
reviewed_at: 2026-11-24T23:10:00+05:30
staged_against: 7f4fc263
blast_radius: account
reviewer: claude-sonnet-seat-b
lens_set: [L1, L8, L10, L15, L16, L20, writer_reader_drift, guard_without_its_mirror, unawaited_no_error_sink]
findings_count: 5
verdict: accepted
---

```yaml
diagnose_stanza:
  symptom: A guarded provider that serves a hand-written empty value on the '<anon>' token can (a) feed a different value than the real "no data" value to a downstream listener and (b) have its guard neutered or made always-empty with the behavioral test staying green
  concept: auth_hive_owner_agreement
  writers:
    - { file: lib/features/nutrition/providers/nutrition_provider.dart, method: MacroTargetsNotifier.build (const empty map without strategy_index), line: 502 }
    - { file: lib/features/home/providers/home_provider.dart, method: TodayWorkoutNotifier.build (null on anon), line: 586 }
  readers:
    - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: _DietPlanScreenState.initState listenManual(macroTargetsProvider.select(dietStrategyOfTargets)), line: 121 }
    - { file: lib/features/nutrition/providers/diet_plan_provider.dart, method_or_widget: DietPlanNotifier.build (MigratedKey.read swallows the throw), line: 124 }
  hive_key_prefix: null
  hive_key_formula: null
  sync_methods: []
  restore_methods: []
  cloud_table: null
  cloud_columns: [null]
  contract_test_path: test/contracts/signed_out_provider_rebuild_behavioral_test.dart
  ist_handling:
    - { file: lib/features/home/providers/home_provider.dart, line: 931, fn: TodayStepsNotifier.build (istTodayStr, below the guard, unchanged) }
  provider_invalidations: [macroTargetsProvider, dietPlanProvider, todayWorkoutProvider]
  telemetry_op_types:
    success: [none]
    failure: [migrated_key_read_user_box]
  cross_account_guard: true
  forbidden_patterns_checked:
    - { pattern: "a Hive/box read ABOVE the token guard in any of the 23 build() bodies", absent: true }
    - { pattern: "a consumer that WRITES Hive/cloud from the empty value in the sign-out window", absent: true }
  proposed_fix: Keep the 23 guards. Add per-field isEmpty/isSeeded assertions (or a non-seeded "signed in is NOT empty" row) for the seven providers named in findings 2-3; make the Diet plan screen's strategy listener ignore a macroTargets emission while the token is '<anon>'; correct the diagnose sentence that says all 33 throw.
  regression_test_planned: [test/contracts/signed_out_provider_rebuild_behavioral_test.dart]
```

# Seat B review of 7f4fc263 (23 guards, 9 provider files)

Verified first: `git diff e41f824d 7f4fc263 -- lib` adds exactly 23 `if (token == '<anon>')` guards (ai_coach 2, home 10, diet 3, nutrition 2, profile 2, weekly 1, train 3); `grep -rn "a2d9f4:" lib | wc -l` = 33. Baseline `flutter test` of the behavioral file: `+197: All tests passed!`. In every one of the 23 bodies the guard is the first statement after the token watch (no box or repository read above it).

## Findings

### 1. P2 - guard_without_its_mirror / writer_reader_drift - lib/features/nutrition/providers/nutrition_provider.dart:502 (reader lib/features/nutrition/screens/diet_plan_screen.dart:121)

Claim: the empty `MacroTargets` map has no `strategy_index` key. `dietStrategyOfTargets` (lib/core/constants/diet_strategies.dart:55-60) maps an absent key to `kDefaultDietStrategy` = balanced (diet_strategies.dart:39). A PRO user whose effective strategy is Keto / Low carb therefore sees the selected strategy flip to Balanced when the token goes `'<anon>'`, and back when it returns. `DietPlanScreen` registers `ref.listenManual(macroTargetsProvider.select(dietStrategyOfTargets), (_, next) => _onEffectiveStrategy(next))` (diet_plan_screen.dart:121). On the flip `dietPlanNeedsRegeneration` is true (`planEpoch > 0 && planStrategyFor(effective, foodType) != requested`, diet_plan_strategy_state.dart:17-23) so `_generatePlan()` runs inside the sign-out window: it calls `UserRepository.instance.getProfile()` (user_repository.dart:278, a raw `userBox` read) and, if that did not throw, `_generateFreshPlan` builds a plan from the const 2400 kcal / 184 g numbers. Nothing is persisted (a fresh plan is unsaved), but the raw read inside a listener callback can throw into the zone, the crash class this batch is closing, through a door the guard opened (the throw used to come from the errored provider instead). The Diet plan route can stay alive in the Nutrition branch navigator while the user signs out from Profile (the tab skeleton gate, hive_tab_scaffold.dart:98, only covers the tab screens, not pushed routes).
Verification: `grep -n "strategy_index" lib/features/nutrition/providers/nutrition_provider.dart` shows it is added only on the real path (line 524); the guard map at 502-509 has bmr/tdee/calories/protein/carbs/fat only. NOT reproduced at runtime (static trace; I did not run the screen). Pre-existing in kind (before the guard the provider threw), so this is "not made safe", not a regression.
Suggested-fix: in `_onEffectiveStrategy` (and the supplements twin at diet_plan_screen.dart:125) return early when `ref.read(authUserIdTokenProvider) == '<anon>'`; or have the screen's listener select on a value that stays unchanged while the token is `'<anon>'`.
status: fixed: both listeners in diet_plan_screen.dart return early on the '<anon>' token; test 'a2d9f4: the signed-out window ...' (mutant: guard off -> red)

### 2. P2 - test honesty (L8 / mutation) - test/contracts/signed_out_provider_rebuild_behavioral_test.dart:451-457, 449, 326-330, 379-388, 407-411

Claim: a guard that ALWAYS serves the empty value (`if (true || token == '<anon>')`) passes all 197 tests for `todayWorkoutProvider`, `allExercisePRsProvider` and `streakWarningEligibilityProvider` (and the same holds for `workoutStatsProvider`, `graduationStatsProvider`, `dietPlanProvider`, which have an `isEmpty` equal to their signed-in value and no `isSeeded`). `todayWorkoutProvider` has only `listen`/`read` closures (no `isEmpty`, no `isSeeded`, line 451-457); `streakWarningEligibilityProvider` is a control with neither (line 449). Always-null today workout would blank the Home Today card for every user.
Verification: mutant m23 (3 guards turned into `if (true || token == '<anon>')`, `grep -c` = 3) -> `+197: All tests passed!`, 0 red.
Suggested-fix: seed a `schedule_<today>` row and add `isSeeded` (non-null) plus `isEmpty: (v) => v == null` through `read:`; seed a completed workout so `allExercisePRs`/`workoutStats`/`graduationStats` are non-empty signed in; add `isEmpty`/`isSeeded` to the eligibility case (seeded streak + planned today row + hour).
status: fixed: seeds + signed-in assertions for todayWorkout, allExercisePRs, streakWarningEligibility, workoutStats, graduationStats, dietPlan; always-empty mutants all red

### 3. P2 - test honesty - test/contracts/signed_out_provider_rebuild_behavioral_test.dart (`isEmpty` closures)

Claim: five empties can be changed to wrong values with the suite staying green because `isEmpty` checks only a subset of fields. m4: `StreakWarningEligibility` empty `shouldShow: true` (would show the streak banner in the window; `isEmpty` is null for it). m8: `NutritionSummaryData(proteinTarget: 1)` (isEmpty checks calories and calorieTarget only, test line 278-281). m12: `MacroTargets` `'protein': 999` (isEmpty checks calories==2400 and bmr==0, line 334). m14: `WeeklyReportSeries` protein `[0,0,0,9,...]` (isEmpty checks weight and calories only, line 354-357). m18: `UserStatsData(isPro: true)` (isEmpty checks totalWorkouts and primaryGoal, line 247-248; a stale `isPro: true` empty would be the worst one, it leaks a PRO state to a signed-out UI).
Verification: mutation table below (m4, m8, m12, m14, m18, each `grep -c` = 1 and 0 red).
Suggested-fix: compare the whole empty value (`v == const NutritionSummaryData()`-style, or a field-complete predicate) instead of two fields.
status: fixed: every isEmpty checks every field; wrong-empty mutants all red

### 4. P3 - L1 / claim accuracy - lib/features/nutrition/providers/diet_plan_provider.dart:124-130, docs/diagnoses/2026-11-24-signed-out-provider-rebuild-a2d9f4.md (proposed_fix says "33 build() bodies that throw")

Claim: `DietPlanNotifier.build` does not throw without its guard. Its only box access is `UserRepository.getSavedDietPlan()` -> `MigratedKey.read` (migrated_key.dart:32-56), which catches the userBox throw, records non-fatal telemetry `migrated_key_read_user_box`, and falls back to the GLOBAL `configBox['saved_diet_plan']` (the legacy, pre-migration location, so in window C it can serve a plan that is not the signed-in user's). So the guard is useful (no telemetry noise, no legacy fallback in the window) but the "throws" claim is wrong for it and the test cannot see the guard: neutering it reddens nothing.
Verification: mutant m19 (`token == '<anon>' && false`, grep -c 1) -> `+197: All tests passed!`; `sed -n 118,185p diet_plan_provider.dart`; `[MigratedKey.read] userBox isPro threw` lines in the baseline log show the swallow path in other providers.
Suggested-fix: seed `saved_diet_plan` in the legacy `configBox` in the test and assert `{}` in window A/B/C; correct the diagnose count wording ("32 throw, DietPlanNotifier is guarded for the legacy fallback").
status: fixed in the diagnose (wording); dietPlan guard now observable: the test seeds a different legacy plan in configBox, guard-off mutant red

### 5. P3 - completeness tripwire blind spots - test/contracts/signed_out_provider_rebuild_behavioral_test.dart:510-522

Claim: `_kTokenWatchSites` counts only the literal `ref.watch(authUserIdTokenProvider)` (regex has no whitespace tolerance). A NEW token-watching provider in a new or existing file DOES fail it (count map differs), but: (a) a build() that reads a raw box and does not watch the token itself (`contextualPromptsProvider` was one, the case list names it at line 446 with the comment "the token-site count cannot see them") is invisible; (b) a watch written as `ref.watch(\n authUserIdTokenProvider)` or `ref.watch(authUserIdTokenProvider.select(...))` is invisible; (c) removing one watch and adding another in the same file nets zero; (d) the fix for a red tripwire is editing the number, nothing forces a `_Case` to exist.
Verification: `grep -rn "authUserIdTokenProvider" lib --include=*.dart | grep -v "ref.watch(authUserIdTokenProvider)"` lists only `ref.read` / `ref.listen` sites and comments today (body_measurements_provider.dart:118,124, referral_summary_provider.dart:59,110,123,188, service_providers.dart:61 `ref.listen`): none is a Notifier.build, so no live gap now.
Suggested-fix: add a second assertion that every `_kTokenWatchSites` file contributes at least one `_Case` provider name (grep the case names), and allow `\s*` in the regex.
status: fixed: the tripwire counts any mention of authUserIdTokenProvider (multi-line, select, read, listen); the residue is stated in the test

## Mutation results

Backups and sha256 of all nine originals in the scratch dir (`.../scratchpad/seatb/sums.txt`); every mutant was applied via `python3 -I`, proven by `grep -c`, run, then restored by `cp` and `sha256sum -c` (all OK). No run showed a compile error (`grep -c "Compiler message|Failed to compile"` = 0 in every log). Baseline: `+197 All passed`.

| Mutant | Site | applied-grep-count | red count |
|---|---|---|---|
| m1 (a) neuter | TodayWorkoutNotifier (nullable) home_provider.dart | 1 | 6 |
| m2 (b) wrong empty `{'x':1}` instead of null | TodayWorkoutNotifier | 1 | 0 (GAP, finding 2) |
| m3 (a) neuter | StreakWarningEligibilityNotifier (const data class) | 1 | 3 |
| m4 (b) `shouldShow: true` | StreakWarningEligibilityNotifier | 1 | 0 (GAP, finding 3) |
| m5 (c) `healthBox;` read above guard | TodayStepsNotifier | 1 | 3 |
| m6 (a) neuter | CalendarWeekNotifier (list) | 1 | 3 |
| m7 (a) neuter | StreakNotifier | 1 | 3 |
| m8 (b) `NutritionSummaryData(proteinTarget: 1)` | NutritionSummaryNotifier (const class) | 1 | 0 (GAP, finding 3) |
| m9 (a) neuter | CurrentPlanNotifier train_provider.dart | 1 | 9 |
| m10 (b) `{'x': {}}` | workoutStatsProvider (map) | 1 | 3 |
| m11 (a) neuter | graduationStatsProvider | 1 | 3 |
| m12 (b) `'protein': 999` | MacroTargetsNotifier (const map) | 1 | 0 (GAP, finding 3) |
| m13 (b) `floorMl + 1` | waterTargetProvider | 1 | 3 |
| m14 (b) protein `[0,0,0,9,...]` | WeeklyReportDataNotifier | 1 | 0 (GAP, finding 3) |
| m15 (a) neuter | coachInsightProvider | 1 | 3 |
| m16 (a) neuter | contextualPromptsProvider | 1 | 3 |
| m17 (b) `{'x': 1}` | UserProfileNotifier (map) | 1 | 3 |
| m18 (b) `UserStatsData(isPro: true)` | UserStatsNotifier | 1 | 0 (GAP, finding 3) |
| m19 (a) neuter | DietPlanNotifier | 1 | 0 (GAP, finding 4) |
| m20 (a) neuter | dietServingViewProvider | 1 | 3 |
| m21 (a) neuter | dietSupplementsInputsProvider | 1 | 3 |
| m22 (a) neuter | AllExercisePRsNotifier | 1 | 3 |
| m23 always-empty `if (true \|\| ...)` x3 | TodayWorkout + AllExercisePRs + StreakWarning | 3 | 0 (GAP, finding 2) |

Each (a) "neuter" and (c) "moved below a read" mutant that reddens does so only 3 times (one provider x windows A/B/C) because the detection is the throw in the listener; where the build does not throw (m19) nothing is seen. Four nullable/const-data/map/list families are covered: nullable todayWorkout (m1, m2, m23), const class (m3, m4, m8, m18), map (m10, m12, m17), list (m6, m22).

## Q1..Q5 answers

Q1 (consumer side effects). I found no consumer that writes from an empty value in the window. The tab screens (Home, Train, Nutrition, Profile) all return the skeleton on `isSessionTearingDown` = `ref.watch(authUserIdTokenProvider) == '<anon>'` (hive_tab_scaffold.dart:98; train/screens/train/screen.dart:92, home_screen.dart:306), the same token the guards test, so the empty values never reach a tab render. `currentPlanProvider` empty (`const CurrentPlanData()`, hasPlan false, isGenerating false) returns before `_autoGeneratePlan` (train_provider.dart:871 vs 891-921), the only generation path; its consumers are the train screen (gated), `holdStatusProvider`/`weekIdentityProvider` (read-only through the read service) and `daySwapWeekProvider` (family, out of scope; watches only currentPlan and reads `workoutBox` in the rebuild, swap_service.dart:160, so it is the one downstream that may still throw in the window; not measured). `todayWorkoutProvider` null feeds Home's `_buildTodayRow`, where `schedule == null && isPhaseExpired()` would render `PlanExpiredCard`, but that sits below the skeleton gate; both card actions are user taps. Streak 0 / StreakFreeze 0 / StreakWarningEligibility: all consumers are render-only (grep of `streakProvider`, `streakFreezeProvider`, `streakWarningEligibilityProvider`), no decay/reset keyed on them (rollover in day_rollover_service.dart only invalidates). `UserProfile {}`: `updateProfile` writes fields then reads `getProfile()` back (profile_provider.dart:93-96); `recalculateTargets` uses `state` but `recomputeDerivedTargets({})` returns null on incomplete inputs; no `{...state}` merge-back anywhere. `MacroTargets` const numbers are read by Diet plan screen via `ref.read` only on user actions, but its strategy listener is finding 1; nothing persists or pushes them. `waterTarget` floorMl, `WeightHistory []`, `NutritionSummary`, `UserStats` are display-only. One consumer door is real: finding 1.

Q2 (window C wrong data, guard placement). In all 23 diffs the guard is the first statement after `final token = ref.watch(authUserIdTokenProvider)`; no repository call or box read is above it (checked in the diff and by mutant m5, which proves a read above the guard is caught). The early return skips later `ref.watch`es (restoreCompletedTick, userProfile select, macroTargets select, subscription) so while anon the provider depends on the token only; the token flip re-runs `build()` which re-registers every dependency, so no legitimate rebuild is lost. Fields/`onDispose` registered after the guard are simply not registered while anon (none of the 23 sets a `late` field in build). Window C wrong-data cannot happen through the box getters (the stub throws, guarded_box.dart:170-173); the one swallowing reader is `MigratedKey.read`, which falls back to the global `configBox` (finding 4).

Q3 (mirror). Token flips back -> `build()` re-runs with the real data (test asserts `isSeeded` again for 17 providers; the unseeded ones only assert no error). Same user returns: covered by the test's reopen step. Different user: window C rebuilds to the new owner's data on the owner edge; no stored state survives (Notifier states are replaced on rebuild). Kill switch `disable_live_auth_token_read` ON: token comes from the cached `currentUserProvider`, so after an A->B swap it stays `'<anon>'` and the guarded providers (and the tab skeletons) stay empty; that is the same state the token reports to every consumer and the pre-fix behavior was a throw, so not a regression. Types: every empty matches the state type (nullable `Map?` for todayWorkout, `const` for immutable data classes, fresh growable lists for WeightHistory / RecentFoodLogs / AllExercisePRs, `const` lists/maps for CalendarWeek / DietPlan / workoutStats, which are only read; DietPlan already returned `const {}` on its normal path). The one semantic mismatch is the missing `strategy_index` (finding 1).

Q4 (test honesty). All 23 appear in `_cases()` (lines 237-410, 446-456). The ones whose case can detect guard-present vs guard-absent only through the "build threw" listener, with an `isEmpty` that equals the signed-in value or no `isEmpty`: todayWorkout, allExercisePRs, workoutStats, graduationStats, dietPlan, streakWarningEligibility (finding 2/4). The ones with seeds that really differ: biometric, userProfile, userStats, streak, nutritionSummary, weightHistory, recentFoodLogs, todayWater/steps, macroTargets, waterTarget, weeklyReport, currentPlan, dietServingView, dietSupplementsInputs. `isEmpty` only checks a field subset for five of them (finding 3). Tripwire: a new file or a new site in an existing file that spells `ref.watch(authUserIdTokenProvider)` fails it; read/listen/select/multi-line spellings and non-watching raw readers do not (finding 5).

Q5 (mutation). 23 mutants run, table above: 15 reddened (all (a) and (c) mutants on providers whose build throws; all wrong-value mutants whose field is asserted), 8 reddened nothing (m2, m4, m8, m12, m14, m18, m19, m23), each a gap explained by findings 2-4. No compile errors; tree restored and verified.

## Founder triage notes

Triaged by the session coordinator, all five fixed in the next commit. One thing the review left open and the coordinator measured: `daySwapWeekProvider` and `daySwapAllowanceProvider` are sync `Provider.family` builds that DO throw in all three windows (3 of 3 each); both are guarded now (35 guarded builds in all) and covered by the test.

## Tuning entry

- **2026-11-24** - blast-radius account - 5 findings; 0 false_alarm; tuning: for any "serve empty" guard review, require per-provider whole-value `isEmpty` + a non-empty signed-in assertion and run an always-empty (`if (true || ...)`) mutant, since throw-detection alone cannot see wrong or constant empties; and when a diagnose claims "N providers throw", mutate each guard individually (DietPlanNotifier did not throw).
