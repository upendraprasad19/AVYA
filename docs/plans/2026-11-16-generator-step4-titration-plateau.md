# Generator step 4: switch on volume titration and plateau escalation (OI-53)

Board: https://claude.ai/artifact/QVpiDjC2KnfPSDh4wVdVEs, step 4 (t401-t406). Pass mark: "No set is added outside the
goal's weekly range."

Plan v3.1 (after review rounds 1 (seats A, B), 2 (seats C, D) and 3 (convergence); see the review log).

## 0. Scope and founder basis

- OI-53's last two ship-dark flags: `enable_volume_titration` (W2.7) and `enable_plateau_escalation` (W3.5: +1 set and
  rotation, one flag). Both act only at a fresh PRO phase advance (`applyVolumeTitration` / `applyPlateauEscalation`,
  passed `pins == null` by the two advance callers: `workout_schedule_read_service.dart:731,734`,
  `pro_phase_advance.dart:888,890`); every other generation is untouched (golden, onboarding, dev panel
  `simulation_service.dart:148`, `holdWeek` (3D): none passes the opt-ins).
- **d82 (2026-11-16):** plateau escalation ships whole, the +1 set and the rotation.
- **d81 (2026-11-16), carried in (findings feed the next step, founder 2026-11-12):** Cut and Maintain identical in 5 of
  576 live-world (finisher switch unset) Cut / Maintain profile pairs is accepted; the gate gains that live-world check
  (section 4, item 0).
- The rules follow decisions already made: d26-d29 (2A: the lead first; R2 every other budgeted row at most the lead's
  sets + 1; R5 the same in week 2), d30-d33 (2B: the day floor's 2-set seats), d65 (a trim takes the most sets first,
  ties to the latest rank, never below 2, and may take the lead).
- Tier L (plan engine, a ship-dark flip): full ×2 plan review and `bpass: accepted` (§4.12.4: a flip is not the
  ship-dark tier). Execution: inline, one worktree (`generator-step4`), decided now (§4.12.7). `plan_generator.dart`
  is not touched.

## 1. What happens today (measured)

Harness `test/plan_generator/plan_audit/history_sim_dump_test.dart` (new, test-only, skipped unless `HISTORY_SIM_OUT`
is set; it is t404's history simulation). 576 profiles (Build / Cut / Maintain x 3-6 days x 3 levels x 4 tiers x 30 /
45 / 60 / 90 minutes), no injuries, no explicit focus (the generator still resolves `weakMuscles()` focus from
the history, below). Per profile and scenario it generates the earlier phase, logs its LOADED
lifts (`weight_reps` / `weighted_bodyweight`) as `exlog_*` sessions ending yesterday (the shape `e1rm_history.dart:28-36`
reads), writes 6 green `readiness_*` rows, and generates the next phase twice from that history: switches ON and opted
in, and switches OFF and not opted in (doubly off). History is cleared per profile; the clock is pinned (2026-11-16
09:00). Scenarios:

- **progress:** phase 1 history (28 days), +2.5 % a session, phase 2 advance (titration's +1).
- **decline:** as progress, each lift's last session 10 % lower (titration's -1).
- **flat:** phase 1's plan logged over 8 weeks at one load, phase 3 advance (plateau needs >= 3 sessions spanning
  >= 28 days, `plateau_scan.dart:42,45`, so it cannot fire at the first advance).

Main 85bdcbbe (the generator equals 63af8c63). Counts over 576 profiles per scenario. Definitions = the gate's
(section 4 item 3), computed by `histsim_analyze3.py` (session scratchpad) over `histsim_main3/history_sim.jsonl`:
group sets count BUDGETED rows only (`SessionBudget.isBudgeted`, as the ledger does); deload weeks are excluded from
the band and lead checks; the lead is `SequencingEngine.openerOf` over the day's budgeted rows, dumped per day by the
harness; a row crediting a focus group is exempt from R2. **Every history scenario has focus groups:** at phase >= 2
`resolveBodyFocus` falls back to `weakMuscles()` over the logged history (`training_history_analyzer.dart:176`;
324 / 324 / 432 of 576 plans), so those groups' top is `SessionBudget.focusWeeklyTop` (25). The ceiling is
top(g) + the floor's seats past it (`BudgetInvariantOracle.floorOverTopSets`, from `debugLastStats` read right after
the ON call; variant A for weeks 1 and 3, B for weeks 2 and 4, A for a 6-day plan). Phases 2 and 3 only: a lighter
phase's top (`band.bottom`, `session_budget.dart:~685`) is not modelled, and no gate scenario generates one.

