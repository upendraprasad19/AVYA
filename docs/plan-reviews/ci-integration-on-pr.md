---
branch: ci-integration-on-pr
date: 2026-11-25
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ci-integration-on-pr-bpass.md
---

# Plan-review record: integration tests on pull requests (OI-527), fixture rebuild after a lost status (OI-528)

Plan: `docs/plans/2026-11-25-ci-integration-on-pr.md`. Tier M, blast radius platform (the workflow, the merge
tooling, test helpers). Execution mode: inline.

Two context-blind Sonnet plan rounds, the second on the post-round-1 text:
- Round 1: 0 P0, 4 P1, 5 P2, 1 P3, all adopted (plan section 6). It changed the design: a missing check-run for
  the job now refuses (new class `prTimeSkippableJobs`), both retry loops are counted.
- Round 2: 0 P0, 2 P1, 5 P2, 6 P3, all adopted; both P1 were completeness (a test fixture, the fallback's effect
  on `main`), no mechanism changed; converged (plan section 7).

Ground truth: plan section 1 was measured on the day (the six red `main` job logs, run ids in the plan; the code by
file:line; GitHub's concurrency documentation).

Code review: `docs/reviews/ci-integration-on-pr-bpass.md` on `37adbd98` (0 P0, 0 P1, 2 P2, 5 P3; the P2 and one P3
fixed, four notes accepted). Full suite: the pull request's CI (run 45531579264), in which the integration job ran
on a pull request for the first time, green, both test steps.
