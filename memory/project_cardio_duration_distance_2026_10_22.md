# cardio-duration-distance: cardio keeps its minutes and km (OI-389 Batch 1a; closes OI-380, OI-382) · 2026-10-22

Branch `cardio-duration-distance` (worktree, base `cbfa8884`) · plan `docs/plans/cardio-duration-distance.md` rev 12 ·
record `docs/plan-reviews/cardio-duration-distance.md` (7 rounds + 2 delta rounds, converged) · closure
`docs/audit/cardio-duration-distance.closure.yaml` · diagnose `e7240a`. **Not committed yet**: commit and push wait on
the founder's ask (§4.3).

## What shipped (in the worktree)

- One type table `fieldsClearedFor`; `ExerciseSet.distanceKm`; `logExercise` resolves the type over existing ∪
  incoming (library → slot hint → stored cardio/distance → shape), normalises both sides before dedup, writes
  `distance_km` = Σ per-set only when > 0; bounds 0..21600 s / 0..300 km (OI-382).
- D2 (founder): the MIN box takes decimal minutes, converted to seconds once at capture; the edit sheet takes
  decimals too and refuses malformed minutes instead of saving 0.
- Every reader through `aggregateDistanceKm` and `cardio_format.dart`; PRs carry their unit (no more "1800 km").
- The move merge reads each side's longer per-set list and drops a stale `sets_detail`.

## Splits (founder D9/D10, 2026-10-22)

1b coach paths (OI-389 stays open) → OI-391 cloud cap → OI-392 coach `logCardio` → OI-393 restore-shaped totals
reset → OI-394 live heal. The AI snapshot cardio fields wait on founder D4.

## Lessons

- Two silent-loss shapes: `memory/feedback_normaliser_else_branch_and_lazy_cast.md`.
- A founder decision mid-batch (D2 decimal minutes) took two delta review rounds; the first found that the card
  still captured with `int.tryParse`, so "12.5" would have saved nothing. A decision change touches every consumer
  of the value, listed by name.
