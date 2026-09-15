---
bug_id: 4e8f1b
date: 2026-07-04
batch: coach-gemini-reliability (Unit B — nutrition absurd-value clamp / FC6)
status: fixed
blast_radius: account
symptom: >
  The AI coach's `log_meal_by_text` tool (and any other NutritionWriteService
  caller — the AI breakdown override, a fat-fingered manual edit) could persist
  an absurd calorie / macro value with NO upstream numeric bound. A single
  garbage row (e.g. an override of 1,000,000 kcal) corrupted every downstream
  sum that reads a stored `nlog_*` row: the daily macro ring, the home nutrition
  snapshot, the weekly AI report, and any streak/goal math derived from calories
  in. Because per-item values resurface on re-edit (append / editLog recompute
  totals from items[]), an unbounded item value re-inflated the total on the
  next edit even if the total was corrected once.
concept: nutrition_total_calories
sot_registry_entry: >
  nutrition_total_calories (docs/sot_registry.yaml) — totals on every nlog_* row
  are computed from items[] by NutritionWriteService.logMeal (+ appendItemsToMeal
  / editLog). FC6 adds a clamp step at every write path so both the meal TOTAL
  and each ITEM are bounded before the Hive put. Behavioral test:
  test/contracts/nutrition_total_calories_behavioral_test.dart (Atwater sum) +
  the new FC6 clamp test below.
writers:
  - "{ file: lib/core/services/nutrition_write_service.dart, method: clampMealPayloadValues, line: 188 } — pure @visibleForTesting clamp: mutates the payload in place (meal totals + each items[] entry) to the ceilings, returns whether anything clamped. NO side effects."
  - "{ file: lib/core/services/nutrition_write_service.dart, method: _clampMealPayload, line: 166 } — thin wrapper: calls clampMealPayloadValues, fires nutrition_absurd_value_clamped telemetry when it returns true (clamp-and-telemetry, never reject)."
  - "{ file: lib/core/services/nutrition_write_service.dart, method: logMeal, line: 112 } — clamp call BEFORE the nutritionBox.put."
  - "{ file: lib/core/services/nutrition_write_service.dart, method: appendItemsToMeal, line: 254 } — clamp call BEFORE box.put (per-item values resurface here)."
  - "{ file: lib/core/services/nutrition_write_service.dart, method: editLog, line: 317 } — clamp call BEFORE box.put (edit recomputes totals from items[])."
readers:
  - "{ file: lib/features/nutrition/repositories/nutrition_repository.dart, method: dailyMacros, line: 31 } — sums the stored total_calories / total_protein across nlog_* rows for the ring + snapshot; a pre-clamp absurd row poisoned this sum."
  - "{ file: lib/core/services/nutrition_write_service.dart, method: appendItemsToMeal, line: 254 } — re-reads items[] and recomputes totals from item calories, so an unbounded ITEM re-inflates the TOTAL on the next edit unless the item is also clamped (the reason FC6 clamps items[] too, not just the total)."
hive_key_prefix: nlog_
hive_key_formula: "nlog_<istDateStr>_<mealType>_<v5(sortedItems)[:8]> (computeLogKey — clamp does NOT touch the key, only the value fields)"
sync_methods: SyncService.syncNutritionData (fires nutrition_logs + nutrition_log_items rows) + pushSnapshot — the clamped values are what sync to cloud.
restore_methods: >
  SyncService restore of nutrition_logs is local-wins/additive (restore_completeness).
  The clamp is a WRITE-path bound; restore re-hydrates already-clamped cloud rows,
  so no restore change is needed. n/a for a restore-path fix.
cloud_table: nutrition_logs
cloud_columns: "total_calories, total_protein, total_carbs, total_fat, total_fiber (+ nutrition_log_items per-item calories/protein/carbs/fat/fiber) — the clamped values propagate here via syncNutritionData."
contract_test_path: test/contracts/nutrition_calorie_clamp_test.dart
ist_handling: >
  n/a — the clamp mutates numeric value fields only; the IST date logic lives in
  computeLogKey (istDateStr) and is untouched by FC6.
provider_invalidations: >
  Unchanged by FC6 — the existing _invalidateNutritionProviders batch
  (dailyNutritionProvider / nutritionSummaryProvider / recentFoodLogsProvider /
  macroTargetsProvider / aiInsightProvider / foodLogProvider) fires after the
  clamped write, so the UI reflects the bounded values immediately.
telemetry_op_types: >
  nutrition_absurd_value_clamped (ErrorTelemetry.recordNonFatal) — NEW non-fatal
  breadcrumb emitted once per write that actually clamped, so a live spike is
  visible without rejecting the user's entry.
cross_account_guard: >
  user-scoped — the clamp runs inside NutritionWriteService before the
  nutritionBox put, which is already wrapped by the wrapUserScopedBox owner
  guard. The clamp is a pure value transform and carries no cross-account
  surface of its own.
forbidden_patterns_checked: >
  No nutrition write path may put a meal payload without first clamping — logMeal
  / appendItemsToMeal / editLog all call _clampMealPayload before box.put
  (verified by reading each method). The clamp NEVER rejects (offline-first must
  not drop a fat-fingered-but-real entry) — it clamps and emits telemetry.
