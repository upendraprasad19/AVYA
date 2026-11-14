---
bug_id: c7e5a1
date: 2026-11-14
batch: generator-step2c
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-475 L2 / L3 (step 2 of the generator overhaul, unit 2C-a): a build_muscle 3 / 4 / 5-day plan trained Quads once a
  week, and a squat on that day spent the Glutes session cap, so later quad rows were refused. Measured over the
  2,304-plan audit (main c6b1ee48, one credit rule on both sides): 384 / 336 build_muscle plan-weeks at 60 / 90 minutes
  sat under the Quads band bottom; week 1 repeated names 74 / 86 / 320 times in the 3 / 4 / 5-day plans
  (intermediate / advanced, 60 / 90 minutes); Glutes from hip and glute exercises alone sat under the band bottom in
  every cell. Second defect, found while building the repeat-pin protection: `repeatPinsFrom` trusted the stored
  `last_phase_profile`, which Edit Profile's reschedule never rewrites. Rows with a `workout_day_index` past the new
  plan's days, or rows of another split, could be pinned into frames they do not match.
concept: balanced_week
sot_registry_entry: balanced_week
contract_test_path: test/contracts/balanced_week_behavioral_test.dart
related_bugs: [cf970c, cb50cb, d4a7e2, b3f1d8]
recurrence: |
  Not a recurrence. The Quads under-dose is the class 1B-Q (cf970c, OI-475 L1) began: it gave the B leg day a
  priority-1 quad compound and left L2 (the credit) and L3 (a second quad day) to this unit. OI-454 (the 6-day Legs B
  quad slot and its credit) is the rule widened here; its golden lesson (cb50cb: a global credit rule moved 745 of 999 keys) is
  why the widening is limited to the balanced week. The repeat-pin defect has no prior instance. Bug-history lookup
  (CLAUDE.md 4.1.5): grep of docs/diagnoses for "last_phase_profile", "repeatPinsFrom", "repeat pin", "workout_day_index"
  and "reschedul" (token and concept). The hits (c3e9a4, d4b8e1, b1c4e7, c2d5e8, d30de7, c1d7a4) cover the custom strip
  and the injury filters on repeat pins. None covers a stale profile or a row past the day count.
writers:
  - { file: lib/shared/repositories/plan_engine/split_resolver.dart, method_or_widget: "balancedWeekApplies (the one predicate)", line: 410 }
  - { file: lib/shared/repositories/plan_engine/split_resolver.dart, method_or_widget: "quadPrimaryCreditsGlutes (S2: the balanced week or the 6-day Legs B)", line: 422 }
  - { file: lib/shared/repositories/plan_engine/split_resolver.dart, method_or_widget: "selectV4 (sessionMinutes:, balancedWeek:) -> _get3DayV4 / _get4DayV4 / _get5DayV4 balanced lists", line: 429 }
  - { file: lib/shared/repositories/plan_engine/models.dart, method_or_widget: "EarlierDayAvoid, MuscleSlotDay.avoidEarlier", line: 308 }
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generateV4: selectV4 sessionMinutes (line 169, waiver d40) and the credit (line 288, waiver d36)", line: 169 }
  - { file: lib/shared/repositories/plan_engine/plan_engine_flags.dart, method_or_widget: "balancedWeekEnabled (disable_balanced_week, default ON)", line: 86 }
readers:
  - { file: lib/shared/repositories/plan_engine/volume_filter.dart, method_or_widget: "filterDays carries avoidEarlier onto the rebuilt day", line: 44 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: "_pickCoreList: earlier(byType) into avoidA / avoidB; earlierByTypeA / B filled after each day", line: 144 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_groupsOf reads ctx.quadPrimaryCreditsGlutes (unchanged)", line: 396 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "foreignDayNamesFor; repeatPinsFrom row checks; _buildRepeatPins passes the new phase's minutes", line: 787 }
hive_key_prefix: "configBox['disable_balanced_week']; userBox last_phase_profile (read, unchanged shape); plan_json.workouts[] (the plan blob)"
hive_key_formula: "MuscleSlotDay lists -> PopulatedDay -> WorkoutDay.toMap; schedule_<date> rows read by getWeek(1/2)"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); day names and rows pass through untouched"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged); a stored plan is not rewritten, the balanced week applies to plans generated from now on"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched; repeat pins read the same getWeek(1/2) rows", line: 1 }
provider_invalidations:
  - "none: generation only; Train and Home read the stored plan as before"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: generation writes through the existing plan writers; last_phase_profile stays user-scoped (MigratedKey -> userBox); the switch lives in configBox like every PlanEngineFlags switch."
