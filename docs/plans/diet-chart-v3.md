# Diet chart v3: plan totals, strategy that follows the plan, swap to any food (founder, 2026-11-17)

Branch `diet-chart-v3`, revision 4 (rounds 1 to 3 applied, sections 7 to 9). Tier M (§4.12.6: more than two product files, writes through an existing profile
door). Execution mode (§4.12.7): inline, one worktree. No migration, no Edge Function, no new stored profile value,
no kill switch (§4.6 is not triggered: nothing here is payment, sync, auth, an AI prompt or the plan generator; the
generator stays byte-identical, pinned in section 5). Rollback is a revert of the PR.

Out of scope, stated (not deferred): the Portions / Grams toggle and the per-food weight audit are OI-517 (founder
decision 2026-11-17); the meals-per-day selector (3/4/5/6) is its own brainstorm. The portion picker built here already
takes grams, so OI-517 adds only the display toggle and the audit.

## 1. Founder decisions (2026-11-17, this session)

1. **A. Totals row.** A compact "your plan vs target" row at the bottom of the meals (kcal, protein, carbs, fat: plan,
   target, difference), computed from the plan so it updates on every swap, pick and regenerate.
2. **The strategy follows the plan.** On a keto plan, a swap that breaks Keto shows a popup "your plan is now Low
   carb"; a further swap that breaks Low carb shows "your plan is now Balanced". Accept = the PROFILE strategy changes
   (targets change app-wide, same confirm dialog with before/after targets) and the edited plan is kept (no
   regeneration). Cancel = the swap is not applied. When the plan fits the stricter strategy again, the totals row offers
   a one-tap "Back to Keto" (the same dialog); never an automatic switch.
3. **B. Swap to any food.** A "Search any food" row in the swap sheet. Processed foods allowed, tagged "Processed".
   The user's own foods in the same search, tagged "Yours", never diet-filtered. Eggetarian / pescatarian users get a
   row-level egg and fish rule so boiled eggs and fish are findable.
4. **Thin vegan roles:** (a) search; (b) new vegan catalog entries for breakfast protein and sides; (c) the swap sheet
   shows ALL alternatives, not 6.
5. **Protein powders** (pea and the other plant powders, whey, casein) are listed in the search for every adult,
   free or PRO, whatever the Supplements switch says. Under 18: never. A vegan sees plant powders only.
6. No popup for processed foods, a full family cap or a day total off target: those only show (the Processed tag, the
   totals row). The only popup is the strategy shift.

## 2. Measurements behind the design (real asset, `TZ=Asia/Kolkata`, 100 seeds per setup)

**Vegan swap options per item** (catalog pool, then offered at the 6 cap; uncapped median in brackets):

| role | vegan pool | offered (median) | items with 0 |
|---|---|---|---|
| mainProtein / sabzi / grain / breakfastMain / fruit | 14 / 27 / 11 / 24 / 19 | 6 (9 / 25 / 9 / 23 / 16) | 0% |
| snack | 11 | 6 (min 3) | 0% |
| breakfastProtein | 4 | 1 | 7-12% |
| side | 3 | 0 | 59-68% |
| fat (Low carb) | 5 | 0-1 | 10-66% |

Pools above are the Low carb ones for breakfast protein (4) and side (3); the Balanced vegan pools are 3 and 2 (round 1, F7).
So the founder's "3-4 options" is true for breakfast protein, side and Low carb fat; the 6 cap hides 9-25 valid options
on the other roles. For non-veg the same roles give 10-29 uncapped.

**Rows beyond the catalog:** 643 vegan rows, 120 in the catalog, 390 free and not tagged processed, 133 tagged
processed (colas, Maggi, packed thepla, bars). 80% of vegan rows exceed 6 g carbs per standard serving.

**Generated plans against their own carb ceiling** (`macroSplit` target; plan day carbs / target, max over 100 seeds):
Keto 1.08, 1.15, 1.12, 1.39 (2000/1500/2700 and 1800 kcal archetypes); Low carb 1.12, 1.15, 1.16, 1.18 and **1.42**
(vegan Low carb 2200/110: median 128 g against a 110 g target). Strictly at target only 4-93% of Keto and 5-80% of Low
carb plans fit. So the fit rule cannot be "carbs <= target": a fresh plan would read as broken. Balanced plans sit far
above both (min 152 g at 2000 kcal against a 100 g Low carb target).

## 3. Writers and readers (named before the change)

| Concept | Writer | Reader |
|---|---|---|
| plan items (`_mealPlans`) | `_swapItem` onPick `diet_plan_screen.dart:342-399` (moves to `diet_plan_screen_swap.dart`); `_generateFreshPlan`; `_loadSavedPlan` `:466` | meal cards `:683`; `_savePlan` `:401`; PDF `_sharePlanAsPdf` `:517`; NEW totals row |
| strategy (profile `diet_strategy`) | `UserProfileNotifier.setDietStrategy` via `handleDietStrategyTap` (`diet_strategy_actions.dart:105`, the one caller `diet_strategy_section.dart:50`); Edit Profile `_save` (`edit_profile_screen.dart:1990`); push `sync_profile.dart:240` | `effectiveMacroTargets` readers (`macroTargetsProvider`, Home `home_provider.dart:636`, coach snapshot `ai_snapshot_builder.dart:96,162`, `suggestMeal.ts`: coach meals follow the shifted strategy, intended); `_planNote` (`diet_plan_screen.dart:510`); the initial stamp (`:90`) |
| plan strategy stamps `_requestedStrategy`, `_planStrategy` | `_generateFreshPlan` `:314`, `_loadSavedPlan` `:498`; NEW: the adoption step | `_onEffectiveStrategy` `:107` through `dietPlanNeedsRegeneration` (`diet_plan_strategy_state.dart:17`), `swapAlternatives(strategy:)`, `_savePlan` stamps, PDF label |
| custom foods | `addCustomFood` (`nutrition_provider.dart:1422-1452`) writes the SAME row to `customBox` (`custom_food_<ms>`) AND `foodBox` (key = the stable `id` uuid, `is_custom: true`); `customBox` also holds custom exercises | NEW `FoodRepository.getCustomFoods()` (the one Hive read; widgets never touch the box, rule 4); `FoodRepository.getAll()` already returns the foodBox copy |
| saved plan (`saved_diet_plan`) | `_savePlan`; cloud `saved_diet_plans.plan_json` (`syncSavedDietPlan`, `_restoreSavedDietPlan`) | `DietPlanNotifier` (`diet_plan_provider.dart:133-155`: hints vanish when the stamp does not match the effective strategy), `_generatePlan` (`:171-182`: a mismatched saved plan is replaced by a fresh one) |
| catalog | `diet_plan_catalog.dart` | generator (`catalogEntryOffered`), `swapAlternatives`, asset script |

