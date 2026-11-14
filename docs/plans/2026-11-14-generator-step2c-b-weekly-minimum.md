# Generator step 2, Unit 2C-b: the weekly minimum and the 5-minute allowance

Status: v5, 2026-11-14 (after review rounds 1-4, §6; founder d47-d49 recorded in §7; built, diagnose e9b3d7). Written on 2C-a's merged tree (main de30a0a7, PR #272). Supersedes §2B, §4B and §5B of the
parent plan `docs/plans/2026-11-14-generator-step2c-balanced-week.md` (v6), whose prototype (v11b) was measured on the
pre-2C-a tree; everything below is measured on merged main.

- Tier L (plan engine). Blast radius platform. Branch / worktree `generator-step2c-b`. Execution mode (§4.12.7): inline.
- Plan-review record: `docs/plan-reviews/generator-step2c-b.md` (2 rounds minimum, `bpass: accepted`).
- Board t212-t215. Kill switch: 2C-a's `disable_balanced_week` (d37, one switch for all of 2C; OI-509 deletes it).
- No change to `plan_generator.dart` (both waivers, d36 / d40, were 2C-a's and are used up).

## 0. Scope

| Input | What it says | 2C-b answer |
|---|---|---|
| d35 | a weekly minimum of 2 sets for any group the plan trains | S3 targets 1 and 3; residue 22 (plan, group) zero-week pairs for Biceps / Triceps (13 / 9, all 30 min but one), 17 of them the price of 2A's lead (§4.7, §7 Q4) |
| d38 | a focus group the plan holds an exercise for gets at least 2 sets a week | S3 target 2 |
| d42 | 30 / 45-minute days may run 5 minutes over, one allowance, never stacked | S4 |
| d42 (size) | "5 minutes" against the displayed minutes | §4.6, §7 Q2 |
| d44 | under 60 minutes the extra time adds sets, never an exercise (a 30-minute day still shows 4) | S4's row cap; §7 Q1 |
| d45 | at 30 minutes the minimum skips Calves | S3 |
| Parent round 3, B-7 | 3 plans became not_suitable (week 2 Chest at 0) | §1 F3, S3 protect-first and fallback |
| Parent round 1, A-8 | a group credited only by a kept hold read 0 | S3 hold credit, measured (§4.3) |
| Parent round 4, A-12 | `BudgetLedger`'s default | `allowance = false`; production builders pass it |
| Parent round 2, A-6 | the "Up to N min" chip | "About N min" |
| OI-501 | `glutes_legs` lowers Calves and Core | NOT fixed (round 3 R3-1): Calves at 0 is fixed at 45+ only; Calves below the no-focus twin rises 1,816 -> 2,231 and Core 981 -> 1,674 (§4.4); §7 Q3. OI-501 stays open with these numbers |

**Not in scope:** the splits and the credit rule (2C-a, merged); supersets (parent §7.2); repeat-phase minutes (2D);
other goals' splits; the selector's picking rules.

**Who changes** (measured, 2,304 plans, §4): 574 of 576 plans at 30 minutes (the 2 fallback plans equal today's;
576 without the S4 signal) and 571 at 45 (S4 and S3); at 60 and 90
minutes one plan each (`strength|4|intermediate|bodyweight|{60,90}|1`: S3 seats Self-Resisted Bicep Curl in place of
Prone T Raise, Back 20 -> 16 in week 2 and 10 -> 8 in week 4, Biceps 0 -> 4 in week 2 and 0 -> 2 in week 4). S3 reaches 60+ rarely because at 60+ both variants of today's plans already
train the same groups.

**Where it runs:** the lead-first path (`_allocateLeadFirst`) with the day floor ON, on both the 5-day-and-under and
the 6-day branch. With 2A off (`leadFirst: false`) or 2B off (`dayFloor: false`) the allocation is that unit's pre-unit
allocation byte for byte, as their contracts say (`session_set_allocator.dart:201-204`); 2C-b does not run there. With
`disable_balanced_week` set, the output is R (below) byte for byte. A test pins each.

## 1. What the re-measure on merged main found

Each finding comes from the prototype re-run on de30a0a7 (scratchpad `step2cb/`, audits `audit_m0` = merged main,
`audit_b0` = parent v11b, `audit_b6` = this plan's design). `audit_b9` is b6 with the protective reference taken from R
and the first allowance re-run only (b6 also unioned the floor-off world-choice stats): its 2,304 plans are byte-identical
to b6's, so the plan specifies the R-only form. **v2's design is `audit_b10`** (b9 plus round 1's fixes, applier
`step2cb/apply_v2.py`). The prototype as one file: `step2cb/proto_v2/` (`session_set_allocator.dart`,
`session_budget.dart` and their diffs against HEAD; the prototype's `BudgetLedger` defaults `allowance` to true, so
`_weekTwoGains` and titration ran with it, §4.5; the build's default is false and only `_weekTwoGains` passes it).

- **F1. v11b reproduces.** Its 30 / 45 group-level gains and losses equal parent §4B.2 exactly; against merged main:
  955 suitable, 30 regressed, 96 improved, the same 3 not_suitable plans (B-7).
- **F2. v11b's row cap was not today's rows.** It capped each day at the rows of the world chosen with the floor OFF
  (`capA` from `aM` / `a`), not at today's output (the floor re-run). 2,397 day-weeks under 60 minutes (weeks 1-3;
  3,198 with the deload week) hold more rows than today in v11b. Parent §4B.2 ("4 on most days; 5-6 only where today's day already holds them") was not true of
  v11b. Fix: the reference is today's exact output (S3, "the reference").
- **F3. B-7's cause** (traced with a one-persona harness, `build_muscle|3|advanced|bodyweight|30|{1,2,3}`):
  - phase 1: in variant B, Triceps is at 0 today while A trains it, so d35 makes Triceps a target. Its cheapest slot
    (Tricep Dips Floor) takes the day's last row under the row cap and displaces Hindu Pushup, the week's only Chest
    credit. Chest is then a "lost" target, but no row is left (`seated 2/2`). This is a state inside the fixpoint
    (traced with debug prints); the final v11b dump shows the last round's result (V-Up in Hindu Pushup's place).
  - phases 2 / 3: the allowance re-run seats the rank-0 Elevated Pike Push Up (today it does not fit) and keeps a hold
    today evicts (Copenhagen Plank); under a 4-row cap that leaves one budgeted seat, the lead's.
  The hold-credit rule alone does not fix it (measured: still 3 not_suitable). Fixed by the fallback (S3 step 5) and
  the reference's hold evictions (S4); on v3 protect-first fires in 2 plans and rescues neither (each is then caught
  by the fallback; on v1 it rescued 1), so it stands on its crafted fixture alone (round 3 R3-7).
- **F4. A hold the reference evicted came back** in 9 day-weeks (a 5th row on a 30-minute day) when the allowance
  re-run had the time to keep it. Fix: S4's "today's hold evictions stand".

## 2. Design

### S4. The allowance (d42, d44)

**The budget.** `BudgetLedger(ctx, n, {bool allowance = false})`: under 60 minutes, with the switch ON and `allowance`
true, the day budget gains 300 s and `forcingBound` is 0; otherwise `forcingBound` is today's
`SessionBudget.maxForcedOverSeconds` (300 s). Pass A2's forcing and S3's seats read `ledger.forcingBound`, so the
allowance and the forcing never stack. The default keeps every direct-ledger test on today's budget
(`session_budget_test.dart:320-349`, `session_set_allocator_behavioral_test.dart:370, 399, 738`,
`day_floor_behavioral_test.dart:55, 216`, `session_set_budget_consumers_test.dart:329`).

