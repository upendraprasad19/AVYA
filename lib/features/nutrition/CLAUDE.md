---
scope: nutrition
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Nutrition — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/nutrition/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/features/nutrition/` owns the 🥗 Nutrition tab + Diet Plan flow.

Screens / sections:

- `nutrition_screen.dart` — top targets + today's macros + 2-tab Log Food (AI text + Scan meal) + saved meals + water + today's meals card (from saved diet plan).
- `food_search_sheet.dart` — 5K-food search (Hive `food_database` box) + per-serving math + save to meal slot.
- `food_logger_section.dart` — AI text analysis ("2 chapatis and dal") via `ai-proxy` with `type: 'food_text_analysis'` (gemini-2.5-flash) → AI breakdown card. NOT a `food-text-analysis` Edge Function — no such function exists.
- `scan_meal_section.dart` — photo capture → `ai-proxy` with `type: 'scan_meal'` (gemini-2.5-flash-lite vision, 20/day server cap combined with cart_auditor) → editable result via `_ScanResultEditor`.
- `cart_auditor_section.dart` — paste / photograph grocery cart → AI macro/cost audit.
- `diet_plan_screen.dart` — generated diet plan + PDF export.
- `water_section.dart` — `WardGlassGrid` 8-cell tracker.

Service layer: `lib/core/services/nutrition_write_service.dart` (single writer
for `nlog_*` Hive rows + `nutrition_logs` cloud) + `nutrition_read_service.dart`.

## Single-source-of-truth contracts

| Concept | Writer | Reader |
|---|---|---|
| `nutrition_total_calories` | `nutrition_write_service.dart` `logMeal` | `nutrition_read_service.dart` + home `TodayMacrosCard` + nutrition screen. **Hive key:** `nlog_${istDateStr(date)}_${hashCode}` (`hive_field_name_nlog` SoT). |
| `food_log_delete_with_undo` | `nutrition_write_service.dart` `deleteLog(allowUndo:)` + `restoreLastDeleted` (soft-delete + restore-on-tap; audit-fixwave F12 — was mis-named `deleteWithUndo`) | the nutrition meal-list dismissible (`TodaysMealsCard`). |
| `saved_meals` | `nutrition_write_service.dart` `saveMealAsTemplate` (audit-fixwave F12 — was mis-named `saveMeal`) | `saved_meals_section.dart` quick-log. |
| `water_logs` | `health_write_service.dart` `setWaterMl` (audit-fixwave F12 — was mis-named `logWater`, now deleted) | `water_section.dart` `WardGlassGrid`. |
| `water_target` | `water_target_service.dart` (Hive `configBox['water_target_ml']`) | `waterTargetProvider`. |
| `diet_plan_saved_loaded` | `diet_plan_screen.dart` `_savePlan` → `configBox['saved_diet_plan']` + `ref.invalidate(dietPlanProvider)` | `TodaysMealsCard` renders "FROM YOUR DIET PLAN" hints on empty slots. |
| `food_text_analysis` daily cap | server-side trigger `trg_food_text_rate_limit` (live definition migration 127) — 10/day free, 200/day PRO. Free arm lowered 50→10 in b8f4c2 to match `AppConstants.freeAiTextLogsPerDay`. Insert-first pattern: `ai-proxy` inserts placeholder row BEFORE Gemini. | client error mapping returns 429 → "limit reached". |
| `ai_breakdown_notifier_save_meal` telemetry (APK +43 obs 1, diagnose `d8e2f4`, 2026-09-16) | `AiBreakdownNotifier.saveMeal` catch block (`nutrition_provider.dart`) now calls `ErrorTelemetry.recordNonFatal(reason: 'ai_breakdown_notifier_save_meal')` — was a bare `debugPrint`, invisible to `client_errors`. Root cause of the underlying founder-reported failure (breakfast/lunch/dinner saved, snack repeatedly didn't) was NOT conclusively identified — every throw site inside `NutritionWriteService.logMeal` is independently guarded with its own telemetry; this closes the one gap that had none. | `client_errors` table, `op_type = 'ai_breakdown_notifier_save_meal'`. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Scan meal result not editable | `_ScanResultEditor` replaces the old read-only `_buildResult`. All scan results are mutable: editable meal name, per-item name/kcal/P/C/F/Fi, +Add Item, X Delete. Total recomputes on every keystroke via `onChanged: (_) => setState(...)`. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Missing projection on MY TARGETS | Both `profile_screen._buildNutritionTargets` and `nutrition_screen._buildProjectionSubtitle` must read `current_weight_kg`, `target_weight_kg`, and `pace_preference` from the user profile. Projection only shown for `lose_fat`/`build_muscle` goals with non-zero gap. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Diet-plan meals not visible on nutrition screen | `TodaysMealsCard` renders "FROM YOUR DIET PLAN" hint on empty slots via `dietPlanProvider` (reads `configBox['saved_diet_plan']`). If hints don't show after a user saves a plan, confirm `diet_plan_screen._savePlan` still calls `ref.invalidate(dietPlanProvider)` after `saveDietPlan`. Tap-to-log pre-fill depends on `showFoodSearchSheet(initialQuery: planned.firstFoodName)` — don't drop the initialQuery argument. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Diet plan over-delivers protein 2-3× target | Plan C's anchor-protein-per-meal algorithm fixed the 32% deficit (the original APK Test #3 bug) but introduced over-delivery: cut 243%, maintain 276%, build 183%. Excess protein costs calories, makes meals expensive, breaks the calorie balance. Three-part fix in commit `c7288d3`: **Part A — smart Pass 2 filler exclusion** (when slot anchor already meets ≥90% of slot's protein target, exclude 'pulses' for lunch/dinner and 'dairy' for breakfast from filler pool). **Part B — Pass 4 surplus trim** (mirror of Pass 3 inverted: if total > 115% target, swap highest-protein non-anchor item for lower-protein filler in same calorie band ±20%, up to 12 swap iterations, anchors protected). **Part C — Pass 1 anchor cap** (anchor protein hard-capped at 1.5× slot's protein target; random pick from in-band pool; fallback: highest-under-cap, NOT smallest-above-floor — that one starves veg slots). Test assertions pin protein in [95%, 115%] band. All 4 archetypes (cut 98% / maintain 112% / build 96% / vegan 102%) now in band. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Generated plan composes absurd meals (Pringles at dinner, double rice at breakfast, zero vegetables, Greek Yogurt twice/day) | Meal-quality constraint layer (2026-09 batch, diagnose `d3c7a9`): **Pass 0 group quotas** (mandatory vegetables lunch/dinner + dairy-or-fruit breakfast, `isQuotaLocked` so recovery can't swap them out), **per-category filler caps** (staples ≤1, pulses ≤1, vegetables ≤2 — each with a re-entrant 2nd-item exception when the slot is >20% under its calorie/protein target), **day-level food uniqueness** (hard in Pass 1/0/2 — optional snack anchors SKIP rather than repeat; soft prefer-unused in recovery swaps), **UPF exclusion** (`is_ultra_processed` rows never generated; food_database.json schema v3, `_foodLibraryVersion` MUST bump with any asset schema change or existing installs silently no-op), **nuts_seeds per-serving ≤300 kcal cap**, **recovery anchor-upgrade + gradual sizing with 1.5× slot headroom** (the old highest-protein-first recovery swapped a 90g Protein Shake into an 8g gap and Pass 4 trimmed it back out — oscillation), **Pass 4 three-tier trim floor** (softFloor 105% → dailyFloor 95% → smallest cut; day-level fallback when no slot is individually over), **Pass 5 fiber floor**. Vegan preference reads the DB's `is_vegan` field AUTHORITATIVELY (name blocklists missed '1% Milk'/'Jaouda Perly'/'Milkybar Moosha' on real data). SoT: `diet_plan_generation_quality`. Tests: `test/nutrition/diet_plan_quality_constraints_test.dart` (mutation-proven M1-M8) + `test/nutrition/food_database_tagged_test.dart` (real-DB gates — the curated fixture CANNOT catch real-data leaks; always run the real-DB file when touching the generator). | diagnose `d3c7a9` (2026-09-17) |
| Counters increment on save not API call | Pre-Test-#11: `UsageCounterService.increment(...)` was called from inside `NutritionWriteService.logMeal`. A free user analysing 50 AI-text meals without saving saw "50 remaining" while the server's `trg_food_text_rate_limit` Postgres trigger had counted every Edge Function call. Test #11 M1+M2: counters now increment at the API-call site (`food_logger_section._analyse`, `ScanMealNotifier.scanImage`, `cart_auditor_section.analyseCart`, `tool_dispatcher._executeLogMealByText`). Save sites no longer increment. Cart auditor counter (previously dead code — no callsite passed `NutritionWriteSource.cart` to `logMeal`) is now wired. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

- `test/contracts/nutrition_total_calories_writer_to_reader_test.dart`
- `test/contracts/food_log_delete_with_undo_writer_to_reader_test.dart`
- `test/contracts/food_log_notifier_to_nutrition_log_items_test.dart`
- `test/contracts/food_log_id_and_name_test.dart`
- `test/contracts/food_text_analysis_daily_cap_test.dart`
- `test/contracts/diet_plan_saved_loaded_writer_to_reader_test.dart`
- `test/contracts/saved_meals_writer_to_reader_test.dart`
- `test/contracts/water_logs_writer_to_reader_test.dart`
- `test/contracts/ai_breakdown_notifier_save_meal_telemetry_test.dart` (behavioral — the catch block's `ErrorTelemetry.recordNonFatal` call, via fault-injection test seams)
- `test/nutrition/diet_plan_quality_constraints_test.dart` (10 behavioral guards for `diet_plan_generation_quality` — mutation-proven M1-M8)
- `test/nutrition/food_database_tagged_test.dart` (real-DB tagged-schema gates + spot-checks + archetypes × 8 seeds — authoritative for the generator)
- `test/nutrition/diet_plan_generator_test.dart` (curated-fixture archetypes — fast, but NOT authoritative for real-data leaks)

## See also

- `lib/features/ai_coach/CLAUDE.md` — AI breakdown card + tool dispatcher routing.
- `lib/core/services/CLAUDE.md` — `NutritionWriteService` + sync fan-out + counters.
- `supabase/functions/CLAUDE.md` — the `ai-proxy` request types `food_text_analysis`, `scan_meal` and `cart_auditor`. All three are `type` values on `ai-proxy`, **not** Edge Functions of their own; all three call sites are in `nutrition_provider.dart` (:733, :1356, :1445).
- `docs/architecture/business-rules.md` — calorie/protein formulas.
- `docs/reference/food-database.md` — Hive food_database box (5K rows).
