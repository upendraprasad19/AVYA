---
bug_id: 83ac8a
date: 2026-11-14
batch: diet-food-quality
status: fixed
blast_radius: account
symptom: >-
  The generated Diet Plan (web, founder screenshot 2026-11-14 13:45) put Thums
  Up in the Evening Snack, mapro mixed fruit jam (100 g) and a branded Thai
  "Mogu litchi" jelly drink in breakfast/snack, Wheat Flakes in lunch, Caesar
  salad and raw ash gourd at dinner. Ten seeded plans from the same generator
  on the real 1,437-row food database showed the pattern is structural: soy in
  9/10 plans (three soy rows in one day in 3/10), roasted peanuts as the
  evening snack 8/10, Greek yogurt mid-morning 8/10, zero dal/rajma/egg/paneer
  in all ten, imported/branded rows (Brie, Camembert, kimchi, shiitake, hemp
  milk, Yoga Bar oats, Chobani, Fortune mustard oil), two or three staples in
  one meal, oils/ghee/butter as line items and a pickle spear or one garlic
  clove as the "vegetable". The swap sheet offered the first five rows of the
  item's whole DB category, so it re-introduced the same rows.
concept: diet_plan_generation_quality
recurrence: >-
  RECURRENCE of d3c7a9 (2026-09-17, same concept). d3c7a9 added constraints
  (quotas, caps, day uniqueness by id, a UPF tag) ON TOP of a generator whose
  filler pool is a whole DB category, and deferred the structural fix as
  OI-214 ("curated Indian meal-template layer"). The constraints held for
  what they named, but (1) day uniqueness is per id, so three different soy
  ids pass; (2) the UPF tag is a keyword heuristic that missed Thums Up,
  "Thumbs Up", colas, packaged juices, jams and Mogu; (3) whole-category pools
  admit any imported/branded/oil row the tags do not catch. Known-good fix
  applied: the template/allowlist architecture OI-214 described (mainstream
  planners select from a curated library, not ingredient rows).
related_bugs: [d3c7a9]
sot_registry_entry: diet_plan_generation_quality (writer moved to the curated generator + catalog; new entry is_everyday)
writers:
  - { file: lib/features/nutrition/services/curated_diet_plan_generator.dart, method: CuratedDietPlanGenerator.generate (template sampling + portion sizing + best of 40), line: 209 }
  - { file: lib/features/nutrition/services/diet_plan_catalog.dart, method: kDietPlanCatalog (151 curated foods, roles, families, portions), line: 109 }
  - { file: lib/features/nutrition/services/diet_plan_swap.dart, method: swapAlternatives (catalog-only swap), line: 78 }
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method: _generateFreshPlan (DietPlanFlags routing; regenerate seed), line: 78 }
  - { file: scripts/patch_food_database_v4.dart, method: main (66 UPF re-tags, 3 un-tags, 7 new rows, is_everyday = catalog mirror), line: 61 }
  - { file: lib/core/services/seed_service.dart, method: _foodLibraryVersion 3 -> 4, line: 210 }
readers:
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: _servicePlanToScreenPlan / _savePlan / _loadSavedPlan (saved JSON key set unchanged), line: 115 }
  - { file: lib/features/nutrition/providers/diet_plan_provider.dart, method_or_widget: DietPlanNotifier.build (TodaysMealsCard hints; item order puts the protein/main first), line: 56 }
  - { file: lib/features/nutrition/services/diet_plan_swap.dart, method_or_widget: swapAlternatives reads is_everyday (retire flag) + is_ultra_processed, line: 123 }
hive_key_prefix: saved_diet_plan
hive_key_formula: MigratedKey('saved_diet_plan') in userBox (unchanged); foodBox rows re-seeded at food_library_version 4 (putAll overwrite + add)
sync_methods: [syncSavedDietPlan]
restore_methods: [_restoreSavedDietPlan]
cloud_table: saved_diet_plans
cloud_columns: [plan_json]
contract_test_path: test/nutrition/curated_diet_plan_test.dart
ist_handling:
  - { file: lib/features/nutrition/services/curated_diet_plan_generator.dart, line: 373, fn: dietPlanSeed (device-local calendar day; a seed, not a date key — unchanged semantics from the pre-batch day hashCode) }
