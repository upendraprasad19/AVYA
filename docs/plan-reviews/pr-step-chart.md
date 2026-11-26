---
branch: pr-step-chart
scope: PR chart as a never-dipping step (tiles, see-all, sheet) with the lifted weight as its own line in the sheet
blast_radius: feature
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — PR step chart (592da4)

Plan: `docs/plans/pr-step-chart.md`. Two context-blind review rounds (one Sonnet reviewer each,
read-only, each dispatched after CI was green on the reviewed head: dbcb26d3, then 13b80f53; the
second on the plan as revised after the first). Feature tier, so the merge seam does not demand
this record; it is kept for the trail. Process note: the first draft of the code was written
before the plan (memory `feedback_fix_authorisation_is_not_a_tier_decision`); the reviewed plan
governs it.

## Round 1 — needs-changes (1 P1, 1 P2, 4 P3), all folded (plan section 8)
- P1, verified by the coordinator in fl_chart 1.2.0: the step line defaults to the MIDDLE, so the
  PR rose half-way before the day it was set. Now `stepDirectionForward`.
- P2 the tile / see-all sparks were slopes: optional `WardSpark.step` (default off, the other
  callers' path pinned).
- P3 UTC day maths; tests for the carry to today and the tooltip.

## Round 2 — converged (0 P0/P1, 1 P2, 4 P3), all folded (plan section 9)
Painter wiring test (recording canvas), shouldRepaint, a real DST case, PR dot and tint, legend
labels, the touch marker off the PR bar, the tier section refreshed. 17 mutants, all red.
