---
branch: fix-boot-onboarding-hive-first
review_type: B-pass (adversarial)
reviewer: context-blind
date: 2026-06-26
review_rounds: 1
verdict: converged
bpass: accepted
---

# B-Pass Review — fix-boot-onboarding-hive-first

## Changed files

- `lib/features/auth/screens/splash_screen.dart` — 12-second `Future.timeout()` wrapping `_runDeferredInit()`; kill-switch `disable_splash_init_timeout`.
- `lib/features/onboarding/providers/onboarding_provider.dart` — `completeOnboarding` now fires cloud chain via `unawaited(_syncOnboardingAndPostActions(...))` after all local writes complete; kill-switch `disable_onboarding_async_sync`.

Diagnose-doc: `docs/diagnoses/2026-06-26-boot-onboarding-cloud-await-hang-a1f9c4.md`

---

## Lens 1 — Referral ordering (sync before redeem)

**What was checked:**
- Full body of `_syncOnboardingAndPostActions` (lines 553–617, `onboarding_provider.dart`).
- Ordering of `_syncOnboardingToSupabase(profile)` relative to the `redeem-referral` callFunction block.
- Error path when `_syncOnboardingToSupabase` throws.

**Happy path:** `await _syncOnboardingToSupabase(profile)` is the first statement inside `_syncOnboardingAndPostActions`, and it is `await`-ed. The `redeem-referral` callFunction is after it (lines ~590–614), also `await`-ed, and conditional on `referralCode.isNotEmpty`. Ordering is preserved. CLEAN.

**Sync-throw path:** On sync failure the catch block logs and schedules a 10-second retry, then falls through. Execution continues to the `unawaited(syncWorkoutData())` / `unawaited(pushSnapshot())` / `_generatePrediction()` calls and then to the referral block. The `public.users` row may not exist yet, so the referral EF will likely fail with a foreign-key or RLS error. However:

1. This was IDENTICAL behavior in the old synchronous code — same try/catch structure, same fall-through. Not a regression introduced by this diff.
2. The referral EF failure is non-fatal (caught inside `callFunction` and logged).
3. `pending_onboarding_sync` flag is set BEFORE the unawaited call, so a subsequent restore path can retry.

**Verdict:** FALSE ALARM (unchanged behavior from old code). No new ordering bug.

---

## Lens 2 — ref-after-dispose

**What was checked:**
- Provider declaration at lines 789–791: `NotifierProvider<OnboardingNotifier, OnboardingState>(OnboardingNotifier.new)` — NOT autoDispose. Provider is retained for app lifetime.
- All `ref` usages in the file: lines 186 (`build()`), 503 (`ref.read(referralCodeStashProvider)`), 506 (`ref.read(referralCodeStashProvider.notifier).clear()`). None inside `_syncOnboardingAndPostActions`.
- `_syncOnboardingAndPostActions` signature and body: uses only `SyncService.instance`, `SupabaseService.instance`, `StatSnapshotService.instance`, `SubscriptionService.instance`, `MigratedKey`, `AiService.instance` — ALL singletons. Zero `ref` calls.
- `_generatePrediction(profile)` (line 648): `void` async function, uses only `AiService.instance` and `MigratedKey`. No `ref`.
- `referralCodeStashProvider` declaration: `NotifierProvider<ReferralCodeStashNotifier, String>` — NOT autoDispose, explicitly marked AUTH_INVALIDATION_EXEMPT in its file.

**Stash capture timing:** `ref.read(referralCodeStashProvider)` and `ref.read(referralCodeStashProvider.notifier).clear()` both execute synchronously BEFORE the `unawaited(cloudCatchUp...)` call (lines 503–510 precede line 519). The stash value is captured into a local `String referralCode` variable on line 503 and passed directly to `_syncOnboardingAndPostActions`. The unawaited method holds a plain Dart String — no provider reference.

**Verdict:** CLEAN. No ref-after-dispose risk. Provider is retained; background method is ref-free.

---

## Lens 3 — Splash mis-route on 12s timeout

**What was checked:**
- `_navigateNext()` at lines 289–305: reads `SupabaseService.instance.isAuthenticated`.
- `SupabaseService.isAuthenticated` at lines 96–99: `if (!_initialized) return false; return currentUser != null;` — `_initialized` is only set to `true` inside `_doInitialize()` after `Supabase.initialize(...)` completes.
- On a 12s timeout, `_initialized` stays `false` → `isAuthenticated` returns `false` → `_navigateNext` routes to `/sign-in`.
- Warm init measured at <2s in practice; 12s covers realistic cold-start + network stall; the diff's PR description explicitly frames this as "intentional degradation for offline-first boot."
- State-loss check: by the time `_initAndNavigate` is running, Hive boxes are already open and `completeOnboarding` writes (if any) have already landed locally. A timeout routes the user to `/sign-in` where re-auth triggers the standard restoring flow which re-reads local Hive. No local state is lost.

**Edge case: already-authenticated user on a slow network.** If Supabase init stalls >12s (e.g., captive portal) and the user HAD a valid session token, `_initialized=false` → `isAuthenticated=false` → routes to `/sign-in` instead of `/restoring`. This means a returning user is asked to re-authenticate rather than hitting the restore screen. This is a UX degradation, not data loss — the Hive data is intact and will reload after sign-in. This is the stated intent of the "offline-first boot" design: prefer a deterministic sign-in prompt over an infinite hang.

