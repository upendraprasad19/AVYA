---
bug_id: d3c7a9
date: 2026-09-17
batch: diet-plan-meal-quality
status: fixed
blast_radius: account
symptom: >-
  The generated diet plan shown to Upendra (2026-09-17 PDF export) contained
  structurally absurd meals: breakfast = idli + red rice + basmati rice + whey
  (three starch servings, no dairy/fruit), lunch = tandoori chicken + packaged
  pasta masala + roti + Special K cereal, dinner = fish curry + 40g Pringles
  (541 kcal, 69% of the slot), Greek Yogurt twice in one day, ZERO vegetables
  or fruit all day, fiber ~12g against a 30g profile target, fat +23% over
  target. Macro/protein math passed (2197 kcal / 152g protein, in the by-design
  95-115% band) — the algorithm optimized its objective function correctly and
  the plan was still unedible.
concept: diet_plan_generation_quality
recurrence: >-
  First reported instance of this shape (the generator is 2026-era, anchor-
  protein-per-meal algorithm from APK Test #3 fix c7288d3 — that fix solved
  protein band misses and over-delivery, and introduced this composition
  failure class as a side effect). Root causes are structural in
  diet_plan_generator.dart, not drift: (1) Pass 2 filler loop has per-MEAL
  avoidIds only — same-category stacking (red rice then basmati) is legal;
  (2) filler category order is fixed with 'staples' first and the loop
  terminates when remainingCals <= 80, so vegetables (30-60 kcal servings)
  are STRUCTURALLY unreachable, not randomly missed; (3) no
  ultra-processed filter or serving-size cap exists — Pringles is just a
  "staples"-tagged row; (4) no day-level uniqueness — Greek Yogurt sits in
  BOTH the breakfast and snack anchor pools (the two snack slots share
  _snackAnchorNames); (5) the profile's fiber target is never read by the
  generator. Industry context (researched 2026-09-17, filed OI-214 for the
  template-layer follow-up): mainstream planners (PlateJoy, Eat This Much)
  select from curated RECIPE libraries rather than composing from ingredient
  rows; academic meal planning adds acceptability constraints (food-group
  quotas, variety) as HARD constraints; the Stigler LP diet is the canonical
  caution that pure nutrient math produces unedible output.
related_bugs: none
sot_registry_entry: diet_plan_saved_loaded (extended — writer unchanged, generation-time constraints added; registry update in this batch)
writers:
  - { file: lib/features/nutrition/services/diet_plan_generator.dart, method: generate (Pass 0 quotas + Pass 1 anchor uniqueness + Pass 2 caps/filters + Pass 5 fiber floor added; passes 1-4 restructured), line: 269 }
  - { file: lib/core/services/seed_service.dart, method: _foodLibraryVersion 2->3 (untagged v2 boxes would silently no-op every new filter — missing field reads as UPF=false/matches-all), line: 105 }
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method: _swapItem (UPF + diet-preference filter on alternatives — a manual tap could re-introduce the defect post-generation), line: 108 }
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method: _generateFreshPlan (fiberTarget input wired from profile['fiber_grams']), line: 74 }
readers:
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: _servicePlanToScreenPlan/_savePlan/_loadSavedPlan (plan JSON schema UNCHANGED — saved-plan contract preserved), line: 89 }
  - { file: lib/features/nutrition/widgets/todays_meals_card.dart, method_or_widget: build (reads saved plan via dietPlanProvider — schema-unchanged), line: 66 }
  - { file: lib/features/nutrition/providers/diet_plan_provider.dart, method_or_widget: DietPlanNotifier.build, line: 54 }
