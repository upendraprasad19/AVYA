---
branch: fix-boot-onboarding-hive-first
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/boot-onboarding-hive-first-bpass.md
hermes: not_required
reviewed_at: 2026-06-26
diagnose: a1f9c4
---

# Plan review — fix-boot-onboarding-hive-first (a1f9c4)

## Scope
Boot + onboarding made truly Hive-first (rule 1): no un-timed cloud/IO `await` on
the critical navigation path.
- **Splash** (`splash_screen.dart`): bound `_runDeferredInit` with a 12s `.timeout`
  in `_initAndNavigate` so the AVYA seal can never hang forever. Kill-switch
  `disable_splash_init_timeout`.
- **Onboarding** (`onboarding_provider.dart`): `completeOnboarding` navigates after
  the LOCAL writes and fires the cloud chain (sync → schedule push → snapshot →
  referral redeem → verify) via the unawaited `_syncOnboardingAndPostActions`,
  preserving the sync-before-referral order. Kill-switch
  `disable_onboarding_async_sync`.

Both kill-switched per §4.6. Diagnose `a1f9c4`. Surfaced live in the Unit G
fresh-signup walk (REPORT FOR DUTY spinner + splash seal both hung forever during
a free-tier sync flood / wedged web session).

## Review round 1 — B-pass (context-blind, Sonnet)
`docs/reviews/boot-onboarding-hive-first-bpass.md` — **ACCEPTED, 0 P0/P1.**
Lenses clean: referral ordering preserved (sync awaited before redeem); the
background method uses zero `ref` (onboardingProvider is NOT autoDispose; the
referral code is captured synchronously before the unawaited fire); the splash
timeout → `/sign-in` is intended degradation, no data loss; both kill-switches
default fix-active and revert correctly; `completeOnboarding` returns the same
phase + sets state at the same points. One P2 (a bare `Future.delayed` not
`unawaited`-wrapped) → **FIXED** in this commit.

## Review round 2 — ground-truth design (context-blind, Opus)
`docs/reviews/boot-onboarding-hive-first-groundtruth.md` — **CORRECT + substantially
COMPLETE, 0 P0/P1.** Independently verified against the actual code (not the
author's prose): the 12s timeout wraps EVERY awaited blocking call in
`_runDeferredInit` (Supabase.initialize + seedIfNeeded + conditional syncToHive);
the onboarding pre-nav local writes are all pure-local Hive (saveProfile/setOnboarded/
saveProgress/logWeight — no awaited network); the splash degrades safely; the
RestoringScreen Plan-A self-heal recovers the now-backgrounded cloud
`onboarding_completed_at` stamp; referral order preserved; `/coach/induction` reads
only local Hive (no race). Independently reverted to pre-fix HEAD → the regression
test FAILS (a TRUE pinning test); restored → PASSES. P2 findings (SoT registry
timing annotation + stale `line_range` for the `onboarding_completed_at` writer) →
**FIXED** in this commit.

## Convergence
Both rounds were independent + context-blind; both ACCEPTED with only P2 findings,
all closed in this commit (no deferrals). `ground_truth_verified: true`.
`verdict: converged`. Hermes not required (account-tier, no catastrophic surface).

## Verification
- `flutter analyze` clean on both changed files.
- `test/contracts/boot_onboarding_hive_first_test.dart` (RED on pre-fix HEAD, GREEN
  on the fix — verified by the round-2 reviewer) + `onboarding_completed_at_behavioral_test.dart`
  + the two directly-affected onboarding contracts all green.
- SoT parity gate green after the `line_range` updates.
- Behavioral proof pending: the founder's live signup re-walk on the rebuilt server.
