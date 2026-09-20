---
bug_id: d9a3f7
date: 2026-09-20
batch: food-logging-observations (fix round, B-pass reviewer B finding 1)
status: fixed
blast_radius: account
symptom: |
  NutritionWriteService.moveMealLog applied a caller's `macroUpdates` map
  to `row` BEFORE the collision-merge branch (destination slot already
  holds a log) ran. The collision-merge branch unconditionally
  recomputes total_calories/protein/carbs/fat/fiber from
  `mergedItems.fold(...)` — overwriting whatever `macroUpdates` had just
  set. A SAVE that both retags a log into a slot with an existing log AND
  edits its macros in the same Edit Macros sheet submission silently
  dropped the macro edit, with no error and no telemetry. Found by
  B-pass reviewer B (lens 6, guard_without_its_mirror), reproduced live
  with a scratch test moving a log into a colliding slot with
  `macroUpdates: {total_calories: 42}` — got `total_calories: 600` (the
  item-fold value) instead of 42.
concept: nutrition_log_retag
sot_registry_entry: nutrition_log_retag
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: moveMealLog, line: 438 }
readers:
  - { file: lib/features/nutrition/widgets/todays_meals_card.dart, method_or_widget: TodaysMealsCard.build, line: 73 }
hive_key_prefix: nlog_
hive_key_formula: "nlog_<istDate>_<mealType>_<itemsHash>"
sync_methods: [_syncNutritionLogs]
restore_methods: [_restoreNutritionLogs]
cloud_table: nutrition_logs
cloud_columns: []
contract_test_path: test/contracts/nutrition_log_retag_writer_to_reader_test.dart
ist_handling: []
provider_invalidations:
  - { provider: dailyNutritionProvider, added_in_this_batch: false, reason: "Already invalidated by moveMealLog's existing _invalidateNutritionProviders() call; this fix only reorders two in-method statement blocks, no new invalidation needed." }
telemetry_op_types:
  success: []
  failure: [nutrition_write_service_move_meal_log]
cross_account_guard: Not applicable — moveMealLog reads/writes via the existing HiveService.instance.nutritionBox (already wrapUserScopedBox-guarded); this fix changes statement order only, not box access.
forbidden_patterns_checked: []
proposed_fix: |
  Move the `if (macroUpdates != null) { ... row.addAll(safeMacroUpdates); }`
  block from immediately after the meal_type/id/log_key stamping (before
  the collision-merge block) to immediately after the collision-merge
  `if` block closes — so macroUpdates is the LAST thing applied to `row`
  before the FC6 clamp, taking precedence over any collision-merge
  recompute rather than being overwritten by it.
regression_test_planned:
  - test/contracts/nutrition_log_retag_writer_to_reader_test.dart
impact_analysis: |
  Single block reordering inside moveMealLog (no new fields, no new Hive
  keys, no sync/cloud contract change). The no-collision path is
  unaffected (macroUpdates still applies exactly once, just later in the
  same function, still before the clamp). The collision path now applies
  macroUpdates AFTER the merge recompute instead of before it — the
  merged item list still determines the destination row's items, but an
  explicit macro override from the caller now sticks instead of being
  silently discarded. No current caller passes both a retag AND
  macroUpdates in production yet (Task 5's Edit Macros sheet is the only
  caller, and always passes both a candidate newMealType and the full
  macro edit together, which is exactly the case this bug affected), so
  this closes the exact failure the SAVE handler is designed to exercise.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/core/services/nutrition_write_service.dart — the macroUpdates apply block now runs at line 438-451, after the collision-merge block (ending line 436) and before the FC6 clamp (line 460); flutter analyze reports 0 warnings on the file." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "test/contracts/nutrition_log_retag_writer_to_reader_test.dart's new test moves two logs into the same destination slot with macroUpdates: {total_calories: 42} and asserts box.get(destinationKey)['total_calories'] == 42, not the merged-item-fold value 600." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change — nutrition_logs columns and natural key unchanged." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No wire format change; _syncNutritionLogs still upserts the same total_calories field, now correctly reflecting an explicit macro override on the collision path too." }
mutation_proven:
  mutated: "Reverted the macroUpdates-apply block to its pre-fix position (immediately after the meal_type/id/log_key stamp, before the collision-merge block), confirmed applied by reading the file."
  result: "Ran the new test in isolation (`flutter test test/contracts/nutrition_log_retag_writer_to_reader_test.dart --plain-name \"macroUpdates on top of a collision-merge\"`): RED — Expected: <42> Actual: <600>, exit status 1. Reverted the mutation; re-ran the full test file: GREEN, all tests passed, exit status 0."
  confirmed_applied: "Read the file (Read tool) before and after each edit to confirm the block's position matched the intended mutation, not just grepped for a string."
---

## Summary

`NutritionWriteService.moveMealLog` (added this same batch, Task 4) applies a caller's
`macroUpdates` map to the row BEFORE the collision-merge branch runs, when the
destination slot already holds a log. The collision-merge branch unconditionally
recomputes every total_* field from the merged item list — silently discarding
whatever `macroUpdates` had just written.

## Root cause

In `moveMealLog`, the statement order was:

1. Stamp `meal_type` / `id` / `log_key`.
2. `if (macroUpdates != null) { row.addAll(safeMacroUpdates); }` — applies the
   caller's explicit macro override.
3. `if (existingAtDestination is Map) { ... }` — on a collision, overwrites
   `row['items']` and all 5 totals with a freshly recomputed union of both sides'
   items, unconditionally.
4. `_clampMealPayload(row);`
5. `box.put(newKey, row)`.

Step 3 always wins over step 2 on the collision path: any macro override the caller
passed is overwritten by the merge recompute before the row is ever clamped or
persisted. The only caller of `moveMealLog` (Task 5's Edit Macros sheet) passes BOTH a
candidate `newMealType` and the full macro edit in a single SAVE — exactly the
scenario this bug silently broke.

## Fix

Moved the `macroUpdates`-apply block to run immediately after the collision-merge `if`
block closes, so it is the last write to `row` before the FC6 clamp — taking
precedence over the merge recompute instead of being overwritten by it. The
no-collision path is unaffected: `macroUpdates` still applies exactly once, still
before the only write.

## Verification

- New behavioral test: two logs, each with distinct calories, are moved into the same
  destination slot with an explicit `macroUpdates: {total_calories: 42}` override;
  asserts the persisted `total_calories` is `42`, not `600` (the merged-item-fold sum).
- RED phase (mutation): reverted the block to its pre-fix position; ran the new test
  in isolation → `Expected: <42> Actual: <600>`, exit status 1.
- GREEN phase: reverted the mutation; ran the full test file → all tests passed.
- `flutter analyze lib/core/services/nutrition_write_service.dart
  test/contracts/nutrition_log_retag_writer_to_reader_test.dart` → No issues found.

## Files changed

- Modified: `lib/core/services/nutrition_write_service.dart` (moved the
  `macroUpdates`-apply block to after the collision-merge block; added a doc comment
  keeping `_allowedMealTypes` in sync with `mealSlotKeys`, a related finding from the
  same review round).
- Modified: `test/contracts/nutrition_log_retag_writer_to_reader_test.dart` (added the
  collision+macroUpdates regression test).
- Created: this diagnose-doc.
