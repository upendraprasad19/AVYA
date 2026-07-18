---
branch: workout-variety-injurysub-11bc
plan: docs/plans/batch11bc-variety-injurysub.md
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/314a11745d08-review.md
---

# Plan Review — Batch 11-C (①.1d curated injury-substitute preference)

§4.12 ×2 context-blind pre-implementation review + a ground-truth audit, then a
self-initiated ≥platform B-pass before the merge. Batch 11 was split; 11-A (W3.3) shipped
`1d93b677`; this branch ships **11-C (①.1d) only** — W3.4 variety (11-B) is decomposed to a
follow-on branch (NOT deferred; it extends the SAME `_selectCandidate` seam with an `avoidNames`
tiebreak). Item: when ON, `_cascadeFill` re-ranks the already-safe (post-injury-filter),
same-`movement_pattern` candidate list to prefer a curated `InjurySubstitutes` sub; ship-dark
`enable_injury_substitute_pref` (default OFF → byte-identical).

## Ground-truth audit (verified against the actual files this session)
- The cascade seam is `exercise_selector.dart` `_cascadeFill` (4 attempt-return sites) →
  `_fillSlots` → `pickV4` → `generateV4`; injuries already threaded to `queryV4 injuryExclusions`.
- The re-rank runs on the POST-injury-filter list → structurally cannot surface a
  contraindicated exercise. Verified against `queryV4`.
- **①.1d library feasibility VERIFIED** against `assets/data/exercise_library.json` (258 rows):
  every injury/pattern has a safe same-pattern remainder; the curated map = library-present,
  same-pattern, not-injury-tagged subs (all 16 counts + 9 injury totals recomputed exact).
- `ExerciseRepository.getAll()` seed rows carry `id`; the const map is Hive-free (tracer imports it).

## Round 1 (context-blind, ×2 — correctness+inertness lens, seam+mirror+test lens)
Both converged (no P0). Material folds: (P1) map order not honored by `where().first` → sort subs
by `prefs.indexOf`; (P1) exact + lowercased BOTH sides; (P1) drop Romanian Deadlift from lower_back
(under-tagging gap); (P1) frozen-baseline gate is `scorecard_gate_test`→`generator_matrix` (21
injured personas) — unmoved because 11-C doesn't wire its trace call; (P2) thread `buildPinnedDays`
sig + `fresh()`; (P2) doc nits (7 trace call sites; 6-of-9 tokens). All applied.

## Round 2 (on the hardened plan)
Verdict CONVERGED, one one-line fix: `preferredFor` must return `List<String>` not `Set<String>`
(`Set` has no `.indexOf`); `.contains` still exact-match. + P2 notes (multi-injury union order;
test asserts the ON pick not a hardcoded OFF winner; L6 phase≥2 may re-swap a curated pick — safe).
All applied. No third round needed (only bounded refinements surfaced — the unit is right-sized).

## B-pass (self-initiated, ≥platform, before merge)
`docs/reviews/314a11745d08-review.md` — **0 findings**, verdict accepted. The reviewer independently
ran the behavioral + diagnostic + scorecard tests, cross-referenced all 20 curated names against the
library, and verified flag-OFF byte-identical inertness, post-filter safety, tracer-mirror fidelity,
full threading, and no crossed-wire named args.

## Convergence
×2 plan review surfaced only bounded refinements (all folded); the B-pass on the implementation
found nothing → **converged**. Tests: `injury_substitute_preference_behavioral_test` (4 cases) +
scorecard gate (baseline unmoved) + v4_diagnostic (mirror parity) all green.
