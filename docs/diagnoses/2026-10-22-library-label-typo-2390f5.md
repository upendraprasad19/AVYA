---
bug_id: 2390f5
date: 2026-10-22
batch: library-data-repair
blast_radius: platform
status: fixed
symptom: >
  E172 Dumbbell Side Bend, a core row, carried target_focus ["Lats"] and nothing else, so
  queryV4's target-muscle filter never offered it to a Core slot: a Phase-1 home_dumbbells
  Core/isolation query returned eight rows (E059 E060 E174 E175 E176 E250 E251 E131) and
  never the side bend. The plate sheet and the exercise card labelled it "Lats" for
  intermediate and advanced users. E163 Foam Roll IT Band, a flexibility row for the
  lateral thigh, carried the same typo.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
related_bugs: [e1a7c4, ada3fb, b7d3e1, 46fc99]
recurrence: >
  Recurrence of the exercise_library_schema class (e1a7c4 stub rows; b7d3e1 text shift and
  46fc99 duplicates in this batch). Known-good fix reused: rewrite the bundled rows, ship them
  with the batch's v12 seed bump, contract test over the bundled file.
writers:
  - { file: assets/data/exercise_library.json, line: 1, source: "scripts/repair_exercise_library_v12.js relabel: E172 ['Lats'] -> ['Core'], E163 ['Lats'] -> ['Legs'], keyed off the typo so a later deliberate edit is left alone" }
  - { file: lib/core/services/seed_service.dart, line: 220, source: "_seedExercises putAll rewrites the two rows on the v12 re-seed" }
readers:
  - { file: lib/shared/repositories/exercise_repository.dart, line: 305, source: "queryV4 step 2 / 2b: _fieldSubstringMatch over target_focus for targetFocus and targetMuscle (was :285-303 before Task 2's alias code shifted it)" }
  - { file: lib/core/utils/exercise_display.dart, line: 9, source: "formatMuscleLabel: target_focus is the muscle label shown to intermediate (text before '(') and advanced users" }
hive_key_prefix: n/a
hive_key_formula: "exerciseBox keyed by the row id E###"
sync_methods: n/a
restore_methods: n/a
cloud_table: exercise_library
cloud_columns: "none: target_focus is not a cloud column (backups/live_schema_columns.json), so no cloud reader sees the label"
contract_test_path: test/contracts/library_label_typo_behavioral_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: n/a — exerciseBox is a global bundled seed, not user-scoped
forbidden_patterns_checked: >
  A general "Lats only on pull patterns" rule was considered and rejected: E070 Front Lever,
  E154 Lat Stretch, E159 Child's Pose and E213 Dead Hang carry 'Lats' correctly on non-pull
  patterns, so the test pins the two typo rows by id. The six bodyweight rows whose label is
  no slot label (E272 E273 E289 E290 'Shoulders', E276 E277 'Upper Back') are deliberately
  NOT relabelled here: _preferNovel (exercise_selector.dart:1054-1066) walks past the first
  sorted entries whenever avoidNames is non-empty, so a Phase 2+ home or gym user's Lateral
  Delts pool would become [E013, E273, E289] and flip Lateral Raise to Towel Lateral Raise;
  E276/E277 would stay inert because every Mid Back slot is compound. They wait for Batch
  B's equipment-aware pool, filed as OI-387. supabase/functions reads no target_focus.
proposed_fix: >
  relabel stage in scripts/repair_exercise_library_v12.js (idempotent; a second run leaves
  the file byte-identical): E172 target_focus ["Core"] (its primary muscle is the obliques,
  and every Core slot queries 'Core'), E163 target_focus ["Legs"] (IT band / lateral thigh).
regression_test_planned: >
  test/contracts/library_label_typo_behavioral_test.dart (2, RED 0/2 then GREEN 2/2): the
  home_dumbbells core/Core/isolation queryV4 over a Hive box seeded from the bundled JSON
  contains E172; E172 and E163 carry no 'Lats'. MUTATION: the HEAD (typo) JSON put back ->
  both tests red; restored from a byte copy and checked with cmp.
impact_analysis: >
  Every Core slot at every tier that allows dumbbells can now draw the side bend (it is not
  foundational, so Phase 1's foundationalOnly slots are unchanged). The batch's Task 5 pick
  diff over the 606-persona matrix measures the plan change and classifies it. E163 is a
  flexibility row with no 'Legs' slot query, so its relabel changes only its display label.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "bundled JSON relabelled; library_label_typo_behavioral_test 2/2 over the real queryV4" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "the batch's v12 seed bump rewrites both rows in every install via putAll" }
  - { layer: postgres_schema, status: verified, evidence: "backups/live_schema_columns.json: exercise_library has no target_focus column" }
  - { layer: edge_function_deploy, status: not_applicable, evidence: "grep of supabase/functions finds no target_focus reader" }
---

## Root cause

Two rows were given the label 'Lats' by mistake when the library was tagged. queryV4
filters slots by a substring match on `target_focus`, so a core row labelled only 'Lats' is
invisible to every Core slot.

## Fix

The repair script's `relabel` stage gives E172 'Core' and E163 'Legs', keyed off the exact
typo.

## Verification

New behavioural test RED then GREEN; the mutation reddened both tests.
