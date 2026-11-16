---
branch: generator-step4
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/generator-step4-bpass.md
---

# Plan review: generator-step4 (switch on volume titration and plateau escalation, OI-53)

- **Plan:** `docs/plans/2026-11-16-generator-step4-titration-plateau.md` (v3.1).
- **Founder basis:** d81 (Cut == Maintain 5 of 576 live accepted; the gate gains the live-world check), d82 (plateau
  escalation ships whole: the +1 set and the rotation); the rules restate d26-d29 (2A lead first, R2 / R5), d30-d33
  (2B day floor) and d65 (trim order, never below 2).
- **Tier and blast radius:** tier L (plan engine, a ship-dark flip: §4.12.4 requires the full ×2 review and the
  B-pass); blast radius platform. New kill switches `disable_volume_titration`, `disable_plateau_escalation` (default
  ON); `plan_generator.dart` untouched.

## Review rounds

Fresh, context-blind Sonnet seats, each verifying claims against the code and the measured data.

- **Round 1 (plan v1):** not converged; seat A (mechanism) 7 findings incl. P1 untested consumers; seat B (measurement,
  tests) 10 incl. P1 harness keys after the flip, the d81 live world absent, the ceiling's variant mapping, the test
  list. The declines-left-untrimmed finding was measured and T2 moved to d65's order with an R2 guard.
- **Round 2 (plan v2):** not converged; seat C (rules) 5 P2 / P3; seat D (gate, harness) 13 incl. 3 P1: every history
  scenario carries `weakMuscles()` focus groups (verified), the focus top, the T4 scenario. The harness was extended
  and re-run; the table restated in the gate's definitions (the v1 "61 over-top" were focus tops and floor seats).
- **Round 3 (plan v3):** converged (0 P0 / P1); 5 P2 / P3 folded into v3.1 (the KILLED identity world, mixed's
  non-vacuity, the focus pin measured at 48 on flat, phases 2-3 only, a null-stash lead).

Ground truth: the history simulation (`history_sim_dump_test.dart`, 576 profiles x 3 scenarios) run twice on main
85bdcbbe; the T2 trim estimate (`t2b_estimate.py`); the d81 keys from the t304 dump; every file:line spot-checked by
seats C and E.
