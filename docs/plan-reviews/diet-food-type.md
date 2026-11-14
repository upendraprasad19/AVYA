---
branch: diet-food-type
date: 2026-11-14
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/diet-food-type-bpass.md
---

# Plan-review record — diet plan Unit 2a: one food-type vocabulary on the client (`diet-food-type`)

Plan: `docs/plans/diet-food-type.md` (revision 5; per-round dispositions in its §7). Diagnose `6f5aaa` (recurrence of `a2b2f1`, concept `diet_preference_vocabulary`). Closes OI-257.

**Pre-merge condition: do not merge before Unit 2b's Edge Functions are deployed (versions recorded in 2b's diagnose doc). SATISFIED 2026-11-14: 2b merged as `fa888563`; daily-snapshot v35, protein-gap-alert v21, weekly-report v38, ai-proxy v105 live; cleanup SQL applied.** A merge to `main` deploys the web app (`vercel.json` builds `main` only), and before 2b the server mishandles the new keys (plan header, round 3 finding 1).

Founder decisions (chat 2026-11-14): food types Veg, Non-veg, Eggetarian, Pescatarian, Vegan; default Non-veg; FREE; selectable on the Diet Plan screen and in Edit Profile; shown on the Nutrition calorie card; the coach knows it; workout generation is unaffected. Keto / low carb are a PRO strategy (Unit 3).

Blast radius: `platform`, from the shared fixture `supabase/functions/_shared/testdata/food_type_vocabulary.json` (test data the Unit 2b Deno mirror reads; no Edge Function code changes here). The client paths classify `account` (`lib/core/constants/food_types.dart`) or lower.

## Rounds

| Round | Reviewer | Verdict | Material findings | Disposition |
|---|---|---|---|---|
| 1 | context-blind Sonnet, ground truth at `3da92d26` | changes required | 3 P1 (unknown value served meat; raw extracted value reaches the coach; suggestMeal egg/fish heuristic) + 12 P2/P3 | plan §7 round 1; the client P1 fixed (unknown → Veg), server P1s moved to Unit 2b |
| 2 | context-blind Sonnet on the post-round-1 plan | changes required | 5 P1 (4 in the server/coach half; Gemini-style spellings fell to Veg) + 11 P2/P3 | spellings added to the client table; unit SPLIT (§4.12.1): this is the client half 2a, the server half is Unit 2b with every carried finding |
| 3 | context-blind Sonnet on revision 3 (2a only) | changes required | 1 P1 (release order: the auto-deployed web app would reach the old server) + 10 P2/P3 | release order 2b-deploy-first, serialised write door, stricter-by-design table, fallback no-meat test |
| 4 | context-blind Sonnet on revision 4 | converged | 0 P1; 2 P2 (queued call across an account change; a failed link) + 4 P3 | all applied in revision 5 |

Ground truth: each reviewer read the cited files at `3da92d26` and re-derived the catalog family counts (egg 7, chicken 5, fish 6, mutton 2 for `is_veg == false`) from the bundled asset.

## B-pass

Accepted: `docs/reviews/diet-food-type-bpass.md` (fresh Sonnet seat on 74085219, review CI green). No P0/P1/P2; five P3 findings (a corrupt non-String read as Non-veg; a dropped write announced as done; a legacy plan re-stamped with the current type; two stale Edit Profile registry ranges; the snapshot push fired before the coach lock), all fixed on this branch with mutations F1 to F5c (diagnose `6f5aaa`). Finding 1 is mirrored in Unit 2b (b76694b1).

## Build evidence

- 19 mutations (diagnose `6f5aaa` table M1-M19), each applied (anchor count 1, replacement present) and each reddening at least one test; files restored byte-equal (sha256).
- Measured on the real asset, 50 seeds: cut eggetarian protein 0.76-0.93 (mean 0.84), cut pescatarian 0.81-0.99 (mean 0.90), maintain both >= 0.94; all calories within [0.96, 1.09].
- Build-time correction to the plan: two quick taps that are both real changes give two locks, not one (plan T2 corrected).
