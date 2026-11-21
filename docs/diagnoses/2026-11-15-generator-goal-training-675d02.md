---
bug_id: 675d02
date: 2026-11-15
batch: generator-step3a
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Generator step 3, Unit 3A (OI-487, generator half; founder d3 / d4 2026-11-08, d58-d68 2026-11-15).
  - Cut (lose_fat) and Maintain (general_fitness) trained like Build: the same reps (the phase's archetype lean on the
    library range), weekly bands within 2-4 sets of Build's (Cut beginner equal to Build).
  - Cut and Maintain plans were identical in 92 of 576 profiles (same days, level, tier, minutes, phase).
  - The Strength focus (`physique_focus = 'strength'`) mapped to no muscles, so it changed nothing.
concept: goal_training
sot_registry_entry: goal_training
contract_test_path: test/contracts/goal_reps_behavioral_test.dart
related_bugs: [e9b3d7, b3f1d8, d4a7e2, c7e5a1]
recurrence: |
  Not a recurrence. The unit adds a goal input the plan engine never read. It reuses the step-2 readers: the weekly
  band (`BudgetLedger.weeklyTop`, B2), the quad-first credit (OI-454, 2C-a), the rest by archetype (OI-456 piece A).
  Bug-history lookup (CLAUDE.md 4.1.5): docs/diagnoses grepped for "lose_fat", "general_fitness", "physique_focus",
  "restForArchetype", "weeklyBand", "quadPrimaryCreditsGlutes" and "reserveBlocked". Hits: OI-454's Glutes credit
  (applied here to 4-day Maintain, the same class: a shared squat spends a tight Glutes top and a hinge is refused,
  feedback_measure_a_shared_rules_golden_footprint: the rule's reach was measured before it was scoped), OI-456 piece
  A (rest follows the exercise; every writer and pricer moved together here), the 2B day floor (d65 amends two of its
  rules). Running the neighbouring gates before the push (bug class 2.162's last point) found S8 / d65.
writers:
  - { file: lib/shared/repositories/plan_engine/training_history_analyzer.dart, method_or_widget: "goalTrainingFromProfile (the switch and physique_focus == 'strength')", line: 124 }
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generateV4: SessionBudgetContext(goalTraining:), d61", line: 300 }
  - { file: lib/shared/repositories/plan_engine/goal_reps.dart, method_or_widget: "GoalReps.base / mainBase (the week-1 table, d58 / d59)", line: 48 }
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "restFor / restForGoal (+30 s on H / M at 60+ minutes, d64)", line: 396 }
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "_goalBands / weeklyBand(goalTraining:)", line: 491 }
  - { file: lib/shared/repositories/plan_engine/split_resolver.dart, method_or_widget: "quadPrimaryCreditsGlutes: 4-day general_fitness", line: 428 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "the day floor (pass 4b'): capTrims, a reservation-blocked slot may be floored (d65)", line: 1362 }
readers:
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "_applyWave: GoalReps.base, then the wave, the range clamp and the 10-15 accessory clamp", line: 307 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "the rest stamp and _weekTwoGains (restFor)", line: 104 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_repeatCost / _variant pricing (restFor)", line: 762 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "pass C grows every group to the band bottom (weeklyBand goalTraining)", line: 1664 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "_titrateWeekBudgeted (weeklyBand goalTraining)", line: 182 }
  - { file: lib/core/services/swap_service.dart, method_or_widget: "swapExerciseInDay: restForGoal with the profile's focus and resolved minutes", line: 549 }
hive_key_prefix: "userBox['profile']['physique_focus'] (read only) and configBox['disable_goal_training'] (the switch)"
hive_key_formula: "HiveService.instance.userBox.get('profile')['physique_focus'] == 'strength'; configBox.get('disable_goal_training') == true"
sync_methods:
  - "none: no new stored key; plan_json carries the new reps and rests like any row"
restore_methods:
  - "none: physique_focus is restored with the profile as before; the switch is device-local"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched", line: 1 }
provider_invalidations:
  - "none: generation and swap only"
telemetry_op_types:
  success: []
  failure: ["training_history_analyzer_goal_training (recordNonFatal reason, a corrupt profile)"]
