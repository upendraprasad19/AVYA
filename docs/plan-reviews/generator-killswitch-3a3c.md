---
branch: generator-killswitch-3a3c
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/generator-killswitch-3a3c-bpass.md
---

# Plan review: generator-killswitch-3a3c (delete the 3A and 3C kill switches, OI-514 / OI-516)

- **Plan:** `docs/plans/2026-11-17-generator-killswitch-3a3c.md` (v3.1).
- **Founder basis:** OI-514 / OI-516 ("delete after the device check", board t308). The founder's partial check of
  2026-11-17 covers 3A's reps and 3C's finisher days. The merge waits for the rest (plan §0).
- **Tier and blast radius:** tier L (plan engine; removing a kill switch takes the full x2 review, CLAUDE.md §4.12.4);
  blast radius platform.

## Review rounds

Fresh, context-blind Sonnet seats, each verifying the plan against the code. Measured data comes from runs on the base
tree.

- **Round 1 (plan v1):** not converged, 5 P1. All folded in:
  - missed `enabled` sites, including a lib/ compile break in `preview_plan_provider.dart`;
  - the S2 credit sweep;
  - an unworkable "move the fixture" for crafted fixtures;
  - self-referential re-records, replaced by the two-tree oracle;
  - a wrong gate list, with the goal-training OFF oracle kept on a frozen baseline.
- **Round 2 (plan v2):** not converged, 3 P1. All folded in:
  - `weekly_minimum_gate_test` sets the finisher key;
  - the day-floor tuples move with the pins;
  - no record path for the gate's OFF digests.
  - Before v3, every affected gate was measured on the base tree with the planned edits (plan §6). Every hard zero
    holds; only digests and the explained `rep30` tuples move.
- **Round 3 (plan v3):** converged (no P0 / P1). Its P2 / P3 items were folded into v3.1:
  - the record order and parallelism;
  - one fixture re-derived as seats;
  - seam resets, comments, headers.

## Ground truth

- **Seam measurements on 421cd2d2:** `oi489`, `repeat_minutes`, `goal_training_gate`, `weekly_minimum_gate` and the
  three day-floor gates, run with `CardioFinisher.debugReserve = false` in place of the finisher key. The results are
  in plan §6.
- **Line references:** every lib/ line reference in plan §2 was spot-checked against HEAD by round 2.
