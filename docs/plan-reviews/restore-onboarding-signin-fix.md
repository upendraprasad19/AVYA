---
branch: restore-onboarding-signin-fix
date: 2026-08-03
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/1cf9f51d2565-round2-review.md
---

# Plan-review record — restore-onboarding-signin-fix (account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Account-tier — confirmed live via `dart run scripts/blast_radius_from_diff.dart` against the
actual staged file set (auth screens + onboarding screen + shared repository, no migration/
Edge Function/pubspec surface touched).

## Scope

Three independent changes, shipped together per founder instruction ("we finalise the design
and fix all in one batch"):

1. Fixes diagnose [a3f6d9](../diagnoses/2026-08-03-restoring-screen-local-onboarded-flag-not-stamped-a3f6d9.md):
   a returning, fully-onboarded user landed on `/onboarding` instead of `/home` after a session
   restore, because the local `onboarding_completed` Hive boolean (which `_authRedirect` gates
   on) was never stamped by the restore path — only the separate cloud-mirrored
   `onboarding_completed_at` timestamp was.
2. Fixes diagnose [e7c2a4](../diagnoses/2026-08-03-welcome-screen-hero-overflow-e7c2a4.md): the
   onboarding welcome screen's hero content overlapped the CTA section on short/normal viewports
   because it had no scroll fallback.
3. Implements a founder-approved visual redesign of the sign-in screen (not a bug fix): a single
   enclosed Wardroom card holding a Google-brand-spec white-pill "Sign in with Google" button
   (primary), an OR divider, the email field, and a visually-secondary CONTINUE button. Approved
   via `/ui-mockup` HTML mockup (`docs/mockups/2026-08-03-sign-in-google-card-v1.html`) before
   any Flutter code was touched, per the founder's explicit request to see the mockup first.

## Review arc (2 rounds; §4.12)

- **Round 1 — context-blind B-pass (fresh Sonnet subagent).** Ran the standard 5 lenses plus 3
  custom lenses for this batch (compact-parameter isolation on the redesign, Google-button guard
  parity, and restoring-screen fix completeness). Verdict: **3 findings (1 P0, 2 P2)**.
  - **P0 (Finding 1):** the diagnose-doc's fix only covered 2 of 3 actual paths to `/home` in
    `restoring_screen.dart` — `_onContinueAnyway` (the 30s CONTINUE timeout escape hatch) bypassed
    `_goHome` entirely and was still missing the flag stamp, reachable exactly during the slow
    restores the bug report described. Independently verified (grep + full method read) before
    accepting, then fixed: added the guard, gated on a new `ownershipOpen` bool.
  - **P2 (Finding 2):** the new SoT registry entry's `line_range` for `_goHome` didn't span both
    branches its own notes described. Corrected.
  - **P2 (Finding 3):** the sign-in redesign touches `account`-tier `lib/features/auth/**` with no
    kill-switch, which CLAUDE.md §4.6 (auth-change feature-flag protocol) asks for by the letter
    of the rule. Independently verified the review's own counter-claim ("UI-only, no auth-logic
    change") by diffing every `onPressed`/guard predicate old vs new — byte-for-byte identical.
    **Disposition (this record):** accepted as exempt from §4.6. §4.6 is aimed at
    behavioral/security auth changes (new code paths, new async operations, changed guard
    predicates); this diff changes only presentation — every guard callback that gates an auth
    operation is reproduced verbatim, confirmed by direct diff, not assumed. Rollback path if the
    redesign proves bad: `git revert` the isolated `sign_in_screen.dart` commit — no other file
    depends on its internals. See `docs/reviews/1dcc14cdbf32-review.md` Finding 3 for the full
    verification trail.

- **Round 2 — independent context-blind review of round 1's own P0 fix (fresh Sonnet subagent).**
  Per §4.12.1: "the corrections themselves can introduce new defects." Tasked specifically with
  re-deriving round 1's reachability claim from the actual code, not accepting its prose. Verdict:
  **1 finding (P0) — round 1's fix was itself wrong.** `_timeoutTimer` (30s) starts in `initState`
  wall-clock-independent of `_kickoffRestore`'s progress, and `resolveDestination` (the
  classification query) is a live, un-timed-out network call — on a slow enough connection the
  CONTINUE CTA can surface *before classification has happened at all*, not only "while `_goHome`
  is already in-flight" as round 1 assumed. Tapping CONTINUE in that window would have
  unconditionally stamped a genuinely new or mid-onboarding user as onboarded.

  Independently re-verified by me before accepting (per this repo's "never trust a subagent
  structural claim unverified" discipline): read `initState`, the full `_kickoffRestore` method,
  and `AuthSessionBootstrapper.resolveDestination`'s actual Supabase call myself — the finding
  checked out; round 1's reasoning was disproven, not just disputed.

  **Fix:** replaced the timing-based inference with explicit state tracking — a
  `_committedToGoHome` bool, default `false`, set `true` only immediately before `_goHome` runs
  (in both the `GoHome` and `ResumeOnboarding`-self-heal branches). `_onContinueAnyway`'s stamp
  now gates on `ownershipOpen && _committedToGoHome && !isOnboarded`; the pre-existing
  unconditional navigation is unchanged, so the pending-classification edge case behaves exactly
  as it did before this diff (correctly re-bounces via `_authRedirect` once classification
  resolves) — only the flag-stamp side effect is now provably safe. The diagnose-doc and SoT
  registry were corrected to remove round 1's disproven reasoning rather than leave it standing
  alongside the fix.

  Round 2's other 8 lens checks (writer/reader drift, function-exception-swallow, blast-radius
  mismatch, secrets-in-tree, unawaited-no-error-sink, ownership-open race correctness re-verified
  from `HiveUserSession` internals, double-write interleaving, and source-grep regex fragility)
  were all clean — see `docs/reviews/1cf9f51d2565-round2-review.md` for the full verification
  trail on each.

  A side-effect of applying round 2's fix: `dart format` reflowed `restoring_screen.dart`,
  incidentally breaking an unrelated pre-existing source-grep test
  (`auth_session_bootstrapper_test.dart`'s literal-substring check for
  `AuthSessionBootstrapper.instance.resolveDestination`, which no longer matched once the
  formatter line-wrapped the call). Fixed in the same commit (regex tolerant of whitespace/
  newlines) rather than deferred, per §4.2 — not a functional regression, a pre-existing test
  fragility this batch's own formatting run happened to surface.

