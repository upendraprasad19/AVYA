---
bug_id: 2d04d7
date: 2026-10-24
batch: thin-day-topup
status: fixed
blast_radius: platform
symptom: >-
  An injured user's generated day could hold one or two exercises, or none. After
  the v14 injury tags (d30de7) the real generator, flag OFF, produced 74 thin days
  (under 3 exercises) and 19 one-exercise days across 1,728 single-injury runs at
  3 and 5 days; pairs of injuries produced 4 empty days at 3 and 5 days and 6 at 4
  and 6 days; a repeat phase left 768 thin and 310 one-exercise days. The cause is
  the safe-omission rule: the cascade drops a slot when no safe candidate exists,
  and nothing refills the day afterwards. A repeat phase drops now-contraindicated
  pins and refills only a variant that is EMPTY, so a variant left with one or two
  survivors stays thin. Founder decision 2026-10-23 (option b, OI-401): top the day
  up with safe moves for its own muscles from a neighbouring movement type, then
  safe core moves, then stop.
concept: thin_day_topup
sot_registry_entry: thin_day_topup
writers:
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method: topUpDays and _topUpVariant, called at the three places a day list leaves the selector (pickV4 cascade end, the B1 _pickCoreList return, buildPinnedDays end)
    line: 1129
  - file: lib/shared/repositories/plan_engine/thin_day_topup.dart
    method: ThinDayTopUp floor, neighbours, applies, anchors (pure rules)
    line: 1
  - file: lib/shared/repositories/plan_engine/plan_engine_flags.dart
    method: thinDayTopupEnabled (configBox disable_thin_day_topup, default ON)
    line: 495
readers:
  - file: lib/shared/repositories/plan_engine/plan_generator.dart
    method_or_widget: generateV4 calls ExerciseSelector.pickV4 (fresh phase) or buildPinnedDays (repeat phase); plan_generator.dart itself is NOT edited (rule 14)
    line: 184
  - file: lib/shared/repositories/plan_engine/periodization_engine.dart
    method_or_widget: apply reads exercisesA on weeks 1 and 3 and exercisesB on weeks 2 and 4 (useB), so a topped-up B is what the user sees in weeks 2 and 4
    line: 87
hive_key_prefix: exerciseBox
hive_key_formula: "read only: queryV4 over exerciseBox (the library); the stage writes nothing to Hive"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/thin_day_topup_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  A post-pass ExerciseSelector.topUpDays on the finished day list at the three
  exits, per variant under ThinDayTopUp.floor (3), injured users only. Stages: the
  day's own (muscle, pattern) anchors in slot-priority order, own pattern before
  its neighbours (ThinDayTopUp.neighbours), rounds until the floor or no progress;
  then core; then stop. Every query is the cascade's own queryV4 (injury,
  capability, exclusions, experience), so no contraindicated or unperformable pick
  is possible, and phase 1 asks for foundational rows first. The avoid sets are
  soft (previous phase, plateau, the other variant) and lower-cased; L6 demoted
  names leave the candidate pool unless they are all that is left.
  Kill-switch disable_thin_day_topup, default ON. Uninjured users get the same
  list instance back. The exercise-seam allowlist moves 16 to 17 (one queryV4
  call site).
regression_test_planned:
  - test/contracts/thin_day_topup_behavioral_test.dart
  - test/plan_engine_v4/thin_day_topup_test.dart
  - test/plan_engine_v4/thin_day_topup_flag_test.dart
  - test/plan_generator/injury_floor_sweep_test.dart
  - test/plan_generator/generator_golden_test.dart
related_bugs:
  - d30de7  # the v14 tags that exposed the thin days (the cost it named)
  - a1f6c3  # injury filter non-functional (the filter whose safe omission this answers)
recurrence: |
  Not a recurrence of a prior bug class. d30de7 named thin days as the cost of a
  correct tag and handed them to OI-401; the safe-omission rule itself (the
  cascade drops a slot rather than hand an injured user a tagged move) has been
  deliberate since U2. This fix does not weaken it: every added move comes
  through the same injury filter.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "exercise_selector.dart topUpDays/_topUpVariant, thin_day_topup.dart, plan_engine_flags.dart thinDayTopupEnabled, scripts/exercise_seam_lib.dart 16 to 17. Tests: thin_day_topup_test (pure rules), thin_day_topup_flag_test (no-Hive default and box), thin_day_topup_behavioral_test (real generateV4 personas plus direct calls on a seeded library)." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "The stage reads exerciseBox through queryV4 and, in phase 2+ on a thin day, scans schedule_* rows once via TrainingHistoryAnalyzer.demotedExercises. It writes no Hive key. Stored plans are not rewritten: pre-launch, every account is a testing account (CLAUDE.md section 1); a regenerated plan gets the top-up." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No cloud column involved; the plan is regenerated locally." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud data involved." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Plan generation is local Dart; no Edge Function touches it." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Real PlanGenerator.generateV4, flag OFF (the path users get), the five sweep blocks (7,200 runs); see the measured tables below. The final-code sweep is recorded in the measured section below." }
