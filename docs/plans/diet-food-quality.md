# Plan — Diet plan Unit 1: food quality (curated catalog + meal templates)

- **Branch / worktree:** `diet-food-quality` (`.claude/worktrees/diet-food-quality`), base `94a021a0`.
- **Date:** 2026-11-14. **Revision:** 4 — round 3 CONVERGED (0 P0/P1; its P2/P3 folded in, §11). Revision 3 was (round 1: 4 P1 + 8 P2 + 3 P3; round 2: 1 P1 + 10 P2 + 2 P3 — all addressed, see §9 and §10). Round 2's P1 came from the swap sheet's broad "everyday" top-up; that mechanism is REMOVED (swaps are catalog-only), not patched.
- **Blast radius (computed):** `account` (`dart run scripts/blast_radius_from_diff.dart lib/features/nutrition/services/diet_plan_generator.dart lib/features/nutrition/screens/diet_plan_screen.dart lib/core/services/seed_service.dart`).
- **Tier (§4.12.6):** M. Full ×2 plan review; gate loop + CI before any review with a diff; B-pass before merge.
- **Execution mode (§4.12.7):** INLINE, one worktree, one coordinator; no subagent writes code.
- **Closes:** OI-214 (template layer). Recurrence of diagnose `d3c7a9` (concept `diet_plan_generation_quality`) → new diagnose doc, FULL template.
- **Founder decisions (2026-11-14):** BOTH a hand-curated allowlist (150–250 foods) AND an everyday-foods tag; no processed foods; meals that look like real Indian meals; readily available foods; whey/supplements arrive in Unit 4. Units 2–4 are out of scope here.

## 1. Symptom (measured)

Ten plans from the CURRENT generator on the real `assets/data/food_database.json` (1,437 rows; seeds 100..433; 1,600–2,600 kcal; veg/non-veg/vegan):

| Defect | Evidence |
|---|---|
| Soy everywhere | Soybean (boiled) is the lunch anchor in 7/10; soy rows in 9/10; three soy rows in one day in 3/10 (day uniqueness is per id, so three soy ids pass). |
| Repetition | Roasted peanuts = evening snack 8/10; Greek yogurt = mid-morning 8/10; no dal/rajma/chana/egg/paneer in any of the 10. |
| Exotic / branded | Brie, Camembert, kimchi, shiitake, Brussels sprouts, asparagus, kale, hemp milk, rice milk, seitan, quinoa; Yoga Bar oats, Saffola oats, Mother Dairy chach, Chobani, Fortune mustard oil, "Sappe … Mogu litchi". |
| Not meals | 2–3 staples in a meal (rice + steel-cut oats; pasta + rava idli); oats at dinner; Wheat Flakes at lunch (founder screenshot); mustard oil / ghee / butter / khoya as items; a dill pickle spear, one garlic clove, 8-kcal lettuce as "vegetables". |
| Processed drinks/jams | Thums Up in an Evening Snack (founder screenshot 2026-11-14): `F0522` + `F1268` "Thumbs Up" + 6 other cola rows are `is_ultra_processed: false`, category `beverages`; the legacy evening slot's fillers include `beverages` (`diet_plan_generator.dart:294`). `F1421` mapro jam and `F1253` Mogu litchi are tagged `fruits`, non-UPF. |

## 2. Writers and readers (verified at `94a021a0`)

**Writers of plan content**
- `lib/features/nutrition/services/diet_plan_generator.dart:308` `generate` — anchor pools `:159/:175/:202`, slot defs `:258` whose `fillerCategories` make a whole DB category the pool (root cause of exotic/branded rows).
- `lib/features/nutrition/screens/diet_plan_screen.dart:73` `_generateFreshPlan` (seed = local day `hashCode`, `:86`).
- `diet_plan_screen.dart:125` `_swapItem` — alternatives = first 5 rows of `getByCategory(item.category)` minus UPF minus diet (`:132-139`).
- `diet_plan_screen.dart:249` `_savePlan` — writes an EXPLICIT key set (`:249-272`) via `UserRepository.saveDietPlan` → `MigratedKey('saved_diet_plan')` in the user box (`user_repository.dart:1165-1174`).
- Asset `assets/data/food_database.json` + `lib/core/services/seed_service.dart:203` `_foodLibraryVersion = 3`; `_seedFoods` `:335` (`putAll` overwrite; errors swallowed `:349-355`); upgrade condition `foodsSeeded && storedFdVersion < _foodLibraryVersion` `:233-234`; seeding awaited before any screen (`splash_screen.dart:160`).

**Readers (contract stays compatible)**
- `diet_plan_screen.dart:106` `_servicePlanToScreenPlan`; `:303` `_loadSavedPlan`; PDF export (same `_MealPlan` fields).
- `lib/features/nutrition/providers/diet_plan_provider.dart:56` `DietPlanNotifier.build` → `todays_meals_card.dart` ("SUGGESTED" chips: meal name + item names).
- Sync/restore of the saved plan: `syncSavedDietPlan` / `_restoreSavedDietPlan` (`sync_restore_completeness.dart:358`), cloud `saved_diet_plans` JSON blob.
- `nutrition_provider.dart:1354` `DietPlanGenerator.instance.clearCache()` after a custom food is added.
- `isAnchor` / `isQuotaLocked`: read only by the legacy generator and tests (`diet_plan_quality_constraints_test.dart:333`, `food_database_tagged_test.dart:259`, `diet_plan_generator_test.dart:228`).
- No reader of the cloud `food_database` table depends on parity with the asset for generation or swap (both read Hive `foodBox`); this batch does not touch the cloud table.

## 3. Design

### 3.1 Curated catalog — new `lib/features/nutrition/services/diet_plan_catalog.dart`

