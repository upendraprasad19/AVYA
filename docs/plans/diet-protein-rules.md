# Diet protein rules: Non-veg, eggetarian and pescatarian plans must contain their protein (founder, 2026-11-18)

Branch `diet-protein-rules`, revision 4 (review rounds 1 to 3 applied, section 9). Tier M (§4.12.6: more than two product files, nutrition feature). Blast radius
is provisional and is re-computed with `dart run scripts/blast_radius_from_diff.dart <paths>` against the real diff
before the first commit. Execution mode (§4.12.7): INLINE, one worktree, no subagent builders; subagents only review.
This is branch A of the founder's 2026-11-18 batch (task board in the session; branch B, the target changes, waits for
the OI-191 merge because both edit `edit_profile_screen.dart` and `bmr_calculator.dart`).

## 1. Founder decisions (2026-11-18, this session)

1. Non-veg: at least 2 of breakfast, lunch and dinner hold meat or egg. Chicken, fish and mutton only at lunch and
   dinner (breakfast can only hold egg). No weighted pick toward meat, except mutton gets a lower weight.
2. Eggetarian: egg at breakfast AND in one of lunch or dinner; the daily egg cap is 2 items for eggetarians only.
3. Pescatarian: fish at BOTH lunch and dinner; the daily fish cap is 2 items for pescatarians only; never the same
   dish twice in a day; the egg cap stays 1.
4. Egg Bhurji (F0341), Egg Omelette Indian (F0344) and boiled egg (F0021) get the `mainProtein` role (lunch and
   dinner). Today only Anda Masala (F0342) has it.
5. NO whole-egg ceiling (item caps only; the founder was told 2 items at 2x portions can reach 8 eggs and that the
   research has no threshold: AHA 2019 says about one egg a day for healthy adults).
