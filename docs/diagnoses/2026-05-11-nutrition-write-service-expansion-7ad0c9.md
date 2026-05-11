---
bug_id: 7ad0c9
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 4 nutrition mutations bypassed `NutritionWriteService` (the documented sole writer per CLAUDE.md §15). `SavedMealsNotifier.saveMealPreset` / `.relogSavedMeal` / `.deleteSavedMeal` + `FoodLogNotifier.restoreFoodLog` each wrote `nutritionBox` rows directly, with `relogSavedMeal` ALSO firing the legacy `NutritionRepository.syncLogToSupabase` double-write. Side effects — provider-invalidation drift (notifiers fired their own list, didn't share the WriteService canonical batch), legacy flat-totals shape on relog (no `items[]`), and the double cloud-write path producing 2 rows per re-log when the timing aligned. Additionally `WaterNotifier.addWater` + `.decrement` built non-IST date keys for `water_ml_<date>`, breaking the IST-anchored contract per CLAUDE.md.
concept: nutrition_write_service_expansion
sot_registry_entry: saved_meals
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: saveMealPreset, line: 448 }
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: deleteSavedMeal, line: 508 }
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: restoreFoodLog, line: 540 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: SavedMealsNotifier (delegators), line: 990 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: FoodLogNotifier.restoreFoodLog, line: 919 }
hive_key_prefix: "saved_meal_*, nlog_*, water_ml_*"
hive_key_formula: "saved_meal_<ts>, nlog_<istDate>_<itemsHash>, water_ml_<istDate>"
sync_methods: ["SyncService.syncNutritionData()", "SyncService.pushSnapshot()", "SyncService.syncSavedMealsNow()"]
restore_methods: []
cloud_table: user_saved_meals
cloud_columns: [id, user_id, name, items, total_calories, total_protein, total_carbs, total_fat, total_fiber, created_at]
contract_test_path: test/contracts/saved_meals_writer_to_reader_test.dart
ist_handling: ["istDateStr(DateTime.now()) for water_ml_ key (addWater + decrement)"]
provider_invalidations: [dailyNutritionProvider, weeklyNutritionProvider, nutritionSummaryProvider, recentFoodLogsProvider, foodLogProvider, macroTargetsProvider, aiInsightProvider]
telemetry_op_types:
  success: [nutrition_write_save_meal_preset, nutrition_write_delete_saved_meal, nutrition_write_restore_food_log]
  failure: [nutrition_write_save_meal_preset_failed]
cross_account_guard: yes
forbidden_patterns_checked: ["savemealpreset_direct_nutritionbox_put", "deletesavedmeal_direct_nutritionbox_delete", "restorefoodlog_direct_nutritionbox_put", "relogsavedmeal_legacy_syncLogToSupabase_double_write", "addwater_manual_date_format_not_istDateStr"]
proposed_fix: Add `saveMealPreset(name, totalCalories, totalProtein, totalCarbs, totalFat, totalFiber, items)`, `deleteSavedMeal(savedMealKey)`, and `restoreFoodLog(log)` to NutritionWriteService. Route the 4 nutrition_provider notifier methods through them. Drop the legacy `NutritionRepository.syncLogToSupabase` double-write inside `relogSavedMeal` (WriteService.logMeal handles cloud projection). Fix `addWater`/`decrement` to use `istDateStr(DateTime.now())` for the water_ml_ key.
regression_test_planned:
  - Updated test/contracts/saved_meals_writer_to_reader_test.dart (accepts WriteService location for `saved_meal_` literal)
  - Updated test/safety/provider_invalidation_test.dart (accepts WriteService delegation for restoreFoodLog)
  - Updated test/sync/sync_gap_test.dart (recognises WriteService delegation; whole-file scan replaces sliced-body scan)
  - Updated test/contracts/water_logs_writer_to_reader_test.dart (addWater/decrement now use istDateStr)
  - Updated docs/sot_registry.yaml (added writers under saved_meals concept; corrected waterTargetProvider line range after refactor)
---
# Audit C-12 (expanded): nutrition WriteService bypasses + IST drift on water

## Bug

Per CLAUDE.md §15 "Hive field-name contract" and "Sync fan-out
contract", `NutritionWriteService` is the documented sole writer for
nutrition Hive mutations. Pre-fix, 4 notifier methods bypassed it:

- `SavedMealsNotifier.saveMealPreset` (line 1001) — direct
  `nutritionBox.put('saved_meal_<ts>', ...)`.
- `SavedMealsNotifier.relogSavedMeal` (line 1031) — direct
  `nutritionBox.put('nlog_<ts>', flatTotalsMap)` with no `items[]`
  array. Also fired `NutritionRepository.syncLogToSupabase` for the
  same row — double-write path. Plus a sibling direct put on the
  saved meal row to increment `times_used`.
