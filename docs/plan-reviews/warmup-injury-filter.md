---
branch: warmup-injury-filter
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/warmup-injury-filter-bpass.md
---

# Plan review — warmup-injury-filter (U3, Ship 2 of the injury batch)

Ship 2 of the workout-generator injury batch (after Ship 1 a1f6c3). Injury-filters
the hardcoded warmup/cooldown/cardio moves (DROP-not-substitute). Diagnose d3f8a1.

## Review rounds (≥2, context-blind, on the design + ground truth, BEFORE code)

- **Round 1 — ground-truth reviewer:** verified against live code + the exercise
  library. Found the plan's central "the map must AGREE with the library" premise
  was FALSE on 17/25 moves (I re-verified the library values myself). Confirmed
  the 2 attach() call sites (generateV4 + template_service, the latter unthreaded),
  the 25-move inventory (complete), and InjuryVocab availability.
- **Round 2 — design reviewer:** independent adversarial pass. Verdict
  harden-then-implement (explicitly NOT split — one file + threading + test).
  Found: the false library-consistency premise; a NON-guaranteed warmup floor
  (knee-bodyweight loses all cardio; multi-injury empties the dynamic warmup);
  the untethered template_service path; an open Arm-Circles medical question.

Both reviewers converged. All findings folded into the hardened plan (see the
plan's HARDENED section) BEFORE any code was written.

## Ground-truth verification (true)

Self-verified against `assets/data/exercise_library.json`: Push Up (E005,
`horizontal_push`, `["wrist"]`), Band Pull Apart (E093, `[]`), Baithak (E077,
`["hip","knee"]`) — the 3 main-cascade-selectable moves; and that the warmup/
cooldown-only rows (Wall Push Up, Dead Hang, the shoulder stretches, …) are
UNDER-tagged (`[]`). The 2 attach() callers + the coach paths routing through
generateV4. Every value read directly, not from subagent prose.

## Resolution (converged)

- Map defers to LIBRARY tags for main-selectable moves (Push Up kept for a
  shoulder injury in BOTH main + warmup — consistent) and uses conservative tags
  for warmup-only moves (the library under-tags them; the map supersedes).
- Guaranteed non-empty FLOOR (safe Slow Walking cardio fallback + Deep Breathing
  anchor); template_service threaded; kill-switch read internally by attach();
  Arm Circles/Band Pull Apart kept untagged on a stated LOAD rationale (rehab/
  low-load), not library-deference; extended behavioral test (multi-injury floor,
  cardio fallback, irrelevant-injury-unchanged, drift guard, non-vacuity).

## FOUNDER DECISION (recorded)

The review surfaced that the library under-tags MAIN moves too (Push Up not
`shoulder`-tagged), so Ship-1's shipped main filter is itself under-inclusive.
**Founder chose Option A (2026-07-12):** ship the bounded warmup filter now;
the library-wide `injury_contraindications` audit (fixing the main-plan under-
tagging) is a SEPARATE deliberate batch with its own review — NOT folded into
this warmup fix.

## Verdict: converged

Behavioral test green (7/7, `warmup_injury_filter_behavioral_test.dart` — the sole
proof; the Batch-0 scorecard is blind to warmup/cooldown); plan_engine_v4 145/145
(no regression from the attach signature change); diagnose d3f8a1 validated;
flutter analyze clean. B-pass on the implemented diff accepted
(docs/reviews/warmup-injury-filter-bpass.md). No open issues.