`const List<CatalogEntry> kDietPlanCatalog` with `CatalogEntry(foodId, roles, family, portions)`; enums `DietRole {breakfastMain, breakfastProtein, mainProtein, grain, sabzi, side, fruit, snack}` and `DietFamily {bfgrain, grain, chilla, egg, dairy, sprouts, paneer, plantmilk, soy, dal, chicken, fish, mutton, veg, side, fruit, nut, roast, dried}`. The catalog holds NO macros: numbers come from the `foodBox` row with that id. A catalog id missing from `foodBox` is skipped. **The catalog REPLACES `meal_fit` for the curated path** (e.g. pesarattu/adai/thalipeeth/puttu/idiyappam/sevai are `meal_fit: [lunch, dinner]` in the DB but are breakfast mains here); the legacy path keeps reading `meal_fit`.

The FULL list (151 unique ids — the count is always derived from `kDietPlanCatalog` in tests, never a literal; every id verified in the asset; generated from the same data the prototype measured):

| Role | Entries (id: name) — family in brackets | Count |
|---|---|---|
| breakfastMain | F0005 Idli, F0149 Set Dosa, F0158 Rava Idli, F0167 Idiyappam, F0009 Oats, F0006 Dosa, F0147 Onion Dosa, F0146 Masala Dosa, F0151 Paper Dosa, F0152 Pesarattu, F0153 Adai, F0154 Uttapam, F0156 Tomato Uttapam, F0155 Onion Uttapam, F0129 Aloo Paratha, F0130 Gobi Paratha, F0131 Mooli Paratha, F0133 Methi Paratha, F0143 Thalipeeth, F0166 Puttu, F0164 Appam, F0008 Rava Upma, F0168 Vermicelli Upma, F0170 Sevai, F1442 Kanda Poha, F1443 Vegetable Dalia, F1444 Khaman Dhokla [bfgrain]; F0132 Paneer Paratha [paneer]; F1445 Besan Chilla, F1446 Moong Dal Chilla [chilla] | 30 |
| breakfastProtein | F0021 Boiled Egg, F0344 Indian Omelette, F0789 Egg White Omelette, F0341 Egg Bhurji, F0370 Scrambled Eggs, F0372 Poached Eggs [egg]; F0029 Curd, F0384 Hung Curd, F0030 Greek Yogurt, F0031 Toned Milk, F0032 Full Cream Milk [dairy]; F0017 Mixed Sprouts [sprouts]; F0229 Paneer Bhurji [paneer]; F0381 Soy Milk [plantmilk]; F1014 Tofu (Firm) [soy] | 15 |
| mainProtein | F0011 Toor, F0012 Moong, F0016 Masoor, F0013 Chana Dal, F0171 Urad, F0172 Black Urad, F0173 Whole Moong, F0177 Kala Chana, F0179 Lobia, F0182 Dal Tadka, F0183 Dal Fry, F0185 Chana Masala, F0186 Rajma Masala [dal]; F0226 Palak Paneer, F0228 Matar Paneer, F0393 Paneer (Low Fat), F0229 Paneer Bhurji [paneer]; F0373 Soy Chunks, F0018 Soybean, F1014 Tofu (Firm) [soy]; F0019 Grilled Chicken Breast, F0020 Chicken Curry, F0026 Tandoori Chicken, F0303 Chicken Tikka, F0349 Chicken Drumstick [chicken]; F0024 Fish Curry, F0358 Rohu, F0362 Surmai, F0357 Pomfret, F0367 Prawn, F0327 Fish Tikka [fish]; F0025 Mutton Curry, F0354 Lean Mutton [mutton]; F0342 Anda Masala [egg] | 34 |
| grain | F0003 Roti, F0120 Phulka, F0139 Bajra Roti, F0140 Jowar Roti, F0141 Ragi Roti, F0142 Makki Roti, F0001 White Rice, F0002 Brown Rice, F0094 Basmati Rice, F0099 Red Rice, F0101 Jeera Rice, F0103 Lemon Rice [grain] | 12 |
| sabzi | F0039 Mixed Sabzi, F0206 Aloo Gobi, F0207 Aloo Matar, F0208 Aloo Methi, F0209 Aloo Palak, F0210 Aloo Baingan, F0211 Aloo Jeera, F0213 Bhindi Masala, F0215 Karela, F0217 Tinda, F0218 Lauki, F0219 Tori, F0220 Kaddu, F0223 Methi Sabzi, F0237 Mixed Veg Curry, F0244 Cabbage Sabzi, F0245 Carrot Sabzi, F0246 Beans Poriyal, F0247 Beetroot Poriyal, F0251 Thoran, F0249 Avial, F0250 Olan, F0041 Baingan Bharta, F0036 Palak, F0038 Broccoli, F0256 Mushroom Curry, F0224 Sarson Ka Saag, F0253 Undhiyu, F0252 Erissery [veg] | 29 |
| side | F1447 Vegetable Raita, F1448 Kachumber Salad, F0042 Cucumber [side]; F0029 Curd, F0033 Buttermilk [dairy] | 5 |
| fruit | F0047 Apple, F0048 Mango, F0049 Papaya, F0050 Watermelon, F0051 Pomegranate, F0414 Pineapple, F0416 Grapes, F0418 Pear, F0422 Lychee, F0426 Jamun, F0046 Banana, F0052 Orange, F0053 Chikoo, F0424 Guava, F0433 Mosambi, F0423 Custard Apple, F0415 Kiwi, F0410 Strawberry, F0427 Ber [fruit] | 19 |
| snack | F0077 Almonds, F0079 Cashews, F0080 Walnuts, F0078 Roasted Peanuts, F0464 Pistachios, F0473 Pumpkin Seeds [nut]; F0708 Roasted Chana, F0710 Plain Makhana [roast]; F0449 Dates, F0451 Dried Figs [dried]; F0017 Mixed Sprouts [sprouts]; F0021 Boiled Egg [egg]; F0029 Curd, F0033 Buttermilk [dairy] | 13 |