| | progress | decline | flat |
|---|---|---|---|
| plans with deltas / changed | 460 / 187 | 460 / 404 | 460 / 446 (picks changed 432) |
| pass mark: group-weeks over the ceiling, ON / OFF | 0 / 0 | 0 / 0 | 0 / 0 |
| group-weeks over the raw top(g) with ON > OFF (same picks / rotated) | 0 / 0 | 0 / 0 | 0 / 0 |
| days with a NEW non-focus row past lead + 1 (R2 / R5) | 451 | 149 | 325 |
| days whose (same) lead lost a set | 0 | 831 | 0 |
| new 1-set rows | 0 | 1,538 | 0 |
| days longer ON / of those over the audit bound (+6 under 60, +5 at 60+) / max extra | 735 / 0 / 10 min | 0 / 0 / 0 | 1,497 / 0 / 21 min |
| under-bottom group-weeks (groups with sets in either world) OFF -> ON | 8,942 -> 8,818 | 8,942 -> 8,942 | 9,956 -> 9,742 |
| major group-weeks at 0 only in OFF / only in ON | 0 / 0 | 0 / 0 | 6 / 0 |

Plan v1's table (lead = the first crediting row, no focus exemption, the band top for every group) read 61 over-top
flat group-weeks; with the generator's own focus top and floor excuse they are 0: no break existed.

- **Declines that trim at all (decline scenario):** 3,519 (plan, group) pairs ask for a -1; only 1,283 get one in any
  week today, because the band-bottom guard (`volume_titration.dart:228`) refuses the rest. Estimated on the OFF rows
  (`t2b_estimate.py`): with T2 below, 1,030 still trim; the 253 that lose it have only 2-set rows, or a lead whose trim
  would break R2 (both recorded decisions: d65, d26-d29). "Never the lead" (plan v1) kept only 881.
- **Bodyweight users get almost nothing.** A row with no load gives no e1RM, so 116 of 144 bodyweight profiles have no
  deltas; the other 28 log a weighted bodyweight row.
- **Rotation, flat scenario, net (d82):** under-bottom group-weeks fall by 214, major group-weeks at 0 by 6.
- Why the pass mark holds: every +1 must pass `ledger.fits` (`volume_titration.dart:223`), which checks every credited
  group's top (the focus top for a focus group), session cap and time; rotation changes picks BEFORE the allocator
  (`plan_generator.dart:193`), whose own seats stay inside the oracle's ceiling. The gate proves it on the final rows,
  and the mutation "titration ignores `ledger.fits`" must redden it.

Why (file:line):
- `VolumeTitration.applyToWeeks` (`volume_titration.dart:163-249`) runs after the allocator and after week 2's gains
  (`plan_engine/plan_generator.dart:348` apply, `:379` titration, `:383` sequencing) on all four weeks, and has no lead:
  a +1 goes to the first matching row that fits the ledger (top, session cap, time), so an accessory passes the lead + 1.
- The -1 guard is only "at least 1 set" and "no credited group at or below the band bottom" (`:227-228`): it takes the
  first matching row (day-major, slot order, `:210-214`), which is the lead whenever the lead credits the group, and
  takes a 2-set row (a 2A seat, a 2B floor seat) to 1.
- `_recovered()` (`:112-132`) counts `readiness_*` rows with no `PlanEngineFlags.readinessEnabled` check, so with
  `disable_readiness` set old rows still allow a +1. `PlateauScan` checks it (`plateau_scan.dart:83,126`).

## 2. Rules

