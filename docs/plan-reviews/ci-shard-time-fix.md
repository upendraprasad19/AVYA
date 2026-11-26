---
branch: ci-shard-time-fix
date: 2026-11-04
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ci-shard-time-fix-bpass.md
---

# Plan-review record - raise the unit-test shard time limit (OI-461)

Platform tier only because `.github/workflows/test.yml` is graded platform in `docs/blast_radius.yaml`.
The change is one number, its pin, and the OI board move. No `lib/` or Edge Function code.

## Scope
`timeout-minutes` of the 4 unit-test shards 20 -> 30; pin in `test/contracts/ci_unit_test_matrix_shape_test.dart`;
OI-461 archived to `closed_issues.md`. Considered and rejected: rebalancing the shards (measured balanced).

## Review arc (2 rounds, section 4.12)
- **Round 1 (fresh Sonnet, context-blind, read-only).** No P0 or P1. One P2: my stated medians ("13 to 13.5 min,
  47 jobs") did not match the data. I recomputed from exact job timestamps: 13 runs, 52 jobs, per-shard medians
  13.4 to 14.1 min, 13.8 overall. Corrected in the workflow comment, the closing note and the commit message.
  Also verified PR 207 shard 1/4 cancelled at 20m15s (attempt 1 of run 41756304890) and that no other file encodes
  the old 20.
- **Round 2 (fresh Sonnet, on the post-round-1 commit).** No P0 or P1. Re-derived all 52 durations independently
  and confirmed every stated figure within 0.2 min; confirmed both cap hits had the test step cancelled with no
  failure first; read the code (not comments) for CI wait ceilings: `land_pr.dart` waits 60 min, `safe_pr_merge`
  has no wait, the gate job's 5 min covers only its own echo. One P2 wording fix: the headroom is "at least 10 min
  over the slowest completed shard (19.3)", because the two capped shards ran longer by an unknown amount. Folded in.
  P3 stale prose in dated plans (`docs/plans/2026-10-24-thin-day-topup.md`, `docs/plans/2026-10-25-library-batch-c-new-rows.md`,
  `docs/audit/speedup-b3-test-matrix.closure.yaml`) is historical as of those dates and left as written.
- **B-pass.** `docs/reviews/ci-shard-time-fix-bpass.md`: 2 P2, both fixed.

## Ground truth
Mutation: pin mutated to 20 and to 300, 1 test red each, mutation confirmed applied, restore confirmed.
Not run locally: full suite, analyze (CI on the PR is that gate).

**Verdict: converged.**