**The size** is `SessionBudget.allowanceSeconds`, 300 s (d42's "5 minutes") unless the founder picks 240 s (§4.6,
§7 Q2): one constant, one test.

**Who passes `allowance: true`:** the allocator's 2C-b re-runs (below), and `PeriodizationEngine._weekTwoGains`
(`periodization_engine.dart:168`), which builds its own ledger over the same ctx: week 2's +1 sees the same day budget
as the allocation it grows. **`VolumeTitration` does not** (round 4 R4-1): it titrates `WeekPlan`s
(`VolumeTitration.applyToWeeks(weekPlans, ...)`, `plan_generator.dart:332`), whose `WorkoutDay` has no allowance field
and is persisted by `toMap`, so the signal cannot reach it without a carrier through `plan_generator.dart`. Its ledger
(`volume_titration.dart:181`) keeps `allowance: false`: a +1 must fit today's budget, so on a day the allowance already
grew the +1 is refused (conservative: fewer sets, never past the allowance). Titration is opt-in
(`enable_volume_titration`, off by default) and every audit here ran it off, so nothing measured changes. Measured both ways (§4.5): mixed, and better with it on the measures that do not depend on Q2's display
bound. **The readers follow the allocator's own outcome** (round 2 A-1 / B-2, round 3 R3-3): `PopulatedDay` gains
`final bool allowance` (default false; `models.dart:351`), which the allocator sets true on every day it returns only
when 2C-b ran (lead-first, floor ON, switch ON), the plan is under 60 minutes and step 5 did not fall back.
`generateV4` hands the allocator's list unchanged to `PeriodizationEngine.apply` (`plan_generator.dart:293-301`), so the
signal needs no edit there (rule 14). `_weekTwoGains` passes `allowance: days.isNotEmpty && days.first.allowance`
to its ledger (one value per plan). A user with 2A or 2B off, a 60+ plan and a fallback plan all
get today's week 2. Measured (b23 = v3 + the signal): the 2 fallback plans
(`build_muscle|3|advanced|bodyweight|30|{2,3}`, the B-7 persona) go back to today's week 2 (34 row-sets, b18 40), and
with it to today's verdict (needs_work, `ab_swing` Chest / Back); every other plan is byte-equal to b18. So the design
as specified measures 969 suitable, not b18 / b10's 971 (§4.1).

**The switch** reaches the allocator as an argument, like 2A's and 2B's: `allocate(..., bool? balancedWeek)`, null
reading `PlanEngineFlags.balancedWeekEnabled` (2C-a, `plan_engine_flags.dart:88`). `SessionBudget`'s ledger takes the
allowance as a constructor argument only (pure); the two readers read the days' `allowance` field, not a flag.

**The row cap (d44).** Under 60 minutes, an allowance re-run may seat on each day at most the rows the reference held
that day (budgeted and not), within the level's count max: `target[d] = min(target[d], rowCap[d] - nonBudgeted[d])`.
Measured: 0 day-weeks hold more rows than today, and 0 fewer (§4.1).

**Today's hold evictions stand** (under 60 only, with the row cap; round 2 A-6). A library hold the reference evicted (pass A's "a hold may give way to a time-starved
slot") is evicted in every allowance re-run too: `_variant(refEvicted:)`, the same mechanism a copied B day already
uses (`copyEvicted`). Without it the extra time keeps the hold and a 30-minute day gains a 5th row (F4).

**Worlds are chosen without it** (parent round 2, A-4): every world-choice `_variant` call runs allowance-off, so the
choice equals today's.

**Readers outside the allocator** (re-verified on de30a0a7):
- `budgetedDaySeconds` (`session_estimate.dart:31`; Train, Home, and `SwapService` at `swap_service.dart:764`) sums
  the stored rows and `budgetedDayMinutes` rounds them (`:23-25`), so a "30" day shows about 35. The display estimator
  runs past the ledger on some days: at 300 s, 701 day-weeks at 30 minutes and 789 at 45 display +6 (§4.6, §7 Q2).
- `WarmupCooldownSelector` and `warmCoolMinutes` read `ctx.minutes`, not the ledger: unchanged.
- The Edit Profile chip reads `'Up to $min min'` (`edit_profile_screen.dart:1150`), its comment, `lib/features/profile/
  CLAUDE.md:47` and `session_duration_chip_wording_test.dart:4, 15, 31`. The build changes the chip to
  `'About $min min'` and the three citations (d42 keeps the numbers; this keeps the words true).

### S3. The weekly minimum (d35, d38, d45)

**The reference R** is today's output, byte for byte: the floor re-run of the chosen worlds (`allowance: false`) on
the lead-first path (where 2C-b runs, §0), for both variants, or for A alone on the 6-day branch. With the switch OFF,
R is returned and nothing below runs.

**Credited groups** of a variant: groups with weekly budgeted sets > 0, plus the groups of the library holds the
variant kept (hold credit, parent A-8). Written `cw` below; `AllocationStats.holdGroups` records the hold groups.

**Targets** (per variant):
1. *new, d35:* a group the other variant credits and this one does not;
2. *new, d38:* a focus group this variant does not credit;
3. *protective:* a group R or this path's first allowance re-run (step 1) credits and this run does not.

**Calves under 45 minutes is never a target of any kind** (d45 over d38, round 1 A-4 / B-2: with the focus exempt the
30-minute `glutes_legs` plan traded Glutes / Quads rows for Calves). "Under 45" and "under 60" are on the resolved
minutes, which `resolveMinutes` keeps in 15-180: a 40-minute profile value behaves as 30 (no Calves target, the
allowance), a 50-minute one as 45, 60+ as 60.

**The minimum pass** (inside `_variant`, after pass A, A2 and the 2B floor, before the count verdict) seats, for each
target still at 0 and not credited by a hold this run kept (round 1 A-9), sorted by name, its cheapest remaining slot
at 2 sets:
- not admitted, not `reserveBlocked`, not a `_Why.target` refusal;
- the day's count: the day's ADMITTED budgeted rows `< target[d]` (round 1 A-1: pass A's `seated` misses A2 and floor
  seats; `target[d]` includes the row cap);
- never past a session cap, never past another group's weekly top (the ledger's top counts budgeted sets; a kept
  hold credits its groups above it, as today: the audit's minor `over_top` rises in 72 issues, all bodyweight Back /
  Shoulders in week 1, against 407 plans on main);
- within `ledger.forcingBound`;
- ties go to the day with the most seconds left.
Seats are recorded in `AllocationStats.minimumSeats` (keyed by day like `floorSeats`; B's copied days inherit A's, as
they inherit `floorSeats`), never in `countForced`.

**The walk** (parent round 2, A-2 / A-3 / B-2; round 1 A-8): pass A walks `walk[d]`, a copy of `byDay[d]` in which
each target's cheapest slot follows the rank-0 slot, the day's 2A opener (when it sits later) and earlier moved
targets; a target already inside that segment counts as moved. `byDay`, `_Slot.rank`, B's copied days, `entries`,
passes B / C / D, the floor ties, `firstLifts` and `leadSeats` keep the selector order; `evictFor` gets the slot's own
`rank`. Measured (§4.7): with the opener protected, today's first row is never dropped (13 day-weeks without it); the
cost is 17 more zero-week pairs.

