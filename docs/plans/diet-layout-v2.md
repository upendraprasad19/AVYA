# Diet chart screen: layout v2 (founder observation, 2026-11-15)

Branch `diet-layout-v2`. Blast radius `feature`: only `lib/features/nutrition/**`, `lib/shared/widgets/**`
(chips used by Edit Profile are NOT changed), tests and docs. No migration, no Edge Function, no generator change,
no new stored value. Tier M (§4.12.6: more than two product files). Execution mode (§4.12.7): inline, one worktree.

## 1. Founder words (2026-11-15, saved in project memory)

Title "Diet chart" with the food-type subtitle. IMMEDIATELY below, ONE row of three columns: (a) food type as a
DROPDOWN listing every option, (b) diet strategy as a dropdown, (c) Supplements with the on/off toggle. Then the
calorie block and the macro block, BOTH compact, so the diet itself starts right after the calorie block and the
user sees at once that the diet has started. The supplements card stays at the END of the diet when the toggle is
on (already built, collapsed). This replaces the two scrolling chip rows and the separate switch card.

## 2. Writer and reader (unchanged by this batch)

| Concept | Writer (file) | Reader |
|---|---|---|
| food type | `UserProfileNotifier.setFoodType` via the screen's `_changeFoodType` (`diet_plan_screen.dart`) | `DietPlanNotifier`, generator, tag |
| strategy | `UserProfileNotifier.setDietStrategy` via `handleDietStrategyTap` (`diet_strategy_actions.dart`) | `effectiveMacroTargets` readers |
| supplements | `UserProfileNotifier.setDietSupplements` via `handleDietSupplementsToggle` | `dietSupplementsActive` |

This batch moves only the CONTROLS. Each control still ends in the same write door; no new write path, no new reader.

## 3. Change

1. `widgets/diet_plan_dropdown.dart` (new): `DietPlanDropdown<T>`, a labelled 44 dp field (the `AppColors.input` box,
   `AppRadius` border) around a `DropdownButton<T>`; the menu lists every option, an option can be disabled; the
   closed field shows the short text. Menu items keep the old chip keys (`food_type_chip_<key>`,
   `diet_strategy_chip_<key>`, `diet_strategy_pro_badge_<key>`) so the pins stay valid; the field itself carries
   `diet_plan_food_type_dropdown` / `diet_plan_strategy_dropdown`.
2. `diet_strategy_section.dart`: `DietStrategySection` becomes `DietStrategyField` (the dropdown column, same
   `_busy` guard, same `handleDietStrategyTap`) plus `DietStrategyFootnotes` (the Keto note, the vegan-Keto reason,
   the paused hint) shown under the row.
3. `diet_supplements_section.dart`: `DietSupplementsSection` becomes `DietSupplementsField` (label + a field with
   On/Off text, the PRO lock and the same `Switch` key `diet_supplements_switch`) plus `DietSupplementsFootnotes`
   (paused hint, needs-date-of-birth hint). A minor gets no column (the row is two columns); an unreadable date
   of birth gets the column with no switch and the hint under the row (same rules as today, one eligibility door).
4. `widgets/diet_plan_settings_row.dart` (new): `DietPlanSettingsRow` = the Row of the three fields (8 dp gap,
   `Expanded` each) and, below it, the footnotes.
5. `diet_plan_macro_cards.dart`: `DietPlanTdeeCard` and `DietPlanMacroTargetsCard` made compact (one 48 dp line
   each: small label above a 16 sp value; macros as three coloured inline figures), same names and same numbers.
6. `diet_plan_screen.dart`: app bar title `Diet chart` (the subtitle tag is unchanged); body order = settings row,
   calorie card, macro card, strategy note, meals, supplements card. The food-type block and both section mounts
   leave the screen; the file shrinks (792 lines before, Gate 43 cap 800).
7. Dead code: `ChipScrollRow` and the `scrollable:` parameter of `FoodTypeChips` / `DietStrategyChips` have no
   caller after this change (Edit Profile uses the wrap). Delete them with their test (`chip_scroll_row_test.dart`)
   in this batch (§4.6 step 4: no "later").

## 4. Tests

- `test/nutrition/diet_plan_layout_v2_test.dart` (new): the three fields share one top edge and sit above the
  calorie card; the macro card sits above the first meal; the settings row is above the calorie block; the title
  reads `Diet chart`; every FoodType is listed in the open menu; Keto is disabled for Vegan; the closed food-type
  field shows the stored type; a 360 dp wide screen has no overflow with every food type and strategy selected
  and Supplements on; compact card heights are at most 60 dp each.
- Existing pins moved from "tap the chip" to "open the dropdown, tap the item" through one helper per file
  (`diet_plan_strategy_screen_test.dart`, `diet_strategy_selector_test.dart`,
  `diet_plan_supplements_screen_test.dart`); the chip-row layout test is replaced by the new layout test.
- Mutants (every one must redden something): M1 swap the order of the row and the calorie card; M2 drop the
  `enabled: false` on a disabled strategy item; M3 route the food-type dropdown to the strategy writer; M4 drop the
  minor-hides-supplements branch; M5 title back to "Diet Plan"; M6 widen the TDEE card back to 80 dp padding;
  M7 drop the PRO badge key; M8 show the Switch for an unreadable date of birth.

## 5. Out of scope (stated, not deferred)

Meals per day (3/4/5/6) is a separate founder brainstorm and changes the generator and the saved-plan stamp; it is
NOT part of this unit. Edit Profile keeps its own chips unchanged.

## 6. Review round 1 (one context-blind Sonnet seat, read-only, on head 71d25b03, CI green)

No P0 or P1. Write doors, busy guards, PRO gate, confirm dialog, flag-off rows, the hint keys and the dangling-reference sweep were checked and are clean. Findings, all fixed in this batch:

| # | Finding | Fix | Pin |
|---|---|---|---|
| P2-1 | At 360 dp each column is about 100 dp; a free user's lock (16) + Switch (60) left ~8 dp for On/Off | the lock moves to the caption row, the Switch uses `shrinkWrap` and no scale | `layout v2 (review R1): a free user keeps On/Off room` (mutant R4 red) |
| P2-2 | Closed food-type field cut Vegetarian/Eggetarian/Pescatarian with an ellipsis | closed label in a `FittedBox(scaleDown)`, arrow 20 dp | `... scales instead of being cut` (mutant R2 red) |
| P3-1 | The scaled Switch was under 44 dp and the field text was not tappable | the whole field is the tap target (`GestureDetector`), both paths go through `_onToggle` | two tap tests (mutant R1 red) |
| P3-2 | Accessibility names lost (chips and the switch card had them) | each field is `Semantics(container, label)`, the caption is excluded | `... carry their names for a screen reader` (mutant R3 red) |
| P3-3 | Field heights 44 vs 48; stale glossary rows; registry ranges off by one | shrinkWrap Switch makes all three 44; `docs/naming_conventions.md` rows renamed; the screen's registry ranges recomputed by a line mapping from 2fe0ae52 | gates |

Numbers the reviewer used were checked: `AppSpacing.gutter` is 22, so (360-44-16)/3 = 100 dp per column.
