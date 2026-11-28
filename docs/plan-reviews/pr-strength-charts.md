---
branch: pr-strength-charts
scope: PR strength charts — sparklines on the Home PR tiles and the see-all list, a full trend sheet, and the PR list following a completed restore
blast_radius: feature
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record — PR strength charts

Plan: `docs/plans/pr-strength-charts.md`. Two context-blind review rounds (one Sonnet reviewer
each, read-only, the second on the plan as revised after the first). Feature tier, so the merge
seam does not demand this record or a B-pass; it is kept for the trail.

## Round 1 — needs-changes (4 P1, 6 P2, 5 P3), all folded (plan section 8)
- P1 `weightTrendWindow` is `@visibleForTesting` (an analyzer warning on a second production
  caller); `WeightTrendPoint` takes named `date` / `weight`.
- P1 "series max == PR, first max date == PR date" was false for legacy key order, an
  unresolved-day PR row, mixed units under one name. Redesigned: the series is derived from the
  PR list, filtered to the PR's unit, with stated invariants and a tie rule.
- P1 the moved switch must keep the raw-type pass 1, the `weight_reps` default in pass 2 and
  the nullable stored unit.
- P2 list sheet has no `WidgetRef`; 56 px spark did not fit a 155 px tile; provider test had no
  file; M2's fixture could not redden; B2 needed literals; several behaviors untested.
- P3 verified by the coordinator against `home_screen.dart:156-191` and
  `home_provider.dart:1097`: the PR list is not refreshed after a background restore. Fixed in
  this batch (plan 4.5).

## Round 2 — converged (0 P0/P1, 2 P2, 7 P3), all folded (plan section 9)
Tile spark moved to the number row; ripple needs a transparent `Material`; import cycle
accepted; two passes stated; resolved-day definition aligned with the PR reader; watch
placement; restore-tick test harness; tie across units; case-variant series test.
No counterexample found to the series/PR invariants.
