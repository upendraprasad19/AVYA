---
bug_id: a1f9c4
date: 2026-06-26
batch: boot-onboarding-hive-first
status: fixed
blast_radius: platform
symptom: >
  Live web E2E (test6@gmail.com, fresh signup, Unit G walk). Two stuck-screen
  hangs with no error and no escape, both on the critical boot/onboarding path:
  (1) the onboarding Plan screen's REPORT FOR DUTY spinner span forever during a
  fresh-signup sync flood (the DB hit statement-timeout 57014 on the ~28
  scheduled_workouts upserts + the snapshot EF hit WORKER_RESOURCE_LIMIT 546 on
  the free tier); (2) after a reload, the SplashScreen sat on the AVYA seal
  forever and never reached Home (reproduced deterministically on a single clean
  tab with a calm backend, once the local web session was wedged).
concept: hive_first_boot_onboarding_no_blocking_cloud_await
sot_registry_entry: onboarding_completed_at (writer timing annotated — the cloud stamp is now fire-and-forget via _syncOnboardingAndPostActions; recovery via RestoringScreen Plan-A self-heal)
writers: >
  lib/features/auth/screens/splash_screen.dart (_initAndNavigate / _runDeferredInit —
  now bounds the deferred init with a 12s timeout, kill-switch
  disable_splash_init_timeout); lib/features/onboarding/providers/onboarding_provider.dart
  (completeOnboarding — now navigates after the LOCAL writes and runs the cloud
  chain via the new unawaited _syncOnboardingAndPostActions, kill-switch
  disable_onboarding_async_sync).
readers: >
  The user (the rendered route). splash _navigateNext reads SupabaseService.isAuthenticated
  (false on a timed-out init → /sign-in, the safe degrade); the plan_screen REPORT
  FOR DUTY handler awaits completeOnboarding (now returns as soon as the LOCAL plan
  is durable). The cloud rows (user_profile, scheduled_workouts, referral_trial)
  catch up in the background; the pending_onboarding_sync flag + bootstrap replay
  backstop a missed sync.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: ["SyncService.syncWorkoutData", "SyncService.pushSnapshot", "_syncOnboardingToSupabase"]
restore_methods: []
cloud_table: user_profile
cloud_columns: ["onboarding_completed_at"]
contract_test_path: test/contracts/boot_onboarding_hive_first_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["onboarding_sync", "onboarding_sync_retry"]
cross_account_guard: false
forbidden_patterns_checked:
  - "An awaited cloud/IO call on the critical boot or onboarding navigation path with no timeout — splash _runDeferredInit awaited Supabase.initialize() with no bound; completeOnboarding awaited _syncOnboardingToSupabase + redeem-referral + verifyFromServer before returning. A HANG (not a THROW) in any of them stranded the user on a dead screen with no escape (the .catchError / 10s-retry only fire on a throw). FIXED — both now degrade offline-first."
proposed_fix: >
  Make boot + onboarding navigation truly Hive-first (rule 1). (a) Splash:
  bound _runDeferredInit with a 12s timeout in _initAndNavigate so _navigateNext
  always fires; a timed-out init reads isAuthenticated=false → /sign-in (a re-auth
  beats an infinite splash; only fires on a real >12s stall — a warm init is <2s).
  (b) Onboarding: after the local writes (profile, plan, progress, onboarded-stamp),
  capture the referral stash synchronously, then run the cloud chain (sync →
  schedule push → snapshot → referral redeem → verify) via the new unawaited
  _syncOnboardingAndPostActions, PRESERVING the sync-before-referral order; return
  phase immediately. Both behind kill-switches (disable_splash_init_timeout /
  disable_onboarding_async_sync) per §4.6.
