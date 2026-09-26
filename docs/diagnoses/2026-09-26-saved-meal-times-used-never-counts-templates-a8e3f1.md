---
bug_id: a8e3f1
date: 2026-09-26
batch: reuse-audit-fixes (founder-requested reuse audit)
status: fixed
blast_radius: feature
symptom: |
  Found by the reuse audit. Saved meals are sorted most-used first and show
  "used N×", but the count only ever moved for LEGACY `saved_meal_*` rows.
  The bump lived in `SavedMealsNotifier.relogSavedMeal`, and
  `saved_meals_section.dart` only routes legacy rows there; `meal_*` templates
  (`saveMealAsTemplate`, the only format the UI creates today) re-log straight
  through `NutritionWriteService.relogSavedMeal`, which never bumped. So every
  modern saved meal stayed at 0 uses forever and the sort never changed.
  Second defect, same field: re-saving a meal that already has a template lands
  on the same `meal_<hash>` key and rewrote the row without `times_used`,
  resetting the count (plan-review R2-7).
concept: saved_meals
sot_registry_entry: saved_meals
related_bugs:
  - 7ad0c9 — C-12, which moved the saved-meal writes into NutritionWriteService but left this bump in the notifier
  - b8d5c2 — saved-meal key scheme
recurrence: yes — writer/reader drift: the counter's writer covered one of the two formats its readers show.
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: "NutritionWriteService.relogSavedMeal — bumps times_used for BOTH formats after a successful logMeal (pure bumpSavedMealTimesUsed), then the coalesced syncNutritionData", line: 652 }
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: "NutritionWriteService.saveMealAsTemplate — a re-save keeps the prior times_used", line: 725 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "SavedMealsNotifier.relogSavedMeal — its own bump REMOVED (would double-count legacy rows)", line: 1226 }
readers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: "SavedMealsNotifier.build — most-used sort", line: 1182 }
  - { file: lib/features/nutrition/widgets/saved_meals_section.dart, method_or_widget: "'used N×' label", line: 55 }
  - { file: lib/core/services/sync/sync_nutrition.dart, method_or_widget: "_syncSavedMeals push projection (legacy rows; meal_* rows do not push yet — separate B2 unit)", line: 695 }
hive_key_prefix: "meal_ / saved_meal_"
hive_key_formula: unchanged
sync_methods: [syncNutritionData]
restore_methods: []
cloud_table: user_saved_meals (times_used column, unchanged)
cloud_columns: [times_used]
contract_test_path: test/contracts/saved_meal_relog_times_used_behavioral_test.dart
ist_handling: []
provider_invalidations: [_invalidateNutritionProviders]
telemetry_op_types:
  success: []
  failure: [nutrition_write_service_relog_times_used]
cross_account_guard: Unchanged — nutritionBox via wrapUserScopedBox.
forbidden_patterns_checked:
  - "calling syncSavedMealsNow (non-coalesced) from the service — rejected: logMeal already fired the coalesced syncNutritionData, which runs _syncSavedMeals; a second call marks it dirty so its trailing pass reads the new count. syncSavedMealsNow stays public (pinned by the API snapshot test)."
  - "failing the re-log when the bump fails — rejected: the meal IS logged; the bump is caught and reported, and the WriteResult stays success."
proposed_fix: |
  Move the bump into NutritionWriteService.relogSavedMeal, after a successful
  logMeal, re-reading the row so a concurrent template edit is not overwritten.
  Remove the notifier's bump. saveMealAsTemplate carries forward an existing
  times_used on the same key.
regression_test_planned:
  - test/contracts/saved_meal_relog_times_used_behavioral_test.dart (new, 5) — meal_* counts 0→1→2; legacy 4→5 (once, not twice); missing key fails and writes nothing; re-save keeps 2; pure bump table.
  - test/sync/closeout_maintenance_test.dart — REPOINTED: the "fires a sync after the times_used increment" pin moves from the notifier to the service (ordering: put before sync) and asserts the notifier no longer bumps.
mutation_proven: |
  Bump replaced with a plain copy → 3 of 5 red (meal_*, legacy, re-save).
  times_used preservation replaced with remove → 1 of 5 red (re-save). Both
  compiled; the 12 "Error:" lines in each run are HiveUserSession setup noise
  that also prints in the unmutated green run.
impact_analysis: |
  Modern saved meals now count and sort by use. Existing rows start counting
  from their current value (0 for meal_* rows). Legacy rows count exactly as
  before (one bump per re-log). No cloud effect for meal_* rows until they
  push, which is the separate saved-meal-sync unit.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze clean on changed files; 46/46 saved-meal + nutrition_write_service tests green." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "saved_meal_relog_times_used_behavioral_test.dart — real Hive write → read." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "2026-09-26 read-only query: user_saved_meals has 0 rows for every user, so no cloud count to reconcile." }
---

## Summary

Re-logging a modern saved meal never increased its use count, because the
counter lived in a notifier path only legacy rows took. The service that
performs every re-log now owns the counter, and re-saving a meal keeps it.
