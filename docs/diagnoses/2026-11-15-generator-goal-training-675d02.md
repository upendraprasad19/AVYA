---
bug_id: 675d02
date: 2026-11-15
batch: generator-step3a
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Generator step 3, Unit 3A (OI-487, generator half; founder d3 / d4 2026-11-08, d58-d65 2026-11-15).
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
  rules). Bug class 2.162 (run the neighbouring gates before every push) found S8 / d65.
writers:
  - { file: lib/shared/repositories/plan_engine/training_history_analyzer.dart, method_or_widget: "goalTrainingFromProfile: the switch and physique_focus == 'strength'", line: 124 }
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generateV4: SessionBudgetContext(goalTraining:), d61", line: 300 }
  - { file: lib/shared/repositories/plan_engine/goal_reps.dart, method_or_widget: "GoalReps.base / mainBase (the week-1 table, d58 / d59)", line: 46 }
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "restFor / restForGoal (+30 s on H / M at 60+ minutes, d64)", line: 396 }
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "_goalBands / weeklyBand(goalTraining:)", line: 491 }
  - { file: lib/shared/repositories/plan_engine/split_resolver.dart, method_or_widget: "quadPrimaryCreditsGlutes: 4-day general_fitness", line: 428 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "the day floor (pass 4b'): capTrims, a reservation-blocked slot may be floored (d65)", line: 1314 }
readers:
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "_applyWave: GoalReps.base, then the wave, the range clamp and the 10-15 accessory clamp", line: 307 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "the rest stamp and _weekTwoGains (restFor)", line: 104 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_repeatCost / _variant pricing (restFor)", line: 729 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "the floor label's band (weeklyBand goalTraining)", line: 1521 }
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
  - { pattern: "a group trained OFF at 0 ON in any plan-week 1-3, with or without the focus (the gate: 0)", absent: true }
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
- Plan-weeks newly at 0: 0. Days over the session: no worse than OFF (+6).
- The Strength focus: 29,012 main lifts at their range floor; rest +30 s at 60+ minutes only; 0 newly at 0; the switch
  overrides the focus.

S8 / d65 (found by the neighbouring day-floor gate, bug class 2.162): 8 of 17,280 `rep30` day-weeks at 2 exercises
(6 by the session cap, 2 by the rank-0 reservation, the latter also a `lost` Goblet Squat). After d65: 0 thin, 0
lost, every floor-off digest equal to main's.

## Mutations

(below)
