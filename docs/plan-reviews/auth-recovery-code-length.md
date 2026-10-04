---
branch: auth-recovery-code-length
date: 2026-10-03
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/auth-recovery-code-length-bpass.md
---

# Plan-review record — password-reset code field vs hosted OTP length (`auth-recovery-code-length`)

Founder-reported incident 2026-10-03: a Google-created user asked for a password-reset code on the web app; the email carried 8 digits and the sheet's code field accepts at most 6.
Plan: `docs/plans/auth-recovery-code-length.md` (v3). Fix tier L (auth), blast-radius `account` (`lib/features/auth/**`, `lib/core/**`), inline execution.

## Review rounds
- **R1** — fresh Sonnet context, read-only (166 tool calls). Verdict **harden**. 2 × P1 (the test harness could not give each case its own client because `Supabase.initialize` is a one-shot
  singleton; the client range check + `maxLength` truncation was the weaker design and "documented contract" was false for email), 9 × P2, 4 × P3. All accepted and folded into v2.
- **R2** — fresh Opus context on the post-R1 plan, read-only (159 tool calls), a different reviewer. Verdict **harden**. 2 × P1 (a `SupabaseClient` built inside the `testWidgets` body hangs on `dispose()` under FakeAsync —
  reproduced with `package:fake_async`; a NEW separate observation, below), 6 × P2, 10 × P3. All accepted and folded into v3. R2 found no defect in the core design (D1–D4); its findings were harness mechanics, ledger/gate
  bookkeeping, wording, and the separate observation.
- **Converged-after-fold is a SELF-ATTESTATION, not a third review.** No third round was run: both reviewed rounds are done, the folds are mechanical, the reviewer's own opinion was "converging; split the large item out",
  and the B-pass reviews the real diff. Precedent: `docs/plans/resume-banner-batch.md` ("harden → CONVERGED after fold").

## Ground truth
- Live (read-only): the user's auth row, identities, session, `recovery_sent_at`; GoTrue `auth_logs` (one `/recover` 200, zero `/verify`); `edge_logs` JWT attributes and `auth_audit_logs` for the §1b timeline (re-verified by the main thread);
  hosted config via the Management API read (allow-listed non-secret keys): `mailer_otp_length` now 6, template = bare `{{ .Token }}`, everything else unchanged — re-read independently by both reviewers.
- Session-sourced (not independently reproducible): the pre-change value 8 and the per-key sha256 "only one key changed" diff of the founder-authorised PATCH.
- GoTrue `Mailer.OtpLength` clamp [6,10] read from upstream source and confirmed by R1 at 9 tags back to v2.50.0; Supabase docs say `{{ .Token }}` is a "6-digit" code (3 pages, re-verified).
- Harness facts derived from the installed gotrue 2.27.1 / supabase_flutter 2.17.1 / supabase 2.16.0 sources and a pure-Dart FakeAsync simulation — **confirmed during execution by real `flutter test` runs**: a per-test recording `SupabaseClient` built in `setUp` and injected through `SupabaseService.clientOverrideForTest`, `Completer` gates holding `/recover` and `/verify` open, and a tap on the modal barrier to dismiss the sheet mid-request all work as planned.
- Not verifiable by anyone: when the hosted value became 8 (no config history); whether shipped APKs contain the sheet (only the web bundle was checked).

## §4.6 disposition (CLAUDE.md feature-flag protocol for auth changes)
**Exempt**, recorded here as `docs/plan-reviews/restore-onboarding-signin-fix.md:50-60` records its own. The diff changes one guard predicate in the recovery-code sheet; the old path is the defect, so a default-OFF flag with the old path
reachable would preserve the lockout. For every code GoTrue can issue the new predicate accepts a superset of the old one (exactly-6-char → ≥ 6 digits), so 6-digit behaviour is identical and 7+-digit codes newly work; the only strings newly rejected
(`+12345`, `-123456`, `0x1234`, …) can never be issued. Rollback is `git revert` of the single fix commit. **The founder may overrule and ask for a flag.**

## Separate observation (not part of this diff)
R2 found, and the main thread re-verified, that the user's SDK session was valid throughout while the sign-in screen was showing (its `email_is_registered` RPC carried her authenticated JWT at 07:29:53Z and 07:30:36Z; the same session
ran normal app traffic from 07:40Z). Mechanism unproven. It is ledger row 15 (`blocked_on_user`: founder scope decision) in `docs/audit/auth-recovery-code-length.closure.yaml`; it needs its own §4.1 diagnosis and is not folded into this unit
(CLAUDE.md §4.12.1).

## B-pass (self-initiated before the merge, CLAUDE.md §4.3)
`docs/reviews/auth-recovery-code-length-bpass.md`: two context-blind reviewers (A: lenses 1-5, 7, 8; B: lens 6, mutate-and-run), 20 findings, every one in a terminal state in `docs/audit/auth-recovery-code-length.closure.yaml`. Reviewer A found the dismissed-sheet defects (pre-existing since `c9e2b7`); reviewer B found that the first fix of those used the wrong predicate (`mounted`, which stays true through the sheet's exit animation), that a double tap could spend the single-use code twice, that a pasted code carrying an invisible character was refused, and that the sheet's whole back / failure / in-flight surface had no test. All fixed in this batch; the new test file grew from 35 to 99 tests and the mutation table from 25 to 73 runs (see the diagnose-doc). `bpass: accepted` is therefore claimed above, after the review exists.
