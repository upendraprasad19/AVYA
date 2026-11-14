# Generator step 2, Unit 2C: a balanced week (weekly minimums and the quad floor)

Status: v6, 2026-11-14 (after review rounds 1-4 and a build-time change to the repeat-pin check, founder decisions d34-d46, prototypes up to v11b / va2fb). Written on 2B's
merged tree (main c6b1ee48).

- Tier L (plan engine; two waived lines in `plan_generator.dart`). Blast radius platform.
- Step 2 plan: `docs/plans/2026-11-12-generator-step2-allocator.md` §11. Board: t212-t215.
- **Split (§4.12.1, after round 2):** both review rounds found material issues, almost all in the weekly minimum and the
  allowance. The unit ships as two PRs, in order:
  - **2C-a**: S1 (the balanced splits at 60+) and S2 (the credit rule). Measured alone on a consistent audit (§4A):
    0 verdict regressions, 98 improved.
  - **2C-b**: S3 (the weekly minimum) and S4 (the 5-minute allowance under 60), on 2C-a's merged tree.
  - One kill switch for both (d37): 2C-a adds `disable_balanced_week`, 2C-b's paths read the same switch.
- **Execution mode (§4.12.7):** inline. Each part has its own worktree, branch and plan-review record (`generator-step2c`
  for 2C-a; `generator-step2c-b` for 2C-b).

## 0. Scope

| Input | What it says | 2C answer |
|---|---|---|
| d14 | Zero-set weeks for small groups | 2C-b S3, the weekly minimum |
| OI-475 L2 | The credit rule: a squat stops counting toward Glutes | 2C-a S2, build_muscle 3/4/5-day at 60+ min |
| OI-475 L3 | A quad hit on another day | 2C-a S1, balanced splits at 60+ min (d40 / d41) |
| OI-477 | 6-day personas short of the Quads floor | not changed (the 6-day split and its credit stay); measured |
| OI-501 | `glutes_legs` lowers Calves and Core | 2C-b S3's focus rule (d38) |
| d20 | low-volume and swing flags | measured (§4) |
| 2B finding | lead + 2 day-weeks | measured (§4B.3) |

**Not in scope:**
- other goals' splits;
- the 6-day build_muscle split;
- 30 / 45-minute build_muscle splits (d40). They get S3 and S4 only.
- supersets that count their saved rest (§7.2, a separate unit if the founder wants it);
- repeat-phase minutes (2D);
- the selector's picking rules (beyond the same-type avoid, S1).

**Who changes:**
- 2C-a: every build_muscle 3/4/5-day plan at 60 and 90 minutes, every level and phase (round 3, A-4 / B-3):
  - S2 (the credit) reaches all of them, a beginner's phase 1-2 Full Body plans included (measured: 3-day beginner Quads
    9 -> 10, 4-day 10 -> 12; Goblet Squat / Romanian Deadlift 3 -> 4 sets; same exercise names);
  - S1 (the split) reaches 3-day and 4-day beginners only from the phase in which `effectiveLevel` lifts them (phase 3
    in the audit grid; before it they are on Full Body, `selectV4`'s `isBeginner && days <= 4` branch), and 5-day
    beginners in every phase (they already use the 5-day body-part split).
- 2C-b: every goal and length (S3), and every goal at 30 / 45 minutes (S4).

## 1. What happens today (main c6b1ee48, the 2,304-plan audit)

**Bug history (§4.1.5):**
- OI-454 (`b8f4c2`);
- 1B-Q (`cf970c`, the B leg-day quad slot);
- OI-501 (t108);
- memory `project_oi475_leg_day_findings` ("one leg day cannot reach the floor").

Not a recurrence: this is the L2 / L3 half step 1 left to step 2.

**Cause.** build_muscle 3/4/5-day train the legs on one day a week. One session's cap (6 / 8 / 10) is under the Quads
floor (10 / 12 / 14), and a squat also spends the Glutes cap and top. Quads under the band bottom (build_muscle,
week-cells, weeks 1-3):

| Minutes | Cells under the bottom |
|---|---|
| 30 | 432 / 432 |
| 45 | 404 / 432 |
| 60 | 384 / 432 |
| 90 | 336 / 432 |

Probes, each a scratch edit restored with a sha check (session scratchpad `step2c/`):
- raising the cap alone: no change;
- the credit rule alone: 336 -> 308 at 90 min;
- a balanced split without the credit rule: Glutes fills its top and stops Quads at ~8.

Both are needed.

**Zero weeks** (a group with sets in some of weeks 1-3 and 0 in another, the run's credit): 92 plans today (Calves 57,
Core 42, Triceps 19, Biceps 16; a plan can count in more than one group). Almost all are 30 minutes, alternating by
variant. Under `glutes_legs`, Calves fall to 0 in 652 plan-weeks against the no-focus twin.

**Session length** (founder walkthrough, 2026-11-14):
- It is a profile-only setting. Onboarding asks nothing and the default is 60 (F2). Edit Profile offers 30 / 45 / 60 /
  90, and a change offers to reschedule.
- A one-off short day is the coach's Shorten today (`SwapService.shortenDay`): it drops lower-priority exercises from
  that day only. The plan and the split never change.

## 2A. Part 2C-a: the splits and the credit rule

### S1. Balanced build_muscle splits at 60+ minutes (`split_resolver.dart`; d35, d39, d40, d41, d43)

`SplitResolver.selectV4` gains `int? sessionMinutes`. The waived line 169 passes
`SessionBudget.resolveMinutes(param: sessionDuration, profileValue: TrainingHistoryAnalyzer.sessionMinutesFromProfile())`,
the same expression the budget uses at line 278, so the split and the budget always agree. One shared predicate,
`SplitResolver.balancedWeekApplies(planGoal, daysPerWeek, minutes)`, decides S1, S2 and the repeat-pin families (round 3, A-9):
build_muscle, days in {3, 4, 5}, `minutes != null && minutes >= 60`, switch ON. The lists are chosen on the predicate,
not inside `selectV4`'s `switch (daysPerWeek)` (whose `default:` serves days 1, 2 and 7 the 4-day list); days 2 and 7
are tested (round 4, A-5). A null `sessionMinutes` means today's
lists (round 3, A-7): the only production caller always passes an int, and the direct test sweeps keep covering the
30 / 45 lists. When it holds, the 3, 4 and 5-day lists are:

| Days | Split | Notes |
|---|---|---|
| 3 | Upper / Lower / Full Body | Core 4th on Full Body, 3rd on Lower (d41); Full Body avoids the earlier days' picks (d46) |
| 4 | Upper A / Lower A / Upper B / Lower B | arms within the first five on each Upper day |
| 5 | Push / Pull / Legs / Upper / Lower + Core | the default 5-day; build_muscle's Upper day is led by Mid Chest (copied day, focus 'Chest, back, shoulders, arms') |

Otherwise:
- 30 / 45-minute plans keep today's lists, verbatim;
- strength keeps its 3-day list verbatim (the shared 'build_muscle / strength' list is not edited; build_muscle gets
  its own branch);
- no leg exercise is added to a Push day (d39).

**Every new day carries a `slotsB`** (round 1, A-1). Without one the selector copies A, and weeks 2 / 4 repeated weeks
1 / 3:
- the 4-day and 3-day lists use designed B lists that rotate emphasis (round 3, A-6: the 3-day B lists differ from A);
- the 5-day days use B lists that equal A, and B soft-avoids A's names.

**A second day of the same type avoids the first's picks** (round 1 A-2; round 2 A-1):
- New `MuscleSlotDay.avoidEarlier` (an enum `EarlierDayAvoid { none, sameType, all }`, default none): `sameType` (the
  same `dayType`, round 4 A-5: 4-day Lower B avoids Lower A; the 5-day Lower + Core, `dayType 'legs'`, avoids the Legs
  day) on Upper B, Lower B and the 5-day Lower + Core; `all` on the 3-day Full Body day (d46: it avoids the Upper and Lower
  days' picks; measured 3-day week-1 repeats 334 -> 0, 98 plans improved vs 91 with repeats).
- `_pickCoreList` adds those earlier days' names, per variant, to the day's soft-avoid set (same-movement partners
  expanded, `_preferNovel` only, never `excludeNames`).
- **`VolumeFilter.filterDays` carries the field** (round 2, A-1). It rebuilds every `MuscleSlotDay` and dropped it, so
  the v2 prototype's avoid never reached the picker (4-day repeats 86 -> 464). With the carry: 86 -> 48 (§4A.2).
- `ExerciseSelector.buildPinnedDays` reads the same filtered frames; a repeat phase pins names and does not consult the
  avoid, and its fresh fill (`pickV4` with `slotDays: [frame]`) has no earlier days to avoid (round 3, A-11; stated,
  pinned).
- OI-458's push / pull feeders are unchanged; a day without the flag is unchanged.

**The exact slot lists** are in the prototype (`apply_splitA6.py`, the scratchpad); the build copies them and pins each
in tests.

**1B-Q:** `disable_variant_b_quad` keeps its meaning for every list it still governs (3-day at 30 / 45, 4 / 5-day at
30 / 45). The 3, 4 and 5-day 60+ lists have no B leg list to restore, and `quadLegsB` does not reach them.

**Repeat-phase pins after a minutes change** (round 2, A-7; round 3, A-1 / B-1; round 4, A-2; build v6). `buildPinnedDays`
maps the previous phase's names by day index, and its map carries no day names (changing it touches `generateV4`, rule
14). The G5 gate (`repeatPinsFrom`, `workout_schedule_read_service.dart:839`) refuses pins when `last_phase_profile`
(goal, equipment, days, effective level) differs, but that profile is stale after Edit Profile's reschedule
(`generateAndScheduleFromDate` rewrites rows from today and never the profile). v5's design (a `balanced_week` marker
re-stamped on reschedule) was dropped at build time: a mid-phase reschedule rewrites only the rows from today, so weeks
1-2 (the rows pins come from) can still hold the old split while a re-stamped profile names the new one. The check now
reads the rows themselves:
- `repeatPinsFrom` gains `Set<String> foreignDayNames = const {}` and refuses the pins when a workout row of weeks 1-2
  is named for one of them. `foreignDayNamesFor` (pure, in the same service) is the day names of the OTHER split
  family that the new phase does not use: for build_muscle 3 / 4 / 5 days, today's lists vs the balanced lists
  (`selectV4` with `balancedWeek` true / false); empty for every other plan, so nothing else changes. The families'
  names are disjoint per day count (3-day Push + Core / Pull + Core / Legs vs Upper / Lower / Full Body; 4-day Push /
  Pull / Legs / Upper vs Upper A / Lower A / Upper B / Lower B; 5-day body-part days vs Push / Pull / Legs / Upper /
  Lower + Core; a beginner's Full Body A-D are the same in both, so empty). A renamed row (a log title from
  `completed_title_healer`, a template) matches neither family and is ignored, as today.