impact_analysis: >-
  Injured users only. A day under 3 exercises gains safe moves; no existing pick
  is removed or reordered. Uninjured users: topUpDays returns the same list
  instance, proved by an identical() test on hand-built thin days and by the
  generator golden (the 974 non-injury keys do not change). Two golden keys
  change (injury|shoulder|bodyweight|build_muscle|4d|intermediate|p1 and |p2).
  The shipped default is ON with a device-local kill-switch and no remote
  rollback (Ruling R3 of the plan); the exposure is concentrated: Plank (48) and
  Dead Bug (20) are all 68 core top-ups in the probe, both tagged [] and both in
  the founder-approved untagged safe pool of PR 155.
---

# A day the injury filter thinned to one or two exercises

Plan: `docs/plans/2026-10-24-thin-day-topup.md` (r3, converged after two context-blind review rounds). Board: OI-401 (this fix), OI-408 (the residual it leaves).

## What was wrong

`_cascadeFill` drops a slot when no safe candidate exists (the safe-omission rule, U2), and `pickV4` never refills the day. `buildPinnedDays` (the repeat-phase path) drops pins that are now contraindicated and refills a variant only when it is EMPTY, so a variant left with one or two survivors stays thin. The v14 injury tags (d30de7) put many more rows behind the filter, so the omission, always possible, became common: a shoulder-injured bodyweight user lost every safe press.

## Measured before and after

