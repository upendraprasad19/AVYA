---
bug_id: 1261a4
date: 2026-09-20
batch: food-logging-observations
status: fixed
blast_radius: feature
symptom: Opening "LOG TO LUNCH" (or any locked-slot CTA) and logging via the Search tab or the Barcode tab could silently write to a different meal slot than the one the user explicitly tapped — the sheet's `mealTypeProvider` lock was ignored by both tabs, which instead computed their own drifted, independent time-of-day inference.
concept: meal_slot_inference_drift
sot_registry_entry: null
writers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: MealTypeNotifier.build (correct, canonical), line: 1350 }
  - { file: lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart, method_or_widget: "_SearchResultsList onTap (pre-fix: _mealTypeForNow())", line: 202 }
  - { file: lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart, method_or_widget: "_relogFromHistory (pre-fix: _mealTypeForNow())", line: 306 }
  - { file: lib/features/nutrition/widgets/barcode_scan_sheet.dart, method_or_widget: "_BarcodeBodyState._logFood + initState (pre-fix: local _mealType field)", line: 123 }
readers:
  - { file: lib/features/nutrition/widgets/log_food_sheet.dart, method_or_widget: "_LogFoodSheetState.initState postFrameCallback (writes lockedSlot into mealTypeProvider)", line: 66 }
hive_key_prefix: "nlog_"
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/widgets/log_food_sheet_search_respects_locked_slot_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable
forbidden_patterns_checked: []
proposed_fix: Both search_mode_body.dart and barcode_scan_sheet.dart now read/write `mealTypeProvider` (via ref.read/ref.watch/select) instead of computing their own inline time-of-day inference. barcode_scan_sheet.dart's local `_mealType` field and its initState time-window initializer are removed entirely; search_mode_body.dart's `_mealTypeForNow()` helper is deleted. Both now match `scan_meal_section.dart`'s existing correct pattern (ref.read at save time, ref.watch + .select() for the in-sheet slot pill selector).
regression_test_planned:
  - test/widgets/log_food_sheet_search_respects_locked_slot_test.dart
touched_layers_checked:
  - { tier: 1, status: fixed_in_this_batch, evidence: "search_mode_body.dart:202-209 (tap handler), :293-309 (_relogFromHistory), _mealTypeForNow() helper deleted; barcode_scan_sheet.dart:123 (field+initState removed), :175 (_logFood), :559-575 (_buildMealTypeSelector) all now route through mealTypeProvider" }
  - { tier: 2, status: verified, evidence: "nlog_* Hive rows written by NutritionWriteService.logMeal already carry meal_type verbatim from the caller — no Hive schema change; behavioral test asserts the written row's meal_type matches the lock" }
  - { tier: 3, status: not_applicable, evidence: "No Postgres schema change" }
  - { tier: 4, status: not_applicable, evidence: "No Postgres data change" }
  - { tier: 5, status: not_applicable, evidence: "No migration" }
  - { tier: 6, status: not_applicable, evidence: "No Edge Function change" }
  - { tier: 7, status: not_applicable, evidence: "No cron change" }
  - { tier: 8, status: not_applicable, evidence: "No RLS change" }
  - { tier: 9, status: not_applicable, evidence: "No storage change" }
  - { tier: 10, status: not_applicable, evidence: "No secrets change" }
  - { tier: 11, status: not_applicable, evidence: "No external service change" }
  - { tier: 12, status: fixed_in_this_batch, evidence: "test/widgets/log_food_sheet_search_respects_locked_slot_test.dart drives LogFoodSheet(initial: LogFoodMode.search, lockedSlot: 'dinner') end-to-end (type query -> tap result -> assert written nlog_* row's meal_type), with mealTypeProvider forced to a value that disagrees with wall-clock time — proving the lock wins, not the clock" }
