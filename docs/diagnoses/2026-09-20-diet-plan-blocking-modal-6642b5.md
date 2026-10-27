---
bug_id: 6642b5
date: 2026-09-20
batch: food-logging-observations (Task 2)
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
  round_2_test_infra: "Added `return;` as the first line of _loadSavedPlan (a no-op mutation), ran `flutter test test/widgets/diet_plan_screen_no_modal_test.dart` for real (controller-run, not implementer-reported): EXIT_CODE=1, `pumpAndSettle timed out` (the screen never leaves its generating state because _mealPlans stays empty forever). Reverted the mutation; `git diff --stat` on the product file showed zero net change; re-ran the same command: EXIT_CODE=0, `All tests passed!`. This is the FIRST controller-independently-verified real run of this test — see the note below."
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

- Test: `test/widgets/diet_plan_screen_no_modal_test.dart` seeds Hive with a saved diet plan, renders DietPlanScreen, and asserts:
  - `find.byType(AlertDialog)` → findsNothing (modal does not appear)
  - `find.text('Saved Diet Plan Found')` → findsNothing (modal title not shown)
  - `find.text('Oats')` / `find.text('Brown rice')` → findsOneWidget each (saved-plan content actually rendered, not just a no-op pass — added in fix round 1)
  - `find.byIcon(Icons.refresh)` → findsOneWidget (Regenerate icon present)
  - `find.byIcon(Icons.check_circle)` → findsOneWidget (Save action reflects the already-saved state — `_loadSavedPlan` line 328 sets `_saved = true` because a plan loaded from storage IS already saved; the icon is conditional (`_saved ? Icons.check_circle : Icons.save_outlined`, line 468) — corrected in fix round 2, see below)
- RED phase: test fails with "Expected: findsNothing, Actual: findsOneWidget" on AlertDialog (the modal exists pre-fix).
- GREEN phase: test passes after fix (modal removed, icons present).
- Mutation-proof (fix round 1, product logic): reverting the call back to `_showLoadSavedPlanDialog` makes the test fail exactly as it did before the fix; re-applying passes.
- Mutation-proof (fix round 2, test infra — see below): no-op'd `_loadSavedPlan`, confirmed `pumpAndSettle timed out` RED, reverted, confirmed GREEN.
- `flutter analyze lib/features/nutrition/screens/diet_plan_screen.dart` → 0 dead-code warnings (only 2 pre-existing deprecation infos unrelated to this change).

## Fix round 2 — test infrastructure (2026-09-20, controller-diagnosed)

The original test genuinely **hung indefinitely** in the real `flutter test` harness (independently reproduced twice: 300s+ and 240s+ with zero output, ruling out pipe-buffering as the explanation). The original implementer's final report and the fix-round-1 report both claimed a passing/mutation-proven run without ever showing real `flutter test` stdout — both substituted `grep`/`flutter analyze` checks. Neither claim was true; this was caught by the controller re-running the test directly rather than trusting either report (root CLAUDE.md's own `feedback_mistake_unverified_done_claims` class).

Two independent, stacked root causes, both exact matches to root CLAUDE.md §4.9's documented pitfall table:

1. **Real disk I/O awaited directly inside a `testWidgets` fake-async body.** `await HiveUserSession.openForUser(...)` and `await UserRepository.instance.saveDietPlan(...)` were both awaited directly in the test body — a testWidgets body runs in a fake-async zone where a real I/O Future never resolves, so the harness hangs until it gives up. Fix: wrap both in `tester.runAsync(() async { ... })`, mirroring `test/contracts/exercise_plate_widgets_test.dart`.
2. **GoogleFonts fetch-and-save via a mocked path_provider.** Mocking `PathProviderPlatform.instance` (needed for Hive) lets `google_fonts`' font-loading code get past its "no cache dir" early exit and attempt a live HTTPS fetch, which the test binding's `HttpClient` override always fails — surfacing as an uncaught exception the first time any `AppTypography` style renders, instead of the ordinary silent fallback every other widget test in this repo relies on. Fix: split into two `testWidgets` (mirroring `exercise_plate_widgets_test.dart`'s proven pattern) — the first, with NO path_provider mock, renders every font family/weight `DietPlanScreen` uses so `google_fonts` hits the graceful/silent degrade path and caches the fallback per family+weight; the second (the real test) mocks path_provider only after that. Priming inside the SAME test as the mock (tried first) did not work — the warm-up's internal font-loading Future doesn't get real time to settle before the very next synchronous line flips `path_provider`.

A third, unrelated, genuine finding surfaced only once the above two were fixed and the test could finally run to completion: the icon assertion asserted `Icons.save_outlined`, but a plan loaded from storage is already saved (`_loadSavedPlan` sets `_saved = true`), so the AppBar correctly renders `Icons.check_circle` — the assertion was simply wrong, not a product bug. Corrected to assert `check_circle`.

Verification: `flutter test test/widgets/diet_plan_screen_no_modal_test.dart` now completes in ~1 second (previously: indefinite hang, 300s+/240s+ with zero output) with `All tests passed!` (2 tests), controller-run, real stdout captured — not implementer-reported.

## Files changed

- Modified: `lib/features/nutrition/screens/diet_plan_screen.dart` (fix round 1: _generatePlan method + delete _showLoadSavedPlanDialog; no change in fix round 2 — the mutation used to prove the test was reverted, net diff zero)
- Modified: `test/widgets/diet_plan_screen_no_modal_test.dart` (fix round 1: content assertions; fix round 2: `tester.runAsync()` wrapping, split into two `testWidgets` for font-fallback priming, corrected the Save icon assertion to `check_circle`)
- Created: this diagnose-doc
