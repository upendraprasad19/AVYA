---
branch: exlog-type-filter-readers
scope: Part P of docs/plans/coach-workout-parity-1c.md. Three Hive readers filtered exlog rows on a `type: 'exercise_log'` key that only the cloud restore writes, so they never saw device-logged workouts. Affected: the FINISH PR scan, the PR badge count and the Profile lifetime volume. They now read through one WorkoutReadService.exlogRows helper. The PR scan uses per-set maxima, and the badge counts a PR only when it beats the best from strictly earlier IST dates. Both surfaces use one rule.
blast_radius: account
review_rounds: 4
ground_truth_verified: true
verdict: converged
mechanical_only: true
bpass: accepted
bpass_review: docs/reviews/exlog-type-filter-readers-bpass.md
---

# Plan-review record: exlog type-filter readers (Part P)

Plan: `docs/plans/coach-workout-parity-1c.md`, Part P (rev 7). Part P was found in round 1 of the coach workout parity 1c review (seat A, A-F2: "the PR scan skips rows with no `type`"). It was folded in as its own unit per §4.2, then split into its own landing in rev 4 (§4.12.1). Every round used two context-blind Sonnet reviewers with an exhaustive read-only command list: seat A for ground truth, seat B for adversarial design.

## Round 2 (rev 2, first round with Part P)
Seat A verified the writer and readers. The only writer of `type: 'exercise_log'` is `sync_workout.dart:1082`. The readers are `train_provider.dart:2078`, `badge_service.dart:105` and `workout_repository.dart:1921`. Seat B found the badge side effect (B2-F1): the device writer marks a first-ever log `is_pr`, so first logs would unlock "First PR". Founder decision 2026-11-10: badges count only a PR that beats an earlier log.

## Round 3 (rev 3)
- A3-F1 (P1): the badge-loop mutant was invisible to pure-function tests. Fix: a real-Hive `checkAll` test.
- B3-F5: an earlier 0 kg row counted. Fix: require an earlier weight above 0.

## Round 4 (rev 4, Part P split into its own landing)
- B4-F2: per-set maxima, because the average-reps fallback would print false bodyweight PRs.
- B4-F10: the badge no longer trusts a stored `is_pr`, which a back-filled heavier row can make stale.
- Seat A found Part P clean.

## Round 5 (rev 5)
All findings were MECHANICAL:
- Gate 19 needs one `exlogRows` helper so no `'exlog_'` literal lands in `badge_service.dart`;
- reuse `bestPerSetReps`;
- one row-max definition;
- `exerciseNameKey` on both sides.
The round closes with `mechanical_only: true` (§4.12.6).

## Coordinator change after round 6 (R6B-F2, from the 1c confirmation round)
With 1c's re-open-and-append, the FINISH scan would compare against today's own coach row. Example: bench 100 kg logged in chat, then 105 kg logged in Active Workout, read as "PR (was 100)" for a first-ever lift. The scan now skips rows dated on the session date, so FINISH and the badge share one rule: beats the best from strictly earlier IST dates. Tests and mutant P12 cover it.

## B-pass
Accepted 2026-11-11: `docs/reviews/exlog-type-filter-readers-bpass.md`. One fresh Sonnet seat ran 3 mutants, all red. No P0 or P1. F1 (P2): the ban regex missed the pre-fix lifetime spelling. Fixed: the ban covers the quoted literal outside the restore writer's one map entry, with 3 mutants red. F2 (P2): the recomputed PR count can fall. Closed: badge unlocks are one-way.
