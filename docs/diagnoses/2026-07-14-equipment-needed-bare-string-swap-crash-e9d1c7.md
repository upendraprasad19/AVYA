---
bug_id: e9d1c7
date: 2026-07-14
batch: workout-equipment-exclusions
blast_radius: account
status: fixed
symptom: >
  Selecting any of 9 exercises (E252–E260: Wall Sit, Bodyweight Good Morning,
  Doorframe Curl, Towel Row, Negative Pull Up, Glute Kickback, Dumbbell Calf
  Raise, Split Squat, Incline Dumbbell Press) from the swap / add-exercise picker
  CRASHED with a _CastError. Those rows store the library `equipment_needed` field
  as a bare String ("Bodyweight"/"Dumbbells") instead of a List, and
  swap_sheets.dart:28 + :130 cast it `(exerciseData['equipment_needed'] as List?)`
  — casting a non-null String to `List?` throws (the `?? []` / `?? original`
  fallback never runs; the cast fails first). Pre-existing (both the bad rows and
  the cast predate this batch); surfaced by the Batch-5 ⑥ equipment ground-truth.
concept: equipment_needed_shape
sot_registry_entry: equipment_needed_shape
writers:
  - { file: assets/data/exercise_library.json, line: 16496, source: "9 rows (E252–E260) equipment_needed corrected from bare String to List<String>" }
  - { file: lib/core/services/seed_service.dart, line: 81, source: "_exerciseLibraryVersion 5 -> 6 (re-seed the corrected library)" }
readers:
  - { file: lib/features/train/screens/active_workout/swap_sheets.dart, line: 28, source: "add-exercise: equipmentNeeded: ExerciseData.parseEquipmentNeeded(exerciseData['equipment_needed']) — was (… as List?) → crash" }
  - { file: lib/features/train/screens/active_workout/swap_sheets.dart, line: 130, source: "swap: ExerciseData.parseEquipmentNeeded(equipRaw) with null→original preserved — was (… as List?) → crash" }
  - { file: lib/features/train/providers/train_provider.dart, line: 161, source: "static ExerciseData.parseEquipmentNeeded — shape-tolerant (List / String / else); _parseExerciseMaps routes through it" }
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a
cloud_columns: n/a
contract_test_path: test/contracts/equipment_needed_shape_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: >
  n/a — no cross-account surface. The exercise library (exerciseBox) is global,
  seeded from a bundled asset; not user-scoped.
forbidden_patterns_checked: >
  Verified no OTHER `as List` / `as List?` cast on the library `equipment_needed`
  field beyond the two fixed swap_sheets sites — train_provider._parseExerciseMaps
  already read it shape-tolerantly (now routes through the same helper), and
  exercise_repository.dart:130 already guards with `is List` (no crash; it silently
  no-ops the 9 rows — a data-quality issue the JSON fix resolves). No source-grep
  gate exists for this shape; the behavioral test + the JSON data-quality test pin it.
proposed_fix: >
  (1) Data at source: the 9 bare-String equipment_needed values in
  assets/data/exercise_library.json corrected to single-element Lists
  (["Bodyweight"] / ["Dumbbells"]); SeedService _exerciseLibraryVersion bumped 5→6
  so the corrected library re-seeds (putAll overwrites by id). (2) Defensive
  reader: a shared static ExerciseData.parseEquipmentNeeded (List → stringified;
  non-empty String → [String]; else const []) that never throws; both crashing
  swap_sheets sites + train_provider._parseExerciseMaps route through it, so a bad
  shape from legacy/restored data can't crash either.
regression_test_planned: >
  test/contracts/equipment_needed_shape_test.dart — (a) parseEquipmentNeeded on a
  bare String → [String] (throws without the fix), List → list, null/empty/bad-type
  → const []; (b) a JSON data-quality guard asserting every row in
  assets/data/exercise_library.json stores equipment_needed as a List (0 bare
  Strings), so re-introducing a bad row fails.
impact_analysis: >
  Live, reachable, pre-existing crash on a common user path (Train → swap or add
  exercise → pick any of 9 common exercises → _CastError red screen). No data loss
  (read-side crash). Blast radius account (touches the shared exercise library +
  SeedService + the swap UI). The 9 rows also silently no-op the (dead) V3
  item-level equipment filter; item-level filtering is not yet wired into
  generateV4 (queryV4 filters on equipment_tier), so plan generation was unaffected.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "swap_sheets.dart:28,130 + train_provider _parseExerciseMaps route through ExerciseData.parseEquipmentNeeded; flutter analyze clean; equipment_needed_shape_test 4/4 green" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "exerciseBox re-seeds the corrected library on next boot (SeedService _exerciseLibraryVersion 6); the 9 rows now store List equipment_needed" }
  - { layer: client_server_contract, status: not_applicable, evidence: "exercise library is a bundled asset; no cloud contract for equipment_needed" }
---

## Root cause

The exercise library schema treats `equipment_needed` as a `List<String>`, and
249/258 rows comply. 9 rows (E252–E260) stored a **bare String**. Every reader
that assumed the List shape via a hard cast — `swap_sheets.dart:28` and `:130`,
`(x['equipment_needed'] as List?)` — throws `_CastError` on those rows, because
Dart's `as List?` rejects a non-null String (the `?` permits only `null`). The
swap / add-exercise picker loads all 258 rows, so selecting any of the 9 crashed.
`queryV4` was NOT affected — it filters on the separate `equipment_tier` field
(a List on all 258 rows).

## Fix

Two layers: **(1) source data** — the 9 JSON values corrected to single-element
Lists + `_exerciseLibraryVersion` 5→6 so exerciseBox re-seeds; **(2) defensive
reader** — a shared `ExerciseData.parseEquipmentNeeded` (never throws) that both
crashing sites and `train_provider._parseExerciseMaps` now route through, so a bad
shape from a legacy cache or a future edit can't crash.

## Verification

`flutter analyze` clean; `equipment_needed_shape_test` 4/4 (helper shape-tolerance
incl. the bare-String case + a JSON guard asserting 0 bare-String rows across all
258). Found via the ⑥ ground-truth (round 1) + adversarial B-pass on the fix
(round 2). Not a recurrence (no prior diagnose for this class).
