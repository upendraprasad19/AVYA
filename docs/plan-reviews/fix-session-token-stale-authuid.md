# Plan-review record — fix-session-token-stale-authuid (OBS-6 residual a7f2e1)

branch: fix-session-token-stale-authuid
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/a7f2e1-session-token-authuid-bpass.md

## What this fixes

OBS-6 residual (diagnose `a7f2e1`): in-session account switch (sign-out A →
sign-in B) leaves every mixin tab stuck on the loading skeleton until reload.
`authUserIdTokenProvider` derived `authUid` from the cached, never-invalidated
`currentUserProvider` → stale on account-switch → token stuck `'<anon>'` → the
`isSessionTearingDown` gate (upstream of all data providers) stuck. FIX (OPT-1):
read the LIVE authUid (same source `wrapUserScopedBox` uses), kill-switched by
`configBox['disable_live_auth_token_read']`. **Not a C3 regression** (restore
succeeded; reload fixes it with no re-restore).

## Review rounds

- **R1 — ×2 context-blind plan review, 3 lenses** (correctness / cross-account
  isolation / completeness+test-breakage), workflow `wf_1d3c11c0`. Converged on
  **OPT-1**. **OPT-2** (make `currentUserProvider` reactive) REJECTED — it fires
  on `authStateProvider` BEFORE `openForUser` completes, re-introducing the
  ordering race the owner-edge design deliberately avoids.
- **R2 — review of the hardened plan, 2 lenses.** Surfaced ONE blocking
  correction: `auth_invalidation_timing_test.dart` overrode `currentUserProvider`
  (dead code under OPT-1) → must migrate to the shared `debugAuthUidResolverForTests`
  seam. **Resolved in implementation** + verified (16 tests green across 5 files).
- **R3 — B-pass adversarial code review of the final diff, 2 lenses**, workflow
  `wf_294a8e41` → `docs/reviews/a7f2e1-session-token-authuid-bpass.md`. **Accepted,
  0 P0/P1** (correctness, cross-account isolation, kill-switch, test adequacy all
  verified).

## Ground truth

Root cause + fix verified against `git show main:` (HEAD `bf8b1aa`) and live prod
telemetry (test7 `e34b04a9`: `restore_completed status=success path=singlecall`;
stuck-skeleton emitted ZERO post-restore telemetry; reload fixes with no
re-restore). `currentUserProvider` confirmed single-consumer + never-invalidated
(zero `invalidate(currentUserProvider)`; single long-lived `ProviderScope`).
`flutter analyze` clean; regression test is genuine RED→GREEN.

## Scope / recurrence

Account-tier (`lib/features/auth/**`; the platform primitives `guarded_box.dart` /
`hive_user_session.dart` are untouched). Recurrence of **b8e3f1** (OBS-6) — that
fix repaired the box read + blank-Home symptom, not the token source, so the
neutral stuck-skeleton residual survived. Diagnose:
`docs/diagnoses/2026-07-02-session-token-stale-authuid-a7f2e1.md`.
