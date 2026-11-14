---
bug_id: b7e2c4
date: 2026-11-09
batch: library-batch-s1b2
status: fixed
blast_radius: platform
symptom: >-
  Dumbbell, kettlebell and gym users had no loaded version of nine movements the library holds only bodyweight or
  barbell (OI-148: Sumo Squat, Split Squat, Walking Lunge, Lateral Lunge, Hip Thrust, Glute Bridge, Sumo Deadlift,
  Romanian Deadlift for kettlebell owners, Russian Twist). The founder approved the nine (2026-11-08) on the condition
  that a loaded version and its original never share a day; no such rule existed (same-day dedup in plan generation is
  by exact NAME only, so a version with a different name would be free to land beside its original). Separately, E010
  Pike Push Up and E045 Romanian Deadlift were core at a level their suitable_for did not list (the step-1A named
  exceptions); the founder ruled (2026-11-09, board d12) to widen suitable_for instead of narrowing core.
concept: same_movement_rule
sot_registry_entry: same_movement_rule
writers:
  - file: scripts/data/library_batch_c_source.json
    method: N14 to N22 source rows (same_movement_as, slot_pattern on N20 only; N19 has none, founder 2026-11-09), criterion_inputs, _meta.derived (scope --write), inputs_sha256 re-pinned
    line: 1
  - file: scripts/add_library_batch_c_v15.js
    method: LINK pass-through (slot_pattern, same_movement_as) in buildRow; the suitable_for kept-row stage
    line: 99
  - file: scripts/data/library_s1b2_suitable_for.json
    method: E010 / E045 suitable_for before / after
    line: 1
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion 22 to 23 (a v23 comment block above it); putAll writes the new rows and rewrites the two by id
    line: 166