6. Surmai (F0362) is removed from the catalog (generator and swap sheet). The food row stays in the database, so
   "Search any food" still finds it (a free-food pick is the user's own choice; the founder can veto).
7. A measured test over many seeds proves each rule. Veg and Vegan plans stay byte-identical to main.

Out of scope: Veg and Vegan plans; the targets (branch B); any UI or copy change; swaps are NOT forced to keep the
rules (a swap is the user's own choice).

## 2. Measured baseline (300 seeds per profile, real asset, real generator, 2026-11-18)

| Profile | meat/egg B / L / D | other |
|---|---|---|
| Non-veg Cut 2000/144 | 47 / 82 / 74 % | every plan had at least 1 |
| Non-veg Maintain 2400/128 | 52 / 59 / 47 % | lunch and dinner both veg in 16 % |
| Non-veg Build 2700/126 | 48 / 48 / 40 % | lunch and dinner both veg in 28 %, no meat all day 13 % |
| Eggetarian (3 targets) | egg B 49-50 %, L 1-4 %, D 1 % | no egg all day 30-34 % |
| Pescatarian Cut / Maintain / Build | fish L 60/34/32 %, D 38/31/20 % | no fish 2/35/48 %; no fish and no egg 1/13/15 % |

## 3. Writers and readers (named before the change)

| Concept | Writer | Reader |
|---|---|---|
| per-day family caps | `dietFamilyDailyCap`, `dietFamilyLowCarbCapOverride`, `dietFamilyLowCarbPlanCapOverride` (`diet_plan_catalog.dart`) | ONE function `dietFamilyCapFor` (`diet_plan_catalog_rules.dart:11`), called by the generator `curated_diet_plan_generator.dart:370` and the swap `diet_plan_swap.dart:160` (the swap's own `familyOf` at `:132` maps catalog ids only and never consults the retired map, see A3); tests read the raw map at `curated_diet_plan_test.dart:300,730` and `curated_diet_plan_strategy_test.dart:556,635` |
| role pools per slot | `CatalogEntry.roles` (`diet_plan_catalog.dart`); templates `kCuratedSlotTemplates` / Keto / Low carb (`curated_diet_plan_generator.dart:67-133`) | `_sampleDay` `:387-398`; `resolveSwapRole` `diet_plan_swap.dart:65-95` |
| family of a food id | `_familyById` built from the catalog (`diet_plan_catalog.dart:1121` `dietCatalogFamily`) | `savedPlanMatchesFoodType` `diet_plan_provider.dart:67` (judges a plan saved before Unit 2a by its foods; the egg and fish exception of `passesDiet` needs it), `diet_plan_food_search.dart:67` |
| `is_everyday` | `scripts/patch_food_database_v4.dart:117-129` mirrors the catalog into `assets/data/food_database.json` | swap `:155` (retired when false); test T1 |

## 4. Units

**A1. Caps by food type.** `dietFamilyCapFor(family, strategy, {FoodType? foodType})` (`diet_plan_catalog_rules.dart:11`; that file gains
`import 'package:icanbefitter/core/constants/food_types.dart';`, the catalog file must stay import-free; the generator calls
`foodTypeOf(inputs.dietPreference)` ONCE outside the `fits` closure at `:370`, not per candidate; a named optional, so
every existing call stays valid and returns today's value: the only two lib callers pass two positionals). Eggetarian:
egg 2. Pescatarian: fish 2. Checked FIRST, before the `lowCarbPlan` and strategy overrides, for every strategy (neither
override map holds egg or fish today, so the order is a no-op now and matters only for a future overlap). The swap passes `foodTypeOf(dietPreference)` (`dietPreference` is a raw `String` parameter, `:113`; `passesDiet` is
called with it at `:157`; the file gains `import 'package:icanbefitter/core/constants/food_types.dart';`; the screen's call
site passes `_foodType.storageKey`, `diet_plan_screen_swap.dart:58`, the only `swapAlternatives` call site is `:52`); the generator passes `foodTypeOf(inputs.dietPreference)`. Non-veg, Veg and Vegan: unchanged.

**A2. Slot needs.** New pure file `lib/features/nutrition/services/diet_plan_slot_needs.dart`:
`Map<String, Set<DietFamily>> slotNeedsFor(FoodType, Random)` keyed by slot key (`breakfast`, `lunch`, `dinner`); a
slot in the map must fill its protein role (`breakfastProtein` at breakfast, `mainProtein` at lunch and dinner) from
those families. It is called ONCE in `_generate`, from the same `rng` (`curated_diet_plan_generator.dart:304`), BEFORE
the 40-sample loop, and the map is passed to `_sampleDay`. Drawing per sample would let the day score (`_dayScore`,
`:460`) pick the combination and bias it toward B+L+D. Draw order is fixed (below) and each draw is one `rng` call.
- Non-veg: ONE `rng.nextInt(4)` picks the combination (0 = B+L, 1 = B+D, 2 = L+D, 3 = B+L+D); B needs `{egg}`; L and D
  need `{chicken, fish, egg}` plus `mutton` by coin. The lower mutton weight: for each of L and D that is in the
  combination, taken L before D, ONE `rng.nextBool()` decides whether `mutton` is in that need's set (true = in, p 0.5).
  A slot that is not a need picks freely as today, mutton at full weight. The need pool (chicken + fish + mutton + egg
  `mainProtein` entries) is 16 in Balanced (5+5+2+4), 17 in Low carb, 16 in Keto, so mutton falls from 2/16 = 12.5 % of a
  need pool to about 6 %, which is its share of today's full 34-entry lunch pool (about 5.9 %): the coin restores
  today's share inside a need pool, it does not go below it. Draw count: 1 + 1 for B+L or B+D, 1 + 2 for L+D or B+L+D. `slotNeedsFor` takes no strategy, so Keto and Low carb use the
  same draw and the same needs.
- Eggetarian: ONE `rng.nextBool()` picks L or D (true = lunch); B needs `{egg}`, that slot needs `{egg}`.
- Pescatarian: L needs `{fish}`, D needs `{fish}`. No draw.
- Veg, Vegan: an empty map and NO `rng` draw at all, so their random stream, and with it their plans, stay
  byte-identical (the Veg/Vegan golden subset in A4 is the proof; a mutant that draws for Veg turns it red).
`_sampleDay` filters `options` in the REQUIRED loop only (`:386-392`, never the optional loop `:393-399`), keyed by ROLE and
not by slot: a need applies to `breakfastProtein` at breakfast and to `mainProtein` at lunch and dinner, i.e. the condition
is `role == (slotKey == 'breakfast' ? breakfastProtein : mainProtein)` (the Balanced breakfast has two required roles and
filtering `breakfastMain` to egg would empty it and send every sample to the fallback). Every other role builds `options`
as today with the same single `rng.nextInt(options.length)`, so a slot without a need keeps its rng call count. The
existing `fits` already requires the role, `:368`, so no chicken, fish or mutton can reach a breakfast role: they only
have `mainProtein`. A need whose pool
is empty returns null, exactly like an exhausted required role (`:386-388`); `_generate` skips null days
(`:309-317`) and the legacy fallback fires only when all 40 are null (`:318-322`). NO reservation mechanism: a day
where an earlier optional or snack pick (the boiled egg F0021 also holds `snack`) or a free L/D egg consumes the
family cap before a later need is simply discarded, and every SURVIVING day meets its needs by construction. Dead ends:
Non-veg has none (the earlier slot's single `mainProtein` pick removes at most one of chicken, fish and mutton, so the
later need always keeps chicken or fish: both exist only in `mainProtein`, 5 entries each, 6 chicken under Low carb and Keto); pescatarian
has none (fish exists only in `mainProtein`, 5 entries, no coherence tokens, `mainProtein` is the first required role so
`mealTokens` is empty); eggetarian can discard a sample (any ONE other egg pick before the need empties it, since the cap is 2 and
breakfast takes one: a boiled egg at a snack, 1 in 14 snack picks, or a free lunch egg, 4 of about 24 eggetarian
`mainProtein` entries). Hand estimate from pool counts, NOT a measurement: about 7 % of lunch-need samples and 28 % of
dinner-need samples are discarded, about 17 % on the Balanced template and probably 20-25 % under Keto and Low carb; 40
samples all null is about 1e-9 even at a 60 % discard (0.6^40), so the legacy fallback essentially never fires. The build measures
the real rate; the `lastFallbackCount == 0` assertion over every row is the check. Keto egg `mainProtein` has 3 entries, not 4 (Anda Masala F0342 has
14 g carbs, over `kKetoItemCarbCap = 6`): a test pins that F0341 at portion 1.0 stays within the cap. Out of scope:
the legacy generator (the all-null fallback and the `disable_curated_diet_plan` kill switch) and a null seed
(`Random(inputs.seed ?? DateTime.now().day)`, `:304`: tests always pass seeds). NO new kill switch (the board of
delete-the-switch items OI-508/510/511/512 shows the cost of each one; rollback is a revert).

**A3. Catalog.** `F0341`, `F0344`, `F0021` gain `DietRole.mainProtein` (portions unchanged; the boiled egg keeps
`snack`; their `meal_fit: ["breakfast"]` asset values stay, harmless because the catalog replaces `meal_fit` and only the
legacy kill-switch path reads it: one doc line in the nested CLAUDE.md). `F0362` (Surmai) leaves `kDietPlanCatalog`
(180 entries become 179, the Balanced base 151 becomes 150; `is_everyday` true 180 becomes 179); the file gains `kRetiredCatalogFamilies = {'F0362': DietFamily.fish}` ("retired" here means "out of
the catalog", related to but not the same as the asset flag `is_everyday == false` that the swap calls retired at
`diet_plan_swap.dart:155`; the glossary says so). Two readers use it, nothing else: `dietCatalogFamily`
(`diet_plan_catalog.dart:1121`, so a saved plan saved BEFORE Unit 2a, with no `food_type` stamp, that still holds
Surmai loads for a pescatarian: `savedPlanMatchesFoodType` reads `family: dietCatalogFamily(id)` at
`diet_plan_provider.dart:67` only for such unstamped plans, a stamped plan returns at `:53` without judging foods) and the
swap's `familyOf` fallback (`diet_plan_swap.dart:132`: a saved Surmai item then counts toward the fish cap instead of
being invisible to it). The generator reads the catalog list only. Search (`diet_plan_food_search.dart:67`) needs
nothing: `_fishWords` already contains `surmai`. Asset: re-run `dart run scripts/patch_food_database_v4.dart`; the
expected diff is exactly ONE changed line (F0362 `is_everyday` true to false, 180 true becomes 179), checked with
`git diff --stat`. `_foodLibraryVersion` is bumped 7 to 8 (the registry class constraint says a seed version bump is
REQUIRED whenever the asset changes, and v5, v6 and v7 each bumped for an `is_everyday` flip; cost: one re-seed per
install at the next start, the same as those): `seed_service.dart` gets a `v8` comment, and the version pins in
`food_library_v4_upgrade_behavioral_test.dart` (`= 7;` at `:120`, `as int, 7` at `:156,174,192,209`) become 8, as do the test titles at `:118,142,159,177,195` and the doc comments that say 'the v7 asset' at `:71,80,90`, and so does the
MIRROR test at `:212-219` (`_markSeeded(hive, 7)` at `:217`: after the bump a box stored at 7 IS re-seeded, so it would go
red; its title and the header comments that say every older box ends at v7 change too). The simulated old boxes
(`_v4Rows`, `_v5Rows`, `_v6Rows`) derive from the NEW asset, so F0362 is already `false` in every one of them and no
test could see the true-to-false flip: a `_v7Rows()` helper (asset rows with F0362 `is_everyday: true`) and a test 'a v7
box ends at v8 with F0362 false' are added, else the bump is protected only by a source-grep constant (presence only,
rule 21).

**A4. Existing tests.** (T3 variety, `curated_diet_plan_test.dart:~320-327`, asserts at least 8 distinct lunch main
proteins per archetype over 50 seeds. The pescatarian need restricts lunch to the 5 remaining fish dishes, so its bound
is set from the MEASUREMENT (the measured minimum over the 50 seeds minus a margin, at most 5: best-of-40 scoring can favour a
few dishes, so the distinct count could be 3 or 4), with the reason in the test; the eggetarian lunch is a need only on
half the plans, so its bound and the Non-veg ones are re-measured the same way and kept at 8 if they hold. This is a variety bound, not a macro floor.) The raw-cap oracles at `curated_diet_plan_test.dart:300,730` and
`curated_diet_plan_strategy_test.dart:635-636` are the failing oracles and get `foodType`: the `asBalanced` branch becomes
`dietFamilyCapFor(f, DietStrategy.balanced, foodType: foodTypeOf(e.key.pref))` and the other `dietFamilyCapFor(f, st, foodType:
foodTypeOf(e.key.pref))`; at `curated_diet_plan_test.dart:300` the variable is `entry.key.pref`. `:556` is NOT repointed to the plan's strategy: it builds `over` from the BALANCED cap across Low
carb and Keto plans and expects it non-empty (it proves the strategy overrides are used), so it becomes
`dietFamilyCapFor(f, DietStrategy.balanced, foodType: foodTypeOf(e.key.pref))` (the loop variable there is `e`), else the eggetarian egg count of 2 would put egg
in `over` and the test would pass without proving any override (fix the assertion, never loosen a cap). The other two-positional calls
at `curated_diet_plan_strategy_test.dart:501-505,520-540` stay correct. Goldens: G1, G2 and G3 hash all 16 archetypes, so they split into the
Veg/Vegan subset (G2 splits further: its legacy block, `strategy_test.dart:~207-259`, builds `base` from a Non-veg plan and
swaps for `['non-veg','veg','eggetarian']`, so it moves with the generator and the catalog; it becomes G2b, re-baselined on
purpose, and only the archetype loop `:176-205` is the pinned G2a) (CAPTURED ON MAIN 5e6902ce BEFORE ANY CODE CHANGE, veg and vegan archetypes only, same loops and same
hash input as the existing tests: G3 Keto `ed3a64d5f5272129792a076a48d97d19a7657125a8aa2c8d153187a84f03df9a`, G1
`0956dd8eb2667da5cd2bc579e8b66ef010ba4ff28bcce783fa1857178d879b4b`, G2a `66f10c61c62ab0fdccbde093491c588551458c02a9423b40e20f5625382c2a32`
(two runs gave the same three values); they stay byte-identical: the proof that Veg and
Vegan did not move) and the Non-veg / eggetarian / pescatarian subset (re-baselined on purpose; the test header
says why and cites this plan). The T5 / T10 macro floors are a contract: they may only be raised.

## 5. Value-semantics sweep (§4.1.5 point 3)

`dietFamilyDailyCap`, `dietFamilyCapFor`, `dietFamilyLowCarb*`: lib (2 callers), `test/nutrition/curated_diet_plan_test.dart`,
`curated_diet_plan_strategy_test.dart` (A4); none in `supabase/functions`. `F0362` / "Surmai": the catalog,
`assets/data/food_database.json`, `test/nutrition/diet_plan_food_search_test.dart:132-136,419` (Search any food over
food rows: unchanged by design, still finds Surmai), migrations 041 (history), `docs/plans/diet-food-quality.md`
(history). `is_everyday`: swap `:155`, seed service comments, the patch script. `supabase/functions/_shared/tools/nutrition/suggestMeal.ts:116`
has a name-based fish regex containing `surmai`: checked, independent of the catalog and harmless. Bug history: diagnose `83ac8a` (the
curated generator, closes OI-214) and `d3c7a9` (legacy generator quality) are the same concept
(`diet_plan_generation_quality`); this is NOT a recurrence of either (no prior diagnosis on meat presence).

## 6. Tests (each fails without its fix; each mutated once, §4.4 rule 21)

New `test/nutrition/diet_protein_rules_test.dart`, real asset, 300 seeds per row:
- Pure `slotNeedsFor` over 2000 seeds: the EXACT key sets and set contents per food type (Non-veg breakfast `{egg}`,
  L and D `{chicken, fish, egg}` with or without `mutton`; eggetarian `{egg}` at breakfast and at one of L or D;
  pescatarian `{fish}` at L and D; Veg and Vegan the empty map); each of the four Non-veg combinations in 25 % +/- 4 % of
  draws (sd about 1 %, so about 4 sd, and a 40/20/20/20 skew fails); over all L/D needs across the draws the share whose
  set holds mutton is 40-60 %; eggetarian lunch and dinner each 40-60 %; the draw count is exact (the stream after the
  call equals a fresh `Random(seed)` advanced by exactly the planned number of calls: 0 for Veg, Vegan and pescatarian, 2
  or 3 for Non-veg by combination, 1 for eggetarian; the advance uses `nextInt(4)` / `nextBool()` calls, one state word
  each). The draw-order choices (the 0..3 mapping, coin L before D, true = lunch) are pinned by an ORACLE REPLAY for a few
  fixed seeds: replay `Random(seed)` by hand (`nextInt(4)`, then `nextBool()` per L/D need, L first) and compare it with
  `slotNeedsFor`, because the symmetric frequency bands cannot see a swapped mapping. At build, measure once whether the
  first `nextInt(4)` is uniform across consecutive seeds; if it is skewed, derive the test seeds through a mixing step
  (never widen the band).
- Generated plans: Non-veg (Cut, Maintain, Build, Female 1500, each also Low carb and Keto) has at least 2 of
  B / L / D holding meat or egg, no chicken, fish or mutton at breakfast, per-family counts within the type's cap;
  eggetarian has egg at breakfast AND at L or D; pescatarian has fish at L AND D with two different dishes; no plan
  ever holds F0362; `lastFallbackCount` stays 0 for every row (a need can always be met).
- Swap: a hand-built `planFoodIds` (as `strategy_test.dart:470-486`; a natural pescatarian plan has no third main-protein
  item to replace) holding two fish offers no third fish; with one fish it offers fish up to the cap 2; an eggetarian swap
  sees cap 2; Veg unchanged. A saved Surmai item counts toward the fish cap (the `familyOf` fallback).
- Caps in the new tests are INDEPENDENT literals (eggetarian egg 2, pescatarian fish 2, Non-veg egg 1, fish 1, mutton 1),
  never `dietFamilyCapFor` itself (`strategy_test.dart:415-416` warns it is not an oracle).
- Retired ids: `kRetiredCatalogFamilies` and the catalog ids do not overlap; F0362's row stays in the asset with
  `is_everyday: false`; `dietCatalogFamily('F0362')` is fish (the vocabulary test `:359-404` gains the pin).
- Saved plan holding F0362 loads for a pescatarian (the retired-family map) and offers swap alternatives.
- Other tests the build measures and reports (they may move because meat and fish are now forced):
  `diet_plan_shake_reach_test.dart:110-116` (assertion at `:115`) (a Non-veg 2400/150 day may be shaken at most `_seeds ~/ 5`),
  `diet_plan_totals_and_fit_test.dart:~197-246` (the fit-factor sweep over Non-veg, eggetarian and pescatarian under Low
  carb and Keto), `diet_plan_swap_only_test.dart`. T5 floors are raise-only; the T10 rows may use the recorded exception
  (a change to a strategy's random stream may re-baseline that strategy's T10 rows, each lowered row at most 0.05 and
  written in the test, `sot_registry.yaml` class constraints).
- Macro floors: the existing T5 / T10 files must stay green UNCHANGED unless the line above applies; the new file also prints the measured protein
  and calorie means per row for the diagnose-style note in section 8.
- Mutants, each applied and confirmed with `grep -c`: M1 drop the eggetarian cap override; M2 pescatarian need pool
  unrestricted; M3 the Non-veg combination draw yields a single-slot combination (the exact key-set assertions redden); M4 `slotNeedsFor` draws one `rng` value for Veg (the Veg golden reddens); M5 swap ignores `foodType`; M6 keep F0362 in
  the catalog; M7a empty `kRetiredCatalogFamilies` (`= {}`; the `dietCatalogFamily('F0362')` pin and the saved-plan-loads test redden; deleting it would be a compile error, not a proof); M7b remove only the swap's `?? kRetiredCatalogFamilies[id]` fallback (the saved-Surmai-counts-toward-the-fish-cap test reddens); M7c the version stays 7 (the `_v7Rows` test reddens). The food-search tests `:132-136,419` do NOT pin the map (`searchFamilyOf` falls back to the name regex, where 'surmai' matches `_fishWords`), so only the new pins protect it; M8' the eggetarian breakfast need also admits `dairy` (observable: `dairy` holds `breakfastProtein`; a chicken-at-breakfast mutant would be equivalent because `fits` already excludes it). M9 drop `fish` or `egg` from the Non-veg L/D set; M10 the mutton coin always true; M11 the combination draw is `nextInt(3)`. A compile error is not a proof.

## 7. Registry, docs, process

`docs/sot_registry.yaml` `diet_plan_generation_quality`: the stale description text and class constraints are rewritten (the lines are listed once, below); the new test is a SIBLING key `behavioral_test_path_protein: test/nutrition/diet_protein_rules_test.dart` (a
second plain `behavioral_test_path:` would be a duplicate key; `check_sot_behavioral_test_paths.dart` resolves the
suffixed keys on disk); a writer entry for `diet_plan_slot_needs.dart` (method `slotNeedsFor`), `dietFamilyCapFor` stays
the reader; `lib/features/nutrition/CLAUDE.md` row 59: '151' becomes 150, the family-caps sentence names the food-type caps, 'Balanced
output is byte-identical to main (goldens G1/G2)' becomes true for Veg and Vegan only, the `meal_fit` doc line, plus the
tests list;
Stale spots found by review rounds 2 and 3, all edited: `sot_registry.yaml:1540` ('151 everyday'), `:1547` (the family-cap
sentence), `:1570` ('byte-identical to main 21db03c7 (golden SHAs G1/G2)'), `:1587` (catalog writer methods), `:1599`
(seed writer versions), the `dietFamilyCapFor` reader note near `:1611-1620` ('Cap: Low carb plan override, then the Low
carb / Keto override, then the daily cap': the food-type cap now comes first), `:1643` (class constraints G1/G2), `:1557`
('version 6 ... is current', now 8) and `:1580`, the `food_is_everyday` writer at `:1995` ('putAll at food_library_version 7'
becomes 8 and names F0362 true to false), the `seed_service.dart` writer's version list (v4 to v7 gains v8), the
`diet_plan_catalog.dart` writer's method list (adds `kRetiredCatalogFamilies`), `docs/naming_conventions.md:677`
(`_foodLibraryVersion` 7 becomes 8), nested `lib/features/nutrition/CLAUDE.md` row 59 (`_foodLibraryVersion` 7 becomes 8
in addition to the edits above). The parity gate verifies methods only for entries with a `line_range` (these have none) and
no gate greps '151'/'150'; row 59 is not in the context-budget tracked set. `docs/naming_conventions.md`: `slot needs` (no clash found) and `retired catalog family` with its relation to `is_everyday`. No schema, migration, Edge Function, cloud column, sync or UI change; the
asset is bundled. Commit type `feat(nutrition)` (a product rule, not a regression), so no diagnose doc is required by
rule 22; the measured baseline in section 2 is the evidence. Gate loop before each review round with a draft diff
(§4.12.8), `/code-review` B-pass before the merge, merge only on the founder's word via `land_pr.sh`. The merge gate needs `docs/plan-reviews/diet-protein-rules.md`
(`review_rounds: >= 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted` once the B-pass is done;
`check_plan_review_record_exists.dart`) if the real blast radius is `account` or above; the record is written with this plan.

## 8. Risks

- A need whose pool empties under Keto or Low carb (the Keto per-item carb cap filters candidates): covered by the
  `lastFallbackCount == 0` assertion over every strategy row.
- The macro floors: forcing meat or fish should raise protein for these types; if a floor drops, fix the catalog or the
  sampler weights, never the floor.
- `diet-grams-toggle` (OI-517) is clean today (no diff, HEAD 5e6902ce); if it or another diet unit also bumps
  `_foodLibraryVersion`, the two conflict on `seed_service.dart:228`: whoever lands second renumbers. `oi191-goal-target`
  has 16 modified files and touches none of this plan's files (catalog, swap, rules, generator, seed service, asset,
  registry, nested nutrition CLAUDE.md, tests).
- More tests that run the real generator and are measured, not edited unless they move: `diet_plan_swap_only_test`
  (per-role alternative-count statistics, `:~100-147`) and `diet_plan_supplements_screen_test.dart:222,522` (real
  pescatarian plans; no assertion on plan contents found).

## 9. Review dispositions

Round 1: two context-blind Sonnet reviewers on revision 1 (A: generator mechanism; B: catalog, swap, tests). Every
finding applied; each verified against the code by the coordinator before applying (B3, the G2 legacy block, was also
re-measured: the first G2 hash included it and was wrong).

| Finding | Disposition | Landed in |
|---|---|---|
| A1 reservation undefined for set needs | the reservation mechanism is REMOVED (A2); Non-veg has no dead end by the family count | A2 |
| A2 reservation not needed, M4 unobservable | same removal; M4 replaced by the Veg-draw mutant | A2, section 6 |
| A3 mutton thinning vs signature | one `rng.nextBool()` per L/D need inside `slotNeedsFor`; free slots unaffected | A2 |
| A4 when `slotNeedsFor` is called | once in `_generate` before the loop; Veg, Vegan, pescatarian draw nothing | A2 |
| A5 M8 equivalent | replaced by the eggetarian-breakfast-admits-dairy mutant | section 6 |
| A6 Keto egg pool is 3 | stated; F0341 carb pin added | A2, section 6 |
| A7 `strategy_test.dart:636` missing | added with the right strategy per branch | A4 |
| A8-A9 wording, line cites | fixed (`:11`, `:318-322`) | A1, A2 |
| A10 legacy path and null seed out of scope | stated | A2 |
| A11 pescatarian numbers | 5 fish entries named | A2, A4 |
| A12 combination frequencies | pure-function frequency floors | section 6 |
| B1 T3 lunch variety breaks | pescatarian bound `min(8, 5)`, eggetarian re-measured | A4 |
| B2 `:556` oracle wrong | repointed to Balanced + foodType, not the plan's strategy | A4 |
| B3 G2 legacy block moves | G2 split into G2a (pinned, recaptured) and G2b (re-baselined) | A4 |
| B4 seed bump required | bump 7 to 8 with the pins | A3 |
| B5 retired map narrow, swap `familyOf` missed | swap fallback added; non-overlap and row pins | A3, section 6 |
| B6 swap wiring | import, `:157`, call site | A1 |
| B7 weak test design | independent literal caps, hand-built `planFoodIds` | section 6 |
| B8 other tests that may go red | measured and reported in the build | section 6 |
| B9 registry and docs | sibling key, writer entry, stale text, row 59 edits | section 7 |
| B10 stale cites | fixed | section 3 |
| B11 patch script result | exactly one changed line, `git diff --stat` | A3 |

Round 2: two fresh context-blind Sonnet reviewers on revision 2 (1: mechanism; 2: catalog, seed, goldens, registry).
Reviewer 1 found no P0 or P1 (8 P2); reviewer 2 found one P1 (a missed test pin) and 8 P2. No design finding in either
round-2 report. Each finding was verified against the code before applying (the MIRROR pin, the 181 constructor lines,
the stale registry lines and the call-site lines were re-read).

| Finding | Disposition | Landed in |
|---|---|---|
| R1-1 "at least 3 of 4 families" false in the worst case | reworded: the earlier pick removes at most one of chicken, fish, mutton | A2 |
| R1-2 mutton test unit | share over all L/D needs, 40-60 % | section 6 |
| R1-3 draw order | mapping 0..3, coins L then D, true = lunch, exact draw counts, pescatarian stream test | A2, section 6 |
| R1-4 filter keyed by role | `role == (breakfast ? breakfastProtein : mainProtein)`, required loop only | A2 |
| R1-5 discard estimate | hand estimate stated (about 17 % Balanced), fallback essentially never fires, build measures it | A2 |
| R1-6 pure tests too weak | exact set contents, 25 % +/- 4 % bands, mutants M9 to M11 | section 6 |
| R1-7 mutton label | need pool 16 / 17 / 16, restores today's share | A2 |
| R1-8 cite `:12` | `:11` | section 3 |
| R2-1 MIRROR pin and flip test | `:217` and a `_v7Rows` test added | A3 |
| R2-2 "150 entries" | 180 to 179, Balanced base 151 to 150 | A3 |
| R2-3 stale registry and docs spots | listed and edited | section 7 |
| R2-4 import in the rules file | named; `foodTypeOf` once outside the closure | A1 |
| R2-5 M7 compile error | M7a, M7b, M7c | section 6 |
| R2-6 T3 bound from measurement | measured minimum minus a margin | A4 |
| R2-7 cites | `:58` / `:52`, `~:207-259`, `e.key.pref` | A1, A4 |
| R2-8 suggestMeal.ts | listed as checked | section 5 |
| R2-9 risks and extra tests | added | section 8 |

Round 3: one fresh context-blind Sonnet reviewer on revision 3, checking only the text revision 3 changed and what
those edits could have introduced. Verdict CONVERGED: no P0, no P1, 8 P2 (wording and pin completeness), all applied in
revision 4 (header, registry cites, three more stale registry lines, M3 wording, an oracle replay for the draw-order
choices, a seed-uniformity measurement at build, the 1e-9 figure, the shake-reach and oracle-variable cites, the test
titles and comments in the upgrade test, the plan-review record line). The reviewer also confirmed against the code: no
import cycle (`food_types.dart` has no imports), the role-keyed filter is right for all three templates, the pool counts
(need pool 16 / 17 / 16, eggetarian `mainProtein` 24), 180 to 179 entries and one changed asset line, a `_v7Rows()` test is
feasible, and every mutant is observable (M3 needed rewording).

