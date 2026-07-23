---
branch: auth-reset-pkce-fix
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/0fc99a56da0c-review.md
---

# Plan review — auth-reset-pkce-fix

## Summary

Fix for diagnose `b7d4e2`: password-reset email links using Supabase's PKCE
flow (`?code=<uuid>`) weren't detected as recovery links by
`PasswordRecoveryDetector` (previously inline in `main.dart`), which only
recognized the older implicit-flow fragment shape. Users landed on
`/onboarding` instead of `/reset`. Fix extracts detection into a pure,
testable function and adds a PKCE branch scoped to the `/reset` path.

## Round 1 (independent, context-blind)

Verdict: **converged**. Independently re-verified (not trusted from the
diagnose-doc): `forgot_password_sheet.dart:57` redirectTo value,
`pubspec.yaml:37` supabase_flutter version + its PKCE/detectSessionInUrl
defaults, `supabase_service.dart:49-52` has no flow-type override,
`main.dart`'s detector call ordering relative to `runApp()`, and
`_navigateNext`'s branch ordering (recovery flag checked before
authenticated-state routing). Considered and ruled out two alternative
root causes (RestoringScreen misclassification; an async-init race
independent of the detector). Checked fix sufficiency against edge cases
(multiple query params, trailing slash / future path-prefix deploys) —
found one minor brittleness note (exact-equality path match), not
fix-invalidating. No P0/P1 issues.

## Round 2 (independent, context-blind, on the round-1-surviving state)

Verdict: **needs-rework → resolved same batch**. Verified the new
behavioral test's assertions are genuinely non-vacuous (checked each would
fail without the corresponding branch). Verified `git log --all --grep=b7d4e2`
resolves to commit `0fc99a56` — closes-diagnose linkage intact. Verified no
conflicting concurrent auth work via `docs/diagnoses/INDEX.md`. **Found a
real issue:** two test docstrings shipped the literal unreplaced placeholder
`diagnose <id>` instead of `diagnose b7d4e2` — a copy-paste artifact. Fixed
in the same batch (commit following `0fc99a56`), re-verified tests still
green (20/20) after the fix. No other issues found.

## Ground-truth verification

Both rounds independently re-read and verified the cited file:line claims
against the live tree rather than trusting the diagnose-doc's prose — see
each round's summary above for the specific checks performed.

## B-pass

`docs/reviews/0fc99a56da0c-review.md` — verdict accepted. 2 non-blocking
findings, both resolved: (1) no end-to-end live-session test for the
`/reset` → `updateUser()` path — covered by the plan's founder-gated manual
verification step instead of a code change; (2) diagnose-doc's
`touched_layers_checked` omitted Tier 11 (external services / Supabase
dashboard redirect-URL allowlist) — added retroactively.
