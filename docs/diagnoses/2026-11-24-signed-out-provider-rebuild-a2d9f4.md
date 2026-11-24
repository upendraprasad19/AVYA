---
bug_id: a2d9f4
date: 2026-11-24
batch: biometric-anon-guard (Crashlytics build 50)
status: fixed
tier: full
blast_radius: account
symptom: |
  Crashlytics, com.icanbefitter.avya build 1.0.0 (50), 2026-11-22: 61 fatal-flagged events from ONE user (a tester switching between two test accounts, sign-out then sign-in, founder's own report): "Bad state: HiveUserSession not opened - cannot wrap user-scoped box "healthBox". Call HiveUserSession.openForUser(userId) after sign-in." Top frames: wrapUserScopedBox (guarded_box.dart:335) <- HiveService.healthBoxGuarded (hive_service.dart:285) <- HiveService.healthBox (hive_service.dart:273) <- BiometricNotifier.build (profile_provider.dart:625) <- Riverpod ProviderScheduler._performRefresh <- _flutterVsync (a frame callback, so the app was in the foreground). The error is recorded as FlutterError, which main.dart:44-48 routes to Crashlytics as FATAL, so a throwing provider build shows as a crash even though the process stays alive.
concept: auth_hive_owner_agreement
sot_registry_entry: auth_hive_owner_agreement
writers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: "signOut -> _teardown: Hive teardown FIRST (HiveUserSession.closeAll), auth.signOut() LAST", line: 1019 }
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: "closeAll / _closeAllLocked: clears the owner and the owner listenable", line: 412 }
  - { file: lib/features/auth/providers/auth_invalidation_provider.dart, method_or_widget: "authUserIdTokenProvider: returns '<anon>' while the live auth uid or the Hive owner is null, or they disagree", line: 48 }
readers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "BiometricNotifier.build: raw HiveService.instance.healthBox (the Crashlytics frame); UserProfileNotifier and UserStatsNotifier build read userBox", line: 637 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "11 build() bodies that read a raw box or a repository over one: TodayWeightLogged, CalendarWeek, Streak, StreakFreeze, NutritionSummary, WeightHistory, RecentFoodLogs, TodaySteps, AllExercisePRs, TodayWorkout, StreakWarningEligibility", line: 1073 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "DailyNutrition / WaterIntake / UrineColor / SavedMeals / WeeklyNutrition / MacroTargets build and waterTargetProvider: raw nutritionBox / healthBox / userBox", line: 426 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "ChatHistoryNotifier.build (raw coachBox), MessageLimitNotifier.build (raw userBox), coachInsightProvider, contextualPromptsProvider (a repository box read)", line: 183 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "TemplatesNotifier, CurrentPlanNotifier, workoutStatsProvider, graduationStatsProvider build: raw workoutBox / userBox", line: 2749 }
  - { file: lib/features/train/providers/day_swap_provider.dart, method_or_widget: "daySwapWeekProvider (weekStates reads the schedule rows) and daySwapAllowanceProvider (DaySwapAllowance.current reads userBox)", line: 109 }
  - { file: lib/features/profile/providers/weekly_report_data_provider.dart, method_or_widget: "WeeklyReportDataNotifier.build: raw healthBox / workoutBox reads", line: 46 }
  - { file: lib/features/nutrition/providers/diet_plan_provider.dart, method_or_widget: "DietPlanNotifier.build, with diet_serving_view_provider.dart and diet_supplements_active_provider.dart: raw userBox reads", line: 126 }
hive_key_prefix: "none changed (reads only: healthBox, nutritionBox, coachBox, userBox and workoutBox keys)"
hive_key_formula: "n/a (no key changes)"
sync_methods: []
restore_methods: []
cloud_table: "none"
cloud_columns: ["none"]
contract_test_path: test/contracts/signed_out_provider_rebuild_behavioral_test.dart
ist_handling: ["unchanged: every date key in the test uses istDateStr(DateTime.now()), the same call the providers use"]
provider_invalidations: ["none added: each guarded provider already watched authUserIdTokenProvider, so the flip of the token back to a real uid re-runs build() (Layer B)"]
telemetry_op_types:
  success: ["none"]
  failure: ["none (the empty return is a normal state, not a failure; guarded_box_null_owner_authenticated already counts the pre-open window)"]