hive_key_prefix: saved_diet_plan
hive_key_formula: MigratedKey('saved_diet_plan') in userBox (unchanged; foodBox rows re-seeded on v3 bump — putAll overwrites/adds, never deletes)
sync_methods: [syncSavedDietPlan]
restore_methods: [_restoreSavedDietPlan]
cloud_table: saved_diet_plans
cloud_columns: [plan_json]
contract_test_path: test/nutrition/diet_plan_quality_constraints_test.dart (10 behavioral guards; existing test/nutrition/diet_plan_generator_test.dart archetypes all still green)
ist_handling:
  - { file: lib/features/nutrition/services/diet_plan_generator.dart, line: 271, fn: generate (day-seed is DateTime.now() LOCAL — pre-existing, unchanged, out of scope) }
provider_invalidations: [dietPlanProvider]
telemetry_op_types:
  success: []
  failure: [nutrition_diet_plan_pdf_export_failed]
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "is_ultra_processed row selected as anchor/filler/swap candidate", absent_after_fix: true }
  - { pattern: "same foodId twice in one day among anchors+quota items", absent_after_fix: true }
  - { pattern: "more than 1 staple per slot (unless >20% under calorie target)", absent_after_fix: true }
  - { pattern: "3-way pulses stacking (rajma+chana+masoor) in one slot", absent_after_fix: true }
  - { pattern: "lunch/dinner without a vegetables item (1431-row DB)", absent_after_fix: true }
