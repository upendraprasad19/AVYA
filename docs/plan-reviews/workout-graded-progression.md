---
branch: workout-graded-progression
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-graded-progression-bpass.md
---

# Plan review — workout-graded-progression (Batch 3b-ii: W2.1 graded double progression)

Item W2.1, the second half of Batch 3b (3b-i ⑦a decay shipped `cb1ec3c6`). Makes
`ProgressionResolver.resolve()`'s progress/hold/back-off rule rep-range-aware with a
2-consecutive-below-range back-off gate + a beginner auto-linear window, behind
`enable_graded_progression` (DEFAULT OFF, ship-dark). Blast radius **platform**. `feat`. Terminal.

## Review rounds (≥2, before code)

- **Round 1 (context-blind) → harden, keep as ONE unit.** Verified ground-truth (repRange on
  `populated`, profile keys, post-⑦a loop). 3 findings folded: **P1** — `onboarding_completed_at` is
  realistically null (restored phase-2+ profiles) → `DateTime.parse` throws → empty progression map; and
  a naive per-exercise profile read on the flag-OFF path would regress shipped ⑦a → structure
  `if(gradedEnabled){graded incl. profile read}else{verbatim 10/5}` byte-identical + `tryParse`. **P2** —
  de-dupe top-2 by CALENDAR DAY (legacy full-timestamp rows). **P2** — reuse ONE `parseRepRange` (not a
  2nd hand-rolled parser, #1 bug class).
- **Round 2 (context-blind, on the hardened plan) → harden ("one tightening pass to converged").** 2 P2s
  folded: **F1** — my "keep-heaviest tie-break feeds base/est1rm" clause would break byte-identical-OFF on
  legacy same-day dupes → DROPPED it; `lastSession` (single most-recent, verbatim first-seen tie-break)
  stays the SOLE base/est1rm source, the top-2 structure is ADDITIVE (ON-gate only). **F2 (reversed
  round-1's concern)** — verified EVERY real library `rep_range` reaching `_applyWave` is clean "N-M"
  (lo<hi; timed "30-60" early-returns), so the SHARED parser IS behavior-preserving (and removes a latent
  `clamp(lo>hi)` throw) → DO share it, gated by a `_applyWave`-invariance regression test (§4.11). F6 folded:
  the new flag getter has its OWN try/catch → false; profile read ONCE before the loop; `parseRepRange` in
  `models.dart` (periodization takes no dep on progression_resolver).

## Ground-truth verification (true — self-verified)

`PlannedExercise.repRange` present on `populated`; `getProfile()` → `fitness_experience` (lowercase RAW)
+ `onboarding_completed_at` (UTC ISO8601); `effectiveExp` widens at phase≥3 (so RAW is required);
`_applyWave`'s parse is per-part-fallback (`:181-182`) — I read it directly and confirmed the shared
whole-range-fallback parser only differs on malformed-with-dash inputs, none of which occur in the real
library (so inert); post-⑦a `base`/`est1rm` computed above the branch, clamp below (shared).

## Verdict: converged

Tests: `progression_resolver_graded_test` (11/11 — rep-range banding, 2-consecutive gate, same-day
de-dupe HOLD, beginner-linear window, null-onboarding no-empty-map, flag-OFF byte-identical),
`progression_resolver_decay_test` still 5/5 (⑦a path unchanged), `periodization_wave_reps_invariant_test`
(14/14 — parser inert), the `*_archetype_test` suite 160/160 green (apply output unchanged), Batch-0
scorecard no-regression, analyze clean. SoT `graded_progression`; plan_engine CLAUDE.md Stage-0 note.
B-pass on the diff accepted (docs/reviews/workout-graded-progression-bpass.md). No open issues.