- **T1. A +1 obeys the lead-first rule.** In each week of `applyToWeeks`, a day's lead is `SequencingEngine.openerOf`
  over that day's budgeted rows (`SessionBudget.isBudgeted`) in that week, computed once per day before any delta
  (titration runs before sequencing, so the opener is derived, not read from position; the definition `_weekTwoGains`
  uses, `periodization_engine.dart:229-230`). Each group takes at most one ±1 per week (the `break` at
  `volume_titration.dart:235`), so the check is: a +1 on a row that is not the lead and credits no `budget.focusGroups`
  group needs `current(row) <= current(lead)`, read at that moment (the lead may already hold an earlier group's +1 this
  week, as `_weekTwoGains` counts `gained`). This equals R5 (`periodization_engine.dart:240-242`); the allocator's R2
  exempts its focus PASS, R5 and T1 exempt a row crediting a focus group. `openerOf` sorts on type / laterality / CNS
  demand only, never sets (`sequencing_engine.dart:62-66`), so a ±1 cannot move the lead. Candidate order is unchanged
  (day-major slot order, first that fits). `applyToWeeks` gains `bool? leadFirst` (null reads
  `PlanEngineFlags.leadFirstEnabled`, as `PeriodizationEngine.apply` and `SessionSetAllocator.allocate` do); false turns
  T1 and T2's guard off. Note: in a history scenario the focus groups come from `weakMuscles()` (phase >= 2,
  `training_history_analyzer.dart:176`), so the exemption is live in every advance, not only with a `physique_focus`. Appended 2D rows cannot occur (titration runs only when `pins == null`).
