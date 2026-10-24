---
branch: oi341-piece-b2b-client
plan: docs/plans/oi341-piece-b2b-client.md
date: 2026-10-22
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi341-piece-b2b-client-bpass.md
---

# Plan review - OI-341 Piece B2b, the client half of a stacked trial purchase

Founder decisions: 2026-10-13 (a trial user may buy; the paid cycle starts when the free days end), 2026-10-20 (the
paywall and checkout notice, verbatim; no Profile door; keep "RENEW TO STAY PRO"), 2026-10-21 (order: build B2b first,
NOT merged; one live session: B2a steps 1-3, 4a door, the B2b merge, 4b the stacked purchase through the new web client,
then refunds; then the AAB with the live key ID). Commit, push and merge are each a separate go; B2b must not merge
before step 4a. The `trialUpgradeUnavailable` wording awaits the founder's sign-off (closure ledger
`B2B-COPY-SIGNOFF`).

## Tier (CLAUDE.md 4.12)

Platform: `supabase/functions/CLAUDE.md` (`supabase/functions/**`) lifts the diff; the code itself is account
(`lib/core/services/**`) and feature (`lib/shared/widgets/**`, `lib/features/**`). Payment client, so tier L: full x2
review, B-pass required (platform). No kill switch (CLAUDE.md 4.6 deviation stated in plan section 0: the server door is
the rollback; with no `stacks_after` the estimate and the checkout options are byte-identical to today). No hermes
(below catastrophic).

## Rounds

Two rounds of context-blind Sonnet review, each verifying the plan's claims against the code; dispositions are in the
plan, sections 7 and 8.

- Round 1 (v1 -> v2): 1 P1 (the plan called B2a "deployed dark"; it is merged, not deployed) + 8 P2 + 5 P3.
- Round 2 (on the post-round-1 plan, v2 -> v3): **0 P0, 0 P1**, 9 P2 + 6 P3, all mechanical; verdict CONVERGED.

## Ground truth

Verified against `47cb142c`: the server door's `stacks_after` and 409 shapes (`create-razorpay-order/index.ts`), the
PostgREST timestamp shape (`_shared/subscription.ts`, a Deno fixture), the plan name in migration 159's
`private.grant_referral_days`, the trial user's paywall entry (the Home expiry banner), the local plan's source
(`refreshFromSupabase` / `verifyFromServer`), the B2a closure ledger's deploy rows (`blocked_on_user`).

## Build evidence

Full gate loop before the B-pass: `flutter analyze lib/` (0 warnings or errors), full `flutter test` in IST with
`--exclude-tags golden` (10379 passed, 9 skipped), pre-commit gate loop with `PRE_COMMIT_GATE_JOBS=1` (OK), context
budget PASS. Mutation: 32/32 author mutants red (one paywall mutant first survived a looped widget test and was made
red by one state per testWidgets); after the B-pass fixes 42 distinct mutants red.

## B-pass

`docs/reviews/oi341-piece-b2b-client-bpass.md`: two fresh read-only Sonnet seats; 0 P0/P1, 3 P2 + 12 P3, all fixed or
verified clean, `verdict: accepted`.
