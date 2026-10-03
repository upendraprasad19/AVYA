---
branch: workout-idkey-variety-11
plan: docs/plans/batch11a-idkey-hardened.md
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/3c9f18f0d42d-review.md
---

# Plan Review — Batch 11-A (W3.3 forward-only, Hive-local ID-keyed exercise history)

§4.12 ×2 context-blind pre-implementation review + a ground-truth audit, then a
self-initiated ≥platform B-pass before the merge. Batch 11 (W3.3 + W3.4 variety +
①.1d injury-sub) was SPLIT into three sub-units; this branch ships **11-A (W3.3) only**
(11-B variety + 11-C injury-sub get their own branch + fresh ×2 — the cascade-seam
reviewer for those items did not converge in this session, so they are explicitly
decomposed out, NOT deferred). Item scope: add a forward-only library `exercise_id`
to `exlog_*` rows + an INCLUSIVE id-OR-name match in `ProgressionResolver`, behind
ship-dark `enable_exercise_id_history` (default OFF → name-only, byte-identical).

## Round 1 (context-blind, on the initial plan)
- **Reviewer A — P1 (folded):** id-keying `TrainingHistoryAnalyzer` would break it — it
  keys volume on a name-keyed `taxonomy[name]`, so an id-key → null → dropped volume.
  **Resolution:** EXCLUDE `TrainingHistoryAnalyzer` from id-keying (keep name-based); only
  `ProgressionResolver` gets the inclusive id-OR-name match. Verified against the analyzer
  source this session (still name-keyed, untouched by the diff).
- **Reviewer B (cascade seam) — did not converge** (session limit). It was scoped to the
  11-B/11-C cascade/variety/injury-sub items, NOT 11-A → 11-A ships alone; 11-B/11-C get a
  fresh ×2 on their own branch.

## Round 2 (on the hardened plan)
- **P2 (folded):** the write ships largely inert if `ExerciseData.copyWith` (fired ~1×/sec by
  the elapsed-timer) drops `exerciseId`, and if the swap reconstruction drops it. **Resolution:**
  thread `exerciseId` through copyWith (preserve: `id ?? this.id`) + the active-workout log call
  + the swap reconstruction. Applied + pinned by the behavioral test.

## Ground-truth audit (verified against the actual files this session)
- Cloud `workout_log_exercises.exercise_id` is NAME-derived (`sync_workout.dart:198`,
  `log['exercise_name'] ?? key`) and is the onConflict natural key — the Hive library id must
  NOT leak upward (→ duplicate rows). Pinned by `sync_exlog_no_library_id_test.dart`.
- `_restoreExerciseLogs` reconstructs the Hive row WITHOUT `exercise_id` → restored rows fall to
  name-matching (forward-only-coherent). No migration / no restore entry needed.
- `ExerciseRepository.getAll()` seed rows already carry `id` (Hive key == id) → the manual
  swap/add id-threading (B-pass fix) is a real win, not dead plumbing.

## B-pass (self-initiated, ≥platform, before merge)
`docs/reviews/3c9f18f0d42d-review.md` — 1 P1 (manual swap/add UI paths dropped the id),
**fixed in-batch** (threaded the id through all three builders + `SwapExerciseData.id` + a drift
guard). All other lenses clean after ground-truth verification (flag-OFF inertness, Hive-local
invariant, sticky write, coach path, graded-union dedup). verdict: accepted.

## Convergence
Two rounds; each surfaced exactly one material issue, both folded; the B-pass surfaced one more,
fixed in-batch. No new material issue on the hardened + fixed plan → **converged** for 11-A.