readers:
  - file: lib/shared/repositories/exercise_repository.dart
    method_or_widget: queryV4 expands excludeNames with same-movement partners once per call from getAll() (OFF same day, OFF B against A, top-up, L6)
    line: 305
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: pickV4 / _pickCoreList avoid sets (expandLower of previous-phase and upper-day names; plateau not expanded), ON picked set adds the chosen row's partners, ON softFor expanded, topUpDays soft-avoid, universal-pool skip
    line: 659
  - file: lib/shared/repositories/plan_engine/same_movement.dart
    method_or_widget: SameMovement.fromRows / expand / expandLower / partnersOf (pure)
    line: 13
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<library id>] (SeedService v23 putAll by id; custom and community rows are never touched)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: [suitable_for]
contract_test_path: test/contracts/library_s1b2_loaded_versions_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Library Batch S1b-2 (plan docs/plans/2026-11-09-library-batch-s1b2-loaded-versions.md v4, three review rounds): nine
  source rows N14 to N22 copying their original's movement fields and injury tags, each with `same_movement_as`; the
  pure SameMovement helper wired at every live name-keyed set of plan generation (Decision 2's table), the scorecard
  mirrors in lockstep; E010 / E045 suitable_for at every level through a kept-row record stage; seed v23; the cloud
  re-seed migration (nine INSERTs, two suitable_for changes; one live go). E053 Donkey Calf Raise split to S1b-3.
regression_test_planned:
  - test/contracts/library_s1b2_loaded_versions_test.dart
  - test/contracts/same_movement_behavioral_test.dart
  - test/plan_engine_v4/same_movement_test.dart
  - test/plan_generator/same_movement_day_gate_test.dart
  - test/plan_generator/v4_diagnostic_test.dart
  - test/contracts/library_seed_v23_upgrade_behavioral_test.dart
  - test/scripts/library_media_importer_test.dart
  - test/contracts/exercise_library_cloud_seeded_test.dart
related_bugs:
  - f3b8d1  # Library Batch S1b-1, the batch before (seed v22)
  - e9a4b6  # Library Batch S1a: the core-levels record whose stage contract the suitable_for record copies
  - c756b4  # generator step 1A: the level-agreement exceptions E010 / E045 closed here
recurrence: |
  Not a recurrence of a known class: a new rule (no same-movement concept existed). Same-day dedup by name is the
  mechanism the rule rides on; the plan-engine pitfall "the scorecard is green in every world" applied (both mirrors
  changed in the same commit, each with a spot-check that a mutation reddens).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "SameMovement wired at queryV4, the universal pool, the ON picked / soft sets and the avoid sets; behavioural tests per seam; gate OFF and ON over 998 personas; mutations below." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "library_seed_v23_upgrade_behavioral_test.dart drives the real SeedService.seedIfNeeded: a v22 box ends at v23 with the nine rows and the two widened rows, every other row unchanged; a v23 box is not rewritten." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "same_movement_as needs no column (JSON-only, like core_levels); suitable_for is an existing cloud column (backups/live_schema_columns.json)." }
  - { tier: 4, name: postgres_data, status: fixed_in_this_batch, evidence: "Migration 174 applied 2026-11-10 on the founder go (HTTP 201): live read-back 934 rows, 871 active, 63 inactive (was 925 / 862 / 63); content md5 (every column but created_at) fd91c822e22819c993b2ed541620a496, equal to the local docker rehearsal; E010 and E045 suitable_for Beginner, Intermediate, Advanced." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "174_reseed_exercise_library.sql applied via .claude/apply_migration_via_api.js and ledgered in backups/applied_migrations.json (hash sha256:34d0eb60...597c); Gate 14, Gate-MLP and Gate 39 pass." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function code changes; getFormCues reads exercise_library by name and gains nine rows." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job is touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy is touched." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No media: the nine rows carry no media keys (initials in the UI)." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret is touched." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service is touched." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "The library reaches the client through the bundled asset and the seed; the cloud copy serves getFormCues by name." }
impact_analysis: >-
  OFF (every user today): the nine rows enter queryV4 pools and E045 enters beginner pools; the golden is re-recorded
  with every changed key attributed (plan Results). ON (dark): see the plan's Results section.
---

# Library Batch S1b-2: nine loaded versions, the same-movement rule, E010 / E045 suitable_for (b7e2c4)

## What changed
- Nine source rows N14 to N22 (dumbbell / kettlebell versions), each with `same_movement_as` naming its original.
- `SameMovement` (pure) adds a name's partner wherever plan generation checks a picked name; per-exercise preferences
  (demoted, plateau) are not expanded.
- E010 Pike Push Up and E045 Romanian Deadlift `suitable_for` at every level; the step-1A exceptions are gone (the gate
  now fails any picked row whose `core_levels` lie outside its `suitable_for`).
- Seed v23; the cloud seed generator takes a list of kept-row records and the batch's new-row ids.

## Mutation evidence (rule 21)
| mutation | applied | red |
|---|---|---|
| queryV4 expansion removed | count 1 | same_movement_behavioral 4 red (1, 2, 4, 6) |
| universal-pool skip reverted | count 1 | same_movement_behavioral 1 red (5) |
| ON picked partners removed | count 1 | same_movement_behavioral 1 red (3) |
| helper one-directional (partner to original only) | count 1 | same_movement_behavioral 4 red |
| demoted names expanded (wrongly) | count 1 | same_movement_behavioral 1 red (7, the mirror) |
| QueryV4Mirror left unexpanded | count 1 | v4_diagnostic 1 red |
| tracer universal-pool skip reverted | count 1 | v4_diagnostic 1 red |
| importer LINK removed | count 1 | library_media_importer 7 red (the LINK group and every byte-for-byte case) |
| N19 out of the Dart safe pool | count 1 | injury_recheck_v14 1 red |
| N14 `same_movement_as` pointed at a missing id (library) | json edit | library_s1b2_loaded_versions 2 red |
| E045 `suitable_for` back to `before` (library) | json edit | library_s1b2_loaded_versions 2 red |
| N14 `equipment_tier` off its equipment (library) | json edit | library_s1b2_loaded_versions 1 + equipment_tier_consistency 1 red |
| N16 injury tags short by one (library) | json edit | library_s1b2_loaded_versions 1 red |
| gate: queryV4 expansion removed | count 1 | same_movement_day_gate OFF red (ON green) |
| gate: ON picked partners removed | count 1 | same_movement_day_gate ON red (OFF green) |

Every mutated file restored byte-identical (`cmp`).