forbidden_patterns_checked:
  - { pattern: "a changed golden persona outside build_muscle 3 / 4 / 5 days (1,010 personas)", absent: true }
  - { pattern: "an output change with disable_balanced_week set (1,010 golden personas; the gate's 288-plan grid at 60 / 90 minutes vs HEAD c6b1ee48)", absent: true }
  - { pattern: "a test oracle that calls balancedWeekApplies or quadPrimaryCreditsGlutes (the audit dump excepted, by design)", absent: true }
  - { pattern: "a day under 3 exercises in the day-floor gate blocks (floor on)", absent: true }
  - { pattern: "plan_generator.dart changed outside lines 169 and 288 (rule 14, waivers d36 / d40)", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-14-generator-step2c-balanced-week.md (v6, four review rounds, founder d35-d46), part 2C-a.
  S1: at 60+ resolved minutes, build_muscle 3-day Upper / Lower / Full Body, 4-day Upper A / Lower A / Upper B /
  Lower B, 5-day Push / Pull / Legs / Upper / Lower + Core, every day with a B list; MuscleSlotDay.avoidEarlier
  (sameType on the later same-type day, all on the 3-day Full Body, d46), carried by VolumeFilter.filterDays and read
  by _pickCoreList as a soft avoid. S2: the same predicate turns off the quad-first Glutes credit. S5: one kill switch,
  disable_balanced_week, read by selectV4, quadPrimaryCreditsGlutes and foreignDayNamesFor. Repeat pins:
  repeatPinsFrom refuses when a workout row's day index is past the new day count or its name is a day of the other
  split family (foreignDayNamesFor, from the new phase's resolved minutes).
regression_test_planned: |
  test/contracts/balanced_week_behavioral_test.dart (lists, predicate, credit matrix, switch per reader, filter carry,
  the earlier-day avoid through VolumeFilter and pickV4, the fresh-fill statement, the row checks, foreignDayNamesFor,
  the pin builder's minutes on real Hive rows); test/plan_generator/balanced_week_gate_test.dart (288 plans: the Quads
  table, week 2 never week 1, repeats, the OFF digest vs HEAD); test/plan_generator/balanced_week_kill_switch_golden_test.dart
  (1,010 personas with the switch set equal main c6b1ee48).
impact_analysis: |
  Platform tier (plan engine). build_muscle 3 / 4 / 5-day plans at 60+ minutes change split, picks and set counts; every
  30 / 45-minute plan, every other goal and every 6-day plan is byte-identical. The founder saw the costs before d40 /
  d43: fewer arm sets, fewer total sets in 3-day 60-minute plans, a 5-day chest focus at 90 minutes gets 13 Chest sets in
  week 1. Repeat pins are refused (a fresh phase instead) more often: whenever the minutes or the switch moved a plan to
  the other family. The app is not live; testers regenerate.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "split_resolver, models, volume_filter, exercise_selector, plan_engine_flags, plan_generator (2 lines), workout_schedule_read_service; flutter analyze clean; every caller test run (119 files), each red listed with its cause below; mutations below" }
  - { layer: hive_local_state, status: verified, evidence: "configBox['disable_balanced_week'] read through PlanEngineFlags (behavioral test S5: unset ON, set OFF, per reader); last_phase_profile read through MigratedKey, shape unchanged; the pin builder test seeds real schedule rows and the userBox profile" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no cloud column, table or migration: day names and rows live inside plan_json, whose shape is unchanged" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged; the golden is re-recorded with per-class attribution and the OFF fixture equals main's hashes" }
---

## Root cause

- **Quads.** Before 2C the build_muscle 3 / 4 / 5-day splits had one leg day a week (two in 4-day: Legs, with
  Upper). The allocator seats slots in split order and credits each exercise to every listed muscle, so a squat filled
  Glutes' session cap and refused the next quad row (the OI-454 mechanism, 6-day only until now).
  - Writer: `SplitResolver._get3DayV4` / `_get4DayV4` / `_get5DayV4`, `generateV4`'s credit flag.
  - Readers: `SessionSetAllocator._groupsOf`, `PeriodizationEngine.apply`, `VolumeTitration`.
- **Repeats.** Days of the same kind picked from the same pool without seeing each other.
  - Writer: the split lists.
  - Reader: `ExerciseSelector._pickCoreList`, whose soft-avoid set held only the B-vs-A and OI-458 feeder names.
- **Repeat pins.**
  - Writer: `generateAndSchedule` stamps `last_phase_profile`. Edit Profile's reschedule rewrites schedule rows
    and never the profile.
  - Reader: `repeatPinsFrom`, which compared only the profile and pinned rows by `workout_day_index`.

## Fix

See `proposed_fix`.

## Measured on the built tree

- **Prototype parity.** The full 2,304-plan audit on the built code is byte-identical to prototype `va2fb`.
  - Suitable 788 -> 886, 0 regressed, 98 improved.
  - Quads plan-weeks under the bottom at 60 / 90: 384 / 336 -> 296 / 120.
- **The gate** (`balanced_week_gate_test.dart`) reproduced §4A.2 exactly on its first run:
  - the per-(days, level) Quads table;
  - week 2 equal to week 1: 16, all 4-day beginner Full Body;
  - week-1 repeats: 3-day 0, 4-day 48, 5-day 102.
- **OFF.** With the switch set, the gate's 288 plans hash to `8d2554d1…`, the value computed on a detached checkout
  of HEAD c6b1ee48, whose generator never reads the switch. The 1,010-persona OFF golden equals main.
- **Golden** (1,010 personas): 230 keys change. Every one is a build_muscle 3 / 4 / 5-day persona, and every such
  persona changes. Reverting one piece alone moves:
  - S1 (the lists): 206 keys;
  - S2 (the credit): 198;
  - the `VolumeFilter` carry: 206;
  - d46: 52, all 3-day.

  No piece moves a key outside that set. The 24 beginner 3 / 4-day phase 1-2 Full Body personas change through S2
  only: their lists are unchanged. Re-recorded with that attribution in the test header.

## Every red on the built tree, with its cause

All 119 test files that reach `generateV4`, `selectV4`, `filterDays`, the golden personas or the repeat pins were run
on the built tree before any expectation moved (the plan's caller list, derived by grep). 15 files were red (40 tests);
each moved only with the cause named:

- **Today's lists at 60 minutes** (`cross_day_variety_behavioral_test`, `variant_b_quads_behavioral_test`,
  `thin_day_topup_behavioral_test`). The tests looked days up by today's names (`Upper`, `Legs`) at the default
  60 minutes, which now builds the balanced lists ("Bad state: No element"). Each now runs at 45 minutes, where
  today's lists still serve, so it keeps testing what it was written for. In `variant_b_quads` the Legs hamstring-first
  check runs only below 60.
- **`quads_floor_6day_behavioral_test`.** Its policy matrix now has minutes. build_muscle 3 / 4 / 5 at 90 and 4 at 60
  do not credit Glutes; at 45 they still do.
- **`rest_by_type_behavioral_test` (f).** The 4-day intermediate full_gym plan at 60 minutes is the balanced week:
  `[6, 6, 6, 6, 6]`.
- **`plateau_rotation_behavioral_test`.** The 4-day 60-minute persona gets the balanced lists. Its rotated-in openers
  cost what the replaced ones did, so no day changes its row count. The deltas were re-recorded to `{}` (they were
  `{w2d1: -1, w4d1: -1}`), with the cause written in the test.
- **`session_set_budget_wiring_test`.**
  - The chest focus check moved to 6 days. The 5-day balanced week gives 13, a cost reported to the founder.
  - The effective-level check passes the restated credit (`false`).
- **`session_set_budget_gate_test`**, **`day_floor_gate_lib`** (`quadOwnsGlutes`). Their oracles restate the rule with
  minutes. Recompose plans count as build_muscle.
- **`day_floor_gate_pairs_p1` / `p4` digests, `day_floor_kill_switch_test`, `lead_first_kill_switch_golden_test`,
  `loaded_wins_kill_switch_golden_test`.** Their OFF worlds predate 2C. They now set `disable_balanced_week` (the
  day-floor lib only for the personas 2C changes) and equal their fixtures again.
- **`day_floor_gate_pairs_p1` / `p4` tallies.** Thin day-weeks with the floor off moved:
  - p1: bodyweight 0 -> 2, home 40 -> 48, basic 60 -> 68, full 40 -> 44;
  - p4: home 40 -> 48, basic 90 -> 88, full 48 -> 52.

  Traced per persona with a temporary print, which also printed the thin days of the same persona's switch-set plan
  (the before world); the lib was restored and checked with `cmp`. Every moved count is a shoulder + elbow build_muscle
  plan:
  - the balanced 5-day's Push, Pull and Upper days (the default 5-day's, which the other goals already use) are thin
    for that injury;
  - before, the body-part split's Shoulders + Arms day was, and at phase 4 a 4-day Pull day that the balanced 4-day no
    longer has (basic 90 -> 88: 4 new, 6 gone).

  Gained = thin in every tier: the floor seats each one and no day ends under 3. Re-pinned with the cause.
