---
bug_id: c8a1f4
date: 2026-06-23
batch: fix-nutrition-target-drift
status: fixed
blast_radius: feature
symptom: >
  Full-charter web E2E (2026-06-21, OBS-11): the Home nutrition snapshot showed
  2540 cal / 140 g protein (correct, the stored canonical user_profile target)
  while the Nutrition tab "Today's Summary" showed 2583 cal / 150 g protein —
  same user, same day, two different targets. Root cause = a writer/reader field
  drift on the carb macro: the cloud `user_profile` column + the restore/sync
  path use the PLURAL `carbs_grams`, while the nutrition + home readers use the
  SINGULAR `carb_grams`. A RESTORED (established) profile carries only
  `carbs_grams`, so `_resolveNutritionTargets`'s all-four canonical check
  (daily_calories + protein_grams + carb_grams + fat_grams) FAILED on
  `carb_grams` and fell through to the RECOMPUTE branch, which re-derives ALL
  four macros from BMR inputs — so calories + protein drifted too. Home reads
  each macro independently (`daily_calories`/`protein_grams` directly → correct;
  `carb_grams` → silently fell to the 250 default).
concept: nutrition_target_canonical_read
sot_registry_entry: not_applicable
contract_test_path: test/contracts/nutrition_target_carb_dualname_test.dart
writers: >
  Cloud `user_profile.carbs_grams` (plural) is the projected column; the Hive→
  cloud push (sync_profile.dart ~:118, sync_service.dart ~:835) reads Hive
  `carbs_grams`. `_restoreUserProfile` (sync_profile.dart :273-285) copies the
  cloud row's keys VERBATIM into the Hive profile → a restored profile gets
  `carbs_grams`, never `carb_grams`. onboarding_provider writes BOTH names
  (so brand-new accounts are unaffected).
readers: >
  `_resolveNutritionTargets` (nutrition_provider.dart) all-four condition + the
  carb value, and `home_provider.dart` `carbTarget` — both now read
  `carb_grams ?? carbs_grams` (dual-name) so the canonical branch fires for a
  restored profile and Home's carb no longer defaults to 250.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods:
  - "sync_profile.dart Hive→cloud projection (carbs_grams) — unchanged"
restore_methods:
  - "_restoreUserProfile (sync_profile.dart) — copies cloud carbs_grams verbatim; reader now tolerates it (no restore change in this feature-tier fix)"
cloud_table: user_profile
cloud_columns: "daily_calories, protein_grams, carbs_grams, fat_grams, water_target_ml (carbs_grams is the plural cloud name)"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "nutrition + home carb-target reads now `carb_grams ?? carbs_grams` (dual-name) — a restored profile (carbs_grams only) reads the stored canonical, never recomputes / defaults. Pinned by nutrition_target_carb_dualname_test.dart."
proposed_fix: >
  Reader-side dual-name read (`carb_grams ?? carbs_grams`) in
  `_resolveNutritionTargets` (the all-four condition + the carb value) and in
  Home's `carbTarget`. This makes the canonical branch fire for a restored
  profile so calories/protein are read as-stored (no recompute) and Home's carb
  no longer falls to the 250 default — Home == Nutrition == user_profile. The
  underlying cloud/Hive name drift (carbs_grams plural) is documented for a
  future standardization but is now tolerated by the readers (debugging §2.1
  dual-name-reader pattern; feature-tier, no platform restore change).
regression_test_planned: >
  test/contracts/nutrition_target_carb_dualname_test.dart — pure-function
  RED→GREEN via the @visibleForTesting `resolveNutritionTargetsForTest` alias:
  a restored profile (carbs_grams only, no carb_grams, no BMR inputs) returns
  the stored canonical 2540/140 instead of the 2400/184 hardcoded defaults; a
  new profile (carb_grams singular) is unchanged.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "nutrition_provider + home_provider dual-name read; flutter analyze clean; nutrition_target_carb_dualname_test green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "restored profile carries cloud carbs_grams (sync_profile :273-285 verbatim merge confirmed); reader now reads carb_grams ?? carbs_grams" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live user_profile canonical = daily_calories=2540, protein_grams=140 (E2E DB query); Home matched, Nutrition recomputed to 2583/150 pre-fix" }
impact_analysis: >
  Feature-tier, restored/established accounts only (new accounts wrote both
  names so were unaffected). The drift made the Nutrition tab show a recomputed
  calorie/protein target that diverged from the stored canonical the rest of the
  app uses — confusing but not data-loss. The dual-name read restores
  cross-surface consistency (Home == Nutrition == user_profile). No migration,
  no cloud, no Edge Function, no cross-account-guard impact.
---

# Nutrition target drift: carb_grams vs carbs_grams field drift (c8a1f4)

## What happened
The cloud column + restore/sync use the PLURAL `carbs_grams`; the readers use
the SINGULAR `carb_grams`. A restored profile carries only `carbs_grams`, so
`_resolveNutritionTargets`'s all-four canonical check failed on `carb_grams` and
fell to the RECOMPUTE branch (re-deriving ALL four macros) → calories + protein
drifted (2540/140 → 2583/150). Home's independent `carb_grams` read fell to the
250 default.

## Fix
Reader-side dual-name `carb_grams ?? carbs_grams` in `_resolveNutritionTargets`
(condition + value) and Home's `carbTarget`. Canonical branch now fires for a
restored profile → Home == Nutrition == user_profile.

## See also
- lib/features/nutrition/providers/nutrition_provider.dart (_resolveNutritionTargets + the test alias)
- lib/features/home/providers/home_provider.dart (carbTarget dual-name)
- lib/core/services/sync/sync_profile.dart (_restoreUserProfile verbatim merge — the source of the drift)
- test/contracts/nutrition_target_carb_dualname_test.dart
