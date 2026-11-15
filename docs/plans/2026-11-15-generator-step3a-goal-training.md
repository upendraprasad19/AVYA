# Generator Unit 3A: training follows the goal (OI-487, generator half)

Board step 3 (t301-t308). Founder decisions d3 / d4 (2026-11-08) and d56-d65 (2026-11-15). Tier L (plan engine, a
rule-14 argument); blast radius `platform`. Execution mode: inline (one worktree, `generator-step3a`).

## 0. Step 3 is four units (§4.12.1)

Step 3 crosses the plan engine, the profile UI, an Edge Function and the schedule services. It ships as four units,
one after another, each with its own x2 review, B-pass, CI and merge:

| Unit | Issues | What | Tier |
|---|---|---|---|
| 3A (this plan) | OI-487 (generator half) | Reps and weekly sets by goal; the Strength focus is real | platform, L |
| 3B | OI-487 (rest), OI-488 | Strength leaves the goal list, its testers become Build + Strength focus; Edit Profile says Cut / Maintain; 90 minutes for advanced only; the coach's switchGoal tool (ai-proxy deploy, t306, its own go) | account + EF, L |
| 3C | OI-396 | The cardio finisher is shown, injury-safe (d56); its 2 days keep its time (d61) | platform, L |
| 3D | OI-175, closes OI-166 | holdWeek replaces redoWeek4; the NOW marker follows the cycle (d57) | account, L |

3A goes first: 3B moves testers onto the Strength focus that 3A makes real.

3B inputs already read:
- Onboarding also offers Strength as a goal (`onboarding_provider.dart:89`; `plan_screen.dart:530/539/727/770/781`;
  `onboarding_chat_screen.dart:878`). d4 names Edit Profile and the coach; 3B asks about onboarding.
- Readers that switch on the token: `pattern_detector.dart:601`, `regenerate_plan_diff.dart:269`,
  `switch_goal_diff.dart:292`, the ai-proxy `switchGoal` enum (`_shared/tools/plan/switchGoal.ts:9`).
- OI-488: `SessionBudget.resolveMinutes` (`session_budget.dart:40`) has no level, and `plan_generator.dart` calls it at
  the context build (rule 14). "A stored 90 for a beginner / intermediate is 60" belongs in
  `TrainingHistoryAnalyzer.sessionMinutesFromProfile()`, keyed on the profile level or on the effective level (3B
  decides).

## 1. What happens today (main 708f9049)

- **Reps.** `PeriodizationEngine._applyWave` (`periodization_engine.dart:272-328`) takes the row's library
  `rep_range` and leans by the PHASE archetype (`archetypeForPhase`, `:16-19`): hypertrophy mid, strength min,
  metabolic max, deload mid. `_waveReps` (`:331-340`) nudges by week, then a clamp into the range. The goal never
  enters.
- **Weekly sets.** `SessionBudget._bands` (`session_budget.dart:434-455`). Cut (lose_fat) is Build minus 2-4 for
  intermediate and advanced, EQUAL for beginners (10-12). Maintain (general_fitness) is 10 / 10-12 / 12-14.
- **Same plan.** Cut and Maintain share a split and a cardio finisher: identical in 92 of 576 profiles on main
  (149 on the OI's 2026-11-08 tree).
- **Strength focus.** `physique_focus = 'strength'` maps to no muscles
  (`TrainingHistoryAnalyzer.physiqueFocusToBodyFocus`, `training_history_analyzer.dart:127`), so it changes nothing.
- **Rest.** `SessionBudget.restForArchetype` (`session_budget.dart:385-390`): H 150, M 120, I 75, B 60. Writers and
  pricers:
  - `periodization_engine.dart:103` (the stamp) and `:196` (`_weekTwoGains`);
  - `session_set_allocator.dart:757` (`_repeatCost`), `:939` and `:968` (`_variant`);
  - `swap_service.dart:548` (a swapped-in row).
  Readers of the stamped rest: the display minutes (`estimateDayMinutesFromPlanDay` and `budgetedDaySeconds` read
  `rest_seconds`, `session_budget.dart:313` and `:370`) and the workout timer. So a rest change at the writers reaches
  every reader.

## 2. The rules (d3, d58-d60, d64)

A row is a **main lift** when its archetype (`SessionBudget.archetypeOfPlanned`) is H or M, i.e. every compound
(d58). Every other row is an **accessory**. Level = the budget's EFFECTIVE level. Phase archetypes cycle (phase 5 =
phase 1).

Week-1 base reps by phase (hypertrophy / strength / metabolic / deload):

| Goal (planGoal) | Main lift | Accessory |
|---|---|---|
| build_muscle (Build; recompose maps here) | today: mid / min / max / mid of the range | today |
| lose_fat (Cut), intermediate + advanced | 8 / 6 / 8 / 8 (d59: deload = phase 1) | today's value clamped to 10-15 |
| lose_fat (Cut), beginner | 10 / 8 / 10 / 10 | as above |
| general_fitness (Maintain), every level | 10 / 8 / 10 / 10 | as above |
| strength (legacy token; 3B moves its holders) | today | today |

