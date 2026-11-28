---
branch: generator-step1-1bf
blast_radius: platform
review_rounds: 18
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step1-1bf-bpass.md
---

# Plan review — generator-step1-1bf (Unit 1B-F: the core-list pool becomes the only picker)

Plan: `docs/plans/2026-11-10-generator-1bf-flip.md` (v19 plus the Ruling 5c amendment). This is the full x2 review
the ship-dark entry `enable_core_list_pool` required for its flip (`docs/ship_dark_pending_review.yaml`, moved to
`resolved:` with this record as `flip_review_record`). Tier L (plan engine), blast radius platform.

## Review rounds

Eighteen rounds ran, each with context-blind Sonnet seats (two in most rounds, one in rounds 17 and 18) on the
post-fix plan, verifying claims against the code and against measured data: the 2,304-plan audit dumps, the 15-pair
injured grid, the five-set focus grid, the floor sweep and the golden personas. Rounds 1 to 16 kept finding material
issues, each folded with a measured prototype (A to J; H3 chosen) and a founder decision where it was a product
trade-off (d13 to d23, plan section 10). Round 16's seat A and round 17's single seat converged; v18 was the build
plan. Round 18 reviewed the build finding Ruling 5c with its diff and converged (P3s folded). Section 9 of the plan
logs every round and the build records of Tasks 2 to 5.

## Ground truth

Every number the plan states was re-measured on the final tree in Task 5 (the closure
`docs/audit/generator-step1-1bf.closure.yaml` names each): the audit equals prototype H except Ruling 5c's 5 plans; the
golden equals main's pre-flip ON world on all 998 keys; the focus grid equals H3's dump except 70 lines in the same 5
keys; the CI hard test's ratchets equal the plan's no-R6 measurement of the extension (182 thin / 6 one-exercise).

## B-pass

Accepted: `docs/reviews/generator-step1-1bf-bpass.md`. Four seats (code, data path, harnesses, documents), no P0 or
P1; nine P2 and eleven P3, each fixed in this batch (code and test fixes mutated red) or answered with evidence.