impact_analysis: |
  Positive impact: Search-tab and Barcode-tab meal logging now respects an explicit slot lock
  (e.g. "LOG TO LUNCH" opened from a specific meal-slot's + LOG CTA), matching the AI and Scan
  tabs' existing behavior and the retired LogToSlotSheet's slot-aware routing. Users logging via
  Search or Barcode outside the inferred time window (e.g. logging a late lunch at 4pm, or
  catching up on breakfast at noon) will now have their explicit slot choice honored instead of
  being silently overridden.
  No breaking changes. No Hive/cloud schema changes. Barcode tab's meal-type pill selector now
  also participates in the shared mealTypeProvider, so a slot picked on Barcode carries over if
  the user switches tabs within the same LogFoodSheet session (previously each tab's meal-type
  state was fully isolated).
---

## Symptom

Found while implementing Task 6 (consolidating `LogFoodSheet`/`LogToSlotSheet` into one widget),
not from a founder-reported observation. Reading every mode body in `LogFoodSheet` while doing
that consolidation revealed that `search_mode_body.dart` and `barcode_scan_sheet.dart` each
carried their own independent, slightly-different inline copy of time-of-day meal-slot inference,
and **neither one read `mealTypeProvider` at all**.

Concretely: opening "LOG TO LUNCH" (which sets `mealTypeProvider` to `'lunch'` for the sheet's
lifetime via `LogFoodSheet`'s `lockedSlot` postFrameCallback) and then switching to the Search tab
or the Barcode tab and logging a food would silently write the log at whatever `meal_type` the
tab's own local time-of-day heuristic computed — which could easily disagree with the locked slot
the user explicitly tapped to open the sheet. This is a functional regression relative to the
retired `LogToSlotSheet`, which routed Search through a slot-aware redirect.

## Root cause — three independently-drifted meal-slot inference implementations

1. **`nutrition_provider.dart:1350-1362`** `MealTypeNotifier.build()` — the canonical
   `mealTypeProvider` initial-state inference (breakfast 05:00-10:30, lunch 11:30-15:30, dinner
   18:00-22:00, else snacks). This is the one the AI tab and Scan tab (`scan_meal_section.dart`)
   already read/write correctly.
2. **`search_mode_body.dart:318-324`** (pre-fix) `_mealTypeForNow()` — a local, DIFFERENT
   time-window inference (breakfast <11:00, lunch <15:00, dinner <19:00, else snacks — no 05:00
   floor, no 11:30/18:00 boundaries) called from two sites: the "All Foods" search result tap
   handler (`_SearchResultsList.onTap`, line 202-209) and `_relogFromHistory` (the "Recent" tab's
   re-log action, line 293-316). Neither read `mealTypeProvider`, so the lock set by
   `LogFoodSheet.lockedSlot` was silently ignored.
3. **`barcode_scan_sheet.dart`** (pre-fix) a local `String _mealType = 'snacks';` field
   (line 123), computed ONCE in `initState` using yet another simplified time window (breakfast
   <11, lunch <15, dinner <19, else the initial `'snacks'` default — same simplified windows as
   `search_mode_body.dart`'s helper, but computed once at mount rather than live). Read at save
   time (`_logFood`) and by the in-sheet meal-type pill selector (`_buildMealTypeSelector`), and
   mutated locally via `setState` when the user tapped a pill — none of which ever touched
   `mealTypeProvider`, so a lock set before opening the Barcode tab was invisible to it, AND a
   slot picked on the Barcode tab's own pill selector was invisible to every other tab.

None of the two drifted copies respected an explicit slot lock, and their time windows disagreed
with both each other and with the canonical `MealTypeNotifier.build()` windows — the exact
writer/reader-drift bug class this codebase's own root CLAUDE.md §4.1 flags as the default
recurring suspect.

## Fix

Both files now defer entirely to `mealTypeProvider`:

- **`search_mode_body.dart`**: the `_mealTypeForNow()` helper is deleted. The "All Foods" search
  tap handler (line 202-209) and `_relogFromHistory` (line 293-309) now pass
  `mealType: ref.read(mealTypeProvider)`.
- **`barcode_scan_sheet.dart`**: the local `_mealType` field and its `initState` time-window
  initializer are deleted entirely (the class was already `ConsumerStatefulWidget`/`ConsumerState`
  so no widget-type conversion was needed). `_logFood` (line 175) now reads
  `ref.read(mealTypeProvider)`. `_buildMealTypeSelector` (line 559-575) now reads
  `ref.watch(mealTypeProvider)` for the active-pill highlight and calls
  `ref.read(mealTypeProvider.notifier).select(types[i])` on tap — mirroring
  `scan_meal_section.dart`'s already-correct `MealSlotChip` pattern (`ref.read` at save time,
  `ref.watch` + `.select()` for the in-sheet selector).

Both fixes are import-only additions (`import '../providers/nutrition_provider.dart' show
mealTypeProvider;`) plus read/write-site substitutions — no new state, no widget-type changes, no
SoT-registry citation drift (all pre-existing registry citations for `search_mode_body.dart` sit
at line ranges 220-300, below every line touched by this fix; `barcode_scan_sheet.dart` has no
existing registry citations).

## Tests

**`test/widgets/log_food_sheet_search_respects_locked_slot_test.dart`** — behavioral widget test.
Forces `mealTypeProvider` to `'dinner'` (via `LogFoodSheet(lockedSlot: 'dinner')`), a value chosen
to disagree with whatever the real wall-clock time infers, then drives the Search tab end-to-end:
types a query, taps the first live search result (seeded via a real Hive `foodBox` row), and
asserts the resulting `nlog_*` Hive row's `meal_type` field is `'dinner'` — not whatever
`_mealTypeForNow()` would have computed for the current wall-clock time.

- **RED (pre-fix, real run, current wall-clock time was in the lunch window):**
  ```
  Expected: dinner
    Actual: lunch
  the locked slot (dinner) must win over time-of-day inference, which pre-fix logged wherever
  _mealTypeForNow() said instead
  00:03 +1 -1: Search tab logs to the locked slot, not time-of-day inference [E]
  ```
- **GREEN (post-fix, real run):**
  ```
  00:02 +2: All tests passed!
  ```

This is a genuine wall-clock-dependent RED, not a synthetic assertion — the test failed because
the machine's local time actually fell in `_mealTypeForNow()`'s lunch window while the lock said
dinner, which is exactly the drift this fix closes.

Uses real Hive I/O (a real `foodBox` seed row + a real `nutritionBox` write) rather than a mock,
per this repo's own documented pitfall class for widget tests exercising real disk I/O
(`tester.runAsync()` around both the Hive box setup and the write-triggering tap; a leading
`testWidgets` primes `google_fonts`' fallback cache before `path_provider` is ever mocked, per
`test/widgets/diet_plan_screen_no_modal_test.dart`'s established pattern).

## Notes

- Barcode tab's meal-type pill selector now participates in the SAME `mealTypeProvider` state as
  every other tab, closing a second, narrower drift: previously a slot picked on the Barcode
  selector was invisible outside that tab (and vice versa) — switching tabs mid-session lost the
  user's in-sheet choice. Post-fix, a slot chosen on any tab (AI/Scan's `MealSlotChip`, Barcode's
  pill row, or a `lockedSlot` CTA) is visible and consistent across all five tabs for the sheet's
  lifetime.
- `MealTypeNotifier.build()` (`nutrition_provider.dart:1350-1362`) intentionally duplicates
  `inferMealSlot`'s time windows inline (its own comment notes this — "kept inline here to avoid
  an import cycle from the provider layer") and is NOT part of this bug: it is the canonical
  initial-state inference every other tab already deferred to. This fix does not touch it.
- No SoT registry update was needed: `docs/sot_registry.yaml`'s existing `search_mode_body.dart`
  citations (lines 220-300, three occurrences) are all below every line this fix touched, and
  `barcode_scan_sheet.dart` carries no registry citations at all.