## Ground truth verified, not assumed

Every structural claim from both subagent review rounds was independently re-verified by the
implementing agent before being accepted or acted on (grep + direct file reads, not trusting
subagent prose) — most materially round 2's Finding 1, which directly contradicted round 1's own
(also independently-verified-at-the-time, but incompletely reasoned) claim. `flutter analyze`
and `flutter test` were re-run fresh after every fix, not assumed from either round's own report.

## Verification

`flutter analyze` clean on all touched files (`restoring_screen.dart`, `welcome_screen.dart`,
`sign_in_screen.dart`, plus the 2 new/1 updated test files). `flutter test` on the full
`test/auth/` directory + `test/widgets/onboarding/welcome_screen_short_viewport_test.dart` +
`test/contracts/onboarding_completed_at_behavioral_test.dart` +
`test/contracts/auth_session_bootstrapper_test.dart` +
`test/contracts/restoring_screen_local_onboarded_flag_stamp_test.dart` → 66/66 green, re-run
after every fix in both rounds. `dart run scripts/validate_diagnose_doc.dart` passes on both
diagnose-docs. Live end-to-end browser verification was attempted (Flutter web-server preview)
but blocked by a session-level environment limitation (Browser pane could not composite/render
CanvasKit frames within the available session time) — not claimed as verified; the sign-in
mockup was independently approved by the founder pre-implementation instead, and the underlying
guard-predicate parity was confirmed by direct diff rather than by pixels.

## Convergence

Round 1 found one blocking issue (fix-completeness gap) and fixed it. Round 2, reviewing that fix
specifically for new defects per §4.12.1, found the fix itself was wrong in a different way and
required a second, structurally different correction (state-tracking instead of timing-inference).
This is exactly the pattern §4.12.1 anticipates ("the corrections themselves can introduce new
defects") — two rounds, two distinct real findings, both fixed, no third round needed: round 2's
other 8 lenses were unanimously clean, and round 2's own fix (a small, localized state-tracking
addition, not a new design) was verified directly by the implementing agent against the actual
code before being accepted, rather than deferred to a third review round. The §4.12
"keeps-finding-new-material-issues → split" signal did not fire on a third pass being needed —
the unit converged.

**Verdict: converged.**
