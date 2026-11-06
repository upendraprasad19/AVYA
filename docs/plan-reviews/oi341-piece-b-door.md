---
branch: oi341-piece-b-door
plan: docs/plans/oi341-piece-b-door.md
date: 2026-10-20
blast_radius: catastrophic
tier: ship_dark_build
review_rounds: 1
mechanical_only: true
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/5f77a4654f04-review.md
hermes: accepted
hermes_report: docs/audit/2026-10-20-hermes-oi341-piece-b-door.md
---

# Plan review - OI-341 Piece B1, the serialised stacking writer and the payment alert (dark)

Founder decisions: 2026-10-13 (purchase during the referral trial, paid time stacks); 2026-10-20 answers 1-6 (the quiet
precondition waived; serialise concurrent payments per user on the server; the door, copy and test-mode purchase are B2);
2026-10-20 "all approved" for: apply migration 161 + the read-only checks, the commit, push and PR, the verify-payment deploy
and the razorpay-webhook deploy. NOT covered: the merge (it goes through `scripts/safe_pr_merge.sh` once CI is green), setting
`ENABLE_SUBSCRIPTION_STACKING`, and anything in B2.

## Tier (CLAUDE.md 4.12.4)

`ship_dark_build`, `review_rounds: 1`: B1 is a catastrophic-tier build behind the EXISTING default-OFF switch
`ENABLE_SUBSCRIPTION_STACKING` (exactly "true"), with behavioural golden tests proving the OFF path equals the `origin/main`
writers. The full x2 review is required again on the commit that flips the switch (B2); logged in
`docs/ship_dark_pending_review.yaml`.

## Review rounds

- **Rounds 1-3 (history of the UNSPLIT unit, v1-v3):** each surfaced new P1s (round 3: removing the switch broke CLAUDE.md
  4.6, an unprobed PostgREST dependency on every payment, a circular equivalence test). Under 4.12.1 the unit was SPLIT into
  B1 (this) and B2 (the door, client, flips). Dispositions: plan sections 7 and 8.
- **Round 4 (B1's build review, context-blind, on v4):** 0 P0, 0 P1, 4 P2, P3s; all folded into v4.1, which is plan-text and
  test-design only (`mechanical_only: true`; plan section 8b). A mechanical check of the v4.1 edits passed.
- **B-pass** (`docs/reviews/5f77a4654f04-review.md`, reviewed at staged `6c6327e7ae5f`; the name moved only because the
  post-review migration ledger entry and live-step closure rows changed the staged hash): two fresh Sonnet seats on the BUILT
  tree, 0 P0 / 0 P1 / 2 P2 / 5 P3. Fixed: an omitted webhook `order_id` would drop `p_order_id` and miss the function (killing
  tests in both layers); overstated SQL "Kills" claims; a vanished conflicting row is now retryable 40001 (R16, mutant M21);
  the year-10000 base edge (R11b, M13b). Ledger rows `BP-*`.
- **Hermes pass** (`docs/audit/2026-10-20-hermes-oi341-piece-b-door.md`, accepted): 4 Sonnet seats, 9 lenses, run AFTER the
  B-pass fixes. 0 P0 / 0 P1 / 0 P2 / 8 P3. Fixed: the alert header's false latency claim; a live arbiter read added to step 6.2.
  Filed: OI-359, OI-360 (pre-existing OFF-path code the byte-identity proof forbids touching). Ledger rows `H-*`.
- **Convergence, stated plainly.** v4.1 was not re-reviewed as a plan; the B-pass and hermes pass read the built tree and found
  no P0 or P1 in the design.

## Ground truth

- Code: both writers, `_shared/subscription.ts`, migrations 010/052/076/094/133/138/140/152/159/160 read for the
  `subscriptions` and `alerts` columns, constraints, triggers and the advisory key (B-pass seat A, hermes seats 2 and 4).
- Replica `rpoc-pgtest` (replica schema + 159 + 160 + 161): `test/sql/record_paid_subscription_local.sh` R1-R16, C1-C4
  SUMMARY ok; 22 of 22 migration mutants killed (M09 after R8 learned to check the denial MESSAGE).
- Deno: 78 passed across the four touched test files; the test agent's mutation table killed every mutant but one equivalent.
- `flutter test` (TZ=Asia/Kolkata, golden excluded) before the apply: 9918 passed, 1 failed = `applied_migrations_parity_test`
  (161 not yet applied); after the apply and the ledger entry that test passes.
- **Live, 2026-10-20** (MCP on `dedsavbjuwgarrhphgnl`, project id confirmed): pre-apply latest migration 160, function absent,
  `UNIQUE (razorpay_payment_id)` the only unique constraint, service_role SELECT + INSERT + BYPASSRLS, statement_timeout 8 s via
  `authenticator` (above the 5 s lock_timeout). Applied as cloud version `20261020073701`; ACL `{postgres=X,service_role=X}`;
  `md5(pg_get_functiondef)` = `d329fa83766ee2a97121d91f2786ee69`, equal to the replica install. PostgREST probe:
  service_role HTTP 400 22023 `invalid_plan`; anon HTTP 401 42501.
- **Deploys, 2026-10-20:** rollback payloads (Piece A, v25 / v29, archive `*_a8d9eeb.json`, both containing `resolveEndDate`)
  copied to the session scratchpad first. `verify-payment` v26 (verify_jwt true): anon-key probe -> the module's own 401
  `Invalid or expired token`. `razorpay-webhook` v30 (verify_jwt false): no-auth probe -> `Missing x-razorpay-signature
  header`. Read back via the management API: v26 / true, v30 / false, both ACTIVE; `ENABLE_SUBSCRIPTION_STACKING` and
  `ENABLE_TRIAL_PURCHASE` NOT set.

## What this record does NOT claim

No live ON-path call (the switch is unset; nothing calls the function), no live payment since the deploys, no PR CI run yet,
and nothing about B2 (the door on `create-razorpay-order`, the client, the flips, the rollback order, the Razorpay
retry-timestamp and response-timeout checks, the first live stacked purchase).