**The steps** (5-day-and-under path; the 6-day path is the same with B = A and no target 1):
1. *Allowance re-run* (under 60 only): A, then B copying the new A, with `allowance: true`, the row cap and today's
   hold evictions. At 60+ this step is R.
2. *Targets* from step 1: A gets 1-3; B gets 2 and 3, plus target 1 against the current A inside the loop (round 3
   R3-5: the prototype's `need` gives B its focus target too).
3. *Fixpoint*, at most 4 rounds: re-run A with its targets, then B against the new A; a protective group now at 0
   joins its variant's targets.
4. *Protect-first* (F3): if a protective group is still at 0, re-run both variants with only the protective targets
   (all new targets dropped together). A new target (1 or 2) never takes the row of a group the plan already trains.
5. *Fallback, the terminal guard* (F3, round 1 A-2): if a protective group is STILL at 0, the output is R, verbatim,
   at every length (no allowance either). Nothing runs after it.

Every re-run in steps 1, 3 and 4 carries the same arguments: the chosen world, `dayFloor: true`, and under 60 the
allowance, the row cap and R's hold evictions. At 60+ steps 1-4 run without the allowance or the row cap, so the output can
differ from R only by minimum seats (one plan per length on the grid). The minimum only adds after the worlds are
chosen; `worldIsWorse` is not re-asked.

On the 6-day branch: step 1 re-runs A; targets 2 and 3 only, and the protective set is R's credit only (round 2 A-5:
the prototype has no step-1 union there); steps 3-5 the same with B = A (prototype v2: inert on the grid, no 6-day
group other than Calves at 30 is newly at 0).

**Not carried into the build** (round 2 A-8): the prototype's unused `preOffA` / `preOffB` / `rowCapOn` locals and
`_pinTo`. The walk's skip test ("rank 0 already credits the group") stays rank-0 only; a target whose group the 2A
opener credits may still be moved (harmless: it only reorders pass A; unmeasured).

**Residue** (`MINMISS` traces): a variant with no exercise for the group (the selector's lists); a day whose row cap
is held by the lead and kept holds.

## 3. Founder decisions this plan builds in

d35, d37, d38, d42, d44, d45 (parent §3), and 2A's d26-d29 (the lead; §4.7). Open for the founder at the end of the review rounds: §7 Q1-Q4.

**Not measured** (round 3 R3-8): injured plans and repeat-pin phases (their sweeps run in CI as callers, not as a
measurement), and the resolved focus of phase 2+ plans (`TrainingHistoryAnalyzer.resolveBodyFocus`, laggard muscles).
The five-focus grid is measured in §4.8.

## 4. Measured (2,304 plans, no focus unless stated; weeks 1-3 unless stated; scripts in scratchpad `step2cb/`:
`m10.py`, `mx.py`, `mx2.py`, `newmajor.py`, `gl2.py`)

### 4.1 Totals against merged main

