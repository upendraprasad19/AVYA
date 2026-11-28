---
branch: claude/oi-242-flaky-test-filing
date: 2026-09-23
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/3aa28693fb6f-review.md
---

# Plan review — confirm-link Vercel-redirect fix + resend-confirmation affordance (`claude/oi-242-flaky-test-filing`)

## Why this record exists

`lib/features/auth/` is explicitly named in root CLAUDE.md §4.12.6's **L**
classification ("payment/auth/sync/schema/EF/plan-engine/CLAUDE.md") — the full,
unabridged ×2 plan-review process applies before this branch can merge to `main`.

## Scope

Live founder-driven investigation of real user "Email not confirmed" reports
(sumitk142003@gmail.com and others), root-caused via direct `curl` against the
live production deployment and live reproduction on two real devices. Two bugs
fixed, then two rounds of independent context-blind review each surfaced one
real defect in the immediately-preceding fix, both corrected in-batch:

1. `f0580c14` — **Bug A**: Vercel's `/confirm` redirect
   (`destination: "/#/confirm"`) forwards `token_hash` BEFORE the `#` fragment
   instead of inside it; this app's Flutter web build is HashUrlStrategy-only,
   so GoRouter's `state.uri.queryParameters` never sees it. Fixed via
   `ConfirmLinkDetector` (new pure detector) capturing `Uri.base` in `main()`
   before `runApp()`, mirroring the existing `PasswordRecoveryDetector`
   pattern. **Bug B**: no self-service recovery path existed for a user whose
   "Email not confirmed" sign-in attempt failed — added a "Resend confirmation
   email" affordance on the sign-in screen.
2. `6bf5ad90` — fixes 3 P2s from the self-triggered B-pass
   (`docs/reviews/3aa28693fb6f-review.md`, `verdict: accepted`): the resend
   affordance hid itself after a FAILED resend (made sticky-once-shown); a
   wrong mutation-proof count in the diagnose-doc (corrected, old claim struck
   through per rule 21); a missing SoT registry entry for the new mechanism.
3. `9ba66bc4` — fixes round-1 plan-review's MAJOR finding: the new
   `AppRouter.pendingConfirmTokenHash` field had no clear-after-use gate, unlike
   its claimed sibling `isPasswordRecovery` (which IS reset `false` after use) —
   would have silently re-supplied an already-consumed/expired token on any
   later re-render of `/confirm`.
4. `1b936deb` — merge from `origin/main`, resolving round-1's other finding
   (branch was stale, missing an unrelated versionCode-bump PR). Pure
   3-way merge, no conflicts, verified both sides' `docs/sot_registry.yaml`
   and `.claude/skills/code-review/SKILL.md` additions survived intact.
