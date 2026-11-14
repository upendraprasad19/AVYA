# Diet plan Unit 3b — strategy-aware diet plans, coach text, switch on

Revision 4 (2026-11-14; round 1 dispositions in §9, round 2 in §10, round 3 in §11). 3b-1a is BUILT in the worktree (§3.2–§3.4 describe the built code; §4's 3b-1a list is green). Parent plan: `docs/plans/diet-strategy.md` (3a, merged dark as PR #274, `21db03c7`; migration 179 `user_profile.diet_strategy` is LIVE since 2026-11-14). Founder decisions (chat 2026-11-14): Balanced (default), Low carb, Keto; PRO; carb and fat targets change everywhere, calories and protein never; a confirm dialog; no AI; label `NON-VEG · KETO`; enough everyday keto foods for veg users (paneer, curd, nuts, seeds, leafy vegetables); a short medical note for Keto (diabetes medication, pregnancy, kidney disease).

## 1. What 3a left open

With `DietStrategyFlags` on, a Keto user sees 30 g carbs / 187 g fat targets above a Balanced meal plan (rice, roti, fruit), with the 3a note line "Meals for Keto come in the next update". 3b makes the plan, the swap sheet, the saved plan and the coach follow the strategy, adds the medical note, and turns the switch on.

## 2. Landings (execution mode: inline, one worktree per landing, each its own PR)

- **3b-1a — catalog, asset, generator, swap (dark).** §3.1–§3.4, §3.7. The only part every user receives is the asset re-seed (14 rows flip `is_everyday` to true) and a Balanced-identical generator and swap sheet; the strategy paths are reached only through `DietStrategyFlags` (still OFF) and tests. Blast radius platform (asset + seed version).
- **3b-1b — screen, saved plan, copy (dark).** §3.5, §3.6, §3.8, §3.9. Every change behind the flag.
- **3b-2 server — coach text and `suggestMeal`.** §5. Inert until the client writes `diet_strategy` (only with the flag on) and until the snapshot carries `diet_strategy` (only with the flag on). EF deploys need the founder's go (ai-proxy, weekly-report).
- **3b-3 flip.** §6.

## 3. Design

### 3.1 Measured feasibility (prototype, 16 archetypes × 50 seeds, real asset)

The catalog as merged cannot make a keto day: no breakfast main or fruit under 8 g carbs a serving, every grain 14–50 g, one sabzi under 8 g, no fat source. Indian curries carry 12–18 g carbs a cup (onion-tomato gravy). A keto day at 20–40 g total carbs is built from plain protein (grilled or fried meat or fish, eggs, paneer, tofu), plain vegetables (cauliflower, spinach, bhindi, capsicum: 5–7 g a cup), added fat (ghee, butter, coconut, coconut milk), nuts, seeds and cheese.

Prototype results (carb target from `BmrCalculator.macroSplit` over a Balanced pack with 25 % fat). These are the prototype's numbers; the T10 floors are set from the BUILT code's own measurement (§4):

| Strategy | kcal mean (over archetypes) | protein mean | carbs mean (× target) | fallbacks |
|---|---|---|---|---|
| Low carb | 0.82–1.02 | 0.70–1.08 | 0.92–1.21 | 0 |
| Keto (non-vegan) | 0.79–0.99 | 0.70–1.17 | 0.91–1.20 | 0 |
| Keto (vegan) | — | — | 8.8× (legacy fallback 50/50) | 50 |

Stated limits: veg keto protein ≈ 0.70 of target (the accepted Balanced veg cut level, Unit 1) and 1.17–1.20× carbs at the 20 g floor; keto at 2,700–3,000 kcal averages 0.79–0.83 kcal (the shared catalog portions cap the protein foods; raising them changes Balanced plans); vegan low carb 0.82–0.91 kcal and 1.08–1.21× carbs; fiber 8–14 g on keto days, 20–41 g low carb.

### 3.2 Catalog (`diet_plan_catalog.dart`)

- New role `DietRole.fat`; new family `fat` (ghee, butter, coconut, coconut milk).
- `CatalogEntry.lowCarbOnly` (named, default false): offered ONLY in Low carb / Keto plans and their swaps.
- 14 new entries, all `lowCarbOnly`, appended at the END of the list, all existing asset rows: Ghee F0402 (1–5 tsp), Butter F0403 (½–2 tbsp), Coconut fresh F0483 (fat + snack), Coconut milk F0383 (vegan fat, ¼–½ cup), Egg fried F0371, Cheese omelette F0790 (category `protein`, egg family), Paneer F0023 (breakfast, main, snack), Cheddar F0398 (breakfast, snack), Paneer full fat F0394, Chicken thigh F0348, Cauliflower cooked F1022, Spinach cooked F1024 (½–1½ cups), Bhindi F0040 (½–1½ cups), Capsicum F0264. Not added: Pomfret Fry (category `restaurant`), raw mushroom ("raw" in a dinner line), sunflower seeds (the only keto-compatible portion reads "⅛ cup"; round 3 finding 2), raw cabbage (never chosen in 1,600 plans; the reachability test requires every entry to appear). Every entry is reachable in Keto (T10).
- `dietFamilyLowCarbCapOverride` = {paneer 2, dairy 3, fat 4, soy 2}; every other cap is the Balanced one. Balanced code reads only `dietFamilyDailyCap` (which gains a `fat: 3` entry no Balanced entry carries).
- Added fat appears as a plan ITEM only in Low carb / Keto plans. Unit 1 removed fats as items from Balanced (T1 "no fats" test); keto cannot reach its fat target without added fat, and "Ghee, 2 tsp" with a meal is how keto plans are written. The T1 ban keeps its intent for the Balanced pool (§4).

### 3.3 Generator (`curated_diet_plan_generator.dart`, `diet_plan_generator.dart`)

- `DietPlanInputs` gains `strategy` (default Balanced) and `carbTarget` (the EFFECTIVE carbs). A non-Balanced strategy with `carbTarget` null or ≤ 0 runs as Balanced, and so does Keto with a vegan preference (round 3 finding 3: the request carries only the Keto carb target, and Low carb templates with it measured 0.53–0.60 kcal; Balanced is honest and the screen's fallback line fires). The screen itself asks for Low carb with the Low carb target (§3.5).
- New `generatePlan(inputs)` returns `({List<DietMealPlan> meals, DietStrategy builtFor})` (round 2 finding 8: a returned value, not a field on the singleton); `generate` stays and returns `.meals`. `builtFor` is the strategy actually used: Balanced after the legacy fallback or either normalisation.
- `curatedTemplatesFor(strategy)`: Balanced = `kCuratedSlotTemplates` (unchanged). Keto: breakfast protein (+ snack-role item: nuts, cheese, paneer, coconut, + fat; a snack-role food at breakfast is deliberate, it is how a keto breakfast reaches 25 % of a high target); mid-morning snack; lunch protein + sabzi (+ side, + fat); evening snack; dinner protein + sabzi (+ side, + fat). Low carb: breakfast protein (+ breakfast main, + fat); mid-morning snack (+ fruit); lunch protein + grain + sabzi (+ side); evening snack; dinner protein + sabzi (+ side, + fat). Same names, keys and shares, so every reader of a saved plan keeps working.
- Candidates: Balanced skips `lowCarbOnly` (before `passesDiet`); Keto also skips any entry whose carbs at its smallest portion exceed `kKetoItemCarbCap = 6` g (no exemption: the built code exempted fat-role entries, mutant A4 survived because every fat entry is already under the cap (ghee/butter 0 g, coconut 3–6 g), so the exemption was removed). Low carb has no per-item cap (the slot and day carb terms size it; a Low carb swap can offer a gravy sabzi: accepted).
- `_sizeSlot`: Low carb / Keto add `5 * max(0, c - slotCarb) / slotCarb` (weight 5, raised from the prototype's 3 when spinach and bhindi joined Keto: it keeps every non-vegan carb mean at ≤ 1.21×) (slotCarb = carbTarget × share). `_dayScore`: Balanced returns the unchanged expression; Low carb / Keto add `10 * max(0, carbs - 1.1 × carbTarget) / carbTarget` and aim fiber at 50 % (keto) / 70 % (low carb) of the profile target instead of 80 %.
- **Balanced byte-identity, measured:** the 800 Balanced plans (16 archetypes × 50 seeds; per item id, grams, serving text, role) hash to the same SHA-256 on `main` 21db03c7 and on the prototype (`96f7e27cb0486b18…`, captured BEFORE the catalog append). A golden test pins it.

### 3.4 Swap sheet (`diet_plan_swap.dart`)

- `swapAlternatives` and `resolveSwapRole` gain `strategy` (default Balanced). For Balanced the catalog is filtered to `!lowCarbOnly` ONCE at the top of both functions, BEFORE the role scan and the `familyOf` / `familyCount` maps (round 2 finding 3: a saved or legacy Balanced plan can hold F0023 / F0371 / F0348, which must keep resolving and counting exactly as before). Keto applies the item carb cap; caps use the override for Low carb / Keto; `resolveSwapRole` scans `curatedTemplatesFor(strategy)` for the slot (round 1 finding 4: the Balanced templates have no `fat` role), so a loaded Keto plan resolves its ghee as `fat` WITHOUT a saved role (a food with two roles in one slot, coconut at breakfast, resolves to the first in enum order: accepted).
- `dietCatalogFamily` covers all entries on purpose: a legacy saved plan holding Egg (Fried) F0371 now reads its egg family, so an eggetarian keeps it (before 3b it was judged by the veg rule and dropped); the only other new families are paneer (veg either way), chicken (non-veg either way) and fat/veg (veg rows). Stated, and covered by the saved-plan test.
- The screen passes the strategy the DISPLAYED plan was built for (`_planStrategy`, §3.6), never the live one.
- Swap golden: every item of the first 5 Balanced plans of each archetype, with and without its role (2,120 queries, `17a456c1…` on `main`), PLUS synthetic legacy plans holding each Unit 3b id in each Balanced slot for Non-veg / Veg / Eggetarian, and a Balanced item swapped while that id sits in the plan (2,440 queries in all, `0acb6a7d…`, captured on `main` 21db03c7 and equal on the build).

### 3.5 Vegan + Keto: one UI guard and one plan request (replaces revisions 1 and 2)

No vegan keto day exists in the catalog. Measured (prototype, 2 vegan archetypes × 50 seeds): Keto templates with the item cap → 100 % legacy fallback; without the cap → kcal 0.48–0.55, protein 0.49–0.64 of target; Low carb templates with the KETO carb target → kcal 0.53–0.60, carbs 3.2–3.8× target. Revision 1 folded the strategy at read time and revision 2 rewrote it at write time; each review round found more doors and readers (restore, a lapsed Edit Profile save, the extraction kill switch, the dialog preview, the chips). So the pair is NOT made special in the data or in any reader:

- **UI guard (prevents new pairs in normal use):** `DietStrategyChips` gains `disabled` (a set of strategies); the Diet Plan section passes `{keto}` when the profile's food type is Vegan, Edit Profile when the FORM's food type is Vegan. A disabled chip is announced as disabled; under the chips: `Keto needs eggs, dairy, fish or meat. Vegan plans can use Low carb.` Nothing is written by the guard.
- **Plan request (handles any pair that exists anyway):** when the effective strategy is Keto and the food type is Vegan, the Diet Plan screen requests a LOW CARB plan with the Low carb carb target (`effectiveMacroTargets(resolveBaseMacroPack(profile), 'low_carb', pro: true, enabled: true)`), and shows `Keto meals need eggs, dairy, fish or meat. This vegan plan is a Low carb plan.` under the header. The targets on every screen stay the stored Keto ones (the user's choice; the line says the plan differs). The generator maps a Keto + vegan request to Balanced defensively (§3.3), so no caller can reach the 100 % fallback or a starved plan.

### 3.6 Diet Plan screen (`diet_plan_screen.dart`, 781 lines; ceiling 800)

One pure helper `planStrategyFor(effective, foodType)` (in `diet_strategies.dart`): Low carb for Keto + Vegan, otherwise the effective strategy. It is the strategy the screen REQUESTS a plan for, and it is the only place the vegan pair is named. Two new fields: `_requestedStrategy` (`planStrategyFor(...)` at the last generation or load) and `_planStrategy` (what the displayed plan was built for: `builtFor` after a fresh generation, Balanced when the kill switch routes to the legacy generator; the plan's `diet_strategy` stamp, absent = Balanced, after a load). `_planStrategy` is used for the save stamp (replacing `dietStrategyOfTargets(ref.read(...))` at `:350`, for `swapAlternatives`, and for the note under the header: Balanced while a non-Balanced strategy is effective → `This plan uses balanced meals.` (a legacy fallback or the kill switch); a Low carb plan for a vegan Keto user → the §3.5 line. The 3a note line goes away in 3b-3 because this condition replaces it.

`_generateFreshPlan` passes `strategy` and `carbTarget` from `macroTargetsProvider` (which carries the effective strategy, `strategy_index`).

Regeneration on a change of the EFFECTIVE strategy (a tap, Edit Profile, a PRO lapse or renewal): a `ref.listen` on `macroTargetsProvider.select(dietStrategyOfTargets)`, registered only with the flag on. It is idempotent (round 2 finding 5): it does nothing when `planStrategyFor(new effective, food type)` equals `_requestedStrategy`; otherwise it sets `_checkedSaved = false`, `_regenerations = 0` and calls `_generatePlan()` (the saved-plan check re-runs, so a stamped Keto plan reloads when PRO resolves after the first frame). A food-type change regenerates through `_changeFoodType` as today and leaves the effective strategy unchanged (the strategy is not tied to the food type), so the listener does not also fire. A plan generation counter `_planEpoch` increments on every generation and load; an open swap sheet captures it and its `onTap` does nothing when it changed (a stale alternative never lands in a new plan).

To stay under the ceiling, the strategy logic (listener body, `_planStrategy` bookkeeping, note, medical note) moves to a new `widgets/diet_plan_strategy_notes.dart` and a small `services/diet_plan_strategy_state.dart`; the line count is re-checked by the existing ceiling test.

### 3.7 Saved plan (`diet_plan_provider.dart`, the screen)

- `savedPlanMatchesStrategy(plan, current)`, where `current` is `planStrategyFor(effective, foodType)`: a stamped plan matches only the same strategy (a vegan Keto user's saved Low carb plan matches); an unstamped plan matches Balanced only. It is consulted ONLY with the flag on (flag off: today's behaviour, a stamped plan still loads; round 2 finding 9). Called next to `savedPlanMatchesFoodType` at the screen's load (`:86`) and in `DietPlanNotifier.build` (`:108`). `DietPlanNotifier` watches `macroTargetsProvider.select(dietStrategyOfTargets)` ONLY with the flag on (the 3a flag-off dependency rule). A strategy mismatch generates a fresh plan and gives no hints, with NO notice (round 2 finding 4: at the first frame the PRO state may not be known yet, so a notice could be false; the chips and the header label already name the strategy). The food-type notice is unchanged.
- No `role` is added to the saved JSON (the existing pin `saved item key set is EXACTLY the pre-Unit-1 set` stays); roles of a loaded plan resolve through the strategy's templates (§3.4).

### 3.8 Copy (Wardroom: plain, no hype)

- Keto medical note: `Keto is not for everyone. Check with your doctor first if you take diabetes medicine, are pregnant or breastfeeding, or have kidney disease.` Shown (a) under the strategy chips on BOTH screens while Keto is selected, and (b) in the confirm dialog for every change TO Keto: a change to Keto always shows the dialog, even when the numbers are the same or unknown. `DietStrategyConfirmDialog` / `showDietStrategyConfirmDialog` take a NULLABLE preview (null or same-shown: the note and the two buttons, no number rows); `handleDietStrategyTap` and `confirmEditProfileDietStrategy` call it for Keto on every path (Edit Profile's `preview == null || sameShown → true` short-cut no longer applies to Keto). Cancel writes nothing, as today.
- Vegan Keto line (§3.5). Fallback note (§3.6).

### 3.9 Ship-dark

Every 3b-1a/b behaviour except the asset re-seed is behind `DietStrategyFlags.enabled`; the re-seed is Balanced-identical for a user (`is_everyday` is read only by the swap sheet's retired-row skip, and the Balanced swap no longer sees `lowCarbOnly` entries at all). The 3a flag-off identity test (2b) is extended to the new watches and to `savedPlanMatchesStrategy` (a stamped Keto plan still loads with the flag off).

## 4. Tests

3b-1a:
- **Existing tests repointed, never loosened** (rounds 1 and 2; `grep -rn` for `kDietPlanCatalog`, `DietRole`, `DietFamily`, `is_everyday`, `_foodLibraryVersion`, `'diet_strategy'`, `Meals for Keto` before coding, and any further hit is added here):
  - `test/nutrition/food_database_tagged_test.dart:117-120` asserts Ghee F0402 is NOT everyday → repointed: Ghee is everyday as a `lowCarbOnly` keto item, and the assertion moves to "not in the Balanced pool";
  - `test/contracts/diet_plan_curated_switch_test.dart:52-62` (the exact routing ternary) → repointed to the new expression (`generatePlan(...)` / legacy), same intent;
  - `test/nutrition/diet_strategy_selector_test.dart:293-310` (no-targets Keto: no dialog) → Keto now shows the note-only dialog; the Low carb no-targets case keeps the old assertion;
  - `test/nutrition/diet_strategy_selector_test.dart:470-485` (one `'diet_strategy'` literal per screen) → recounted: the screen also READS the stamp (load) and the count pins write sites by a write-shaped regex;
  - `supabase/functions/_shared/captain_manual_food_type_test.ts` literals for the "Older values" line and the legacy text → updated in 3b-2 with the reworded line; `curated_diet_plan_test.dart` T1 "no fats" → the banned set is asserted over the BALANCED pool (`!e.lowCarbOnly`), and a new assertion lists the four fat entries as exactly the `lowCarbOnly` `fat`-role set; T1 categories: unchanged rule, no exception needed (Pomfret Fry dropped); T1 identical-macros, id uniqueness, imports-nothing, T7 serving texts: run over all entries including the new ones; T1 mirror: after re-running `scripts/patch_food_database_v4.dart`. The whole file is run against the build before the plan's done-criteria.
- **Asset:** the 14 ids flip to `is_everyday: true` (`scripts/patch_food_database_v4.dart` re-run: a 14-line diff, 165 everyday rows); `_foodLibraryVersion` 4 → 5 (`seed_service.dart:211`; `:242` re-seeds when stored < constant); `food_library_v4_upgrade_behavioral_test.dart` extended: a v4 box re-seeds to v5 and the 14 ids read true.
- **Balanced goldens:** generator SHA (§3.3) and swap SHA (§3.4).
- **T10 strategy matrix** (`test/nutrition/curated_diet_plan_strategy_test.dart`, real asset, 16 archetypes × 50 seeds × {Low carb, Keto}; vegan Keto is the defensive path and is asserted in T11, not floored): zero fallbacks; Keto plans hold no grain, fruit or breakfast main and no item over the cap; template shape per strategy; every `lowCarbOnly` entry reachable, and in Keto; no `lowCarbOnly` food in a Balanced plan; caps with the override; carbs mean ≤ 1.25× target; kcal and protein floors PER ARCHETYPE = the built code's minimum − 0.02 (30 rows, raise only). Built-code minima: kcal 0.68–0.95, protein 0.40–0.91; the lowest are the veg/vegan Low carb cuts (stated limit, §3.1).
- **Swap:** Keto alternatives respect the cap and the strategy's templates (`fat` resolves); Balanced never offers `lowCarbOnly`.
- Throwaway harnesses (`test/nutrition/zz_*`) are deleted before the commit (round 3 finding 8); their durable parts are G1/G2/T10.
- **Mutants (each applied, counted, run, red):** Balanced sees `lowCarbOnly` (generator; swap candidate loop; swap role scan / family map); keto carb cap off; cap applied to fat-role items; vegan Keto not mapped in the generator; carb term off in `_sizeSlot`; carb term off in `_dayScore`; fiber aim Balanced for keto; override caps used for Balanced; override keys dropped; templates swapped; null `carbTarget` not normalised; `builtFor` not Balanced after a fallback; `resolveSwapRole` on Balanced templates.

3b-1b:
- **Vegan Keto:** `planStrategyFor` truth table (3 strategies × 5 food types); a Veg Keto user switching to Vegan regenerates once (through `_changeFoodType`, not also the listener) into a Low carb plan, and their saved Low carb plan then matches; the chip is disabled for Vegan on both screens (and announced as disabled) with the reason line; a stored Keto + Vegan pair gets a Low carb plan with the Low carb carb target and the §3.5 line; the generator's own defensive mapping of a Keto + vegan request is Balanced (`builtFor` Balanced, zero fallbacks; round 3 finding 3, built and tested in 3b-1a T11), so the screen never sends that pair: `planStrategyFor` turns it into a Low carb request first.
- **Screen:** a strategy change regenerates (flag seam); the listener is a no-op when the strategy equals `_requestedStrategy` (one generation per change, counted); a stamped Keto saved plan reloads when PRO resolves after the first frame, with no notice; the fallback note shows for the kill switch and a forced fallback; `_planStrategy` (not the live strategy) is stamped and passed to the swap; a swap tapped after a regeneration changes nothing.
- **Saved plan:** `savedPlanMatchesStrategy` truth table; consulted only with the flag on; `DietPlanNotifier` rebuilds on a strategy change with the flag on and adds no watch with it off; a legacy eggetarian plan with F0371 loads (the `dietCatalogFamily` change, §3.4).
- **Copy:** the medical note on both screens and in the dialog, including the same-shown and no-targets Keto paths, on both the Diet Plan and Edit Profile doors.
- **Mutants:** listener not registered; listener not idempotent; `_checkedSaved` not reset; live strategy stamped; note condition inverted; saved-plan strategy check off; check applied with the flag off; unstamped plan matched for Keto; flag-off watch added; Keto dialog skipped when same-shown; stale swap applied.

## 5. 3b-2 server

- `captain_manual.ts` SECTION 7 DIET gains a DIET STRATEGY passage: one constant `DIET_STRATEGY_MANUAL_PASSAGE`, placed in the template AFTER the food-type lines and OUTSIDE every `FOOD_TYPE_MANUAL_RULES_NEW` string, so the food-type switch's `.replace` never touches it. `captainManual()` composes the two switches: start from the food-type choice (`CAPTAIN_MANUAL` or `CAPTAIN_MANUAL_LEGACY_FOOD`, unchanged), then, when `DISABLE_DIET_STRATEGY_MANUAL_RULES` is exactly "true", remove the passage with one `.replace(DIET_STRATEGY_MANUAL_PASSAGE, '')` (asserted present first). A Deno test covers all four env combinations and the parity of the reworded line. Text: when `snapshot.profile.diet_strategy` is `low_carb` or `keto`, use `snapshot.daily_targets.carbs` / `fat`; keto: no rice, roti, bread, fruit, sugar or gravy curries; build meals from eggs, paneer, meat, fish, plain vegetables, ghee, nuts and seeds; low carb: one grain portion at lunch, none at dinner; never change the strategy or food type in chat (the Diet Plan screen does); the medical note. The passage is conditional on a field only the CHAT snapshot carries, so `weekly-report` (which bundles the manual but has no `daily_targets`) reads it as inert. The "Older values … keto or low_carb = non_veg with a low-carb emphasis" line is reworded in BOTH copies (template and `FOOD_TYPE_MANUAL_RULES_NEW[1]`): those are old FOOD-TYPE spellings; the strategy is a separate field.
- `suggestMeal.ts`: the existing `user_profile` select adds `diet_strategy`; a read error keeps today's fail-safe (vegan options) and applies no strategy; the strategy applies only when `ctx.isPro` (server-verified by `checkPro`); keto (vegan: low carb) → `.lte("carbs_std", 6)`, low carb → `.lte("carbs_std", 25)`, inside the query before its row limit. Kill switch `DISABLE_SUGGESTMEAL_DIET_STRATEGY` (exactly "true"); its removal tracked with OI-510's switches. Accepted window: the client's local PRO state and `checkPro` can disagree briefly (screens Balanced, tool filtered, or the reverse), and the client's local `disable_diet_strategy` kill switch does not reach the server (a column written while the flag was on stays); nothing is written by either. Before editing, `suggestMeal_test.ts` is grepped for select-string assertions.
- Deploy ai-proxy and weekly-report, one founder go each, rollback dry-run first (skill §6).

## 6. 3b-3 flip

`kDietStrategyDefaultOn = true`; the 3a note line removed (§3.6's condition replaces it); the `docs/ship_dark_pending_review.yaml` entry closed by this commit's record (full ×2 review + `bpass: accepted`). Migration 179 is already live. Device check by the founder after the build: a Keto day on a veg and a non-veg profile, a lapse (Balanced shown, choice kept), an Edit Profile change, Vegan + Keto (Low carb), the PDF label.

## 7. Open questions for the founder (proceeding on the recommended default unless vetoed)

1. Vegan + Keto: the Keto chip is disabled for Vegan; a vegan user who already holds Keto gets a Low carb plan with a one-line note (§3.5).
2. Added fat (ghee, butter, coconut) shown as plan items in Low carb / Keto plans (§3.2).

## 9. Round 1 dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | the read-time vegan fold misses readers/writers (dialog preview, paused hint, chips, Edit Profile, no rebuild on a food-type change) | fold REMOVED; a write-time rule at the three doors (§3.5): no reader changes, and the food-type door invalidates the target providers when it moves the strategy |
| 2 | P1 | legacy fallback / kill switch show a Balanced plan under a KETO label; null carbTarget | `lastStrategyUsed` + `_planStrategy` + the mismatch note (§3.3, §3.6); null/≤0 carbTarget runs as Balanced |
| 3 | P1 | existing T1 tests go red (ghee/butter ban, restaurant category), asset flags | repoints listed (§4); Pomfret Fry and raw mushroom dropped; patch script + v5 re-seed + extended upgrade test |
| 4 | P2 | a loaded saved Keto plan cannot resolve `fat` | `role` saved and loaded; `resolveSwapRole` uses the strategy's templates (§3.4, §3.7) |
| 5 | P2 | listener ambiguity, stamp of the live strategy, double generation, 800-line ceiling | `_checkedSaved` reset + `_generatePlan()`; `_planStrategy` stamp; `_changingFoodType` guard; new files (§3.6) |
| 6 | P2 | medical note skippable | note on both screens + a mandatory dialog for any change to Keto (§3.8) |
| 7 | P2 | manual switch, older-values line, weekly-report, suggestMeal fail-safe/limit/vegan | own kill switch; both copies reworded; passage inert without the chat snapshot field; select + `.lte` + fail-safe + vegan rule + accepted window (§5) |
| 8 | P2 | goldens, missing mutants, floors, flag-off watch | swap golden; mutant lists extended; floors from the built code; flag-gated watch (§4, §3.7) |
| 9 | P2 | 3b-1 too large | split 3b-1a / 3b-1b (§2) |
| 10 | P3 | wording | breakfast snack deliberate (§3.3); categories (§3.2); migration live (§6) |

## 10. Round 2 dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | the write-time vegan rule misses doors (restore, lapsed Edit Profile save, extraction kill switch, no heal on an equal type) | data mechanism REMOVED (§3.5): vegan + Keto is an ordinary pair in the data; a UI-only chip guard prevents new pairs, and the screen requests a Low carb plan for any pair that exists (measured: no honest vegan keto plan exists). No door or reader depends on it |
| 2 | P1 | existing tests turned red and not listed | listed with their repoints (§4): tagged-asset ghee, routing ternary, no-targets Keto dialog, literal counts, Deno literals; a grep step before coding |
| 3 | P1 | Balanced swap changes for saved/legacy plans holding the new ids | Balanced filters the catalog to `!lowCarbOnly` before the role scan and family maps; `dietCatalogFamily` change stated and tested; golden adds legacy ids (§3.4) |
| 4 | P2 | first-frame false mismatch notice, wrong text | no notice for a strategy mismatch (§3.7) |
| 5 | P2 | double generation, stale swap | listener idempotent on `_requestedStrategy`; `_planEpoch` guards the swap sheet (§3.6) |
| 6 | P2 | silent vegan switch | moot: nothing is switched; the plan line names the Low carb plan (§3.5) |
| 7 | P2 | two manual switches on one string | one passage outside the food-type strings, removed by its own `.replace` after the food-type choice; four-combination test (§5) |
| 8 | P3 | `lastStrategyUsed` on a singleton | `generatePlan` returns `builtFor` (§3.3) |
| 9 | P3 | low carb swap cap, server vs local switch, select test, flag-off saved plan | accepted and stated (§3.3); window text (§5); grep step (§5); check only with the flag on (§3.7) |

## 11. Round 3 dispositions

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | the PDF label/targets read the live strategy, not the plan's | 3b-1b: the PDF `strategyLabel` comes from `_planStrategy`, and the §3.5/§3.6 line is printed in the PDF when `_planStrategy` differs from the effective strategy; registry lists the PDF reader; test: a vegan Keto PDF carries the line, a fallback PDF is not labelled Keto |
| 2 | P2 | spinach, bhindi, sunflower dead in Keto (cap 6) | built: spinach/bhindi gain a ½ portion (3.4/3.5 g), sunflower and the `seed` family dropped, raw cabbage dropped (never chosen); T10 reachability test (all and Keto) |
| 3 | P2 | defensive vegan Keto mapping starves the plan | built: maps to Balanced (`builtFor` Balanced, fallback line) (§3.3) |
| 4 | P2 | listener before the first generation (`_requestedStrategy` null) | 3b-1b: `_requestedStrategy` set synchronously in `initState` from the current targets; a test fires the provider before the post-frame callback and counts one generation |
| 5 | P2 | the chip guard does not stop every new pair; disabled+selected chip; how the section gets the food type | 3b-1b: wording "does not offer Keto to a Vegan profile"; a selected Keto chip renders selected and disabled with the reason line and a tap does nothing; Edit Profile does NOT reset the form strategy (the pair is legal data, §3.5) and the pair-on-save path is tested; `DietStrategySection` watches `userProfileProvider.select(foodTypeOfProfile)` |
| 6 | P2 | coach manual: vegan + keto | 3b-2: the passage adds "vegan with keto: low carb with plant foods" (pinned in the Deno test); the passage reaches every channel (morning, proactive, weekly): accepted, it is a few lines and inert without the field |
| 7 | P2 | source-grep tests not listed (saved-plan key slice, routing ternary, no-modal, restore completeness, T2) | 3b-1b grep list extended: `diet_plan_saved_loaded_writer_to_reader_test.dart` (the `_savePlan`→`_loadSavedPlan` slice: the two methods stay adjacent and in order), `diet_plan_curated_switch_test.dart`, `diet_plan_screen_no_modal_test.dart`, `restore_completeness_writes_test.dart:118-137`; T2 stays Balanced-only by design (its plans are Balanced) |
| 8 | P2 | throwaway harnesses | deleted (§4) |
| 9 | P2 | suggestMeal edit points | 3b-2: the helper returns `{foodType, strategy}`; the `.lte` goes inside `foodQuery` so all three query sites get it; `carbs_std` is per standard serving (stated); tests for the egg/fish branch and the read-error branch |
| 10 | P3 | note precedence; stale §9 rows | the fallback line wins over the vegan line; §9 rows 4/5 superseded by §10 rows 3/5 |
| 11 | P3 | `lastStrategyUsed` wording | superseded by `generatePlan` / `builtFor` (§3.3) |