Real `PlanGenerator.generateV4`, B1 flag OFF, the five blocks of `test/plan_generator/injury_floor_sweep_test.dart` (7,200 runs): the 9 single injuries (3 and 5 days at phases 1 and 3, 4 and 6 days at phase 1), the 15 pairs of knee/shoulder/lower_back/wrist/elbow/hip (phase 1, 3 to 6 days), the repeat phase for each single (phase 2 with phase 1's names pinned, 3 to 6 days); no exclusions, no history, no plateau names, weeks 1 and 2 scanned.

| block | empty / thin(<3) / one-exercise BEFORE (main `1f1ea306`) | AFTER prototype 1 | AFTER prototype 2 (the design shipped) |
|---|---|---|---|
| singles 3 and 5 days | 0 / 74 / 19 | 0 / 0 / 0 | 0 / 0 / 0 |
| singles 4 and 6 days | 1 / 75 / 13 | 0 / 0 / 0 | 0 / 0 / 0 |
| pairs 3 and 5 days | 4 / 531 / 197 | 0 / 2 / 0 | 0 / 2 / 0 |
| pairs 4 and 6 days | 6 / 647 / 241 | 0 / 6 / 0 | 0 / 6 / 0 |
| repeat phase 3 to 6 days | 0 / 768 / 310 | 0 / 0 / 0 | 0 / 0 / 0 |

- Unsafe picks 0 and unresolved names 0 in every block for both prototypes. The prototypes carried no equipment oracle, no duplicate counter and no kill-switch; the final code's `unperformable` and `duplicates` counters are gated at 0 in the sweep (Task 3).
- The residual is identical in both prototypes: 8 scan days, all shoulder + lower_back, bodyweight, beginner (the 5-day build_muscle plan, and the 6-day lose_fat, strength and general_fitness plans), each holding `Plank, Dead Bug`. A scan day is one day in week 1 or week 2, so these are 4 runs with one short day each. The cause is `VolumeFilter.targetCount('beginner', 5|6)` = 4, which trims the day before the selector runs, plus the founder's "then stop". Filed as OI-408.
- What the top-up adds (singles 3/5 days plus shoulder + lower_back at 3 to 6 days, 1,056 runs): 63 runs (6%) get any top-up. Prototype 1 (neighbour then core): 41 neighbour adds, 106 core adds (72% core). Prototype 2 (own pattern, neighbour, core): 49 own, 30 neighbour, 68 core (46% core). Most picked: Plank 48, Dead Bug 20, Reverse Fly 17, Bodyweight Rear Delt Raise 11, Wall Triceps Press 8, Reverse Lunge 8, Doorframe Curl 8.
- Repeat phase (phase 2, 1,728 runs): 302 runs (17%) get a top-up: 783 own-pattern adds, 189 neighbour, 93 core. 2,055 of 15,552 scanned days sit at exactly 3 after the top-up (13%, against 2.0% in singles): a pinned plan keeps its slots, so its dropped pins are mostly refilled from the same pattern, and 3 is where the floor stops.
- Generator golden: 2 keys change for both prototypes (`injury|shoulder|bodyweight|build_muscle|4d|intermediate|p1` and `|p2`); the 974 non-injury keys and the 22 other injury keys do not (998 in all).
- Widest generator test set (46 minutes), prototype 1: 6,562 passed, 4 skipped, 1 failed, the golden's 2 keys.
- **Final code, the same sweep file** (Task 3, 2026-10-24): every block passes. empty / thin / one-exercise: singles 3/5 days 0 / 0 / 0; singles 4/6 days 0 / 0 / 0; pairs 3/5 days 0 / 2 / 0; pairs 4/6 days 0 / 6 / 0; repeat 0 / 0 / 0. Unsafe main 0, unsafe warm-up/cool-down 0, unresolved 0, `unperformable` 0, `duplicates` 0 in every block. All thin days are the OI-408 persona (`shoulder+lower_back|shoulder+lower_back`).
- **The kill-switch reproduces main exactly.** The same file run with `disable_thin_day_topup` set gives the BEFORE column to the digit (0/74/19, 1/75/13, 4/531/197, 6/647/241, 0/768/310), with `unperformable` 0 and `duplicates` 0, so those two counters were also clean on main.
- **Time, back to back, solo, same machine state:** five-block sweep 12:02 on the final code against 10:51 with the kill-switch set (the main path), +11%; under the 14-minute split threshold, so the sweep stays one file. Per block (final / switch set): singles 2:52 / 2:17, singles46 1:24 / 1:16, pairs 2:37 / 2:27, pairs46 3:09 / 2:58, repeat 2:00 / 1:53. Heaviest persona (shoulder + lower_back, bodyweight, beginner, 6-day lose_fat, 40 plans each, two rounds): 160 and 165 ms per plan with the switch set, 284 and 285 ms with the top-up, so about +124 ms (+78%) in the worst case on this machine; plan generation runs on the UI isolate (preview and phase advance), so a phone will take a multiple of that. Earlier runs for reference: 10:11 solo on main, 27:02 in the loaded full-suite run, 15:40 prototype 1, 17:21 prototype 2.

## The decision

Founder, 2026-10-23, option (b): a day with fewer than 3 exercises is topped up with safe moves for that day's own muscles from a neighbouring movement type, then with safe core moves, then stop. The plan's rulings R1 to R10 record the choices the founder did not make (floor, trigger, live-with-kill-switch, three exits, candidate rules, soft avoid, scorecard blindness, the residual, B1 ON, the seam count).

## Persona preconditions

Each real-library test first asserts the thin day with `disable_thin_day_topup` set, so a persona that stops being thin fails loudly instead of passing vacuously: shoulder bodyweight advanced 4-day (week-2 "Chest, shoulders, triceps" empty); knee+hip bodyweight intermediate 3-day (week-2 "Quads, hamstrings, glutes" empty); elbow bodyweight lose_fat beginner 6-day repeat (one surviving pin on "Upper pull + conditioning"); shoulder bodyweight beginner 5-day with B1 ON ("Chest focus" thin); wrist bodyweight intermediate 5-day with towel and doorway excluded (the unexcluded top-up adds a towel move); shoulder home_dumbbells beginner 5-day (the core top-up is Plank, not Farmers Carry).

## What the full suite found (2026-10-24)

The complete local `flutter test` on `bb366796` (43 minutes, `TZ=Asia/Kolkata`): 10,707 passed, 27 skipped, 2 failed. The widest generator set had run green apart from the golden's 2 keys; these two were outside it.

1. `core_list_pool_behavioral_test.dart` "injured user keeps the soft avoid and L6". The one-slot day is now topped up to three, which is the feature. It also exposed a real gap in the top-up: with the injury-substitute preference on, `_selectCandidate` narrows the pool to the curated subs before any soft avoid, so a swapped-out curated sub (`Machine Chest Press`) was topped back in while other safe rows existed, after the cascade's own L6 post-pass had run. Fixed by taking demoted names out of the candidate pool unless they are all that is left (plan R11). The original test now pins the pool pick as the first entry and the top-up size; the regression is in `thin_day_topup_behavioral_test.dart` ("demoted + the injury-substitute preference (L6)", control first).
2. `core_list_pool_gate_test.dart` "ON hard counts are 0: extra". 16 built rows (E234 Floor Press, E261 Bodyweight Rear Delt Raise, E271 Wall Triceps Extension) in shoulder-injured bodyweight and home-dumbbells 4-day personas are retired in B1's sense (no core level, no variant family) because the top-up reads the OFF-path candidates (plan R9). R9 had predicted green and said to record a red as evidence without repointing the gate; a red test cannot merge (rule 20), so plan R12 keeps the gate on the shipped combination, keeps B1's own picks and any skill/olympic row hard, and attributes top-up additions by re-running a flagged persona with the kill-switch set. The three ids are pinned exactly (`_r9TopUpRetired`); the open question (core-list-only under B1?) is on the `enable_core_list_pool` entry of `docs/ship_dark_pending_review.yaml`.

Class: both are "a new post-pass handles a rule an existing pass enforces": its own tests seeded no curated subs and no B1-ON persona with a retired-only safe pool, so only the sibling's tests could see it (`feedback_mistake_guard_without_its_mirror.md`, instance 43).

## Mutation proof

Each mutation was applied once, confirmed applied (the file differed from the saved copy), run against the three new test files (the gate file for M17x; the sweep's singles block as well for M2, M10b and M11), and restored from a saved copy with the sha1 verified; `git status` under `lib/` and `test/` was empty afterwards. 29 of 29 applied, none survived, none was a compile error.

| # | Mutation | Red tests | Sweep singles block |
|---|---|---|---|
| M1 | floor 3 to 0 | 31 | - |
| M2 | drop `injuryExclusions` from the query | 8 | 1 red |
| M3 | delete the early return and the `injuries.isNotEmpty` clause of `applies` | 2 | - |
| M4 | drop the alias branch (`b = a`) | 2 | - |
| M5a | drop A's names from B's avoid set | 2 | - |
| M5a2 | drop the lower-casing of A's names in B's avoid set | 2 | - |
| M5b | drop previous-phase names | 1 | - |
| M5c | drop plateau names | 1 | - |
| M5d | drop the demoted pool filter (L6) | 2 | - |
| M5e | drop B's names from A's avoid set | 1 | - |
| M5f | invert the strength check for A only | 2 | - |
| M6 | drop the core stage | 7 | - |
| M7 | remove the `buildPinnedDays` call | 3 | - |
| M8 | remove the `_pickCoreList` call | 1 | - |
| M9 | ignore the kill-switch | 10 | - |
| M10 | capability null and exclusions `{}` | 3 | - |
| M10b | capability null and `equipmentTier ''` | 8 | 1 red |
| M11 | drop `excludeNames: picked` | 10 | 1 red |
| M12 | swap the stage order (core first) | 4 | - |
| M13 | use `slotsA` for B | 2 | - |
| M14 | drop the length guard | 1 | - |
| M15 | drop the own-pattern query (neighbours only) | 13 | - |
| M16 | drop the foundational try-first | 4 | - |
| M18 | demoted filter without the sole-candidate fallback | 1 | - |
| M17a | gate: ignore the without-top-up attribution | 1 | - |
| M17b | gate: a skill id the top-up added becomes evidence | 1 | - |
| M17c | gate: skip the re-run block entirely | 1 | - |
| M17d | gate: the re-run does not set the kill-switch | 2 | - |
| M17e | gate: delete the re-run statement only | 1 | - |

Two of my own mutation-run mistakes, recorded because they would have misled the table: the runner's result parser missed the failure count when a skipped-test marker sat between the pass and fail counts (`+9 ~1 -1`), so M17a and M17b first showed 0 red although each had reddened exactly the test written for it; and M17c (the whole block skipped) was a true survivor until the R9 test also asserted that an attribution re-run happened (`attributionReruns > 0`) and the block gained a fail-closed check for a re-run that built nothing (M17e).

The exhausted-key memo is a pure performance cache and the idempotence assertion guards a future change; neither has a mutation.
