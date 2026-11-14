---
branch: profile-share-grow-order
date: 2026-10-04
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/profile-share-grow-order-bpass.md
---

# Plan-review record — one Photos row opening a Progress | Saved hub; SHARE & GROW below AVYA (`profile-share-grow-order`)

Founder requests 2026-10-03 (two rows to one, then "an abstraction like user photos … progress and saved"; "move share and grow block to below avvya block") and 2026-10-04 ("go ahead ship it").
Plan: `docs/plans/profile-share-grow-order.md` (v4, after both rounds and the B-pass). Fix tier M (the diff touches `lib/core/router/app_router.dart`, outside the S filter), blast-radius `account` (`lib/core/**`), inline execution.

## Review rounds
- **R1** — fresh Sonnet context, read-only (157 tool calls), on the v1 plan and the staged draft. Verdict **harden**; no P0/P1. 12 findings: 4 × P2 (the gate pin used first-occurrence `indexOf` and stayed green with a second ungated push while the plan said the gate cannot be run in a test; a stale "still PRO-gated at tap" comment; the Progress route's missing gate had no terminal state; plan numbers), 8 × P3. All folded into v2, with one reviewer claim corrected on the way (it said no widget test pumps `PaywallSheet`; `test/widgets/swap_picker_sheet_test.dart` does).
- **R2** — fresh Opus context, a different reviewer, read-only (138 tool calls), on the post-R1 plan and diff. Verdict **converged**; no P0/P1/P2. 10 × P3: wrong line numbers in v2, a false "not pinned" claim about the feature constant (the real gap was the gate BRANCH), hook order in the new test, four more device tests with the same dead scroll step (one of which could not pass), the hub's registry reader row, the double-tap label, a missing real-route-table test, a dead widget chain that could be deleted mechanically, ledger hygiene. All folded into v3.
- **Converged-after-fold is a SELF-ATTESTATION, not a third review.** No third round was run: both reviewed rounds are done, round 2 found nothing above P3, and the B-pass reviews the real final diff (including the folds R2 asked for: the real-router test, the dead-code deletion, the six device-test edits).

## Ground truth
- Code, read at the base `c2bb0f75` and the staged tree by both reviewers and the main thread: the Profile source and its section order, the router, the destination screens, `SubscriptionService.gateAndVerify` / `verifyFromServer`, the go_router 17.2.3 and flutter_test sources (shell push semantics, `scrollUntilVisible`), the `integration_test` helpers.
- No live system was read or written: no database, no Edge Function, no network call. The R1-04 facts (free daily cap, RLS policies) are from the repo's migrations and code; the `progress-photos` storage-bucket policies are not in the repo and are said to be unverified.
- Run, not just read: the covering test files, the whole suite (re-run on the final tree before the commit; counts in the commit message), `flutter analyze` of the whole repo, the whole pre-commit gate loop, and two mutation rounds: 33 mutants against the first tests (all red), then 54 against the strengthened ones (53 red, 1 behaviour-equivalent by design).
- Not verifiable here: anything on a device or in a browser; the six edited device tests.

## §4.6 disposition (CLAUDE.md feature-flag protocol)
**Not applicable.** No payment / sync / auth / AI-prompt / plan-generator change: a UI re-arrangement of existing destinations; the Progress gate is the same `gateAndVerify` call with the same feature constant. Rollback is a revert of the merge commit.

## B-pass (self-initiated before the merge, CLAUDE.md §4.3)
`docs/reviews/profile-share-grow-order-bpass.md`: two context-blind reviewers (A: the read-only lenses; B: lens 6 by mutate-and-run in a scratch copy). Reviewer A found no P0/P1/P2 and six P3; reviewer B's own mutants left **13 of 21 green** against the first tests (three P1, three P2, four P3). All sixteen findings are test-strength or wording findings, none in product code, and all are folded; the strengthened tests were re-proven by a second mutation round (53 of 54 red; the one green mutant is a behaviour-equivalent route-order move). `bpass: accepted` is claimed above only after that file exists with every finding in a terminal state in `docs/audit/profile-share-grow-order.closure.yaml`.
