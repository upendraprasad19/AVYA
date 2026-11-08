---
bug_id: c756b4
date: 2026-11-08
batch: generator-step1-core-list
status: fixed
blast_radius: platform
symptom: >-
  The 2,304-plan audit (2026-11-08, main 0633a121; 4 goals x 3-6 days x 3 levels
  x 4 tiers x 30/45/60/90 min x phases 1-3, no injuries) found that the core-list
  pool (enable_core_list_pool, ship-dark, OFF) ranks rows with no notion of the
  user's equipment. Barbell Overhead Press (E011) and Pike Push Up (E010) tie on
  every sort key and E010 wins on id, so 56 of 56 Strength 4-day gym OHP Days held
  Pike Push Up ON (36 of 56 live). Equipped users' isolation slots kept household
  rows where a loaded row fits (Sliding Leg Curl in 58 full-gym plans), and plans
  with an unloaded pick where a loaded row fits were 1,505 ON (1,700 live). Board
  OI-484.
concept: core_list_pool
sot_registry_entry: core_list_pool
writers:
  - file: lib/shared/repositories/plan_engine/core_list_selector.dart
    method: CoreListSelector.rankedPool (order keys and the new R3 (a) like-for-like reduction, step 4b; R3 (b) fit key)
    line: 192
readers:
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: _pickCoreList hands r.ordered to _selectCandidate, whose _preferNovel returns the first row NOT in the avoid set (previous phase, plateau, upper-day feeders, B's soft avoid, demoted)
    line: 846
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: _preferNovel
    line: 1614
hive_key_prefix: exerciseBox
hive_key_formula: "read only: rankedPool reads the library rows; nothing is written to Hive"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/core_list_pool_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Generator step 1A R3 (docs/plans/2026-11-08-generator-step1-core-list.md v6).
  (a) In an implement user's isolation slot whose pattern is neither one of the
  implement patterns nor core, REDUCE the pool to like-for-like implement rows
  (exercise_type isolation, first primary muscle names the slot's muscle, calf heads
  gastrocnemius / soleus) when one exists; a partition, because an ordering key
  cannot keep a row out once _preferNovel walks past the top row. (b) In non-core
  compound slots, a key before priority_tier: a row using a non-household item the
  user has sorts first. Both inside the ship-dark pool; OFF is byte-identical.
regression_test_planned:
  - test/contracts/core_list_pool_behavioral_test.dart
  - test/contracts/core_list_like_for_like_data_test.dart
  - test/plan_generator/core_list_pool_gate_test.dart
  - test/plan_generator/generator_golden_test.dart
related_bugs:
  - c1d7a4  # Batch C1: the core rows the pool needs (data side of the same pool)
  - d3a8f5  # equipment tier as a curation hint, capability as the safety check
  - b1c4e7  # capability floor on the name paths
recurrence: |
  Not a recurrence. Prior equipment bugs (d3a8f5, a9e3c7, b6f4d1, f7b2c4) were
  SAFETY leaks: a user prescribed a row needing equipment they lack. This one is
  the opposite direction inside an already-safe pool: no preference for the
  equipment the user has. The OI-387/388 improvised filter covered five patterns (vertical_push joins them in 1A v7);
  the gap was every other pattern and every compound slot. Searched INDEX.md for
  core list, equipment, improvised, self-resisted, tie / row order, queryV4 sort.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "core_list_selector.dart rankedPool steps 4b and the fit key; trace field likeForLikeImplement. Behavioral tests (R3 (a) and (b) groups) and the data contract core_list_like_for_like_data_test.dart; mutations recorded below." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "rankedPool is pure over the exerciseBox rows; nothing is written. With the flag OFF (the shipped default) pickV4 never calls it: the 998-persona golden is unchanged." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No cloud column involved; the plan is generated locally." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud data involved." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Plan generation is local Dart." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Real PlanGenerator.generateV4 over the 2,304-plan grid, OFF and ON (test/plan_generator/plan_audit/), and the 998-persona gate; numbers below." }
impact_analysis: >-
  None for users today: the pool is OFF (ship-dark) and OFF is byte-identical
  (golden, 998 personas). Under the flip (Unit 1B) an equipped user gets a loaded
  press, curl or calf raise where one exists. Named coaching consequences: the
  full-gym hamstring curl becomes a machine curl, not Sliding Leg Curl; a one-row
  reduced pool makes variant B and phase 2 repeat that row (reported per cell).
---

