---
branch: coach-workout-parity
scope: Coach workout parity slices 1a (one shared completion-bookkeeping step for every door, OI-379) and 1b (stricter chat-card completion rule + Train "Logged so far" + Complete button); merged together
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
---

# Plan-review record — coach workout parity (1a + 1b)

This branch merges two plans in one PR (1a plan §4: 1a alone would let the chat card's mark-on-any-save count a one-exercise day, permanently).

## Slice 1a: `docs/plans/coach-workout-parity-1a.md` (rev 4)

Three context-blind Sonnet review rounds, each with an exhaustive read-only command list.

**Round 1** (rev 1; A ground truth, B exposure). Both reviewers returned `needs-changes`.
- P1s:
  - `newlyCompleted` excluded rest, paused and terminal rows, so Active Workout stopped counting days it counts today (A-F1, B-F1, B-F7).
  - A +1 lost to a crash could never heal (B-F2).
- P2s: the success gate, the kill switch's false "exact restore" claim, backdated and non-IST dates, the hold-gate contract, and the repoint list.
- Folded into rev 2: the plan's §7.

**Round 2** (rev 2; A, B). Both reviewers returned `needs-changes`.
- P1s:
  - 1a alone over-counts permanently through the chat card. Fix: merge 1a and 1b together (B).
  - Legacy `wlog_<ms>` duplicates double a day. Fix: count distinct dates (A).
  - The owner was captured after the `logExercise` awaits. Fix: capture at entry (A).
- P2s: the restore-unsettled partial schedule, the writeservice allowlist, the helper's location, the null-progress mint, and masked mutations.
- Folded into rev 3: §8.

**Round 3** (rev 3; delta, both lenses). **CONVERGED** (no P0/P1).
- P2/P3 folded into rev 4 (§9):
  - the wlog clause on `newlyCompleted`;
  - the owner re-check;
  - the offline cost stated;
  - the record scope and push order;
  - the test seams;
  - the date precedent.

**Ground truth verified.** Every door, line and helper was checked against code by A in rounds 1 and 2 and re-checked in round 3:
- `markCompleted` lock and pre-write read: `workout_write_service.dart:596-631`.
- Hold-gate equivalence: `train_provider.dart:1071-1099`, against `activeHoldOrdinalFor`.
- `updateProgress` atomicity and sync: `user_repository.dart:1005-1018`.
- Synchronous reckon: `workout_repository.dart:336`.
- Every `type:'workout_log'` writer under `wlog_`: `workout_write_service.dart:647`, `sync_workout.dart:938`/`:1308`, `workout_repository.dart:763`, and the backfill migrator.
- The cloud ratchets: `weekly-recalc` `Math.max`, migration 156 `GREATEST`, and restore max-wins at `user_repository.dart:440`.

## Slice 1b

Pending: its own ×2 review is recorded here before the PR is opened.
