---
bug_id: 44d40a
date: 2026-11-08
batch: generator-step1-core-list
status: fixed
blast_radius: platform
symptom: >-
  The 2,304-plan audit (2026-11-08, main 0633a121) run with the core-list pool ON
  found it worse than the live generator on three counts that block its flip:
  plyometric rows (E193 Jump Squat, G3582 Lunge with Jump) appeared 1,273 times in
  week 1, 573 as the day's lead lift, because for advanced home and bodyweight users
  they were the only core-list knee_dominant rows; week-1 days opening with a
  non-compound rose from 4 plans to 310 (445 days, every one E193, typed
  calisthenics); plans with a major muscle at 0 sets in weeks 1-3 rose from 84 to
  309, mostly hamstrings, because every bodyweight hamstring row is core at beginner
  only. Also: the thin-day top-up used the OFF candidate rules under the pool, so an
  injured user's day could gain retired rows; and the gym Glutes hinge slot took
  E021 Deadlift over E047 Hip Thrust on an id tie. Board OI-485.
concept: core_list_pool
sot_registry_entry: core_list_pool
writers:
  - file: lib/shared/repositories/plan_engine/core_list_selector.dart
    method: CoreListSelector.rankedPool (R2 jump partition step 3b; R5 glute-first last key)
    line: 192
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method: topUpDays / _topUpVariant (R4 coreListOnly, two-pass ladder)
    line: 1193
  - file: assets/data/exercise_library.json
    method: core_levels of the R1 rows (founder-signed data; see the closure ledger)
    line: 1
readers:
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: _pickCoreList -> _selectCandidate -> _preferNovel (first row not avoided)
    line: 846
  - file: lib/shared/repositories/plan_engine/periodization_engine.dart
    method_or_widget: apply reads exercisesA weeks 1 and 3, exercisesB weeks 2 and 4 (a topped-up or re-picked B is what the user sees)
    line: 87
hive_key_prefix: exerciseBox
hive_key_formula: "read only: rankedPool and queryV4 read the library rows; nothing is written to Hive"
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
  Generator step 1A (docs/plans/2026-11-08-generator-step1-core-list.md v6). R2:
  jump rows (high_impact or discipline plyometric) leave a mixed pool before the
  improvised filter; a jump-only pool is kept. R5: in Glutes hip_dominant slots a
  glute-first row wins the LAST tie (gym Glutes E047 Hip Thrust; Hamstrings keeps
  E021). R4: topUpDays takes a REQUIRED coreListOnly; on the ON paths the ladder
  runs core rows first (at the user's level or easier), then today's ladder with a
  fresh memo, so the floor of 3 holds. R1 (data): the missing advanced home and
  bodyweight squat, hinge, curl and calf rows go on the core lists once the founder
  signs the table, with the R9 gate zeros (i) and (iv). All inside the ship-dark
  pool; OFF is byte-identical.
regression_test_planned:
  - test/contracts/core_list_pool_behavioral_test.dart
  - test/contracts/thin_day_topup_behavioral_test.dart
  - test/plan_generator/core_list_pool_gate_test.dart
  - test/plan_generator/generator_golden_test.dart
  - test/plan_generator/plan_audit/plan_audit_lib_test.dart
related_bugs:
  - c1d7a4  # Batch C1 core rows (the data the pool depends on)
  - 2d04d7  # thin-day top-up (R4 changes its ON-path candidates)
  - b1c4e7  # capability floor on name paths
recurrence: |
  Not a recurrence of a fixed class. c1d7a4 added missing core rows for the levels
  measured then; the advanced home knee row and the bodyweight hinge rows above
  beginner were never on a list (a data gap the 998-persona gate did not measure as
  a jump pick: it counted high-impact picks as reported, not gated). The top-up
  question (2d04d7, R9 of its plan) was reserved for the flip review and is answered
  here. Searched INDEX.md for core list, jump squat, plyometric, high impact,
  thin day / top-up, glute, hinge.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "core_list_selector.dart R2 and R5; exercise_selector.dart R4 (topUpDays coreListOnly required; three callers). Behavioral tests and mutations recorded below." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Both stages read exerciseBox only. With the flag OFF the cascade exit passes coreListOnly false and buildPinnedDays short-circuits to false: the 998-persona golden (including the 24 injury personas that exercise the OFF top-up) is unchanged." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No cloud column involved." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud data involved; the cloud library reseed for R1 belongs to the data commit and is listed in the closure ledger." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this commit." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Plan generation is local Dart." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Real PlanGenerator.generateV4 over the 2,304-plan grid OFF and ON, the 998-persona gate, and the multi-injury sweep; numbers below." }
