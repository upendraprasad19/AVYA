---
bug_id: e7b2d4
date: 2026-09-17
batch: custom-picker-fix
status: fixed
blast_radius: platform
symptom: |
  Founder, logged in as Upendra, doing his morning workout in the
  active-workout screen: searching the SWAP EXERCISE picker for his own
  custom exercise `Single Leg Front Lever` returned nothing. The exercise
  IS visible on the Train screen (YOUR EXERCISES / logged rows — those
  readers scan customBox / exlog_ directly and never filter) but absent
  from every picker's selection list.
concept: custom_exercises_mutations
sot_registry_entry: custom_exercises_mutations
writers:
  - { file: lib/features/train/widgets/create_custom_exercise_sheet.dart, method: _save, line: 205 }
  - { file: lib/features/train/repositories/workout_repository.dart, method: createCustomExercise, line: 1325 }
readers:
  - { file: lib/features/train/widgets/exercise_swap_sheet.dart, method_or_widget: _loadExercises, line: 100 }
  - { file: lib/features/train/screens/active_workout/exercise_picker_sheet.dart, method_or_widget: _loadAllExercises, line: 57 }
  - { file: lib/features/train/screens/template_builder_screen.dart, method_or_widget: _refresh, line: 543 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: _eligibleCustomExercises, line: 963 }
hive_key_prefix: custom_exercise_
hive_key_formula: "'custom_exercise_${DateTime.now().millisecondsSinceEpoch}' (create) | 'custom_exercise_<cloudRow.id>' (restore)"
sync_methods: [syncCustomItemsNow, pushSnapshot]
restore_methods: [_restoreCustomExercises]
cloud_table: user_custom_exercises
cloud_columns: [id, user_id, name, logging_type, category, primary_muscles, equipment_needed, default_sets, default_reps, submitted_to_library, approved_for_library, created_at]
contract_test_path: test/contracts/can_offer_in_picker_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: wrapUserScopedBox(customBox)
forbidden_patterns_checked:
  - { pattern: "getCustomExercises\\(\\)[\\s\\S]{0,200}canPerform\\(", absent: true }
