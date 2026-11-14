---
bug_id: 6f5aaa
date: 2026-11-14
batch: diet-food-type (diet plan Unit 2a, plan docs/plans/diet-food-type.md revision 5, 4 review rounds, converged)
status: fixed
blast_radius: account
symptom: >-
  The profile value `diet_preference` had three vocabularies. Onboarding
  never asked and wrote `veg` (plan_screen.dart, onboarding_provider.dart
  `?? 'veg'`); Edit Profile offered `non_veg | vegetarian | vegan |
  pescatarian | keto` and highlighted NO chip for a stored `veg` (OI-257);
  the coach's nightly extraction wrote `vegetarian | vegan | non_veg | keto |
  pescatarian`. The diet plan's filter `passesDiet` knew only `vegan` and
  `veg`/`vegetarian`, so a pescatarian (and any unknown value) got chicken
  and mutton plans; there was no eggetarian choice; `keto` (a diet STRATEGY)
  was stored as a food type. The founder (2026-11-14) asked for one set of
  food types everywhere (Veg, Non-veg, Eggetarian, Pescatarian, Vegan),
  default Non-veg, selectable on the Diet Plan screen and in Edit Profile,
  shown on the Nutrition calorie card, known to the coach, and with no effect
  on workout generation.
concept: diet_preference_vocabulary
recurrence: >-
  RECURRENCE of a2b2f1 (2026-09-27, same column): two unsynchronised writers
  of `diet_preference`; that fix added the coach-extraction lock and taught
  the protein-gap alert's isVeg both `veg` and `vegetarian`, and filed the
  remaining vocabulary mismatch as OI-257, blocked on a product decision.
  The founder made it today. Known-good fix applied: one closed vocabulary,
  one tolerant normaliser that every reader goes through (the
  equipmentAccessOf pattern), one write door, a shared fixture the server
  mirror (Unit 2b) reads too.
related_bugs: [a2b2f1]
sot_registry_entry: diet_preference_vocabulary (new); diet_plan_saved_loaded (saved plan gains top-level food_type)
writers:
  - { file: lib/core/constants/food_types.dart, method: FoodType / foodTypeOf / foodTypeOfProfile (vocabulary + normaliser), line: 77 }
  - { file: lib/features/onboarding/screens/plan_screen.dart, method: "setAnswer('diet_preference', 'non_veg')", line: 582 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method: resolveOnboardingDietPreference, line: 999 }
  - { file: lib/features/profile/providers/profile_provider.dart, method: UserProfileNotifier.setFoodType (serialised write door, lock on a real change), line: 95 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method: _save writes _foodType.storageKey, line: 1836 }
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method: _changeFoodType / _savePlan food_type, line: 114 }
readers:
  - { file: lib/features/nutrition/services/diet_plan_generator.dart, method_or_widget: passesDiet (normalises; eggetarian/pescatarian family exception), line: 1328 }
  - { file: lib/features/nutrition/services/curated_diet_plan_generator.dart, method_or_widget: _candidates passes the catalog family, line: 240 }
  - { file: lib/features/nutrition/services/diet_plan_swap.dart, method_or_widget: swapAlternatives passes the catalog family, line: 125 }
  - { file: lib/features/nutrition/providers/diet_plan_provider.dart, method_or_widget: DietPlanNotifier.build watches the food type; savedPlanMatchesFoodType, line: 73 }
  - { file: lib/features/nutrition/screens/diet_plan_screen.dart, method_or_widget: _generatePlan (saved plan of another food type not loaded, notice once), line: 82 }
  - { file: lib/features/nutrition/screens/nutrition_screen.dart, method_or_widget: FoodTypeTag on the calorie card, line: 417 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: _foodType = foodTypeOfProfile(profile), line: 239 }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: profile.diet_preference (canonical) + diet_preference_label, line: 112 }
hive_key_prefix: user_profile
hive_key_formula: userBox profile map key 'diet_preference' (unchanged key; values now the five canonical keys); saved plan MigratedKey('saved_diet_plan') gains top-level 'food_type'
sync_methods: [syncProfileNow, pushSnapshot, syncSavedDietPlan]
restore_methods: [restoreProfile (passthrough), _restoreSavedDietPlan (verbatim JSONB)]
cloud_table: user_profile
cloud_columns: [diet_preference]
contract_test_path: test/contracts/diet_preference_vocabulary_writer_to_reader_test.dart
ist_handling:
  - { file: lib/features/profile/providers/profile_provider.dart, line: 95, fn: "setFoodType (no date key; IST not involved)" }
provider_invalidations: [userProfileProvider (state write), dietPlanProvider (rebuilds through its food-type select, no explicit invalidate)]
telemetry_op_types:
  success: []
  failure: [diet_plan_food_type_change (ErrorTelemetry.recordNonFatal reason on a failed setFoodType from the Diet Plan screen)]
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "a 'veg' fallback for an absent diet_preference in lib/", absent_after_fix: true }
  - { pattern: "a Keto chip in the food-type selector", absent_after_fix: true }
  - { pattern: "a raw diet_preference string compared without foodTypeOf in lib/", absent_after_fix: true }
  - { pattern: "diet_preference / FoodType read under plan_engine/, train/, home/", absent_after_fix: true }
  - { pattern: "chicken or mutton in an eggetarian or pescatarian plan or swap list", absent_after_fix: true }
proposed_fix: >-
  lib/core/constants/food_types.dart: enum FoodType (storage key, label,
  short label), default Non-veg, a tolerant foodTypeOf (null/'' → Non-veg,
  legacy spellings → their type, keto/low_carb → Non-veg, any other
  non-empty string → Veg so an unknown deliberate choice never gets meat),
  pinned by a shared JSON fixture the Unit 2b Deno mirror reads. Onboarding
  writes non_veg. One write door UserProfileNotifier.setFoodType: serialised
  by a chained future, captures the user id and aborts if it changed, no-op
  on equal, writes the canonical key, pushes the coach snapshot when signed
  in and locks the field against the coach's extraction only when the type
  itself changed. One shared FoodTypeChips widget (Edit Profile's pill, 44 dp
  minimum, button semantics with a tap action) used by Edit Profile (Keto
  chip removed) and the Diet Plan screen. passesDiet normalises and takes the
  catalog family: eggetarian admits the egg family, pescatarian egg and fish,
  before both veg checks. The saved plan records its food_type; a plan of
  another type is not loaded (notice once) and feeds no Nutrition hints. The
  calorie card, the Diet Plan header and the PDF show the food type. The coach
  snapshot sends the canonical key and a label. The day score gained a steep
  calorie-band term beyond ±8 % (a 1,500 kcal pescatarian day measured
  1.11× before it).

touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter analyze (whole project); targeted suites green (food_types 40, writer/reader 14, chips 5, tag 6, curated matrix with 4 new archetypes, diet plan screen 3); mutation table below" }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "real-Hive behavioral tests: setFoodType write→read, DietPlanNotifier rebuild from both doors, saved plan food_type mismatch (diet_preference_vocabulary_writer_to_reader_test.dart, diet_plan_screen_no_modal_test.dart)" }
  - { tier: 3_postgres_schema, status: verified, evidence: "live read-only query 2026-11-14: user_profile.diet_preference is text, no CHECK constraint mentions it (pg_constraint), so all five keys are accepted; saved_diet_plans.plan_json is jsonb, a new top-level key is stored verbatim" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "live read-only query 2026-11-14: user_profile.diet_preference values veg 32, non_veg 4, null 1, non_vegetarian 1 (38 test accounts); every one is a fixture row of foodTypeOf (veg, nonVeg, nonVeg, nonVeg). No data migration: pre-launch, every account is a test account (CLAUDE.md §1); the 32 silent veg values stay Veg until the tester changes them" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function change in 2a; the server half is Unit 2b, deployed BEFORE this PR merges (release order in the plan)" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "daily-snapshot extraction changes are Unit 2b" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "same column, same write path (ProfileWriteService.patchProfile)" }
  - { tier: 9_storage, status: not_applicable, evidence: "no Storage object" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12_client_server_contract, status: verified, evidence: "coach snapshot profile.diet_preference now always canonical + diet_preference_label (+~30 bytes vs the 10K limit; snapshot_compaction_test rerun); the five keys are the fixture rows Unit 2b's TS normaliser is tested against" }
impact_analysis: >-
  Account tier: the profile write path (a new door that reuses
  updateProfile → ProfileWriteService), Edit Profile, the Diet Plan screen,
  the Nutrition calorie card, the coach snapshot. Behaviour users notice:
  new users default to Non-veg (was silently Veg); a stored veg/vegetarian
  highlights the Veg chip; Keto is no longer a food type (Unit 3 adds it as
  a PRO strategy); Eggetarian is new; a pescatarian no longer gets chicken
  or mutton; a saved plan of another food type stops feeding the Nutrition
  hints until a plan of the new type is saved. passesDiet is unchanged for
  veg, vegetarian, vegan, non_veg, non-veg, keto and '' and stricter by
  design for pescatarian, eggetarian and unknown strings. No kill switch
  (plan §3): a closed-enum normaliser that maps every old value is more
  tolerant than the code it replaces. Release order: Unit 2b's Edge
  Functions are deployed before this PR merges (web deploys on merge).
regression_test_planned:
  - test/core/food_types_test.dart (T1, every fixture row)
  - test/contracts/diet_preference_vocabulary_writer_to_reader_test.dart (T2 + T5 hints)
  - test/nutrition/passes_diet_food_type_test.dart (T3 truth table)
  - test/nutrition/curated_diet_plan_test.dart (T3 archetypes, purity, oracle, catalog family pin, forced fallback)
  - test/shared/food_type_chips_test.dart (T4)
  - test/widgets/diet_plan_screen_no_modal_test.dart (T5 mismatch notice; the selector's success and failure paths on the real screen)
  - test/contracts/food_type_no_workout_reader_test.dart (T6, presence)
  - test/nutrition/food_type_tag_test.dart (T7)
  - test/nutrition/diet_plan_pdf_test.dart (the PDF export moved to services/diet_plan_pdf.dart to keep the screen under the 800-line gate; still builds a PDF)
---

# One food-type vocabulary on the client (6f5aaa)

## What was wrong

`diet_preference` was written in three vocabularies and read in four
subsets (table in the plan §1). The visible effects: a new user was silently
Veg; Edit Profile showed no chip selected for that Veg; a pescatarian got
chicken; Keto sat among the food types; nobody could choose Eggetarian.

## Writers and readers (named before the fix)

Writers: onboarding (`plan_screen.dart` setAnswer, `onboarding_provider.dart`
`?? 'veg'`), Edit Profile's chips and save map, the coach's nightly
extraction (Unit 2b). Readers: the Diet Plan screen (three `?? 'veg'`),
`passesDiet` (curated generator, swap sheet, legacy generator),
`DietPlanNotifier` (Nutrition hints, did not watch the food type at all),
Edit Profile's chip highlight and lock compare, the coach snapshot, and the
server readers (Unit 2b).

## Fix

See `proposed_fix` above and the plan §2. The design choices that matter:

- **Fail-safe direction.** Never chosen (null, `''`) reads as the founder's
  default, Non-veg. A non-empty value the table does not know reads as Veg:
  an unknown deliberate choice must never be served meat.
- **Egg and fish identity is the catalog family**, not a name match. The
  catalog's `is_veg == false` entries are exactly egg 7, chicken 5, fish 6,
  mutton 2 (pinned). The legacy generator gets no family, so eggetarian and
  pescatarian get the veg rule there (never meat).
- **The lock** (a2b2f1's mechanism) fires only when the food type itself
  changes, so rewriting a legacy `vegetarian` to `veg` does not stop the
  coach from learning later.

## Deviations from the plan, stated

- Plan T2 said two quick taps (Veg, then Non-veg) give "exactly one lock".
  Both taps are real changes (non_veg → veg → non_veg), so the test asserts
  two locks; the plan text is corrected.
- Plan T4 named an Edit Profile widget test. No test in the repo pumps
  `EditProfileScreen` (it needs most of the app's providers). The stored
  value → highlighted chip mapping is `foodTypeOfProfile` (every fixture row,
  T1) and the wiring is a presence pin (`_foodType = foodTypeOfProfile(profile)`,
  `FoodTypeChips(value: _foodType`). Stated as presence.
- Plan T5 named `diet_plan_saved_loaded_behavioral_test.dart`. The
  `DietPlanNotifier` cases live in the writer/reader test (real Hive, both
  write doors) and the screen's mismatch notice in
  `diet_plan_screen_no_modal_test.dart` (the screen is pumped there already).

## Measured (curated generator, real asset, 50 seeds)

| Archetype | kcal / protein | protein ratio (min, mean) |
|---|---|---|
| cut male eggetarian | 2000 / 144 | 0.76, 0.84 |
| cut female pescatarian | 1500 / 110 | 0.81, 0.90 |
| maintain eggetarian | 2400 / 128 | ≥ 0.94, 1.00 |
| maintain pescatarian | 2400 / 128 | ≥ 0.94, 1.00 |

All calories within 0.96–1.09 of target after the calorie-band term. Floors
were set just under the measured values (contract: raise only).

## Mutation proof (rule 21)

Each guard was broken in turn by a script that asserted the anchor matched
exactly once and the edit APPLIED, ran the listed test files, restored the
file and asserted it byte-equal to the original (sha256). No result below is a
compile error. M19 was applied by `sed` with a `grep -c` = 1 check and
restored from a copy.

| # | Guard broken | Test file(s) | Failing tests |
|---|---|---|---|
| M1 | unknown string reads as Non-veg (`?? FoodType.veg` → default) | food_types_test | 3 |
| M2 | `vegetarian` → Non-veg | food_types_test | 3 |
| M3 | eggetarian egg exception removed | passes_diet_food_type + curated | 2 |
| M4 | pescatarian also admits the chicken family | passes_diet_food_type + curated | 3 |
| M5 | setFoodType locks on a spelling-only change | writer/reader | 2 |
| M6 | setFoodType never locks | writer/reader | 2 |
| M7 | serialisation removed (no chain) | writer/reader | 1 |
| M8 | account-change check removed | writer/reader | 1 |
| M9 | DietPlanNotifier stops watching the food type | writer/reader | 1 |
| M10 | screen loads a saved plan of another food type | diet_plan_screen_no_modal | 1 |
| M11 | chip Semantics loses its tap action | food_type_chips | 1 |
| M12 | onboarding default back to `veg` | writer/reader | 1 |
| M13 | calorie-band term removed from the day score | curated | 1 |
| M14 | mismatch notice shown on every open | diet_plan_screen_no_modal | 1 |
| M15 | `passesDiet` lets eggetarian through when no family (legacy path) | curated (forced fallback) | 1 |
| M16 | Keto added back as a FoodType | food_type_chips + food_types_test | 3 |
| M17 | failure snackbar removed | diet_plan_screen_no_modal | 1 |
| M18 | the screen's chip skips `setFoodType` | diet_plan_screen_no_modal | 1 |
| M19 | coach snapshot sends the raw stored value | writer/reader | 1 |

Declared limits: Edit Profile's chip wiring and onboarding's `setAnswer`
literal are presence pins (stated above); the workout-isolation sweep (T6)
is presence only by nature.