**Verdict:** CLEAN (by design). The mis-route is intentional. Severity is at most a UX design note, not a bug.

---

## Lens 4 — Unawaited error sinks

**What was checked:**
- Main unawaited call at lines 518–521:
  ```dart
  unawaited(cloudCatchUp.catchError((Object e, StackTrace s) {
    debugPrint('[Onboarding] background cloud catch-up error: $e');
  }));
  ```
  This is properly sunk. The `.catchError` is chained BEFORE `unawaited()` wraps it. CLEAN.

- `Future.delayed` at line 567 inside `_syncOnboardingAndPostActions`:
  ```dart
  Future.delayed(const Duration(seconds: 10), () async {
    try { ... } catch (e) { ... }
  });
  ```
  The returned future handle is discarded — no `unawaited()` wrapper. The inner closure has a full try/catch that absorbs all exceptions, so this cannot cause an unhandled async exception. The lint warning (`unawaited_futures`) is generated, but the runtime behavior is safe.

  **Is this new?** This bare `Future.delayed` was present in the OLD code (pre-diff). The diff's change to `completeOnboarding` moved the CALL SITE from the awaited critical path to an unawaited background method, but did NOT introduce this bare future — it was already there and already had the inner try/catch.

**Finding P2 (non-regression, pre-existing lint):** `onboarding_provider.dart` line ~567 — bare `Future.delayed(...)` with no `unawaited()` wrapper. Functionally safe (inner try/catch). Lint: `unawaited_futures`. Pre-existing in old code; not introduced by this diff.

**Suggested fix (optional, not blocking):**
```dart
unawaited(Future.delayed(const Duration(seconds: 10), () async {
  try { ... } catch (e) { ... }
}));
```

---

## Lens 5 — Kill-switch semantics

**What was checked:**
- `disable_splash_init_timeout` at `splash_screen.dart`:
  ```dart
  final timeoutDisabled = HiveService.instance.configBox
          .get('disable_splash_init_timeout') == true;
  if (!timeoutDisabled) {
    guardedInit = guardedInit.timeout(...);
  }
  ```
  Default: flag absent → `get()` returns `null` → `null == true` is `false` → `timeoutDisabled = false` → timeout IS applied → fix is active. Set flag to `true` → no timeout → old blocking behavior. Correct semantics.

- `disable_onboarding_async_sync` at `onboarding_provider.dart`:
  ```dart
  if (HiveService.instance.configBox
          .get('disable_onboarding_async_sync') == true) {
    await cloudCatchUp; // old blocking behavior
  } else {
    unawaited(cloudCatchUp.catchError(...)); // new async behavior
  }
  ```
  Default: flag absent → `null == true` is `false` → goes to `else` → unawaited → fix is active. Set flag to `true` → `await` → old blocking behavior. Correct semantics.

Both switches default to fix-active. Both revert to old behavior when set to `true`. Both read from `HiveService.instance.configBox` which is open before `runApp()`.

**Verdict:** CLEAN.

---

## Lens 6 — completeOnboarding contract

**What was checked:**
- Local write ordering (lines 470–501): all Hive writes (`MigratedKey.write`, `userBox.put`, etc.) complete before the cloud chain is started. `pending_onboarding_sync` is written at line 498, BEFORE the `cloudCatchUp` future is created at line 511.
- `state = state.copyWith(isCompleting: false, lastComputedTargets: targets)` at line 523 — same position as in old code, after `unawaited(...)` or `await cloudCatchUp`.
- `return phase` at line 524 — same return point and same variable as old code.
- `isCompleting` guard: set to `true` at line 423 (same as old code), cleared at line 523 (same position). No state change in between is skipped.
- `pending_onboarding_sync` semantics: written `true` before cloud call (line 498), cleared inside `_syncOnboardingAndPostActions` on success (line 561 via `MigratedKey.write('pending_onboarding_sync', false)`). If the unawaited chain is interrupted (app kill), the flag stays `true` → a retry path on next launch can catch it. This matches the stated design.

**Verdict:** CLEAN. Contract preserved. Local-first writes unchanged. Return value and state transition identical to old code.

---

## Summary

| Lens | Finding | Severity |
|------|---------|---------|
| 1 — Referral ordering | Sync is awaited before referral in background method. Sync-throw → referral still fires, same as old code. | FALSE ALARM |
| 2 — ref-after-dispose | Provider not autoDispose; background method is ref-free; stash captured to local String before unawaited. | CLEAN |
| 3 — Splash mis-route | Timeout routes returning user to /sign-in instead of /restoring — intentional degradation by design. | DESIGN NOTE (not a bug) |
| 4 — Unawaited error sinks | New unawaited has `.catchError`. Bare `Future.delayed` at line ~567 is pre-existing, inner try/catch makes it safe. | P2 (pre-existing, non-regression) |
| 5 — Kill-switches | Both default to fix-active. Both correctly revert to old behavior on `== true`. | CLEAN |
| 6 — completeOnboarding contract | Local writes, state transition, return value, `pending_onboarding_sync` semantics all unchanged. | CLEAN |

**Verdict: bpass: accepted**

One P2 (bare `Future.delayed` lint issue at `onboarding_provider.dart:~567`) — pre-existing, not introduced by this diff, functionally safe due to inner try/catch. No P0 or P1 findings. The branch is safe to proceed.
