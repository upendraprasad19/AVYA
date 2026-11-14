---
bug_id: a3f6c9
date: 2026-09-20
batch: food-logging-observations (Task 4, fix round)
status: fixed
blast_radius: account
symptom: |
  NutritionWriteService.moveMealLog's collision-merge branch (two logs
  retagged into the same destination slot+item-hash bucket) wrote merged
  totals (total_calories/protein/carbs/fat/fiber) WITHOUT ever re-clamping
  them against the FC6 absurd-value ceilings. A merge that pushed a total
  past _kMaxMealCalories (15000) or _kMaxMacroGrams (2000) would persist
  the unclamped value to Hive and, via the sync fan-out, to the cloud
  nutrition_logs row. Found by an independent B-pass review of Task 4's
  moveMealLog implementation, before this code reached main.
concept: nutrition_log_retag
sot_registry_entry: nutrition_log_retag
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: moveMealLog, line: 448 }
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
  - { provider: dailyNutritionProvider, added_in_this_batch: false, reason: "Already invalidated by moveMealLog's existing _invalidateNutritionProviders() call; this fix only reorders an in-method statement, no new invalidation needed." }
telemetry_op_types:
  success: []
  failure: [nutrition_write_service_move_meal_log]
cross_account_guard: Not applicable — moveMealLog reads/writes via the existing HiveService.instance.nutritionBox (already wrapUserScopedBox-guarded); this fix changes statement order only, not box access.
forbidden_patterns_checked: []
proposed_fix: |
  Move the `_clampMealPayload(row)` call from immediately after the
  meal_type/id/log_key/macroUpdates stamping (before the collision-merge
  block) to immediately before `box.put(newKey, row)` (after the
  collision-merge block closes). This mirrors editLog and
  appendItemsToMeal, which both clamp AFTER their own items-recompute for
  the identical reason: a recompute can produce a value outside the
  ceiling and must be re-bounded every time totals are recomputed.
regression_test_planned:
  - test/contracts/nutrition_log_retag_writer_to_reader_test.dart
impact_analysis: |
  Single statement reordering inside moveMealLog (no new fields, no new
  Hive keys, no sync/cloud contract change). The no-collision path is
  unaffected (clamp still runs exactly once, just later in the same
  function, before the only write). The collision path now clamps the
  MERGED row instead of the pre-merge row — strictly more correct, and
  the only behavioral difference is that a merge which pushes a total
  over a ceiling is now bounded (previously it was not). No caller
  currently exists yet (Task 5, which wires a UI picker to moveMealLog,
  has not been built), so there is no production usage to regress against
  — this is a pre-merge fix to code not yet reachable from any UI.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/core/services/nutrition_write_service.dart: _clampMealPayload(row) call moved to line 448, immediately before box.put(newKey, row); flutter analyze reports no issues." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "test/contracts/nutrition_log_retag_writer_to_reader_test.dart's new clamp-order test reads box.get(destinationKey) after a real collision and asserts total_calories == 15000 (clamped), not 18000 (unclamped sum)." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change — nutrition_logs columns and natural key unchanged." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No wire format change; the same total_calories field is still upserted by _syncNutritionLogs, now guaranteed within the existing FC6 ceilings on the collision path too." }
mutation_proven:
  mutated: "Temporarily moved _clampMealPayload(row) back to its pre-fix position (immediately after the macroUpdates stamp, before the collision-merge block), confirmed applied by reading the file."
  result: "Ran only the new clamp-order test (`flutter test test/contracts/nutrition_log_retag_writer_to_reader_test.dart --plain-name \"clamps the POST-merge total\"`): RED — `Expected: <15000> Actual: <18000>`, exit status 1. Reverted the mutation; re-ran the full test file: GREEN, 6/6 tests passed, exit status 0."
  confirmed_applied: "Read the file before and after each edit (Read tool) to confirm the clamp call's line position matched the intended mutation, not just grepped for a string."
---

## Summary

`NutritionWriteService.moveMealLog` (added this same batch, Task 4) recomputes a meal log's
totals when two retagged logs collide at the same destination Hive key (same date + mealType +
item-hash bucket). The FC6 absurd-value clamp (`_clampMealPayload`) was called BEFORE that
recompute, not after, so a collision that produced an out-of-bounds merged total would be written
to Hive (and synced to the cloud `nutrition_logs` row) completely unclamped.

## Root cause

In `moveMealLog`, the statement order was:

1. Stamp `meal_type` / `id` / `log_key`, apply `macroUpdates`.
2. `_clampMealPayload(row);` ← clamps whatever `row` looks like AT THIS POINT.
3. `if (existingAtDestination is Map) { ... }` — on a collision, overwrites
   `row['items']` and all 5 totals with a freshly recomputed union of both sides' items.
4. `box.put(newKey, row)`.

Step 2 clamps a version of `row` that step 3 then overwrites. `editLog` and
`appendItemsToMeal` — the two other methods in this file that recompute totals from an items
list — both call `_clampMealPayload` AFTER their own recompute for exactly this reason (see
`_clampMealPayload`'s own doc comment: "per-item values resurface on re-edit ... so both the
TOTAL and each ITEM must be bounded"). `moveMealLog` broke that invariant on its collision path.

## Fix

Moved `_clampMealPayload(row);` to immediately before `box.put(newKey, row)`, i.e. after the
collision-merge `if` block closes (now at `lib/core/services/nutrition_write_service.dart:448`).
The no-collision path is unaffected — the clamp still runs exactly once, on the final version of
`row`, right before it is persisted.

## Verification

- New behavioral test `moveMealLog clamps the POST-merge total, not the pre-merge one, on a
  collision` in `test/contracts/nutrition_log_retag_writer_to_reader_test.dart`: two logs each
  with `calories: 9000` (under the 15000 per-meal ceiling individually) are moved into the same
  destination slot; asserts the merged `total_calories` is `15000` (clamped), not `18000`
  (the unclamped sum).
- RED phase (mutation): temporarily reverted the clamp call to its pre-fix position; ran the new
  test in isolation → `Expected: <15000> Actual: <18000>`, exit status 1.
- GREEN phase: reverted the mutation; ran the full test file → 6/6 passed, exit status 0.
- Also added: a functional collision/merge test (items union + summed totals across two distinct
  source logs), an invalid-`newMealType` rejection test, and a no-op-same-mealType test (all from
  the same review round).
- `flutter analyze lib/core/services/nutrition_write_service.dart
  test/contracts/nutrition_log_retag_writer_to_reader_test.dart` → No issues found.
- `dart run scripts/check_sot_registry_parity.dart` → PASS, 0 errors (registry line-range
  citations re-derived against the post-edit file after the fix's line-count shift).

## Files changed

- Modified: `lib/core/services/nutrition_write_service.dart` (moved `_clampMealPayload(row)` call;
  added an `items`-key guard on `macroUpdates`, matching `editLog`'s exclusive ownership of the
  `items` key — a related, cheap defensive fix from the same review round).
- Modified: `test/contracts/nutrition_log_retag_writer_to_reader_test.dart` (added 4 tests:
  collision/merge, clamp-order mutation-proof, invalid-mealType rejection, no-op same-mealType).
- Modified: `docs/sot_registry.yaml` (corrected `nutrition_log_retag`'s writer line_range and the
  `todays_meals_card.dart` reader's `fields_read`; re-derived two unrelated, pre-existing
  line-range citations this fix's line-count shift also disturbed — `deleteLog` cross_domain entry
  and one `onStateChanged` reader entry).
- Created: this diagnose-doc.
