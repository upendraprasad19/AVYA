---
branch: library-batch-c2
date: 2026-11-05
blast_radius: platform
review_rounds: 3
mechanical_only: true
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/library-batch-c2a-bpass.md
---

# Plan-review record: Library Batch C2a (removals, production-name repoints, one cloud deactivation)

Keystone record for the section 4.12 merge gate (`check_plan_review_record_exists.dart`).

Plan: `docs/plans/2026-11-04-library-batch-c2a-removals.md` (r4). The earlier C2 plan did not converge after two rounds (17 items), so it was split: this batch is the removals only; the twins, the E230 retag and the media are C2b (OI-462).

## Rounds

- Rounds 1 and 2: context-blind reviewers verified every claim of the plan against the code and the live state; round 2 ran on the plan hardened by round 1. Both found material items (the depth rule not seeing the uninjured cell, the cloud deactivation shape, the seed v18 prune that must not feed `retiredLibraryIds`, the committed base-depth fixture because CI uses a depth-1 checkout).
- Round 3 (the plan at r4): mechanical items only, so `mechanical_only: true`; no new design question.

## Founder decisions in the plan

E293 is removed with E291 as its replacement; a removed name that differs from its replacement becomes an alias on the replacement row; G1429 `progression_to` points at G3418. The cloud apply is a live step with its own explicit go on the exact migration file.

## Build and B-pass

Built in `library-batch-c2` from base 80a9bc2d; merged with `origin/main` on 2026-11-05 (conflicts resolved: the generator golden re-recorded on the merged tree, the injury sweeps re-measured with one recorded ceiling rise, `repeat bodyweight` 0 to 4 thin days). B-pass: `docs/reviews/library-batch-c2a-bpass.md` (6 findings, triaged; fixes in commit 14cd036b). Gate loop: whole-project `flutter analyze --no-fatal-infos` clean, the full suite and the pre-commit loop run before the merge with main, the five injury sweeps and the affected contract tests re-run after it.
