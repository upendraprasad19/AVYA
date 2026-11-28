---
branch: generator-step1-core-list
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step1-core-list-bpass.md
---

# Plan review — generator-step1-core-list (generator overhaul step 1, Unit 1A)

Plan: `docs/plans/2026-11-08-generator-step1-core-list.md` (v7: the converged v6 plus one measured amendment,
below). Unit 1A fixes the core-list pool
(`enable_core_list_pool`, ship-dark, default OFF) with the pool still OFF and OFF byte-identical: core-list data
for advanced home / bodyweight squats, bodyweight hinge, curl and calf rows (R1, waiting for the founder's
signature on the level table; this branch carries the code half and no R1 data), jump rows
partitioned out (R2), equipment fit as a like-for-like isolation filter and a compound key (R3), the top-up
preferring core rows while keeping the founder's 3-exercise floor (R4), a glute-first last tie-break in Glutes
hinge slots (R5), and CI zeros on the gate's trace (R9). Unit 1B (the flip and the old-path deletion) is a
separate plan; its items are `upstream_blocked` ledger entries.

## Review rounds (six, context-blind Sonnet reviewers, each on the post-previous-round plan, before any code)

Every reviewer read the code and data and verified claims at file:line; rounds 2-6 also ran a Python port of
`CoreListSelector.rankedPool` over the library (862 rows) and the 36 split slot shapes, checked against the Dart.

| round | on | P0 | P1 | P2 | P3 | main findings |
|---|---|---|---|---|---|---|
| 1 | v1 | 0 | 5 | 8 | 4 | E073 is a skill row; E193 the only bodyweight calf row; v1's top-up rule broke the founder's floor; old-path deletion far larger than stated (scope split into 1A / 1B); most drops untouched |
| 2 | v2 | 0 | 3 | 6 | 2 | an ordering key cannot keep rows out because `_preferNovel` walks past it (partition instead); `typeFor` reasoning wrong for the ON path; CI zero (ii) ill-defined |
| 3 | v3 | 0 | 2 | 5 | 3 | glute-first key demoted the gym Deadlift; widened filter turned Quads isolation into a second squat |
| 4 | v4 | 0 | 1 | 3 | 2 | gym Glutes hinge Deadlift -> Hip Thrust (accepted, named); filter must reduce to like-for-like rows |
| 5 | v5 | 0 | 1 | 1 | 1 | raw equality dropped the real calf machines (same-muscle head table) |
| 6 | v6 | 0 | 0 | 0 | 3 | converged |

All findings are folded into the plan; the full log is its section 10. Remaining founder decisions are listed in
the plan (R1 table, R7 per slot, Nordic Curl, gym Glutes Hip Thrust) and are `blocked_on_user` in the closure
ledger until signed.

## v7 amendment (measured during the gate loop, after review #6)

Gate R9 (iii) went red on 7 home_dumbbells advanced phase-1 personas: the R3 (b) fit key put Barbell OHP first,
but variant B soft-avoided it and `_preferNovel` walked to the foundational Pike Push Up, the same lesson as
review #2 (an ordering key cannot keep a row out). v7 adds `vertical_push` to `_implementPatterns`, a pool
partition, so the like-for-like reduction removes Pike from an implement user's press slot. Measured footprint:
24 home_dumbbells advanced phase-1 plans and one new week-2 Chest zero (allocator class); plan section 7 carries
the full audit before and after.

## B-pass

Accepted: `docs/reviews/generator-step1-core-list-bpass.md`. A fresh, context-blind Sonnet agent reviewed
`git diff 0633a121 93550461` with the skill's eight lenses plus an OFF-identity check: no P0, P1 or P2. Two P3s,
no code change: F1 (a one-row like-for-like pool makes variant B repeat A's row) is the plan's named consequence,
measured in section 7, remedied by the OI-148 rows in Unit 1B; F2 (raw vs lower-cased tier key) is unreachable.
The full suite on 93550461 passed (13,648 tests).