- **Week wave and clamp.** Today's `_waveReps` week nudge applies, then the clamp into the library range. A lift
  whose range cannot reach the table stops at its bound (d58). An accessory's final clamp is into [10, 15]
  ("accessories 10-15 for all").
- **Strength focus** (d4, d60, d64), any goal: a main lift's base is the range's MIN in every non-deload phase (the
  deload keeps the goal's rule). In a session of 60+ resolved minutes its rest is +30 s (H 180, M 150); at 30 / 45
  minutes the rest is normal (d64: +30 s there pushed whole groups out of 110 of 2,304 plans, 102 of them in all three
  weeks; heavy compounds only still cost 56). Accessories are unchanged.
- **No range.** A row with no parsable range keeps the legacy `baseReps` path verbatim.
- **Weekly sets (d3, d62).**
  - Maintain = two-thirds of Build, rounded: beginner 7-8, intermediate 8-11, advanced 9-13.
  - Cut = slightly fewer than Build: intermediate 10-14 and advanced 12-16 already are; beginner 10-12 -> 9-11.
  - Session caps are unchanged.
  - The chosen minutes still fill the session (d62), so Maintain's sets as a share of Build are 98% at 30 min, 92% at
    45, 88% at 60, 76% at 90 (measured, §4).
- **Quad-first credit for 4-day Maintain.** Measured: Maintain's beginner top of 8 is spent on Glutes by the 4-day
  full body's four Goblet Squats, which refuses every hinge (Hamstrings at 0 in 90 plan-weeks / 30 plans; the OI-454
  class). `SplitResolver.quadPrimaryCreditsGlutes` returns false for `general_fitness` at 4 days (switch ON), so a
  squat does not spend the Glutes top.
  - Scope measured: for every Maintain plan the loss moved to Calves (120 plan-weeks) and Biceps (108).
  - At 4 days only: 0 plan-weeks newly at 0.
  - The predicate has no level; scoping to beginners would need another `plan_generator.dart` argument.

## 3. Changes

- **S1.** `GoalTraining` (`session_budget.dart`, pure): `enabled` (the `disable_goal_training` kill switch) and
  `strengthFocus`. It is a field of `SessionBudgetContext` (default ON, no focus).
  `TrainingHistoryAnalyzer.goalTrainingFromProfile()` reads the switch and `physique_focus == 'strength'`
  (try/catch, telemetry). `plan_generator.dart` passes it, which is d61's one argument. The switch rides inside that
  argument, because `session_budget.dart` reads no flag.
- **S2.** `SessionBudget.restFor(archetype, ctx)` / `restForGoal(archetype, gt, minutes:)` = `restForArchetype` + 30 s
  for H / M under the focus at 60+ minutes (switch ON; `ctx.minutes` in a generation, the profile's resolved minutes
  in a swap). Every writer and pricer in §1 calls it. `swap_service` reads
  `goalTrainingFromProfile()`, so a swap keeps the generated rest.
- **S3.** `GoalReps` (`plan_engine/goal_reps.dart`, pure) gives the week-1 base. `_applyWave` uses it in place of the
  archetype switch, keeps the wave and the range clamp, then clamps a Cut / Maintain accessory into [10, 15].
- **S4.** `_goalBands` (switch ON) beside `_bands` (switch OFF). `weeklyBand(..., goalTraining:)` defaults to the ON
  table. The ledger, the allocator's band bottom (pass C) and titration pass `ctx.goalTraining.enabled`.
- **S5.** Quad-first credit for 4-day Maintain (§2), in `quadPrimaryCreditsGlutes` (it reads the switch, like
  `balancedWeekApplies`).
- **S6.** Kill switch `disable_goal_training` (`PlanEngineFlags.goalTrainingEnabled`, default ON, §4.6). OFF:
  `GoalTraining.off`, today's reps, bands, rests and credit. A golden test proves OFF is byte-identical to main.
  Its deletion is OI-514 (after the device check), like OI-509.
