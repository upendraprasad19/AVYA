---
bug_id: e1c5b8
date: 2026-09-20
batch: food-logging-observations (fix round, B-pass reviewer B findings 2-3 + round-2 plan review)
status: fixed
blast_radius: feature
symptom: |
  Four related defects surfaced across B-pass reviewer B and the round-2
  context-blind plan review, all in the same meal-slot vocabulary/
  reactivity surface Task 5-7 of this batch introduced or touched:
  (1) `TodaysMealsCard`'s Snack card writes the singular `'snack'` via
  `MealTypeNotifier.select`, but `NutritionWriteService._allowedMealTypes`
  only accepts the plural `'snacks'` — every write from that entry point
  silently failed `isAllowedMealType` and was dropped with no
  user-visible error. (2) `LogFoodSheet`'s header title read the static
  `widget.lockedSlot` constructor field instead of the live
  `mealTypeProvider` value, so switching tabs and using that tab's own
  slot selector silently changed the write destination while the header
  kept showing the originally-tapped slot. (3) `LogFoodSheet.initState`
  only seeded `mealTypeProvider` when `lockedSlot` was set — opening the
  free-floating "+ LOG FOOD" entry point after an earlier "LOG TO
  BREAKFAST" sheet left the provider on the stale `breakfast` value for
  the rest of the session, since `MealTypeNotifier.build()` only infers
  once per app session. (4) `nutrition_screen.dart`'s Edit Macros SAVE
  predicate compared the user's selection against the raw
  `meal['meal_type']` field instead of the selector's own resolved
  initial value, so a legacy row with `meal_type == 'snack'` (a value no
  selector can ever hold) always read as "the user changed the slot",
  silently retagging the log on every macros-only edit.
concept: meal_slot_ui_selection
sot_registry_entry: not_applicable
writers:
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: MealTypeNotifier.select, line: 1363 }
readers:
  - { file: lib/features/nutrition/widgets/log_food_sheet.dart, method_or_widget: _LogFoodSheetState._buildHeader, line: 117 }
