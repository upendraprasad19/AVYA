---
bug_id: 7ad0cc
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: No source-grep guardrail enforced the WriteService SoT contract for `exlog_*`, `wlog_*`, `nlog_*`, `saved_meal_*` Hive prefixes. C-8 + C-12 closed half a dozen bypass sites manually; without a detector, new code can re-open the class. While writing the detector, a 7th bypass was caught — `_relogFromHistory` in `search_mode_body.dart` wrote `nlog_<ts>` directly with the legacy flat-totals shape (no items[]), same C-12 sibling class.
concept: write_service_bypass_detector
sot_registry_entry: workout_logs
writers: []
readers: []
hive_key_prefix: "exlog_*, wlog_*, nlog_*, saved_meal_*"
hive_key_formula: "n/a — detector test scans for any direct .put with these prefixes outside the WriteServices + restore allowlist"
sync_methods: []
restore_methods: []
cloud_table: "n/a — guardrail test, not a runtime path"
cloud_columns: []
contract_test_path: test/contracts/write_service_bypass_detector_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["direct_workoutbox_put_exlog_or_wlog_outside_writeservice", "direct_nutritionbox_put_nlog_or_saved_meal_outside_writeservice", "indirect_id_local_then_box_put_with_prefix_literal"]
proposed_fix: New test file `test/contracts/write_service_bypass_detector_test.dart` with 3 cases. (a) Scan every file in `lib/` for direct `workoutBox.put('exlog_...'` or `workoutBox.put('wlog_...'` outside an allowlist of `workout_write_service.dart`, `sync_service.dart`, and the legacy `workout_repository.dart` legacy fallback path. (b) Same for `nutritionBox.put('nlog_...'` / `'saved_meal_...'` outside `nutrition_write_service.dart` + `sync_service.dart`. (c) Indirect form — detect `<box>.put(<id>, ...)` paired with a `<id> = '<prefix>_…'` declaration anywhere in the same file. Plus close the 7th bypass found by the detector — route `_relogFromHistory` in `search_mode_body.dart` through `NutritionWriteService.logMeal`.
regression_test_planned:
  - test/contracts/write_service_bypass_detector_test.dart (3 cases — direct workout, direct nutrition, indirect form)
---
# Audit T-12: WriteService bypass detector + 7th bypass closure

## Bug

CLAUDE.md §15 names two services as the sole writers for
`exlog_*` / `wlog_*` (WorkoutWriteService) and
`nlog_*` / `saved_meal_*` (NutritionWriteService). Audit findings C-8
and C-12 closed half a dozen bypass sites manually. Without an
automated guardrail, new code can re-open the class — the cost is
silent data loss for AI snapshot / receipts / per-set cloud sync.

## Cause

The SoT contract is a documentation rule (CLAUDE.md §15). The previous
fixes were point-in-time closures; no test scans the codebase for new
violations.

## Fix

**Detector test** at `test/contracts/write_service_bypass_detector_test.dart`
with 3 cases:

1. **Direct workout bypass.** Scan every `lib/**/*.dart` for
   `workoutBox.put('exlog_...` or `'wlog_...`. Allowlist:
   `workout_write_service.dart`, `sync_service.dart`,
   `workout_repository.dart` (the legacy fallback path — slated for
   removal in Phase 8).
2. **Direct nutrition bypass.** Same for `nutritionBox.put('nlog_...`
   or `'saved_meal_...`. Allowlist: `nutrition_write_service.dart`,
   `sync_service.dart`.
3. **Indirect form.** Detect files that BOTH declare a key literal
   matching one of the four prefixes (`final id = 'exlog_…'`) AND
   put it to the matching Hive box (`workoutBox.put(id, …)`). This
   catches the exact shape of the C-8 / C-12 bugs which always
   declared `id` inline before the put.

**7th bypass closed.** The detector caught
`_relogFromHistory` in `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart`
writing `nlog_<ts>` directly with the legacy flat-totals shape. Routed
through `NutritionWriteService.logMeal` with a synthesised single
`FoodItem` (same approach as `FoodLogNotifier.logFood`).

Suite: 1553 pass / 0 fail / 2 skip.

## Related

- 7ad0c8 (C-8 — chat workout bypass)
- 7ad0c9 (C-12 — nutrition bypass expanded scope)
- CLAUDE.md §15 (Hive field-name contract + Sync fan-out contract)