# The core-list pool ignored the equipment the user has

Plan: `docs/plans/2026-11-08-generator-step1-core-list.md` (v6, six context-blind review rounds). Board: OI-484. Sibling diagnose: `2026-11-08-core-list-blockers-44d40a.md` (OI-485).

## What was wrong

`CoreListSelector.rankedPool` sorts by demoted, soft-avoid, phase-1 foundational, sub-focus, exercise type, `priority_tier`, foundational, then id. Nothing reads the user's equipment beyond the hard `canPerform` filter, so Pike Push Up (bodyweight) and Barbell Overhead Press tie on every key and the lower id wins. The improvised filter (OI-387/388) removes household rows only in five arm, shoulder and pull patterns. A key alone was then not enough for `vertical_push` (plan v7): once variant B avoided the loaded press, `_preferNovel` walked to the foundational Pike Push Up, so `vertical_push` joined the implement patterns.

## Why a key was not enough for (a)

`_pickCoreList` passes the ordered pool to `_selectCandidate`, and `_preferNovel` returns the first row that is not avoided. Variant B avoids A's pick; phase 2 avoids the previous phase's. A household row sorted last is still picked once the rows above it are avoided. Only removing it from the pool keeps it out, so R3 (a) is a reduction. A key is enough for (b) because a compound slot's alternatives are all acceptable lifts; the key only decides which comes first.

## Mutation proof

Each mutation was applied by a script that asserted the target string occurred exactly once and that the file changed, ran `core_list_pool_behavioral_test.dart` and `thin_day_topup_behavioral_test.dart` (round 2 also the data contract), and restored the file from a saved copy; `cmp` against the copies was clean afterwards. No mutation was a compile error.

| # | Mutation (`core_list_selector.dart`) | Red tests |
|---|---|---|
| M05 | R3 (a) reduction off (`if (false && ll.isNotEmpty)`) | 2 |
| M06 | calf head table off | 3 |
| M07 | `namesMuscle` prefix match instead of equality | 3 |
| M08 | drop the isolation-type condition of like-for-like | 0 in round 1 (survivor: no fixture row was a compound implement row listing the muscle first); a test was added ("a compound implement row that lists the muscle first is not like-for-like"), round 2 below |
| M09 | R3 (a) applies to `core` slots too | 2 (incl. the OI-386 obliques pick) |
| M10 | R3 (b) fit key off | 3 |
| M11 | fit key moved after `priority_tier` | 1 |
| M12 | fit key applies to `core` slots too | 1 |

Round 2 (after the M08 test and the data contract `core_list_like_for_like_data_test.dart`, 31 recorded cells, were added): M08 2 red (the new test and the data contract), M05 4, M06 5 (each also reddens the data contract). 19 of 19 mutations across both docs are now red.

## Measured

The 2,304-plan audit (`test/plan_generator/plan_audit/`, `PLAN_AUDIT_OUT` set), the pool forced ON, before (main
0633a121) and after this batch (plan v7):

| measure | live (OFF) | ON before | ON after |
|---|---|---|---|
| plans with a household substitute while the user has real equipment | 1,466 | 58 | 44 |
| plans with an unloaded pick where a loaded row fits | 1,700 | 1,505 | 468 |
| Strength 4-day gym OHP Day with Pike Push Up | 36 of 56 | 56 of 56 | 0 of 56 |

Largest pick changes in the ON world (day-weeks, all weeks): Pike Push Up -> Barbell Overhead Press 3,988, ->
Dumbbell Shoulder Press 1,304, -> Arnold Press 1,022; Glute Kickback -> Glute Kickback (Cable) 1,592; Standing
Single Leg Curl -> Dumbbell Lying Hamstring Curl 336; Incline Pike Push Up -> Dumbbell Seated / Single Arm Shoulder
Press 384; Donkey Calf Raise -> Band Single Leg Calf Raise 80; Front / Goblet Squat -> Leg Extension 48 (the
isolation slot now holds an isolation row). The full table is in plan section 7. The v7 partition moved 24
home_dumbbells advanced phase-1 plans from Pike Push Up to a dumbbell press; one of them (build_muscle 3-day 30 min)
now has a week-2 Chest zero, because Pike Push Up credited Chest and the dumbbell press does not: a set-allocation
gap of the step-2 allocator (OI-475), not of the ranking. The 44 improvised and 468 unloaded residues are rows
the R1 data and the 1B equipment variants (OI-148) address; OFF is unchanged (golden green).