hive_key_prefix: nlog_
hive_key_formula: "nlog_<istDate>_<mealType>_<itemsHash>"
sync_methods: [_syncNutritionLogs]
restore_methods: [_restoreNutritionLogs]
cloud_table: nutrition_logs
cloud_columns: []
contract_test_path: test/nutrition/meal_slot_vocabulary_test.dart
ist_handling: []
provider_invalidations:
  - { provider: mealTypeProvider, added_in_this_batch: false, reason: "Existing provider; this fix corrects what value it is set to (normalized vocabulary) and when it is re-seeded (every unlocked LogFoodSheet open), not its invalidation semantics." }
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — mealTypeProvider is transient UI state, not persisted per-user data.
forbidden_patterns_checked: []
proposed_fix: |
  (1) Normalize `'snack'` to `'snacks'` inside `MealTypeNotifier.select`
  so every write path shares one canonical vocabulary regardless of
  which UI surface (TodaysMealsCard's singular display label vs
  NutritionWriteService's plural storage vocabulary) triggered it.
  (2) Change `LogFoodSheet._buildHeader` to `ref.watch(mealTypeProvider)`
  instead of `widget.lockedSlot`, so the title always reflects the slot a
  save will actually write to.
  (3) Change `LogFoodSheet.initState` to unconditionally re-infer
  (`widget.lockedSlot ?? inferMealSlot(DateTime.now())`) instead of only
  seeding the provider when locked, closing the stale-carryover leak on
  every unlocked open.
  (4) Extract `resolveInitialMealSlot(meal)` as a pure function applying
  the same "unknown/legacy value falls back to snacks" rule, and use its
  return value for BOTH the selector's initial value and the SAVE
  handler's "did the user change it?" comparison, so they cannot diverge.
regression_test_planned:
  - test/nutrition/meal_slot_vocabulary_test.dart
  - test/widgets/log_food_sheet_locked_slot_test.dart
  - test/widgets/log_food_sheet_search_respects_locked_slot_test.dart
impact_analysis: |
  All four fixes are localized to the meal-slot selection/display layer;
  none change the Hive key formula, sync methods, or cloud schema for
  `nutrition_log_retag`. (1) only affects which string value
  mealTypeProvider is ever set to — a superset of previously-valid values
  now also includes what was previously silently rejected. (2) and (3)
  only affect what LogFoodSheet reads/writes to a provider that already
  existed; no new state introduced. (4) only affects the Edit Macros
  SAVE predicate's comparison operand — the selector's actual displayed
  options and moveMealLog's own validation are unchanged. Combined,
  these close every path a user could hit "meal silently didn't log" or
  "meal silently retagged" without any error surfacing, all within the
  same feature-tier surface (lib/features/nutrition/**).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ reports 0 warnings across all 4 touched files (nutrition_provider.dart, log_food_sheet.dart, nutrition_screen.dart, meal_slot_inference.dart)." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "test/widgets/log_food_sheet_search_respects_locked_slot_test.dart's new 'snack'-writes-'snacks' end-to-end test asserts the persisted nlog_* row's meal_type field is 'snacks', not the dropped/absent write the pre-fix code produced." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change — this fix corrects a client-side vocabulary/reactivity bug; the cloud nutrition_logs meal_type column and its accepted values are unchanged." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No wire-format change; _syncNutritionLogs upserts the same meal_type field, now always populated with a value NutritionWriteService actually accepts." }
mutation_proven:
  mutated: "(1) Removed the ternary normalization in MealTypeNotifier.select, reverting to `state = mealType;` verbatim. (2) Reverted LogFoodSheet._buildHeader's title to read `widget.lockedSlot!` instead of `currentSlot`. (3) Reverted LogFoodSheet.initState to the pre-fix `if (slot != null) { ... }` conditional seed. (4) Reverted nutrition_screen.dart's resolveInitialMealSlot extraction, comparing against a raw `currentMealType` field again. Each mutation confirmed applied by reading the file before running tests, then reverted and confirmed re-applied correctly."
  result: "(1) test/nutrition/meal_slot_vocabulary_test.dart: 2 of 8 tests reddened (the select-normalization assertions). (2) test/widgets/log_food_sheet_locked_slot_test.dart: 'header title stays in sync' reddened, sibling re-infer test unaffected — correct isolation. (3) Same file: 'opening unlocked re-infers the current slot' reddened, header-sync sibling unaffected. (4) test/nutrition/meal_slot_vocabulary_test.dart: 3 of 8 tests reddened (the resolveInitialMealSlot-fold assertions). Each mutation reverted individually and its corresponding test file re-run to confirm full green before moving to the next."
  confirmed_applied: "Read (Read tool) each file before and after every mutate/revert cycle to confirm the specific line matched the intended state, not just grepped for a string."
---

## Summary

Four related defects in the meal-slot selection/display layer, surfaced by two
independent review passes over this batch's Tasks 5-7:

1. **Snack vocabulary mismatch** (reviewer B, P1-adjacent — writer/reader drift): the
   Home/Nutrition "Snack" card writes the singular display label `'snack'`, but the
   write-side allowlist only accepts the plural `'snacks'`.
2. **Header staleness** (reviewer B, P2 guard_without_its_mirror): `LogFoodSheet`'s
   title read a static constructor field instead of the live provider it claims to
   track.
3. **Stale slot carryover** (round-2 plan review): the free-floating "+ LOG FOOD"
   entry point could silently inherit an earlier locked sheet's slot for the rest of
   the session.
4. **Edit Macros false-positive retag** (round-2 plan review): the SAVE predicate
   compared against a value the selector could never actually produce, so every
   macros-only edit on a legacy row was misread as an intentional slot change.

## Root cause

All four share the same underlying pattern: two places computing or comparing the
"current meal slot" independently, using different vocabularies or different
timing, instead of a single shared source. (1) is a vocabulary drift between a
display-only label and a storage-layer allowlist. (2)/(3) are `LogFoodSheet` reading
its own constructor param instead of the provider it exists to seed. (4) is a SAVE
handler comparing against the field it read FROM, not the field the selector was
actually initialized WITH.

## Fix

1. `MealTypeNotifier.select` normalizes `'snack'` → `'snacks'` before setting state.
2. `LogFoodSheet._buildHeader` now watches `mealTypeProvider` for its title instead
   of reading `widget.lockedSlot`.
3. `LogFoodSheet.initState` unconditionally seeds `mealTypeProvider` with
   `widget.lockedSlot ?? inferMealSlot(DateTime.now())` on every open, locked or not.
4. Extracted `resolveInitialMealSlot(meal)` in `meal_slot_inference.dart`, used for
   both the Edit Macros selector's initial value and its SAVE comparison, so they
   cannot diverge.

Additional cleanup landed in the same review round: deleted the now-dead
`food_search_sheet.dart` (zero live callers — `nutrition_screen.dart`'s slot CTAs now
route exclusively through `showLogFoodSheet`), removed the now-redundant
`_allowedSlotKeys` field in `nutrition_screen.dart` in favor of the shared
`mealSlotKeys` constant, and corrected `meal_slot_inference.dart`'s and
`todays_meals_card.dart`'s doc comments, which had drifted from what the code
actually does.

## Verification

- New test file `test/nutrition/meal_slot_vocabulary_test.dart` (8 tests): select
  normalization (`'snack'`→`'snacks'`, plural passthrough, other slots unaffected),
  `resolveInitialMealSlot` (known values, legacy/unknown fallback to `'snacks'`), and
  `mealSlotLabel`/`mealSlotEmoji` singular/plural equivalence.
- `test/widgets/log_food_sheet_locked_slot_test.dart` (4 tests, 2 new): header stays
  in sync when the live slot changes after open; opening unlocked re-infers the
  current slot rather than an earlier sheet's leftover value.
- `test/widgets/log_food_sheet_search_respects_locked_slot_test.dart` (3 tests, 1
  new): the singular-`'snack'`-CTA end-to-end path persists a `meal_type: 'snacks'`
  row, not a silently-dropped write.
- Mutation proof for all 4 fixes (see `mutated`/`result` above) — each isolated
  revert reddened exactly the test(s) written for that fix, no more, no less.
- `flutter analyze lib/` — 0 warnings; the 45 pre-existing infos are all in files
  untouched by this diff (confirmed via `git diff` hunk ranges vs. the analyze
  output's line numbers).

## Files changed

- Modified: `lib/features/nutrition/providers/nutrition_provider.dart` (select
  normalization; `MealTypeNotifier.build()` now delegates to `inferMealSlot` instead
  of an inline duplicate).
- Modified: `lib/features/nutrition/services/meal_slot_inference.dart` (added
  `resolveInitialMealSlot`).
- Modified: `lib/features/nutrition/screens/nutrition_screen.dart` (Edit Macros SAVE
  predicate now uses `resolveInitialMealSlot`; removed dead `_allowedSlotKeys` field;
  `MealSlotSelector.slots` now aliases the shared `mealSlotKeys` constant).
- Modified: `lib/features/nutrition/widgets/log_food_sheet.dart` (header watches
  `mealTypeProvider`; `initState` unconditionally re-infers).
- Modified: `lib/features/nutrition/widgets/todays_meals_card.dart` (corrected
  class-level and `onLogSlot` doc comments).
- Modified: `lib/features/nutrition/widgets/log_food_modes/search_mode_body.dart`
  (removed a stale "legacy showFoodSearchSheet" doc-comment reference).
- Deleted: `lib/features/nutrition/widgets/food_search_sheet.dart` (dead code, zero
  live callers — landed in commit `e3c96e08`, this batch's prior fix-round commit,
  since it was already staged when that commit was made; noted here for completeness
  since it was found by the same review finding this doc otherwise covers).
- Modified: `test/nutrition/meal_slot_vocabulary_test.dart` (new file),
  `test/widgets/log_food_sheet_locked_slot_test.dart`,
  `test/widgets/log_food_sheet_search_respects_locked_slot_test.dart`.
- Modified: `lib/features/nutrition/CLAUDE.md` (corrected the
  `log_food_sheet_locked_slot_test.dart` test-coverage description, which previously
  overclaimed "durability" for what is actually reactive/live behavior; also removed
  the stale `food_search_sheet.dart` listing and its "locks... for the sheet's
  lifetime" description of `log_food_sheet.dart`, and corrected the "Diet-plan meals
  not visible" pitfall row's dead `showFoodSearchSheet` reference — all found by a
  scoped re-review of this fix round, 2026-09-20).
- Modified: `supabase/functions/CLAUDE.md` (added the missing `gemini_failure_alert`
  SoT contract row for the feature Tasks 9-10 shipped with no nested-CLAUDE.md entry
  at all — found by the same scoped re-review, filed alongside this doc rather than
  its own since it is a documentation gap, not a code defect).
- Corrected `concept`/`sot_registry_entry` in this doc's own frontmatter from
  `nutrition_log_retag` to `not_applicable` (was internally inconsistent with this
  doc's own `cross_account_guard` field, which already correctly describes
  `mealTypeProvider` as transient UI state — `nutrition_log_retag` is the durable
  Hive/cloud rekey concept `moveMealLog` owns, a different contract). Corrected two
  `line:` citations (1362→1363, 121→117) that had drifted by one line each. Both
  found by the scoped re-review of this fix round.
- Created: this diagnose-doc.

## Residual, examined and rejected as not worth shipping

The scoped re-review also flagged a real but low-severity **P3**: `LogFoodSheet`'s
header seed write is deferred to a `WidgetsBinding.instance.addPostFrameCallback`
(required — mutating a Riverpod provider synchronously in `initState` throws), so the
sheet's very first `build()` reads whatever slot `mealTypeProvider` held BEFORE this
sheet opened, not the slot it was just opened locked to. In a live app this could
theoretically flash the wrong locked-slot label for one frame before self-correcting.

A fix was drafted (an `_initialSlot`/`_providerSeeded` fallback, read on the first
frame only) and a regression test written to catch it (pre-seed the provider with a
different slot, `pumpWidget`, then a single `tester.pump()` — not `pumpAndSettle` —
before asserting). **Mutation-proof reddened ZERO tests**: `TestWidgetsFlutterBinding`
resolves `addPostFrameCallback`s scheduled during a widget's `initState` within the
SAME `pumpWidget()` call, before it returns — so there is no window a standard
widget-test `pump()` can observe between "first build" and "seed write landed." The
test provided no discriminating power; per root CLAUDE.md §4.4 rule 21 ("a mutation
that reddens ZERO tests is not proof the case is already covered"), a green check
with no discriminating input is worse than no check, so both the fix and the test
were reverted rather than shipped unverified.

**Accepted as-is**: the flash, if it exists at all in a real rendering pipeline
(untested — the widget-test harness cannot observe it), is a single frame (~16ms) on
sheet open, for the locked-slot title text only, self-correcting on the very next
frame. Lower severity than the residual this doc's own P2-4-equivalent items
document, and fixing it would add new state (`_initialSlot`/`_providerSeeded`) with
zero test coverage protecting it against a future regression — a worse trade than
leaving the existing, well-tested reactive-header behavior alone.