| Measure | Merged main (2C-a) | Parent v11b (b0) | v1 (b9) | **v2 (b10)** |
|---|---|---|---|---|
| Suitable / needs_work / not_suitable, over-time issues excluded | 886 / 1,390 / 28 | 955 / 1,346 / 3 | 969 / 1,335 / 0 | **971 / 1,333 / 0** |
| The same, over-time issues included (the audit's +5 check, §4.6) | 886 / 1,390 / 28 | | 692 / 1,612 / 0 | **694 / 1,610 / 0** |
| Plans regressed / improved (over-time excluded) | | 30 / 96 | 23 / 106 | **23 / 108** |
| Plans with a NEW major issue | | 3 (B-7) | 0 | **0** |
| (plan, group) pairs with a zero week | 134 | 73 | 54 | **71** (Calves 49 at 30 min, d45; Biceps 13, Triceps 9) |
| Plan-weeks a group today trains goes to 0 | | Calves 147, Chest 3, Triceps 2 | Calves 143 | **Calves 143** at 30 min (d45; 196 with the deload week) |
| Plans losing Calves in all of weeks 1-3 | | | 53 | **53** (30 min, d45) |
| Day-weeks under 60 with more / fewer rows than today | 0 / 0 | 2,397 / | 0 / 0 | **0 / 0** |
| Day-weeks under 60 whose exercise set changes (30 / 45 min) | | | 938 / 124 | **914 / 123** (279 plans) |
| Day-weeks whose first row changes / today's first row dropped | | | 76 / 13 | **63 / 0** |
| Days whose first row equals today's with fewer sets | 0 | 66 | 48 | **48** of 31,041 (the weekly top, §6 B-7) |
| (plan-week, group) pairs whose sets fall (all goals) | | | 671 | **649** |
| Max display minutes over at 30 / 45 / 60 / 90 | 4 / 1 / 1 / 1 | 6 / 6 / 1 / 1 | 6 / 6 / 1 / 1 | **6 / 6 / 1 / 1** |
| Wall clock of the whole 2,304-plan audit test (one run each, VPS; not a per-plan or device measure) | 2:20 | | 2:20 | **2:06** |

**With the allowance signal (b23, the design as specified, S4):** suitable 969 / 1,335 / 0, 692 with the over-time
check, regressed / improved 23 / 106. Only the 2 fallback plans differ from b10 / b18 (back to today's week 2 and
verdict); every other row above is unchanged.

- **v2 falls by goal and length** ((plan-week, group) pairs, of 1,728 plan-weeks x 10 groups each): build_muscle 30 / 45
  min 88 / 40; general_fitness 141 / 33; lose_fat 162 / 26; strength 139 / 18; 60 and 90 min one each (the strength
  plan, §0). Total weekly sets fall in 0 of 9,216 plan-weeks (v1: 1); under 60 they rise on average 7.4 a week at 30 minutes and
  7.8 at 45 (weeks 1-3).
- **The 28 not_suitable plans on main** are lose_fat / general_fitness 3-day 30-minute plans with Shoulders at 0 in
  weeks 1-3 (84 major zero_muscle issues). S4 re-picks rows within the same count and seats a Shoulders exercise; they
  need the full allowance (§4.6).
- **The 23 regressions:** build_muscle 30 min 14, lose_fat 30 min 4, general_fitness 30 min 4, strength 45 min 1. New
  moderate codes: ab_swing 15 issues in 15 plans (the allowance grows the A weeks 1 / 3 while B's week 2 stays, so the
  audit's 2x A/B ratio is crossed; 89 of all 112 new ab_swing issues are "the high week rose, the low week unchanged";
  the pin has the same regressions, so it is the allowance, not the minimum),
  lead_starved 8 plans. The 8 have a timed hold as their first row (for example Doorway Isometric Row, `timed`, at 3
  next to Sliding Lat Pull at 5); the budgeted lead and 2A's R2 are intact, and the audit reads the first row. None of
  the 23 holds a day past the count max by `effectiveLevel`, a lead below today's sets, or a group at 0 other than
  Calves at 30.
- **Protect-first / the fallback fired** in 2 / 2 plans, all 30 minutes (v2 counter run, `audit_b21.log`; v1: 3 / 2).
  In them d35 is given up (the phase-1 week-2 Triceps stays at 0, as today).
- **R's hold evictions under 60 only** (round 2 A-6): b18 is byte-identical to b10; the two 60 / 90 plans that differ
  from main differ by a minimum seat.
- "Display minutes" is the estimator's rounded `min` in the dump; the gate checks the ledger's seconds.

### 4.2 The pinned alternative (b4, on v1; re-run on v2 as b19 / b20 for §7)

The minimum at today's budget first, then the allowance re-run restricted to those rows. 951 suitable, 28 not_suitable
(today's, unchanged), 21 regressed, 86 improved, 0 new majors, zero-week pairs 70. It still swaps rows (110 / 8
day-weeks at 30 / 45, 60 plans: the minimum's swaps happen before the pin) and has 12 day-weeks with FEWER rows than
today (a 30-minute day showing 3: lose_fat / strength 6-day beginner home_dumbbells, phase 1), so it is not "today's
exercises exactly" either. (plan-week, group) falls 254; plans losing Calves in all of weeks 1-3: 0.

### 4.3 Hold credit, counterfactual (b22 = v2 without it; v1: b7)

Zero-week pairs 71 -> 92 (Triceps 9 -> 19, Core 0 -> 11; Biceps 13 either way), suitable 971 -> 968. Without the
credit a group trained only by a hold is a target and takes another group's row. (On v1 the same: 54 -> 70.)

### 4.4 The `glutes_legs` focus (focus groups Calves, Glutes, Hamstrings, Quads), against the no-focus twin

| Measure | Merged main | v1 (b6) | **v2 (b10)** |
|---|---|---|---|
| Plan-weeks Calves at 0 where the twin trains them | 503 | 0 | **569** |
| Inert plans (no focus group above the twin in any week 1-3) | 729 | 334 | **540** |
| Plan-weeks a focus group is lower than the twin: Glutes / Quads / Hamstrings / Calves | 7 / 244 / 968 / 1,816 | 772 / 703 / 1,234 / 1,891 | **7 / 265 / 1,143 / 2,231** |
| Plan-weeks Core is lower than the twin | 981 | 1,719 | **1,674** |
| 30 min, the focus plan's mean weekly sets: Glutes / Quads / Hamstrings / Calves | 10.74 / 5.39 / 3.81 / 0.43 | 10.42 / 5.31 / 4.21 / 2.13 | **12.11 / 5.92 / 4.37 / 0.19** |
| 30 min, focus plan-weeks with Calves at 0 | 1,358 | 11 | **1,567** |

v1 seated Calves at 30 for the focus and traded Glutes / Quads rows for it (round 1 B-2); v2 applies d45 to the focus
too, so the 30-minute focus plan keeps and grows its Glutes / Quads work and leaves Calves to 45+. Costs for the
founder: Core below the twin rises (OI-501: 981 -> 1,674), Hamstrings below the twin rises (968 -> 1,143), and at 30
minutes the focus plan's Calves stay at 0 more often (d45). d38 is "at least 2 sets", not "never below the no-focus
plan"; the twin gains from the minimum too.

### 4.5 `_weekTwoGains` and titration with and without the allowance (b10 vs b12)

| | Readers pass the allowance (b10) | Readers do not (b12) |
|---|---|---|
| Suitable (over-time excluded / included) | 971 / 694 | 969 / 700 |
| Plans with an over-time issue | 449 | 429 |
| (plan-week, group) falls | 649 | 687 |
| First row equal to today's with fewer sets | 48 | 67 |

Chosen: `_weekTwoGains` passes it, following `PopulatedDay.allowance` (S4; titration does not, R4-1); "mixed": b12 is ahead only on the over-time-included
measures, which depend on Q2's display bound.

### 4.6 The allowance size against the displayed minutes (on v2)

| Allowance | Suitable / not_suitable (over-time excluded) | Day-weeks displaying +6 (30 / 45) | Plans with an over-time issue | Suitable, over-time included |
|---|---|---|---|---|
| 240 s | 923 / 28 | 0 / 0 (max +5) | 0 | 923 |
| 270 s | 941 / 28 | 325 / 133 | 170 | 851 |
| 285 s | 967 / 0 | 467 / 394 | 307 | 777 |
| **300 s** | **971 / 0** | 701 / 789 | 449 | 694 |

**The display, not just its maximum** (round 2 B-6; weeks 1-3, 7,776 day-weeks per length):

| | Main | v2 at 300 s | v2 at 240 s |
|---|---|---|---|
| 30 min: mean display minus the label / share at +3 or more | +0.46 / 13.8 % | +4.14 / 93.8 % | +3.19 / 75.0 % |
| 45 min: the same | -0.93 / 0 % | +3.11 / 79.4 % | +2.27 / 70.7 % |
| Day-weeks displaying +5 or +6 (of 15,552) | 0 | 6,241 (40.1 %) | 1,339 (8.6 %) |

The allowance is nearly always used: a "30" profile typically shows 33-36 minutes, which is why the chip says "About".

No size keeps every day's display at +5 or less AND fixes today's 28 plans: 270 s does not fix them (all 28 stay) and
already displays +6 on 458 day-weeks, 285 s fixes them; the 28 plans' own fixed days display +6 on 108 day-weeks at
both 285 and 300 s, so the fix itself needs a +6 day. Sizes 271-284 are untested; the counts are monotone across 240 /
270 / 285 / 300 (+6 day-weeks 0 / 458 / 861 / 1,490; suitable 923 / 941 / 967 / 971). The display runs past the ledger
because the estimator and the ledger price a day differently (inferred, not measured: the dumps carry the display minute only; at 4.5 minutes of allowance a +6 already
appears, so on that day display minus ledger is at least about 1 minute). The +6 days all hold 4+ rows, no timed rows
and no supersets, so it is not the floor's overrun. The build adds a ledger-seconds field to the dump and reports the
gap distribution. §7 Q2.

### 4.7 The walk's opener rule (round 1 A-8), counterfactual (b14 = v2 without it)

| | With (b10) | Without (b14) |
|---|---|---|
| Day-weeks where today's first row is dropped | 0 | 13 |
| Day-weeks whose first row changes | 63 | 76 |
| Zero-week pairs | 71 | 54 |

Kept: 2A's lead (d26-d29) outranks 17 zero-week pairs. Round 1's A-1 (count all admitted rows) and A-9 (kept-hold
skip) change no plan on the grid (b13 / b15 are byte-identical to b10); they are guards for the cases the
grid does not sample, each with its own fixture (§5).

### 4.8 The five-focus grid (round 3 R3-8)

`focus_grid_dump_test.dart`: five focus sets (`biceps`, `chest`, `core`, the upper set, `glutes_legs`) x every goal,
day count, level and equipment at 30 and 45 minutes (5,760 plans), v3 + the signal at 300 s (`audit_bfg`) against
merged main (`audit_mfg`), weeks 1-3; groups from the library's primary muscles (`fgcmp.py`). The dump carries no
audit verdict, so new majors are not measured on this grid.

- **Groups newly at 0** (a plan-week main trains and 2C-b does not): Calves at 30 minutes only (d45), 143 plan-weeks
  in each of the `biceps`, `chest` and upper sets, 155 in `core`, 209 in `glutes_legs`; 369 plans. No other group and
  no 45-minute plan-week.

| Focus, minutes | Focus groups' weekly sets, main -> 2C-b | Focus-group plan-weeks at 0, main -> 2C-b |
|---|---|---|
| biceps 30 / 45 | 2.7 -> 3.7 / 6.4 -> 8.6 | 486 -> 114 / 284 -> 1 |
| chest 30 / 45 | 6.0 -> 7.5 / 8.5 -> 9.5 | 0 -> 0 / 0 -> 0 |
| core 30 / 45 | 4.6 -> 5.7 / 9.3 -> 11.1 | 346 -> 54 / 0 -> 0 |
| upper (Chest, Shoulders, Triceps, Biceps) 30 / 45 | 19.8 -> 23.7 / 31.3 -> 37.2 | 1,499 -> 285 / 608 -> 1 |
| glutes_legs 30 / 45 | 20.7 -> 22.9 / 28.2 -> 31.9 | 1,358 -> 1,567 (all Calves, d45; §7 Q3) / 192 -> 0 |

- **d38's residue at 45 minutes:** one Biceps plan-week (in the `biceps` and the upper set alike).
- **d38's residue at 30 minutes:** Biceps 114 plan-weeks (3- and 4-day bodyweight / home_dumbbells, all goals; the same
  114 in the upper set), Triceps 171 (upper set), Core 54 (`core`, mostly build_muscle 3-day, 12 on 6-day). One plan
  traced (`biceps|strength|3|advanced|home_dumbbells|30|1`): every day holds 3 budgeted rows and a kept Hollow Body Hold,
  and the row cap is today's 4 rows, so no day has room for a curl: S3's residue class "a day whose row cap is held by
  the lead and kept holds" (d44 over d38). The other plans are not traced one by one.

## 5. Tests and files

**Production:**
- `session_budget.dart`: `BudgetLedger(allowance:)`, `forcingBound`, the switch read.
- `session_set_allocator.dart`: `allocate(balancedWeek:)`; `AllocationStats.holdGroups` / `minimumSeats`;
  `_variant(allowance:, minGroups:, rowCap:, refEvicted:)`; the minimum pass and the walk; the 2C-b post-step (steps
  1-5) on the lead-first path, both branches; pass A2 reads `ledger.forcingBound`.
- `periodization_engine.dart:168`: `allowance: days.first.allowance` (§4.5); `volume_titration.dart:181` unchanged
  (`allowance` defaults to false, R4-1).
- `SessionBudget.allowanceSeconds` (§7 Q2).
- `edit_profile_screen.dart:1150`: "About"; its comment.

**Behaviour tests, `test/contracts/weekly_minimum_behavioral_test.dart`:**
- each guard refuses (cap, top, forcing bound, the count incl. the row cap);
- **the count counts A2 and floor seats** (round 1 A-1): a day whose pass A seated fewer than `target[d]` but whose A2
  or floor seat filled it refuses the minimum (the grid never reaches this: b13 = b10, so the fixture is the proof);
- the cheapest slot, the tie rule, target order;
- targets 1, 2, 3; Calves under 45 skipped for every target kind incl. a focus, at 45 not; minutes 40 / 50 behave as
  30 / 45;
- hold credit: a hold-only group is not a target, and a group whose hold this run kept is not seated (A-9; b15 = b10,
  fixture);
- no slot means no seat; `minimumSeats` (and B's copied days inherit it), never `countForced`;
- the walk leaves `rank`, B / C growth order and `leadSeats` alone; `evictFor` uses the slot's rank; a target goes
  after the 2A opener when the opener is not rank 0 (A-8; the opener keeps its seat);
- copy-day alignment: a copy day plus a target on another day; B's copied day equals A's slot for slot;
- the fixpoint restores a group the first re-run zeroed;
- **protect-first**: a crafted week where a target-1 seat displaces a protective group's only row; the group keeps it;
- **the fallback**: a crafted week where protect-first cannot restore the group; the output equals R exactly, at 30
  and at 60;
- where it runs: lead-first floor ON (5-day and 6-day branches, the `kept == null` case) changes; `leadFirst: false`
  and `dayFloor: false` equal their pre-unit output with the switch ON; switch OFF equals R.

**Behaviour tests, `test/contracts/session_allowance_behavioral_test.dart`:**
- `allowanceSeconds` under 60 with the switch ON, none at 60+ or OFF; `forcingBound` 0 / 300; no day past budget +
  the allowance;
- worlds chosen allowance-off (the lead keeps its base sets where it does today);
- the row cap: no day holds more or fewer rows than R's that day; today's hold evictions stand (F4's fixture);
- 2A's R2 holds in the allowance re-run (no budgeted row above the budgeted lead + 1 outside pass D);
- `PopulatedDay.allowance` (round 4 R4-2 / R4-7): true on every returned day only when 2C-b ran under 60 without the
  fallback; false with 2A off, 2B off (the floor off), the switch off, at 60+, on the fallback, on the `kept == null`
  path and on a 6-day fallback; one fixture per case, and mutants that set it true on the fallback and with the floor
  off (the prototype's probe did the latter);
- `_weekTwoGains` reads `days.first.allowance` (a fixture where it is false gets today's week 2; an empty list reads
  false); `VolumeTitration` builds its ledger with `allowance: false` (with `enable_volume_titration` set, a +1 on a
  day the allowance filled is refused; mutant: pass true);
- **through `generateV4`** (round 2 A-1 / B-2): with 2A off, and with 2B off, at 30 minutes and the switch ON, the plan
  equals the pre-2C-b digest; with the switch OFF it equals main's (the kill-switch goldens set it already).

**A 60+ fixture for S3** (round 1 B-5: on the grid only one plan per length changes at 60 / 90): a crafted 60-minute
week where variant B lacks a group A trains, so the minimum seats it; the oracle excuses the seat within the forcing
bound.

**Gate, `test/plan_generator/balanced_week_gate_test.dart`** (2C-b part, grid at 30 / 45 / 60 / 90):
- no plan gains a major issue against the OFF run;
- no group newly at 0 against the OFF run except Calves at 30;
- no day past R's rows under 60; no day past the count max by `effectiveLevel`;
- no day past budget + 300 s + the floor's overrun (ledger seconds);
- zero-week pairs at or under §4.1;
- at 60+, a plan with no target equals R exactly (round 2 A-6, round 3 R3-6);
- the `allowance` field: true only on the under-60, 2C-b-ran, no-fallback plans; the fallback plans' week 2 equals
  today's.

**Shared oracle:** `budget_invariant_oracle.dart`'s `excusedSeconds` (`:61-71`) gains an `allowanceSeconds` parameter
(default 0) and a `minimumSeats` excuse within the forcing bound; on-path callers pass the allowance, so the OFF worlds
(switch off, 2A off, 2B off) keep today's strict check (round 1 A-6, round 2 A-7). Five tests compute their own time limit instead
of the oracle's and are moved onto it: `test/plan_generator/oi489_timed_hold_real_engine_test.dart:105`,
`session_set_budget_consumers_test.dart:349`, `session_set_budget_wiring_test.dart:187`,
`session_set_allocator_behavioral_test.dart:772`, `test/plan_generator/session_set_budget_gate_test.dart:363-366` (the other three in `test/contracts/`; lines on de30a0a7;
round 1 cited the fifth as `balanced_week_gate_test.dart:363`, which has 192 lines). Two more read the forcing bound
directly and are re-read against `ledger.forcingBound`: `exercise_count_band_behavioral_test.dart:54, 94, 125` and
`day_floor_behavioral_test.dart:71`.

**The policy for existing tests** (round 2 A-3): `allocate(balancedWeek:)` defaults to the flag (ON), so every direct
call at 30 / 45 minutes on the lead-first, floor-ON path now gets 2C-b. A test that pins pre-2C-b mechanics passes
`balancedWeek: false` (and the fixtures in `test/helpers/session_budget_fixtures.dart:80` forward it, as they forward
`leadFirst` / `dayFloor`); a test of the new behaviour uses the default. The direct callers on de30a0a7:
`exercise_count_band_behavioral_test.dart:170` (30 min, `countForced[0] == ['h3']`: changes, since `forcingBound` is 0),
`rest_by_type_behavioral_test.dart:241` (30 min), `session_set_allocator_behavioral_test.dart:718`,
`session_set_budget_consumers_test.dart:316`, `day_floor_behavioral_test.dart:486`,
`quads_credit_flag_consumers_test.dart:72, 84`, and the fixture. `PeriodizationEngine.apply` / `VolumeTitration`
direct callers (`volume_titration_behavioral_test`, `plan_engine_v4/*_archetype_test` and its helpers) default to 60
minutes (`testBudget`) and are run too.

**Builder specifics** (round 3 R3-10):
- `_variant(..., bool allowance = false, Set<String> minGroups = const {}, List<int>? rowCap, Map<int, Set<int>>?
  refEvicted)`: the default is false (the prototype's true default is not carried); every 2C-b re-run passes
  `allowance: ctx.minutes < 60`.
- `AllocationStats.minimumSeats`: `Map<int, List<({String name, String group})>>` keyed by day, the shape of
  `floorSeats`, filled where the seat is made; a copied B day copies A's entry for that day, as `floorSeats` does
  (`session_set_allocator.dart:522-523`).
- `AllocationStats.holdGroups`: `Set<String>`, filled at the end of `_variant` from the kept holds.
- `PopulatedDay.allowance`: `final bool allowance` (default false; `PopulatedDay` has no `copyWith`, so every
  constructor call in the allocator passes it); set by `_allocateLeadFirst` on every returned day (one value per plan);
  the byte-equal replay of the prototype also compares this field per plan (R4-7).
- The ledger-seconds field in the audit dump: the dump test prices each stored row with
  `SessionBudget.plannedExerciseSeconds` (the allocator's own spend) and writes the day's seconds next to `min`; the
  gap distribution (display minus ledger) is reported in the diagnose doc.
- The gate's "major issue": `PlanAuditor` (`plan_audit_lib.dart`) over all goals at 30 / 45 minutes, ON and OFF
  (1,152 plans each), plus the existing 60 / 90 build_muscle grid; the 60+ "equals R" check runs on that grid.
- Direct `allocate` callers not listed above (90 minutes or `leadFirst: false`, so unchanged, run anyway):
  `rest_by_type_behavioral_test.dart:98, 210`, `session_set_allocator_behavioral_test.dart:861`,
  `quads_credit_flag_consumers_test.dart:47-99`.

**The build reproduces the measured prototype** (round 2 A-4: the prototype defaults `allowance` to true, the build to
false, so a missed explicit `allowance: true` changes every number): a one-off proof in the build, the 2,304-plan audit
dump on the built code byte-equal to the chosen prototype run's `plan_dump.jsonl` (as 2C-a did with va2fb).

**Every caller file is run** (parent round 3 A-3): the 19 test files that name `SessionSetAllocator`, `BudgetLedger`,
`AllocationStats`, `debugLastStats` or the oracle, and the 34 more that call `generateV4` (53 in all, listed in
`step2cb/callers.txt`); each red is named with its cause in the diagnose doc. Known before the build:
`session_duration_chip_wording_test` (the chip), `plan_audit_lib_test` (the over-time mirror, §7 Q2), the golden.

**Mutants:** one re-run without `allowance: true` (A-4); `PopulatedDay.allowance` set true on the fallback / with the floor off / at 60+; titration passing `allowance: true`; each guard and target clause; the allowance and the no-stack rule; `allowance: false` in each world-choice
call; the row cap; `refEvicted`; the walk (mutating `byDay`); `evictFor`'s rank; the fixpoint; protect-first
(skipped; all targets kept); the fallback (skipped; or a pinned re-run instead of R); hold credit off; the kept-hold
skip; the count read from `seated` (A-1's bug); the walk inserting at 1 (A-8's bug); the 6-day branch; Calves at 30
(`< 45` vs `< 60`; the focus exempt, B-2's bug); the reference taken from the floor-off world (F2's bug); the readers
without the allowance; the switch argument ignored.

**Docs:** nested `plan_engine/CLAUDE.md`; `plan-engine-detail.md`; SoT entries `session_duration_minutes`,
`balanced_week`; `lib/features/profile/CLAUDE.md:47`; `naming_conventions.md` (allowance, minimum seat, protective
target, `refEvicted`); a diagnose doc for F2 / F3; the closure ledger; OI-475 / 477 / 501 updates; OI-509 (the switch
now also covers S3 / S4).

## 6. Review log

**Round 1 (2026-11-14, two context-blind Sonnet seats on v1; briefs `step2cb/review_r1_{A,B}.md`).** Seat B recomputed
every number in §1 and §4.1-§4.4 from the dumps and all reproduce; the findings are design gaps and unstated costs.
- **Seat A, code.**
  - P1 A-1: the minimum pass's count guard read `seated[d]`, which only pass A increments (HEAD 641, 685); A2 and the
    floor seats were not counted, so a seat could pass the row cap or the count max. Fixed: it counts admitted rows
    (verified on HEAD: `seated` is written at 540 / 641 / 685 only). The floor's "no count-target guard is needed"
    comment (HEAD 808) stays true: the floor acts below 3 rows only.
  - P1 A-2: no terminal guard; the v1 fallback ran under 60 only and re-ran a pinned allocation that need not reproduce
    R's credits. Fixed: the fallback IS R, verbatim, at every length (S3 step 5).
  - P2 A-3: the prototype is inert with 2B off and on the 2A-off path. Fixed by scope: 2C-b runs on the lead-first path
    with the floor ON; 2A off and 2B off keep their contracts ("the pre-unit allocation byte for byte") (S3, "Where it
    runs").
  - P2 A-4: d45 covered only the cross-variant target; a focus plan still seated Calves at 30 (Glutes / Quads rows
    traded for Calves; seat B, B-2). Fixed: Calves at 30 is never a target of any kind. Minutes outside 30 / 45 / 60 / 90
    (`resolveMinutes` accepts 15-180) stated.
  - P2 A-5: the pinned fallback changed `rowsSeen` / `slotsSeen` and `_pinTo` matched duplicate names by first
    occurrence. Fixed with A-2 (no pinned re-run; `_pinTo` removed).
  - P2 A-6: the oracle must excuse `minimumSeats` within the forcing bound at 60+; five tests compute their own time
    limit; the red list was hand-picked. Fixed (§5).
  - P2 A-7: no `balancedWeek:` argument on `allocate`; Q3 already answered by the prototype's default. Fixed: the
    argument (like `leadFirst:` / `dayFloor:`); Q3 measured both ways (§4.5).
  - P2 A-8: the walk could put a target ahead of the 2A opener; `moved` did not advance for a target already in place.
    Fixed: targets go after rank 0 and the opener; `moved` counts every target in the segment.
  - P2 A-9: the minimum pass skipped a group by `ledger.week(g)` only, so a group credited by a hold kept in that run
    still got a seat. Fixed: kept-hold groups are skipped too.
  - P2 A-10 (= B-1): Q1's framing. Fixed (§7 Q1).
  - P3 A-11 / A-12: F2's count is weeks 1-3 (3,198 with week 4); the order and argument carry-through stated (S3).
- **Seat B, measurements.**
  - P1 B-1: Q1 mis-described b4 (it swaps rows in 120 day-weeks and has 12 day-weeks with FEWER rows than today) and
    left out b6's own costs. Fixed: §7 Q1 is a side-by-side table.
  - P1 B-2: the 30-minute `glutes_legs` plan became a Calves plan (d38 over d45, unstated). Fixed with A-4; §4.4
    re-measured.
  - P2 B-3: with the audit's over-time check (+5 moderate), 448 plans flag and suitable is 692; 1,489 day-weeks
    display +6. Measured: allowance size against the display (§4.6); decided there.
  - P2 B-4: §4 was the "Q3 true" world. Fixed (§4.5).
  - P2 B-5: at 60 / 90 only one plan per length changes. Stated; the gate gets a 60+ fixture that exercises S3.
  - P2 B-6: 8 `lead_starved` regressions: the first row is a timed hold (Doorway Isometric Row, `timed`), not the
    budgeted lead, so R2 is not broken; the audit reads the first row. Stated as a cost.
  - P2 B-7: unstated costs (group falls per goal and length, 53 plans lose Calves in all of weeks 1-3, lead names
    change, 45-minute days whose lead goes 4 -> 3). The last is the weekly top: earlier days grow first and use the
    group's weekly room (traced, `build_muscle|4|beginner|bodyweight|45|1`: Chest week total unchanged at 10). Fixed:
    §4.1 costs.
  - P3 B-8: F3's phase-1 cause is a state inside the fixpoint, not in the final dump; the firing counts come from a
    counter run (`audit_b8.log`). Stated. B-9: wording. B-10: unmeasured paths (answered by A-3's scope) and Q4's
    baseline (§4.1).

**Round 2 (2026-11-14, two fresh Sonnet seats on v2; briefs `step2cb/review_r2_{A,B}.md`).** Seat A: 0 P0 / P1, 8
P2 / P3. Seat B: 3 P1 (claims and framing, no broken mechanism), 5 P2, 5 P3; every v2 number reproduces.
- A-1 / B-2 (P2 / P1): the readers passed the allowance whatever 2A / 2B / the fallback did, so "byte for byte" held
  at allocator level only. Fixed: the readers gate on all three flags (superseded by round 3 R3-3's signal); a fallback plan's week-2 gain within the
  allowance is stated and accepted (no per-plan signal without a third waived `plan_generator.dart` line); a
  `generateV4`-level test.
- A-2 / B-5 / B-6 (P2): Q2 framed on the over-time-excluded count; 285 s not offered; only the maximum display shown.
  Fixed: Q2 shows main and the over-time-included count, offers 240 / 285 / 300, and §4.6 shows the display
  distribution and the corrected size bounds (270 does not fix the 28; the fix itself shows +6).
- A-3 (P2): no policy for existing allocator tests. Fixed (§5).
- A-4 (P2): prototype default `allowance = true` vs the build's false. Fixed: a byte-equal replay of the chosen
  prototype run in the build; a mutant.
- A-5 (P2): the 6-day protective set is R only in the prototype. Fixed in the text.
- A-6 (P3): `refEvicted` applied at 60+ can move a plan with no target. Fixed: under 60 only (measured, §4.1); a gate
  assertion that at 60+ a plan with no target equals R.
- A-7 (P3): the oracle's allowance as a parameter, default 0. Fixed. A-8 (P3): loose ends listed.
- B-1 (P1): Q1's "70 vs 71" mixed Calves (d45) with the d35 groups (Biceps / Triceps: pin 5, design 22) and hid the
  lead-versus-d35 trade. Fixed: split rows; the trade is put to the founder (Q1).
- B-3 (P1): the ab_swing mechanism was false (the allowance grows weeks 1 / 3, not a minimum seat). Fixed (§4.1).
- B-4 (P2): the pin was on the v1 base. Fixed: re-run on v2 (and at 240 s) for Q1.
- B-7 / B-8 (P2): "a minute above the ledger" is inferred; §4.5 is mixed. Fixed in the text; the build measures the gap.
- B-9 to B-13 (P3): stale totals, denominators, over_top (the ledger's top counts budgeted sets; kept holds add above
  it), the 60 / 90 plan's week 4, the generation-time wording, v2 counters. Fixed.

**Round 3 (2026-11-14, one fresh Sonnet seat on v3, code and measurements; brief `step2cb/review_r3.md`).** 0 P0, 1
P1, 4 P2, 5 P3; every recomputed cell of the §7 table reproduces.
- R3-1 (P1): §0 said OI-501 was fixed; at 45+ only Calves at 0 is fixed, and Calves / Core below the no-focus twin
  rise. Fixed: §0 says NOT fixed, with the numbers; OI-501 stays open.
- R3-2 (P2): d45 against d38 for a focus at 30 minutes was decided in the design, not by the founder. Fixed: §7 Q3.
- R3-3 (P2): a per-plan signal reaches the readers without touching `plan_generator.dart`. Fixed: `PopulatedDay.allowance`
  (S4), replacing round 2's three-flag gate; measured (b23): the 2 fallback plans' week 2 is today's again.
- R3-4 (P2): the swap at 240 s is dominated by the pin at 240 s; the pin at 285 s was unmeasured. Fixed: §7 says so;
  the pin at 285 s measured (b24): it leaves the 28.
- R3-8 (P2): only `glutes_legs` was measured. Fixed: the five-focus grid (§4.8); injured, repeat-pin and resolved-focus
  plans named as unmeasured (§3).
- R3-5 / R3-6 / R3-7 / R3-9 / R3-10 (P3): B's focus target in step 2; the 60+ "no target equals R" gate bullet;
  protect-first rescued 0 of 2 on the grid (kept on its fixture); the 60 / 90 plan's week-2 Biceps; the builder's
  specifics (signal, ledger-seconds field, the gate's major-issue source, `minimumSeats` shape, `allowance` default).
  Fixed in S3, §0, §1 F3 and §5.

**Round 4 (2026-11-14, one fresh Sonnet seat on v4, confirming; brief `step2cb/review_r4.md`).** 0 P0, 1 P1, 2 P2,
4 P3; every recomputed number reproduces (b23 / b25 against b18 / b17: exactly the 2 fallback plans; every §7 cell;
every §4.8 cell). Converged on the design; the findings are the titration path and text.
- R4-1 (P1): the signal cannot reach `VolumeTitration` (it titrates `WeekPlan`s, `plan_generator.dart:332`). Verified;
  fixed: titration keeps `allowance: false` (S4), conservative, and unmeasured either way since titration is opt-in
  and the audits ran it off.
- R4-2 (P2): §5 still tested round 2's three-flag gate. Fixed: per-path fixtures for the field and mutants.
- R4-3 (P2): question numbers. Fixed: §7 lists Q1 x Q2, Q3, Q4 and the body cites them so.
- R4-4 to R4-7 (P3): no `copyWith` on `PopulatedDay` and an empty-list guard; 574 not 576 with the signal; main's 886
  next to option (a); the 45-minute Biceps residue; the prototype's probe true with the floor off (the build follows
  the spec; the replay compares the field). Fixed.

## 7. Open questions

**Decided by the founder (2026-11-14), after the rounds:**
- **d47 (Q1 x Q2):** option (a), the swap design with `SessionBudget.allowanceSeconds = 285`; the audit's over-time
  check moves to the displayed +6 bound (`plan_audit_lib_test` changes with it).
- **d48 (Q4):** keep 2A's lead protected (the walk's opener rule stays; 17 Biceps / Triceps zero-week pairs accepted).
- **d49 (Q3):** d45 wins for a focus too: at 30 minutes the minimum never targets Calves, `glutes_legs` included.

The questions as put to the founder are kept below for the record.

**For the founder, after the rounds.** Q1 (how much a short day may change, d44) and Q2 (the allowance size, d42) are
coupled (round 2 B-5): the swaps fix today's 28 not_suitable plans only with an allowance of 285 s or more. One table,
all on the v2 base, weeks 1-3, against merged main (the pin: the minimum at today's budget first, then the allowance
re-run restricted to those rows):

| | Main | Pin, 240 s (b20) | Pin, 300 s (b19) | Swap, 240 s (b11) | Swap, 285 s (b17) | **Swap, 300 s (b10)** |
|---|---|---|---|---|---|---|
| Suitable: over-time excluded / the audit's +5 check included | 886 / 886 | 927 / 927 | 948 / 696 | 923 / 923 | 967 / 777; **965 / 775 with the signal (b25)** | 971 / 694; **969 / 692 with the signal (b23)** |
| Today's 28 not_suitable plans | 28 | stay | stay | stay | fixed | fixed |
| Plans regressed / improved (over-time excluded) | | 20 / 61 | 21 / 83 | 22 / 59 | 23 / 104; 23 / 102 (b25) | 23 / 108; 23 / 106 (b23) |
| Day-weeks displaying +6 (30 / 45 min) | 0 / 0 | 0 / 0 | 702 / 805 | 0 / 0 | 467 / 394 | 701 / 789 |
| Day-weeks whose exercise set changes (30 / 45 min); plans | | 80 / 7; 50 | 80 / 7; 50 | 709 / 123; 258 | 914 / 123; 279 | 914 / 123; 279 |
| Day-weeks with fewer rows than today | | 12 | 12 | 0 | 0 | 0 |
| Day-weeks whose first row changes / today's first row dropped | | 0 / 0 | 0 / 0 | 63 / 0 | 63 / 0 | 63 / 0 |
| (plan, group) zero-week pairs: Biceps + Triceps (d35) / Core / Calves (d45 at 30) | 35 / 42 / 57 | 20 / 8 / 57 | 20 / 8 / 57 | 22 / 0 / 49 | 22 / 0 / 49 | 22 / 0 / 49 |
| Plans with no Calves in weeks 1-3 that train them today | | 0 | 0 | 51 | 53 | 53 |
| (plan-week, group) pairs whose sets fall | | 234 | 222 | 596 | 654 | 649 |
| Days whose first row equals today's with fewer sets | | 66 | 48 | 66 | 42 | 48 |

The swap columns are v2 / v3 without the allowance signal; the signal (S4, the design as built) moves only the 2
fallback plans (B-7 persona, back to today's week 2 and verdict): measured at 285 s (b25) and 300 s (b23), every
other cell of those columns is unchanged (b25 vs b17: those 2 verdicts only).

Reading it:
- **The pin is not "today's exercises exactly"** (80 / 7 day-weeks still swap, from the minimum before the pin) and it
  breaks the "a 30-minute day shows 4" rule on 12 day-weeks (a 30-minute day showing 3, a 45-minute day showing 4),
  which the swap design never does. On the d35 groups it is slightly better (Biceps + Triceps 20 vs 22), on Core worse
  (8 pairs at 0 vs 0). d44 reads "adds sets, never an exercise": the swap changes the exercise set in 914 + 123
  day-weeks (279 plans), the pin in 80 + 7 (50).
- **At 240 s the pin is the better pairing** (round 3 R3-4): against the swap at 240 s it has more suitable (927 vs
  923), fewer regressions (20 vs 22), 50 plans touched vs 258, 234 falls vs 596, no plan losing Calves (0 vs 51); the
  swap wins only on Core (0 vs 8) and the 12 fewer-row day-weeks. The swap earns its churn only with 285 s or more.
- **The pin at 285 s** (b24, measured for R3-4): 944 suitable over-time excluded, 791 included; today's 28
  not_suitable plans STAY; 21 regressed / 79 improved; 420 / 422 day-weeks display +6 (30 / 45); 305 plans with an
  over-time issue; 80 / 7 day-weeks change exercises (50 plans), 12 hold a row fewer; Biceps + Triceps zero-week
  pairs 20, Core 8, no plan losing Calves; falls 224. So the 28 are fixed by the swap alone, never by more time on
  the pin, and the pin at 285 s is dominated by the pin at 240 s on the audit's own measure (791 vs 927).
- **The 28 plans** need the swap design AND 285 s or more, and their fixed days display +6.
- **With the audit's own +5 over-time check,** every 285-300 s column is below main (777 / 694 / 696 vs 886); every
  240 s column is above it (923-927). Excluding over-time, 300 s is best (971).
- **2A's lead vs d35 (round 2 B-1):** protecting the lead (d26-d29) costs 17 Biceps / Triceps zero-week pairs (§4.7);
  without it today's first row is dropped in 13 day-weeks. The design keeps the lead. The founder may reverse it.

The questions:
1. **Q1 x Q2, one choice of three** (they are coupled):
   - (a) **swap + 285 s** (b25: 965 suitable, 775 with the +5 check against main's 886, 0 not_suitable): fixes today's 28 not_suitable plans; 861 day-weeks display +6; 279 plans' exercise sets
     change; 53 plans lose Calves at 30 (d45);
   - (b) **pin + 240 s**: every day displays +5 or less and beats main on the audit's own measure (927 vs 886); the 28
     stay; 12 day-weeks hold one row fewer than today; 50 plans change exercises;
   - (c) **swap + 300 s** (d42's literal 5 minutes): best without the over-time check (971); 1,490 day-weeks display +6.
   Recommended: (a). Whatever is chosen, the audit's over-time check moves to the chosen display bound, so
   `plan_audit_lib_test` changes.
2. **Q4, the lead vs d35** (round 2 B-1): keep 2A's lead protected (17 Biceps / Triceps zero-week pairs) or let d35 take
   it (13 day-weeks drop today's first row). Recommended: keep the lead.
3. **Q3, Calves for a focus at 30 minutes** (round 3 R3-2): d45 says the minimum skips Calves at 30; d38 says a focus
   group gets at least 2 sets. v3 lets d45 win for a focus too (a `glutes_legs` plan at 30 minutes has Calves at 0 in
   91 % of plan-weeks, 79 % today; v1 let d38 win and traded Glutes / Quads rows for Calves, §4.4). Recommended: d45
   wins (the 30-minute focus plan keeps its Glutes / Quads work).
4. **Costs to report** with the results: §4.1's falls by goal (biggest: lose_fat 30 min, strength 30 min), Calves at
   30 (d45), the `glutes_legs` Core and Hamstrings cells (§4.4, OI-501), the regressions, the chip wording ("About N
   min").

**Answered in v2:** the reference on each path (§0, "Where it runs": 2C-b runs on the lead-first, floor-ON path only);
`AllocationStats` readers (`debugLastStats` has no production reader; the tests that read `rowsSeen` keep it because the
fallback is R itself); `_weekTwoGains` and titration (§4.5); generation time (§4.1: no measurable change).
