---
branch: diet-food-type-server
date: 2026-11-14
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/diet-food-type-server-bpass.md
---

# Plan-review record — diet plan Unit 2b: one food-type vocabulary on the server and in the coach (`diet-food-type-server`)

Plan: `docs/plans/diet-food-type-server.md` (revision 3; dispositions in its §7, build-time corrections in §8). Diagnose `c9bc6a` (recurrence of `a2b2f1`; pairs with Unit 2a's `6f5aaa`). Switch removal: OI-510.

**Release order:** this PR lands on `main` first; then `daily-snapshot`, `protein-gap-alert`, `weekly-report` and `ai-proxy` are deployed from the merged `main` SHA, each with its own founder go and a rollback dry-run first; then the stale-copy cleanup SQL with its own go; then Unit 2a's PR (#270) merges. 2b changes no client file, so its merge deploys nothing user-visible on the web.

Founder decisions (chat 2026-11-14): five food types (Veg, Non-veg, Eggetarian, Pescatarian, Vegan), default Non-veg, "Everywhere it should be same. The coach should be aware about this." Keto / low carb are a later PRO strategy (Unit 3).

## Rounds

| Round | Reviewer | Verdict | Material findings | Disposition |
|---|---|---|---|---|
| 1 | context-blind Sonnet, ground truth at `3da92d26` (incl. a live read-only food_database count) | changes required | 1 P1 (the extraction re-embeds `diet_preference` every run and the coach retrieves it after the user changed it) + 13 P2 + 3 P3 | the extraction stops producing a food type at all; manual + weekly-report switch; vegan deny-list; fish/meat rules + seed scan; fake_sb numeric fix; deploy facts; lands on main first |
| 2 | context-blind Sonnet on revision 2 | converged | 0 P1; 6 P2 + 4 P3 | cleanup is an UPDATE (vector kept), ad-hoc SQL with its own go; `captainManual()` per call; meat-rule false negatives fixed; rollback command corrected |

Ground truth: both reviewers read the cited files at `3da92d26`; round 1 counted the live `food_database` tags (is_veg true 1,235 / false 196 / null 0; is_vegan true 631) and the fish/meat regex misses against the 196 non-veg rows.

## B-pass

Pending: `docs/reviews/diet-food-type-server-bpass.md` after review CI is green.

## Build evidence

- 18 mutations (diagnose `c9bc6a` table B1-B18), each applied and reddening at least one test; B9 survived the first test set and a mixed-dish list was added.
- Whole Deno tree on the VPS: 1,707 passed, 2 failed with the known `AddrInUse` :8000 (modules that `serve()` at import; CI has no conflict).
- Seed scan of the bundled asset's 196 `is_veg = false` rows: eggetarian keeps 35 egg rows, pescatarian 91 egg / fish / seafood rows, none with a meat word.
