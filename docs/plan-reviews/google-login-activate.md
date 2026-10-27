---
branch: google-login-activate
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/762507c768be-review.md
---

# Plan review — google-login-activate

## Summary

Activates Google OAuth sign-in. The Flutter/Supabase client code
(`ENLIST VIA GOOGLE` button + `AuthNotifier.signInWithGoogle`) already
existed but was never actually functional: no Google Cloud OAuth client had
been created (Track A, founder-performed: Google Cloud Console + Supabase
dashboard configuration, outside this repo), Android had no deep-link
intent-filter to catch the OAuth redirect, and `redirectTo` was hardcoded to
the mobile-only custom scheme even on web (diagnose `f2b8a1`, recurrence of
the `redirectTo`/allowed-redirect-list mismatch class from `e9f2a4`). This
batch (Track B) adds the Android manifest intent-filter and branches
`redirectTo` on `kIsWeb`.

## Round 1 (independent, context-blind)

Verdict: **converged**. Independently re-derived the root cause from
`git show HEAD:lib/features/auth/providers/auth_provider.dart` (pre-fix,
confirmed hardcoded `redirectTo` with no `kIsWeb` branch, an outlier vs.
`kIsWeb` guards elsewhere in the same file) and confirmed the pre-fix
manifest had no scheme intent-filter. Verified the fix's specifics: valid
Dart ternary syntax, intent-filter scheme/host exactly matches the runtime
redirect string, intent-filter sits on the correct `.MainActivity` block,
`https://app.icanbefitter.com` independently confirmed (via grep) as the
same established prod web origin used in `forgot_password_sheet.dart:57`
and prior diagnose-docs (e9f2a4, b7d4e2) — not a typo. Considered
completeness: `singleTop`/`taskAffinity` already present pre-fix (sufficient
for redirect delivery), `app_links` present transitively via
`supabase_flutter`, no scheme collision risk repo-wide. Checked
`docs/diagnoses/INDEX.md` for conflicting concurrent auth work — none
found. Confirmed the new regression test is non-vacuous by tracing each of
its 6 assertions against the pre-fix code. No P0/P1 issues.

## Round 2 (independent, context-blind, on the round-1-surviving state)

Verdict: **converged**. Verified the two B-pass documentation findings
(below) actually landed correctly — re-read the diagnose-doc and manifest
directly rather than trusting the review file's claim. Re-ran the
diagnose-doc validator and the regression test independently (both green).
Checked internal consistency of `touched_layers_checked` +
`impact_analysis` after the wording edit — coherent, no contradiction
introduced. Verified the edited `lib/features/auth/CLAUDE.md` pitfalls row
and the trimmed Phone-OTP row both still read accurately, and that
`functionality-flow.md`'s new `AUTH-04b` entry cites a test file that
actually exists at that path. Cross-checked the two different
`app.icanbefitter.com` redirect URL suffixes used (`/reset` vs. bare
origin) — different flows, correct as-is, not a drift. No new issues found.

## Ground-truth verification

Both rounds independently re-read and verified every cited file:line claim
against the live tree (pre-fix via `git show HEAD:...`, post-fix via direct
`Read`) rather than trusting the diagnose-doc's prose — see each round's
checklist above.

## B-pass

`docs/reviews/762507c768be-review.md` — verdict accepted. 2 findings, both
fixed in the same batch before commit: (1) the diagnose-doc self-declared
`blast_radius: feature`, but the touched paths (`lib/features/auth/**`,
`android/**`) are `account` tier per `docs/blast_radius.yaml` — corrected,
`impact_analysis` reworded to acknowledge the tier; (2) the diagnose-doc's
`readers:` entry cited `AndroidManifest.xml:41` (the pre-existing LAUNCHER
filter) instead of the actual new OAuth intent-filter at line 47 —
corrected. Neither finding was a defect in the shipped code, only in the
diagnose-doc's own self-description.

## Outstanding (not blocking, tracked in the diagnose-doc)

Live end-to-end verification (Android device tap-through, and the web flow
once deployed to `app.icanbefitter.com`) is still pending — no device/
emulator was available this session. `docs/diagnoses/2026-08-02-google-oauth-web-redirect-mobile-scheme-f2b8a1.md`
tracks this explicitly as the immediate next step, not a deferral.