proposed_fix: >-
  Compose-then-fill constraint layer on the existing anchor-protein algorithm
  (Option B; the meal-template architecture is OI-214, deferred). Pass 0 group
  quotas: mandatory vegetables item in lunch/dinner, dairy-or-fruit in
  breakfast, placed BEFORE calorie filling with an isQuotaLocked flag so
  Pass 3/4 recovery cannot swap them out. Per-category filler caps with
  re-entrant yield exceptions: staples <=1 (+2nd while slot >20% under
  CALORIE target), pulses <=1 (+2nd while >20% under PROTEIN target),
  vegetables <=2. Day-level food uniqueness: HARD in Pass 1 anchors
  (optional snack anchors SKIP rather than repeat — an exhausted pool yields
  no anchor; required slots repeat only as last resort) and Pass 0/2; SOFT
  prefer-unused in Pass 3/4 recovery swaps (protein correctness outranks
  variety; the vegan archetype's recovery needs cross-meal freedom). UPF
  exclusion: is_ultra_processed rows never generated or swap-candidate,
  category-independent (Pringles/Maggi/Special K live in 'staples'), missing
  field => false. nuts_seeds per-serving <=300 kcal cap (per-SERVING, not
  kcal/g — a kcal/g cap bans almonds/peanuts; per-serving keeps 81/170/94
  kcal servings and excludes 372 kcal jar rows) and it survives stage-4
  relaxation. Recovery sizing rewritten: gradual convergence (smallest unused
  higher-protein candidate per swap, bounded loop) with a 1.5x-slot-target
  headroom constraint — replaces the old highest-protein-first grab that
  swapped a 90g Protein Shake into an 8g gap and handed Pass 4 an
  untrimmable problem. Pass 4 trim re-floored in three tiers: lowest-protein
  unused candidate landing >= softFloor(105%) -> any candidate landing >=
  dailyFloor(95%) -> highest-protein overall (smallest cut). Pass 5 fiber
  floor: if daily fiber < 70% of the profile fiber target, swap the
  lowest-fiber staple for a whole-grain alternative in the +-20% calorie
  band, bounded 6 tries, no-op on empty candidates. _swapItem alternatives
  filtered by UPF + diet preference. Generator anchor pools gain Soy Chunks
  (cooked) / Soya Chaap / Tofu (Firm) (real DB F0373/F0374/F1014) so the
  vegan archetype survives day-uniqueness. Seed version 2->3 ships the tags
  to existing installs. founder HTML review of heuristic tags
  (scripts/generate_food_tag_review.dart) gates the tagged asset; pinned
  spot-checks follow in the asset commit.

touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter test test/nutrition/diet_plan_quality_constraints_test.dart + test/nutrition/diet_plan_generator_test.dart -> 15/15 passed. Mutation-proven with SEVEN mutations (results in the Mutation-proof section below); mutations M1 and M6 initially FAILED to redden their tests — vacuous-test blind spots found BY mutation and fixed (details below), then re-proven red." }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "foodBox rows gain meal_fit + is_ultra_processed on the v3 re-seed (seed_service putAll overwrites/adds, never deletes — custom foods and saved-meal snapshots survive). saved_diet_plan key/schema unchanged. foodBox read-only at generation. Version bump pinned in this doc; behavioral version test rides the asset commit's test file (asset not yet swapped — founder HTML review in progress)." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: verified, evidence: "live query: public.saved_diet_plans = 0 rows (user never saved a plan); no cloud write in this batch" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "generation is local Dart; zero API cost by design" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "food_database.json is a bundled asset, not a Storage object" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service call" }
  - { tier: 12_client_server_contract, status: verified, evidence: "saved-plan JSON writer keys (diet_plan_screen.dart _savePlan) pinned unchanged by source-presence test; loader (_loadSavedPlan) and TodaysMealsCard reader contract unchanged; syncSavedDietPlan/_restoreSavedDietPlan untouched" }
mutation_proof:
  method: >-
    Each guard was neutered IN TURN in lib/features/nutrition/services/
    diet_plan_generator.dart, the targeted test re-run, the mutation REVERTED,
    and the test re-verified green. Every mutation left the code COMPILING and
    semantically wrong (no compile-error proofs). Two initial no-red results
    were treated as BLIND SPOTS in the tests, not as coverage — both tests
    were strengthened until the mutation reddened them (rule 21's
    mutate-it-and-run-it clause working as intended).
  mutations:
    - { id: M1, guard: UPF exclusion in Pass 2 filler stage loop (line ~697), neutered: "if (_isUpf(f)) return false;" removed, result: initially NO red — fixture's Pringles row (541 kcal/serving) was ALSO blocked by the fit filter, so the test passed vacuously through the redundancy. FIX: added fixture row 'Maggi Small Packet' (15g serving, 60 kcal — passes the fit filter, only the UPF flag blocks it) + expanded the no-UPF test to 30 seeds x 3 prefs x 2 archetypes. RE-RUN: RED — 'UPF item Maggi Small Packet generated into dinner' (1 test reddened). Reverted -> green. }
    - { id: M2, guard: Pass 0 quota placement (_pickQuotaItem call), neutered: "final quota = null;", result: RED — 'lunch has no vegetables item' (2 tests reddened: quota presence + quota-flag). Reverted -> green. }
    - { id: M3, guard: staples per-slot cap, neutered: cap branch removed (always allowed), result: RED — 'double-rice class defect regressed: [Soy Chunks, Cucumber Salad, White Rice, Roti, Whole Wheat Bread]' — triple-staple lunch, the exact observed defect (1 test reddened). Reverted -> green. }
    - { id: M4, guard: day-uniqueness in _pickAnchor, neutered: unique-filter + optional-skip removed (pool = candidates), result: RED — 'seed=1 pref=veg: Greek Yogurt appeared 2 times' — the original observed dupe reproduced (1 test reddened). Reverted -> green. }
    - { id: M5, guard: isQuotaLocked skip in Pass 3 target selection, neutered: "if (item.isQuotaLocked) continue;" removed, result: initially NO red on the flag-presence test (the flag is set in Pass 0 and survives regardless — wrong assertion for this guard); the QUOTA PRESENCE test reddened: 'lunch has no vegetables item [Soy Chunks, Toor Dal, Poha, White Rice]' — recovery swapped the quota veg out exactly as predicted by plan-review round 2 finding 4 (1 test reddened after using the right test). Reverted -> green. }
    - { id: M6, guard: Pass 5 fiber floor, neutered: while-loop condition false, result: initially NO red — the test's floor (fiberTarget 8 -> 5g) was below the plan's baseline fiber (quota veg + dal fillers already carry >5g), so it passed vacuously. FIX: rewrote as a strict comparison — same seed, fiberTarget 0 (Pass 5 dormant) vs fiberTarget 30; assert floored fiber STRICTLY greater. RE-RUN: RED — 'Pass 5 produced no fiber gain over the dormant baseline (14 vs 14)' (1 test reddened). Reverted -> green (14 -> 15+). }
    - { id: M7, guard: nuts_seeds per-serving <=300 kcal cap, neutered: cap expression removed (fit filter only), result: initially NO red — the Almond Butter Jar (372 kcal/serving) was blocked by the fit filter in every reachable snack slot (remaining <= ~330 kcal), so the cap appeared redundant. FIX: added a surgical deterministic test with a fixture where the jar is the ONLY nuts_seeds row (stage-4 fit relaxation would otherwise admit it) — RE-RUN: RED — "Expected: not 'Almond Butter Jar' / Actual: 'Almond Butter Jar'" (1 test reddened). Reverted -> green. }
    - { id: M8, guard: recovery anchor-upgrade (_upgradeWeakAnchors — added in the real-DB phase), neutered: call-site condition false, result: initially NO red on real-DB seeds 42/7 (those seeds pass without the upgrade — seed blind spot); FIX: archetype seeds extended to 1-8; RE-RUN: RED — 'low-cal cut seed=1: protein deficit on the REAL DB (119 g vs >= 123.5 g)' (1 test reddened; the guard is load-bearing for veg AND vegan archetypes). Reverted -> green. }
  residual_gaps:
    - meal_fit is SOFT (yields first in the degradation order, per review round 2 finding 7) — pinned on the REAL DB by test/nutrition/food_database_tagged_test.dart (alcohol never-generate + UPF spot-checks).
    - The no-UPF test remains probabilistic for the Maggi row (30 seeds make a vacuous pass ~0.1% likely, not impossible).
    - Pass 5 swaps are protein-blind (can lower protein by a few g); the archetype band tests passing on the same seeds is the pin that this stays within the band.

real_db_phase: >-
  After the founder's HTML export was validated (25,758 legacy-field
  comparisons byte-identical, spot-checks green, 5 alcohol rows DELIBERATELY
  cleared to empty meal_fit = never-generate), the asset was swapped and a
  real-DB test file (test/nutrition/food_database_tagged_test.dart) written.
  Running the archetypes against the REAL 1431-row DB surfaced four defects
  the curated fixture could never show, all fixed in this batch:
  (1) VEGAN LEAK: the name-blocklist vegan filter missed real DB rows
  ('1% Milk', 'Greek Yogurt Plain (2%)', 'Jaouda Perly', 'Nestle Milkybar
  Moosha', 'Buttermilk (Cultured)'). FIX: the DB's own is_vegan field is now
  authoritative for the vegan preference (all dals vegan=true on real data —
  the old comment claiming is_vegan:false would reject dals was a
  fixture-era assumption); blocklists remain as fallback for untagged rows.
  Pinned by the vegan-purity test.
  (2) UNDER-TAGGED UPF ROWS: 6 branded rows the heuristic keywords missed
  and the founder's glance did not catch (Smith & Jones Pasta Masala,
  Nestle Milkybar Moosha, 2x Yoga Bar protein items, Pintos Dark-Chocolate
  PB, Jaouda Perly). FIX: scripts/patch_food_upf_tags.dart + keyword list
  extended (milkybar/nestle/smith & jones/yoga bar/pintos/jaouda).
  (3) VEGAN PROTEIN FLOOR: the real DB's vegan anchor pool was too thin
  (best breakfast anchor Tofu 8g of a 37.5g target). FIX per the
  pre-sanctioned fallback: 10 protein-dense vegan rows appended under NEW
  ids F1432-F1441 (scripts/append_vegan_protein_rows.dart — Soya Chunks
  Nutrela dry 26g/srv, Tempeh 20.3g, Seitan 25g, Sattu, Edamame, Soy Flour,
  Hemp/Pumpkin Seeds, Black Chana, Green Peas dried; the founder's own
  coach-made diet charts use exactly the Nutrela soya-chunks item) + added
  to breakfast/main/snack anchor pools + a new recovery ANCHOR-UPGRADE pass
  (_upgradeWeakAnchors: an anchor under-delivering <60% of slot target is
  swapped for the highest-protein unused pool candidate within 1.5x
  headroom; mutation M8).
  (4) FILLER THRESHOLD GAP: the pre-existing remainingCals > 80 filler
  cutoff left 72 kcal (~5g protein) unfilled in a dinner slot, busting the
  veg-cut floor on the real DB. FIX: threshold 80 -> 50 (the fit filter
  bounds overshoot) + a day-level Pass 4 fallback (when the DAY total busts
  the ceiling but no slot is individually over 1.2x, every slot becomes a
  trim candidate — replacement rules still require protein reduction above
  the daily floor). Final state: 23/23 tests green including real-DB
  archetypes x 8 seeds x 4 archetypes within [95%, 115%].

bpass_phase: >-
  The B-pass (docs/reviews/diet-plan-quality-bpass.md, 10 lenses) found 1
  blocker + 2 majors + 3 minors, all remediated in-batch: (1) BLOCKER — 4 of
  the 10 appended vegan rows duplicated existing names and the source tag
  inflated the pinned seed count 93->103 (2 RED assertions on the v2
  contract test); fixed via scripts/fix_bpass_f1_duplicate_rows.dart.
  (2) MAJOR — the veg preference had the same blocklist-leak defect the
  vegan fix closed; is_veg now authoritative + veg-purity test.
  (3) MAJOR — _dietPref was never set on the saved-plan path; fixed.
  (4-6) MINOR — usedIds registration on all recovery swap sites; UPF filter
  on the anchor path; empty-swap-sheet snackbar. NEW GUARDS added during
  remediation, both mutation-proven: M9 (day-level Pass 4 trim append — the
  day ceiling can bust while no slot is individually over 1.2x) and the
  anchor-upgrade DAY-CEILING guard (upgraded anchors are isAnchor-protected
  and cannot be trimmed back out, so an upgrade that pushes the day over
  115% is refused at the source). Post-remediation: 30/30 tests green
  including real-DB archetypes x 8 seeds x 4 archetypes.
impact_analysis: >-
  Account-tier: touches the seeded food DB schema (v3), the diet plan shown to
  every user, and the shareable PDF artifact (a marketing surface — the PDF is
  the most-shared nutrition artifact). Nutrition-correctness risk is bounded by
  the 15-test suite (protein band [95%,115%] across 4 archetypes, no-UPF,
  quotas, caps, uniqueness, fiber). No payment/sync/auth/AI-proxy surface
  touched. The saved-plan contract is unchanged so cross-device restore and
  TodaysMealsCard hints keep working. Existing installs get the tags only via
  the v3 re-seed; until then the missing-field semantics (UPF=false,
  meal matches-all) keep generation IDENTICAL to the pre-batch behavior on
  untagged boxes except for the composition constraints, which operate on
  category data that already exists.
regression_test_planned:
  - test/nutrition/diet_plan_quality_constraints_test.dart (10 behavioral guards — SHIPPED in this commit, all mutation-proven)
  - test/nutrition/diet_plan_generator_test.dart (4 archetype band tests, fixture enriched — SHIPPED)
  - test/nutrition/food_database_tagged_test.dart (real-DB tagged schema + pinned spot-checks + real-DB archetype run — planned, rides the tagged-asset commit after founder HTML review)
  - test/contracts/diet_plan_saved_loaded_writer_to_reader_test.dart (existing — schema-unchanged pin)
---

# Diet plan composition failure — anchor/filler algorithm with no meal-grammar constraints (d3c7a9)

## Observed plan (Upendra, 17 Sep 2026, PDF export)
