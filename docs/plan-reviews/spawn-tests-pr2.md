---
branch: spawn-tests-pr2
date: 2026-10-07
blast_radius: feature
review_rounds: 5
ground_truth_verified: true
verdict: converged
---

# Plan-review record — PR 2 of `spawn-tests-env-and-stderr`: every remaining spawn test goes through `test/helpers/spawn.dart`, and the site guards become strict

Founder decisions 2026-10-06 (items 1 and 3, scope answer "Shared helper, 2 PRs"); OI-317. Plan: `docs/plans/spawn-tests-pr2-migrate-remaining.md` (v6, after five rounds). Fix tier M (`test/` only, far above 100 lines, many files). Blast radius `feature` (no path of this PR is in a platform tier; `docs/blast_radius.yaml`).

## Review rounds
- **R1 to R3**: three context-blind reviewers, each on the plan as left by the previous round, each verdict `harden` (R1 census and guard holes; R2 3 P1 + 9 P2 + 3 P3; R3 2 P1 + 8 P2 + 3 P3, none in the migration design). Every finding was re-derived against the tree before folding; none rejected. The plan's top tables list each finding and where it landed.
- **R4**: a fourth reviewer on v5, verdict `harden` (5 P2, 2 P3, no P1, none in the migration design): the poison values `PUSH_BEFORE` / `GITHUB_EVENT_PATH` were invisible, the base-arm locators made every `override_present` line `yes`, step 0 must be committed before the detached unit trees exist, the `spawn-guard-quote` marker was copyable, time-limited tests flake under wave load, `spawn_helper_test.dart` needed a G3 allow-list entry, plus nits. All folded into v6 (R4 table).
- **R5**: a fifth reviewer (Sonnet, read-only, exhaustive command list) on v6, a CONFIRMATION round. Verdict `converged`: no P0, P1 or P2; every R4 row confirmed against the code (`check_plan_review_record_exists.dart:332-361,408-410`, `spawn_helper_test.dart:206/215`, `git ls-files test` = 1052 `.dart`); two wording points (a leftover log name, and a migrated-arm-only statement for `plan_review_record_gate_e2e_test`) applied before this record.
- Rounds R1 to R4 used reviewers chosen before the founder's Sonnet-only rule of 2026-10-07; R5 ran on Sonnet.

## Ground truth
- Code read at the base (`e672816b`, PR #81 merged): the helper `test/helpers/spawn.dart`, its tests, the manifest, 1052 test files by a `blankDart`-stripped census (50 files, 120 sites), the gate scripts the poison variables reach.
- Run, not just read, in earlier rounds: the census scan and the stdin-site census; the D6 poison design was checked against the scripts' own reads of each variable.
- Not verifiable here: Windows (the same stance as PR 1).

## §4.6 disposition
**Not applicable.** Test code only; rollback is a revert of the merge commit.

## B-pass (§4.3)
**Not required** at `feature`. The strict guard, the per-unit measured poison runs (D6), the CI-like runs (D8) and the full suite are the verification.