- The minutes are resolved as `generateV4` resolves them: `_buildRepeatPins` and `buildRepeatPinsForAdvance` gain an
  optional `int? sessionDuration`; the auto path (`autoGenerateNextPhaseIfNeeded`) passes its own; the graduation path
  (`pro_phase_advance.dart:858`) passes nothing, as its generate does, so both read the profile.
- **OFF:** `foreignDayNames` is then the balanced names. Rows written while ON refuse the pins (correct, the frames
  differ); a user who was never ON has no such rows, so OFF behaves as main. Nothing new is written to Hive.
- **The days case (a pre-existing bug, fixed here with its own diagnose doc):** 4 -> 5 days rescheduled, then 5 -> 4
  with the reschedule declined: the stale stored 4 matches, and the 5-day rows' first four days were pinned into the
  4-day frames. `repeatPinsFrom` now also refuses when a workout row's `workout_day_index` is past the new plan's days.
  The opposite direction (fewer rows than frames) already fails G5 (stored days differ) or leaves gap days that
  `buildPinnedDays` fresh-fills.
Files: `workout_schedule_read_service.dart` only (`pro_phase_advance.dart` unchanged). Tests: rows of the other family
refuse; a renamed row is ignored; 60 -> 60 pins; OFF with ON-written rows refuses; OFF with today's rows equals main;
the day-index refusal; `foreignDayNamesFor` per days and goal (empty for 6-day, other goals and beginner Full Body).
Only testers exist today.

### S2. The credit rule (d35, d36, d43; line 288)

Line 288 becomes:

```dart
quadPrimaryCreditsGlutes: SplitResolver.quadPrimaryCreditsGlutes(planGoal, daysPerWeek,
    SessionBudget.resolveMinutes(param: sessionDuration, profileValue: TrainingHistoryAnalyzer.sessionMinutesFromProfile()),
    quadLegsB: quadLegsB),
```

(One logical argument; the constructor call may gain physical lines, nothing else in the file changes.) The minutes
expression is the one line 169 and line 278 use. `generateV4` is synchronous, so the three profile reads in one
generation return the same value (round 2, A-5; `session_minutes_resolution_test.dart` counts calls only).

One function holds the decision:
- false when `balancedWeekApplies` holds;
- for 6-day, exactly today's `!(quadLegsB && hasQuadLegsBSplit)` (round 1, A-4): `disable_quad_legs_b` still restores
  the slot and the credit together;
- for everything else, today's expression.

**Production readers** (unchanged, they read `ctx.quadPrimaryCreditsGlutes`):
- `session_set_allocator.dart:402`;
- `periodization_engine.dart:188`;
- `volume_titration.dart:190`.