impact_analysis: >-
  None for users today (the pool is OFF; golden unchanged). Under the flip a jump
  row never leads a strength slot while a non-jump row exists, the gym Glutes
  hinge is a hip thrust, and an injured user's topped-up day prefers core rows.
  The floor of 3 is unchanged by construction (pass 2 is today's ladder).
---

# The core-list pool's own defects: jump squats, glute ties and the top-up

Plan: `docs/plans/2026-11-08-generator-step1-core-list.md` (v6). Board: OI-485. Sibling: `2026-11-08-core-list-equipment-fit-c756b4.md` (OI-484).

## What was wrong

1. **Jump rows as the main squat.** E193 Jump Squat and G3582 Lunge with Jump are core at intermediate / advanced, and for an advanced home or bodyweight user they were the only core knee_dominant rows. `typeFor` types E193 (`calisthenics`) by the slot, and the sequencing engine then opened 445 week-1 days with it.
2. **Zero-hamstring weeks.** Every bodyweight hamstring row is core at beginner only, so an intermediate or advanced bodyweight user's hamstring slots dropped (data, R1).
3. **Glutes hinge tie.** E021 Deadlift and E047 Hip Thrust tie on every key in a gym Glutes hip_dominant slot; E021 won on id.
4. **The top-up under the pool** used queryV4's OFF rules, so an injured user's day could gain a retired row (E261, E271 in the gate's ratchet).

## The R4 note (it changes injured users' top-up under the pool)

Pass 1 keeps only candidates core at the user's level or an easier one (the Ruling 12 emergency's rule); pass 2 is the unchanged ladder with a fresh memo. The reachable candidates depend on the day's anchor patterns, not on what was picked, so both passes together fill to the same count as before; only the choice moves toward core rows. The OFF path passes `false` and is byte-identical.

## Mutation proof

Same script and restore check as in c756b4 (the sibling doc). No mutation was a compile error.

| # | Mutation | Red tests |
|---|---|---|
| M01 | R2 partition off | 4 in round 1; round 2 below |
| M02 | keep-a-jump-only-pool off (`if (jumps > 0)`) | 5 (the jump-only test and four ON-world real-data tests whose slots emptied) |
| M03 | `isJumpRow` `||` to `&&` | 2 |
| M04 | R2 moved after the improvised filter | 1 |
| M13 | R5 glute key off | 2 |
| M14 | R5 moved before `priority_tier` | 1 |
| M15 | R4 pass 1 off | 4 |
| M16 | R4 memo not reset for pass 2 | 5 |
| M17 | `isCoreAtOrEasier` `<=` to `==` | 1 |
| M18 | the `_pickCoreList` exit passes `false` | 1 |
| M19 | `buildPinnedDays` passes `false` | 1 |

Round 2 (after the "R2 through the real pick" group was added): M01 6 red, including "variant B repeats the squat rather than take the jump row" and "phase 2 with the squat in the avoid set keeps the squat", the two cases where `_preferNovel` would walk past an ordering key. The real-data test "Strength 4-day home_dumbbells intermediate Squat Day holds no jump row" stays GREEN under M01: that persona's Squat Day picks no jump row even without the partition, so it is a guard, not a proof; the advanced home case that does pick E193 needs the R1 data and is gated by R9 (i) in the R1 commit.

## Measured

Gate report (998 personas, 576-run sweep): the R4 top-up retired additions went from E271 x4 and E261 x8 (2
personas) to none; gate mutation G3 (R4 pass 1 off) brings E271 and E261 back. Box Jump picks 24 -> 0, Jump Squat
726 -> 682, Lunge with Jump 288 -> 288; Romanian Deadlift 992 -> 706 (R5). Over the 2,304-plan audit (pool forced
ON) R5 moved Romanian Deadlift -> Hip Thrust in 908 day-weeks and Deadlift -> Hip Thrust in 480, and Bodyweight Good
Morning -> Single Leg Glute Bridge in 260.

What does NOT move without the R1 data (founder signature pending, ledger `S1A-R1-DATA`): week-1 jump rows stay
1,273 (573 leads) and isolation-first plans 310, because every remaining jump pick sits in a jump-only pool that R2
keeps on purpose; zero-hamstring weeks stay (322 bodyweight muscle-weeks worse than the live twin). Weeks with a
major muscle at 0 sets went 309 -> 330: 21 week-2 Quads zeros where R2 removed Box Jump (it credited Quads) from the
variant-B Calves slot and the B Quads slot is not seated at 30 minutes, plus one Chest zero from the v7 Pike removal;
both are the step-2 allocator (OI-475 board text). R6: `emergencyAnyLevel` 2 personas and 40 sweep runs, `refilled`
16, sweep retired ids E261 only (was E271, E261, E254, E234); full detail in plan section 7.