cross_account_guard: "Strengthened, not loosened. The guard returns an EMPTY value whenever the token is '<anon>' (no session, or the auth user and the Hive owner disagree), so a rebuild in the swap window can never read the other account's box. The throw it replaces is the same refusal in loud form."
forbidden_patterns_checked:
  - { pattern: "a null-returning or try/catch-swallowing healthBoxSafe() wrapper around the raw getter (would hide a genuine read-before-openForUser ordering bug that guarded_box.dart:335 is kept loud for)", absent: true }
  - { pattern: "removing or loosening the StateError at guarded_box.dart:335 or the rawBox throw on GuardedBox.empty (write safety for the other ~200 raw-getter call sites)", absent: true }
  - { pattern: "a Hive read in a guarded provider before the token check", absent: true }
proposed_fix: |
  1. Every Notifier / Provider build() that reads a raw user-scoped box (directly or through a repository) takes the token value (`final token = ref.watch(authUserIdTokenProvider)`) and returns its empty value when `token == '<anon>'`, before any box read: 35 guarded bodies in 10 provider files (the two last ones are the `Provider.family` week and allowance providers of the day swap, found by Seat B's downstream question and confirmed by the probe). This is the pattern body_measurements_provider.dart:55 and measurement_prompt_provider.dart:34 already use. The empty value is the one each provider already serves for "no data" (0, false, [], a const data class, null for the nullable-state todayWorkout, '' for the coach insight, the cold-start default for the streak-warning eligibility).
  2. Three sign-out windows, one guard: A (Hive torn down, auth user still set: the empty stub's rawBox throws), B (both gone: guarded_box.dart:335) and C (the auth user and the Hive owner disagree, an account swap: the empty stub again). Each yields '<anon>' from the token provider.
  3. Test seam: `setUpHiveForTests` (and the six test files that open a session by hand) set `debugAuthUidResolverForTests = () => HiveUserSession.currentOwnerFullId`, so a pure-VM test that opens a session is "signed in" to the token provider. It follows the owner, so it never creates a disagreement; the signed-out tests replace it.
  4. Two listeners on the Diet Plan screen (`_onEffectiveStrategy`, `_onSupplementsActive`, `diet_plan_screen.dart`) return early on the `'<anon>'` token: the empty MacroTargets map has no `strategy_index` (so the shown strategy reads Balanced) and the empty supplements inputs read false, and without this a signed-out window regenerates the plan on a user-less read (Seat B finding 1). Seat C refinements: `_healSupplementsState` returns before logging or marking while anonymous; because a select fires only on a CHANGE, a token listener re-decides post-frame when the token returns (an account that is Balanced after the window equals the empty value, so no event would follow); `SwapConfirmSheet.build` returns an empty box on the anonymous token (its `preview` reads the boxes straight). Tests: `test/nutrition/diet_plan_strategy_screen_test.dart` 'a2d9f4: ...' (four), `test/widgets/swap_confirm_sheet_test.dart`.
  Not done, on purpose:
  - The loud StateError at guarded_box.dart:335 and the rawBox throw on GuardedBox.empty stay (they protect every raw-getter call site, ~200 outside a build()).
  - FutureProvider providers (previewPlanProvider, adminDashboardProvider, videoRender): a throw lands in an AsyncError their screens handle. (This line first also named `daySwapAllowanceProvider`; that one is a sync `Provider.family`, throws, and is now guarded. The sweep is `grep -rlE` over provider files that read a user box and do not mention the token: only `sync_state_provider.dart` remains, and it reads the shared configBox only.)
  - The CLOSING GAP is a separate defect, OI-526: `HiveUserSession._closeAllLocked` (hive_user_session.dart:412-425) awaits each box close BEFORE it clears the owner and the listenable, so a rebuild inside that gap still sees the old owner and reads a closed box (`HiveError: Box not found`). The test clears its error list after the sign-out switch for that reason and says so.
  - The kill switch `disable_live_auth_token_read` (the token provider then reads the stored owner only) can leave the token at '<anon>' if the stored owner is null; the guarded providers then serve empty, which is the same state the token already reports to every other consumer.
regression_test_planned: |
  test/contracts/signed_out_provider_rebuild_behavioral_test.dart: real Hive, the real token provider and the real notifiers. A case table of 68 providers (35 guarded, with seeded real data where cheap, plus downstream providers, controls and four nullable-state providers read through typed closures) x 3 windows (A, B, C): seed, build signed in (the real value), sign out in the app's own order (Hive first, auth last), assert NO error reached the listener after the switch and the empty value is served, sign back in as the same user and assert the real value returns. A completeness tripwire compares the per-file count of mentions of `authUserIdTokenProvider` under lib/ (import and comment lines excluded, any spelling) with `_kTokenWatchSites`, so a new token-reading provider fails the test until it is added to the case table or named as a control; its residue (a provider that reads a raw box and never mentions the token) is stated in the test. Every guarded case now has a seed that makes the signed-in value differ from the empty one, and an `isEmpty` that checks every field. 203 tests.
mutation_proof: |
  Rule 21, against the final test (every mutant confirmed APPLIED by grep -c before running):
  - M1 neuter every guard (`if (token == '<anon>' && false) return ...`): 30 of 30 sites applied (first batch) -> 102 red.
  - M2 invert every guard (`token != '<anon>'`): applied -> 102 red.
  - M3 wrong empty values across the guarded set: 30 red.
  - M4 guard moved BELOW the box read: 3 red.
  - M5 (the last two guards) `'<anon>'` replaced by `'<never>'` in streakWarningEligibility and contextualPrompts: 2 of 2 applied -> 6 red (3 windows each), 191 green.
  - M6 (after Seat B, which found 8 of its 23 mutants reddened nothing): always-empty guards (`if (true)`) on todayWorkout, streakWarningEligibility, allExercisePRs, workoutStats, graduationStats: 5 of 5 applied -> red each; wrong empties (todayWorkout `{}`, shouldShow true, proteinTarget 1, macro protein 999, weekly-report protein 1, userStats isPro true): 6 of 6 applied -> red each; dietPlan guard off: red once the test seeds a DIFFERENT legacy plan in the shared configBox (the user-box read falls back to it while signed out, MigratedKey.read).
  - M7 day-swap guards off: 2 of 2 applied -> 3 red each; the Diet Plan screen listener guard off: 1 applied -> 1 red.
  Probe before the fix (same scenario, no guard): the first ten providers threw in both windows (A, B); the class sweep after the B-pass found 22 more that throw in A, B and C, and Seat B's downstream question found 2 more (`daySwapWeekProvider`, `daySwapAllowanceProvider`).
  Files restored from a backup by cp and checked with sha256sum after each mutant.
impact_analysis: |
  Client only. While a session is closed or switching, the 35 guarded builds serve their empty value instead of throwing; when the token returns to the new uid they rebuild with that account's data (the same liveness path the tabs' isSessionTearingDown skeleton uses). Side effects of an empty serve, read per consumer: `currentPlanProvider` serves an empty plan (its auto-generate path runs only on a real session, not on the guarded return); the streak, freeze and eligibility providers write nothing from build(); the coach providers serve [] / 0 / ''. No schema, Edge Function, Hive key or cloud change. Existing tests: files that name these providers and open a Hive session were run locally; 6 files (19 tests) went red on the first guard because they open a session without an auth seam (the token stayed '<anon>') and were fixed with the same owner-following seam. The other `setUpHiveForTests` users and every test that pumps a screen are left to the full CI suite.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "35 build() guards in 10 provider files plus 2 screen-listener guards; flutter analyze --no-fatal-infos (see the batch commit for the whole-project run)." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Behavioral test uses real Hive boxes via setUpHiveForTests, closeAll and openForUser; seeded data returns after the re-open." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "None." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: verified, evidence: "Crashlytics issue read from the founder's paste of the issue's stack trace (the app never calls FirebaseCrashlytics.log or setCustomKey, so Keys and Logs are empty by construction)." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No server call is on this path." }
