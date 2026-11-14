---
bug_id: f3b8d1
date: 2026-11-09
batch: library-batch-s1b1
status: fixed
blast_radius: platform
symptom: >-
  With the core-list pool ON (enable_core_list_pool, ship-dark), gym users got the
  bodyweight Glute Kickback (E257) or Side Lying Hip Adduction (G3667) in the Hip
  slot (114 audit plans for Glute Kickback at advanced gym after Library Batch S1a,
  and the beginner and intermediate gym Hip slots in the gate personas), because the
  R3 (a) like-for-like reduction compares a row's first-listed muscle with the slot's
  muscle and the Hip slot names a region ("Hip") that no row lists first. Separately,
  S1a put E038 Goblet Squat at advanced, which put it in the advanced basic and full
  gym Quads compound pools ahead of Bulgarian Split Squat / Leg Press on the id tie;
  the founder ruled (2026-11-09) that advanced gym users should not get it.
concept: core_list_pool
sot_registry_entry: core_list_pool
writers:
  - file: scripts/data/library_s1_core_levels.json
    method: core-levels record for kept rows; E038 removed (back at its pre-S1a value), E107 after = every level, E109 added (after = every level)
    line: 1
  - file: scripts/data/library_batch_c_source.json
    method: G0168 Cable Hip Adduction core_levels [] to every level; _meta.derived re-derived by library_batch_c_scope.js --write (C1 to C6 green)
    line: 1
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion 21 to 22 (a v22 comment block above it); putAll rewrites the rows by id
    line: 160
readers:
  - file: lib/shared/repositories/plan_engine/core_list_selector.dart
    method_or_widget: namesMuscle gains the region table _slotRegionMuscles (hip -> abductors, adductors), read by the R3 (a) like-for-like reduction in rankedPool; flag ON only
    line: 117
  - file: test/plan_generator/core_list_pool_gate_test.dart
    method_or_widget: new hard zero - an uninjured basic or full gym persona (gym kit not excluded) never gets a bodyweight-only row in the Hip or Glutes hip_isolation slot, nor a Glutes pick whose first muscle is not Glutes (restated from EquipmentVocab.tierItems and primary_muscles)
    line: 258
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<library id>] (re-seeded by SeedService v22 putAll by id; custom and community rows are never touched)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: []
contract_test_path: test/contracts/core_list_like_for_like_data_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Library Batch S1b-1 (plan docs/plans/2026-11-09-library-batch-s1b1-gym-hip-goblet.md,
  founder decisions 2026-11-09, board d12): a region table in CoreListSelector.namesMuscle
  so Abductors and Adductors name the Hip slot (exact match only); E107 Hip Abduction
  Machine and G0168 Cable Hip Adduction core at every level (the machine for full gym, a
  cables row for basic gym, which has no machines); E109 Glute Kickback (Cable) at beginner
  too, so the gym Glutes isolation slot reduces to it (otherwise E107 took it on the id tie); E038 Goblet Squat back to
  [beginner, intermediate]; seed v22. core_levels is not a cloud column, so no migration.
regression_test_planned:
  - test/contracts/core_list_like_for_like_data_test.dart
  - test/contracts/library_s1_core_levels_test.dart
  - test/contracts/library_seed_v22_upgrade_behavioral_test.dart
  - test/contracts/exercise_library_core_fields_contract_test.dart
  - test/plan_generator/core_list_pool_gate_test.dart
related_bugs:
  - e9a4b6  # Library Batch S1a: the levels that put E257 / G3667 at advanced and E038 at advanced
  - c756b4  # generator step 1A: the R3 (a) like-for-like rule this extends
recurrence: |
  Not a recurrence of a known class. A sibling of c756b4's like-for-like rule: that rule
  was keyed on muscle names and the Hip slot's target is a region, so the rule silently
  never fired there (the S1a plan named it: "the like-for-like step cannot fire there").
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "core_list_selector.dart region table; library JSON, source, record, seed constant 22; tests in regression_test_planned green; mutations below." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "library_seed_v22_upgrade_behavioral_test.dart drives the real SeedService.seedIfNeeded: a v21 box ends at v22 with the new levels on E038 / E107 / G0168 and every other row unchanged; a v22 box is not rewritten." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "core_levels is not a cloud column (backups/live_schema_columns.json, exercise_library)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud row changes; exercise_library_cloud_tuples_match_test.dart stays green against the newest seed migration." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads core_levels." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job is touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy is touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No media change." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret is touched." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service is touched." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "The library reaches the client through the bundled asset and the seed only; core_levels has no cloud column." }
impact_analysis: >-
  OFF (every user today): none; the golden and scorecard are green unchanged and the
  2,304-plan OFF dump is byte-identical to S1a's. Installs re-seed once (v22). ON (dark):
  see the plan's Results section.
---

# Library Batch S1b-1: gym Hip slot gets gym kit, Goblet Squat off advanced (f3b8d1)

## What changed
- `CoreListSelector.namesMuscle`: Abductors and Adductors name the Hip slot (`_slotRegionMuscles`), so an equipped
  user's Hip slot reduces to like-for-like implement rows.
- `core_levels`: E107, E109 and G0168 at every level; E038 back to `[beginner, intermediate]`. Seed v22.
- Gate: a new hard zero for a bodyweight row in an uninjured gym persona's Hip or Glutes isolation slot, and for a
  Glutes pick whose first muscle is not Glutes.

## Mutation evidence (rule 21)
| mutation | applied | red |
|---|---|---|
| region table emptied (`'hip': <String>{}`) | `grep -c` 1 | like-for-like data test 2 red |
| seed constant back to 21 | `grep -c` 1 | v22 and v21 seed tests 3 red |
| E038 advanced level back in the library | edited by python | S1 levels and v22 tests 3 red (the importer `--check` stays green: E038 is no longer in the record, so the fixture test is the guard) |
| G0168 back to `[]` in the library | edited by python | S1 levels and like-for-like tests 2 red |
| E109 back to `[intermediate, advanced]` (the reviewers' P2 state) | node read-back | gate exit 1: 38 'gym Glutes slot got a non-glute row' (beginner gym Glutes slots) |

Every mutated file restored byte-identical (`cmp`). The gate zero's red on the first build (beginner and intermediate gym
Hip slots still bodyweight) is what widened E107 and G0168 to every level.
