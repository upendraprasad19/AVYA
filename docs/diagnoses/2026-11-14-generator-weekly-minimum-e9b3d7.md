---
bug_id: e9b3d7
date: 2026-11-14
batch: generator-step2c-b
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Generator step 2, Unit 2C-b (founder d35, d38, d42, d44, d45, d47-d49). Measured on merged main de30a0a7 over the
  2,304-plan audit (weeks 1-3):
  - 28 plans were not_suitable. All were lose_fat / general_fitness, 3-day, 30-minute plans with Shoulders at 0 in
    weeks 1-3 (84 major zero_muscle issues).
  - 134 (plan, group) pairs had a week at 0 for a group the plan trains in another week (Calves 57, Core 42,
    Triceps 19, Biceps 16).
  - A 30-minute day could only fit what the clock allowed, with no room for a missing group's 2 sets.
  - The parent plan's first prototype (v11b) fixed most of this but carried three defects:
    - F2: its row cap came from the floor-OFF world, so 2,397 short day-weeks got MORE rows than today;
    - F3 (round 3 B-7): a d35 target displaced a protective group's only row, so 3 plans became not_suitable
      (week 2 Chest at 0);
    - F4: the allowance re-run kept holds today evicts.
concept: weekly_minimum
sot_registry_entry: weekly_minimum
contract_test_path: test/contracts/weekly_minimum_behavioral_test.dart
related_bugs: [c7e5a1, b3f1d8, d4a7e2, cf970c]
recurrence: |
  Not a recurrence; it continues the step-2 allocator chain:
  - 2A (d4a7e2, the lead): its R2 and the opener are what the walk must leave in place (round 1 A-8);
  - 2B (b3f1d8, the day floor): its re-run with the floor is this unit's reference R;
  - 2C-a (c7e5a1, the balanced week at 60+): shares the kill switch (d37).
  Bug-history lookup (CLAUDE.md 4.1.5). Grep of docs/diagnoses for the tokens "weekly minimum", "zero week",
  "allowance", "row cap", "not_suitable", "Shoulders at 0" and "forcing bound", plus the concepts (the count floor's
  300 s; a group falling to 0 between variants). Hits:
  - d4a7e2 (R3's worlds: a group main trains never at 0);
  - b3f1d8 (the floor seats past the top, d33);
  - the OI-456 count band (maxForcedOverSeconds).
  None of them sets a weekly minimum across variants or lets a short day run past its minutes.
writers:
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_allocateLeadFirst: the 2C-b steps 1-5 on the 5-day path", line: 380 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_allocateLeadFirst: the 2C-b steps on the 6-day path", line: 504 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant: the walk (targets after rank 0 and the 2A opener)", line: 807 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant: the weekly minimum pass (minimumSeats)", line: 1107 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_variant: the row cap (rowCap) and R's hold evictions (refEvicted)", line: 741 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "PopulatedDay(allowance: allowanceUsed) on every returned day", line: 565 }
  - { file: lib/shared/repositories/plan_engine/session_budget.dart, method_or_widget: "SessionBudget.allowanceSeconds (285, d47); BudgetLedger(allowance:) and forcingBound", line: 421 }
  - { file: lib/shared/repositories/plan_engine/models.dart, method_or_widget: "PopulatedDay.allowance (default false)", line: 362 }
readers:
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "_weekTwoGains: BudgetLedger(allowance: populated.first.allowance)", line: 169 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "pass A2 and the minimum pass read ledger.forcingBound (0 with the allowance)", line: 996 }
  - { file: lib/shared/repositories/plan_engine/volume_titration.dart, method_or_widget: "applyToWeeks keeps BudgetLedger(allowance: false) (round 4 R4-1: WeekPlans carry no stamp)", line: 181 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "_buildSessionDurationSelector: the chip reads 'About N min'", line: 1152 }
hive_key_prefix: "configBox['disable_balanced_week'] (2C's one switch, d37; read by allocate unless balancedWeek: is given); plan_json.workouts[] (the plan blob)"
hive_key_formula: "PopulatedDay lists (allocator) -> PeriodizationEngine.apply -> WorkoutDay.toMap; PopulatedDay.allowance is never stored"
sync_methods:
  - "SyncService plan push (user_progress.plan_json); sets and rows pass through untouched, the stamp is not in the map"
restore_methods:
  - "plan_json merge via PlanIntegrityReconciler (unchanged); a stored plan is not rewritten, 2C-b applies to plans generated from now on"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched", line: 1 }
provider_invalidations:
  - "none: generation only; Train and Home read the stored plan as before"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: generation writes through the existing plan writers; the switch lives in configBox like every PlanEngineFlags switch."
