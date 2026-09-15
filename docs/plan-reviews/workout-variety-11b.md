---
branch: workout-variety-11b
plan: docs/plans/batch11b-variety-hardened.md
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/03054fb02600-review.md
---

# Plan Review — Batch 11-B (W3.4 cross-phase variety)

§4.12 ×2 context-blind pre-implementation review + a ground-truth audit, then a
self-initiated ≥platform B-pass before the merge. The LAST piece of Batch 11 (11-A W3.3
`1d93b677` + 11-C ①.1d `0fa2b56c` already shipped). Item: on a fresh phase advance, the
cascade avoids repeating the previous phase's per-slot picks when a same-`movement_pattern`
sibling exists — extending the shipped 11-C `_selectCandidate` with an `avoidNames`
`_preferNovel` tiebreak, behind ship-dark `enable_cross_phase_variety`.

## Ground-truth audit (verified against the actual post-11-C code)
- `_selectCandidate` (shipped by 11-C) extended: injury-sub selects the pool (outer), variety
  breaks ties within it (inner). 11-C's map-order sort kept.
- The previous-phase reader reuses the W2.5 `getWeek`/parser machinery WITHOUT the G5 gate;
  `namesOf`/`collect` were private closures → extracted to shared static helpers (fold 1).
- `avoidNames` is SOFT (feeds `_selectCandidate` only, never queryV4) → can't hard-empty a slot.
- Only the pickV4 branch threads it (buildPinnedDays unchanged — variety ⟂ pins==null).

## Round 1 (context-blind ×2 — reader+threading lens, _preferNovel+mirror+sweep lens)
Both converged (no P0). Folds: extract shared parsers `_exerciseNamesOfRow`/`_namesByDayIndex`
(#1 drift class); avoidNames SOFT (⚠ never queryV4/excludeNames); tracer mirror MUST gain
avoidNames + `_preferNovel` (else the sweep passes trivially); EXTEND the real `_selectCandidate`
(keep the sort); exact+lowercased avoidNames; indexed pickV4 loop; L6/edge-case notes.

## Round 2 (on the hardened plan)
Verdict CONVERGED, implementation-ready. Simplification confirmed: `buildPinnedDays` needs ZERO
changes (variety mutually-exclusive with pins). P2 folds: attempt-5 pool NOT variety-eligible
(SoT note); pin the SET-differs test to a `full_gym`/`advanced` deep-pool persona; the shared
parser keeps original case, `previousPhaseNamesByDay` adds its own lowercase.

## B-pass (self-initiated, ≥platform, before merge)
`docs/reviews/03054fb02600-review.md` — 1 P1 (the SERVICE reader `previousPhaseNamesByDay` had no
runtime test — the behavioral test drove generateV4 directly), **fixed in-batch**: extracted a
`@visibleForTesting previousPhaseNamesFrom` pure core + added a reader-core test group (A/B mapping,
lowercase, day-index union, non-workout skip, ship-dark flag gate). All other lenses clean; the
reviewer independently ran 55 regression tests + the frozen-baseline gate. verdict: accepted.

## Convergence
×2 plan review surfaced only bounded spec-hardening folds (all folded); the B-pass found one
test-coverage gap, fixed in-batch → **converged**. Tests: `cross_phase_variety_behavioral_test`
(8, incl. the reader core) + scorecard gate (baseline unmoved) + v4_diagnostic (mirror parity) +
repeat_phase (parser-extraction regression) all green.