proposed_fix: |
  Reader-side picker exemption (founder decision "Option A for now; file B
  as OI"). New predicate EquipmentCapability.canOfferInPicker: a
  user-authored custom exercise with an UNVERIFIABLE equipment requirement
  (empty/null/all-unmappable `equipment_needed` — the creation sheet's
  hardcoded shape) is always offered in the three pickers; customs WITH
  parseable equipment and ALL library/community rows keep the fail-closed
  canPerform. Provenance comes from LIST MEMBERSHIP (getCustomExercises
  output), never a per-row is_custom check — restored custom rows carry no
  is_custom field (the cloud table has no such column; restore stamps only
  type: 'exercise'), so a row-shape discriminator would miss exactly the
  restore population, which is where the founder's reported exercise came
  from. Plan-generator canPerform is untouched. Same batch: muscle-capture
  chips on the creation sheet (re-arms _eligibleCustomExercises) and an
  edit mode for existing customs (name-locked, same-key save through the
  canonical SoT writer).
regression_test_planned:
  - test/contracts/can_offer_in_picker_behavioral_test.dart
  - test/contracts/custom_picker_capability_wiring_test.dart
  - test/contracts/custom_muscle_vocabulary_test.dart
  - test/contracts/custom_exercises_mutations_behavioral_test.dart
  - test/contracts/custom_exercise_writer_to_reader_test.dart
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "predicate + 3 picker sites + sheet, flutter analyze lib clean" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "edit-mode write->read-same-key behavioral arm, custom_exercises_mutations_behavioral_test Test 5" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no migration; user_custom_exercises already carries primary_muscles" }
  - { layer: migrations, status: not_applicable, evidence: "none applied" }
  - { layer: edge_functions, status: verified, evidence: "promote-community-item projects primary_muscles already; no EF change" }
  - { layer: rls, status: not_applicable, evidence: "no policy touched" }
  - { layer: sync_restore, status: verified, evidence: "_restoreCustomExercises shape unchanged; restored rows (no is_custom) covered by the fifth test arm" }
  - { layer: cloud_contract, status: verified, evidence: "edit round-trips on onConflict 'id' (sync_community.dart:129); no schema change" }
root_cause: |
  Writer/reader drift, second distinct instance against the SAME exercise
  name as a5d29c (related_bugs below).

  Writer half: create_custom_exercise_sheet.dart `_save` hardcodes
  `'equipment_needed': <String>[]` (the sheet has no equipment field at
  all) AND `'primary_muscles': <String>[]`. Every UI-created custom
  exercise ever made stores both fields empty.

  Reader half: ⑦ OI-89 (2026-08-28) added `EquipmentCapability.canPerform`
  — a fail-closed capability check (`if (needed.isEmpty) return false;`)
  designed so an unreadable requirement means "we do not know", not "no
  requirement". Its doc comment names `createCustomExercise` as a
  population that can store `[]` by design, and the swap-sheet seam
  comment even says customs SHOULD be filtered — but neither accounted for
  the UI creation sheet, which stores `[]` for EVERY custom. The three
  OI-89 UI seams (swap 6, picker 8, template 7) applied canPerform to the
  custom list, so the moment `enable_equipment_capability_floor` defaulted
  ON, every user-authored custom exercise disappeared from all three
  pickers BEFORE the search string was applied.

  Secondary reader half: exercise_selector._eligibleCustomExercises skips
  customs with empty primary_muscles — combined with the same hardcoded
  writer, the plan-generator's custom-supplement path (L2 append) has been
  dead for sheet-created customs since inception.

  Two independent defects with the same symptom family, both found in this
  investigation: (a) picker visibility (this fix), (b) the dead supplement
  path (fixed by muscle capture in this batch).
impact_analysis: |
  Every user, every custom exercise, live in production: swap picker,
  +Add Exercise picker, and template builder all filtered customs through
  the fail-closed rule; the flag defaults ON for everyone. The May 2026
  fix (a5d29c — type-stamp on restore) is intact and was NOT the cause;
  that bug restored rows successfully and this filter then hid them.

  Fix-shape risks examined in the two plan-review rounds:
  - P0 (round 1): a per-row `is_custom == true` discriminator misses
    restored custom rows (cloud table has no such column) — the fix would
    have failed for the exact population of the reported exercise, which
    arrived via restore. Resolved by list-membership provenance
    (filter-then-merge).
  - P1 (round 2): edit mode must not re-stamp equipment_needed or
    approved_for_library (demotes approved submissions; wipes AI rows'
    real equipment) and must union pre-existing unmapped muscle tokens
    through save (no silent data loss). Both encoded in buildEditPayload +
    pinned behaviorally.
  - Disclosed plan-engine consequence: customs with muscles now pass the
    _eligibleCustomExercises gate and can be auto-appended to generated
    plans (exclusion-checked, not capability-checked — safe while the
    sheet still writes equipment_needed: []) and feed _muscleTaxonomy →
    weakMuscles/bodyFocus. Intended.
fix: |
  1. equipment_capability.dart: new pure static canOfferInPicker
     (exemption fires ONLY on an unparseable requirement; canPerform
     untouched).
  2. exercise_swap_sheet.dart (:100), exercise_picker_sheet.dart (:57,
     filter-then-merge), template_builder_screen.dart (:543, doableCustom).
  3. create_custom_exercise_sheet.dart: muscle multi-select chips
     (16 canonical tokens, membership pinned by
     custom_muscle_vocabulary_test), primary_muscles written from
     selection; EDIT mode (existing param, name locked — a rename would
     mint a NEW deterministic v5 UUID and orphan name-keyed log history),
     saving to the SAME key via WorkoutWriteService.upsertCustomExercise
     (WriteSource.editSheet), preserving id/created_at/equipment_needed/
     approved_for_library and unioning unmapped muscle tokens through.
  4. Edit entry: tap a chip in YOUR EXERCISES.
mutation_proven: |
  5 mutations, all semantic (none compile-error reds), each confirmed
  applied by grep before running:
  M1 polarity flip of the exemption → 2 red (ARM 1 + restored-row arm).
  M2 isCustom-guard drop → 1 red (ARM 3, non-custom fail-closed).
  M3 buildEditPayload `_key`-strip removal → initially ZERO red (the
  fixture never carried _key — the exact fictional-fixture trap); fixture
  corrected to reproduce the real workflow (section injects _key, stored
  row must not have it), then 1 red on the new assertion. Reverted.
  M4 writer hardcode restored → 2 red (wiring + writer→reader field set).
  M5 muscleOptions token drift → 3 red (vocabulary membership).
related_bugs:
  - a5d29c (2026-05-15, same exercise, different root cause — missing
    type stamp on cloud-restored customs; that fix is intact)
recurrence: |
  Fourth picker-miss incident against the custom-exercise concept
  (a5d29c May 2026; s1n4c0-era swap/create flows; this). Class:
  capability filter (fail-closed by design) applied to a population that
  structurally cannot carry the data it is checked against. Not a
  writer/reader FIELD drift this time — a POLICY drift between the OI-89
  safety predicate and the creation sheet's data shape.
---