proposed_fix: >
  Add a per-write clamp with ceilings set FAR above any real meal (meal total
  15000 kcal, item 10000 kcal, macros 2000 g, fiber 500 g — a full day is
  ~2500-4000 kcal, so nothing legitimate is corrupted). Clamp both the meal
  TOTAL and every items[] entry (items resurface on re-edit). Clamp-and-telemetry,
  never reject. Extract the pure clamp into a @visibleForTesting static
  `clampMealPayloadValues(Map)` that mutates in place and returns whether it
  clamped, so the FC6 regression test can assert the bound without a Hive box;
  the private `_clampMealPayload` wrapper owns only the telemetry side-effect.
  Wire the clamp into logMeal / appendItemsToMeal / editLog before each put.
regression_test_planned: >
  test/contracts/nutrition_calorie_clamp_test.dart (2 cases) — (1) a payload with
  total_calories=1,000,000 and an item {calories:1,000,000, protein:999, …}
  clamps total→15000, item calories→10000, macros→2000, and returns true;
  (2) a normal meal (total 650, item 300) is unchanged and returns false.
  Drives the pure clampMealPayloadValues directly (no Hive). FAILS if the clamp
  is removed, a ceiling drifts, or a normal meal is wrongly flagged as clamped.
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: clampMealPayloadValues (l188) extracted pure + wired via _clampMealPayload (l166) into logMeal (l112) / appendItemsToMeal (l254) / editLog (l317) before each box.put; ceilings 15000/10000/2000/500. Behavior identical to the prior inline clamp. }"
  - "{ layer: hive_local_state, status: fixed_in_this_batch, evidence: the clamp runs on the exact Map passed to nutritionBox.put, so the stored nlog_* row can never exceed the ceilings; per-item values bounded so re-edit can't re-inflate. Asserted by test/contracts/nutrition_calorie_clamp_test.dart. }"
  - "{ layer: client_to_server_contract, status: verified, evidence: clamped values are what syncNutritionData writes to nutrition_logs / nutrition_log_items — bounding at the write path bounds the cloud projection too; no schema change. }"
  - "{ layer: postgres_schema, status: not_applicable, evidence: no schema change — a client-side value bound on existing columns. }"
  - "{ layer: edge_function_code_vs_deploy, status: not_applicable, evidence: FC6 is a pure client-side change; no Edge Function touched. }"
impact_analysis: >
  Pre-fix a single absurd value (from the coach log_meal_by_text override or any
  caller) had no numeric bound and flowed straight into total_calories + each
  item's calories, poisoning every downstream sum (daily macro ring, home
  snapshot, weekly report, streak/goal math) — and because append/editLog
  recompute totals from items[], an unbounded ITEM re-inflated the total on the
  next edit. Post-fix every nutrition write clamps both the meal total and each
  item to ceilings set far above any real meal, so no legitimate entry is
  corrupted and any garbage is bounded + surfaced via the
  nutrition_absurd_value_clamped telemetry breadcrumb. Clamp-and-telemetry
  (never reject) preserves offline-first: a fat-fingered-but-real entry is kept,
  not dropped. No migration; no cloud backfill (existing clean rows are within
  the ceilings; a pre-existing absurd row would be re-clamped on its next edit).
closes-diagnose: 4e8f1b
---

# 4e8f1b — Absurd calorie/macro values persisted with no upstream numeric bound

## What happened
`NutritionWriteService` is the single canonical writer for `nutrition_logs`.
Every nutrition mutation routes through `logMeal` / `appendItemsToMeal` /
`editLog`, which compute the meal totals from `items[]`. But there was **no
upper bound** on the numbers. The AI coach's `log_meal_by_text` tool can supply
an `overrideTotalCals`, and the model (or a fat-fingered manual edit) could pass
an absurd value — e.g. `1,000,000 kcal`. That garbage was persisted verbatim
into `total_calories` and each `items[].calories`.

Every reader of a stored `nlog_*` row then summed the poison: the daily macro
ring, the home nutrition snapshot, the weekly AI report, and any streak/goal
math derived from calories-in. Worse, because `appendItemsToMeal` / `editLog`
**recompute** the total from `items[]`, an unbounded per-item value re-inflated
the total on the next edit even after a one-off correction.

## Root cause
No numeric guard between an untrusted caller (the coach tool override, or a
manual edit) and the Hive `put`. The WriteService validated `mealType` and
non-empty `items[]` but never the magnitude of the calorie / macro numbers.

## Fix
1. **Clamp at every write path.** New ceilings — meal total 15000 kcal, item
   10000 kcal, macros 2000 g, fiber 500 g — set FAR above any real meal (a full
   day is ~2500-4000 kcal) so nothing legitimate is corrupted. Both the meal
   TOTAL and every `items[]` entry are clamped (items resurface on re-edit).
2. **Clamp-and-telemetry, never reject.** Offline-first must not silently drop a
   fat-fingered-but-real entry; the clamp emits a `nutrition_absurd_value_clamped`
   non-fatal breadcrumb instead so a live spike is visible.
3. **Testability refactor.** The pure clamp is extracted into a
   `@visibleForTesting static bool clampMealPayloadValues(Map)` that mutates in
   place and returns whether it clamped; the private `_clampMealPayload` wrapper
   owns only the telemetry side-effect. This lets the regression test assert the
   bound without a Hive box.
4. **Regression test** — `test/contracts/nutrition_calorie_clamp_test.dart`
   (rule 21; fails pre-fix).

## Recurrence
Not a prior instance — first numeric-bound gap on the nutrition write path. Same
broad "untrusted value reaches a canonical writer without a bound" class as the
FC7 snapshot-injection guard (9c2d4a) shipped in the same batch, one layer over
(prompt trust vs numeric magnitude).