**Test oracles that restate the rule.** Round 1 (A-5) had them call the new function. Build-time change (v6): each
oracle RESTATES the rule in its own words (build_muscle, days 3-5 at 60+ resolved minutes, or 6 days), because an oracle
that calls the production predicate cannot catch a wrong predicate (OI-454's lesson). Only the audit dump, a
measurement tool that must score both sides of a comparison by the generator's own rule, calls it:
- `plan_audit_dump_test.dart:108-109` (calls `quadPrimaryCreditsGlutes`, by design);
- `session_set_budget_gate_test.dart:126, 270-274, 378, 524` (`_credited`);
- `day_floor_gate_lib.dart:111, 149` (`quadOwnsGlutes`; it gains the block's minutes: `pairs_*` run at 60, `rep30` at 30;
  round 3, A-10);
- `oi489_timed_hold_real_engine_test.dart:35`;
- `session_set_budget_wiring_test.dart:123-133` (explicit parameter, checked; the effective-level test passes a literal
  `false` for its 3-day 90-minute plan).

### S5. One kill switch (d37)

`disable_balanced_week` (`PlanEngineFlags.balancedWeekEnabled`, default ON). **Each callee reads it** (round 2, A-5), as
2A and 2B do, so `plan_generator.dart` changes on lines 169 and 288 only:
- `SplitResolver.selectV4` (S1) and `SplitResolver.quadPrimaryCreditsGlutes` (S2) in 2C-a;
- `SessionSetAllocator.allocate` (S3) and `BudgetLedger` (S4) in 2C-b.

Each takes an optional override argument for tests. `generateV4` has no `await`, so the reads in one generation cannot
disagree. Tests that need OFF through `generateV4` (goldens, the other kill-switch tests and their OFF worlds, e.g.
`day_floor_kill_switch_test` and the `digest|` checks) set `configBox['disable_balanced_week']`, as the other switches
do (round 3, A-3). OFF equals main byte for byte over the 1,010 golden personas (fixture
`generator_golden_hashes_balanced_week_off.json`, recorded on c6b1ee48 in 2C-a and re-checked in 2C-b). The switch and
the old lists' dead branches are deleted after the phone check (an OI minted at 2C-a's merge, updated by 2C-b).

## 2B. Part 2C-b: the weekly minimum and the allowance

### S4. One 5-minute allowance for 30 / 45-minute plans (d42, d44)

**The budget.** `BudgetLedger(ctx, n, {bool allowance = false})`: a plan under 60 minutes gains 300 s of day budget when
`allowance` is true and the switch is ON. The three production builders (`session_set_allocator.dart:420`,
`periodization_engine.dart:168`, `volume_titration.dart:181`) pass it; the default keeps every direct-ledger test
(`session_budget_test.dart:320`, `session_set_allocator_behavioral_test.dart:370, 399`, `day_floor_behavioral_test.dart:55,
216`, `session_set_budget_consumers_test.dart:329`) on today's budget (round 3, A-12). Pass A2's forcing bound and S3's become `ledger.forcingBound`: 0 when the
allowance is on, else today's 300 s. The two never stack (v5 stacked to +10 min).

**Worlds are chosen without it** (round 2, A-4). With the allowance in the world choice, the main world seated more rows
and beat the lead world, so 15-20 % of 30-minute days lost the lead's third set (strength leads at 3 sets: 88 % -> 67 %).
Like 2B's floor (F3):
- every world-choice `_variant` call runs with `allowance: false`, so the choice equals today's;
- the chosen worlds are re-run with `allowance: true` (A first, then B copying the new A), on every path (lead-first,
  the `kept == null` fallback, 2B OFF, the 6-day path, the 2A-off `allocate`).

Measured (v11b): the lead has fewer sets than today on 0-0.6 % of 30 / 45-minute days with the same lead.

**The extra time buys sets, not exercises (d44).** In the allowance re-run a day may hold at most the rows the chosen
allowance-off world held that day (budgeted and not), within the level's count max. A 30-minute day still shows 4
(founder D-A stands). The founder chose this over a 5th exercise, with the measured comparison (§4B.1).

**Readers outside the allocator** (round 2, A-6, B-3):
- `budgetedDaySeconds` (`session_estimate.dart:31`, Train, Home) sums the stored rows, so a "30" day shows about 35;
  d42 accepted it.
- `SwapService._estimateSeconds` (`shortenDay`) takes a caller target and is unaffected.
- `WarmupCooldownSelector` and `warmCoolMinutes` read `ctx.minutes`, not the ledger: unchanged.
- `PeriodizationEngine` (`_weekTwoGains`) and `VolumeTitration` build their own `BudgetLedger` over the same ctx and
  pass `allowance: true`.
- The Edit Profile chip reads `'Up to $min min'` (`edit_profile_screen.dart:1146`), with its comment at `:1939`,
  `lib/features/profile/CLAUDE.md:47` and `session_duration_chip_wording_test.dart`. "Up to 30" becomes false. The build
  changes the chip to `'About $min min'` and updates the comment, the nested CLAUDE.md line and the chip test (d42 keeps
  the numbers; this keeps the words true). The founder is told at the end of 2C-b.
- `session_set_budget_wiring_test.dart`'s tolerance moves with the allowance.

### S3. The weekly minimum (d35, d38, d45)

**Targets** (per variant):
1. A group with weekly sets > 0 in the other variant and 0 here (d35).
2. A focus group at 0 here (d38).
3. A group the chosen allowance-off world trained in this variant and the allowance re-run left at 0 (round 2, B-1: the
   minimum and the allowance never take a group today trains to 0).
4. **Calves at 30 minutes is never a target** (d45): at 30 minutes calves may alternate 2 / 0.

**Hold credit** (round 1, A-8). The ledger's weekly sets count budgeted rows only, so a group credited only by a kept
timed hold reads 0 (v11b debug: Core in `build_muscle|3|beginner|basic_gym|30|3`). The target test counts the groups of
kept library holds as trained, in both "the other variant trains it" and "already has sets here". A test pins it.

**The pass** seats, for each target still at 0, its cheapest remaining slot at 2 sets, under these guards:
- not admitted, not `reserveBlocked`;
- the day's count: `seated[d] < target[d]` (round 2, B-3; the `_Why.target` flag alone missed clock-removed slots);
- never past a session cap;
- never past another group's weekly top;
- within `ledger.forcingBound`.

Ties go to the day with the most seconds left. Seats are recorded in `AllocationStats.minimumSeats`, never in
`countForced`.

