# OI-456 piece B plan: the exercise count band (v6, post reviews #1 and #2, for review #3)

Status: v6 (v4 plus review #1: 2 P1 + 6 P2; v5 plus review #2: 1 P1 + 6 P2; all folded in, section 7), re-planned on 2026-11-04 AFTER piece A landed (PR #210) and after founder decision D-A
("option 2"). Supersedes the parked v3. Execution mode: INLINE (one worktree `oi456-b-count-band`, one
writer), decided at batch start per CLAUDE.md 4.12.7. Nothing here is approved to code until review #2.

## 0. What is already on main (piece A) and is NOT redone here

- `SessionBudget.restForArchetype` (H150 M120 I75 B60, unknown 60), `SessionBudget.baseSets = 3` on every day,
  deload `min(sets, max(2, floor(0.6 x sets)))`, swap rest from the incoming exercise, `_weekTwoGains` priced
  by archetype. `restFor`/`desiredFor` are gone. `plan_generator.dart` is NOT touched (rule 14 holds).
- Pass A in `session_set_allocator.dart` (`_variant`, lines ~252-301) still loops `k = desired(3)..2`, so a slot
  that fits at 3 sets takes 3. That is why 30 min holds 3 exercises, 45 min 4-5, 90 min 6-9.

## 1. Founder decisions (all accepted)

1. Count at 60 min: beginner 5, intermediate 6, advanced 7-8; hard range 5-8.
2. The band holds at 30/45/60/90 minutes, sets flex first. **D-A (2026-11-04): at 30 minutes the floor is 4,
   not 5**; the session stays inside its minutes. 45/60/90 keep floor 5.
3. Only main exercises count (not warm-up, cool-down, cardio finisher). Non-budgeted rows (timed, customs)
   count as main rows and are never sized.
4. The count band beats the weekly SET band at the bottom only. The weekly TOP and the session CAP stay HARD
   (a soft top was tried in v2 and removed: unbounded overshoot).
5. Deload keeps the count (piece A rule, already live). OI-457 parked, OI-458 separate, OI-454 after this.

## 2. Measured baseline (piece A report, `test/plan_generator/rest_by_type_report.md`)

| case | counts per day, week 1 |
|---|---|
| intermediate 4d basic_gym, 60 | 6 6 7 6 |
| same, 30 min | 3 3 3 3 |
| same, 45 min | 4 5 5 5 |
| same, 90 min | 7 6 8 9 (spread 3) |
| beginner 4d, 60 | 5 5 5 4 |
| advanced 4d, 60 | 6 6 7 6 |

Gaps to close: 30 min (3 -> 4+), 45 min (4 -> 5+), 90 min (9 -> <= 8 and spread), beginner 60 (4 -> 5), advanced
60 (6 -> 7-8 where the clock allows).

Clock facts: day budget = (minutes - warmCool) x 60 = 24 / 37 / 50 / 76 min of main work at 30/45/60/90. A typical
exercise at 2 sets costs 4.3 min (isolation) to 5.6 min (compound), 6.3 min (heavy). Four at 2 sets: 17-25 min,
so 4 usually fits 24 and 4 heavy lifts can overrun by about 1 min. Five at 2 sets: 21-28 min, fits 37+.

## 3. Design (allocator only; periodization, swap, wiring unchanged)

### 3.1 Tables (`session_budget.dart`, one place)
- `countMax(level)`: beginner 5, intermediate 6, advanced 8 (unknown level reads intermediate, as `_levelKey`).
- `countFloor(minutes)` (review #2 P1-1: no cliff, defined over the WHOLE 15-180 range, `minMinutes`/`maxMinutes`
  at `session_budget.dart:29-30`): `minutes >= 45 ? 5 : minutes >= 25 ? 4 : 3`. At 31-44 min the floor is 4 (budget
  25-36 min, 4 at 2 sets costs 17-25 min, so no forcing); at 45 the budget is 37 min and 5 at 2 sets costs 21-28,
  so no forcing either; the floor step never lands on a clock cliff. 30 min = 4 is D-A. `hardMax = 8`.
- `maxForcedOverSeconds = 300`: the force step may leave a day at most 5 minutes over its budget in total.
- No new ledger method. `baseSets` stays 3 and `desired` stays 3 for every slot.

### 3.2 Allocator `_variant`
**Seat target.** For a day: `target = min(countMax(level) - nonBudgetedCount, budgeted slots)`, floor 0, and
the day never exceeds `hardMax` main rows. Budgeted slots beyond the target are removed lowest rank first
(`removed = true`, `why` computed as today at 2 sets).

**Pass A (seat at 2).** Same rank-major, day-major loop, but `k` is fixed at 2 (no `desired..2` descent) and a
slot seats only while the day's seated count < target. The rank-0 reservation `reserved(k)` and the hard
`ledger.fits` (clock, session cap, weekly top) are unchanged.

**Pass A2 (floor: force step only).** Pass A already skips a slot that does not fit and carries on to later
ranks, and the ledger only grows, so a second non-forced walk would be dead code (review #2 P2-2: deleted).
If a day's main rows (seated + non-budgeted) < `floorEff(d)` after pass A and the empty-day guard, the force step
below runs; a seated slot is never removed and the lead lift is never displaced. If still below the floor and only the CLOCK blocks, force-seat the cheapest
remaining slots at 2 sets (cheapest first, ties by rank), never past a cap or a weekly top, and only while
the day's total overrun stays <= `maxForcedOverSeconds` (a slot that would break the bound is not forced and
the day is recorded in `belowCount` with cause `clock`). Each forced day is recorded in new
`AllocationStats.countForced`, a `Map<int, List<({String name, int sets})>>` (day -> the forced slots), so the gate
can subtract the real seconds of those named exercises in every week (review #2 P2-3). If a cap or top
blocks, the day stays short and is recorded in new `AllocationStats.belowCount`, never forced.
Order of passes: A, empty-day guard (unchanged), A2, B, C, D. The empty-day guard keeps `timeForcedFirst` /
`capForcedFirst` semantics.

**The force predicate (review #1 P1-1).** `ledger.fits` opens with `addSeconds > secondsLeft(day)`
(`session_budget.dart:538`), and `secondsLeft` is NEGATIVE on a day that non-budgeted rows or the guard already
overspent, so `fits(..., 0)` is false exactly where forcing is needed. No ledger method is added. A2's force step
uses a hand-written local `canForce(s)`: for every group `g` of the slot, `ledger.week(g) + 2 <= ledger.weeklyTop(g)`
and `ledger.session(d, g) + 2 <= ledger.cap(g)`, nothing about time (the same shape as `room()` at ~line 306
plus the session-cap test). The NON-forced A2 walk keeps plain `fits` (clock respected). A mutant that uses
`fits(...)` for the force step must redden a fixture whose day starts with negative `secondsLeft`.

**Copy days and both lists (review #2 P2-4).** A day can be in `forcedDays` (guard) AND `countForced`; the gate and
the `:714` exemption subtract both. Variant B copies A's `countForced` entries for its copy days (it copies A's
seats, forced ones included), so weeks 2-4 and the B variant pass the `time` check.

**Only `allocateDays` (review #1 P2-3).** Target, A2, B and the stats iterate `allocateDays`; a copied day
(variant B) keeps A's seats, so a copied day that is below its floor in A is inherited and counted in
`belowCount` of EACH variant's own stats (A and B are separate `AllocationStats`), never fixed in B.

**Pass B (grow to base).** New: rank-major, day-major, +1 set per slot up to `baseSets` while the hard `fits`
holds. Passes C (weekly bottom) and D (focus) are unchanged (up to `maxSetsPerExercise` 5). Because sets flex
AFTER the count is fixed, a long session ends with every exercise at 3 sets and a short one at 2.

**`boundBy` / `firstLifts` / `why`.** `later` is built inside the rank loop (~lines 262-276), so it is STORED per
rank-0 slot (`_Slot.later`, a `Map<String,int>?`) and `boundBy` after pass B calls
`_firstBlockingGroup(ledger, d, s, 1, null)` when `lead.sets < desired`, else null (time) (review #2 P2-6: after
pass B every later day's lead is already in the ledger, so re-applying the reservation `later` would double-count
them; `later` therefore is NOT stored and the post-B check passes null; fixture: time alone stops the lead and
`boundBy` is null). A target-removed slot is never refused for time/cap/top: new `_Why.target` with `why = {}` (no
flags; the earlier 'computed as today' wording is dropped). `_label` skips it when it is not the only reason; a group
whose crediting slots are ALL target-removed gets label `count_limited` instead of falling to `cap_limited`
(`_Why` is private to the allocator file; no other switch exists). `firstLifts` and the gate's `capForcedFirst == 0` keep their meaning.

**Copy days (variant B).** A day whose B list equals A's copies A's seats and is never regrown: it inherits A's
count. **6-day single list:** B is A.

### 3.3 Known limits, stated now
- **Definitions (review #1 P2-4).** Per variant, per allocated day `d`: `rows(d)` = admitted budgeted + all
  non-budgeted rows; `reach(d)` = `slotsSeen[d] + nonBudgeted(d)`; `floorEff(d) = min(countFloor(minutes), reach(d))`.
  `belowCount` lists days with `rows(d) < floorEff(d)` (cap/top caused it; each entry carries the blocking cause).
  `selectorThin` lists days with `reach(d) < countFloor(minutes)` (the selector/injury/top-up supplied too few):
  these are the thin days, still ratcheted by `kThinCeilings` (which counts days under 3 and is re-measured,
  not redefined). If `nonBudgeted(d) >= countMax`, target is 0, the empty-day guard may still force ONE lift, so
  main rows can reach `countMax + 1` (<= `hardMax` only when countMax < 8): this is a named exception in the
  proof's upper-bound assertion, listed by day, never silent.
- Lighter phases (weekly top = band bottom): the hard top may keep a day under the floor; it is reported in
  `belowCount`. If a CLEAN non-thin day lands under its floor because of the hard top, STOP and take the
  numbers to the founder; do not add a softening mechanism.
- Existing plans on tester devices are not regenerated; only new generations and phase advances move.
- Seat-at-2 then grow: accessories at 2 sets can take weekly top before pass B grows the lead lift in lighter
  phases, so a lead may end at 2 (its `boundBy` says why). Target removal is lowest rank first and not
  group-aware; Task 5 asserts `belowFloor` does not worsen against the piece A baseline per sweep block, else STOP.
  A beginner session cap (6, `session_budget.dart:~423`) can hold a lower-body day under the floor: those days are
  `belowCount`, an allowed exception in assertion (a), never forced past the cap.
- Beginner at 90 min: 5 exercises x 3 sets is about 40 of 76 minutes (count max wins over the clock; stated).

## 4. Tasks
1. Value-semantics sweep (4.1.5.3), command `git grep -nE "\\.length|toHaveLength|exercises\\.length|desired|baseSets" -- test lib supabase/functions docs` narrowed by file list above: every literal that pins an exercise COUNT or a set count produced by pass A
   (`desired` 3, seat-at-3), in `lib/`, `test/`, `supabase/functions/`, docs, `docs/sot_registry.yaml`, nested
   CLAUDE.md. List recorded in the diagnose-doc.
2. `session_budget.dart`: `countMax`, `countFloor`, `hardMax`.
3. `session_set_allocator.dart`: target, pass A at 2, A2, B, `boundBy`, `countForced`, `belowCount`.
4. Repoint tests that pin old counts (REPOINT, never loosen). **Gate rule (review #1 P1-2):** the gate is
   `test/plan_generator/session_set_budget_gate_test.dart` (not `test/contracts/`). `countForced` days are a
   SEPARATE list from `forcedDays` (the empty-day guard's, whose `explained` rule at :333-345 keeps meaning
   'day minus the lead lift is inside the limit'). New rule: a day in `countForced` is explained when `mins - sum(exSeconds of the NAMED forced exercises)/60
   - (guard lead's exSeconds/60 if the day is also in `forcedDays`) <= limitMin`, AND the overrun over the user's
   minutes <= `maxForcedOverSeconds/60 + 2`; recorded in `_agg` like `timeForcedOver`; every other day keeps the
   hard limit.
   The same list exempts `secondsLeft(d) >= -1e-6` at `session_set_allocator_behavioral_test.dart:~714` for
   exactly those days. Weekly top and caps stay hard. D-A's 'stays inside its minutes' is true except these
   named days; the report lists them. Tests to repoint, found by review #1's grep (Task 1 reruns it): allocator
   behavioral test (:74, :714), `rest_by_type_behavioral_test` (:150, :242, :419-427 pin [6,6,7,6], [3,3,3,3],
   [6,6,7,6,6,7]), `plan_generator_test`, `regression_logic_test`, `test/plan_engine_v4/shared_contracts_test.dart`,
   `thin_day_topup_behavioral_test`, `plateau_rotation_behavioral_test`, `session_set_budget_wiring_test`,
   `core_list_pool_gate_test`, `v4_diagnostic_test`, `bodyweight_capability_leak_test`,
   `equipment_exclusion_filter_behavioral_test`, `active_workout_set_logging_behavioral_test`, `sets_count_3rd_fallback_test`,
   `docs/sot_registry.yaml:~17041,~17112`, `session_set_budget_report.md`, `rest_by_type_report.md`,
   `sample_plans_output.md`, `baseline_scorecard.json`, `test/fixtures/generator_golden_hashes.json` (path verified); consumers/wiring/estimate/thin-day/physique-focus/archetype tests, `rest_by_type_behavioral_test`
   expectations, `kThinCeilings` re-measured, `generator_golden_hashes.json` regenerated with a before/after
   table of per-hash counts (every count in band or a named thin day), `session_set_budget_report.md`.
5. New proof `test/contracts/exercise_count_band_behavioral_test.dart`, sweep level (3) x minutes (30/45/60/90) x
   days (3-6) x goals x weeks 1-4 x variants A/B x lighter phases; minutes also swept at 15, 20, 25, 31, 35, 44, 120, 180
   (bound and floor hold across the whole range, review #2 P1-1): (a) main rows within `[countFloor, countMax]`
   on clean days, thin days ratcheted; (b) upper bound by level (beginner <= 5, intermediate <= 6, all <= 8);
   (c) deload keeps the count; (d) no group over its weekly top or session cap; (e) forcing bounded: every `countForced` day's overrun <= `maxForcedOverSeconds`; `countForced` only at
   short sessions and only over the clock; (f) copy days equal; (g) expensive-earlier / cheaper-later fixture
   (skip keeps the lead lift); (h) empty-day fixture; (i) non-budgeted rows push a day toward 9 (`hardMax`);
   (j) the tester case (intermediate, basic_gym, 4 days, 55 kg, build_muscle) at 30/45/60/90. Regenerate the
   measured report `rest_by_type_report.md` and assert all cells.
6. Mutation proofs (rule 21), each confirmed applied; state which fixture kills each (review #1 P2-6): 'pass A back
   to desired..2' is killed ONLY by exact-count cells and a fixture where seat-at-3 starves the 4th slot (it may be
   equivalent at 45/60 min; if the measured run shows zero red, label it equivalent with that evidence); 'skip
   replaced by swap' is DROPPED (the walk it mutated is deleted); instead 'force order cheapest-first -> rank order'
   is killed by a fixture with an expensive rank-3 and a cheap rank-5 slot (fewer forced seconds, so the bound holds
   only cheapest-first); 'force bound removed' by a 15-minute fixture; 'A2
   forces past cap/top' by a full-top-group fixture; 'force uses fits' by the negative-secondsLeft fixture; floor removed; floor off by one (3/4/5/6); level max +1;
   `hardMax` 9; `countFloor` 30-min branch removed; skip replaced by swap; A2 forcing past a cap or top; A2 not
   forcing at all; pass B removed; pass A back to `desired..2`; target ignores non-budgeted rows; empty-day
   guard removed. Reddened counts into the diagnose-doc.
7. Docs: plan_engine `CLAUDE.md` ("Exercise count per day" paragraph and the "Session set budget" bullet),
   `plan-engine-detail.md`, SoT `session_set_budget` entry (+ `behavioral_test_path`), registry ranges
   recomputed from anchors. Diagnose-doc `docs/diagnoses/2026-11-04-exercise-count-band-<id>.md` (full template;
   `related_bugs:` from `docs/diagnoses/INDEX.md`, including piece A d3b7f1).
8. Full gate loop (whole-project `flutter analyze --no-fatal-infos`, `TZ=Asia/Kolkata flutter test`, pre-commit),
   then B-pass `/code-review`, then `land_pr.sh`, then retire the worktree, then OI-456 can close.

## 7. Review #1 record (v4 -> v5)
P1-1 force predicate (section 3.2), P1-2 gate path and countForced rule (Task 4); P2-1 `later` stored and `_Why.target`;
P2-2 A2 draws weekly top that no rank logic protects (accepted, stated) and pass B can consume room pass C needs in
lighter phases (Task 5 reruns the report and asserts `belowFloor` does not worsen against the piece A baseline, else
STOP and re-plan B before C); P2-3 allocateDays only; P2-4 definitions; P2-5 test list; P2-6 fixtures. No finding disputed.

Review #2 (v5 -> v6): P1-1 floor defined over the whole range plus the forcing bound; P2-2 dead walk deleted; P2-3
`countForced` is a map to named slots; P2-4 both lists, copy days; P2-5 `count_limited`; P2-6 post-B `boundBy` passes
null; P2-7 stated risks, `belowCount` exception, negative-secondsLeft fixture with 4 heavy lifts at 30 min. Findings per
round: 2 P1 -> 1 P1 (decreasing, each a definition not a new mechanism); review #3 is run on v6 (piece A took 4 rounds).

Review #3 (v6, CONVERGED, 0 P0/P1, 6 P2 folded at build time): (a) the allocator test 'reservation never needed' (:99,
lead ends at 5) flips intent because forced seats now eat the weekly top that lead growth used to get: repoint it and
name that in the diagnose-doc; (b) A2 walks RANK-MAJOR then day-major, cheapest-first within a rank, and a forced
slot resets `removed = false` and `why = {}`; (c) `docs/naming_conventions.md:~281` ('five reasons') and the
`belowFloor` doc comment (`session_set_allocator.dart:~31-34`) gain the sixth label `count_limited` (Task 7);
(d) Task 5's 'belowFloor does not worsen' check EXCLUDES groups labelled `count_limited` (cutting a 9th exercise at 90
minutes raises belowFloor by design, decision 4); (e) `hardMax` is ENFORCED in the target (`target <= hardMax -
nonBudgeted` and a guard lead may add one only inside the named exception), fixture (i) kills 'hardMax 9'; (f) the
'skip replaced by swap' mutant is deleted from Task 6's list. Floor 4 at 25-29 minutes follows the step function (not a
founder-stated value; flagged to the founder in the report).

## 5. Out of scope (named)
OI-454 (Quads), OI-457 (level self-report), OI-458 (Upper repeats), onboarding, `sessionDuration` question, cloud
data (no migration; plans regenerate locally and back up in `user_progress.plan_json`).

## 6. Risks for reviewers to attack
- A2 skip order vs the rank-0 reservation and the empty-day guard; the force predicate ignoring the clock only.
- The hard weekly top leaving a clean day under its floor (lighter phases, 6-day beginners).
- Seating at 2 then growing changes WHICH exercises survive on tight days versus today's seat-at-3: cheaper
  late slots now seat; check lead-lift protection and the focus passes.
- Golden/scorecard pins on counts; sweep runtime (pre-push sweep ~53 min).