recurrence: "Recurrence of the 'user-scoped Hive read while no session is open' class: a7c3f8 (coach backfill at boot), b8e3f1 / a7f2e1 (OBS-6: the owner-null serve-empty fix and the token source) and b3f9e7 (terms write before openForUser). Those fixed the box getter's behaviour and one stuck-skeleton path; none touched a Notifier.build that reads the RAW getter, whose `rawBox` throws on the empty stub. The known-good shape is the '<anon>' early return of body_measurements_provider.dart:55, applied here."
related_bugs: [b8e3f1, a7f2e1, c4055a, a7c3f8, b3f9e7]
---

# a2d9f4 - provider rebuild reads a raw user box while signed out

## What happened
A tester signed out of one account and into another on build 50. Signing out tears Hive down first and the auth user last (`auth_provider.dart` signOut). Every provider that watches `authUserIdTokenProvider` is rebuilt when that token flips. `BiometricNotifier.build` then read `HiveService.instance.healthBox`, which is `GuardedBox.rawBox`: it throws on the empty stub (Hive closed, auth user still set) and at `guarded_box.dart:335` (both gone). Riverpod reported the throw as a FlutterError, which `main.dart` records as fatal: 61 times for one user.

## What the measurement added
The Crashlytics issue named one provider, but a probe on real Hive showed ten with the same shape (a `build()` that reads a raw user-scoped box and ignores the token it watches) throw in the sign-out windows. The B-pass (Seat A) then showed the class was much larger: my first sweep grepped `*provider*.dart` for the literal `HiveService.instance.<box>` and missed repository reads, `hive.<box>` aliases and providers that read only through another provider. A probe over every provider in the tree found 33 build() bodies that throw in window A, B or C, and the review rounds added 2 more (the day-swap family providers), 35 in all. All 35 are fixed in this batch (no deferrals, CLAUDE.md 4.2); the founder chose "fix all in this PR". Only Biometric reached the Crashlytics trending list.

