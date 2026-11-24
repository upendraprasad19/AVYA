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
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "BiometricNotifier.build: raw HiveService.instance.healthBox (the Crashlytics frame)", line: 624 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "TodayWeightLoggedNotifier.build: raw healthBox", line: 1027 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "DailyNutritionNotifier / WaterIntakeNotifier / UrineColorNotifier / SavedMealsNotifier / WeeklyNutritionNotifier build: raw nutritionBox / healthBox", line: 420 }
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "ChatHistoryNotifier.build (raw coachBox) and MessageLimitNotifier.build (raw userBox)", line: 178 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "TemplatesNotifier.build: raw workoutBox", line: 2736 }
hive_key_prefix: "none changed (reads only: healthBox weight_/water_ml_/urine_color_/step_log, nutritionBox nlog_/meal_, coachBox rows, userBox msg_count_, workoutBox tmpl_)"
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
  1. Each of the ten Notifier.build bodies that read a raw user-scoped box now takes the token value (`final token = ref.watch(authUserIdTokenProvider)`) and returns its empty value when `token == '<anon>'`, before any box read. This is the pattern body_measurements_provider.dart:55 and measurement_prompt_provider.dart:34 already use. Empty values: BiometricData(), false, DailyNutritionData(), 0, -1, [], WeeklyNutritionData(), [], 0, [].
  2. Window A (Hive torn down, auth user still set) and window B (both gone) both yield '<anon>' (owner null), and so does an owner/auth disagreement, which are exactly the states where the raw getter throws (rawBox on the empty stub, or guarded_box.dart:335).
  3. Test seam: `setUpHiveForTests` (and the six test files that open a session by hand) now set `debugAuthUidResolverForTests = () => HiveUserSession.currentOwnerFullId`, so a pure-VM test that opens a session is "signed in" to the token provider. It follows the owner, so it never creates a disagreement; the signed-out tests replace it.
  Not done, on purpose: previewPlanProvider (a FutureProvider: a throw lands in an AsyncError the screen handles, it is never an uncaught build error); the other 216 raw-getter reads in lib/ (226 in total, 10 are the guarded build() bodies; the rest are methods that run on a user action, plus previewPlanProvider above).
regression_test_planned: |
  test/contracts/signed_out_provider_rebuild_behavioral_test.dart: real Hive, the real token provider and the real notifiers, for each of the 10 providers x 2 windows (A: Hive closed with the auth user still set; B: both gone): seed real data, build signed in (the real value), sign out in the app's own order (Hive first, auth last), assert NO error reached the listener and the empty value is served, sign back in as the same user and assert the real value returns. Plus a seam test (a signed-in session has a real token). 21 tests.
mutation_proof: |
  Rule 21, run once against the final test (every mutant confirmed APPLIED by grep -c before running):
  - M1 neuter every guard (`if (token == '<anon>' && false) return ...`): 10 of 10 sites applied -> 20 red, 1 green (the seam test).
  - M2 invert every guard (`token != '<anon>'`): 10 of 10 applied -> 20 red, 1 green.
  - M3 wrong empty values (water and message limit 0 -> 1, urine -1 -> 0, weight false -> true, biometric isSyncEnabled true): 5 providers applied -> 10 red, 11 green.
  Probe before the fix (same scenario, no guard): all 10 providers threw in both windows and delivered the error to the listener (measured, not assumed).
  Files restored from a backup by cp and diffed (0 differences) after each mutant.
impact_analysis: |
  Client only. While a session is closed or switching, ten providers now serve their empty value instead of throwing; when the token returns to the new uid they rebuild with that account's data (the same liveness path the tabs' isSessionTearingDown skeleton uses). No schema, Edge Function, Hive key or cloud change. Existing tests: 35 files that name these providers were run locally; 6 of them (19 tests) went red because they open a Hive session without an auth seam (the token stayed '<anon>'), and were fixed by adding the same owner-following seam. The other 166 files that use setUpHiveForTests, and every test that pumps a screen watching these providers, are left to the full CI suite.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "10 build() guards in 5 provider files; flutter analyze --no-fatal-infos on the whole project: 0 warnings, 0 errors (460 existing infos)." }
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
The Crashlytics issue named one provider, but a probe on real Hive showed ten providers with the same shape (a `build()` that reads a raw user-scoped box and ignores the token it watches) all throw in both windows. Only Biometric reached Crashlytics in the trending list; whether the others are in the dashboard is not known. They are fixed in the same batch (no deferrals, CLAUDE.md 4.2).

## The fix
Each of the ten returns its empty value on the `'<anon>'` token and rebuilds with data when the token flips back. See `proposed_fix` for the reasons the loud throw and the raw getters are left as they are.

## Not established
- Which rebuild trigger fired the 61 events. The founder's account-switch fits window A or B; the day-rollover invalidation and the Profile retry also reach the same build(). The fix does not depend on it.
- Why only `BiometricNotifier` shows in Crashlytics. The Home, Nutrition, Train and Coach tabs gate on `isSessionTearingDown`, which may drop their listeners before the rebuild, while the Profile tab's watcher stays mounted; not measured.
- The 166 other `setUpHiveForTests` users and screen-pumping tests were not run locally; the full suite on CI decides.
