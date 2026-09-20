---
bug_id: 6642b5
date: 2026-09-20
batch: food-logging-observations (Task 2)
tier: s_fix
status: fixed
blast_radius: feature
symptom: |
  Opening the Diet Plan screen shows a blank spinner behind a "Saved Diet Plan Found —
  load it or generate fresh?" modal, even though the saved plan is already available
  synchronously from local Hive storage. The AppBar already has persistent Regenerate
  and Save icons, making the modal pure friction.
concept: diet_plan_immediate_load_no_modal
sot_registry_entry: diet_plan_saved_loaded
writers:
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: _generatePlan, line: 49 }
readers:
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: DietPlanScreen, line: 24 }
hive_key_prefix: saved_diet_plan
hive_key_formula: "null"
sync_methods: [syncSavedDietPlan]
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/widgets/diet_plan_screen_no_modal_test.dart
ist_handling: []
provider_invalidations:
  - { provider: dietPlanProvider, added_in_this_batch: false, reason: "Already invalidated by _savePlan; no change here" }
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — synchronous local Hive read.
forbidden_patterns_checked: []
proposed_fix: |
  Remove the _showLoadSavedPlanDialog method entirely (50 lines). Modify _generatePlan
  to call _loadSavedPlan(savedPlan) directly instead of _showLoadSavedPlanDialog(savedPlan).
  The saved plan renders immediately; users retain access to Regenerate/Save actions via
  the AppBar icons.
regression_test_planned:
  - test/widgets/diet_plan_screen_no_modal_test.dart
impact_analysis: |
  Removes 50 lines of dead dialog code. One call-site change in _generatePlan.
  No Hive key changes, no cloud changes, no provider changes. The _loadSavedPlan method
  (unchanged) is now called directly instead of through a dialog callback.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "diet_plan_screen.dart: _generatePlan method updated (comment + direct call), _showLoadSavedPlanDialog deleted; flutter analyze lib/features/nutrition/screens/diet_plan_screen.dart reports no dead-code warnings (2 pre-existing Share deprecation infos unrelated to this change)." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "diet_plan_saved_loaded contract verified by existing test/contracts/diet_plan_saved_loaded_behavioral_test.dart; synchronous UserRepository.getSavedDietPlan() → _loadSavedPlan call path exercises Hive read correctly." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change — saved_diet_plan Hive key and sync fan-out untouched." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "No wire change; sync fan-out and plan serialization format unchanged." }
mutation_proven:
  mutated: "Temporarily reverted _generatePlan call from _loadSavedPlan(savedPlan) back to _showLoadSavedPlanDialog(savedPlan), confirmed applied by checking the method body."
  result: "Test reddened: find.byType(AlertDialog) then found 1 (the modal), breaking the expect(find.byType(AlertDialog), findsNothing) assertion. After re-applying the fix, test passed."
  confirmed_applied: "grep -c '_showLoadSavedPlanDialog' diet_plan_screen.dart returned 0 post-deletion (no call sites or method definition remain)."
---

## Summary

The Diet Plan screen unnecessarily gates the loaded saved plan behind a modal dialog, blocking the UI while the plan data is already available synchronously in local Hive. The AppBar's Regenerate and Save icons already provide both user actions (generate fresh or modify the loaded plan).

## Root cause

`_generatePlan` (line 49) calls `_showLoadSavedPlanDialog` (line 300), which shows an AlertDialog with Load/Generate buttons. The saved plan is read synchronously via `UserRepository.instance.getSavedDietPlan()` at line 60, so there is no async barrier justifying the modal. The modal is pure friction.

## Fix

- Modified `_generatePlan` (lines 57–68) to call `_loadSavedPlan(savedPlan)` directly instead of `_showLoadSavedPlanDialog(savedPlan)`.
- Deleted the entire `_showLoadSavedPlanDialog` method (lines 300–349).
- The comment now explains: "load it immediately instead of gating behind a dialog — the AppBar's existing Regenerate (:498) and Save (:514) icons already give the user both actions without a blocking modal."

## Verification

- NEW test: `test/widgets/diet_plan_screen_no_modal_test.dart` seeds Hive with a saved diet plan, renders DietPlanScreen, and asserts:
  - `find.byType(AlertDialog)` → findsNothing (modal does not appear)
  - `find.text('Saved Diet Plan Found')` → findsNothing (modal title not shown)
  - `find.byIcon(Icons.refresh)` → findsOneWidget (Regenerate icon present)
  - `find.byIcon(Icons.save_outlined)` → findsOneWidget (Save icon present)
- RED phase: test fails with "Expected: findsNothing, Actual: findsOneWidget" on AlertDialog (the modal exists pre-fix).
- GREEN phase: test passes after fix (modal removed, icons present).
- Mutation-proof: reverting the call back to `_showLoadSavedPlanDialog` makes the test fail exactly as it did before the fix; re-applying passes.
- `flutter analyze lib/features/nutrition/screens/diet_plan_screen.dart` → 0 dead-code warnings (only 2 pre-existing deprecation infos unrelated to this change).

## Files changed

- Modified: `lib/features/nutrition/screens/diet_plan_screen.dart` (2 changes: _generatePlan method + delete _showLoadSavedPlanDialog)
- Created: `test/widgets/diet_plan_screen_no_modal_test.dart` (98 lines, full widget test harness)
- Created: this diagnose-doc
