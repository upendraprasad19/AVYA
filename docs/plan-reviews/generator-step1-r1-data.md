---
branch: generator-step1-r1-data
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step1-r1-data-bpass.md
---

# Plan review — generator-step1-r1-data (Library Batch S1a: core-list levels, gate zeros R9 (i) and (iv), seed v21)

Plan: `docs/plans/2026-11-08-library-batch-s1-core-data.md` (v4). Only `core_levels` changes (the founder-approved
R1 table, the R7 household rows for Biceps / Lateral / Rear Delts, the advanced Hip and Glutes rows, G0339 to keep a
dumbbell curl for equipped users, and the level-agreement edits with two named exceptions), seed v21, and the two gate
zeros that need the data. `core_levels` is not a cloud column, so no migration and no live step. The twins, the
same-movement rule, E053 and the migration are Batch S1b.

## Review rounds (context-blind Sonnet seats, each on the post-previous-round plan, before any code)

Every seat verified claims at file:line; rounds 1 to 3 ran a Python mirror of `CoreListSelector.rankedPool` over the
split's slot shapes, four tiers and three levels.

| round | on | seats | P0 | P1 | main findings |
|---|---|---|---|---|---|
| 1 | draft 1 | lens A data, lens B pipeline | 0 | 15 | `core_levels` not a cloud column; new-row machinery (generator, scope inputs, injury builder, removals generator, E053 media) much larger; family "same movement" rule does not exist; E010 narrowing empties a slot; E276 fills Rear Delts; E020 missing. Split into S1a / S1b |
| 2 | draft 2 | lens A, lens B (fresh) | 0 | 3 | gate (iv) scope vs injured personas; tier is platform; `git show` tests fail on CI's shallow checkout; towel curl at basic gym (G0339 added); Goblet Squat in advanced gym pools named |
| 3 | draft 3 | one fresh seat, convergence | 0 | 0 | like-for-like test moves in three cells; G0339 effects at full gym and for bench owners; (iv) exemption as `injury == null`; converged |

All findings are folded into the plan; its review log has the detail. Founder items before the build go: plan
Decision 3 (E255, E010 / E045 exceptions, the Goblet Squat effect, G0339, gym Hip picks).

## B-pass

Accepted: `docs/reviews/generator-step1-r1-data-bpass.md`. A fresh context-blind Sonnet seat reviewed the staged diff
(29 files): no P0, P1 or P2; two P3 wording findings (the R9 (iv) comment now names source `core` or `fill`; the
before-fixture's `_note` says it is frozen), both applied. The full suite passed on the staged tree (13,665 tests).