Bug-history lookup (§4.1.5): `docs/diagnoses/INDEX.md` is a local build and absent; the relevant history is in memory
(`feedback_restore_never_refreshes_profile_provider_state`, `feedback_session_open_rebuilds_notifier` d86bad: a provider
write inside a method re-emits and empties state mid-method; here the new write happens BEFORE the plan edit and the
method reads what it needs into locals first) and in the Unit 3 plan (the regeneration listener).

## 4. Design

### 4.1 Totals row (part A)

- `services/diet_plan_totals.dart` (pure): `DietPlanTotals {kcal, protein, carbs, fat}` summed from the rounded item
  values the meal cards already show (so the row equals the sum of the card headers), and `totalsDiff`.
- `widgets/diet_plan_totals_row.dart`: one compact card (its own ceiling `kDietPlanTotalsRowMaxHeight` = 128 dp at text scale 1.0 (measured 122.8 in the widget test) including the fit line, with the "Back to" button INLINE at the right of the fit line (a text button, not a second row; the ceiling is measured in the widget test and set from the measurement, round 2 N8); the 60 dp ceiling belongs to the calorie cards):
  four cells (Calories, Protein, Carbs, Fat), each = the plan figure large, "of <target>" and the signed difference
  small; difference colour: neutral within 10% of the target, warn beyond. Under the cells, one fit line (4.2) and, when
  eligible, the "Back to <strategy>" button. Targets are the SHOWN targets (`macroTargetsProvider`) when `_planStrategy` equals the strategy in effect; when they differ (a Keto + Vegan profile, whose plan is Low carb) the carbs and fat targets are those of `_planStrategy` (`effectiveMacroTargets(base, _planStrategy, pro: true)`) and the cell caption names it, so the row never compares a 110 g Low carb plan to a 25 g Keto target (round 1, F12). Sits under the last meal and above `DietSupplementCardSection`.
- The existing note above the meals (`_planNote`, `kBalancedPlanNote`) stays for a plan built for another strategy than
  the targets; the row then honestly shows the carbs gap.
