---
branch: generator-step2d
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step2d-bpass.md
---

# Plan review: generator-step2d (Unit 2D, a repeat phase with more minutes, OI-453)

- **Plan:** `docs/plans/2026-11-15-generator-step2d-repeat-minutes.md` (v4, built).
- **Founder basis:**
  - OI-453's hybrid design (2026-11-03): keep the pins, extra sets first, then appended accessories from the normal
    selector, no reshuffle.
  - d50 (2026-11-15): the rule-14 waiver for one pass-through argument in `plan_generator.dart`.
  - d52 (2026-11-15, asked after round 3 with the measurements): "sets first" is the allocator's own set targets,
    then accessories, not sets to the 5-set maximum.
- **Tier and blast radius:** tier L (plan engine), blast radius platform.
- **§4.6:** no new kill switch (d37). The step is reached only through a repeat, which `disable_adherence_gate` turns
  off. Every non-repeat generation, and a repeat at the same minutes, is byte-identical (the golden and the three
  kill-switch goldens are unchanged).

## Review rounds

Fresh, context-blind Sonnet seats (read-only; no tests run). Each verified claims against main 0c383703 (rounds 1-3)
or the built diff (round 4).

- **Round 1 (v1, two seats): not converged, 21 findings.** v1 ran the accessories inside the allocator's passes. That
  collided with holds, custom-only days, the opener, the 2A worlds, the 2C-b re-runs and the top-up. v2 moved the
  mechanism after the allocation.
- **Round 2 (v2, two seats): not converged; no P0, 3 P1.**
  - B-1: a reschedule patch would store minutes the pinned rows were not built at. Dropped.
  - B-4: gate cells a repeat cannot reach (build_muscle crossing 60 goes fresh). Pins are now derived through
    `repeatPinsFrom`.
  - B-5: the accessories would take week 2's +1 sets. Fixed with the reserve.
  - Also: `rose` moved inside `generateAndSchedule`; the step wraps both allocator branches; the B copy predicate;
    the seam gate.
- **Round 3 (v3, one seat): not converged; 2 P1.**
  - F1: an appended row could become the week-2 lead. Appended rows are now kept out of the lead.
  - F2: copied B-day seats skipped B's fit checks. Every variant is now seated on its own ledger.
  - P2s: the SameMovement source, the allowance stamp and alias, R3's direction, one `capToLead`. All folded into v4.
- **Round 4 (built diff, one seat): converged; no P0 or P1.** The seat traced the reserve's monotonicity, the visit
  order, pricing parity with `_variant` and `_weekTwoGains`, the seam count and d50's scope, and found them clean.
  P2 / P3 findings, all fixed in commit 2 of the branch:
  - two doc blocks attached to the wrong function;
  - the gate checked week 1 only: it now covers weeks 1-2, each extra's session cap and weekly top, and duplicates
    across the week, partners included;
  - the promised ledger-pricing test was missing: added, with a timed hold and a rep-based custom whose own rests
    differ from their archetype's;
  - two mutants were not run: M30 and M31 (diagnose doc).

`ground_truth_verified: true`: every round's cited `file:line` claims were checked against the code by the seat. The
measurements (the gate's 768 personas, the 2,304-plan flag-false goldens) come from runs on the built tree.