- **T2. A -1 follows d65's trim order and keeps R2.** Candidates: rows crediting the group with `current >= 3` (never
  below 2) whose credited groups all stay above the band bottom (today's guard, kept). Order: the most sets first; ties
  to the latest day, then the latest slot in that day (d65's "latest rank", extended across days; plan v1 left the
  cross-day tie open; the lead is not always slot 0, so on a tie it can be the latest). The lead is a candidate only if,
  after its -1, every OTHER budgeted row of its day that credits no focus group has `current <= lead's new sets + 1`
  (the T1 / R5 predicate; a focus row legally above it, d27, never blocks the trim; on the deload week every `current`
  is the stash); a skipped candidate passes to the next. No candidate: the group keeps its sets that week (as a refused
  +1 is today). With `leadFirst` false, the lead is an ordinary candidate. A non-lead trim never lowers a row below 2,
  so the 2B day floor, 2C-b's minimum seats and a group's only credit are untouched.
- **T3. Deload week:** T1 / T2 read and write the stash (`workingSets`); a row whose stash is null is skipped, per row
  (today a null counts as 0 and a +1 on it writes `workingSets: 1`); a lead whose stash is null switches the T1 / T2
  lead checks off for that day (it cannot be compared). The generator writes the stash on every row or on
  none ( `periodization_engine.dart:126-132`, so this only changes hand-built weeks). The triggered un-deload restores
  the titrated peak, unchanged.
- **T4. `_recovered()` returns false when `PlanEngineFlags.readinessEnabled` is false** (the plateau scan's mirror).
- **T5. The flip.** Both getters default ON (catch -> true, the other kill switches' pattern) and read new kill
  switches: `disable_volume_titration`, `disable_plateau_escalation`; the `enable_*` keys are retired, as
  `enable_equipment_exclusions` was (every account is a testing account, CLAUDE.md section 1). The opt-in arguments
  and the two advance callers are unchanged; the getters are read once per call, where they are read today
  (`volume_titration.dart:56`, `plateau_scan.dart:81,125`). The dev panel gains a toggle for each kill switch, beside
  `disable_readiness` / `disable_triggered_deload` (`dev_panel_screen.dart:320-360`), so the founder's device check
  (t406) has an off switch without a Hive edit (§4.6 step 3).
- **T6. Unchanged on purpose:** the ±1 magnitude, the evidence rules (35-day titration window, 3 check-ins, 40 %
  soreness; plateau's 63 days / 3 sessions / 28 days / 5 % and its own non-green fatigue rule: the two scans keep their
  different fatigue definitions), the merge (`putIfAbsent`, a -1 wins), the ledger's top / cap / time checks, no
  allowance for titration (`session_allowance_behavioral_test.dart:154`).

## 3. Expected after the rules (re-measured on the build, t404)

- R2 / R5 new non-focus row breaks 0 in every scenario; new 1-set rows 0; a lead lowered only under T2's guard; no day
  both longer and over the time bound; 0 group-weeks over the ceiling; 0 over the raw top(g) with ON > OFF.
- d82 net, flat: ON under-bottom group-weeks <= OFF's and no major group-week at 0 only in ON. T1 refuses some +1s that
  lift a group today, so the margin (214) is re-measured on the build; a sign flip goes to the founder, not into a
  loosened check.
- Reported, not targeted: deltas that found no candidate; declining (plan, group) pairs with no -1 in any week
  (estimate 2,489 of 3,519, of which 2,236 are today's band-bottom refusals).
- The golden hashes do not move: no golden persona passes the opt-ins (`generator_golden_test.dart` and the kill-switch
  goldens, seat A); verified by running them on the build.
- Value-semantics sweep (§4.1.5 (3)): no test seeds `exlog_*` / `readiness_*` and drives an advance caller (seat A
  grep); `supabase/functions/` reads neither key.

## 4. Changes

0. **d81 live-world check.** `goal_training_gate_test.dart` gains a third world: `grid(goals: ['lose_fat',
   'general_fitness'], finisherShown: true)` deletes `disable_cardio_finisher_shown` in a try / finally that restores it
   (the two existing worlds, `_onDigest` and the focus test are untouched; ~1,152 extra generations inside the file's 40
   minutes). It compares Cut with Maintain per key `days|level|tier|minutes|phase` (phases 1-3, 576 pairs, the key
   `identical()` already uses) on every day of every week: each exercise's name, sets, reps, rest, duration, superset
   group and type, plus the day's finisher NAMES, which is t304's comparison exactly (`x` minus the derived groups, and
   `fi` = finisher names). It expects `_identicalLive = {'3|beginner|home_dumbbells|30|1',
   '3|beginner|home_dumbbells|30|2', '3|intermediate|bodyweight|30|2', '3|advanced|bodyweight|30|2',
   '5|advanced|bodyweight|30|2'}` (d63's two plus three); the build runs it once before pinning, and a different set
   goes back to the founder rather than into the constant.
1. `volume_titration.dart`: T1, T2 and T3 inside `_titrateWeekBudgeted` (lead per day per week from the week's own
   budgeted rows; the +1 filter; the -1 candidate order and R2 guard; the per-row stash skip); T4 in `_recovered()`.
2. `plan_engine_flags.dart`: T5.
3. **Harness and gate.** Shared logic moves to `test/plan_generator/plan_audit/history_sim_lib.dart` (history writer,
   readiness writer, the row dump with `openerOf` lead, focus groups and floor excuse, the metric functions); the dump
   test and the gate both use it. `setSwitches` puts / deletes `disable_volume_titration` and
   `disable_plateau_escalation`. Per profile and scenario the call order is: earlier phase, OFF (kill switches set, no
   opt-in), IDENTITY (kill switches unset, no opt-in), KILLED (kill switches set, opted in), ON (unset, opted in), then
   `debugLastStats` read; the focus
   groups are `BudgetMuscleGroups.of(TrainingHistoryAnalyzer.resolveBodyFocus(explicitBodyFocus: const [], phase:
   phase))` after the history is written. Scenarios:
   - **progress, decline, flat** as in section 1.
   - **mixed** (phase 3, 8 weeks like flat): walking the earlier plan's loaded rows in plan order, a compound becomes
     FLAT if one of its credited groups has no flat row yet (a row is marked once; a flat row is never logged
     declining); every other loaded row declines 10 % in its last session. A group with a flat compound and a declining
     row gets a plateau +1 and a titration -1, so `putIfAbsent` must keep the -1 (`logHistory`'s factor callback gains
     the exercise name). Asserts: for every group in both maps, `merged[g] == -1`, AND at least N profiles (measured on
     the build, pinned) have such a group, so the assertion cannot hold vacuously (bodyweight tiers log no load).
   - **sore** (progress base): 3 of 6 check-ins at `soreness 2` (the 40 % rule: `beatUp >= 2 && beatUp >=
     ceil(0.4 x 6) = 3`), so no +1 applies; plus a boundary profile set with 2 of 6 (a +1 applies).
   - **readiness-off** (progress base): 6 green check-ins and `disable_readiness` set: T4 makes ON == OFF (today a +1
     applies).
   - **focus** (progress base): `physique_focus: glutes_legs` in the profile, so the explicit focus replaces
     `weakMuscles()`.
   The CI gate `test/plan_generator/titration_plateau_gate_test.dart` runs progress, decline, flat and mixed over the
   576 profiles and sore, readiness-off and focus over the 192 intermediate profiles: about 2,880 profile-scenarios x
   5 generations ~ 14,400 generations (the dump: 5 min 40 s for 1,728 x 3), under an explicit
   `@Timeout(Duration(minutes: 40))` (goal_training_gate: 40 min for 6,912). Hard zeros on the ON plan's FINAL rows
   (never `debugLastStats`' sets, written before titration, `session_set_allocator.dart:213`): R2 / R5 new non-focus
   row breaks; new 1-set rows; days longer and over the time bound; group-weeks over the ceiling; over the raw top(g)
   with ON > OFF. Identity: the IDENTITY plan's `toMap()` and the KILLED plan's `toMap()` each equal OFF's for every
   profile (IDENTITY proves the opt-ins gate both features; KILLED proves the two kill switches turn them off). Positive pins (so a stricter mutant cannot hide): flat has focus rows that gained a set and sit above
   lead + 1 (48 on main, `focus_pin.py`; progress has 0, so the pin is on flat; the build's count is pinned); decline
   has leads trimmed under the guard (estimated from `t2b_estimate.py`: 516 lead-only trim weeks; pinned on the build); mixed's merge assertion; sore and readiness-off ON == OFF with the boundary set changed.
   The d82 net check and the reported counts as in section 3.
4. **Tests that change** (each expectation re-derived, none loosened; the commit lists which keep their meaning):
   - `test/contracts/session_set_budget_consumers_test.dart:387-715` (~25 hand-built `applyToWeeks` cases; trims at
     :432-446, :462, :489-495, :641-664 change rows under T2; +1 cases where an accessory is first change under T1).
   - `test/contracts/quads_credit_flag_consumers_test.dart:135`.
   - `test/contracts/volume_titration_behavioral_test.dart` (keys :343-391; new T1 / T2 / T3 / T4 tests: a +1 refused
     above the lead, allowed on the lead, focus row exempt, `disable_lead_first` off, the lead read after its own +1;
     T2: most sets first, the cross-day tie, never below 2, the lead taken only under the R2 guard; T3 null stash
     skipped; T4).
   - `test/contracts/plateau_escalation_behavioral_test.dart` (:185, 209, 288, 312, 426) and
     `plateau_rotation_behavioral_test.dart` (:145, 187, 201, 298, 341): `put(enable_*, false)` becomes
     `put(disable_*, true)`; default-OFF assertions become default-ON; the end-to-end merge at :296-345 re-derived.
   - `test/plan_generator/plateau_scan_test.dart` (flag-default cases).
   - `test/contracts/session_allowance_behavioral_test.dart:163-188` (a Chest +1 over a filler row: its bumped /
     refused counts re-derived under T1).
   - After the flip, a grep of `test/` for both getter names and both new keys; plan v2's three guessed files
     (`thin_day_topup_behavioral_test`, `core_list_pool_behavioral_test`, `session_budget_fixtures.dart`) hold neither
     (seats C and D grep).
   - New: a `generateV4`-level test with seeded history, switches default, opts false: the plan equals the no-history
     plan's titration-free output (the opt-in AND; the gate's identity covers it at scale).
   - A stash test: a T2 trim on week 4, then the triggered un-deload restores the trimmed peak.
5. **Records** (a grep of both key strings, both getter names and "DEFAULT OFF" across `lib/`, `docs/`, `test/`,
   `scripts/` decides the list; known now): `docs/sot_registry.yaml` (`volume_titration`, `plateau_escalation`,
   `plateau_rotation`, ~12145-12303: ranges, the kill switches); `docs/ship_dark_pending_review.yaml` (:60-93 and :785:
   both rows resolved with `flip_commit`; the readiness-gap note closed by T4); `docs/naming_conventions.md` (append the two `disable_*` keys, §4.7; the :364 titration row updated);
   plan engine `CLAUDE.md:79,86` rewritten (not only the "not re-capped" sentence in the 2A bullet) and
   `docs/architecture/plan-engine-detail.md:110-111,220,254`; code comments `volume_titration.dart:17-23`,
   `plateau_scan.dart:11-23`, `plan_generator.dart:108,117,363-371`, `plan_engine_flags.dart:343-350,467-477`;
   `docs/audit/gate-input-family.closure.yaml:291` (read, updated if it states the old key as live); OI-53 archived to
   `closed_issues.md` (append only); the 3D-b post-merge stamps (closure HW-* commit 7ed5da70 / merge 85bdcbbe,
   ship_dark `flip_commit`); diagnose doc; closure ledger `docs/audit/generator-step4.closure.yaml`.

## 5. Mutations (each must redden a named test)

| Mutant | Must redden |
|---|---|
| T1 check removed | behavioral T1 test; gate R2 zero |
| T1 lead = slot 0 instead of `openerOf` (fixture: an isolation row ranked before the compound opener) | behavioral T1 opener test |
| T1 lead sets read at the start of the week, not at the moment | behavioral "lead read after its own +1" |
| T1 focus exemption removed | behavioral focus test; gate positive pin (flat: focus +1 above lead + 1) |
| T2 floor `>= 2` instead of `>= 3` | behavioral never-below-2; gate 1-set zero |
| T2 first-match instead of most-sets | behavioral most-sets test |
| T2 cross-day tie earliest instead of latest | behavioral cross-day tie test |
| T2 lead guard removed | behavioral lead-guard test; gate R2 zero (decline) |
| T2 lead guard counting focus rows | behavioral focus-row-at-lead+2 trim test |
| T2 lead never a candidate | gate positive pin (a lead trimmed in decline) |
| T3 null stash counted as 0 | behavioral T3 test |
| T4 removed | behavioral T4 test; gate readiness-off ON == OFF |
| the 40 % rule moved to 2 of 6 | gate sore boundary |
| titration ignores `ledger.fits` on a +1 | gate ceiling zero; consumers top test |
| `applyToWeeks` ignores `leadFirst: false` | behavioral `disable_lead_first` test |
| each default flipped back (2) | flag-default tests |
| the opt-in AND dropped (getter alone) | new `generateV4` opt-in-false test; gate identity |
| merge `putIfAbsent` -> overwrite (+1 wins) | gate mixed assertion; `plateau_escalation_behavioral_test` merge test |
| the d81 set widened by one key | goal-training gate live world |
| harness OFF world reading the retired `enable_*` key | gate identity (OFF would titrate, IDENTITY would not) |

## 6. Board

t401 plan, t402 reviews, t403 build, t404 the history re-run (this harness), t405 review / CI / merge, t406 device check
(a PRO phase advance needs 28 days of history on a device: the founder decides what to look at).

## Results on the build (t404, 2026-11-16)

`titration_plateau_gate_test.dart` (15 min 41 s locally, 3,072 profile-scenarios x 4 worlds + the earlier phase): every
hard zero holds (R2 / R5, 1-set rows, time, the ceiling, raw top with ON > OFF in same-pick weeks); IDENTITY and KILLED
equal OFF for every profile; sore 3 / 6 and readiness-off change nothing.

| | progress | decline | flat | mixed | focus (192) | sore 2 / 6 (192) |
|---|---|---|---|---|---|---|
| plans changed | 126 | 373 | 446 | 434 | 41 | 48 |
| leads trimmed under T2's guard | 0 | 685 | 0 | 343 | 0 | 0 |
| focus rows above lead + 1 that gained | 0 | 0 | 48 | 15 | 0 | 0 |
| under-bottom group-weeks OFF -> ON | 8,942 -> 8,942 | 8,942 -> 8,942 | 9,956 -> 9,830 | 9,939 -> 9,956 | 2,996 -> 2,996 | 3,219 -> 3,219 |

- Mixed: 1,612 groups had a plateau +1 and a titration -1; every one kept the -1.
- Costs (reported to the founder with the step): before T1 the progress scenario's +1s lifted 124 group-weeks over the
  band bottom; with T1 they lift none (those +1s went to rows past the lead + 1). The d82 net on flat shrinks from 214
  to 126 group-weeks. Mixed histories end 17 group-weeks lower at the bottom (trims plus rotation).
- 16 rule mutants each reddened a behavioral test (diagnose `7c4e2a`).

## Review log

- **Round 1 (2026-11-16, two Sonnet seats, plan v1).** Seat A (mechanism, 34 claims, 7 findings): A1 P1 untested
  consumers (section 4 item 4); A2 cross-day tie (T2); A3 declines left untrimmed: measured, T2 changed to d65's order
  with an R2 guard (1,030 vs 881 of 1,283 kept); A4 oracle on final rows; A5 records list; A6 line anchors; A7 over-top
  attribution (section 1, mutation). T1 == R5 confirmed; golden unaffected confirmed; no advance-caller test with
  seeded history. Seat B (measurement and tests, 24 claims, 10 findings): B1 P1 harness keys after the flip; B2 P1 the
  d81 live world did not exist (item 0 specified, the 5 keys named); B3 P1 week-to-variant mapping for the ceiling; B4-B6
  metrics corrected and the table re-run (R2 now per row: decline 184 -> 165, flat 365 -> 386; under-bottom split into
  newly / deeper; time row adds longer days and the max); B7 scenarios mixed / sore / focus added; B8 harness correct;
  B9 mutations added; B10 P1 test list. All 17 folded into v2.
- **Round 2 (2026-11-16, two fresh Sonnet seats, plan v2).** Seat C (rules and code, 34 claims, 5 findings): C1 T2's
  lead guard now uses the T1 / R5 predicate (focus rows exempt, stash on deload); C2 dev-panel toggles; C3 / D11 the
  test list measured, not guessed; C4 the two keys into naming; C5 `applyToWeeks(leadFirst:)`. T1 == R5, opener
  independent of sets, T2 vs d65, T3 and T4 confirmed. Seat D (gate, harness, tests, 41 claims, 13 findings): D1 P1
  every history scenario has `weakMuscles()` focus groups (verified at `training_history_analyzer.dart:176`); D2 P1
  top(g) is the focus top for a focus group; D3 P1 T4 is visible only with green rows and `disable_readiness`
  (readiness-off scenario added; sore pinned at 3 of 6 with a 2-of-6 boundary); D4 mixed rebuilt on one group
  (flat compound + declining rows); D5 / D6 / D7 positive pins, the IDENTITY generation and call order, the opt-in
  test; D8 raw-top check reworded to ON > OFF; D9 the net check defined; D10 item 0's comparison is t304's (finisher
  names); D12 the harness dumps the `openerOf` lead; D13 runtime estimated (~11,500 generations, 40 min). The harness
  was extended (focus groups, lead, floor excuse) and re-run; section 1's table is now in the gate's definitions: the
  61 "over-top" group-weeks were focus tops and floor seats (0 over the ceiling), R2 new days 451 / 149 / 325. All 18
  folded into v3.
- **Round 3 (2026-11-16, one fresh Sonnet seat, plan v3, convergence).** 31 claims, 0 P0 / P1, converged: true. Every
  round-2 fix verified in the text (table definitions, sore boundary arithmetic, mixed's -1 path, `leadFirst`
  implementable). Five P2 / P3 folded into v3.1: E1 the identity proved the opt-in only, so a KILLED generation (opted
  in, kill switches set) must equal OFF; E2 mixed's flat-row choice made explicit plus a non-vacuity pin; E3 the focus
  pin measured (48 on flat, 0 on progress, so the pin moved to flat); E4 phases 2-3 only; E5 a null-stash lead.