cross_account_guard: "unchanged: the profile read goes through the user-scoped userBox, as physiqueFocusMuscles does."
forbidden_patterns_checked:
  - { pattern: "a Build or legacy-strength plan changed without the focus (the gate: 0 of 1,152)", absent: true }
  - { pattern: "a group trained OFF at 0 ON in any plan-week 1-3 of the uninjured grid, with or without the focus (the gate: 0; injured plans: d66, accepted)", absent: true }
  - { pattern: "a change with the switch set (goal_training_kill_switch_golden_test: 1,010 personas = main)", absent: true }
  - { pattern: "plan_generator.dart changed beyond d61's argument", absent: true }
  - { pattern: "a day under 3 exercises or a lost row against the floor off (the three day-floor gates)", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-15-generator-step3a-goal-training.md, S1-S8.
  - S1: GoalTraining on SessionBudgetContext, built from the profile and the switch; d61's one argument.
  - S2: rest through restFor / restForGoal everywhere (+30 s on H / M under the focus at 60+ minutes, d64).
  - S3: GoalReps for the week-1 base; Cut / Maintain accessories clamped to 10-15.
  - S4: _goalBands (Maintain two-thirds of Build, Cut beginner 9-11), caps unchanged.
  - S5: quad-first Glutes credit for 4-day Maintain.
  - S6: kill switch disable_goal_training, OFF = main.
  - S7: audit knobs PLAN_AUDIT_DISABLE / PLAN_AUDIT_FOCUS.
  - S8 (d65): the day floor may seat a reservation-blocked slot, and takes sets off a group's rows above 2 when only
    a session cap refuses a thin day's third exercise.
regression_test_planned: |
  test/contracts/goal_reps_behavioral_test.dart; test/plan_generator/goal_training_gate_test.dart;
  test/plan_generator/goal_training_kill_switch_golden_test.dart; test/contracts/day_floor_behavioral_test.dart (d65);
  test/contracts/swap_exercise_rest_follows_incoming_archetype_test.dart (the focus rest in a swap).
impact_analysis: |
  Platform tier (plan engine). Every Cut and Maintain plan changes (reps, bands, the 4-day Maintain credit); Build
  changes only under the Strength focus. The app is pre-launch with testers only; an existing plan changes at its next
  generation. 3B moves the legacy Strength-goal testers onto Build + the focus.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "goal_reps, session_budget, periodization_engine, session_set_allocator, split_resolver, volume_titration, training_history_analyzer, plan_engine_flags, plan_generator (d61), swap_service; flutter analyze clean" }
  - { layer: hive_local_state, status: verified, evidence: "physique_focus is read from userBox['profile'] (no new key); the swap test writes the profile and reads the stamped rest back from workoutBox" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column, table or migration; plan_json's shape is unchanged" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json rows are ordinary PlannedExercise maps; the coach reads reps and rest as before" }
---

## Root cause

- **Writer:** `PeriodizationEngine._applyWave` chose week-1 reps from the PHASE archetype on the library range, and
  `SessionBudget._bands` gave Cut and Maintain bands close to Build's. No writer read the goal beyond the band.
- **Reader:** every plan reader (Train, the coach, the audit) shows the stamped reps, sets and rest.
- **Missing input:** the goal's training style (main-lift reps, accessory reps, weekly volume) and the Strength focus
  existed only as profile values nothing in the engine read.

## Fix

See `proposed_fix` and the plan. Execution mode: inline.

## Measured on the built tree

The gate (`goal_training_gate_test.dart`, 2,304 plans ON vs OFF):
- Build and the legacy strength token: 0 plans changed.
- Cut and Maintain identical: OFF 92 of 576, ON exactly the two d63 profiles.
- Week-1 main lifts (archetype H / M): 14,547, every one at the table or its range bound (3,601 at a bound).
- Week-1 accessories: 12,360, every one in 10-15 (or its own range clamped there).
- Plan-weeks newly at 0: 0 (the uninjured grid; injured plans below, d66). Days over the session: no worse than OFF (+6).
- The Strength focus: 29,010 main lifts (on the 2E tree; 29,012 before it) at their range floor; rest +30 s at 60+ minutes only; 0 newly at 0; the switch
  overrides the focus.

S8 / d65 (found by the neighbouring day-floor gate, run before the push: bug class 2.162's last point): 8 of 17,280 `rep30` day-weeks at 2 exercises
(6 by the session cap, 2 by the rank-0 reservation, the latter also a `lost` Goblet Squat). After d65: 0 thin, 0
lost, every floor-off digest equal to main's.

## Accepted consequences (review round 1)

- d66 (founder, re-confirmed with the two-injury numbers): an injured Cut / Maintain plan can lose a group the
  switch-off plan trains, when the group's only row also works a group whose lower top is spent (Face Pull for
  Shoulders under a shoulder injury; a hamstring curl or walkout under lower_back; Dand for Triceps under elbow).
  Goal training ON vs OFF, plan-weeks 1-3: 36 of 3,072 single-injury plans (8 injury states x 2 goals x 3-6 days x 3
  levels x 4 tiers x 30 / 60 minutes x phases 1 and 4; 8 more are d67's), and with two injuries (the day-floor
  personas, these include d67's) 35 of 1,440 phase-1 plans, 60 of 1,440 phase-4 plans and 11 of 480 pinned 30-minute
  repeats. Nearly all Maintain. No code change.
- d67: with a lower_back injury, 4-day Maintain beginner plans hold today's exercises, but the quad-first credit books
  Walking Lunge to Quads only, so Glutes reads 0 in the set count.
- d68: the rep table follows the EFFECTIVE level (a beginner trains as intermediate from phase 3, as the bands do), so
  a Cut beginner's phase-3 and deload main lifts take 8; d59's deload is phase 1's entry at that level.
- d65 (b) on a thin day: the trimmed lead stays at 2 sets and its capped group cannot regrow, so pass B may bring
  another row to 3 and then R2 / R5 refuse every pass C / D and week-2 +1 on that day (no stated property fails; the
  lead keeps 2 and no row passes lead + 1; B-pass seat B).
- A row with no parseable rep range keeps the legacy `baseReps` path under every goal (outside the table and the
  10-15 clamp; pinned in `goal_reps_behavioral_test.dart`).
- d65 is not behind `disable_goal_training`. With goal training off everywhere and d65 kept, the three day-floor gates
  pass on main's old pins (review round 1), and with the switch set 2,592 plans hash the same with the pre-d65 floor
  (seat B), so the switch-off world still equals main where measured.

- The 10-15 accessory clamp (d3: "accessories 10-15 for all") can prescribe outside a row's own range: a rep-based
  accessory whose range starts above 15 is prescribed 15, under its range (3 library rows, all bodyweight and 20-30:
  Box Jump, Mountain Climber, Alternate Heel Touchers; Burpee, also 20-30, is a compound and stops at its bound), so
  `ProgressionResolver._gradedSuggestion` can read logged sets as "below range"; an accessory whose range tops at 10
  or below (22 rep-based rows) is prescribed 10, its top. Counted from `assets/data/exercise_library.json`. Founder's
  rule, stated here.
- A plan-day swap keeps the outgoing row's reps (as before 3A) while its rest follows the incoming row and the goal
  rule: under Cut / Maintain a main lift swapped into an accessory slot keeps the accessory's 10-15 reps, and the
  reverse (B-pass seat A).
- A plan-day swap reads the profile's CURRENT minutes and focus (`swap_service.dart`): after a minutes or focus change
  without a regeneration, a swapped-in main lift takes the new rest while its neighbours keep the generated stamp.

## Mutations

Each mutant was applied to the committed file (`grep -c` confirmed the edit), run, and restored; `git diff --stat lib/`
was empty after every pass. "Fast" = `goal_reps_behavioral_test` + `swap_exercise_rest_follows_incoming_archetype_test`
(25 tests, 26 after G13's test, 27 with round 2's week-2 test, 29 with the B-pass's weeks 1-4 and no-range tests); "golden" = `goal_training_kill_switch_golden_test`; "gate" = `goal_training_gate_test`.

| ID | Mutation | Result |
|---|---|---|
| G1 | Cut int / adv strength-phase main reps 6 -> 7 (`goal_reps.dart`) | fast red (2) |
| G2 | the 10-15 accessory clamp skipped (`_applyWave`) | fast red (1) |
| G3 | "main" = archetype H only (M dropped, d58) | fast red (2) |
| G4 | the focus takes the range floor in the deload too (d59) | fast red (2) |
| G4b | the focus's range floor removed | fast red (2) |
| G5 | `minutes >= 60` -> `> 60` (d64) | fast red (5) |
| G6 | `gt.enabled` dropped from the focus rest (the switch no longer overrides it) | fast red (2); golden green (the switch already returns `GoalTraining.off`) |
| G7 | Maintain beginner top 8 -> 10 | fast red (1) |
| G8 | the floor-label band read without `goalTraining:` (defaults ON) | fast green; golden red (the OFF world takes the goal bands) |
| G9 | the 4-day Maintain Glutes credit removed | fast red (1) |
| G10 | `goalTrainingFromProfile` ignores the switch | fast red (1); golden red |
| G11 | the swap prices the rest at 0 minutes | fast red (1) |
| G11b | the swap prices the rest at 60 minutes whatever the profile | fast red (1) |
| G12 | `plan_generator.dart` drops d61's argument (the default context: enabled, no focus) | fast green; gate red (2) |
| G13 | the allocator prices a not-budgeted rep-based row at `restForArchetype` | **survived** fast and gate (no plan in the grid has a custom row); new test "a custom main lift is priced at the focus rest in the allocator" (`goal_reps_behavioral_test.dart`): red under G13 (18 passed, 1 failed), green restored |
| G14 | the accessory clamp for every goal (Build too) | fast red (3) |
| G15 | Cut beginner band 9-11 -> 10-12 | fast red (1) |
| G16 | `isStrengthFocus` always false | fast red (1); gate red (1) |
| WK (B-pass, seat B) | the Cut / Maintain 10-15 clamp in week 1 only (`weekIdx == 0 &&`) | **survived** fast; new test "weeks 1-4 and the stash" (`goal_reps_behavioral_test.dart`): red under WK (21 passed, 1 failed), green restored |
| W2 (round 2, seat B) | `_weekTwoGains` prices the +1 set at `restForArchetype` | **survived** fast; new test "week 2 prices the +1 set at the focus rest" (`goal_reps_behavioral_test.dart`): red under W2 (19 passed, 1 failed), green restored |

d65 (`session_set_allocator.dart` pass 4b', `day_floor_behavioral_test.dart`; the grid is `day_floor_gate_rep30_test`):

| ID | Mutation | Result |
|---|---|---|
| RB | a reservation-blocked slot skipped again (d65 a) | contract red (1) |
| NOTRIM | `capTrims` never finds a donor (d65 b off) | contract red (2) |
| LEDGER | the trim's ledger update removed (the day's sessions keep the cut sets) | contract red (1) |
| CREDIT (B-pass, seat B) | the trim's ledger update credits the sets but 0 seconds | **survived** (LEDGER removed the whole call); new test "the trim gives the cut set's seconds back to the day" (24 minutes, 2C-b off): red under CREDIT (26 passed, 1 failed), green restored |
| COPY (round 2, seat B) | B's copy of `floorTrims` on a copied day disabled | **survived** (nothing read B's `floorTrims`); new test "B copies A's floorTrims with the floored day": red under COPY (25 passed, 1 failed), green restored |
| MOST (round 2, seat B) | the donor with the FEWEST sets first | equivalent, like BELOW2 and TIE, by a stronger argument: the floor (pass 4b') runs before pass B and the grow passes, so every slot then holds 2 sets except the day's lead, which pass A may seat at 3 (R1). The only possible donor is the lead, so the donor order, the tie rule and the floor of 2 cannot change a choice |
| ORDER | the trim tier tried first (`[true, false]`) | **survived** the contract test and the rep30 grid (4 tests green, 7 min 43 s); new test "a slot that needs no trim is preferred to one that does": red under ORDER (24 passed, 1 failed), green restored |
| BELOW2 | a donor may go down to 1 set | equivalent: contract and rep30 grid green. A thin day holds at most 2 admitted rows, and a trim is needed only when the group's session is at least cap - 1 >= 5 (every cap is 6 or more), so one donor always has 3+ sets and the most-sets-first pick never reaches a row at 2 |
| TIE | ties to the earliest rank instead of the latest | equivalent: contract and rep30 grid green. Two tied donors (x, x) on a 2-row day give an even overflow (2x + 2 - cap with 2x <= cap), so both are cut by one whichever is first |

The day-floor oracle's `priced()` (`day_floor_behavioral_test.dart`) now reads `SessionBudget.restFor` instead of
`restForArchetype` (bug class 2.164: a restating oracle carries the rule it restates).

Attribution (the moved pins are 3A's, not a regression): with goal training off everywhere (the flag getter, the
`GoalTraining` default and `weeklyBand`'s default) and d65 reverted, `weekly_minimum_gate_test`,
`repeat_minutes_gate_test`, the three day-floor gates and the generator golden all pass on their pre-3A pins; with
goal training off and d65 kept, the seeded sweep pins and every golden persona are unchanged (d65 moves none of
them). The pins were then re-recorded from the ON run.