regression_test_planned: >
  test/contracts/boot_onboarding_hive_first_test.dart — comment-stripped source
  structure contract (per feedback_source_grep_strip_comments_first): asserts
  (1) splash _initAndNavigate bounds the init via `.timeout(`; (2) completeOnboarding
  fires the cloud chain through `unawaited(` `_syncOnboardingAndPostActions` and does
  NOT `await` the redeem-referral / verifyFromServer calls in its main body (they
  live only in the background method). FAILS on the pre-fix code (cloud awaited in
  the critical path). Behavioral proof: the founder's live signup re-walk — REPORT
  FOR DUTY navigates instantly and the splash reaches Home even on a slow backend.
  (A fakeAsync behavioral test that injects a hanging Supabase requires a service
  fake / DI seam — tracked as a follow-up; the structural test + kill-switch +
  live re-verify are the bar for this fix.)
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "splash_screen._initAndNavigate bounds _runDeferredInit at 12s; onboarding completeOnboarding fires the cloud chain unawaited via _syncOnboardingAndPostActions. flutter analyze clean on both files." }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "the LOCAL writes (saveProfile/generateAndSchedule/saveProgress/setOnboarded) stay awaited + ordered BEFORE navigation — onboarding completion is durable locally before the user leaves the Plan screen, so a reload self-heals (onboarding_completed_at present in Hive)." }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "the cloud user_profile / scheduled_workouts / referral_trial rows still land — just in the background, preserving the sync-before-referral order; the pending_onboarding_sync flag + bootstrap replay backstop a missed sync. Live: test6's referral_trial + amar both-party grant landed (the redeem path is unchanged, only its timing moved off the critical path)." }
impact_analysis: >
  Platform blast radius (the boot + onboarding entry path every user hits). The
  bug class is "an awaited cloud/IO call on the critical navigation path with no
  timeout" — a slow/cold/stalled backend (free-tier statement timeouts, EF cold
  starts, bad client network) strands the user on the splash seal or the REPORT
  FOR DUTY spinner forever, with no error and no escape. Surfaced live on a fresh
  free-tier signup. Same class as the onboarding/Home not-quite-Hive-first gap.
  Fix is offline-first degradation: do the durable local work, navigate, let the
  cloud catch up in the background. Kill-switches restore the old blocking paths
  if a regression surfaces. related: the e2e-fullcharter evidence doc (this is the
  Unit G live-walk finding).
---

# Boot + onboarding hang on an un-timed cloud await (a1f9c4)

## What happened
Two stuck screens on a fresh-signup web walk, both with no error + no escape:
1. **REPORT FOR DUTY spinner forever.** `OnboardingNotifier.completeOnboarding`
   did its local writes, then `await`ed three cloud calls in the critical path —
   `_syncOnboardingToSupabase` (`:491`), `redeem-referral` (`:557`),
   `verifyFromServer` (`:563`) — before returning the phase the Plan screen waits
   on. During the fresh-signup sync flood the DB hit `statement timeout (57014)`
   on the ~28 `scheduled_workouts` upserts and the snapshot EF hit
   `WORKER_RESOURCE_LIMIT (546)`; the awaited cloud call never resolved AND never
   threw, so the spinner never cleared (the 10s retry only fires on a *throw*).
2. **Splash seal forever.** `SplashScreen._initAndNavigate` only calls
   `_navigateNext()` after `_runDeferredInit()` completes, and that `await`s
   `SupabaseService.initialize()` (→ `Supabase.initialize()`) with no timeout.
   When it stalled (wedged web session / cold backend), the splash never advanced —
   and the `.catchError` only catches a throw, not a hang.

## Root cause (the class)
An **awaited cloud/IO call on the critical boot or onboarding navigation path,
with no timeout**. A *hang* (distinct from a *throw*) has no handler → the user
is stranded on a dead screen. This is the boot/onboarding analogue of the
not-truly-Hive-first pattern: the LOCAL state is durable, but navigation blocks
on the network.

## Fix
- **Splash** (`splash_screen.dart`): bound `_runDeferredInit()` with a 12s
  `.timeout` in `_initAndNavigate`, so `_navigateNext()` always runs. A timed-out
  init → `isAuthenticated == false` → `/sign-in` (a re-auth beats an infinite
  splash; only fires on a genuine >12s stall). Kill-switch
  `disable_splash_init_timeout`.
- **Onboarding** (`onboarding_provider.dart`): after the local writes, capture
  the referral stash synchronously, then run the whole cloud chain via the new
  `unawaited` `_syncOnboardingAndPostActions` (preserving sync-before-referral
  order) and `return phase` immediately. Kill-switch `disable_onboarding_async_sync`.

## Verification
- `flutter analyze` clean on both files.
- `test/contracts/boot_onboarding_hive_first_test.dart` (comment-stripped source
  contract).
- Live: founder re-walks the signup — REPORT FOR DUTY navigates instantly, the
  splash reaches Home even on a slow backend. test6's referral grant (both-party)
  still landed (redeem path unchanged; only its timing moved off the critical path).

## See also
- `lib/features/auth/screens/splash_screen.dart` (`_initAndNavigate`)
- `lib/features/onboarding/providers/onboarding_provider.dart` (`completeOnboarding` / `_syncOnboardingAndPostActions`)
- `docs/reviews/e2e-fullcharter-2026-06-21-evidence.md` (the Unit G live-walk finding)
- Companion infra finding: the fresh-signup sync burst overwhelms the free-tier DB (statement timeouts) — batch/stagger the schedule upserts and/or Supabase Pro (tracked separately).