Dishes that duplicate another entry under a different id were REMOVED instead of grouped (idli F0157, dosa F0145, chole F0015 / pindi chana F0184 / rajma F0014 vs their masala rows, soya chaap F0374 = soy chunks' identical macros, egg curry F0340 vs anda masala, cabbage poriyal F0248 vs cabbage sabzi, pumpkin curry F0221 vs kaddu, yellow moong F0174, sweet lime F0436 vs mosambi). A test pins "no two catalog ids with identical `calories_std/protein_std/carbs_std/fat_std` in the same category" (§4 T1) so a duplicate cannot be re-added silently.

Drumstick Sambar (F0255) is NOT a sabzi and Bharwan Bhindi (F0212, identical macros to Avial) is not listed (round 3). Sambar and rasam are NOT sides (they are lentil gravies: dal + sambar or chicken curry + sambar is not a meal) and packaged bread is NOT in the catalog (NOVA ultra-processed; `F0921` also embeds "(1 slice)" in its name).

**Meal coherence rule (within one slot):** no two items may share a key-ingredient token from `{palak, matar, sambar, methi, baingan, mushroom, chana, moong, rajma, paneer, egg, anda, soy, soya, tofu, curd, dahi}` (lower-cased name words). This blocks palak paneer + aloo palak, matar paneer + aloo matar, drumstick sambar + any sambar, egg bhurji + boiled egg, curd + raita-style doubles. Measured: 0 invalid samples across 50 seeds × 6 archetypes incl. vegan.

**Family caps per day** (the soy fix): `soy 1, paneer 1, egg 1, chicken 1, fish 1, mutton 1, nut 1, chilla 1, roast 1, dried 1, plantmilk 1, sprouts 1, dal 2, dairy 2`; `bfgrain, grain, veg, side, fruit` uncapped. Per-day `foodId` uniqueness applies on top. (Measured: raising soy/paneer to 2 for veg moves veg-cut protein by only +0.02–0.04, so caps stay at 1 — the founder's soy complaint wins.)

**Portions** (multipliers of the standard serving; the FULL per-entry table is in the catalog file and pinned by T7):

| Descriptor kind (examples) | Allowed multipliers |
|---|---|
| bowl / cup / plate / glass dishes (dals, sabzis, upma, poha, dalia, curd, milk, rice) | from {0.5, 1, 1.5, 2} (per entry subset) |
| countable "1 X" (roti, phulka, dosa, paratha, chilla, uttapam, appam, drumstick, egg) | whole numbers only, e.g. roti {1,2,3,4}, phulka {2,3,4,5} |
| countable "2 X" / "3 X" / "4 X" (idli, set dosa, idiyappam, dhokla pieces, tikka pieces, dates, figs) | {1, 1.5, 2} only when the result is whole (2→3→4), else {1, 2} |
| egg dishes with a parenthetical ("1 cup (2 eggs)", "1 omelette (2 eggs)") | {1, 2}; the parenthetical number is scaled too ("2 cups (4 eggs)") |
| "1 medium" fruits, "1/4 cup" nuts/roasts, "1 handful" peanuts, "10 almonds", "5 halves", "100 g" fish/chicken | {1, 2} ("1/4 cup" × 2 = "1/2 cup"; "10 almonds" × 2 = "20 almonds"; "100 g" also 1.5 → "150 g") |

### 3.2 Template generator — new `lib/features/nutrition/services/curated_diet_plan_generator.dart`

`class CuratedDietPlanGenerator` with `List<DietMealPlan> generate(DietPlanInputs)` — the same five slots, `name`, `slotKey`, shares (0.25/0.10/0.30/0.10/0.25) as `diet_plan_generator.dart:258-305`. It reads rows via `FoodRepository.getById` (returns `null` for a missing id — `food_repository.dart:27-31`) on every call; no cache, so the `clearCache` caller needs no change. Constructors: `CuratedDietPlanGenerator.instance` (production) and `CuratedDietPlanGenerator.forTest(FoodRepository repo, {List<CatalogEntry>? catalog})` (T3b's fixture catalog). Cost: ≤ 40 samples × 5 slots × ≤ 625 combinations ≈ 125k cheap evaluations; measured in the build on the VPS and stated in the diagnose doc (target < 100 ms; the call is synchronous on the UI thread today, same as legacy). **At runtime it filters ONLY by the catalog + `DietPlanGenerator.passesDiet`** — never by `is_ultra_processed` or `is_everyday` — so a v3 box whose re-seed failed still generates (missing new ids are skipped).

| Slot | Required roles | Optional (portion may be 0) |
|---|---|---|
| Breakfast | breakfastMain, breakfastProtein | fruit |
| Mid-Morning Snack | fruit | snack |
| Lunch | mainProtein, grain, sabzi, side | — |
| Evening Snack | snack | fruit |
| Dinner | mainProtein, grain, sabzi | side |

1. **Sample a day:** slots in order; per role, uniform pick among entries passing diet, unused `foodId`, family cap, and the meal-coherence rule (§3.1). An exhausted REQUIRED role invalidates the sample; an exhausted optional role is skipped.
2. **Size each slot:** enumerate portion combinations (an optional item adds a 0 option; ≤ 5 items × ≤ 5 options) minimising `3·|kcal − slotKcal|/slotKcal + max(0, slotProt − prot)/slotProt + 0.3·max(0, prot − 1.3·slotProt)/slotProt`.
3. **Best of K = 40 samples** minimising `3·|kcal − T|/T + 2·max(0, 0.95·P − prot)/P + max(0, prot − 1.15·P)/P`; all randomness from `Random(seed)`.
4. **Output items:** macros = round(row `*_std` × m) and `fiber` = round(row `fiber_per_100g` × servingG / 100) (as the legacy `_toItem` does; the constructor default of 0 must not be relied on — d3c7a9's fiber class); `servingG` = row g × m; item ORDER inside a slot = required roles in table order, then optional (so `TodaysMealsCard`'s `firstFoodName` is the protein/main); `servingDesc` = `scaleServingDesc(desc, m)`; `category` = row category; `isAnchor` = role ∈ {breakfastProtein, mainProtein}; `isQuotaLocked` = false; NEW nullable field `DietPlanFoodItem.role` (String, the role name; legacy generator leaves it null).
5. **No valid sample in 40** ⇒ return the legacy `DietPlanGenerator` output; the generator exposes `int get lastFallbackCount` (test seam) and `debugPrint`s. Tests assert it stays 0 across the archetype matrix.

`scaleServingDesc(String desc, double m)` (pure, public for tests):
- `m == 1` ⇒ `desc` unchanged.
- desc = `<qty>[ ]<unit words>[ (<qty2> <words>)]` (a unit glued to the number is accepted: `100g`), qty an integer, decimal or `a/b`: both quantities are multiplied; results print as integers when whole, else as quarters (`1/2`, `3/4`, `1 1/2`); the first unit word is pluralised only when the ORIGINAL quantity is ≤ 1 and the new quantity > 1 (so `3 egg whites` × 2 = `6 egg whites`, never `6 eggs whites`), via a fixed map (`cup→cups, bowl→bowls, glass→glasses, plate→plates, piece→pieces, handful→handfuls, roti→rotis, chilla→chillas, dosa→dosas, paratha→parathas, uttapam→uttapams, appam→appams, drumstick→drumsticks, egg→eggs, slice→slices, phulka→phulkas, adai→adais, thalipeeth→thalipeeths, pesarattu→pesarattus, puttu→puttus, omelette→omelettes`; for `1 masala dosa` / `1 leg piece` the pluralised word is the LAST unit word: `2 masala dosas`, `2 leg pieces`), words not in the map are left as written (`idli`, `medium`, `almonds`, `halves`, `g`). Examples: `1 roti`×3 → `3 rotis`; `1/2 cup`×1.5 → `3/4 cup`; `1 cup (2 eggs)`×2 → `2 cups (4 eggs)`; `100 g`×1.5 → `150 g`; `1 medium`×2 → `2 medium`.
- The countable-unit set (whole-number results required) = the map keys above + `idli, idiyappam, dates, figs, almonds, cashews, halves, pieces, egg whites, set dosas, masala dosa, leg piece`. T7 fixed cases include `3 egg whites`×2, `1 masala dosa`×2, `100g`×1.5, `2 set dosas`×1.5.
- No `×` fallback exists: a catalog descriptor that does not parse is a T7 failure, so every catalog entry is guaranteed a clean label.
- T7: fixed examples + a sweep over EVERY catalog entry × each portion asserting the output parses back to `qty × m`, countable results are whole, and no `NaN`/`Infinity`/`×` appears.

### 3.3 Kill switch (§4.6) — through a flag accessor, not the widget

New `lib/features/nutrition/services/diet_plan_flags.dart` `class DietPlanFlags { static bool get curatedEnabled }` — same shape as `PlateFlags` (`lib/shared/widgets/exercise_plate/plate_flags.dart:53`): reads `HiveService.instance.configBox.get('disable_curated_diet_plan') != true`, `try/catch` ⇒ `true`. `configBox` is cleared by `clearAllData()`, so the switch does not survive a sign-out (same accepted property as PlateFlags G4). `_generateFreshPlan` calls `DietPlanFlags.curatedEnabled ? CuratedDietPlanGenerator.instance.generate(…) : DietPlanGenerator.instance.generate(…)` with identical inputs. The screen never touches Hive. Legacy deletion → a new OI minted in this batch (Status OPEN, "Blocked on: founder device check of the curated plan"), not an intention.

### 3.4 Swap sheet (`_swapItem`) — catalog-only

The alternatives logic moves into a pure function `swapAlternatives({required item, required slotKey, required pref, required planItemIds, required planFamilyCounts, required FoodRepository repo, List<CatalogEntry> catalog = kDietPlanCatalog})` in `lib/features/nutrition/services/diet_plan_swap.dart`; `_swapItem` calls it and keeps its sheet/snackbar UI.
- **Slot:** `_MealPlan` gains `slotKey`; fresh plans copy it from `DietMealPlan.slotKey`; a LOADED plan maps the saved meal `name` → slotKey with the fixed generator names (`Breakfast→breakfast, Mid-Morning Snack→mid_morning, Lunch→lunch, Evening Snack→evening, Dinner→dinner`; unknown → no role ⇒ snackbar). The saved JSON is unchanged.
- **Role resolution:** `item.role` if set (fresh plan, or inherited through a swap); otherwise derived from the catalog by `(foodId, slotKey)`: the first role, in `DietRole` ENUM order, of that catalog entry that the slot's template allows (§3.2 table) — deterministic for curd / sprouts / boiled egg. A saved plan reopened after Save therefore keeps role-aware swaps (round-2 finding 2). An item whose `foodId` is NOT in the catalog (a plan saved before this batch, e.g. Brie) gets the role whose category set matches the item's category within that slot (`staples→grain/breakfastMain`, `vegetables→sabzi`, `pulses/protein→mainProtein/breakfastProtein`, `dairy→breakfastProtein/side`, `fruits→fruit`, `nuts_seeds→snack`); no match ⇒ the "No alternatives" snackbar (intended, e.g. a legacy dairy item in a snack slot).
- **Candidates:** catalog entries of that role, passing `passesDiet`, whose `foodBox` row exists and is not explicitly `is_everyday == false` (the tag's runtime reader: the DB can retire a catalog food without a code change; an ABSENT tag — a v3 box — passes), excluding ids already anywhere in the plan, excluding entries whose family is at its day cap when the replaced item is not of that family, excluding entries that break the meal-coherence rule with the slot's other items. Up to 6, ordered by closeness of the entry's best-fitting portion kcal to the replaced item's kcal, ties broken by catalog index; each offered at that portion.
- The swapped-in `_PlanFoodItem` takes the NEW row's category, the inherited role, and the scaled `servingDesc`/macros/fiber.
- No `foodBox` category scan remains in the swap path (the old first-5-of-category pool, the source of Brie/kimchi suggestions, is deleted).

### 3.5 Everyday tag — an exact DB mirror of the catalog

`is_everyday == true` iff the row's id is in `kDietPlanCatalog`; every other row `false`. Written by `scripts/patch_food_database_v4.dart`, which IMPORTS the catalog file so the two cannot drift. `diet_plan_catalog.dart` therefore imports NOTHING outside `dart:core` (not the generator, not `food_repository.dart`, whose `hive_service.dart` pulls `package:flutter`); a T1 source pin asserts it has no `import` line. The script appends F1442–F1448 BEFORE it asserts every catalog id exists; the earlier source/category deny-list rule (367 rows, which let Wheat Flakes, tempeh, seitan, instant oats, cheese naan and raw lettuce through — round 2 finding 1) is removed. Expected count = the catalog's own unique-id count (151 at revision 4).
**Reader:** `swapAlternatives` (a catalog food whose row says `is_everyday: false` is never offered). **Why keep a tag that equals the catalog:** the founder asked for both mechanisms; the tag lets a later asset update retire a food without a code release, and gives Unit 2+ (search, coach suggestions) a DB-side marker. It is NOT read by the generator (a v3 box must still generate — §3.2).

### 3.6 Processed-food tags + new rows (same script)

- `is_ultra_processed → true` for 66 reviewed ids (list in the script; round 2 added `F1368` nissin noodels, `F1407` protein wafer, `F1381` MTR instant poha, `F1300` / `F1420` packaged breads): every soda/cola/energy/packaged juice incl. `F1268` "Thumbs Up", `F1212`, `F1220`, `F1252`, `F1275`, `F1377`, `F1382`, `F1313`, `F1383`, `F0528`, `F0531`, `F0532`; jams `F1264/F1355/F1421`; `F1253` Mogu; chocolate drinks/milk/spreads/oats; instant noodles `F1331/F1403`; `F1418` packaged parota; `F1364` fruit cake; `F1297` Milky bar; `F1429` Amul kool; deli meats `F0903/F1198/F1199/F1200`; processed cheese slices `F0035/F1274`; mass gainers `F0818/F0842/F0961`; nuggets `F0768`. Produced by a keyword sweep over every non-UPF row (99 hits), then read row by row: fresh juices, home-style shakes, fresh lime soda, coconut water (`F1246/F1280`) and plain carbonated water (`F1411`) deliberately stay false; `F1335` (a cheese) and `F1366` (plain whey powder) stay false — not ultra-processed by NOVA, and neither is in the catalog. Alcohol rows `F0533–F0537` stay as they are (empty `meal_fit` already makes the legacy path skip them; the curated path cannot reach them).
- `is_ultra_processed → false`: `F0708` Roasted Chana, `F0709` Roasted Makhana, `F0710` Plain Makhana (plain roasted; `F0711` Masala Makhana stays true).
- New rows `F1442–F1448` (ids free — max was F1441; names unique), `source: icanbefitter_seed_v4`, `is_indian/is_veg: true`, derived `*_std` computed by the script from per-100 g: Kanda Poha (1 plate 150 g, 250 kcal, breakfast/snack), Vegetable Dalia (1 bowl 200 g, 220, breakfast), Khaman Dhokla (2 pieces 70 g, 112, breakfast/snack), Besan Chilla (1 chilla 70 g, 140, breakfast), Moong Dal Chilla (1 chilla 70 g, 120, breakfast), Vegetable Raita (1 bowl 150 g, 90, vegan false, lunch/dinner), Kachumber Salad (1 bowl 150 g, 40, lunch/dinner). These rows also enter the LEGACY filler pools; verified harmless (§6).
- `F0007` Poha (dry weight, 346 kcal/100 g labelled "1 bowl") stays out of the catalog and is not everyday.
- `seed_service.dart` `_foodLibraryVersion 3 → 4`.

## 4. Tests

**`test/nutrition/curated_diet_plan_test.dart`** (behavioral, real asset loaded like `food_database_tagged_test.dart`, a `_RealDbRepo`):
- **T1 catalog integrity:** every id exists in the asset; non-UPF; `is_everyday == true` and the asset's `is_everyday == true` count equals the catalog size exactly; ≥ 150 unique ids; every row's category ∈ {staples, pulses, protein, dairy, vegetables, fruits, nuts_seeds} OR the id ∈ {F0708, F0710 (packaged), F0303, F0327 (restaurant)}; no `openfoodfacts_india_v2` row; no fats (`F0402–F0405`), no herbs, no sambar/rasam in `side`, no packaged bread; no two ids with identical std macros in one category; every entry has ≥ 1 role and ≥ 1 portion; F0708/F0710 present and non-UPF.
- **T2 template shape + no fallback:** archetype matrix (below) × 20 seeds: each slot holds exactly its required roles plus ≤ 1 optional; every item id ∈ catalog; no `beverages`-category item at all; exactly one `grain`-role item at lunch and at dinner and none elsewhere; no two items in a slot share a key-ingredient token (§3.1 rule); `isAnchor` true exactly on breakfastProtein/mainProtein items; `lastFallbackCount == 0`. **T2-v3** (round 2 finding 8): the same matrix on a v3-shaped repo DERIVED IN THE TEST from the patched asset — drop F1442–F1448, strip `is_everyday`, set `F0522.is_ultra_processed=false` and `F0708/F0710=true` (no `git show` at test time; CI may be a shallow clone) — still `lastFallbackCount == 0`, no item outside the catalog.
- **T3 variety (deterministic):** (a) on the real catalog, per plan no `foodId` repeats and every family cap holds; across 20 seeds of one archetype ≥ 8 distinct lunch mainProtein ids; (b) a FIXTURE catalog of 2 soy + 1 dal entries where only the cap prevents a double-soy day, asserting the soy count ≤ 1 for every seed (so dropping the cap reddens deterministically, not by luck).
- **T4 diet purity:** veg ⇒ every item `is_veg`; vegan ⇒ every item `is_vegan`.
- **T5 macro bands — the floors below are the CONTRACT.** Archetypes are realistic `BmrCalculator` outputs (cut = 2.0 g/kg of goal weight, maintain 1.6, build 1.8). Prototype = Python model of exactly §3.2 (incl. the coherence rule and calorie weight 3), 50 seeds. **The Dart implementation may only RAISE a floor; if a Dart minimum falls below a floor, the fix is K / weights / catalog, never the test.** 50 seeds per archetype.

| Archetype | kcal / protein | Prototype kcal | Prototype protein (min–max, mean) | Floor: protein min | Floor: protein mean |
|---|---|---|---|---|---|
| cut male non-veg | 2000 / 144 | 0.98–1.05 | 0.87–1.06, 0.96 | 0.82 | 0.90 |
| cut male veg | 2000 / 144 | 0.98–1.05 | 0.76–0.92, 0.83 | 0.70 | 0.78 |
| cut female veg | 1500 / 110 | 0.98–1.09 | 0.72–0.89, 0.79 | 0.66 | 0.75 |
| cut female non-veg | 1500 / 110 | 0.98–1.06 | 0.83–1.05, 0.94 | 0.78 | 0.88 |
| cut vegan | 1800 / 130 | 0.99–1.06 | 0.74–0.91, 0.82 | 0.68 | 0.77 |
| recomp non-veg | 2200 / 160 | 0.95–1.03 | 0.90–1.07 (mean ≈0.97) | 0.84 | 0.88 |
| maintain veg | 2400 / 128 | 0.99–1.01 | 0.95–1.05 (mean ≈1.00) | 0.90 | 0.93 |
| maintain vegan | 2200 / 110 | 1.00–1.01 | 0.95–1.14, 1.01 | 0.90 | 0.93 |
| build non-veg | 2700 / 126 | 1.00 | 0.96–1.11 (mean ≈1.03) | 0.90 | 0.93 |
| build veg | 3000 / 150 | 0.99–1.01 | 0.95–1.06 (mean ≈1.00) | 0.90 | 0.93 |
| 1200 floor veg | 1200 / 100 | 0.99–1.12 | 0.56–0.78, 0.66 | 0.50 | 0.62 |
| 1200 floor non-veg | 1200 / 100 | 0.99–1.15 | 0.64–1.03, 0.83 | 0.58 | 0.78 |

  Calories: every plan in [0.92, 1.10] × target for ≥ 1500 kcal and [0.92, 1.18] at 1200 kcal. Fiber: every plan ≥ 0.7 × the 30 g default (21 g) for ≥ 1500 kcal. Prototype minima per archetype (30 seeds): 2000 non-veg 25, 2000 veg 30, 1500 veg 23, 1800 vegan 49, 2700 non-veg 40 g (1200 veg 22 g, not banded). 25 catalog rows (eggs, dairy, meat, fish) carry `fiber_per_100g = 0`. The Dart re-measure reports each archetype's minimum in the diagnose doc; a minimum < 21 g is fixed in the catalog/weights, not by lowering the floor. **Accepted trade-off, reported to the founder with these exact numbers:** vegetarian/vegan CUT plans average ~80 % of the protein target (legacy: 95 %+ via soy/whey in most meals); 1,200-kcal vegetarian plans average ~66 %. Unit 4's whey option closes it.
- **T6 determinism:** same seed ⇒ identical plan (deep equality of ids + multipliers); 20 seeds ⇒ ≥ 10 distinct plans (a plan = its ordered `foodId` list; measured in the prototype: 20/20 distinct).
- **T7 `scaleServingDesc`:** fixed table (the examples in §3.2) + the every-catalog-entry sweep.
- **T8 processed foods (category-wide, not id-keyed):** in the asset, every row whose name matches `/\b(thums|thumbs|cola|pepsi|sprite|limca|maaza|frooti|frroti|sting|red bull|gatorade|glucon|mountain dew|campa|noodles?|noodels|wafer)\b|jam\b/i` is UPF; every non-UPF `openfoodfacts_india_v2` row in `beverages` is one of `F1246, F1280, F1411` (coconut/carbonated water); and no curated plan in the T2 matrix contains a `beverages`-category or UPF row.
- **T9 swap (`swapAlternatives`, pure, real catalog + asset):** (a) fresh-plan item with a role → only same-role catalog entries; (b) the same plan round-tripped through the saved-JSON shape (no role key) → identical alternatives (role derived by `(foodId, slot)`); (c) a legacy saved item not in the catalog (Brie `F1115`, Kimchi `F1063`) → alternatives are catalog entries of the mapped role, never another non-catalog row; (d) never an id already in the plan, never a second soy/paneer/egg… beyond the family cap, never a coherence clash, never diet-failing; (e) a catalog row patched to `is_everyday: false` in the fixture is not offered, and a row with the key ABSENT is offered; (f) never any id from a "never offer" set {F0690 Wheat Flakes, F0375 Tempeh, F0376 Seitan, F0696/F0692 instant oats, F0126 Cheese Naan, F0286 Lettuce, F0921 packaged bread, F0522 Thums Up} across 200 random plan items; (g) the swapped-in item carries the new row's category and the inherited role; (h) no alternative is ever UPF (keeps the protection of the old source pin's `is_ultra_processed` literal).

**`test/nutrition/food_database_tagged_test.dart`** (extended): `is_everyday` is a bool on every row; spot-checks (F0522 / F1268 / F1421 / F1253 UPF true; F0708 / F0710 UPF false; Toor Dal everyday true; Brie / kimchi / ghee everyday false); F1442–F1448 present with `*_std == round1(per100 × g / 100)`.

**`test/contracts/diet_plan_curated_switch_test.dart`** (behavioral, real Hive `configBox` in a temp dir): key absent ⇒ `DietPlanFlags.curatedEnabled` true; `true` ⇒ false; unopened box ⇒ true; and a source pin that `_generateFreshPlan` routes through `DietPlanFlags` (presence-only, stated).

**`test/contracts/diet_plan_saved_loaded_writer_to_reader_test.dart`** (extended): the saved JSON key set of a curated plan item equals the pre-batch key set exactly (no `role`).

**`test/nutrition/diet_plan_quality_constraints_test.dart:421-431`** (the source pin that slices `_swapItem` and asserts it contains `is_ultra_processed` and `passesDiet`): REPOINTED, not loosened — it now slices `swapAlternatives` in `diet_plan_swap.dart` and asserts `passesDiet` and the catalog/`is_everyday` filter are present, and asserts `_swapItem` calls `swapAlternatives` (§4.9 pitfall: moving code breaks source-grep pins).

**Seed bump (NEW food test — the existing `library_seed_v14..v27_upgrade_behavioral_test.dart` files cover EXERCISES and pin `food_library_version` to 9999, so they are unaffected):** `test/contracts/food_library_v4_upgrade_behavioral_test.dart` adapts their `_markSeeded` helper: Hive temp dir, `food_library_version = 3`, foodBox holding v3-shaped rows derived from the asset the same way as T2-v3, run `SeedService.seedIfNeeded()`, assert `F1442` present, `F0522.is_ultra_processed == true`, `F0001.is_everyday == true`, `F0007.is_everyday == false`, version key == 4. Plus a source-regex pin `_foodLibraryVersion = 4` (repo convention for private constants, `exercise_plate_library_data_test.dart:33`).

**Mutations (rule 21), each confirmed applied with `grep -c`, results in the diagnose doc:** M1 family cap removed (T3b); M2 breakfast template takes `grain` (T2); M3 `passesDiet` skipped (T4); M4 swap falls back to a category scan (T9 f); M5 one UPF id reverted in the script (T8 / tagged test); M6 flag polarity inverted (switch test); M7 `scaleServingDesc` returns desc (T7); M8 fallback forced (T2 `lastFallbackCount`); M9 `isAnchor` mapping inverted (T2 asserts `isAnchor` true exactly on protein roles); M10 role not derived on load (T9 b); M11 coherence rule disabled (T2); M12 fiber not populated (T5 fiber); M13 `is_everyday` reader ignored (T9 e). The best-of-K objective weights are covered by T5 only (bands), declared as such.

**Existing tests that must stay green:** all of `test/nutrition/` (41 tests — already re-run GREEN against the patched asset, §6), `diet_plan_saved_loaded_writer_to_reader_test.dart`, `todays_meals_card_suggested_chip_test.dart`, `diet_plan_screen_no_modal_test.dart`, plus the full CI suite.

## 5. Docs / registries (same batch)

- Diagnose doc `docs/diagnoses/2026-11-14-diet-plan-curated-catalog-<id>.md` (FULL template; `related_bugs: d3c7a9`; `recurrence:` cites d3c7a9 + OI-214; `touched_layers_checked`; mutation table).
- `docs/sot_registry.yaml`: recompute every line anchor that moves when `_swapItem` is extracted (`diet_plan_saved_loaded`, `diet_plan_generation_quality`); update the latter's description (it still says "seed version 3"); `diet_plan_generation_quality` writer → curated generator + catalog, `behavioral_test_path: test/nutrition/curated_diet_plan_test.dart`; NEW entry for `is_everyday` (writer: the patch script / asset; reader: `swapAlternatives`; behavioral test T9); `diet_plan_saved_loaded` unchanged but its reader list gains the role-free key-set assertion.
- `lib/features/nutrition/CLAUDE.md`: new pitfall row (catalog/template rule, family caps, catalog replaces `meal_fit`, runtime never filters on tags) + the d3c7a9 row marked "legacy path only"; new tests listed.
- `docs/naming_conventions.md`: `is_everyday`, `disable_curated_diet_plan`, `DietRole`/`DietFamily`.
- OI board: mint the legacy-deletion OI; close OI-214 (move to `closed_issues.md`).
- `docs/plan-reviews/diet-food-quality.md` record. `scripts/patch_food_database_v4.dart` is not a `check_*.dart` gate (rule 24 / gate-wiring do not apply); confirmed by the gate loop.

## 6. Pre-review-2 evidence (run in the worktree, uncommitted)

- `dart run scripts/patch_food_database_v4.dart` → `UPF->true 61, UPF->false 3, appended 7, rows 1444, is_everyday=true 367`; a second run → `appended 0` (idempotent). The JSON diff is only the intended fields (`is_everyday` on every row, the tag flips, the 7 rows).
- `TZ=Asia/Kolkata flutter test test/nutrition/` on the patched asset → **41/41 passed**, incl. the legacy real-DB archetypes `[95%, 115%]` and legacy UPF/veg/vegan invariants. So the new rows and tag flips do not shift the legacy path out of its bands.

## 6b. Re-run required at build

The asset was patched with revision 2's deny-list rule; the build re-runs the revised script (catalog-mirror tag, 66 UPF ids) and re-runs all of `test/nutrition/` before any commit.

## 7. Out of scope (later units, on the task board)

Food-type vocabulary / non-veg default / eggetarian / pescatarian (Unit 2); diet strategy & app-wide targets (Unit 3); supplements & whey (Unit 4); the cloud `food_database` table; food search.

## 8. Risks

- Veg/vegan cut protein at ~75–90 % (accepted; reported; Unit 4).
- 1,200-kcal plans can run to +15 % calories (protein push vs. minimum portions); band [0.92, 1.18] states it.
- Regional mixing (e.g. adai + tofu); accepted for Unit 1.
- A user whose v4 re-seed fails keeps v3 rows: curated still generates (no tag filter at runtime; new ids skipped).

## 9. Review round 1 → disposition

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | catalog ≈130 unique, not 150 | Rebuilt: 152 unique ids, full list in §3.1, duplicates removed. |
| 2 | P1 | protein for common cut targets unbanded | 12 realistic archetypes incl. cuts at 0.072–0.083 g/kcal, measured, banded in T5; trade-off reported to founder. |
| 3 | P1 | kill switch read in the widget | `DietPlanFlags` accessor (§3.3), PlateFlags pattern. |
| 4 | P1 | UPF list incomplete (F1268 "Thumbs Up" etc.) | 61-id list from a keyword sweep read row by row (§3.6); T8 made category-wide. |
| 5 | P2 | role field plumbing + saved key set untested | `DietPlanFoodItem.role` + `_PlanFoodItem.role`, inherit on swap, key-set test. |
| 6 | P2 | stale citations; saved plan is MigratedKey/user box; clearCache | Citations corrected (§2); no-cache generator. |
| 7 | P2 | vegan feasibility thin; families unspecified; fallback untested | Families per entry in §3.1; T2 asserts `lastFallbackCount == 0` across vegan archetypes. |
| 8 | P2 | duplicate dishes defeat uniqueness | Duplicates removed + identical-macro test. |
| 9 | P2 | `scaleServingDesc` on real descriptors | Rule restricted to plain quantity+unit; `N ×` fallback; sweep test over every catalog entry. |
| 10 | P2 | catalog silently overrides `meal_fit` | Stated in §3.1. |
| 11 | P2 | v3 box; custom rows lack `is_everyday`; seed bump test | Runtime never filters on tags (§3.2); custom rows excluded deliberately (§3.4); bump test pattern (§4). |
| 12 | P2 | new rows change legacy path | Ran all 41 nutrition tests on the patched asset: green (§6). |
| 13 | P3 | nits (broccoli source; beverages assertion; row count) | Fixed in text and T2. |
| 14 | P3 | mutation coverage gaps | M8–M10 added; objective weights declared band-only. |
| 15 | P3 | registry/naming/script gates | §5 lists them; `is_everyday` SoT entry added. |

## 10. Review round 2 → disposition

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | `is_everyday` deny-list let Wheat Flakes, tempeh, seitan, instant oats, cheese naan, raw lettuce through; swap top-up offered them | Mechanism removed: swaps are catalog-only (§3.4); `is_everyday` = exact catalog mirror (§3.5); T9 (f) never-offer set. |
| 2 | P2 | saved plan loses role | Role derived by `(foodId, slot)` on load; T9 (b). |
| 3 | P2 | fiber dropped | `fiber` populated; T5 fiber floor; measured 22–108 g. |
| 4 | P2 | floors set from implementation | Floors are the contract, may only be raised; mean floors; 50 seeds (§4 T5). |
| 5 | P2 | T1 vs packaged/restaurant ids | T1 allowed-category set + 4 named exceptions. |
| 6 | P2 | `scaleServingDesc` ugly/wrong | Portion table in §3.1; parenthetical scaled; plural map; countable set; no `×` fallback; bread dropped. |
| 7 | P2 | seed-bump "pattern" claim wrong | New food upgrade test + source-regex pin (§4). |
| 8 | P2 | v3-box claim untested | T2-v3 on the HEAD asset. |
| 9 | P2 | source pin breaks on extraction | Repointed to `swapAlternatives` (§4). |
| 10 | P2 | meal coherence (dal + sambar, palak + palak) | Sambar/rasam removed from `side`; key-ingredient coherence rule; T2 assertion; M11. |
| 11 | P2 | more non-UPF processed rows | +5 ids (66 total); T8 regex extended; F1335/F1366 kept false with reason. |
| 12 | P3 | swap ignores plan context; category kept | Plan-wide id/family/coherence exclusion; new row's category (§3.4, T9 d/g). |
| 13 | P3 | TodaysMealsCard order, forTest, kill-switch procedure, perf, countable set | Item order stated (§3.2); `forTest(repo, catalog)`; the nested CLAUDE.md row states the switch honestly: it is a local `configBox` key with NO remote lever (same as `disable_exercise_plates`, `docs/operations/EXERCISE_MEDIA.md:175`), cleared by `clearAllData()` at sign-out; a fleet-wide rollback is a build that ships `curatedEnabled` hard-wired false (one line in `DietPlanFlags`); perf measured in build; countable set defined. Note: `DietPlanNotifier` maps both snack slots to `snack` last-wins — pre-existing, unchanged by this batch (slot names unchanged). |

## 11. Review round 3 → disposition (round 3 verdict: converged)

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P2 | count is 151 not 153 | Text says 151; tests derive the count from `kDietPlanCatalog`; floor ≥ 150. |
| 2 | P2 | F0212 = F0249 identical macros | F0212 dropped (Avial kept). |
| 3 | P2 | F0019 `100g` does not parse | Grammar accepts a glued unit; no row text changed. |
| 4 | P2 | plural map misfires (`6 eggs whites`), missing words | Pluralise only when original qty ≤ 1; words added; last-word rule for `masala dosa`/`leg piece`; fixed T7 cases. |
| 5 | P2 | dal + Drumstick Sambar (~1.5–2 % of days) | F0255 removed from `sabzi`; F0427 Ber + F0473 Pumpkin Seeds added (count stays 151). |
| 6 | P2 | how tests get the v3 asset | Derived in-test from the patched asset (T2-v3, seed test). |
| 7 | P3 | wrong Brie id | F1115 / F1063. |
| 8 | P3 | slotKey on load, role order, tie-break | `_MealPlan.slotKey` + name map; enum order; catalog-index tie-break; snackbar case stated. |
| 9 | P3 | catalog must be import-free | Stated + T1 source pin; script appends before asserting. |
| 10 | P3 | T5 means, 1200 band, fiber per archetype, legacy fiber wording | Table completed; [0.92, 1.18]; per-archetype fiber minima; wording fixed. |
| 11 | P3 | registry anchors; source-pin UPF protection | §5 recompute + description; T9 (h). |