**Order: a separate walk, not a reorder** (round 2, A-2, A-3, B-2). In a re-run with targets, pass A walks `walk[d]`, a
copy of `byDay[d]` in which each target group's cheapest slot follows the day's rank-0 slot and earlier moved targets.
`byDay`, `_Slot.rank`, B's copied days, `entries`, passes B / C / D, the 2B floor ties, `firstLifts` and `leadSeats` all
keep the selector order. `evictFor` receives the slot's own `rank`, not the walk index. The rank-0 slot is never moved,
and `opener` is computed before the walk, so R1 is unchanged.

**Re-runs to a fixpoint** (round 2, B-1). After the 2B re-run (now also the allowance re-run): targets for A, re-run A;
targets for B against the new A, re-run B copying it; then any group that was trained before and is at 0 now joins the
targets, at most 4 rounds. Every path:
- lead-first, including the `kept == null` fallback;
- 2B OFF (the same re-runs with `dayFloor: false`);
- **the 6-day path** (B = A; v9 measured Triceps newly at 0 in 48 plan-weeks of 6-day 30-minute plans without it):
  targets 2-4;
- the 2A-off `allocate`.

The minimum only adds seats after the worlds are chosen. `worldIsWorse` cannot turn against the chosen world.

**Residue, causes established** (v11b debug, `MINMISS` traces):
- *no free place*: a bodyweight day of timed holds whose row cap (d44) leaves one budgeted seat, held by the lead;
- *no slot*: the variant holds no exercise for the group (the selector's lists);
- *hold-only credit*: closed by the hold-credit rule above (re-measured in the build).

## 3. Founder decisions (2026-11-14; board t212)

- **The alternating 2-week split: rejected.**
- **d34:** 3-day kept Push / Pull / Legs plus a squat on Push. Replaced by **d39** (no leg exercise on a Push day) and
  **d41** (3-day becomes Upper / Lower / Full Body at 60+, with Core moved earlier).
- **d35:**
  - balanced 4-day (Upper / Lower x2) and 5-day (Push / Pull / Legs / Upper / Lower, chest press on Upper) splits;
  - the credit rule for build_muscle;
  - a weekly minimum of 2 sets;
  - a focus never lowers its own group (narrowed by d38).
- **d36:** a rule-14 waiver for `plan_generator.dart` line 288.
- **d37:** one kill switch for all of 2C (both parts read it).
- **d38:** a focus group the plan holds an exercise for gets at least 2 sets a week.
- **d40 / d43:** the balanced splits only at 60+ minutes, with a rule-14 waiver for line 169. At 30 / 45 the split cost
  the upper body (4-day Back 9 -> 4, 13 -> 6) with no Quads gain.
- **d42:** the choices stay 30 / 45 / 60 / 90; 30 / 45 days may run 5 minutes over, as one allowance.
- **d44:** under 60 minutes the extra 5 minutes adds sets, never an exercise (D-A, "a 30-minute day shows 4", stands).
  Applied to 45 minutes too: the question said 45 works the same way; the founder can split them.
- **d45:** at 30 minutes the weekly minimum skips Calves ("in 30 mins it's okay if we skip calves").
- **d46:** the 3-day Full Body day uses different exercises from the Upper and Lower days (a soft avoid), not the same
  main lifts twice a week. Shown with one plan's week and the counts (repeats 334 -> 0; 98 improved vs 91).
- **Costs shown to the founder:** the §4A.1 table for 60 / 90, the 30-minute example week (4 vs 5 exercises), the
  30 / 45 group-level changes (§4B.2).
- **"Can we increase arm sets?":** the Upper-day arm reorder barely helps (§4A.1). Supersets are the real lever (§7.2).

## 4A. Measured, 2C-a alone (prototype `va2fb`: S1 with d46 + S2 + the filter carry + null = today's lists; 2,304 plans)

**One audit rule for both sides** (round 3, A-2). The audit's credit mirror (`plan_audit_dump_test.dart:108`) is the
judge: both today's run (`audit_base2`) and 2C-a's are scored with S2's rule (a squat credits Quads only in build_muscle
3/4/5-day at 60+). v3's §4A scored 2C-a with today's rule; its verdicts are replaced here.

### 4A.1 60 / 90 minutes, build_muscle, median weekly sets (weeks 1-3), today -> 2C-a

Every exercise's full groups counted (Glutes includes squats; the next table splits it):

| Plan | Chest | Back | Shoulders | Biceps | Triceps | Quads | Hams | Glutes | Calves | Core |
|---|---|---|---|---|---|---|---|---|---|---|
| 3-day int 60 | 7.5->6 | 8->6.5 | 10->11 | 6->3 | 4->3 | 3->9.5 | 7->9 | 8->15 | 4->3 | 7.5->6 |
| 3-day int 90 | 8->9 | 8->9 | 11->14 | 6->5 | 4.5->4 | 3->12 | 7->12.5 | 8->22 | 4->5 | 9.5->10 |
| 3-day adv 60 | 8->6 | 10->8 | 11->10.5 | 6->5 | 5->4 | 5->8 | 5->7 | 10->14 | 2->2 | 11->5 |
| 3-day adv 90 | 10->8 | 10->11 | 14->14.5 | 8->8 | 8->7 | 5->11 | 7->11 | 10->20 | 4->4 | 15->8 |
| 4-day int 60 | 7.5->6.5 | 14->9 | 15->12 | 11.5->7 | 11->6 | 5->12 | 7->10 | 8->20.5 | 3->6 | 4->7 |
| 4-day int 90 | 8->10 | 15.5->12 | 16->14 | 12->10 | 12->10 | 5->12 | 7->12 | 8->24 | 4->9 | 4->10 |
| 4-day adv 60 | 8->8 | 15->12 | 19->17 | 12->6 | 10.5->5.5 | 5->10 | 5->10 | 10->20 | 2->4.5 | 6->5 |
| 4-day adv 90 | 10->12 | 17->16 | 20->20 | 16.5->11 | 15->9.5 | 5->14 | 7->14 | 10->27 | 4->8 | 9->10.5 |
| 5-day int 60 | 11.5->10 | 12->11 | 16->16 | 16->12 | 12->10 | 5->10 | 7->6.5 | 8->21.5 | 3->6 | 9->11 |
| 5-day int 90 | 11.5->12 | 12->12.5 | 16->16 | 16->12 | 12->12 | 5->12 | 7->10 | 8->28 | 4->10 | 9->14 |
| 5-day adv 60 | 14->11 | 15->15 | 20->19 | 16->11.5 | 14.5->8 | 5->9 | 6->8 | 10->21 | 2->4 | 10.5->12.5 |
| 5-day adv 90 | 15->14 | 17.5->18 | 20->20 | 17->14.5 | 18->14 | 5->12 | 7->11.5 | 10->27.5 | 4->9 | 15->17 |

