# Generator step 2, Unit 2B: the 3-exercise day floor (OI-452)

Status: v6 (2026-11-13, converged at plan review round 4; founder decisions d30-d33), written on 2A's merged tree (main 8a2e1c5a). Tier L (plan engine), blast radius
platform. Step 2 plan: `docs/plans/2026-11-12-generator-step2-allocator.md` §10. Board: step 2 cards.

**Execution mode (§4.12.7):** inline, one worktree (`generator-step2b-day-floor`), one PR.

## 0. Scope

**The problem.** An injured user, mostly a beginner, can get a day of 1 or 2 exercises. Founder direction (2026-11-03,
OI-452) is a hard floor of 3 exercises a day. A day below the floor may exceed the weekly set band by a few sets, only
on those days, with its own stats.

**Done when (OI-452):**
- The plan is reviewed twice.
- The allocator keeps every day at 3 or more exercises, or says why it cannot.
- The weekly-top invariant is restated with its exception.
- `kThinCeilings` falls to 0 (or to a named residue).
- Mutants prove it.

**Not in scope:**
- the weekly minimums and the quad floor (2C);
- repeat-phase minutes (2D);
- the selector (the top-up keeps its own floor of 3);
- `plan_generator.dart`, which is not touched.

## 1. What happens today (measured on main 8a2e1c5a)

**Bug history (§4.1.5).**
- `2d04d7` (thin-day top-up, OI-401): fixed the SELECTOR side. An injured user's selector day is topped up to 3.
- Closure row `SBF-THIN-DAYS` (`docs/audit/set-budget-flip.closure.yaml:85`): after the session set budget went on,
  the ALLOCATOR removes slots whose group's weekly top is spent, "every removal there is a weekly-top removal".
- A guard that took removed slots back over the weekly top fixed the sweeps. It was reverted because it broke the
  allocator's weekly-top invariant (`session_set_allocator_behavioral_test`, a top of 16 reached 26) and the budget
  gate.
- This is the same class. The difference in this plan is §3: only days under 3, 2 sets a slot, the worlds chosen
  first, and a stated invariant.

**Writers and readers:**
- Writer, pass A (`session_set_allocator.dart`): seats each slot at 2 sets when `ledger.fits`, which checks time, the
  session cap and the weekly top.
- Writer, pass A2 (`:666`): forces a slot past the clock only. `canForce` (`:679`) refuses one that would pass a
  weekly top or a session cap.
- Reader of the verdict (`:722-733`): a day whose selector supplied fewer rows than the count floor goes in
  `selectorThin` (`:726`); one short for another reason goes in `belowCount` (`cap_top` / `clock`, `:732`).
- Reader of the counts: `test/helpers/injury_floor_sweep_lib.dart` `kThinCeilings` (exact ratchet) and
  `expectNoThin`.

**Measured (probe over the two sweep blocks that hold thin days, weeks 1-2):**
- `pairs`: the 15 pairs x 4 tiers x 4 goals x 3 levels x 3-6 days, phase 1, 60 minutes.
- `rep30`: the pinned repeat at 30 minutes, beginner.
- 369 thin day-weeks: pairs 70, all 5-day; rep30 299. This equals the recorded ceilings exactly.

**The labels hide the cause.** 363 of the 369 read `selectorThin`, because 3 selector slots are below the count floor
of 4 or 5. Yet the selector gave 3 slots and the day ended with 1 or 2. A temporary trace of every left-out slot gives
the real cause:
- Every one was refused by a WEEKLY top that earlier days had filled: Back 219, Glutes 69, Quads 61, Shoulders 29,
  Chest 8, Biceps 2.
- The session cap had room every time.
- The day had 700-850 s of clock left.

The founder's description is exact.

## 2. The rule (prototype measured)

**F1, the floor** (amended by d33: no clock bound; d31: every phase).
- After pass A2, a day whose rows (budgeted + not budgeted) are under `min(3, the day's reach)` seats one remaining
  slot at 2 sets past a group's weekly top.
