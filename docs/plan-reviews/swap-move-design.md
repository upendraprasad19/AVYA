---
branch: swap-move-design
date: 2026-10-21
blast_radius: account
bpass: accepted
bpass_review: docs/reviews/215812fec86a-review.md
review_rounds: 3
ground_truth_verified: true
verdict: converged
---

# Plan-review record — in-workout ⇄ swap / ⇅ move (`swap-move-design`)

Founder request (chat 2026-10-21): the active-workout card header gets ⇄ swap and ⇅ move icons;
⇅ then tap a target slides the exercise there for this session only, with UNDO; a per-account
first-use hint; swap keeps the slot's superset group; superset groups persist by identity.
Spec: `docs/superpowers/specs/2026-10-21-active-workout-swap-move-design.md`. Plan:
`docs/plans/active-workout-swap-move.md`. Weekday swap (Unit 2) is out of scope.

## Rounds

Each round was fresh and context-blind, and verified claims against the code. Every fold-in is
listed in the plan's "Self-review" section.

- **R1:** NOT converged. Material items: UNDO had to be the inverse move (not a snapshot);
  `applyExerciseMove` had to refuse during `_completing`; `supersetGroupingSourceIndex` was missing
  from the remap; move-mode tap routing was undefined; a stale index-keyed swap-UNDO snackbar
  could act on the wrong exercise after a move; the hint lost state and re-persisted; warm-up sets
  vs `completedSets`; the screen was untestable until the controller seam existed; the swap's
  group carry was presence-only (moved into the notifier, behavioural).
- **R2:** NOT converged. Material items: review-mode and save-window guards plus the
  `applyExerciseMove` return value; group mode cleared on apply; a per-role icon table (done
  chip/plate inert in move mode); the hint was burned before it was shown (`_hintWasShown`);
  `hideCurrentSnackBar` via the messenger; stale build-captured `data`; motion handling in
  `didChangeDependencies`.
- **R3:** converged. No blockers; plan-text items only (single-valued highlight timing, a
  false undo-test claim reworded, dead controller API removed, hide-snackbar moved after a
  successful apply, hint gated on group/review mode).

## B-pass

`docs/reviews/215812fec86a-review.md`: 0 P0, 1 P1, 4 P2. Four were fixed with mutation-proven
tests (UNDO leaves move mode; no half-stored superset pair; id matches before name matches; a
stale move result is refused). One false alarm was disproved by measurement.

## Rebase after convergence

The branch was rebased onto `origin/main` `5f5160bf` (the LOG flip, PR #135) before building.
That added one index-keyed field, `suggestedInputs` (`ex-set-field` keys), which the move now
remaps, with its own mutation-proven test. `reopenedExercises` is keyed by name and needs no remap.