5. `cab97d56` — fixes round-2 plan-review's MAJOR finding: commit 3's own fix
   introduced a new gap — clearing `pendingConfirmTokenHash` means a LATER
   rebuild of the same `ConfirmEmailScreen` State (browser back; go_router
   reuses State via `didUpdateWidget` since `pageKey` is path-only) can arrive
   with `tokenHash == null` while a real `confirmEmail()` call is still in
   flight, and the pre-fix `build()` early-return for a missing token skipped
   past the `ref.listen` registration entirely — silently dropping the
   success → `/restoring` routing. Fixed by gating the early return on
   `_startedFor == null` too. Also corrects two stale-doc findings from the
   same round (a `sot_registry.yaml` `class_constraints` block describing the
   pre-round-1-fix behavior, and a diagnose-doc line the doc's own
   `mutation_proven` block had already corrected but which wasn't propagated).

## Review timeline (3 rounds + 1 B-pass, all independent/context-blind)

1. **B-pass** on `f0580c14`+`6bf5ad90`: 3 findings (all P2), 0 false_alarm, all
   fixed in-batch. `docs/reviews/3aa28693fb6f-review.md`, `verdict: accepted`.
2. **Plan-review round 1** (dispatched fresh, context-blind, on
   `git diff origin/main HEAD` as it stood after the B-pass): **NOT CONVERGED**
   — 1 MAJOR (`pendingConfirmTokenHash` clear-after-use gap) + 1 MAJOR (branch
   staleness vs `origin/main`), both real, both verified against live code
   before fixing. Fixed in `9ba66bc4` + `1b936deb`.
3. **Plan-review round 2** (dispatched fresh, explicitly scoped to probe round
   1's OWN fix for a new gap, per CLAUDE.md §4.12.1's "the corrections
   themselves can introduce new defects"): **NOT CONVERGED** — 1 MAJOR (the
   `ref.listen`-drop gap described above, a genuinely new defect introduced by
   round 1's fix, not present in the original `f0580c14`) + 2 MINOR (stale doc
   claims). Fixed in `cab97d56`.
4. **Round-3 convergence check** (small, tightly-scoped, dispatched fresh
   against only the ~15-line round-2 fix, not a full re-review — per
   CLAUDE.md §4.12.1's "don't review the large thing a fifth time" guidance,
   since the unit stayed small and each round converged one genuinely new,
   real finding rather than repeatedly surfacing unrelated material):
   **CONVERGED**. Independently re-ran the mutation-proof (reverted the
   round-2 guard, confirmed exactly 1/8 tests reddens — the new regression
   test — matching the author's claim), traced `AuthNotifier.confirmEmail`'s
   full try/catch structure to rule out a "stuck loading forever" residual,
   confirmed both doc corrections are now internally consistent, ran
   `flutter test`/`flutter analyze` clean.

## Ground truth (independently re-verified across all rounds, not merely asserted)

- Root cause: live `curl -D-` against `https://app.icanbefitter.com/confirm?...`
  confirmed the exact Vercel redirect shape; reproduced on 2 real devices
  (iPhone Safari, Android w/ app installed).
- `vercel.json`'s `/confirm` redirect rule: confirmed byte-identical to
  `origin/main`, never touched by this branch (deliberate — a client-side fix
  was chosen over live trial-and-error against production redirect config).
- All new/touched test files run live and green multiple times across all
  4 review passes: `test/contracts/confirm_link_detector_test.dart`,
  `test/contracts/is_email_not_confirmed_message_test.dart`,
  `test/auth/sign_in_screen_resend_confirmation_test.dart`,
  `test/auth/confirm_email_screen_test.dart` (8 tests, final state).
- `flutter analyze` clean on every touched `lib/` file across all rounds.
- `dart run scripts/check_sot_registry_parity.dart`: PASS, 0 errors, every
  round (including after the `origin/main` merge).
- `dart run scripts/validate_diagnose_doc.dart` on both diagnose-docs
  (`f92d17`, `f6c2a9`): PASS.
- Full local `flutter test` suite (pre-push, unconditional at ≥account tier):
  green at `1b936deb` (6304 tests) and again at `cab97d56` (6305 tests) —
  both independently confirmed landed via `git log -1` + `git status
  --porcelain` + `git ls-remote origin` matching local HEAD (never trusted
  from exit code alone, per this repo's own `feedback_git_landing_verification`
  discipline — one push attempt genuinely failed on a transient SSH timeout
  and was caught this way before being retried).
- Mutation-proofs independently re-run by a DIFFERENT reviewer than the one
  who wrote each fix, for both round-1's and round-2's regression tests —
  not merely trusted from the author's own claim.

## Residual, explicitly out of scope for this branch

1. **Not yet deployed to Vercel production.** Requires separate, explicit
   founder authorization per CLAUDE.md §4.3 before the fix takes live effect —
   this record covers mergeability to `main`, not the deploy step.
2. **Android App Links not claiming `/confirm`** on real devices even with the
   app installed — live-reproduced, separate root cause (likely Play App
   Signing certificate mismatch), tracked under OI-244, not this branch's job.
3. Does not retroactively confirm already-unconfirmed real accounts
   (sumitk142003@gmail.com, avyaanshfit@gmail.com, etc.) — each needs the new
   resend affordance (once deployed) or a manual admin confirm.

## Verdict

**Converged.** 3 review rounds + 1 B-pass, each round's own finding
independently verified and fixed before proceeding, final round confirming no
further gap. Safe to merge to `main`.