## The fix
Each guarded build returns its empty value on the `'<anon>'` token and rebuilds with data when the token flips back. See `proposed_fix` for what is left alone and why.

## Not established
- Which rebuild trigger fired the 61 events. The founder's account-switch fits window A or B; the day-rollover invalidation and the Profile retry also reach the same build(). The fix does not depend on it.
- Why only `BiometricNotifier` shows in Crashlytics. The Home, Nutrition, Train and Coach tabs gate on `isSessionTearingDown`, which may drop their listeners before the rebuild, while the Profile tab's watcher stays mounted; not measured.
- The `setUpHiveForTests` users and screen-pumping tests that were not run locally; the full suite on CI decides.
- The closing gap (OI-526): reproduced once as a flaky `HiveError` in the test, cause read from `_closeAllLocked`, not fixed here.
- Seat B findings and their handling (review file `docs/reviews/7f4fc263-review.md`): P2 strategy listener fixed (above); P2 test gaps fixed (seeds and full-field `isEmpty`); P3 `DietPlanNotifier` does not throw without its guard (`MigratedKey.read` swallows and falls back to the shared configBox), so it is guarded for the wrong-data reason (window C or a legacy plan served to the wrong account), and the earlier '33 throw' wording was too strong for it; P3 tripwire widened. Not measured by Seat B and measured here: `daySwapWeekProvider` (it throws, fixed).
- Seat C (delta review of b48f07cf, `docs/reviews/b48f07cf-review.md`, no P0/P1, four findings, all fixed): unpinned supplements listener; unpinned guard placement; the swallowed edge when the real value equals the empty one plus a false heal event; `SwapConfirmSheet` reading raw boxes while signed out. Mutants on the fix: 6 of 6 red (supplements guard, strategy guard, heal guard, token-return listener, guard removed from the placement spot, swap-confirm guard).