- PDF: one line "Plan total: ... (target ...)" under the meals (`buildDietPlanPdf` gains an optional `planTotals`), using the SAME targets as the row
  (the plan strategy's) and naming the strategy when it differs from the header's (round 2 N9).

### 4.2 Strategy fit and the shift (the cascade)

- `services/diet_plan_strategy_fit.dart` (pure). `strategyCarbCeiling(strategy, base)` = `BmrCalculator.macroSplit(...)`
  carbs x `kStrategyFitFactor` (**1.5 provisional**: the largest generated ratio measured is 1.42, and 1.48 once the Supplements shake (pea, the most carbs) is added on top (B-pass seat A finding 4: the test now runs both legs, 3800 plans); the build re-measures
  200 seeds x 10 archetypes including 1200 kcal and 3500 kcal (the 20 g Keto floor and the 150 g Low carb cap, `bmr_calculator.dart:280-281`) and the factor is the smallest value above the largest ratio, rounded to a quarter; a test
  pins that EVERY generated plan fits its own strategy, so a fresh plan can never read as broken).
  `strictestFit({dayCarbs, base, allowKeto})`: Keto if carbs <= keto ceiling and `allowKeto`, else Low carb if <= low
  carb ceiling, else Balanced. `base` is the stored pack (`resolveBaseMacroPack(profile)`); a missing or incomplete pack
  means no fit is evaluated, no line, no popup (the same rule `effectiveMacroTargets` uses).
- The "current" strategy is `_planStrategy` (what the shown plan is built for; Low carb for a Keto + Vegan profile,
  `planStrategyFor`), never the raw profile value. `allowKeto` = the food type allows Keto (`dietStrategiesDisabledFor`).
- **Shift rule (round 1, F1):** after a prospective pick, `afterFit = strictestFit(afterCarbs)`. The pick needs the shift
  dialog only when `afterFit` is LESS strict than `_planStrategy` (Keto -> Low carb/Balanced, Low carb -> Balanced) AND the pick
  INCREASED the day's carbs (`afterCarbs > beforeCarbs`). A pick that keeps or lowers carbs never asks, so a saved plan
  that already sits over its ceiling (saved before this change, an extreme archetype) is not asked on every swap, and a
  corrective swap never writes the profile. `next = afterFit`. It never moves UP automatically.
  A free user (Balanced) and a plan already Balanced never shift. A Balanced-fallback plan (`builtFor` Balanced for a
  Keto request) is Balanced here, so no popup.
- **Order of operations on a pick** (`diet_plan_screen_swap.dart`, `_applyPick`; the sheet pops ITSELF first and then calls `onPick`, so the dialog never pops the sheet, round 1 note):
  0. `_pickBusy` guard (a second tap while a pick, its PRO gate or its dialog is pending is ignored; round 1, F6) and capture `epoch = _planEpoch`;
  1. build the prospective plan (a copy with the item replaced), compute totals and `next`;
  2. no shift: apply the pick (`setState`, `_saved = false`); done;
  3. shift: set `_requestedStrategy = planStrategyFor(next, _foodType)` FIRST (so the regeneration listener, which
     compares it with the new effective strategy, finds nothing to do), then
     `handleDietStrategyTap(..., next, current: effective, reason: ..., alwaysAsk: true, isStale: () => epoch != _planEpoch || !mounted)`; it gates PRO (as today),
     shows `DietStrategyConfirmDialog` with the reason line ("Your plan now has 49 g of carbs, over the Keto limit of
     37 g. Switching to Low carb changes your targets: Carbs 25 g -> 100 g, Fat ...") and writes through
     `setDietStrategy`, returning whether it was written (return type `Future<bool>`; the one existing caller ignores it). `isStale` is checked after the PRO gate, after the dialog and immediately before `setDietStrategy`: a regeneration that landed while the dialog was open (supplements listener `:117`, `_healSupplementsState`, a PRO change) writes NOTHING (round 1, F5);
  4. written (the re-check, round 2 N2): after `await handleDietStrategyTap` returns true, `epoch != _planEpoch || !mounted` is checked AGAIN
     (the profile write has a Hive await after the last `isStale`); if stale, apply nothing and set no stamp (the profile is already
     written and the regeneration followed the effective strategy) and say "Your plan was rebuilt for <strategy>". Otherwise: apply the pick, `_planStrategy = next`, `_droppedFrom ??= previous strategy`; the listener fires with a
     matching request and does not regenerate. NO automatic save (rounds 2-3: the re-save mechanism produced three defects in
     two rounds, N3 and D1, so it is removed): the saved plan on disk and in the cloud is never touched by a pick. This is the model a
     strategy change through the dropdown already has (the saved plan, stamped for another strategy, stops loading; an unsaved edit is lost
     on leaving), so the DIALOG says it plainly, "Save the plan afterwards to keep your changes", and ONE snackbar follows ("Plan
     updated for Low carb. Save to keep it."): `handleDietStrategyTap` gets `silent`, which suppresses the SUCCESS snackbar only (the
     failure snackbar stays; D6);
  5. cancelled, refused, stale or failed: apply nothing, and restore `_requestedStrategy` ONLY when `_planEpoch` still
     equals the captured epoch (a newer generation owns the field).
  `_pickBusy` is cleared in a `finally`.
- **Back up:** the row shows "Back to <_droppedFrom>" only while the current totals fit `_droppedFrom` and the plan is
  still the dropped one; tap = `handleDietStrategyTap(next: _droppedFrom, alwaysAsk)` with the same ordering; nothing
  else changes. `_droppedFrom` is cleared on a regeneration, a load and a food-type change.
- **Fit line text:** Keto/Low carb plans: "Fits Keto" / "Fits Low carb" (ok colour) or "Over the Keto limit (49 g, limit
  37 g)"; Balanced: no line. After a save and reload the stamps (`diet_strategy`, `diet_strategy_requested`) equal the
  new profile strategy, so the saved plan loads for it (`savedPlanMatchesStrategy`).
- `diet_strategy_actions.dart`: `handleDietStrategyTap` gains `reason` (shown in the dialog), `alwaysAsk` (ask even
  when the shown targets would not move), `isStale` and `silent`, returns `Future<bool>` and returns `applied` on its `!context.mounted` path
  after a successful write too (else the caller restores `_requestedStrategy` for a written profile; round 2 N12). A dropped stale pick
  is not silent: a snackbar says "The plan changed. Pick again." `DietStrategyConfirmDialog` gains an optional
  `reason` line. Existing behaviour is unchanged when both are left out (pinned).

Existing gap fixed here because the shift makes it matter: a swap does not set `_saved = false` today (the app bar keeps
the green check on a changed plan). Every pick sets it; without a shift the Nutrition-tab hints still read the saved plan
until Save.
Vegan Keto profile (plan Low carb, round 2 N11): the dialog's reason and rows name what really changes ("Your plan is Low carb ... Switching your
strategy to Balanced replaces Keto: Carbs 25 g -> 275 g"); "Back to" offers the PLAN's previous strategy (Low carb), never Keto.
`strictestFit` never calls `macroSplit` for Balanced (it throws, `bmr_calculator.dart:275`).
Fit line text (F12): "Fits Keto (up to 37 g)" / "Over the Keto limit (49 g, up to 37 g)".

### 4.3 Swap sheet: all alternatives, search, own foods, powders, portion

- `showDietPlanSwapSheet` becomes scrollable (`isScrollControlled`, 80% max height). It lists EVERY alternative
  (`swapAlternatives(limit: 100)`; the order stays calorie closeness) and ends with a pinned "Search any food" row. With
  no alternatives the sheet still opens (a one-line "No ready alternatives for this item" and the search row); the old
  snackbar `showNoDietPlanSwapSnack` is deleted (§4.6 step 4).
- `services/diet_plan_food_search.dart` (pure): `searchDietPlanFoods(query, foods, customFoods, dietPreference,
  powdersAllowed, limit)`. Ranking: word-start match, then substring, then shorter name, then id. Rules:
  - a row with `meal_fit == []` is never returned (editorial: alcohol rows);
  - category `supplements` only as a PROTEIN POWDER: `calories_std` <= 210, `protein_std` >= 14, not UPF, and `powdersAllowed`
    (no name regex: it dropped Iso-Zero, ISO 100, Syntha-6, Isopure, Nitrotech Ripped and the vegan Gold Vegan; the kcal and protein
    bounds already exclude gainers, pre-workouts and fish oil, round 1, F9); the two generated-shake ids (`F0823`, `F0831`) are
    excluded so a pick is never mistaken for the Supplements shake (a limit the founder should know: a vegan typing "pea" finds
    "Plant Protein (Pea + Rice)" F0832 but not the generic "Plant Protein (Pea)" F0831; soy F0830, hemp F0833 and the branded vegan
    powders F0834-F0837 are listed; round 2 N5) (`isSupplementShake` hides the swap icon and the
    generator skips a plan that has one); mass gainers, pre-workouts, bars and fish oil never qualify;
  - diet filter = `passesDiet(row, pref, family: searchFamilyOf(row))`; `searchFamilyOf` gives a free row the egg family
    (name has egg|omelette|bhurji|anda) or the fish family only when the name has NO meat word. The fish list is spelled out
    (fish, prawn, shrimp, salmon, tuna, cod, tilapia, scallop, mussel, anchov, sea bass, halibut, trout, snapper, mahi, macher,
    crab, lobster, squid, sardine, pomfret, rohu, hilsa, surmai, mackerel, oyster, swordfish; round 2 N4 found nine rows the first list
    missed); the meat list includes chicken, mutton, lamb, beef, pork, keema, veal, goose, quail,
    lard, bacon, ham, sausage, salami, and `duck egg` / `quail egg` are read as eggs before the meat check. A test pins the EXACT
    id sets the asset yields, taken from a real run at build (the egg words give 35 rows on the asset today, including F0828 Egg White
    Protein, F0787 Quail Egg and F0788 Duck Egg; the test states whether F0117 Egg Biryani is in); Veal F0989, Goose F1012, Quail F1013
    and Lard F1176 never pass for eggetarian or pescatarian) (round 1 F11, round 2 N4);
  - for a user who is NOT `powdersAllowed` (a minor or an unreadable date of birth) rows whose name has whey|protein
    (shake|smoothie|bar|pudding|powder|wafer)|gainer|pre-workout|kodiak are hidden too (F0067, F0959, F0961, F0962, F0853, F0854, F0860,
    F0956, F0950, F0951 are reachable through other categories otherwise; the test pins the set the rule yields on the asset, taken from a real run, which must contain all ten; the rule also covers
    `max protein|sneaky protein|protein (waffle|\()` because the first regex missed F0853, F0854, F0860, F0951 (round 3 D2). Stated limits: it also hides
    F1400 and F0950 for a minor, and energy drinks (Red Bull, Sting) stay reachable;
    the minor test is `dietSupplementsEligible(enabled: true, ...)` (age only), the powder listing also needs the kill switch on, so the kill
    switch never hides bars from adults (D4); round 2 N6); the age is
    self-attested (OI-513), which the plan states as the limit (round 1, F10);
  - `is_ultra_processed == true` stays in the results with `processed: true` (the "Processed" tag);
  - own foods come from `FoodRepository.getCustomFoods()`: the customBox keys that start with `custom_food_` (custom exercises use
    `custom_exercise_`, so the prefix alone separates them; NO `type` or `is_custom` test: a row restored from the cloud
    (`sync_community.dart:433`, the `_projectCustomFood` shape) has neither, and reading them was APK Test #15.4's bug, `exercise_repository.dart:461-478`);
    the key's suffix is injected as `id` when the row has none. They are returned with `yours: true`, never diet-filtered. The foodBox pass SKIPS
    `is_custom == true` rows (`addCustomFood` copies the row there; foodBox survives `clearAllData`, so the skip also stops another
    account's custom foods leaking) and the two are de-duplicated by `id`, the customBox copy winning, and of two customBox rows with one id (one name, one uuid) the newest `created_at` wins (round 1 F3, round 2 N1, round 3 D5).
    The reader is registered under the SoT concept `custom_food_mutations` (`docs/sot_registry.yaml:2660`).
  - foods already anywhere in the plan are not offered, except the replaced item itself (the catalog swap does the same; round 2 N12).
- `powdersAllowed` = `dietSupplementsEligible(profile, enabled: DietSupplementsFlags.enabled, now)`: an adult with a
  readable date of birth, no PRO test, no switch test (the existing one door for the age rule; the kill switch off = no
  powders, like the section).
- `widgets/diet_plan_food_search_sheet.dart`: text field, results (name, serving, kcal, tags), empty query = own foods
  then powders; a tap opens the portion sheet.
- `widgets/diet_plan_portion_sheet.dart`: for a chosen row: a stepper of the standard serving (0.5 steps, 0.5 to 10; the step is chosen so that `qty x m` is a whole number for a countable serving unit (`kCountableServingUnits`, `curated_diet_plan_generator.dart:545`; a
  "2 rotis" serving steps by 0.5, a "1 roti" one by 1), so no half roti or 1.5 idli; a parenthetical like "1 cup (3 eggs)" is not tokenised, a stated limit; round 2 N7, round 3 D3) and a
  grams field kept in step (g = std_g x m; 1 to 2000 g), live kcal / P / C / F (the row's `*_std` x m, per-100 g
  when `_std` is missing), the serving text through `scaleServingDesc` when m is a clean multiple of 0.5, otherwise
  "<g> g". Returns a `DietPlanFoodItem` whose `role` is the REPLACED item's role (so a later swap of this pick finds
  that role's catalog alternatives, as a swapped catalog item does today) and whose `category` is the row's.
- `FoodRepository.getCustomFoods()` and `getAllFoods` snapshot read once per sheet open (not per keystroke).

### 4.4 New vegan catalog entries (swap only)

- `CatalogEntry` gains `swapOnly` (default false): offered by `swapAlternatives`, never by the generator
  (`catalogEntryOffered` keeps serving the swap, `swapCatalogFor` at `diet_plan_swap.dart:57`; the generator's one caller `curated_diet_plan_generator.dart:341` moves to the new `generatorOffered(e, strategy)` = offered && !swapOnly). The generator output stays
  byte-identical (goldens G1/G2, T5/T10 floors untouched). Founder's later choice whether to promote an entry to
  generated plans.
- Candidates: breakfast protein: Sattu F1433, Hemp Seeds F0477, Peanut (Raw) F0471, Tofu (Silken) F1015, Soy Yogurt F1019
  (F1434 black chickpeas and F1438 pumpkin seeds are dropped: twins of catalog F0177 and F0473, round 1, F8); sides: Garden Salad
  (no dressing) F1061, Carrot (raw) F0269, Cherry Tomato F0295, Tomato F0043, Green Beans (cooked) F1028 (Carrot is dropped by
  the Keto item cap, accepted). Families are the honest ones from the existing enum (soy, nut, dal, side); the Balanced daily caps
  (soy 1, nut 1) and the coherence tokens (tofu) bite, so the ACCEPTANCE target is measured AFTER caps and tokens on 100 vegan
  Balanced plans per archetype, not on pool size: items with zero options at most 5% for breakfast protein and 10% for side,
  median offered at least 3 and 3 (round 1, F7: the Balanced vegan pools are 3 and 2 today, 8 and 7 after).
- The new ids are APPENDED at the end of `kDietPlanCatalog` (the index is the swap tie-break and the generator's `catalogIndex`), are NOT
  `lowCarbOnly` (a Balanced swap must see them), and carry portions like their neighbours (round 2 N10).
- Asset: `scripts/patch_food_database_v4.dart` re-run (T1 `is_everyday` mirror), `_foodLibraryVersion` 6 -> 7, the
  v6 -> v7 re-seed test extended, `docs/reference/food-database.md` count updated, and the nested `lib/features/nutrition/CLAUDE.md` catalog row (151 + 14 + 5 counts).

### 4.5 Files and line budgets

`diet_plan_screen.dart` 776 lines (Gate 43 cap 800; it counts only files ending `_screen.dart` under `/screens/`, so the part file escapes exactly as `diet_plan_screen_models.dart` does, and the screen lands near 745): `_swapItem` moves to a part file `diet_plan_screen_swap.dart`
(an extension on the state, with `_applyPick` and the shift step; `setState` is `@protected`, so the part carries `// ignore_for_file: invalid_use_of_protected_member` as `profile_content.dart:6` does); the screen adds the totals mount, `_droppedFrom` and the
`_saved = false` ownership. New files: `diet_plan_totals.dart`, `diet_plan_strategy_fit.dart`,
`diet_plan_food_search.dart`, `widgets/diet_plan_totals_row.dart`, `widgets/diet_plan_food_search_sheet.dart`,
`widgets/diet_plan_portion_sheet.dart`, the swap part. Changed: `diet_plan_swap_sheet.dart`, `diet_strategy_actions.dart`,
`diet_strategy_confirm_dialog.dart`, `diet_plan_catalog.dart`, `diet_plan_catalog_rules.dart`, the generator call that
reads `catalogEntryOffered`, `food_repository.dart`, `diet_plan_pdf.dart`, the asset.

## 5. Tests (each fails without the change)

- Totals: sum equals the card headers over generated plans; a swap changes the row; difference sign and the 10% colour.
- Fit: every generated plan (8 archetypes x 200 seeds, Keto/Low carb, vegan Keto -> Low carb) fits its own strategy;
  oats into a Keto plan -> Low carb; a second carb-heavy pick -> Balanced; allowKeto false skips Keto; missing pack = no
  fit; never moves up.
- Shift flow (widget, real Hive in `tester.runAsync`): popup text and the before/after rows; accept writes the profile
  strategy once, keeps the swapped item, does NOT regenerate (`debugDietPlanGenerations` unchanged) and the save stamps
  equal the new strategy; cancel applies nothing and leaves the profile; a regeneration while the dialog is open drops the
  pick; a failing write applies nothing and restores `_requestedStrategy`; free user / Balanced: no popup; "Back to Keto"
  appears only while it fits and goes through the dialog.
- `handleDietStrategyTap` unchanged without `reason` / `alwaysAsk` (existing selector tests stay green).
- Swap sheet: all alternatives shown (vegan breakfast protein and side now have >= 6 / >= 8); a vegan side item opens the
  sheet; the search row; stale-epoch pick ignored (existing `diet_plan_strategy_screen_test`).
- Search: ranking; vegan results never contain a `is_vegan == false` row; eggetarian finds boiled egg, none of its results
  has a meat word; pescatarian finds fish; own foods tagged and unfiltered; UPF tagged; alcohol rows absent; powders only
  for an adult (a minor and an unreadable date of birth get none), no PRO or switch needed, vegan gets plant powders only,
  F0823 / F0831 never returned, mass gainers never returned.
- Portion: stepper and grams stay in step; macros scale; a free pick keeps the replaced role; a later swap of the pick
  offers that role's catalog alternatives.
- Generator byte-identity: the existing goldens G1/G2 and the T5/T10 floors pass untouched with the new entries; a test
  asserts `swapOnly` entries never appear in generated plans across the matrix.
- Catalog: T1 (everyday mirrors the catalog) with the new ids; new entries are non-UPF, vegan, in a family; v6 -> v7 re-seed.
- Repoints (round 1, F2): `test/nutrition/diet_plan_quality_constraints_test.dart:429-432` slices the screen between `void _swapItem` and
  `void _savePlan` (RangeError after the move): it reads the part file instead (a pin that `swapAlternatives(` is called there);
  `test/nutrition/diet_plan_strategy_screen_test.dart` `offeredSwapNames` (:455, "no sheet = snackbar") and the stale-pick test (:840-873,
  taps `tiles.first`) are rewritten for the new sheet (the sheet always opens, the pick pops the sheet first); other tests that read
  `diet_plan_screen.dart` source (`diet_plan_curated_switch_test`, `diet_plan_saved_loaded_writer_to_reader_test`,
  `restore_completeness_writes_test`, `null_guard_test`, `diet_plan_pdf_test`) are grepped for `_swapItem`/`swapAlternatives` anchors.
- Shift rule (F1): a saved Keto plan already over its ceiling is NOT asked on a carb-cutting or carb-neutral swap and IS asked on a
  carb-adding one; 1200 and 3500 kcal archetypes are in the fit matrix; own foods appear once (F3); `is_custom` foodBox copies skipped;
  a stale dialog (regeneration while open) writes nothing and does not clobber the new `_requestedStrategy` (F5); a double tap runs one
  pick (`_pickBusy`); an accepted shift on a saved plan re-saves it (F4).
- Round 2 pins: a restored-shape custom row (no `type`, no `is_custom`) is returned (`test/nutrition/diet_plan_food_search_restored_custom_test.dart`);
  a foodBox `is_custom` row absent from the customBox is NOT returned; a regeneration that lands DURING the profile write drops the pick
  and sets no stamps (N2); the dialog carries the "Save the plan afterwards" line and exactly one snackbar follows an accepted shift; a pick never writes `saved_diet_plan` (N3, D1: a load-swap-shift sequence leaves the saved plan untouched);
  the exact egg and fish id sets and the minor-hidden id list; countable units step by whole numbers; foods already in the plan are
  not offered; `offeredSwapNames` counts every `ListTile` in a `BottomSheet`, so the search row is NOT a `ListTile`.
- Layout: the totals row and the sheet at 360 dp with textScale 1.0 and 1.3, no overflow (a measurement, not an
  existence check); screen line count <= 800.
- Mutants (each must redden something; a no-output mutant is not applied): M1 factor 1.5 -> 1.0; M2 shift allowed upward;
  M3 `_requestedStrategy` not set before the write (regenerates); M4 apply the pick on cancel; M5 `_saved` not cleared;
  M6 drop the `meal_fit == []` filter; M7 powders for a minor; M8 PRO test added to powders; M9 F0823 allowed; M10 own
  foods diet-filtered; M11 egg family given to a meat dish; M12 limit back to 6; M13 `swapOnly` leaks into the
  generator; M14 `alwaysAsk` ignored; M15 role dropped on a free pick; M16 UPF row excluded from search; M17 popup on a carb-cutting
  pick; M18 `isStale` not checked before the write; M19 the sheet pops after `onPick`; M20 customBox copy not de-duplicated;
  M21 a pick writes `saved_diet_plan`; M22 `_pickBusy` removed; M23 minor sees whey drinks; M24 customBox filter requires `type`; M25 the post-write epoch re-check removed; M26 the "Save the plan afterwards" line
  removed; M27 half steps on a countable unit.

## 6. Process

SoT registry: add the concepts `diet_plan_totals_and_fit` and `diet_plan_free_pick` (each with a `behavioral_test_path:`, Gate 42) and
extend `custom_food_mutations`; re-baseline the context-artifact budget (`check_context_artifact_budget.dart --record`, indexes built first); write
`docs/plan-reviews/diet-chart-v3.md`; `food_repository.dart` is account tier (`blast_radius.yaml:452`), so the B-pass and the record are required; re-anchor the screen's ranges after the
move (recompute from anchors, per commit). Nested `lib/features/nutrition/CLAUDE.md` rows updated, `docs/naming_conventions.md`
gets: plan totals, strategy fit, shift, swap only, free pick, protein powder. Plan review x2 (context-blind Sonnet, read-only,
one seat each), then the gate loop (`flutter analyze --no-fatal-infos`, pre-commit gates, CI full suite through
`land_pr --ci-only` on an open PR), B-pass at the account tier before any merge. The merge waits for the founder's own go.

## 7. Review round 1 (one context-blind Sonnet seat, read-only, on revision 1) and dispositions

The reviewer verified the writers/readers, the regeneration ordering, the swap-only byte-identity, Gate 43 and the asset counts, and
found no P0. The three P1 and the P2/P3 below are fixed in this revision; I re-checked F2, F3 and F6 against the code myself before
accepting them.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| F1 | P1 | the shift compared only the AFTER-pick fit, so a carb-cutting swap on a plan already over its ceiling still asked and wrote the profile | rule now needs `afterFit` less strict than `_planStrategy` AND carbs increased (4.2); extreme archetypes in the factor measurement |
| F2 | P1 | `diet_plan_quality_constraints_test.dart:429-432` and two screen-test helpers break when `_swapItem` moves / the sheet changes | repointed (section 5) |
| F3 | P1 | custom foods live in BOTH boxes; search would list each twice (one filtered) | de-dupe by id, skip `is_custom` foodBox rows, customBox filter by prefix and `type` (4.3) |
| F4 | P2 | after a shift the old saved plan matches nothing: hints vanish, next open replaces the edit | re-save when it was saved, else "Save to keep it" (4.2) |
| F5 | P2 | the profile write ran before the epoch check; the cancel path clobbered a newer `_requestedStrategy` | `isStale` checked before the write; restore only on an unchanged epoch (4.2) |
| F6 | P2 | `setState` from an extension is a protected-member warning that aborts pre-push; two picks can race | `ignore_for_file` as `profile_content.dart:6`; `_pickBusy` (4.2, 4.5) |
| F7 | P2 | the "4 and 3" pools are the Low carb ones; caps cut the new entries | corrected pools; the acceptance target is measured after caps (4.4) |
| F8 | P3 | two candidates duplicate catalog foods | dropped (4.4) |
| F9 | P3 | the powder name regex dropped real powders | removed, kcal/protein bounds only (4.3) |
| F10 | P3 | whey drink rows reachable by a minor | hidden for a non-eligible user; the age limit stated (4.3) |
| F11 | P3 | the fish rule missed 11 fish rows, meat words could leak | spelled-out lists and exact id pins (4.3) |
| F12 | P3 | contradicting target vs "fits" signals; row height | plan-strategy targets, caption, "up to N g", own 96 dp ceiling (4.1, 4.2) |
| F13 | P3 | registry incomplete, line numbers | added (section 3) |
| F14 | P3 | a free pick loses its role after Save + reload; after a shift to Balanced, low-carb-only foods are invisible to family counts | ACCEPTED, stated: `role` is never persisted (existing), the sheet still opens with the search row |

Navigator note adopted: the sheet pops itself first, then calls `onPick`.

## 8. Review round 2 (a second fresh Sonnet seat, read-only, on revision 2) and dispositions

The seat found no P0 and one P1 that revision 2 itself introduced. Checked clean: the regeneration ordering before the write (the
listener compares equal, vegan Keto included), the shift rule operands, `strictestFit` with `allowKeto` false, the rounded sums equal to
the card headers, every catalog consumer (no Deno or `_shared/testdata` mirror), Gate 43 exemption of the part file, rule 5.
I re-checked N1 against `sync_community.dart:283-314,433` myself.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| N1 | P1 | the own-foods filter required `type == 'food'`; a cloud-restored custom food has no `type`, so after a reinstall no "Yours" food appears (APK Test #15.4's bug class) | prefix-only filter, id injected, foodBox `is_custom` skip kept, SoT `custom_food_mutations`, restored-shape test (4.3) |
| N2 | P2 | the epoch was not re-checked after the profile write's own Hive await | re-check after `handleDietStrategyTap` returns (4.2 step 4) |
| N3 | P2 | the re-save silently overwrites the saved plan on device and cloud, and three snackbars queue | superseded by D1: the re-save is removed; one snackbar (`silent`) (4.2) |
| N4 | P3 | nine fish rows unmatched, "33 egg rows" not reproducible (35) | list extended, pins taken from a real run (4.3) |
| N5 | P3 | a vegan typing "pea" does not find F0831 | stated to the founder (4.3) |
| N6 | P3 | minors still reach gainer shakes, bars, pre-workout | list widened, ids pinned, age limit stated (4.3) |
| N7 | P3 | half a roti | whole steps for countable units (4.3) |
| N8 | P3 | 96 dp unattainable with the button | 120 dp, button inline, measured (4.1) |
| N9 | P3 | PDF total line vs header targets | same targets as the row, strategy named (4.1) |
| N10 | P3 | append order, not lowCarbOnly, portions, nested CLAUDE.md counts | stated (4.4) |
| N11 | P3 | vegan Keto dialog wording and "Back to" target | stated (4.2) |
| N12 | P3 | search offered foods already in the plan; a stale pick vanished silently; `applied` lost on `!mounted` | fixed (4.2, 4.3) |
| N13 | P3 | Gate 42 paths, budget re-baseline, review record missing | added (section 6) |

## 9. Review round 3 (a third seat, delta check on revision 3) and dispositions

No P0 or P1. N1, N2, N4, N5, N8-N13 verified fixed on real data shapes. The seat found that N3's fix created a new defect.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| D1 | P2 | the re-save keyed on `_saved`: load a saved plan, swap A (clears `_saved`), swap B (shifts): no re-save, no dialog line, the saved plan stays stamped for the old strategy | the mechanism is REMOVED (the third defect it produced, memory `remove_mechanism_when_rounds_chase_its_symptoms`): a pick never saves; the dialog and one snackbar say "Save to keep it" (4.2) |
| D2 | P3 | the minor-hide regex missed 4 of the 8 named ids | rule extended, the pinned set is the real run's, limits stated (4.3) |
| D3 | P3 | whole steps keyed on `m`, not on `qty x m` | step so that `qty x m` is whole (4.3) |
| D4 | P3 | the kill switch also hid bars from adults | minor test is age only (4.3) |
| D5 | P3 | de-dupe by id kept an arbitrary row | newest `created_at` (4.3) |
| D6 | P3 | `silent` scope | success snackbar only (4.2) |

Review record: rounds 1-3 (round 2 found one P1 that round 1's fix created, round 3 one P2 that round 2's fix created and removed that mechanism);
every fix after round 3 is a deletion or a wording change, with no new mechanism. Revision 4 is the plan the build follows.

## 10. Mutation record (CLAUDE.md 4.4 rule 21, self-attested)

First pass: 31 distinct mutants (M1-M27 and the screen wiring ones), each applied one at a time (an exact single-match replace, a restore from a backup after each, the tree compared after the run).
- 29 reddened a test on the first pass: 24 failed cleanly, 5 (M21, M15b, M26, M-dropped, M-mount) failed their first screen test and then hung the next one (the known "a failed testWidgets hangs the next one" class); each is counted only because an `[E]` line was in the partial output.
- M10 (own foods diet-filtered) SURVIVED: the fixture was an untagged custom food, which passes the vegan filter anyway. Fixed the fixture (`is_vegan: false`, `is_veg: false`); M10 now reddens.
- M19 (the sheet pops AFTER the pick) SURVIVED: no test gave the sheet a pick handler that opens a dialog synchronously. New `test/nutrition/diet_plan_swap_sheet_test.dart`; both doors mutated by hand, both red.
- M25 (the post-write epoch re-check removed) SURVIVES: a regeneration that lands inside the profile write cannot be driven from a widget test (the profile write is the dialog's own `await`; the test can only change the strategy while the dialog is OPEN, which the isStale check before the write already covers). Self-attested residue: a PRESENCE pin only. Same for `_pickBusy` (not mutated).
Second pass (after the B-pass fixes, section 11): 8 more mutants MB1-MB8 (the provisional request not handed back, untagged community rows offered, back-up ignoring the partial level, the extra countable words dropped, the totals grid never, `isStale` not wired in the pick, `adult` always true, the replaced item not excluded from the search), all red. MB5 SURVIVED once (the test compared two tops that a centred Row already makes differ by a few dp): the assertion now needs a whole cell (30 dp) between the rows and reddens. Five portion-sheet mutants (stepper clamp, initial multiple, Add enabled with no calories, scroll view removed, search sheet height) are red in `diet_plan_portion_sheet_test.dart`.
Total: 39 mutants, 38 red, 1 residue (M25), plus the `_pickBusy` presence pin.

## 11. B-pass (three context-blind seats on 6a0f5645) and dispositions

No P0 or P1. Findings and what was done, all in this batch:

| # | Sev | Finding | Disposition |
|---|---|---|---|
| A1 | P2 | `_requestedStrategy` set before the write was handed back only on `!written`, not on a throw or any other uncommitted exit | restored in the `finally` unless the pick committed and no newer generation owns the field (both flows); screen test: a cancelled shift saves a plan still stamped Keto |
| A2 | P3 | Keto -> Balanced, then a day that fits only Low carb offered nothing | back-up offers the strictest level the day fits, capped at where the plan dropped from; vegan Keto profile: the plan's own level is Low carb, so Back returns to Low carb (the stored Keto choice is the dropdown's, not the swap's) |
| A3, C7 | P3 | totals cells never grew with the text scale; the fit line cut the numbers; a 28 dp button; one spoken line per cell missing | above scale 1.3 the cells go 2 x 2; the fit line has two lines; the button is 44 dp (height ceiling 128 -> 144); each cell is one Semantics label with units; test at 1.0, 1.3, 1.5, 2.0 |
| A4 | P3 | the 1.5 fit factor was measured without the Supplements shake | the matrix runs both legs: worst ratio 1.42 -> 1.48 with the pea shake over 3800 plans; 1.5 stays (a ceiling of 1.5 x the 20 g floor is 30 g, and 1.5 x the Keto cap 50 g is 75 g, the Low carb floor) |
| A5 | P3 | the "set before the write" comment overstated an invariant | reworded: ordering, not an invariant |
| B1 | P2 | untagged community rows passed the veg and vegan filter | rows without `is_veg` are hidden from everyone but a non-veg user; test |
| B2 | P2 | the stepper threw for a serving over 4000 g and started above the 2000 g cap | lower limit capped at the upper, start at min(1, max); widget test |
| B3 | P3 | naan, chapati, slices, pcs stepped by halves | a free-pick-only extra set of countable words (the generator's T7 set untouched) |
| B4 | P3 | a vacuous F0851 assertion | replaced by "whey protein bar" positive and minor cases |
| B5 | P3 | the search sheet's lower fifth sat behind the keyboard | height = min(0.8 H, room left by the keyboard); widget test |
| B6 | P3 | a restored row with no calories added 0 kcal silently | note and a disabled Add; widget test |
| C1 | P2 | nine registry ranges for `diet_plan_screen.dart`, `seed_service.dart` and the new files were stale | recomputed from anchors |
| C2 | P2 | the shift test had no "carbs rose, fits a STRICTER level" case | cases added (the `!=` form of the strictness test now reddens) |
| C3 | P2 | the screen "carb-cutting pick" test could not fail on its guard | retitled to what it proves; the guard stays pinned by the pure case |
| C4 | P2 | screen wiring unobserved: isStale, the failed-write restore, the age wiring, the already-in-plan exclusion | four screen tests (a regeneration under the open popup; cancel then Save; adult and minor whey; already in the plan) |
| C5 | P2 | the plan said the egg, fish and minor id sets were pinned; they were spot checks | the three sets are pinned from a real run (35 egg, 57 fish, 25 minor-hidden) |
| C6 | P2 | the portion sheet was a bare Column | scrolls; 360 x 640, keyboard up, scale 1.0 / 1.3 / 2.0 |
| C8 | P3 | stale v6 text, a test comment, a missing food-database note, the section 10 arithmetic | fixed |
| C9 | P3 | the screen tests depended on the day's plan seed | `debugDietPlanSeedOverride`; passes for seeds 4242, 17, 90001, 31337 |
| C10 | P3 | `diet_plan_free_pick` pointed at the reader-half test | points at the screen test |

Not changed, stated: the "Back to ..." offer after the user's own first drop never goes above the level the plan started from (a recorded decision: back-up is manual and capped); the second review reads this table.