- It never passes a session cap.
- (v3, d33) It is not bound by the clock. A seat that did not fit the day's remaining seconds when it was seated
  (`seconds(s, 2) > ledger.secondsLeft(d)`) is named `overClock` (v5, round 3 P1).
- It never takes a slot the rank-0 reservation blocked.
- It runs one slot per day per round, until nothing changes.
- The day's "reach" is what the selector supplied. A day handed 2 slots is floored to 2.

**F2, the choice.** The slot with the fewest groups over their top, then the least total excess, then the cheapest.
Unlike A2, the floor gives the lead no preference. Remaining ties go to the lowest rank (a strict comparison in rank
order). Round 4 P3.

**F3, the worlds (2A's R3).**
- Each variant's world (lead / capped / main) is chosen exactly as today, with the floor off.
- The chosen worlds are then re-run with the floor on: A first, then B, copying the final A.

Why: with the floor inside every world, a lead world one row short was lifted back to 3 rows over the top, and R3
then kept it instead of the capped world that stays inside the band. That changed R3's choice on 330 day-weeks that
were never thin.

**F4, stats.**
- `AllocationStats.floorSeats` (v3; v1-v2 `floorOverTop`): per day, each seat (name, 2 sets, the groups it took over the top, whether it passed the clock bound). B's copied
  days carry A's entries.
- The count verdict is unchanged. `selectorThin` still means the selector gave fewer rows than the count floor.
  `belowCount` still means the day is under that floor.
  - Both stay true for a day floored to 3 when the count floor is above 3, i.e. 25 minutes and up.
  - Below 25 minutes the count floor IS 3 (`session_budget.dart:412`), so a floored day is in neither list (round 2
    P2-4). `floorSeats`
  is what says the day reached 3 past a weekly top. (Round 1 P1-2: v1 claimed a floored day leaves both lists. It
  does not.)
- `belowCount`'s `cap_top` / `clock` label is computed BEFORE the floor (v5, round 3 P3), so it keeps its A2 meaning:
  what stopped pass A2. List membership (`selectorThin`, `belowCount`) is read after the floor.
  - Mechanism (round 4 P2): before the floor loop, snapshot the label of every day under the count floor.
  - After the floor, `belowCount[d]` takes the snapshot's label only for a day still under the count floor.
  - A test pins a case where the floor changes what `canForce` sees and the label stays.

**F5, kill switch.**
- `disable_day_floor` (`PlanEngineFlags.dayFloorEnabled`, default ON), with an optional `dayFloor` argument on
  `allocate`. It is read once per call.
- It applies in both paths: 2A on (the floor, and the re-runs of the chosen worlds) and 2A off. Switched off, the
  floor and the re-runs are skipped.
- **The four combinations** (both switches on is the default):
  - Both switches off: main 9fc3b043.
  - `disable_lead_first` alone: main + the floor.
  - `disable_day_floor` alone: today's main (8a2e1c5a).
- **The OFF proofs** need injured personas, because no golden persona reaches the floor (round 1 P1-1, round 2 P2-5):
  - **Fixture** `test/fixtures/day_floor_off_hashes.json`.
    - Personas: the probe's two blocks, i.e. `pairs` (15 pairs x 4 tiers x 4 goals x 3 levels x 3-6 days, phase 1)
      and `rep30` (the pinned repeat at 30 minutes, beginner).
    - Fixture size: a hash of every plan in those blocks.
    - Recorded on main 8a2e1c5a. A test with `dayFloor: false` must equal it.
    - The same personas with the floor ON must differ on exactly the thin days (pinned counts).
  - The 2A OFF golden is kept as it is (1,010 uninjured personas, unchanged by the floor).
  - **Pinned combinations** on a small injured sample:
    - 2A on + floor on;
    - 2A on + floor off (= main 8a2e1c5a);
    - 2A off + floor on;
    - 2A off + floor off (= main 9fc3b043, the 2A-off fixture's world).
  - **The 6-day path** (B = A) is pinned in each.
- The prototype's `debugFloorExcessCap` is a probe knob. It goes before the build.

**Invariant restated:**
- Week: `week(g) <= weeklyTop(g) + the floor's sets over the top for g` (named in `floorSeats`).
- The session cap is never passed.
- Time: within budget, plus the day's `countForced` seconds (A2, at most 300 in total), plus the seconds of the day's
  `overClock` floor seats (no cap). A floor seat is never in `countForced` (v5, round 3 P1).

**Readers of the weekly top**, each moved to one shared oracle (`test/helpers/budget_invariant_oracle.dart`: top +
the named floor sets; time excused per the restated invariant). No reader is loosened ad hoc.
- `test/plan_generator/session_set_budget_gate_test.dart:385` (hard fail; its injured block `:536`)
- `test/contracts/session_set_budget_consumers_test.dart:356` (week) and `:342-347` (time)
- `test/contracts/session_set_allocator_behavioral_test.dart:744` (week; `forced == 0` covers guard seats, not floor
  seats) and `:728-735` (time)
- `test/contracts/session_set_budget_wiring_test.dart:173-180` (time)
- `test/plan_generator/session_set_budget_gate_test.dart:318-370`: the main time oracle. `countExplained` reads
  `countForced` only and caps the excuse at 300 s. It reads the oracle instead (round 2 P1-1).
- `test/plan_generator/oi489_timed_hold_real_engine_test.dart:99-102` (time)
- `test/contracts/quads_floor_6day_behavioral_test.dart:343-382` (`auditPlan`: week top `:348`, `:380-382`; day
  minutes `:371-373`). Its uninjured grid passes with the prototype (18 / 18), so no day there reaches the floor. It
  is routed through the oracle anyway, so a future floor seat there is named, not failed (round 2 P1-2).
- `test/plan_generator/lead_first_gate_test.dart`
- Checked and unaffected:
  - `exercise_count_band_behavioral_test.dart:406` (asserts no `countForced` from 45 minutes);
  - `session_estimate_display_test.dart:439`, `:537` (display parity);
  - `session_set_budget_gate_test.dart:404` (a `firstLifts` precondition);
  - `plan_audit_dump_test.dart:110` (dump only).

**The oracle's time excuse** (d33, v5): budget + the day's `countForced` seconds (A2) + every `overClock` floor
seats' seconds (no cap).

**Library readers (behaviour unchanged; stated):**
- `BudgetLedger.weeklyTop` / `fits` (`session_budget.dart:540-574`): a group already over its top fits no further
  set, so passes B, C and D never grow a floor seat past 2.
- `PeriodizationEngine._weekTwoGains` (`periodization_engine.dart:165-230`): week 2 gains nothing on an over-top
  group.
- `VolumeTitration` (`volume_titration.dart:181-233`, OFF by default): can trim a floor seat 2 -> 1 when it trims a
  group over its bottom. It is named here as an accepted read: titration is off, and when on it already moves sets
  +/-1 by its own rule.

**F3 restated (round 1 P2-4).**
- The worlds are chosen with the floor off.
- A's chosen world is re-run with the floor. B's chosen world is re-run copying the FLOORED A, so a copied day carries
  its floor sets into B's week.
- The floored B is not compared with main's B again. Round 2 (P2-3) showed the v3 reasoning was wrong: a copied
  floored A day adds over-top sets to B's week, so B's own days have less room. Measured instead, as the floor off vs
  on over every day:
  - Probe blocks: 34,560 day-weeks. The only changes are the 369 thin day-weeks (2 -> 3: 353; 1 -> 3: 16) and 10
    day-weeks that keep their exercises with one set fewer on one row. Example: Backpack Bent-Over Row 3 -> 2, the
    week's Back room taken by a floor seat on another day; a week-2 gain 4 -> 3. No day loses a row or an exercise.
  - Grid: 418,608 day-weeks. Only the 2,292 thin day-weeks change (60 minutes: no set knock-on).
  - The 392 day-weeks with a floor seat in the probe (369 thin days + 23) are reconciled (v5, round 3 P2): the 23 are days
    with 3 rows in both worlds. There, the floored A copy took the week's room, the slot's normal seat was refused,
    and the floor seated it instead. 13 come out identical, and 10 have a set less on another row (the 10 above).
    v4 called the 23 a reading error; that was wrong.
- The build pins this in the new gate: against the floor-off run, no day loses a row or an exercise, and only a day
  under 3 gains rows. The set knock-on is counted and pinned at its measured number.
- No code guard is added: the measured worse-than-main count is 0.
- Cost: one extra `_variant` for A and one for B per plan (one in total on the 6-day path). It is measured on the
  gate suites before the build is accepted.

**Interactions (round 1 P2-5, P3).**
- **A floored lead.** A floor seat can be the day's opener, or the opener among the admitted rows. It holds 2 sets,
  so R2 caps the day's others at 3 (= `baseSets`). `leadSeats`, `firstLifts` and week-2 R5 follow it. Pinned by a
  test.
- **The count target never blocks a floor seat.** `rowsOf < 3` means `seated < 3 - nonBudgeted <= target`.
- **The rank-0 reservation.** A slot the top refused at rank 0 is not `reserveBlocked`, so the floor can seat it. The
  later days' leads are already seated (pass A runs rank by rank), so no lead loses its seat. Pinned.
- **An evicted hold** lowers `rowsOf` but not the reach, so the floor seats a budgeted slot in its place. Pinned.
- **Seat order across days** is by day index, so an earlier day claims first under a cap. Pinned.
- **A pinned repeat day's reach** is its pin count.
- **Week 4** (`min(sets, max(2, floor(0.6 x sets)))`) leaves a floor seat at 2. Pinned.
- **Pass B and the bottom pass (round 2 P3-6):** a floor seat over a top spends that week's room, so another row of
  the same group can grow one set less (the 10 day-weeks above). This is a stated cost of d30, not "behaviour
  unchanged".
- **The coach's `shortenDay`** (`swap_service.dart:614-700`) can still trim any day to 2, a floored day included. It
  is unchanged and out of scope (round 2 P3-7).
- **The display** (`budgetedDaySeconds`) shows an over-clock floor day's real length, e.g. 38 minutes on a 30-minute
  plan (d33).
- **`WarmupCooldownSelector`** scales with the session minutes, not the day's seconds, so it is unaffected.

**Prototype results (probe, weeks 1-2):**

| Weekly excess cap per group | Thin day-weeks left (of 369) | Floor seats | Largest excess over the top |
|---|---|---|---|
| none | 0 | 392 day-weeks with a floor seat (369 thin; 23 three-row days re-seated, §2 F3); at least 408 seats (16 days need 2) | +8 (+6 or +8 in 42 group-weeks) |
| +4 | 39 | 369 | +4 |
| +2 | 128 | 269 | +2 |

- **Induced B days:** a floored A day copied into B puts its over-top sets in B's week. Another B day then loses room
  and is floored too: 23 day-weeks, all in bodyweight / home 30-minute beginner repeats.
- **Where the large excesses sit:** injured beginner plans where the injury leaves one region. For example,
  bodyweight shoulder + lower_back leaves only leg rows, so every day stacks Quads and Glutes: Glutes +6 against a top
  of 12, +8 against 10.
- **The 1,010 golden personas are unchanged.** No uninjured plan reaches the floor.

**Whole injured grid** (`injured_grid_dump_test.dart`: 46,512 runs, 418,608 day-weeks, weeks 1-2, 60 minutes;
measured 2026-11-13 on the prototype, three worlds through a probe knob):

| World | Empty | Thin (1-2 exercises) | One-exercise | Day-weeks changed vs floor off |
|---|---|---|---|---|
| Floor off (main 8a2e1c5a) | 0 | 2,292 | 94 | – |
| Floor, no cap | 0 | 0 | 0 | 2,292, exactly the thin ones (+1 exercise 2,198, +2 exercises 94) |
| Floor, cap +4 a group-week | 0 | 241 | 51 | 2,088 |

- **Cap +4 residue, by block:** `quads_all` 108, `triples_eq` 76, `pairs_repeat` 21, `pairs` 20, `all9_all` 16. Basic
  gym 151, full gym 50. Beginner general_fitness 135.
- **No-cap world:**
  - Measured with the v2 prototype, which still had the clock bound: the bound never stopped a floor seat (0 thin days
    left by it, in the grid and in the 30-minute probe). So d33 (no bound) changes no measured plan.
  - Run time: 130 vs 131 minutes for the floor-off world, so the extra runs of the chosen worlds cost nothing
    visible.
  - The grid's runs are at 60 minutes, and no day there changes besides the thin ones. The set knock-on (10
    day-weeks) is in the 30-minute pinned repeats.

## 3. Founder decisions (2026-11-13, recorded on the board as d30-d33)

- **d30, the size of "a few sets": no limit.**
  - A day under 3 goes past a group's weekly top as far as it needs to reach 3.
  - Grid: thin days 2,292 -> 0. Most weeks go +2 or +4 over; a few injured plans go +6 to +8 (bodyweight shoulder +
    lower_back: Glutes 18 against 10).
- **d31, deload phases: the floor applies everywhere.**
  - Phase-4 sample (the pairs block, 2,880 runs): thin day-weeks 89 -> 0, those weeks +2 to +4 over the lowered top
    (+6 twice).
  - The v2 recommendation (no floor in a lighter phase) is withdrawn.
- **d32, a day the picker gave fewer than 3: floored to its reach** (it keeps what was found). Not seen in the grid.
- **d33, the clock: the floor may pass the 300 s forcing bound.** Measured, it never needed to (0 thin days left by
  the clock in the grid and the 30-minute probe).

**What changes in the rule:**
- F1 drops the clock condition: a floor seat needs only the session cap and a slot not blocked by the reservation.
- F4's stat becomes `floorSeats`: per day, each seat as `(name, sets, overTop: [groups], overClock: bool)`, where
  `overClock` means the seat did not fit the day's remaining seconds when it was seated (v5). A seat can be over the
  top, over the clock, or both.
- The restated invariant reads:
  - Week: `week(g) <= weeklyTop(g) + the floor's sets over the top for g`.
  - Session cap: never passed.
  - Time: within budget + the day's `countForced` seconds + its `overClock` floor seats' seconds (see §2).

## 4. Tests (planned, v5)

**New behavioural tests** (`test/contracts/day_floor_behavioral_test.dart`):
- F1:
  - seats past the weekly top;
  - never past a session cap;
  - never a reservation-blocked slot;
  - not bound by the clock (d33);
  - the reach rule (d32): a day handed 2 slots is floored to 2;
  - a phase-4 (lighter) week is floored too (d31);
  - below 25 minutes a floored day is in neither verdict list.
- F2: the order (fewest groups over the top, then the least excess, then the cheapest).
- F3: the worlds are chosen floor-off, then A and then B are re-run; B copies the floored A, and its copied day carries
  A's `floorSeats`.
- F4: `floorSeats` with `overTop` and `overClock`. `overClock` is set exactly when the seat did not fit the remaining
  seconds, and a floor seat is never in `countForced`.
- F5: the kill switch and the `dayFloor` argument, in both 2A paths.
- Interactions:
  - a floored lead (`leadSeats`, `firstLifts`, R2 at 3, week-2 R5);
  - week 2 gains nothing on an over-top group;
  - week 4 leaves a floor seat at 2;
  - an evicted hold;
  - the count target.

**Shared oracle** `test/helpers/budget_invariant_oracle.dart` (§2), used by every reader in §2's list.

**New gate** (`test/plan_generator/day_floor_gate_test.dart`), over the probe's `pairs` and `rep30` blocks plus a
phase-4 `pairs` block (round 3 P2-4). It covers weeks 1-4; its pinned counts are re-measured over weeks 1-4 (the
probe's were weeks 1-2). The sweep personas carry no focus group (`injury_floor_sweep_lib.dart` `gen` passes none),
so pass D's R2 exemption cannot meet a floor lead there. It asserts:
- no day under min(3, its reach);
- against the floor-off run of the same persona: no day loses a row or an exercise, only a day under 3 gains rows, and
  the set knock-on is pinned at its measured count;
- the oracle holds on every day;
- no budgeted row at the lead + 2.

**Kill-switch fixture** `test/fixtures/day_floor_off_hashes.json` (§2 F5).

**Re-recorded with cause.** v5 rule: the build runs every plan-engine test file on the built tree and lists each red
with its cause before acceptance; this list is what round 3 found by reading.
- `kThinCeilings` (`injury_floor_sweep_lib.dart`) and the eight `r6_removed_runs_*_test.dart` exact ratchets
  (`r6_removed_runs_lib.dart:94`), to 0 or the named residue.
- Count-band (m): the floor passes the weekly top now.
- `session_set_allocator_behavioral_test`:
  - the weekly top, a reach-2 day (d32);
  - the lighter phase (d31);
  - the seeded sweep's top check, through the oracle;
  - "R1 P2-2" (`:874-898`): the 30-minute day whose clock dropped the lead now seats it at 2 past the clock (d33). The
    stated policy "the lead lift is protected from the week and from an empty day, not from the clock" gains "and, by
    d33, from a thin day".
- `quads_credit_flag_consumers_test.dart:50-53` and its week-2 twin: reach-2 days floored to 2 (d32), Glutes past
  16.
- Preconditions to re-check: `thin_day_topup_behavioral_test.dart` (~373, ~427, ~444) and
  `session_set_budget_wiring_test.dart:302`.

**Mutants:**
- each condition of F1: the top, the session cap, `reserveBlocked`, the reach, the phase;
- each key of F2;
- the `overClock` classification;
- the world order (F3: the floor inside the world choice);
- B copying the unfloored A;
- the `floorSeats` copy;
- the kill switch in each 2A path.

## 5. Files

- **Library:** `session_set_allocator.dart` (the floor, `floorSeats`, the label snapshot, the world re-runs, the
  `dayFloor` argument) and `plan_engine_flags.dart` (`dayFloorEnabled`, `disable_day_floor`).
  `plan_generator.dart` is not touched.
- **Tests (§4):**
  - the new behavioural test, the gate, the oracle and the fixture;
  - the re-recorded files.
  - The build also runs, and lists any red from, every file that calls the allocator, including
    `lead_first_allocator_behavioral_test`, `allocator_timed_hold_eviction_behavioral_test`,
    `plateau_rotation_behavioral_test`, `rest_by_type_behavioral_test` and `lead_first_kill_switch_golden_test`.
  - The scratch probes (`test/zz_*`) and the probe knob `debugFloorExcessCap` are removed.
- **Docs:**
  - this plan;
  - the plan-review record `docs/plan-reviews/generator-step2b-day-floor.md`;
  - a diagnose doc (the thin-day class, recurrence of `SBF-THIN-DAYS` and `2d04d7`);
  - nested `plan_engine/CLAUDE.md` (the floor, and the lead-protection sentence per d33);
  - `plan-engine-detail.md`;
  - `naming_conventions.md` (`disable_day_floor`, `dayFloorEnabled`, `floorSeats`, `overTop`, `overClock`,
    `day_floor`);
  - the SoT registry: concept `day_floor`, with `behavioral_test_path:
    test/contracts/day_floor_behavioral_test.dart`;
  - the OI board: OI-452 archived to `closed_issues.md`, and an OI minted for the kill switch's deletion after the
    device check;
  - the closure ledger `docs/audit/generator-step2-2b.closure.yaml`.

## 6. Review log

- **Round 1** (2026-11-13, one fresh Sonnet seat, read-only): not converged. 3 P1, 4 P2, 1 P3.
  - P1-1: the kill switch must cover the 2A-off path, with an injured OFF proof.
  - P1-2: F4's verdict claim was false.
  - P1-3: the weekly-top readers needed one oracle.
  - P2: the B re-run is not compared with main's B; a floored lead and R2 / R5; the lighter phase is an exception;
    the clock bound is a decision.
  - All are folded into v2 above.
- **Founder decisions d30-d33** (2026-11-13): v3.
- **Round 2** (2026-11-13, one fresh Sonnet seat on v3, read-only): not converged. 2 P1, 3 P2, 2 P3.
  - P1-1 and P1-2: the lists of time and week-top readers were incomplete (the gate's time oracle, oi489,
    quads_floor's `auditPlan`).
  - P2-3: the F3 claim that B can never be worse rested on wrong reasoning. Measured: no row lost; 10 day-weeks with a
    set less.
  - P2-4: F4 is wrong below 25 minutes.
  - P2-5: the OFF proof was not concrete.
  - P3: the pass-B knock-on; `shortenDay` and the display.
  - All are folded into v4.
- **Round 3** (2026-11-13, one fresh Sonnet seat on v4, read-only): not converged. 1 P1, 3 P2, 2 P3.
  - P1: `overClock` defined as past 300 s left a hole for a top-refused seat 1-300 s over. Redefined as "did not fit
    the remaining seconds".
  - P2: more tests go red (quads-credit consumers, R1 P2-2, eight r6 ratchets), so the build lists every red with its
    cause.
  - P2: the stale v1-v3 text is rewritten; the 392 / 23 records are reconciled.
  - P2: the gate gains a phase-4 block.
  - P3: the `belowCount` label is read after the floor (stated below); "four combinations" now lists the default.
  - All are folded into v5.
- **Round 4** (2026-11-13, one fresh Sonnet seat on v5, read-only): **converged.** 0 P0, 0 P1, 2 P2, 4 P3; no design
  change.
  - P2: §5 now names the plan-review record, the diagnose doc and the SoT `behavioral_test_path`.
  - P2: the label snapshot mechanism.
  - P3: the "day-weeks with a floor seat" unit; F2's tie rules; the gate counts re-measured over weeks 1-4; no focus
    in the sweep personas.
  - All are folded into v6.

## 7. Build notes (2026-11-13)

Where the build differs from §4 / §5, and why:
- **The gate is three files** (`day_floor_gate_pairs_p1_test.dart`, `_pairs_p4_test.dart`, `_rep30_test.dart`, one test per
  tier, harness `test/helpers/day_floor_gate_lib.dart`) instead of one: one file would run about 30 minutes on CI.
  The pairs blocks run at 3-6 days (the probe's), weeks 1-4.
- **The kill-switch fixture stores digests.** `day_floor_off_hashes.json` holds, per (block, tier), the sha256 over the
  sha256 of every floor-off plan of the gate (12 entries for 6,720 personas), not one hash per plan: the gate's own OFF
  leg is the comparison, so the OFF plans are generated once. Recorded on a detached checkout of main 8a2e1c5a by
  `day_floor_kill_switch_test.dart`, which imports only `test/helpers/day_floor_personas.dart` (no 2B symbol) so it
  compiles there. All 12 equal.
- **The combination sample moved.** The first sample (3 pairs x 4 tiers x 4 goals, beginner, 3 and 6 days) held no
  thin day: the floor changed 0 of its 192 keys, so its floor-on pins proved nothing. The sample is now basic_gym pairs
  at 5 days plus the 6-day 30-minute repeat, where the floor acts.
- **The choice order is a pure function** (`SessionSetAllocator.floorPrefers`), so each F2 key is tested and mutated
  directly.
- **Knock-on:** 7 day-weeks over weeks 1-4 on the final tree (the repeat only); the prototype probe had 10 over weeks
  1-2. The difference was not traced; the final count is pinned.
- **Finding for the next step (2C), not a 2B change:** 9 day-weeks (pairs phase 1, home_dumbbells, wrist + elbow,
  strength, intermediate, 4 days) hold a row at the lead + 2 with the floor on AND off (identical plans): both variants
  fell back to Unit 2A's `main` world, where R2 does not apply. The 2A gate covers uninjured personas only. The 2B gate
  pins the count and fails on any lead + 2 the floor adds.
