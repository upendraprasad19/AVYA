---
branch: freeze-order-d1
date: 2026-11-02
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/c0a6bf692b15-review.md
---

# Plan-review record - freeze-order-d1 (settle, then credit; platform)

Plan: `docs/plans/2026-11-02-freeze-order-settle-then-credit.md` (r7). Tier `platform` (the streak walk and the
freeze refill path; `streak_progress_service.dart` is a platform file in `docs/blast_radius.yaml`).

## Rounds (context-blind Sonnet reviewers, each verifying claims against the code)

1. Round 1: NOT converged; the plan was folded.
2. Round 2: NOT converged. P0: a stateless walk cannot make a break durable, so the horizon rule was added.
3. Round 3: NOT converged. P1: the pre-pass and caller reorder sat in the wrong place; the rule moved into the walk
   and both were deleted.
4. Round 4: NOT converged (test and weekday scope).
5. Round 5: NOT converged (Monday-key helper double-conversion bug; the NULL-stamp decision).
6. Round 6: the MECHANISM converged (0 P0, 0 P1 in code). One test-plan P1 (the legacy-switch tick>0 case) was
   folded mechanically into plan section 3.9 and is pinned by a test.

Honest note: rounds 1-5 did not converge; the unit was kept because each round removed a mechanism (the pre-pass,
the caller reorder) instead of adding one, and round 6 found nothing in the code. Round 6 converged on mechanism
with the one test-plan P1 folded without a seventh round.

## Ground truth

The founder's rule and the chain behaviour were checked against the code and a pinned-clock behavioral test
(26 tests, 18 mutants plus the PRO-cap mutant red). No live-state claim is made; no migration, no Edge Function.
B-pass: `docs/reviews/c0a6bf692b15-review.md` (no P0/P1; every P2/P3 handled in the batch).
