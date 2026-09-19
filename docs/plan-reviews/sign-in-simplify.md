---
branch: sign-in-simplify
scope: Hide ENLIST VIA PHONE (Twilio not wired) + email-first auth (server-side registration check replaces manual sign-in/sign-up toggle) + center alignment + centered brand-mark header polish
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/96afd825-review.md
---

# Plan-review record — sign-in-simplify

## Ground-truth verified (against live repo, pre-implementation)
`sign_in_screen.dart`'s `_buildEmailView` (pre-change) held a manual `bool _isSignUp` toggle with no
server-side registration check; `public.users` RLS is owner-only (`auth.uid() = id`, migration
`001_create_users.sql`) with no `auth.uid()` available pre-signin, confirming a
`SECURITY DEFINER` RPC (not an RLS relaxation) was required for a pre-auth "is this email
registered" check; the email sub-view routed through a bare `SingleChildScrollView` with no
bounded-height ancestor, confirming the top-alignment bug's root cause. Verified no existing
pre-auth email-registration check existed anywhere in the codebase (repo-wide grep).

## Round 1 (×2 context-blind — fresh agents, no conversation history, re-derived every citation
against the live repo rather than trusting prose) — findings, all folded into the plan
- The core designs were confirmed correct: `SECURITY DEFINER` over an RLS-relaxation; the
  `AuthState2`-shaped `checkEmailRegistered` method; the `LayoutBuilder`/`ConstrainedBox`/`Center`
  centering fix.
- Real gaps found and folded in: (a) `test/auth/terms_skip_test.dart:123-131` source-greps the
  literal strings `'if (_isSignUp)'` / `'!_isSignUp || _privacyAccepted'` and would break silently
  without an update; (b) the DPDP terms-acceptance Hive-stamp write block (`closes-diagnose:
  2026-05-16-terms-accepted-at-dpdp`, pinned by `test/contracts/terms_signup_writes_test.dart`)
  had to be carried over verbatim, same relative position to `signUpWithEmail(...)`; (c) no
  functional index existed on `lower(email)` — added `idx_users_email_lower`; (d)
  `docs/sot_registry.yaml`'s `terms_acceptance` entry and `docs/architecture/functionality-flow.md`'s
  `AUTH-02` entry would go stale.

## Round 2 (×2 — on the Round-1-hardened plan) — findings, all folded
- Re-checked every Round-1 fix against the live repo: all confirmed correct/complete.
- One new gap found: `checkEmailRegistered` was missing the `_ensureSupabaseReady()` guard every
  sibling auth method (`signInWithEmail`/`signUpWithEmail`/`signInWithGoogle`/`signInWithPhone`)
  uses — folded in before implementation.
- I independently re-verified the load-bearing claims from both rounds myself (not just trusting
  subagent prose) before accepting them. Round 2 verdict: ready to implement.

## Implemented + tested (`flutter analyze` clean; `flutter test` green — 2154+ tests)
- Part 1: `_kEnablePhoneEnlist` const flag hides the phone button; old path preserved verbatim
  (§4.6 feature-flag protocol).
- Part 2: `_EmailStep` 3-step state machine (enterEmail → signIn/signUp); new migration `106`
  (`public.email_is_registered(text)`, renumbered from a colliding `104` after a 24-commit main
  fast-forward mid-session — see B-pass Finding 5 for the pre-existing filename-collision risk
  class); applied live to `dedsavbjuwgarrhphgnl` with explicit founder go-ahead, verified via
  `has_function_privilege` + live registered/unregistered probes.
- Part 3: centered brand-mark header (seal + eyebrow + gold rule + full-width title) replacing the
  narrow `AuthHeader` on the email path only; `AuthHeader` untouched, still used by the phone view.
- Live-verified on `localhost:8080` (Flutter web release build) by the founder for both the
  email-first flow and the Part 3 visual polish before committing.

## Round 3 — B-pass (`docs/reviews/96afd825-review.md`, on the committed diff `96afd825`)
Fresh Sonnet subagent, context-blind, ran the 5 standard lenses + extra scrutiny on the RPC's
security (SQL-injection surface, anon-grant correctness, RLS non-weakening — all live-verified) and
the state machine's reset/race behavior. **5 findings (1 P1, 4 P2), all triaged same-session:**
- P1 (blast_radius_mismatch): this plan-review record itself was missing — the actual finding this
  file resolves.
- P2 (writer_reader_drift): `docs/sot_registry.yaml`'s `terms_acceptance` line-range citation was
  stale (cited the wrong method's line range) — fixed.
- P2 (state-machine correctness): no synchronous reentrancy guard on the CONTINUE button allowed a
  same-frame double-tap to fire `checkEmailRegistered` twice (idempotent, low severity, but real) —
  fixed with a `_checkingEmail` guard + a new regression test.
- P2 (test quality): no behavioral (only source-grep) test protects the `AuthStatus.success`
  invariant on `checkEmailRegistered` — accepted as a pre-existing, codebase-wide structural gap
  (no AuthNotifier network method has a mocked-network test; `SupabaseService` is a non-injectable
  singleton) and spawned as a dedicated follow-up rather than a scope-creeping mock harness inside
  this UI batch.
- P2 (blast_radius_mismatch): the blast-radius classifier is filename-substring-based for
  catastrophic-tier migration detection, so a SECURITY DEFINER migration with an innocuous filename
  (like this one) doesn't auto-escalate — verified benign for this specific migration via live
  query, spawned as a tooling follow-up.

## Verdict: converged
Core design validated across 2 pre-implementation rounds, implementation matches the hardened plan,
founder live-verified both functional flow and visual polish, and the post-commit B-pass found no
P0s and no unaddressed live-risk P1/P2s (1 P1 was this record itself; the 4 P2s are fixed or
explicitly triaged with follow-ups spawned for the two genuinely out-of-scope structural items).
