---
branch: diet-strategy
date: 2026-11-14
blast_radius: platform
review_rounds: 7
ground_truth_verified: true
verdict: converged
bpass: pending
bpass_review: docs/reviews/diet-strategy-bpass.md
---

# Plan-review record — diet plan Unit 3a: diet strategy targets and selector, shipped dark (`diet-strategy`)

Plan: `docs/plans/diet-strategy.md` (revision 7; round dispositions in its §6 to §12). Execution mode (§4.12.7): inline, one worktree (`.claude/worktrees/diet-strategy`), based on `main` `41595b49` (Units 1 and 2 merged).

**Ship-dark:** 3a lands behind `DietStrategyFlags.enabled`, `kDietStrategyDefaultOn = false`, with a behavioural identity test (plan §4 test 2b). It is logged in `docs/ship_dark_pending_review.yaml`. The flip happens in Unit 3b with its own full ×2 review and B-pass. This build nevertheless had the full review (7 rounds), not the 1-round ship-dark tier.

**Migration:** `user_profile.diet_strategy` needs its own founder go before this PR merges.

Founder decisions (chat 2026-11-14): strategies Balanced (default), Low carb, Keto; PRO; Option A — carb and fat targets change everywhere, calories and protein do not; a confirm dialog before a change; no AI; unlimited changes; the calorie card label shows food type and strategy.

## Rounds

| Round | Reviewer | Verdict | Material findings | Disposition |
|---|---|---|---|---|
| 1 | context-blind Sonnet, ground truth at `aeb46334` | changes required | 1 P1 (a strategy switch via the full recompute moves calories) + 5 P2 | `macroSplit`; generator work moved to 3b; seams named |
| 2 | context-blind Sonnet on rev 2 | changes required | 2 P1 (no "server-confirmed free" seam; a local-only `targets_strategy` breaks after a restore) + 5 P2 | the write-time mechanism REMOVED: read-time `effectiveMacroTargets`, stored targets unchanged |
| 3 | context-blind Sonnet on rev 3 | changes required | 2 P2 (tester-visible keto targets beside balanced meals; helper rule on an incomplete pack) | 3a ships dark; one helper rule |
| 4 | context-blind Sonnet on rev 4 | changes required | 3 P2 (flag-off leaks: snapshot keys, ungated writes, int rounding) | every leak gated; doubles |
| 5 | context-blind Sonnet on rev 5 | changes required | 3 P2 (unconditional watches, ungated push entry, a paused choice erased) | flag-gated watches and push; effective-value seeding |
| 6 | context-blind Sonnet on rev 6 | changes required | 1 P2 (no carrier for the effective strategy) | `strategy_index` / `DailyNutritionData.strategy` |
| 7 | context-blind Sonnet on rev 7 | converged | 0 P0/P1/P2 | two P3 notes applied |

Ground truth: every reviewer read the cited files at `aeb46334` (Unit 2a's head, which `main` now contains); the reader inventory of carb/fat targets was confirmed complete across `lib/`, `supabase/functions/` and `supabase/migrations/` in rounds 3, 5, 6 and 7.

## B-pass

Pending: `docs/reviews/diet-strategy-bpass.md` after review CI is green.