- `SavedMealsNotifier.deleteSavedMeal` (line 1075) — direct
  `nutritionBox.delete(id)`.
- `FoodLogNotifier.restoreFoodLog` (line 919) — direct
  `nutritionBox.put(key, log)`.

Side effects:

- **Provider-invalidation drift.** Each notifier hand-rolled its own
  invalidation list; the WriteService canonical
  `_invalidateNutritionProviders` (dailyNutritionProvider +
  weeklyNutritionProvider + nutritionSummaryProvider +
  recentFoodLogsProvider + foodLogProvider + macroTargetsProvider +
  aiInsightProvider) wasn't fully covered. A re-logged saved meal
  wouldn't refresh the AI insight card; a restored food log wouldn't
  refresh the macro target progress.
- **Legacy flat-totals shape on `relogSavedMeal`.** The directly-put
  row had no `items[]` array, so `_syncNutritionLogs` cloud
  projection wrote 0 rows to `nutrition_log_items` (Test #11 C1 sibling
  bug class). AI coach + weekly-report saw "no items" server-side.
- **Double cloud-write on `relogSavedMeal`.** `nutritionBox.put` →
  `_syncNutritionLogs` fan-out (canonical path) AND
  `NutritionRepository.syncLogToSupabase` direct call (legacy path).
  When timing aligned, 2 rows in `nutrition_logs` for one re-log.

`WaterNotifier.addWater` + `.decrement` separately built the
`water_ml_<date>` Hive key with manual `'${year}-${month}-${day}'`
formatting (UTC / device-local, not IST). The IST drift class
documented in CLAUDE.md and Test #11 B1+B2+M3 sweeps; surfaced now
because the contract test for water_logs explicitly asserts
`istDateStr` usage.

## Cause

Same as C-8 — the WriteService SoT was introduced in APK Test #6 with
the explicit contract documented in CLAUDE.md §15. Multiple call sites
were migrated then, but these 4 nutrition mutations were missed because
the audit sweep didn't include the SavedMealsNotifier / FoodLogNotifier
restore path.

The IST drift on water is a pre-existing bug that became visible when
the contract test was updated. Fixed in the same batch to keep the
test suite green.

## Fix

**Three new methods on NutritionWriteService**:

```dart
Future<WriteResult> saveMealPreset({ name, totalCalories, totalProtein,
                                      totalCarbs, totalFat, totalFiber,
                                      items });
Future<WriteResult> deleteSavedMeal(String savedMealKey);
Future<WriteResult> restoreFoodLog(Map<String, dynamic> log);
```

Each writes the Hive row, fires `_invalidateNutritionProviders`, and
fan-outs `syncNutritionData() + pushSnapshot()`.

**4 notifier methods refactored to delegate**:

- `SavedMealsNotifier.saveMealPreset` → `NutritionWriteService.saveMealPreset`.
- `SavedMealsNotifier.relogSavedMeal` → `NutritionWriteService.relogSavedMeal`
  (existing method). Notifier keeps the `times_used` counter
  increment (small targeted update). Drops the legacy
  `NutritionRepository.syncLogToSupabase` double-write.
- `SavedMealsNotifier.deleteSavedMeal` → `NutritionWriteService.deleteSavedMeal`.
- `FoodLogNotifier.restoreFoodLog` → `NutritionWriteService.restoreFoodLog`.

**Water IST fix**:

`WaterNotifier.addWater` + `.decrement` now build the `water_ml_<date>`
key with `istDateStr(DateTime.now())`.

## Regression tests

Suite: 1544 pass / 0 fail / 2 skip.

- Updated `test/contracts/saved_meals_writer_to_reader_test.dart` to
  accept the WriteService location for the `saved_meal_` literal.
- Updated `test/safety/provider_invalidation_test.dart` to recognise
  the WriteService delegation for `restoreFoodLog`.
- Updated `test/sync/sync_gap_test.dart` to use a whole-file scan for
  `NutritionWriteService.instance.saveMealPreset` / `.deleteSavedMeal`
  (multi-line param blocks defeated the sliced-body heuristic).
- `test/contracts/water_logs_writer_to_reader_test.dart` passes
  unchanged once `addWater`/`decrement` use `istDateStr`.
- Updated `docs/sot_registry.yaml`:
  - Added the WriteService writers under the `saved_meals` concept.
  - Corrected the `waterTargetProvider` line range after the
    notifier shrank.

## Related

- 7ad0c8 (C-8 — sibling workout WriteService bypass)
- CLAUDE.md §15 (Hive field-name contract + Sync fan-out contract)
- Test #11 C1 (legacy `nlog_*` saves without `items[]` — same class)