- **`lead_first_gate_test`.** The kept worlds moved: A:lead 944 -> 959, A:capped 66 -> 51. A temporary per-persona
  diff (switch set vs unset): 15 personas, all build_muscle 4 / 5-day at 60 minutes, all capped -> lead. 7 are 4-day
  beginner Full Body plans, whose lists do not change, so the credit rule is what lets the lead world hold.
- **`generator_golden_test`.** Re-recorded (above).
- **Predicted red, stayed green: `l2_repeat_pins_strip_test`.** Its rows carry no `workout_name`, so the row check
  never sees them. The pin builder's minutes wiring therefore had no test. One was added (behavioral group "the pin
  builder").

## Mutations

Each mutant was applied once (the anchor count checked, compile clean) and restored. A sha256 of the six production
files was compared before and after the whole run. Run against `balanced_week_behavioral_test.dart` plus
`quads_floor_6day_behavioral_test.dart` (56 tests); red counts:

| Mutant | Red |
|---|---|
| M01 `minutes >= 60` -> `> 60` | 12 |
| M02 days `<= 5` -> `<= 6` | 3 |
| M03 days `>= 3` -> `>= 2` | 1 |
| M04 null minutes resolved as 60 | 5 |
| M05 the predicate ignores the switch | 3 |
| M06 Upper A: Biceps and Triceps slots swapped | 2 |
| M07 S2 `||` -> `&&` | 7 |
| M08 S2's 6-day half ignores `quadLegsB` | 2 |
| M09 `VolumeFilter` drops `avoidEarlier` | 3 |
| M10 `sameType` reads nothing | 1 |
| M11 earlier A names never written | 2 |
| M12 `all` read as `sameType` | 1 |
| M13 the day-index refusal removed | 1 |
| M14 the other-family refusal removed | 4 |
| M15 `foreignDayNamesFor` families swapped | 5 |
| M16 5-day never balanced | 4 |
| M17 `plan_generator.dart:169` passes null minutes | 1 |
| M18 the flag getter always ON | 3 |
| M19 earlier B names never written | 0, then 1 (see below) |
| M20 `plan_generator.dart:288` passes null minutes | 1 (`quads_floor_6day_behavioral_test`) |
| M21 the earlier names left out of `avoidA` | 2 |
| M22 the pin builder drops its minutes argument | 1 |
| M23 the pin builder drops the profile's minutes | 1 |

**M19 survived the first run.** The sameType fixture's later B moved off the earlier B's pick through B's within-day
avoid of its own A, not through the earlier-day names. A fixture whose A is a hinge slot and whose B is a knee slot
was added ("sameType, variant B on its own"). Re-run against the behavioral file: M19 1 red, M11 2, M10 2.

Against the gate (`balanced_week_gate_test.dart`, 2 tests): M01, M09, M12, M05 and M18 are red (1 each). M06 stays
green there: an arm-slot swap changes no Quads count or repeat. The behavioral list pins catch it.
