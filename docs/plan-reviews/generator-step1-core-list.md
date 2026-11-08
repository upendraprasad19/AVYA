---
branch: generator-step1-core-list
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: pending
---

# Plan review — generator-step1-core-list (generator overhaul step 1, Unit 1A)

Plan: `docs/plans/2026-11-08-generator-step1-core-list.md` (v6). Unit 1A fixes the core-list pool
(`enable_core_list_pool`, ship-dark, default OFF) with the pool still OFF and OFF byte-identical: core-list data
for advanced home / bodyweight squats, bodyweight hinge, curl and calf rows (R1, founder-signed), jump rows
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

## B-pass

Pending: `/code-review` runs on the finished diff before the merge (platform: `bpass: accepted` required).
