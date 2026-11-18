---
branch: diet-grams-toggle
date: 2026-11-18
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/diet-grams-toggle-bpass.md
---

# Plan-review record — Diet chart Portions / Grams view (OI-517, account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `account`, COMPUTED:** `dart run scripts/blast_radius_from_diff.dart lib/features/onboarding/providers/onboarding_provider.dart lib/core/services/seed_service.dart assets/data/food_database.json lib/features/nutrition/widgets/diet_serving_view_toggle.dart` -> `account` (the onboarding path drives it; the food asset is `feature`, the seed service `account` (`lib/core/services/**`)).

## What this branch is

A display-only Portions / Grams view for the Diet chart: a pure label function, one local profile key (`diet_serving_view`, absent = Portions, new users get Grams at onboarding), a switch at the right end of the BMR / TDEE / TARGET card, `weight_unit: "ml"` on 145 audited liquid food rows (drinks, soups, rasam) (seed v8), and the five serving readers (meal rows, swap sheet, portion sheet, search rows, PDF). Plan: `docs/plans/diet-grams-toggle.md` (revision 7, sections 10-15 hold the review log).

## Review rounds (all context-blind Sonnet seats, read-only, each verified claims against code and data)

1. **Round 1** on draft 1: 2 P0 + 5 P1 + 3 P2, all accepted (grams are never edited by the audit; the `weight_unit` field needs a seed bump; the label table for 22 unparseable and 7 non-gram-bracket rows; readers list; two existing layout pins; resolver; key plumbing).
2. **Round 2** on revision 2: 0 P0, 4 P1, 5 P2, all accepted (4-column geometry infeasible at 360 dp, label table gaps, Gate 33 script naming, seed behavioural test).
3. **Delta 3** on revision 4 (founder moved the control to the app bar): found the app bar infeasible (my width arithmetic was wrong); the founder then marked the calorie card.
4. **Delta 4** on revision 5: 3 P1 (22 dp screen padding, unit letter spacing, 44 vs 42 dp hit area), all accepted; the design now does not depend on font estimates (a scale-down FittedBox).
5. **Delta 5** on revision 6: design judged robust; 1 P1 (tests cannot assert the real-font scale), accepted; revision 7 converged with no P0/P1 open.

Founder decisions recorded in the plan: grams = food as served; every food shows grams with the count in brackets; liquids in ml; one switch for the whole Diet chart; phone-only storage; new users start on Grams, existing accounts keep Portions; the switch sits at the right end of the calorie card (marked on a screenshot, 2026-11-18); the merge was pre-authorised on a green CI and a clean B-pass.

## Execution

Inline in one worktree (plan section 9). Five code units, each with its own mutants (all went red, restored): asset + seed, label function, setting + card switch + onboarding default, the five readers, one real bug fixed on the way (diagnose `2d9f4b`: a scaled serving printed "1. cups"), then docs.

## Known limits (stated, not hidden)

- Widget tests run on the Ahem fallback font (no font files in the repo), so the real-font look of the calorie card (figures at or near full size at 360 dp) is an on-device check by the founder after the build.
- No test drives `completeOnboarding` end to end; the new-user default is a presence pin plus the write/read contract of the key.
- The PDF label is pinned by presence (the share path needs the plugin); the label itself is covered by the pure tests.
