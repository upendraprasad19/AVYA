---
branch: oi341-piece-b2-door
plan: docs/plans/oi341-piece-b2-door.md
date: 2026-10-21
blast_radius: catastrophic
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/64b21cb79f3c-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-21-hermes-oi341-piece-b2-door.md
---

# Plan review - OI-341 Piece B2a, the purchase door, the switch-mismatch alarm, the replay window and both flips

Founder decisions: 2026-10-13 (purchase during the referral trial, paid time stacks); 2026-10-20 answers 2-6; 2026-10-21
(the server keys are the LIVE pair, so the live steps use small real payments with one 90% promo code, refunds and
cancel-not-delete clean-up; the order B2a live steps -> refunds -> B2b -> the next AAB with the live key ID in `.env`);
2026-10-21 "ok" to build B2a, then "ok" to the commit, this record, the PR, the gate replay and the merge, and "ok" to
OI-366 and OI-367 as decisions before store launch. NOT covered: every live step of plan section 4 (the code, the three
deploys, the alarm drill, both secret flips, the purchases, refunds and row corrections), each its own go.

## Tier (CLAUDE.md 4.12.4)

Full x2 review, no `ship_dark_build` tier. B2a is the commit that makes `ENABLE_SUBSCRIPTION_STACKING` flippable (it is
the flip review the Piece A and B1 entries in `docs/ship_dark_pending_review.yaml` waited for; that entry moves to
`resolved:` in this commit) and adds `ENABLE_TRIAL_PURCHASE`. Both secrets stay unset at merge; setting each is a live step.
While either is off, the door answers as `origin/main` `b8385b6c` (golden against the committed fixture copy).

## Review rounds

- **Rounds 1-2 (v1, v2, the unsplit B2):** round 1 0 P0 / 5 P1, round 2 0 P0 / 2 new P1. Round 2's P1-A (the web client
  deploys at merge, before the door opens) SPLIT the unit into B2a (server, this record) and B2b (client, its own plan).
  Dispositions: plan sections 7 and 8.
- **Round 3 (v3, the first review of post-split B2a):** 0 P0, 2 P1 (the notes-based alarm a client could forge; step 3(b)'s
  tester), 5 P2. v4 replaced the alarm with a database check. Plan section 10.
- **Round 4 (v4):** **0 P0, 0 P1**, 4 P2, P3s; all plan text, folded into v4.1 (`mechanical_only`). Rounds 3 and 4 are the
  two reviews of the post-split plan: converged. Plan section 11.
- **v4.2** (founder answers, live-sequence text only) and **v4.3** (B-pass and hermes dispositions): plan sections 12-13.
  Both were read by the B-pass and hermes seats, whose briefs included section 4.
- **B-pass** (`docs/reviews/64b21cb79f3c-review.md`, accepted): 2 fresh Sonnet seats on the built, staged tree; 0 P0 / 0 P1 /
  4 P2 / 7 P3, all fixed (ledger rows `BP-*`); seat A's proposed mutants run as SA1-SA12.
- **Hermes pass** (`docs/audit/2026-10-21-hermes-oi341-piece-b2-door.md`, accepted): 4 Sonnet seats (L1/L21, L23/L40,
  L22/L2 + the live sequence, L29 + abuse), run after the B-pass fixes; 0 P0 / 0 P1 / 6 P2 / 7 P3. Fixed in code: the
  silent 400 for a captured amount that matches no plan (diagnose c3e7a1). Fixed in the plan: fresh testers and a third
  redeem, cancel-not-delete, upper-case code, host-shell deploy. Filed: OI-366, OI-367. Ledger rows `HM-*`.
- **Convergence, stated plainly.** v4.3 was not re-reviewed as a plan; the B-pass and hermes seats read the built tree with
  the v4.2 live sequence and found no P0 or P1.

## Ground truth

- Code commit `6bfbd402` (33 files, +3311/-115), from `main` `b8385b6c`.
- Deno: 1288 passed across the whole functions tree; the only 2 failures (`future-prediction`, `re-engagement`) are the
  VPS port-8000 `AddrInUse` clash in functions this batch does not touch.
- Flutter (TZ=Asia/Kolkata, golden excluded): 9959 passed, 9 skipped. `flutter analyze lib/`: no warnings or errors.
- Mutation runner: 57 of 57 mutants red on the final tree; sources restored and byte-compared.
- Pre-commit gate loop: exit 0 with the review file staged; staged hash stable at `64b21cb79f3c`.
- Ledger `docs/audit/oi341-piece-b2-door.closure.yaml`: 67 rows, all terminal (Gate 40 PASS); live steps are
  `blocked_on_user` rows `L*`.
- Live state read during the batch: `verify-payment` v26 and `razorpay-webhook` v30 are the `b8385b6c` code;
  `create-razorpay-order` is the pre-B2a door; neither `ENABLE_SUBSCRIPTION_STACKING` nor `ENABLE_TRIAL_PURCHASE` is set;
  `alerts` has no CHECK on `source`; the server Razorpay secrets are the live pair (founder statement).

## What this record does NOT claim

No B2a deploy, no secret set, no live payment, no alarm drill and no PR CI run yet; nothing about B2b (the client copy, the
paywall line, the EST seal) or the next AAB.
