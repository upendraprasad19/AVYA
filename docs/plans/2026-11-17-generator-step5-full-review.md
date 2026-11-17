# Generator step 5: the full plan review after steps 1-4 (2026-11-17)

Board step 5 ("Full plan review after every step"): re-run the 2,304-plan review on main, extended with a simulated
history, injuries and every physique focus, check each step's pass mark, and publish the comparison on the Plan
Explorer page (https://claude.ai/artifact/QTfsRNn2pALY7tTQnbzfku, version 3: a Today / 8 Nov switch on every plan).

- **Tree:** main f7d55205 (PR #291, generator step 4), every generator kill switch at its default.
- **Baseline:** the 8 Nov explorer data (main 0633a121), re-counted with the same definitions.
- **Ledger:** `docs/audit/generator-step5.closure.yaml`.

## Runs

| Run | Harness | Size |
|---|---|---|
| No focus | `plan_audit/plan_audit_dump_test.dart` (`PLAN_AUDIT_OUT`) | 2,304 plans |
| Each physique focus | the same, `PLAN_AUDIT_FOCUS=glutes_legs` / `chest_shoulders_arms` / `strength` | 3 x 2,304 |
| Finisher off | the same, `PLAN_AUDIT_DISABLE=disable_cardio_finisher_shown` (attribution only) | 2,304 |
| Injuries | `injured_grid_dump_test.dart` (`INJURED_GRID_OUT`) | 418,608 days, 8 blocks |
| History | `history_sim_dump_test.dart` (the step 4 gate's library), progress / decline / flat | 576 x 3 |
| Explorer data | the explorer dump, equal to the no-focus audit dump on every row and day minutes | 2,304 plans |

## Verdicts

| Tree | Not suitable | Needs work | Suitable |
|---|---|---|---|
| 8 Nov (0633a121) | 1,502 | 637 | 165 |
| main f7d55205 | 56 | 1,343 | 905 |

The 56 not-suitable plans share one cause: each is a Cut or Maintain plan at 30 minutes with a major group at 0 in a
week. All 56 clear with the finisher switched off, so they are d76's accepted cost (3C plan, §153). Of the 1,343
"needs work" plans, 760 carry a moderate `low_volume` issue and 673 an `unused_time` issue (accepted under 90
minutes, d54 / d55).

## Pass marks

| Step | Pass mark | 8 Nov | main | Result |
|---|---|---|---|---|
| 1 | Household picks (equipped plans) | 1,466 | 0 | met |
| 1 | Jump exercise leading a day (all weeks) | 0 live | 0 | met |
| 1 | Gym Strength OHP Day with no overhead press | 36 of 56 | 0 of 56 | met; the 112 OHP days left use Pike Push Up, and all are bodyweight plans |
| 1 | Plan-weeks without hamstring work (weeks 1-3) | 0 | 60 (20 plans) | accepted, d76: Cut / Maintain 30 min; 0 with the finisher off |
| 1 | Injured days under 3 exercises | 2,286 (11 Nov) | 0 of 418,608 | met; none empty |
| 2 | Accessory more than 1 set above the lead | 7,831 days | 128 days | met with the named residue: all 160 rows involve a timed hold (99 accessories, 61 leads) |
| 2 | Days under 3 exercises | n/a | 0 | met |
| 2 | Plan-weeks without a quad compound | 221 | 0 | met |
| 3 | Cut == Maintain (finisher included) | 149 of 576 | 5 of 576 | accepted, d81 (the same 5 profiles) |
| 3 | Main-lift reps = the table (week 1) | n/a | 13,949 / 13,949 | met |
| 3 | Accessory reps 10-15 | n/a | 12,592 / 12,626 | met with the named residue: the 34 are Skater Squat |
| 3 | Finisher days per week: Cut / Maintain 2, Build / Strength 0 | n/a | every week | met |
| 4 | Over the ceiling ON, all scenarios | n/a | 0 | met |
| 4 | R2 / R5 breaks, new one-set rows, majors newly at 0 | 451 / 149 / 325, 1,538 (pre-fix) | 0 | met |
| 4 | Flat: group-weeks under the bottom | 9,956 OFF | 9,830 ON | met (d82) |

**Time.** No day passes its bound (+6 under 60 minutes, +5 at 60 and over) in any of the four grids (165,888 days).
No titrated day is both longer and over the bound.

## Extended runs

| Focus | Verdicts (not suitable / needs work / suitable) | Over lead + 1, not exempt | Major-zero cells (weeks 1-3) |
|---|---|---|---|
| none | 56 / 1,343 / 905 | 0 (160 holds) | 174 |
| glutes_legs | 52 / 1,195 / 1,057 | 0 (2,384 focus rows, d27; 147 holds) | 156 |
| chest_shoulders_arms | 60 / 1,240 / 1,004 | 0 (6,585 focus rows; 126 holds) | 204 (54 new: Maintain 30 min Hamstrings / Glutes) |
| strength | 56 / 1,359 / 889 | 0 (178 holds) | 174 (the no-focus set) |

- **Zero cells:** every one is Cut or Maintain at 30 minutes.
- **Strength focus:** 28,013 of 28,021 main lifts sit at their range minimum. The other 8 are Bodyweight Squat (archetype B), as the 3A plan states (§4b).

## The 8 Nov findings, then and now

| # | Finding | 8 Nov | main |
|---|---|---|---|
| 2 | Unloaded where a loaded row fits | 1,700 plans | 46 |
| 2 | Leg Press chosen | 0 plans | 8 |
| 2 | Distinct exercises: all plans / full-gym advanced | 124 / 63 | 166 / 55 |
| 3 | Plans with a major at 0 / plans halving a major from week 1 to week 2 | 84 / 265 | 56 / 79 |
| 4 | Lead 2+ sets under an isolation (`lead_starved`) | 876 | 36 |
| 6 | Median minutes used at 90 (beginner / intermediate / advanced) | 53 / 60 / 70 | 56 / 64 / 74 |
| 7 | Major under the bottom in week 1 / under half | 2,288 / 1,341 | 2,281 / 1,199 |
| 8 | Isolation-first days (audit) | 4 | 0 |
| 9 | Deload = week 3 / Front Squat below advanced / bands in a gym / over the top | 48 / 224 / 103 / 485 | 0 / 0 / 33 / 440 |

Notes on the table:

- **#4:** all 36 plans (22 bodyweight, 14 home dumbbells) involve a timed hold, either Doorway Isometric Row as the lead or Hollow Body Hold as the larger accessory.
- **#6:** the 90 chip shows for Advanced only (d70).
- **#8:** five bodyweight 30-minute plans have Pull days with no compound at all, because the tier has no pull-up bar. The audit reads that as "no compound later", not as isolation first.

## Findings for the founder

- **S5-A: Cut and Maintain under the Strength focus.** With the Strength focus, Cut equals Maintain in 60 of 576
  profiles: 58 at 30 minutes and 2 at 45. Without a focus the count is 5 (d81). The cause is that the focus puts
  every main lift at its range minimum for both goals, and at 30 minutes the clock gives both goals the same sets
  (d62).
  - **Recommendation:** accept, on d81's reasoning.
  - **Alternative:** a goal split on accessory reps under the focus.
- **S5-B: Cut and Maintain repeat week 1's exercises in week 2.** This holds in 576 of 576 Cut plans and 576 of 576
  Maintain plans, against 208 for Build and 352 for Strength. It is unchanged since 8 Nov (finding 5), and no step or
  decision covers it. The cause is that their splits have one version of each day.
  - **Recommendation:** keep it. The same lifts week to week carry the progression inside a phase, and
    cross-phase variety changes them at the next phase.

## Measurement notes

- **Finisher-off run, over-time flags.** The run shows 737 plans flagged over time. Those minutes are the stored,
  hidden finisher's, which the harness counts. The app does not show them: every minutes reader goes through
  `FinisherSafety.shownOfRow`, which shows nothing when the switch is set (`lib/features/train/CLAUDE.md`,
  `cardio_finisher_shown`). The run is used only to attribute the zero cells.
- **The explorer dump harness** is a throwaway, adapted to today's API (`finisher:` on
  `estimateDayMinutesFromPlanDay`). It was not committed.