- **S7.** Audit harness knobs: `PLAN_AUDIT_DISABLE` (config keys set true) and `PLAN_AUDIT_FOCUS=strength` (the
  profile's focus).
- **S8 (d65, the day floor, found by the neighbouring day-floor gate).** 3A's lower Cut / Maintain tops left 8 of
  17,280 `rep30` day-weeks (30-minute pinned repeats, injured beginners, home dumbbells) at 2 exercises, against the
  Unit 2B floor's "no day under 3". Two 2B rules blocked the third exercise:
  - the session cap (6 day-weeks): the lead already at 3 Back sets and a second Back row at 2, so a third Back row at 2
    is 7 > 6;
  - the rank-0 reservation (2 day-weeks, 4-day Maintain): B's copied floored days spent the Quads top before day 1's
    pinned Goblet Squat, the reservation blocked it, and the floor seated Step Up instead (the gate's `lost`).
  The founder amended both (d65, `session_set_allocator.dart` pass 4b'):
  - (a) the floor may seat a reservation-blocked slot: every later day's lead is seated when it runs, so the
    reservation guards nothing there;
  - (b) when only a session cap refuses, the floor takes sets off that group's admitted rows above 2 (most sets first,
    ties to the latest rank; never below 2), so 3 + 2 becomes 2 + 2 + 2. A slot that needs no trim is always
    preferred. Trims are recorded in `AllocationStats.floorTrims` (B inherits a copied day's).
  The floor's kill switch `disable_day_floor` turns both off with the floor.

## 4. Measured (2,304-plan audit, switch OFF vs ON, prototype on 708f9049)

| | OFF | ON |
|---|---|---|
| Cut and Maintain identical | 92 of 576 | 2 of 576 (d63: 3-day bodyweight, intermediate / advanced, 30 min, phase 2; every lift's floor is 8) |
| main-lift week-1 reps = table (or its range bound) | - | 14,238 of 14,238 (3,429 at a bound) |
| accessories in 10-15 | - | 12,633 of 12,669 + 36 Skater Squat, a compound by archetype typed isolation in the dump (correct) |
| Build / strength plans changed | - | 0 |
| plan-weeks newly at 0 (weeks 1-3, any group) | - | 0 (192 newly trained) |
| days over the session (max) | +6 | +6 |
| Maintain week-1 hard sets, mean | 82.0 | 77.3 (Build 89.1) |

### 4b. The Strength focus (`PLAN_AUDIT_FOCUS=strength`, ON vs OFF, 2,304 plans)

| | d60 as first decided (+30 s at every length) | heavy compounds only | d64 (built: +30 s at 60+ minutes) |
|---|---|---|---|
| plan-weeks newly at 0 | 320 (110 plans; 102 group-plans in all 3 weeks) | 156 (56 plans) | 0 |
| main lifts at the range floor, phases 1-3 | 27,934 of 27,942 | - | same rule |
| compound rest M, H: under 60 / 60+ | 150, 180 / 150, 180 | M 120 everywhere; H 180 | 120, 150 / 150, 180 |

The 8 main lifts not at their floor are Bodyweight Squat (12-20): its archetype is calisthenics (B), not a main lift,
though the dump's displayed type reads compound.

## 5. Tests

- `test/contracts/goal_reps_behavioral_test.dart`: the table for every goal x level x phase, main / accessory, the
  focus, the switch, rest (d60), bands (d3).
- `_applyWave` end-to-end over crafted rows: the table, the d58 bound, the accessory clamp, a no-range row, deload
  (phase 4).
- Rest: the allocator prices +30 s under the focus (a crafted day fits fewer sets), the stamp equals the price, a swap
  keeps it.
- Quad-first: a 4-day Maintain plan keeps a hinge; the predicate's goal x days x switch table.
- Kill-switch golden: OFF equals main on the generator golden grid.
- Gate `test/plan_generator/goal_training_gate_test.dart` (the 2,304-plan grid, ON vs OFF, and the Strength focus):
  Build unchanged byte for byte; Cut / Maintain identical OFF 92, ON exactly the two d63 profiles; week-1 reps of
  every main lift (archetype H / M: 14,547, 3,601 at a range bound) equal the table, every accessory (12,360) in
  10-15; 0 plan-weeks newly at 0; days over the session no worse than OFF; under the focus every main lift (29,010 on the 2E tree)
  at its range floor, rest +30 s at 60+ minutes only, 0 newly at 0, and the switch overrides the focus; digests of
  both worlds pinned. (The plan's 14,238 counted the dump's displayed type; the gate classifies by archetype.)
- Neighbouring gate oracles restate the band and the credit in their own words, so they gain 3A's rules: the
  session-set budget gate (`_table`, the 4-day Maintain credit), the day-floor gate lib (the credit; its pins and
  floor-off digest taken with `disable_goal_training` set, so the digest is still main's), the 2C-a credit table (held
  to its own rule with `goalTraining: false`), crafted fixtures through `Fx(goalTraining: GoalTraining.off)` where
  their arithmetic is a pre-3A band. The lead-first gate's opener rule now names a reorder of two rows both worlds hold;
  an ON opener the OFF day lacks (the 2A lead seated where the OFF world's lower top refused it, R1) is counted and
  pinned.
- Neighbouring gates run locally before every push (bug class 2.162): golden, the kill-switch goldens, 2C-b, 2D, 2B,
  2A, 2C-a, B2, the seeded allowance sweep, core-list.
- Golden re-record with per-class attribution.
- A mutation pass on every new branch.

## Review log
