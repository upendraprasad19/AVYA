---
branch: diet-strategy-3b2
date: 2026-11-14
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: pending
bpass: pending
bpass_review: docs/reviews/diet-strategy-3b2-bpass.md
---

# Plan-review record — diet plan Unit 3b-2: the diet strategy in the coach manual and `suggestMeal` (`diet-strategy-3b2`)

Plan: `docs/plans/diet-strategy-3b.md` §5 (revision 4; it lands on `main` with Unit 3b-1a, PR #275, which merges first; this branch is synced with `main` after that merge). Execution mode (§4.12.7): inline, one worktree per landing (`.claude/worktrees/diet-strategy-3b2`), based on `main` `21db03c7` (Unit 3a merged dark, migration 179 live).

**Scope of this landing:** server only, no client file. `_shared/captain_manual.ts` gains `DIET_STRATEGY_MANUAL_PASSAGE` in SECTION 7 (outside every food-type string) and composes its switch `DISABLE_DIET_STRATEGY_MANUAL_RULES` after the food-type switch in `captainManual()`; the "Older values" line is reworded in both copies. `_shared/diet_strategies.ts` (`normalizeDietStrategy`) is new. `suggestMeal` reads `diet_strategy` in the same profile row as the food type and, for a PRO caller (`ctx.isPro`) whose read succeeded, caps `carbs_std` (keto 6 g; a vegan keto caller and low carb 25 g) inside `foodQuery`, before the literal limit, with a note; kill switch `DISABLE_SUGGESTMEAL_DIET_STRATEGY`. Removal of both switches is added to OI-510.

**Inert until the flag is on:** `user_profile.diet_strategy` is written only by an app with `DietStrategyFlags` on (3b-3 flips it), and `snapshot.profile.diet_strategy` is sent only by such an app, so after the deploy every live user gets today's tool rows and today's coach behaviour (a passage conditional on a key no snapshot carries).

**Release order:** this PR merges after #275; then `ai-proxy` and `weekly-report` (both bundle `captain_manual.ts`; `suggestMeal` is in `ai-proxy`) are deployed from the merged `main` SHA, each with its own founder go and a rollback dry-run first (`.claude/skills/edge-function-deploy-rollback/SKILL.md`).

## Rounds

The three plan rounds of `docs/plans/diet-strategy-3b.md` each covered §5 (the server half) with ground truth read from `main`.

| Round | Reviewer | Verdict | Material findings for 3b-2 | Disposition |
|---|---|---|---|---|
| 1 | context-blind Sonnet on rev 1 | changes required | P2 (finding 7): manual switch, the "Older values" line, weekly-report, suggestMeal fail-safe / limit / vegan | own kill switch; both copies reworded; the passage is inert without the chat snapshot field; select + `.lte` + fail-safe + vegan rule + accepted window (plan §5, §9 row 7) |
| 2 | context-blind Sonnet on rev 2 | changes required | none new for §5 | plan §10 |
| 3 | context-blind Sonnet on rev 3 | changes required | P2 (findings 6, 9): vegan + keto in the manual; suggestMeal edit points | the passage names vegan keto (pinned); the helper returns `{foodType, strategy}`, the `.lte` sits inside `foodQuery` so every query site gets it, tests for the egg branch and the read-error branch (plan §11 rows 6, 9) |

## Build verification

- Deno: `_shared/tools/__tests__/suggestMeal_test.ts` (Unit 3b-2 block, 7 tests), `_shared/captain_manual_diet_strategy_test.ts` (4 tests), `_shared/captain_manual_food_type_test.ts` (unchanged, passes with the reworded line): 51 pass. Whole tree: 1,726 pass, 2 fail with `AddrInUse` (the known port-8000 VPS quirk; CI is the source).
- `deno check --node-modules-dir=none` on `ai-proxy/index.ts` and `weekly-report/index.ts`: clean.
- Mutants D1–D12, each applied once (count 1) and restored, run against the three test files: template loses the keto line, manual switch ignored, manual switch applied only on the new food-type base, keto cap 6 -> 7, low carb cap 25 -> 30, `isPro` check dropped, a read error applies keto, the query cap not applied, vegan keto gets the keto cap, the switch case-insensitive, an unknown strategy read as keto, the cap on the main query only: 12 of 12 red.

## B-pass

Pending.
