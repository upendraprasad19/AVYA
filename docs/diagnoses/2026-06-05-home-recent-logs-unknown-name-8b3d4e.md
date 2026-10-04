---
bug_id: 8b3d4e
date: 2026-06-05
batch: apk-obs-2026-06-05
status: fixed
blast_radius: feature
symptom: >
  The Home "Recent Logs" list rendered every logged food as "Unknown" (e.g.
  "Unknown — 61 kcal — P2·C2·F4"), while the SAME meals showed their correct
  names on the Nutrition tab.
concept: nutrition_recent_logs_name
sot_registry_entry: nutrition_recent_logs_name
writers: >
  lib/core/services/nutrition_write_service.dart logMeal — stores the food name
  ONLY inside items[].name (+ a meal_type); never a top-level food_name. Unchanged.
readers: >
  Home reader lib/features/home/providers/home_provider.dart (RecentFoodLogEntry
  provider) — was reading non-existent top-level food_name/meal_name/name; now
  calls the shared NutritionReadService.deriveMealDisplayName(log). Nutrition
  reader lib/features/nutrition/widgets/todays_meals_card.dart now forwards to the
  same shared helper. SoT helper: lib/core/services/nutrition_read_service.dart
  deriveMealDisplayName.
hive_key_prefix: nlog_
hive_key_formula: not_applicable (no key change — name derivation only)
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: nutrition_logs
cloud_columns: not_applicable (read derives from local items[].name + meal_type)
contract_test_path: test/contracts/nutrition_recent_logs_name_test.dart
ist_handling: >
  Bonus fix in the same home reader — todayStr was built from device-LOCAL
  year/month/day; switched to istDateStr(DateTime.now()) to match the writer's
  IST date key (drifted vs the writer between IST 00:00–05:30).
provider_invalidations: not_applicable (recentFoodLogsProvider rebuild unchanged)
telemetry_op_types:
  - food_log_unknown_name
cross_account_guard: not_applicable (reads user-scoped nutritionBox via existing guarded paths)
forbidden_patterns_checked:
  - "Home recent-logs reading top-level food_name/meal_name/name (which the writer never writes) — replaced with the shared NutritionReadService.deriveMealDisplayName; pinned by test/contracts/nutrition_recent_logs_name_test.dart."
proposed_fix: >
  Extract todays_meals_card's _deriveMealDisplayName into a shared SoT helper
  NutritionReadService.deriveMealDisplayName (items[].name joined → meal_type →
  sentinel). Both the nutrition card (forwards) and the home provider (calls
  directly + emits food_log_unknown_name on the sentinel) use it — one derivation,
  can't drift. Fix the home reader's date key to istDateStr.
regression_test_planned: >
  test/contracts/nutrition_recent_logs_name_test.dart — deriveMealDisplayName
  returns items[].name (not "Unknown") for the writer's shape; comment-stripped
  wiring grep that BOTH readers call the shared helper, the home reader no longer
  reads log['food_name'], and it uses istDateStr.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "shared helper added; both readers call it; flutter analyze clean on nutrition_read_service.dart + home_provider.dart + todays_meals_card.dart" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "writer's items[].name shape unchanged; nutrition_total_calories + food_log_id_and_name tests still green" }
impact_analysis: >
  Feature blast radius — display only, but writer/reader-drift class (the
  recurring bug type). Affects every user with any logged food on the Home tab.
  Centralising the derivation in one SoT helper removes the drift permanently
  (a future writer-shape change updates one place). The IST fix removes a latent
  early-morning date mismatch. Found via the founder's APK image 2.
---

# Home "Recent Logs" shows "Unknown" (writer/reader drift)

## What happened
Home recent-logs rendered every food as "Unknown"; Nutrition tab was correct.

## Root cause
The writer stores names only in `items[].name` (+ `meal_type`); the home reader
looked for top-level `food_name`/`meal_name`/`name` — fields that don't exist —
so it always hit the `'Unknown'` fallback. The nutrition card already derived
correctly from `items[].name`.

## Fix
Extracted the card's derivation into `NutritionReadService.deriveMealDisplayName`
(shared SoT). Both readers use it; the home reader also emits
`food_log_unknown_name` on the sentinel and now keys by `istDateStr` (was
device-local, a latent IST drift).

## Verification
`flutter analyze` clean; `nutrition_recent_logs_name_test.dart` (derivation +
wiring + IST); existing nutrition tests green.

## See also
- `lib/core/services/nutrition_read_service.dart`
- `feedback_writer_reader_field_drift_recurring.md` (this is another instance)