provider_invalidations: [dietPlanProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "generated item whose foodId is not in kDietPlanCatalog", absent_after_fix: true }
  - { pattern: "is_ultra_processed row in a curated plan or swap list", absent_after_fix: true }
  - { pattern: "more than one soy / paneer / egg / chicken / fish / mutton item in a day", absent_after_fix: true }
  - { pattern: "two grain-role items in one meal, or a grain at breakfast/snacks", absent_after_fix: true }
  - { pattern: "two items in one meal sharing a key ingredient (palak paneer + aloo palak)", absent_after_fix: true }
  - { pattern: "swap alternative read from a whole DB category", absent_after_fix: true }
  - { pattern: "role key in the saved plan JSON", absent_after_fix: true }
  - { pattern: "Hive read inside diet_plan_screen.dart (kill switch)", absent_after_fix: true }
proposed_fix: >-
  OI-214's template layer. A hand-curated catalog of 151 everyday Indian foods
  (roles, day-capped families, allowed portions; no macros — numbers come from
  the food row). A template per slot (breakfast = main + protein (+fruit);
  lunch = protein + one grain + sabzi + side; dinner = protein + one grain +
  sabzi (+side); snacks = fruit/snack), a key-ingredient coherence rule, day
  family caps (soy/paneer/egg/chicken/fish/mutton/nut 1, dal/dairy 2),
  exhaustive portion sizing per slot, best of 40 sampled days scored on
  calories, a protein band and a fiber floor. Catalog-only swap sheet with
  role resolution for saved plans. Asset v4: 66 processed rows re-tagged UPF,
  plain roasted chana/makhana un-tagged, seven everyday rows added (Kanda
  Poha, Vegetable Dalia, Khaman Dhokla, Besan/Moong Dal Chilla, Vegetable
  Raita, Kachumber Salad), is_everyday = exact catalog mirror (the swap
  sheet's retire flag). Local kill switch DietPlanFlags (legacy path kept;
  its deletion tracked on the OI board). Regenerate now produces a new plan
  (the seed moved per tap; it reused the day's seed before).

touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter analyze (whole project) clean of warnings; test/nutrition/ 71 tests green incl. 30 new curated tests; mutation table below" }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "foodBox re-seeded at food_library_version 4 — behavioral test test/contracts/food_library_v4_upgrade_behavioral_test.dart drives the real SeedService.seedIfNeeded from a v3 box; saved_diet_plan key and JSON key set unchanged (exact key-set test)" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no cloud write; saved_diet_plans blob shape unchanged" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "generation is local Dart; zero API cost" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "food_database.json is a bundled asset, not a Storage object" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service call" }
  - { tier: 12_client_server_contract, status: verified, evidence: "saved plan JSON writer key set pinned exactly (diet_plan_saved_loaded_writer_to_reader_test.dart); TodaysMealsCard / restore / sync untouched; the cloud food_database table is not read by generation or swap" }
impact_analysis: >-
  Account tier: the diet plan every user sees, its swap sheet, the saved plan
  (unchanged shape) and the seeded food database (v4 re-seed on next launch,
  same putAll path as v3). No payment, sync, auth, AI or schema surface. The
  generator is local and synchronous like the legacy one. Behavior change
  users will notice: different foods (everyday Indian dishes), one grain per
  meal, Regenerate now changes the plan, and lower protein on vegetarian cut
  plans (~80 % of target, stated to the founder). Rollback: the local kill
  switch (no remote lever) or a build with curatedEnabled false.
regression_test_planned:
  - test/nutrition/curated_diet_plan_test.dart (T1-T9, 12 archetypes x 50 seeds on the real asset)
  - test/contracts/food_library_v4_upgrade_behavioral_test.dart
  - test/contracts/diet_plan_curated_switch_test.dart
  - test/contracts/diet_plan_saved_loaded_writer_to_reader_test.dart (exact saved key set)
  - test/nutrition/food_database_tagged_test.dart (v4 spot-checks + new rows)
  - test/nutrition/diet_plan_quality_constraints_test.dart (swap source pin repointed, not loosened)
---

# Diet plan: curated catalog + meal templates (83ac8a)

## What the founder saw

Thums Up in the Evening Snack; jam and a branded jelly drink as "fruit"; Wheat
Flakes at lunch; a lunch of soybean + parsnip + thalipeeth + wheat flakes +
aloo palak (888 kcal). The ask: plans that are consistent, made of foods
people can buy, and not processed.

## Root cause

The legacy generator's slot definitions (`diet_plan_generator.dart:258-305`)
name filler CATEGORIES, so every row of a category — 1,437 rows from four
sources incl. Open Food Facts brands and a Western list — is a candidate.
Quality depends on tags that a keyword heuristic wrote, and on per-id
uniqueness that cannot see "soy". d3c7a9 fixed symptoms on that architecture;
this batch replaces the pool.

## Measured result (Dart, real asset, 50 seeds per archetype)

| Archetype | kcal / protein | kcal ratio | protein ratio (min–max, mean) | fiber min |
|---|---|---|---|---|
| cut male non-veg | 2000 / 144 | 0.98–1.04 | 0.90–1.11, 0.97 | 24 g |
| cut male veg | 2000 / 144 | 0.98–1.05 | 0.74–0.92, 0.83 | 34 g |
| cut female veg | 1500 / 110 | 0.97–1.09 | 0.69–0.93, 0.79 | 26 g |
| cut female non-veg | 1500 / 110 | 0.96–1.07 | 0.85–1.09, 0.95 | 24 g |
| cut vegan | 1800 / 130 | 0.98–1.06 | 0.77–0.96, 0.83 | 50 g |
| recomp non-veg | 2200 / 160 | 0.97–1.04 | 0.88–1.19, 0.97 | 25 g |
| maintain veg | 2400 / 128 | 0.99–1.01 | 0.93–1.05, 0.99 | 48 g |
| maintain vegan | 2200 / 110 | 0.99–1.01 | 0.95–1.13, 1.01 | 61 g |
| build non-veg | 2700 / 126 | 1.00 | 0.95–1.15, 1.04 | 36 g |
| build veg | 3000 / 150 | 0.99–1.02 | 0.93–1.10, 0.99 | 55 g |
| 1200 floor veg | 1200 / 100 | 0.98–1.16 | 0.57–0.82, 0.68 | 25 g |
| 1200 floor non-veg | 1200 / 100 | 0.97–1.17 | 0.71–1.02, 0.84 | 23 g |

Accepted trade-off (founder told these numbers): vegetarian/vegan CUT plans
average ~80 % of the protein target (the legacy generator reached 95 %+ by
putting soy or whey in most meals); 1,200-kcal vegetarian plans ~68 %. Unit 4
(supplements: whey) closes it. Soy and paneer stay capped at once a day —
measured: raising both to 2 moved veg-cut protein only +0.02–0.04.

The first Dart run found a non-veg plan at 17 g fiber (meat + white rice +
a light sabzi); a fiber term (aim 80 % of the profile target) was added to the
day score instead of lowering the test floor (the plan's contract rule).

## Mutation proof (rule 21)

Each guard was broken in turn by a script that asserted the edit APPLIED
(anchor matched exactly once, the replacement present after writing), ran the
listed test, restored the file and asserted it byte-equal to the original. No
result below is a compile error (M8's first form did not compile; it was
rewritten so it does, then re-run).

| # | Guard broken | Test run | Failing tests |
|---|---|---|---|
| M1 | family cap (`>= cap` → `>= cap + 99`) | curated T3 | 2 (caps + the soy fixture) |
| M2 | breakfast template takes `grain` | curated T2 | 1 |
| M3 | `passesDiet` skipped in the generator | curated T4 | 1 |
| M4 | swap ignores the role | curated T9 | 1 |
| M5 | Thums Up `is_ultra_processed` reverted in the asset | curated T8 / tagged | 1 / 1 |
| M6 | kill-switch polarity inverted | switch test | 3 |
| M7 | `scaleServingDesc` returns its input | curated T7 | 1 |
| M8 | legacy fallback forced | curated T2 | 3 |
| M9 | `isAnchor` mapping inverted | curated T2 | 1 |
| M10 | swap role not derived from the catalog on load | curated T9 | 2 |
| M11 | coherence rule off | curated T2 | 1 |
| M12 | `fiber` not populated | curated T5 | 1 |
| M13 | swap ignores `is_everyday: false` | curated T9 | 1 |
| M14 | fiber term removed from the day score | curated T5 | 1 |
| M15 | `_foodLibraryVersion` back to 3 | v4 upgrade test | 2 |
| M16 | swap UPF filter removed | repointed source pin | 1 |

Declared limits: the best-of-K objective weights are covered by the T5 bands
only; the screen's kill-switch routing is a presence pin (the screen is not
pumped).

## Not done here (owned by later units on the founder's task board)

Food-type vocabulary / non-veg default / eggetarian / pescatarian (Unit 2),
diet strategy (Unit 3), supplements (Unit 4). The legacy generator and the
kill switch are deleted after the founder's device check (OI minted in this
batch).