**Glutes, both ways** (median, weeks 1-3; band 12-16 intermediate, 14-20 advanced). Today, glute work from hip and
glute exercises alone (hinges, thrusts, kickbacks; the S2 count) is under the band bottom in every cell; 2C-a raises it
everywhere:

| Plan | All glute-listed sets | Hip / glute exercises only (S2's count) |
|---|---|---|
| 3-day int 60 / 90 | 8 -> 15 / 8 -> 22 | 5 -> 6 / 5 -> 10 |
| 3-day adv 60 / 90 | 10 -> 15 / 10 -> 21 | 7 -> 8 / 7 -> 12 |
| 4-day int 60 / 90 | 8 -> 20.5 / 8 -> 24 | 5 -> 9 / 5 -> 12 |
| 4-day adv 60 / 90 | 10 -> 20.5 / 10 -> 28.5 | 6.5 -> 12 / 6.5 -> 17 |
| 5-day int 60 / 90 | 8 -> 21.5 / 8 -> 28 | 5 -> 12 / 5 -> 16 |
| 5-day adv 60 / 90 | 10 -> 21 / 10 -> 29.5 | 6.5 -> 14 / 6.5 -> 18 |

### 4A.2 Totals

| Measure | Today | 2C-a |
|---|---|---|
| build_muscle Quads cells under the bottom, 60 / 90 min (weeks 1-3) | 384 / 336 | 296 / 120 |
| Verdicts, one audit rule (suitable / needs work / not suitable) | 788 / 1488 / 28 | 886 / 1390 / 28 |
| Plans regressed / improved | | 0 / 98 |
| Issue counts | | low_volume -157, ab_swing -118, unused_time -37, over_top -11, under_floor -3, unloaded -2, lead_starved +3, band_in_gym +2 |
| Max minutes over | +4 | +4 |
| Zero-week plans | 92 | 92 (unchanged; 2C-b's job) |
| Repeated names in week 1, int / adv at 60 / 90 (3 / 4 / 5-day) | 74 / 86 / 320 | 0 / 48 / 102 |
| Week 2 equal to week 1 (4 / 5-day at 60+) | 16 / 0 | 16 / 0 (beginner Full Body, as today) |

- **Unchanged:** every 30 / 45-minute plan, every other goal and every 6-day plan (byte-identical, round 3 seat B).
- **Quads residue at 90 minutes** (120): 6-day advanced 36 (OI-477, not changed), 5-day advanced 36, 3-day advanced
  36, 5-day intermediate 4, 3-day intermediate 4, 3-day beginner 2, 5-day beginner 2 (d46's lighter Full Body squat
  adds 5 to v3's 115).
- **Quads cells under the bottom per (days, level), 60 / 90 minutes, today -> 2C-a** (round 4, A-4; the gate pins
  them). 2C-a does NOT move 3-day intermediate / advanced, 4-day advanced or 5-day intermediate / advanced at 60
  minutes:

  | Days, level | 60 min | 90 min |
  |---|---|---|
  | 3 beginner / intermediate / advanced | 36 -> 12 / 36 -> 36 / 36 -> 36 | 36 -> 2 / 36 -> 4 / 36 -> 36 |
  | 4 beginner / intermediate / advanced | 12 -> 2 / 36 -> 6 / 36 -> 36 | 12 -> 0 / 36 -> 0 / 36 -> 0 |
  | 5 beginner / intermediate / advanced | 36 -> 12 / 36 -> 36 / 36 -> 36 | 36 -> 2 / 36 -> 4 / 36 -> 36 |
  | 6 beginner / intermediate / advanced | 12 -> 12 / 36 -> 36 / 36 -> 36 | 0 -> 0 / 0 -> 0 / 36 -> 36 |
- **Repeats, both weeks** (int / adv, 60 / 90): week 1 74 / 86 / 320 -> 0 / 48 / 102; week 2 102 / 78 / 306 -> 30 / 54 /
  86 (3 / 4 / 5-day). d46's "334 -> 0" is the 3-day week 1 against v3's prototype; against today it is 74 -> 0.
- **Costs** (round 3, B-5; the founder saw the arm rows of §4A.1 before d40 / d43):
  - total weekly sets fall in 3-day 60-minute plans (70 of 108 plan-weeks; 4-day 60 34, 5-day 60 26; at 90 minutes 6 /
    0 / 6);
  - plan-weeks with an arm group under half its band bottom (60 / 90, 3/4/5-day): Biceps 154 -> 252, Triceps 202 ->
    227, against Quads 425 -> 0 and Hamstrings 275 -> 98.

## 4B. Measured, 2C-b (prototype v11b on top of 2C-a; 2,304 plans)

### 4B.1 The 30-minute choice the founder made (d44)

One plan, build_muscle 4-day intermediate full gym 30 minutes, week 1: today 4 exercises per day. With a 5th exercise:
Chest 5 -> 7, Biceps 6 -> 8, Triceps 2 -> 4, Calves 0 -> 2. With sets only: Back 9 -> 11, Shoulders 9 -> 11. Across the
grid (both before d45):

| Option | Zero-week plans | Suitable | Regressed |
|---|---|---|---|
| 5th exercise (v10) | 13 | 962 | 12 |
| Sets only (v10b, chosen) | 28 | 956 | 28 |

### 4B.2 30 / 45 minutes (today's splits, S3 + S4 with d44 / d45)

- Total weekly sets never fall, except 30-minute plan-weeks: build_muscle 3, lose_fat 1, general_fitness 1 (of 576 each).
- Plan-weeks where a group gains / loses sets, 30 minutes (of 576): build_muscle Chest +346 / -14, Back +334 / -24,
  Shoulders +253 / -42, Core +195 / -33, Hamstrings +196 / -20, Calves +108 / -14; lose_fat Core +280 / -89, Calves
  +138 / -52; strength Calves +144 / -82. The losses are the minimum giving a target group a seat in place of another
  exercise, and calves at 30 (d45).
- Rows on a 30-minute day: 4 on most days (beginner 1608 / 2304); 5-6 only where today's day already holds them.

### 4B.3 Totals

| Measure | Today | 2C (a + b, v11b) |
|---|---|---|
| Zero-week plans | 92 | 63: Calves 47 at 30 min (d45); Biceps 10, Core 8, Triceps 5, Chest 3 |
| Plan-weeks newly at 0 against today | | Calves 200 (30 min, d45), Chest 6, Triceps 4 (no-free-place residue) |
| Lead with fewer sets than today (same lead) | | 0-0.6 % of 30 / 45-minute days |
| Max minutes over | +4 | +6 (30 / 45 only) |
| Days over the count max (by `effectiveLevel`) | 0 | 0 |
| Verdicts, with the audit's over-time mirror (S4) | 789 suitable | 956 suitable, 30 regressed, 194 improved |

- **Round 2's "beginners over the count max" (B-3) was not reproduced:** it read the input level; at phase 3 a
  beginner's `effectiveLevel` is intermediate (count max 6). 0 days past the count max by `effectiveLevel`.
- **The 30 regressions** (all 30 / 45): new moderate issues ab_swing 15 (a minimum seat turns a zero week into a 2-set
  week next to a 5+ week), lead_starved 6, low_volume 4, unloaded 2, and **3 plans that become not_suitable** (round 3,
  B-7): `build_muscle|3|advanced|bodyweight|30|{1,2,3}`, "Week 2: no sets at all for Chest" (the allowance re-run's
  lead, Elevated Pike Push at 3 sets, leaves no time for Hindu Pushup, and the row cap leaves no seat). A newly major
  zero_muscle is a regression the 2C-b design must remove; its gate fails on one. 2C-b's plan round decides how (a
  swap of the lowest-priority seated row for the target, or the lead at 2 sets when the target is the week's only
  credit).
- **Calves at 30 minutes:** 55 plans have no calf sets in any of weeks 1-3 against today's run (d45).
- **Over time** is measured from the estimator (`min` in the dump). The gate uses the ledger's seconds; the build
  measures (display minus ledger) per day before writing the bound (round 2, B-6).

### 4B.4 The `glutes_legs` focus, against its no-focus twin (v11b)

| Measure | Today | 2C (v11b) |
|---|---|---|
| Calves plan-weeks to 0 | 652 | 0 |
| Inert plans (no focus group gains in any week) | 636 | 375 |
| Plan-weeks a focus group is lower than the no-focus twin | Quads 263, Glutes 0 | Quads 789, Glutes 877 |
| Plan-weeks Core is lower than the twin | 1319 | 2110 |

d38 accepted focus groups below the twin (the rule is "at least 2 sets", not "never below no-focus"); the build lists
the Glutes / Quads cells for the founder with the results.

## 5. Tests and files

### 5A. 2C-a

**Production:**
- `split_resolver.dart`: S1 lists, `selectV4(sessionMinutes:)`, `balancedWeekApplies`, `quadPrimaryCreditsGlutes`, the
  switch read.
- `models.dart`: `avoidEarlier` (`EarlierDayAvoid`).
- `volume_filter.dart`: carries `avoidEarlier`.
- `exercise_selector.dart`: the earlier-day avoid (`sameType`, `all`).
- `workout_schedule_read_service.dart`: `foreignDayNamesFor`, the row checks in `repeatPinsFrom`, the optional minutes
  on the pin builders.
- `test/plan_generator/plan_audit/plan_audit_dump_test.dart`: the credit mirror calls `quadPrimaryCreditsGlutes`.
- `plan_generator.dart`: lines 169 and 288 only (d36, d40).
- `plan_engine_flags.dart`: `balancedWeekEnabled`.
- `superset_pairer.dart`: no change. The new Upper days are 'upper' days and pair as today's 'Upper' did; pinned.

**Behaviour tests, `test/contracts/balanced_week_behavioral_test.dart`:**
- every list and slot order at 60+; 30 / 45 verbatim; strength 3-day verbatim; beginners (phase 1-2 Full Body for 3 / 4
  days, the phase-3 lift, 5-day every phase); slotsB present;
- the earlier-day avoid through the REAL pipeline (`VolumeFilter.filterDays` then `pickV4`), with a crafted pool of
  three rows: Upper B does not repeat Upper A's pick while another row exists; Full Body does not repeat Upper's or
  Lower's; a pool of one repeats (soft avoid);
- `VolumeFilter.filterDays` keeps the field (a direct test);
- `balancedWeekApplies`: days {3, 4, 5} only, null minutes false, 59 false, 60 true, switch OFF false, other goals false;
- the repeat-pin row checks (S1): the other family refuses, a renamed row is ignored, the day index past the plan
  refuses, OFF, `foreignDayNamesFor`;
- S2's value for every goal x days x {30, 45, 60, 90} x quadLegsB x switch; the allocator lets a squat grow past a full
  Glutes cap;
- the switch per reader.

**Gate, `test/plan_generator/balanced_week_gate_test.dart`** (the audit grid in-test, 2C-a part):
- the Quads residue at 60 and 90 minutes equals §4A.2's per (days, level) counts;
- no week 2 equal to week 1 in a 60+ build_muscle 4 / 5-day plan, except the beginner Full Body plans;
- week-1 repeated names at or under §4A.2;
- OFF digests equal main.

**Golden:** re-record with per-class attribution (S1, S2, the filter carry, each reverted alone), plus the OFF fixture.

**Expected reds, each with its cause named before re-recording:**
- `variant_b_quads_behavioral_test`;
- `quads_floor_6day_behavioral_test` and `quads_credit_flag_consumers_test` (the predicate move);
- `cross_day_variety_behavioral_test`;
- `session_set_budget_gate_test`;
- `lead_first_gate_test`;
- the `day_floor_gate_*` files (OFF digests and `quadOwnsGlutes`);
- `oi489_timed_hold_real_engine_test`;
- `core_list_pool_gate_test`;
- the injured sweeps (`kThinCeilings` stays 0 / 0);
- `plan_audit_lib_test`;
- `lead_first_kill_switch_golden_test` and `loaded_wins_kill_switch_golden_test` (their OFF fixtures run with 2C OFF);
- `loaded_wins_behavioral_test` T8 (`:502`, 4-day intermediate phase 2).

**Run every caller, targeted** (round 3, A-3; round 4, A-1): the files that call `generateV4`, `selectV4` or
`filterDays`, read the golden personas, or touch the pins (`repeatPinsFrom`, `buildRepeatPinsForAdvance`,
`last_phase_profile`, `generateAndSchedule`, `runGraduationPhaseAdvance`, `autoGenerateNextPhaseIfNeeded`), derived by
grep at build time (scratchpad `review_r3_A/callers.txt` is the first axis), each run with `TZ=Asia/Kolkata`; each red
gets a named cause before any expectation moves. Named in advance:
- `l2_repeat_pins_strip_test` (`:102-107`: a 4-day intermediate advance at the default 60 over rows named for today's
  4-day split; with v6's row check those rows are the other family and the pins are refused: the fixture's rows or
  minutes move, with the cause named);
- `repeat_content_scheduling_test` (`:64`, the pure `repeatPinsFrom`; compiles through the parameter's default);
- `pro_phase_advance_behavioral_test`, `phase_unlock_end_to_end_test`, `advance_choice*`, `lapse_gap_*`,
  `phase_unlock_start_date*` (the pin and advance paths);
- `thin_day_topup_behavioral_test` (looks days up by the old focus strings at `:284-447`; the OI-401 proof needs a
  persona re-search, not a relabel; `kShoulderElbowWeek2BackDay` is a pinned list);
- `injury_recheck_v14_contract_test` (`:253-266`, seven build_muscle 3/4-day reach personas, re-searched);
- `day_floor_kill_switch_test` and `test/fixtures/day_floor_off_hashes.json` (their OFF worlds set the 2C switch);
- `same_movement_day_gate_test` (hard zero over the new lists);
- the injured sweeps and `r6_removed_runs_*` (thin / one-exercise ratchets at 0 / 0), measured on the prototype before
  the build claims them;
- `repeat_phase_pinned_selection_behavioral_test` (`:159`, the 4-day split's variant B on day 0);
- with null minutes meaning today's lists, `library_overlay_copy_test`, `core_list_like_for_like_data_test`,
  `keep_all_slots_selection_test`, `variant_b_quads_behavioral_test`'s direct calls and `loaded_wins_behavioral_test:470`
  keep covering the 30 / 45 lists; each also gains a 60-minute sweep.

**Mutants:** `balancedWeekApplies`' clauses (60 `>=` vs `>`, the day set, null); slot orders; S2's connectives and the
6-day branch; the filter carry; `avoidEarlier` read and write (`sameType` and `all`); the row checks in `repeatPinsFrom`
(each refusal, the family difference); the switch per reader.

**Docs, 2C-a:** also re-anchor every `docs/sot_registry.yaml` range that cites `plan_generator.dart` after lines 169 /
288 grow (round 3, A-11), per commit.

### 5B. 2C-b

**Production:**
- `session_budget.dart`: `BudgetLedger(allowance:)`, `forcingBound`, the switch read.
- `session_set_allocator.dart`: worlds chosen allowance-off then re-run on (every path); the row cap (d44); the S3
  targets (including hold credit, d45), walk order, guards, fixpoint, `minimumSeats`; the 6-day path.
- `edit_profile_screen.dart`: the chip word ("About"); its comment.

**Behaviour tests, `test/contracts/weekly_minimum_behavioral_test.dart`:**
- each guard refuses (cap, top, forcing bound, the count);
- the cheapest slot and the tie rule; target order;
- focus targets; the trained-before target; Calves at 30 skipped, Calves at 45 not; hold credit;
- no slot means no seat; `minimumSeats`, never in `countForced`;
- every re-run branch: lead-first, the fallback, 2B OFF, 6-day, 2A off;
- **copy-day alignment** (round 2, A-2): a copy day plus a target on another day; B's copied day equals A's slot for
  slot;
- the walk leaves `rank`, B / C growth order and `leadSeats` alone; `evictFor` uses the slot's rank (a hold ranked
  before the moved slot is not evicted);
- the fixpoint: a group the first re-run zeroes is restored.

**Behaviour tests, `test/contracts/session_allowance_behavioral_test.dart`:**
- 300 s under 60 with the switch ON, none at 60+ or OFF; A2 / S3 never stack (no day past budget + 300 s);
- the worlds are chosen allowance-off (the lead keeps its base sets where it does today);
- the row cap: a day never holds more rows than its allowance-off world;
- the readers listed in S4 (Train / Home estimate, `_weekTwoGains`, titration).

**Gate, `test/plan_generator/balanced_week_gate_test.dart`** (2C-b part):
- zero-week plans at or under §4B.3 per group;
- no group newly at 0 against the OFF run except Calves at 30 and the named residue;
- no day past budget + 300 s + the 2B floor's overrun (ledger seconds);
- no day past the count max by `effectiveLevel`, and no allowance day past its allowance-off rows.

**Expected reds:** `exercise_count_band_behavioral_test`, `session_set_allocator_behavioral_test`, the
`day_floor_behavioral_test` clock fixtures, `session_duration_chip_wording_test`, `session_set_budget_wiring_test`
(tolerance), `plan_audit_lib_test` (the over-time mirror), the golden.

**Shared oracle:** `budget_invariant_oracle.dart`'s time excuse becomes budget + the allowance under 60 + the floor's
overrun; the count bound is added.

**Mutants:** each guard and target clause; the allowance and the no-stack rule; `allowance: false` in each world-choice
call; the row cap; the walk (mutating `byDay` instead); `evictFor`'s rank argument; the fixpoint; the 6-day branch;
Calves at 30 (`< 45` vs `< 60`).

### Docs (each part, for its own changes)

- nested `plan_engine/CLAUDE.md`: a new item, amendments to OI-454, 1B-Q, OI-458 and the count band (2C-b);
- `plan-engine-detail.md`;
- SoT entries: `balanced_week` (new), `quad_primary_glute_credit`, `session_duration_minutes`;
- `lib/features/profile/CLAUDE.md:47` (2C-b);
- `naming_conventions.md`;
- the diagnose docs;
- the closure ledgers;
- OI-475 / 477 / 501 updates;
- a new OI for the switch's deletion.

## 6. Review log

**Round 1 (2026-11-14, two context-blind Sonnet seats, code and measurements):**
- **Seat A, code.**
  - P0 A-1: no slotsB; fixed in S1.
  - P1: A-2 same-type repeats (`varyFromEarlierSameType`; it did not bite until round 2's A-1); A-3 count max; A-4 6-day
    precedence kept; A-5 oracles repointed; A-6 missing reds added.
  - P2: A-7 Quads residue named; A-8 hold credit (decided in v3: counted); A-9 re-run branches; A-10 strength 3-day
    branch; A-11 supersets on Upper days stated; A-12 beginners.
  - P3 A-13: one read per generation (v3: callees read, `generateV4` synchronous).
- **Seat B, measurements.** P1: B-1 focus wording (d38); B-2 new all-week zeros (d40); B-3 30 / 45 costs (d40 / d42);
  B-4 regressions and over-time (S4, the mirror); B-5 beginners. P2: B-6 squat on Push (d39); B-7 the over_top mirror.
  P3 B-8 definitions. Every reproduced number matched.

**Round 2 (2026-11-14, two context-blind Sonnet seats on v2):**
- **Seat A, code.**
  - P1 A-1: `VolumeFilter.filterDays` drops `varyFromEarlierSameType`, so the avoid never reached the picker. Fixed (S1);
    4-day repeats 464 -> 48.
  - P1 A-2: the S3 reorder mutated `byDay`, misaligning B's copied days. Fixed: a separate walk (S3).
  - P1 A-3: the reorder left `_Slot.rank` stale and `evictFor(d, r)` on the walk index. Fixed: walk + `s.rank` (S3).
  - P1 A-4: S4 cost the lead a set on 15-20 % of 30-minute days. Fixed: worlds chosen allowance-off (S4); 0-0.6 %.
  - P1 A-5: `plan_generator.dart` lines beyond 169 / 288 for the switch. Fixed: callees read it (S5).
  - P2 A-6: the "Up to N min" chip, comment, nested doc, chip test. Fixed: "About N min" (S4).
  - P2 A-7: repeat pins by day index across a split change. Fixed: the day-name guard (S1).
  - P2 A-8: direct `selectV4` callers and `filterDays` users must be run. Listed (§5A).
- **Seat B, measurements.**
  - P1 B-1: S3 zeroed groups the first run credited (Calves 44). Fixed: the fixpoint and target 3 (S3).
  - P1 B-2: the reorder vs `evictFor` and the floor ties. Fixed with A-2 / A-3.
  - P1 B-3: S4 changed the 30-minute shape (D-A). Put to the founder: d44 (sets, not exercises). Its "beginners past
    the count max" was not reproduced (input level vs `effectiveLevel`).
  - P2 B-4: "legs unchanged" false at group level. Restated (§4B.2) with group-level counts.
  - P2 B-5: verdicts once the mirror follows d42; the ab_swing class. Restated (§4B.3).
  - P2 B-6: "+6 is rounding" asserted. The gate uses ledger seconds; display minus ledger measured in the build.
  - P2 B-7: one dump per table; 5-day beginners change in every phase. Fixed (§4A.1, §0).
  - P2 B-8: the Quads gate sentence. Fixed: exact cells and counts (§4A.2).
  - P2 B-9: repeats. Answered by A-1.
  - P3 B-10: noted.
- Material issues in both rounds, almost all in S3 / S4: the unit is split (§4.12.1). 2C-a's part of round 2 was A-1,
  A-5, A-7, A-8, B-7, B-8.

**Round 3 (2026-11-14, two context-blind Sonnet seats on v3, scope 2C-a):**
- **Seat A, code.**
  - P1 A-1: the day-name pin guard has no data (the pin map carries no day names; changing it touches `generateV4`).
    Fixed: the `balanced_week` marker in `last_phase_profile` and the existing G5 gate (S1).
  - P1 A-2: §4A's verdicts and Glutes were scored with today's credit while the generator used S2's. Fixed: one audit
    rule for both sides (`audit_base2` vs `va2fb`): 0 regressed, 98 improved; Glutes shown both ways, both rise.
  - P1 A-3: hand-picked red lists. Fixed: every caller file is run; the known breaks named (§5A).
  - P2 A-4: S2 reaches beginners' phase 1-2 Full Body plans. Restated (§0); kept (no regression measured).
  - P2 A-5: the 5-day intermediate residue is 4. Fixed (and re-measured with d46: 120).
  - P2 A-6: the 3-day B lists differ from A. Fixed (S1).
  - P2 A-7: null minutes now means today's lists. Fixed (S1).
  - P2 A-8: the 3-day Full Body repeats. Put to the founder: d46 (different exercises).
  - P3 A-9 one predicate over days {3, 4, 5}; A-10 oracle minutes; A-11 fresh fill, registry ranges, 5-day B quad.
    Fixed or stated.
  - P1 A-12 (2C-b): `BudgetLedger`'s default. Fixed: `allowance = false`, production builders pass true.
- **Seat B, measurements.** P1 B-1 (= A-1). P2 B-2 (= A-5), B-3 (= A-4), B-4 issue counts and Glutes over_top (on one
  audit rule over_top falls by 11; Glutes table added), B-5 costs (total sets in 3-day 60, arms under half the bottom;
  stated). P3 B-6 (= A-9). 2C-b: P1 B-7 three plans become not_suitable (Chest zero week; recorded, the 2C-b design must
  remove it), P2 B-8 (calves all-week zeros, focus Glutes below twin; recorded). Every other 2C-a number reproduced,
  and 30 / 45, other goals and 6-day are byte-identical to today.

**Round 4 (2026-11-14, one context-blind Sonnet seat on v4, scope 2C-a):** every recomputed number matched (verdicts,
issue deltas, scope, Quads cells, repeats). Findings, all specification completeness, folded into v5:
- P1 A-1: the pin tests were missing from the caller list (`l2_repeat_pins_strip_test` goes red). Fixed (§5A).
- P1 A-2: the marker plumbing (where the predicate is computed, optional parameters, the reschedule re-stamp, the SoT
  text). Fixed (S1); the re-stamp also closes the pre-existing `days_per_week` case (a bug fix with its own test).
- P2 A-3: "OFF byte-identical" restated as "OFF writes nothing new", tested.
- P2 A-4: the 60-minute per-cell Quads table added (§4A.2).
- P3 A-5 (same `dayType`, the day-count branch, week-2 repeats, marker granularity) and A-6: stated.
- No design finding: 2C-a converged after round 4.

**Build-time change (v6, 2026-11-14):** the v5 marker design for repeat pins was replaced before any code landed (a
mid-phase reschedule rewrites only the rows from today, so a re-stamped profile can name a split weeks 1-2 do not hold).
The row check (S1) reads the rows the pins come from. It is reviewed by the B-pass (a fresh seat on the code), which
the plan-review record names.

**Build-time notes (v6, after the build):**
- The test oracles restate the credit rule instead of calling `quadPrimaryCreditsGlutes` (§S2, "Test oracles").
- The gate (`balanced_week_gate_test.dart`) pins §4A.2's per-(days, level) Quads table exactly, and it matched on the
  first run of the built tree (296 / 120). It also pins week 2 equal to week 1 at 16, all 4-day beginner Full Body,
  and week-1 repeats at 0 / 48 / 102. The 1,010 golden personas hold no 90-minute plan, so the gate also hashes its
  288-plan grid with the switch set. That hash equals the pre-2C tree's (HEAD c6b1ee48, run on a detached checkout).
- Costs found while re-recording, for the founder:
  - a 5-day build_muscle chest focus at 90 minutes now gets 13 Chest sets in week 1, where today's body-part split
    (with its Chest day) gave more than 16, the ordinary top a focus may pass (`session_set_budget_wiring_test`, moved
    to 6 days);
  - the balanced 5-day's Push, Pull and Upper days are the default 5-day's, so for a shoulder + elbow user they are
    thin with the floor off, as they already are for the other goals (the day-floor gate's floor-off tallies moved in
    7 tiers, -2 to +8 day-weeks). Unit 2B's floor seats every one; no day ends under 3.

## 7. Open questions (closed for 2C-a by round 4)

1. The `balanced_week` marker (S1): writer, G5 compare, minutes resolution at the advance, OFF byte-identity, legacy
   records. Is anything still wrong?
2. `avoidEarlier` (`sameType`, `all`) and `balancedWeekApplies` as specified; the §5A lists.
3. Do §4A's numbers reproduce from `audit_base2` vs `audit_va2fb`?
4. **Supersets** (the lever for more arm sets in 60 minutes): a separate unit, recorded for the founder; not in 2C.
5. 2C-b continues on 2C-a's merged tree with its own rounds (B-7's not_suitable plans, the hold-credit rule).