forbidden_patterns_checked:
  - { pattern: "an output change with 2A off or 2B off (crafted: weekly_minimum 'where it runs'; real engine: the gate's 48-plan digests with disable_lead_first / disable_day_floor)", absent: true }
  - { pattern: "a day under 60 minutes with more or fewer rows than today (the gate: 1,152 plans, all four weeks)", absent: true }
  - { pattern: "a group today trains newly at 0 except Calves at 30 minutes (the gate: exactly 143 plan-weeks, d45)", absent: true }
  - { pattern: "a plan gaining a major issue (the gate, 1,152 plans; the 2,304-plan audit)", absent: true }
  - { pattern: "plan_generator.dart changed (rule 14; the stamp rides on PopulatedDay, which generateV4 passes through unchanged)", absent: true }
  - { pattern: "a minimum seat in countForced (weekly_minimum test 1, the sweep's oracle)", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md (v5, four review rounds, founder d35-d49).
  - **S4, the allowance.** `BudgetLedger(allowance: true)` under 60 minutes adds `SessionBudget.allowanceSeconds`
    (285 s, d47) and sets `forcingBound` to 0, so it never stacks with the count floor's 300 s.
  - **The reference R** is the pre-2C-b floor re-run of the chosen worlds.
  - **The allowance re-run** keeps the chosen worlds and caps each day at R's rows (d44: sets, never an exercise).
    Under 60 it keeps R's hold evictions.
  - **S3, the targets**:
    - 1 (d35): a group the other variant credits;
    - 2 (d38): a focus group at 0;
    - 3 (protective): what R or step 1 credits.
    Credit counts kept library holds. Calves under 45 minutes is never a target (d45, d49).
  - **The walk** moves each target's cheapest slot after rank 0 and the 2A opener (d48 keeps the lead).
  - **The minimum pass** seats a target still at 0 at 2 sets, within the forcing bound.
  - **The steps**: a fixpoint of at most 4 rounds; protect-first; the fallback to R verbatim is the terminal guard.
  - **The kill switch** reaches the allocator as `allocate(balancedWeek:)`. The allocator stamps
    `PopulatedDay.allowance`, which `_weekTwoGains` follows; titration never takes the allowance (R4-1).
  - **The chip** reads "About N min". The audit's over-time bound moves to +6 (d47).
regression_test_planned: |
  test/contracts/weekly_minimum_behavioral_test.dart (target 1 and the minimum pass, each guard, copy-day seats, target
  2 on the 6-day path, hold credit, where it runs, Calves under 45); test/contracts/session_allowance_behavioral_test.dart
  (the ledger, the stamp per path, the row cap and time, the readers, a 220-plan seeded sweep with 2C-b ON through the
  shared oracle incl. "at 60+ a plan with no target is R"); test/plan_generator/weekly_minimum_gate_test.dart (1,152
  real plans at 30 / 45 minutes ON vs OFF, 2A / 2B off digests).
impact_analysis: |
  Platform tier (plan engine). Every 30 / 45-minute plan of every goal on the lead-first, floor-ON path changes.
  - Sets grow (about 5-6 a week).
  - 279 plans' exercise sets change at the same row count (the swap design, d47).
  - 860 short day-weeks display +6 minutes.
  - At 60 / 90 one strength plan per length changes (a minimum seat); one golden persona of 1,010 changes, the same
    class.
  - Costs the founder accepted (plan §7): Calves at 0 at 30 minutes in 143 plan-weeks (d45), the `glutes_legs` focus
    cells (OI-501 stays open), lead_starved / ab_swing regressions in 23 plans.
  The app is not live; testers regenerate.
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "session_set_allocator, session_budget, models, periodization_engine, edit_profile_screen (chip); flutter analyze clean; every caller test run (53 files), each red listed with its cause below; mutations below" }
  - { layer: hive_local_state, status: verified, evidence: "configBox['disable_balanced_week'] read through PlanEngineFlags.balancedWeekEnabled by allocate; the gate sets / unsets it and the 2A / 2B switches; nothing new is written to Hive" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no cloud column, table or migration; plan_json's shape is unchanged (PopulatedDay.allowance never reaches WorkoutDay.toMap)" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json shape unchanged; the golden is re-recorded (1 key, attributed below); the 2,304-plan dump of the built tree equals the chosen prototype run byte for byte" }
---

## Root cause

- **The 28 not_suitable plans.**
  - Writer: `SessionSetAllocator._variant` (pass A seats in split order inside the day's minutes).
  - Reader: the audit's `zero_muscle` rule.
  - Mechanism: a 30-minute 3-day plan's rows were the first four of each split day, and no day's first four held a
    Shoulders slot. Without extra time nothing could re-pick them.
- **Zero weeks.**
  - Writer: the A and B variants, allocated separately.
  - Mechanism: B copies only same-named days, so a group one variant seats can be missing from the other. Nothing
    set a weekly minimum across variants.
- **v11b's defects.**
  - F2: the row cap was taken before the floor re-run.
  - F3: a new target was allowed to take a protective group's only row, and there was no terminal guard.
  - F4: the re-run did not carry R's hold evictions.

## Fix

See `proposed_fix`. Execution mode: inline (plan §0).

## Measured on the built tree

- **Prototype parity.** The 2,304-plan audit dump of the built tree (`plan_dump.jsonl` and `audit.json`) is
  byte-identical to the chosen prototype run b25 (option (a): the swap design at 285 s with the allowance signal).
  - The dump carries week 2, so the stamp's effect is compared on every plan.
  - The two runs differ in the probe: b25's set the stamp with the floor off too (R4-7). No grid plan runs with the
    floor off, so the dumps cannot see that difference. The built code follows the spec, and the gate checks it with
    the floor off (2B off).
- **Suitable** (2,304 plans, the audit's over-time bound at +6) is 965 / 1,339 / 0, against main's 886 / 1,390 / 28.
  - 23 plans regress, 102 improve, 0 gain a new major issue.
  - (plan, group) zero-week pairs fall from 134 to 71.
- **The gate**, on its first run, reproduced the values computed from the dumps before it ran:
  - 30 / 45 minutes ON: 657 / 495 / 0; OFF: 578 / 546 / 28;
  - Calves newly at 0 at 30 minutes: 143;
  - rows equal to OFF's on every day of all four weeks;
  - zero-week pairs 71 against 132;
  - display at most +6;
  - the stamp false on exactly the two fallback plans, whose whole plan equals OFF.
- **Golden** (1,010 personas): 1 key changes, `grid|bodyweight|strength|4d|intermediate|p1`, a 60-minute plan whose B
  variant credits a group A lacks. It is a minimum seat at 60+, the class of the grid's strength 60 / 90 plan (§0).

## Every red on the built tree, with its cause

All 53 caller files (plan §5, `step2cb/callers.txt`) plus `plan_audit_lib_test` and the chip pin were run on the built
tree before any expectation moved. 41 tests were red (7 more "reds" were helper and report files the list loaded
as tests).

- **Crafted fixtures that pin pre-2C-b mechanics** (the plan's test policy). These files build
  `Fx(balancedWeek: false)` and pass `balancedWeek: false` to their direct `allocate` calls. Their 30 / 45-minute
  fixtures now got 2C-b (the allowance changed their seats).
  - `allocator_timed_hold_eviction_behavioral_test`: 5 tests.
  - `exercise_count_band_behavioral_test`: 7.
  - `lead_first_allocator_behavioral_test`: 11.
  - `rest_by_type_behavioral_test`: 1.
  - `session_set_allocator_behavioral_test`: 6, two of them its seeded sweep and the B-pass fixes.
- **Seeded sweeps with an exact `over` map** (`session_set_allocator_behavioral_test` 220 plans,
  `session_set_budget_consumers_test` 60 plans). These keep pinning the pre-2C-b seconds (`balancedWeek: false`). The
  same sweep with 2C-b ON, through the shared oracle's new allowance excuse, is in
  `session_allowance_behavioral_test`.
- **Own time limits** (plan §5's list). These tests now take the oracle's allowance excuse when the allocator stamped
  the plan (`SessionSetAllocator.debugLastAllowance`), and the minimum seats share the forcing bound:
  - `session_set_budget_wiring_test`: 2 tests;
  - `oi489_timed_hold_real_engine_test`: 2;
  - `session_set_budget_gate_test`: 5 grid blocks.
  The `over` maps were re-pinned with the measured seconds, every one inside the 285 s:
  - wiring: 186 to 264 s;
  - oi489: up to 35.3 minutes, with the Ruling 5c day at 34.5 and never count-forced.
- **`generator_golden_test`.** Re-recorded (above).
- **`plan_audit_lib_test`, `session_duration_chip_wording_test`.** The over-time bound moved to +6 (d47), and the chip
  reads "About N min". Both changed with their production line.

## Mutations

Each mutant was applied to the production tree by an exact-text replacement with its count asserted, so a mutant that
did not apply aborts the run. It had to pass `dart analyze` with no `error -` line: a compile error is not a red. Then
the three new test files ran against it, and the tree was restored and sha-checked after every mutant. Columns:
`weekly_minimum_behavioral_test` (W, 10 tests), `session_allowance_behavioral_test` (S, 6 tests; its seeded sweep
pins every ON allocation by digest) and `weekly_minimum_gate_test` (G, 1,152 real plans ON vs OFF, ON digest pinned).

| Mutant | What it changes | W | S | G |
|---|---|---|---|---|
| M01 | the allowance re-run runs without the allowance | green | green | RED |
| M02 | the stamp stays true on the fallback | green | green | RED |
| M03 | the stamp is true whenever under 60 | green | RED | RED |
| M04 | titration builds its ledger with the allowance | green | RED | green |
| M05 | `_weekTwoGains` ignores the stamp | green | green | RED |
| M06 | no row cap on the re-run | RED | RED | RED |
| M07 | the re-run forgets R's hold evictions | green | green | RED |
| M08 | no walk | green | green | RED |
| M09 | the walk puts targets at rank 1 | green | green | RED |
| M10 | `evictFor` takes the loop index, not the slot's rank | green | green | green |
| M11 | the count reads pass A's `seated`, not admitted rows | green | green | green |
| M12 | no admitted-row count guard in the minimum pass | green | green | green |
| M13 | no forcing-bound guard | RED | green | green |
| M14 | no other-group weekly-top guard | RED | RED | green |
| M15 | no session-cap guard | green | green | green |
| M16 | no tie rule (most seconds left) | green | green | green |
| M17 | the minimum pass does not skip a kept hold's groups | green | green | green |
| M18 | credit does not count kept holds | RED | green | RED |
| M19 | Calves exempt below 30, not below 45 | RED | green | RED |
| M20 | a focus Calves group is not exempt (5-day branch) | RED | green | green |
| M21 | no protect-first step | green | RED | green |
| M22 | no fallback to R | green | green | RED |
| M23 | the fixpoint runs one round | green | green | RED |
| M24 | the 6-day branch runs no 2C-b | RED | RED | RED |
| M25 | the switch is ignored (2C-b always on) | RED | RED | RED |
| M26 | worlds are chosen with the allowance on | green | green | RED |
| M27 | the forcing bound stacks on the allowance | green | RED | green |
| M28 | the allowance is 300 s | green | RED | RED |
| M29 | a copied day does not inherit minimum seats | RED | green | green |
| M30 | target 1 (d35) is not computed | RED | green | RED |

M20 survived the first run (the 6-day test covers only the 6-day branch). The 5-day Calves test was added, and M20
then turned W red (1 test). M21 survived the first run too. The sweep digest was added after that run, and M21 then
turned S red. M03 first failed to compile, because it read `under60` before its declaration. It was re-anchored after
the declaration, and that version is the one in the table.

**Six survivors, each a guard no input reaches.** None changes a single allocation on the 2,304-plan grid, the
1,152-plan gate, the 220-plan random sweep (random libraries, focus groups, 6-day plans) or 22 crafted two-target
probe days (beginner and intermediate, 2 to 4 customs):
- M11 and M12. Pass A marks a slot it refuses on the count with `_Why.target`, and the minimum pass skips that mark
  first. A slot could still reach the count guard if the floor or A2 filled the day after pass A had refused that
  slot on the clock. No input does that, and two minimum seats on one day exceed the forcing bound on every probe. The
  guard stays as round 1 A-1's backstop.
- M15. The minimum pass seats at 2 sets, and every session cap is at least 2 above any session at 0 in the target
  group. The cap would bind only for another group the slot also credits that is near its cap. No input has one.
- M16. On every input, two slots priced equal on different days with different seconds left never both qualify.
- M17. Credit already counts a kept hold's groups (M18 is red), so no target is ever a group a kept hold trains. This
  skip is a second door on that rule.
- M10. Inside the walk the loop index equals the slot's rank for every slot `evictFor` is called on, except a walked
  target. No input has a walked target that evicts a hold.

## Not covered by a crafted fixture (stated)

- **The week-2 reader.** In 12 crafted shapes at 30 / 45 minutes the week-2 +1 never binds on the clock. It binds on
  the lead + 1 hold and the weekly band first. The reader's proof is the gate's exact verdict counts (without the stamp
  the grid moves, plan §4.5), and mutant M05 against the gate.
- **The tie rule, and round 1 A-1's count source** (admitted rows, not pass A's `seated`). Probed fixtures either let
  the bench grow to equal seconds on both days or let A2 admit the target itself. Their mutants (M16, M11) survive
  every test; the Mutations section says why.
- **The walk, protect-first, the fallback, the fixpoint and the row cap's effect.** These are pinned on the real engine
  by the gate's exact counts and the fallback plans. The crafted shapes either reach the fallback or change nothing.
