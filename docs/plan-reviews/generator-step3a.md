---
branch: generator-step3a
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step3a-bpass.md
---

# Plan review: generator-step3a (Unit 3A, training follows the goal, OI-487 generator half)

- **Plan:** `docs/plans/2026-11-15-generator-step3a-goal-training.md` (built).
- **Founder basis:** d3 / d4 (2026-11-08); d56-d65 (2026-11-15): the rep table (d58 / d59), the focus rest at 60+
  minutes (d60 / d64), the rule-14 argument (d61), Maintain at two-thirds (d62), d63, the day-floor amendment (d65);
  d66-d68 (review round 1): the injured-plan group loss and the Glutes bookkeeping accepted, the effective level.
- **Tier and blast radius:** tier L (plan engine), blast radius platform. Kill switch `disable_goal_training` (OFF
  equals main over the 1,010 golden personas; deletion OI-514).

## Review rounds

Fresh, context-blind Sonnet seats, each verifying claims against the code and the built diff, CI green on the head.

- **Round 1 (two seats, on 91bbaf68):** seat B's P1, a group trained OFF going to 0 ON in injured Cut / Maintain plans
  (measured: 36 of 3,072 single-injury plans; 2.3-4.2 % of two-injury plans), went to the founder, who accepted it
  (d66, re-confirmed with the corrected numbers), with d67 and d68. Seat A: d65's attribution (the day-floor gates pass
  on main's pins with goal training off and d65 kept), doc and comment fixes, the audit harness's OFF band.
- **Round 2 (two seats, on f85e4af6):** no P0 / P1; every round-1 fix verified. Two missed pins (the week-2 focus price,
  B's `floorTrims` copy) added and mutation-proven; the donor-order mutants shown equivalent; P3 doc fixes. Converged.
- **B-pass (two seats, on 912aeacd, CI green):** no P0 / P1; two missed pins (weeks 2-4 of the goal reps, the trim's
  time credit) added and mutation-proven, a stale SoT cite, comments, consequences (`docs/reviews/generator-step3a-bpass.md`).

Ground truth: the gate (`goal_training_gate_test.dart`, 2,304 plans ON vs OFF and under the focus), the kill-switch
golden, the attribution runs (every moved neighbouring pin returns with goal training off), the mutation pass
(diagnose `675d02`), the injured sweeps behind d66, and the share table re-measured on f85e4af6; the neighbouring gates
ran locally before each push (bug class 2.162's last point).
