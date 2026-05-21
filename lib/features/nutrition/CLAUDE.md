---
scope: nutrition
parent: ../../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# Nutrition — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/nutrition/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

<!-- MIGRATION IN PROGRESS — content from CLAUDE.md will be moved here in Milestone 2 -->

## Single-source-of-truth contracts

(populated in Milestone 2)

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Scan meal result not editable | `_ScanResultEditor` replaces the old read-only `_buildResult`. All scan results are mutable: editable meal name, per-item name/kcal/P/C/F/Fi, +Add Item, X Delete. Total recomputes on every keystroke via `onChanged: (_) => setState(...)`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Missing projection on MY TARGETS | Both `profile_screen._buildNutritionTargets` and `nutrition_screen._buildProjectionSubtitle` must read `current_weight_kg`, `target_weight_kg`, and `pace_preference` from the user profile. Projection only shown for `lose_fat`/`build_muscle` goals with non-zero gap. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Diet-plan meals not visible on nutrition screen | `TodaysMealsCard` renders "FROM YOUR DIET PLAN" hint on empty slots via `dietPlanProvider` (reads `configBox['saved_diet_plan']`). If hints don't show after a user saves a plan, confirm `diet_plan_screen._savePlan` still calls `ref.invalidate(dietPlanProvider)` after `saveDietPlan`. Tap-to-log pre-fill depends on `showFoodSearchSheet(initialQuery: planned.firstFoodName)` — don't drop the initialQuery argument. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Diet plan over-delivers protein 2-3× target | Plan C's anchor-protein-per-meal algorithm fixed the 32% deficit (the original APK Test #3 bug) but introduced over-delivery: cut 243%, maintain 276%, build 183%. Excess protein costs calories, makes meals expensive, breaks the calorie balance. Three-part fix in commit `c7288d3`: **Part A — smart Pass 2 filler exclusion** (when slot anchor already meets ≥90% of slot's protein target, exclude 'pulses' for lunch/dinner and 'dairy' for breakfast from filler pool). **Part B — Pass 4 surplus trim** (mirror of Pass 3 inverted: if total > 115% target, swap highest-protein non-anchor item for lower-protein filler in same calorie band ±20%, up to 12 swap iterations, anchors protected). **Part C — Pass 1 anchor cap** (anchor protein hard-capped at 1.5× slot's protein target; random pick from in-band pool; fallback: highest-under-cap, NOT smallest-above-floor — that one starves veg slots). Test assertions pin protein in [95%, 115%] band. All 4 archetypes (cut 98% / maintain 112% / build 96% / vegan 102%) now in band. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Counters increment on save not API call | Pre-Test-#11: `UsageCounterService.increment(...)` was called from inside `NutritionWriteService.logMeal`. A free user analysing 50 AI-text meals without saving saw "50 remaining" while the server's `trg_food_text_rate_limit` Postgres trigger had counted every Edge Function call. Test #11 M1+M2: counters now increment at the API-call site (`food_logger_section._analyse`, `ScanMealNotifier.scanImage`, `cart_auditor_section.analyseCart`, `tool_dispatcher._executeLogMealByText`). Save sites no longer increment. Cart auditor counter (previously dead code — no callsite passed `NutritionWriteSource.cart` to `logMeal`) is now wired. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

(populated in Milestone 6)
