---
branch: nutrition-history
scope: Nutrition History screen (since-day-one trends), a local target history, one shared resolver of shown targets, and clean-ups C1-C5 (Landing A; no cloud change)
blast_radius: account
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ec84affa06db-review.md
---

# Plan-review record — Nutrition History (Landing A)

Plan: `docs/plans/nutrition-history.md` (sections 11, 12, 13 are the revisions; each overrides
what precedes it). Four context-blind rounds, one Sonnet reviewer each, read-only, each on the
plan as revised after the round before. Every claim the coordinator acted on was re-read in
the code first.

## Round 1 — needs-changes (4 P1, 10 P2, 6 P3), folded as plan section 11
- P1 a legacy `target_override_<date>` row carries a `date`: "logged" must be narrower than
  "counted" or such a day reads as a logged zero.
- P1 the raw-key pin test allow-lists files by path and fails on a stale entry: the resolver
  move needs it repointed.
- P1 today and a one-snack day would count against averages, hit-rates and runs: day classes
  (in progress / partial / complete) added.
- P1 ground truth: no `flog_` key; the restore writes the profile with `skipSync` (not a
  `_fireSync` site); two direct profile writers exist (neither changes a target).
- P2 restore and water-override triggers, provider freshness, join-date header, slot
  vocabulary, existing aggregators, top-food key, existing tests the moves break.

## Round 2 — needs-changes (5 P1, 7 P2, 5 P3), folded as plan section 12
Resolver imports (it uses `BmrCalculator`, no feature import); no-target mode; the hook must
sit inside the lock and never rethrow; the exact C3 deletion list; ledger rows from the real
engine shape. Found a pre-existing bug in the weekly cards (C5, diagnose d7b3f1).

## Round 3 — needs-changes (1 P1, 6 P2, 5 P3), folded as plan section 13
P1: the planned ownership guard used a `@visibleForTesting` function. Two mechanisms that kept
producing findings were REMOVED rather than patched: the water field of the history (it would
have written an entry at nearly every weigh-in) and the ownership guard (the history is written
to the same per-owner box as the profile it describes).

## Round 4 — converged (0 P0/P1, 1 P2, 4 P3), folded as plan U12
Explicit withdrawals of the superseded water rows; raw-key pin outcome stated per file.

## Deviations at build (recorded, not re-reviewed; in scope of the B-pass)
- `nutritionHistoryProvider` is NOT in `profileDerivedSurfaceProviders`: it watches
  `macroTargetsProvider`, which is. The list test pins 7 / 6, not the plan's 8 / 7.
- The history files are `widgets/history/history_common.dart`, `history_trend_chart.dart`,
  `history_heatmap.dart`, `history_sections.dart`, `history_day_sheet.dart` (the smaller
  sections share one file).
- Charts are painted (`CustomPaint`), not fl_chart: one widget per chart instead of a bar chart
  and a line chart stacked.
- `NutritionRepository.mealsForDay` returns an empty list when no session is open.
- S12's timing bound is 400 ms on the 4-core VPS for 730 days x 4 meals (plan said 150 ms; not
  measured below that on this machine under a test runner).

## B-pass — accepted (0 P0/P1, 2 P2, 6 P3), all fixed in the branch
`docs/reviews/ec84affa06db-review.md`, one fresh seat on the CI-green head ec84affa. Fixes:
a failing history put is recorded; future-dated entries are dropped instead of blocking;
strict day keys; a ten-year floor on the series; a zero calorie target judges nothing; a
"Low protein" status and a text twin for the heatmap; seven registry cites re-derived.
