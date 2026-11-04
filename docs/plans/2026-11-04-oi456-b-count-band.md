# OI-456 piece B plan: the 5-8 exercise count band (NOT YET FOR REVIEW)

Status: PARKED DRAFT v3 for piece B. Split from piece A (`2026-11-04-oi456-a-rest-by-type.md`) on
2026-11-04 after three review rounds (6, 6, 4 P1 design holes, all inside the count-band allocator).
CLAUDE.md 4.12.1: reviews that keep finding material issues mean the unit is too large. Piece A ships
first; piece B is re-planned from piece A's MEASURED counts, then reviewed twice. Nothing below is
approved to code. Open founder decision D-A (30-minute sessions) lives here.

### Review findings carried into piece B (do not lose; all must be answered in the re-plan)
- Pass A2 force step needs a ledger predicate that ignores the clock (`fits` fails when secondsLeft < 0,
  `session_budget.dart:539`); order must be pass A, empty-day guard, THEN A2; A2 rank-major then day-major.
- "5-8 on every clean day" contradicts the hard weekly top (6-day beginner, lighter phases 4/8/12): define the
  assertion as 5-8 OR `belowCount` with a cap/top cause; pre-register the founder-escalation threshold.
- At 30 min the clock overrun is universal (beginner 5 slots, typical mix 1486 s > 1440 s window); the gate's
  `limitMin = effMinutes + 2` (`session_set_budget_gate_test.dart:310`) and `explained` branch (`:336-338`)
  need a `countForced` day-index list covering all 4 weeks, 6-day single list, copy days.
- Target-removed slots must not read `cap_limited` in `_label`; `boundBy` after pass B uses `later = null`.
- Dead/equivalent mutants: `hardMax`, unknown-archetype default; missing fixtures: A2 blocked by cap/top, 90-min
  every exercise >= 3 sets, seat target with non-budgeted rows, 5+ non-budgeted rows (target 0).
- Reword "lead lift never displaced" (pass A still drops a lead that misses the clock).
- Product numbers the founder should see: beginner at 90 min = 5 exercises x 3 sets, about 40 of 76 min.

## 1. Problem (measured, not assumed)

A tester's 4-day plan came out Push 4, Pull 6, Legs 4, Upper 9 exercises. Cause, by file:line:

- WRITER of the per-day rest: `split_resolver.dart:10` gives the days `strength, hypertrophy,
  strength, endurance`; `SessionBudget.restFor` (`session_budget.dart:381`) turns that into 150 / 75
  / 38 s for EVERY exercise of the day, and `desiredFor` (`:389`) into 4 / 3 / 2 sets.
- READERS: `session_set_allocator.dart:191` (`dayRest`) and `:209` (`desired`),
  `periodization_engine.dart:158` (week-2 gains), `:83-85` (`_profileParams` stamps the rest on the
  exercise), test mirrors `session_set_allocator_behavioral_test.dart:171,691`,
  `session_budget_test.dart:208-236`.
- The 60-minute clock then fits 4 exercises on a 150 s day and 9 on a 38 s day.

## 2. Founder decisions (all accepted 2026-11-03; unchanged here)

1. Count at 60 min: beginner 5, intermediate 6, advanced 7-8; hard range 5-8 for everyone.
2. Rest by exercise type: heavy compound (archetype H) 150 s, other compound (M) 120 s, isolation (I)
   75 s, timed / calisthenics (B) 60 s. Day intensity changes reps and load only.
3. The 5-8 band holds at 30 / 45 / 60 / 90 minutes; sets flex first; the count never drops below 5.
4. Only main exercises count (not warm-up, cool-down, cardio finisher).
5. The count band beats the weekly set band; the weekly band becomes a soft target.
6. Deload keeps the count and cuts sets, floor 2 sets per exercise.
7. OI-457 (level self-report) parked: no onboarding change. OI-458 (Upper repeats) separate.

## 3. What measuring the clock showed (changes the plan; needs a founder call)

Time model: `1.20 x (overhead + sets x work + (sets-1) x rest)`; day budget = minutes minus
warm/cool (30 min -> 24, 45 -> 37, 60 -> 50, 90 -> 76 minutes of main work). With the new rests,
a typical mix (2 heavy, 2 other compound, rest isolation):

| Day length | 5 ex @2 sets | 6 ex @2 | 8 ex @2 | 5 ex @3 | 6 ex @3 |
|---|---|---|---|---|---|
| 30 min (24 avail) | 26-28 OVER | 30-32 OVER | 39-41 OVER | 41-44 OVER | 47-50 OVER |
| 45 min (37 avail) | 26-28 fits | 30-32 fits | 39-41 OVER | 41-44 OVER | 47-50 OVER |
| 60 min (50 avail) | fits | fits | 39-41 fits | 41-44 fits | 47-50 edge |
| 90 min (76 avail) | fits | fits | fits | fits | fits |

Consequences:
- **C1. At 30 min the floor of 5 exercises at 2 sets does not fit** (26-28 min of work in a 24 min
  window). Decision 3 and the clock conflict.
- **C2. At 60 min an 8-exercise day fits only at 2 sets each; 6 exercises fit at 2-3 sets.** The
  advanced "7-8" therefore means mostly 2 sets per exercise at 60 minutes, which is below the
  advanced weekly band (14-20) once the split is 4 days. Decision 5 already says the count wins.
- **C3. At 45 min, 8 exercises do not fit even at 2 sets** (42 vs 37 min).

**FOUNDER DECISION D-A (open, proceeding on the recommendation):** at 30 minutes the count floor
beats the clock, so a day may SHOW about 28 min of main work. Alternative: floor 4 at 30 min, which
breaks decision 3. Everything below is written for the recommendation; the alternative is one
constant (`minCountAt30`).

Resolutions (precise, per review #1 item 6):
- R2 (the upper end, defined by the algorithm, not a formula): the day's target `n` is the level's
  max (beginner 5, intermediate 6, advanced 8) and the allocator seats slots by rank at 2 sets each,
  GREEDILY, stopping at `n` or when the next slot does not fit the clock. The count is whatever that
  seats, never below the floor. So advanced lands at 7-8 at 60/90 min, 6-7 at 45, 5-6 at 30, because
  that is how many fit. The lower end is never clamped by the clock (R1).
- R1 (the floor, SKIP not SWAP): if fewer than 5 are seated, the allocator keeps walking the
  remaining slots in rank order and seats each one that fits (a cheaper later slot can seat where an
  expensive earlier one did not: that is the only reordering, and it never removes a seated slot).
  The rank-0 lead lift is therefore never displaced. If it is still below 5, it force-seats the
  cheapest remaining slots at 2 sets and the day overruns (counter `countForced` on
  `AllocationStats`, separate from `timeForcedFirst`/`capForcedFirst`, whose gate value stays 0).
  Tests that assert `secondsLeft >= 0` exempt exactly the days listed in `countForced`.

## 4. Design

### 4.1 Lookup tables (SessionBudget, one place)

`SessionBudget.countBand(level) -> ({int target, int max})`: beginner (5,5), intermediate (6,6),
advanced (7,8); unknown level reads intermediate (as `_levelKey` does). `minCount = 5`,
`hardMax = 8`, both constants.

`SessionBudget.restForArchetype(archetype) -> int`: H 150, M 120, I 75, B 60. This REPLACES the
rest column of `restFor(intensity)`. `restFor` is deleted (not kept as a dead overload): its
readers move to the archetype table (writer/reader list in section 1).

`SessionBudget.desiredSets` no longer varies by day intensity: base 3 (the hypertrophy value); the
allocator flexes it. `desiredFor` is replaced by a constant `baseSets = 3`.

### 4.2 Allocator (`session_set_allocator.dart`): v3 = today's pass A, re-parameterised

v3 REMOVES the "soft weekly top" of v2 (review #2 found it unsound: unbounded overshoot, broken
lighter-phase gate, the invariant an earlier guard was reverted for). The weekly TOP and the SESSION
CAP stay HARD everywhere. Decision 5 ("count beats the weekly band") is honoured at the BOTTOM: the
weekly bottom is a soft target that the grow passes chase, and the count never waits for it. If the
sweep (Task 7) shows a clean, non-thin day left under 5 by the hard top, STOP and take the numbers to
the founder; do not add a softening mechanism on our own.

**What counts.** "Main exercise" = every row of the day that is not warm-up, cool-down or finisher,
non-budgeted rows (timed such as Wall Sit, customs) included: they are unremovable, spend time, and
are never sized. Seat target for budgeted slots on a day = `levelMax - nonBudgetedCount`, floor 0,
where `levelMax` = beginner 5, intermediate 6, advanced 8 (`countBand(level).max`; the `target`
field of v1 is dropped). A day never holds more than `hardMax = 8` main rows; a selector day with
more budgeted slots than the target loses the lowest-rank ones (`removed = true`, `why` as today).

**Pass A (seat), same loop as `session_set_allocator.dart:246-290` with three changes:**
1. `k` is fixed at 2 (no `for k = desired..2`): every seat is 2 sets.
2. A slot is seated only while the day's seated count is below its target.
3. Non-budgeted rep-based rows are priced at `restForArchetype(archetypeOfPlanned)` instead of
   `dayRest` (`:197`), so the allocator, `_weekTwoGains` (`:162`) and the `_applyWave` stamp agree.
   A test pins that a rep-based custom is priced and stamped identically in all three.
The rank-0 reservation (`reserved(k)`, `:259-266`) is UNCHANGED and lives in pass A only (it is not
claimed for the grow passes: `grow` calls plain `fits`, as today).

**Pass A2 (floor).** If a day's main-row count (seated + non-budgeted) is below `min(5, slotsAvailable)`
after pass A, walk the day's unseated slots in rank order and seat each that fits (clock, session
cap, weekly top: all hard). Cheaper later slots can seat where an expensive earlier one did not;
a seated slot is never removed and the rank-0 lead lift is never displaced (skip, not swap). If the
day is STILL below the floor only because of the CLOCK, force-seat the cheapest remaining slots that
pass the cap and the top (never a cap or top breach) and record the day in the new
`AllocationStats.countForced`; those days overrun the clock (D-A). If cap or top is what blocks, the
day stays short and is reported in `belowCount` (a new stat), never forced.
`slotsAvailable` = the budgeted slots the selector produced; the floor cannot create slots. A day
with fewer than 5 main rows because the selector/injury/top-up supplied fewer is the named thin-day
exception and stays ratcheted by `kThinCeilings`.

**Pass B (grow to base).** New: rank-major, day-major, +1 set up to `baseSets = 3`, while the hard
`fits` holds. Then passes C (weekly bottom) and D (focus), unchanged, up to `maxSetsPerExercise = 5`.

**`desired`, `boundBy`, `firstLifts`, `why` (defined, because pass A no longer loops over `desired`):**
`_Slot.desired = baseSets (3)` for every slot and day. `boundBy` for the lead lift is computed AFTER
pass B: when `lead.sets < desired`, the first group whose cap/top/reservation refuses +1 (the existing
`_firstBlockingGroup(ledger, d, s, 1, later)`), else null (time). `why` flags of a removed slot are
computed as today (`_whyFlags` at 2 sets). `firstLifts` and the gate's `capForcedFirst == 0` keep
their meaning; `timeForcedFirst` still counts the empty-day guard only.

**Empty-day guard** stays exactly as is.
**Variant B / copy days:** a day whose B list equals A's copies A's seats and is never regrown, so it
inherits A's count; the proof asserts 5-8 on A and B for non-copy days and equality on copy days.
**Lighter phases:** weekly top = band bottom (`session_budget.dart:510-512`). Seating at 2 sets may
then leave a group unable to seat; the hard top wins, the day may fall short, and the sweep reports
it. Stated consequence: a deload week cannot go below about 2 sets x the day's count, so for 30-45
minute users the week-4 volume cut is small (the load/rep cut carries the deload).

### 4.3 Periodization (`periodization_engine.dart`)

- Rest: `_profileParams` loses its rest column. `_applyWave` stamps
  `restForArchetype(archetypeOf(ex))` on a rep-based exercise (a timed row keeps its own rest).
  Reps still follow the day intensity (strength 5 / hypertrophy 10 / endurance 18).
- `_weekTwoGains` runs on `populated` BEFORE rests are stamped (`ex.restSeconds` is still the selector
  default `default_rest_secs ?? 60`, `exercise_selector.dart:1438,1761`), so it MUST price like the
  allocator: for a budgeted row or a rep-based custom, `restForArchetype(archetypeOfPlanned(ex,
  budget))`; for a timed row, its own rest. Pin: week-2 gains equal an independent re-price of week 1
  with archetype rests (a mutant reading `ex.restSeconds` must redden it).
- Deload (week 4): `min(ex.sets, max(2, floor(0.6 x ex.sets)))`, so a 1-set custom is not RAISED.
  Accepted consequence, stated: a 2-set exercise keeps 2, 3 and 4 become 2, 5 becomes 3; most 5-8
  exercise days therefore see a small set cut, and the load/rep cut (`_waveReps` x0.8) carries the
  deload. The cue "fewer sets" (`_waveCues[3]`) stays true for 3+ sets; Task 8 adds a test that every
  deload exercise has sets <= its week-1 sets and the day keeps its count.
- Titration (`VolumeTitration._titrateWeekBudgeted`, `volume_titration.dart:192,221`) reads the STAMPED
  `restSeconds`, which is archetype-based after this task: NO change there (do not add a branch).

### 4.4 Wiring (`plan_generator.dart`, waiver)

Review #1 grepped `lib/`, `test/`, `supabase/functions/`: `plan_generator.dart` has NO call to
`restFor`/`desiredFor`, so the file is NOT touched and the rule-14 waiver is unused (recorded in the
plan-review record). If implementation finds a call site, stop and re-plan.

### 4.5 Display and divergence

Train / Home / coach `shortenDay` price stored rest through `exerciseSeconds` and pick up the new
rests with no change. Known divergence: a swapped or added exercise keeps the library's
`default_rest_secs` (swap_service / templates), not the type table, so its estimate differs after a
swap. This is an explicit task (Task 12: mint an OI with `scripts/mint_oi.sh` and decide there), not
a silent gap.

## 5. Tasks

1. Value-semantics sweep (4.1.5.3) of `restFor`, `desiredFor`, `_profileParams`, intensity-keyed rest
   in `lib/`, `test/`, `supabase/functions/`, docs, `docs/sot_registry.yaml` (line ranges shift) and
   nested CLAUDE.md. Record the list in the diagnose-doc.
2. `session_budget.dart`: `countBand(level).max` (5/6/8), `minCount = 5`, `hardMax = 8`, `restForArchetype` (unknown ->
   60, like `exerciseSeconds` treats unknown as B), `baseSets = 3`; delete `restFor`/`desiredFor`;
   (no new ledger method: the weekly top stays hard).
3. `session_set_allocator.dart`: pass A re-parameterised, A2, B, the `desired`/`boundBy` definitions, non-budgeted rest, `countForced` and `belowCount` in `AllocationStats`.
4. `periodization_engine.dart`: rest by archetype, `_weekTwoGains` fix, deload rule.
5. Repoint every test that pins the old numbers (REPOINT, never loosen). Allocator behavioral test:
   `desired` 3/4 at lines 71, 124, 147 (`first.desired == 4` on a strength day), 282, 757; the rest
   mirrors `:171,691`; the block near 150-180 (`[('chest',4),('back',3),('delts',3)]`; "strength day
   holds fewer sets than hypertrophy" becomes "day intensity changes neither sets nor rest"); the
   rank-0 reservation tests at 92-147; every `f.day('strength', ...)` fixture. `session_budget_test.dart:208-236`;
   `session_set_budget_gate_test.dart` (:330-345 `explained` branch gains `countForced`/`belowCount`,
   :353-357 weekly-top/lighter-phase check stays HARD and unchanged, :372, :385-387 caps unchanged,
   time checks exempt exactly the `countForced` days); `session_set_budget_consumers_test.dart`
   (:175-186, :281, :492 hand-priced rest 75/30); `session_set_budget_wiring_test.dart:109-110`;
   `session_estimate_display_test.dart:13-15` (verify only); `shared_contracts_test.dart:642,850`;
   `strength_archetype_test.dart:50-51`, `hypertrophy_archetype_test.dart:31-32` (deload set cut);
   `thin_day_topup_behavioral_test.dart:324,345,371,425,443`; `physique_focus_bringup_test.dart:85`;
   helpers `test/helpers/session_budget_fixtures.dart`, `test/plan_engine_v4/_helpers.dart` (rest 75).
6. Regenerate `test/fixtures/generator_golden_hashes.json` (a regeneration: every hash moves, so the
   file proves nothing; review step = a before/after table of per-hash day counts, sets and rests,
   every count in 5-8 or a named thin day), `session_set_budget_report.md`, `kThinCeilings`
   (`injury_floor_sweep_lib.dart:252-273`, re-measure and ratchet), `scorecard_gate_test.dart` pins that move.
7. New proof `test/contracts/exercise_count_band_behavioral_test.dart`: sweep level (3) x minutes
   (30/45/60/90) x days (3-6) x goals x weeks 1-4 x variants A/B x lighter phases. Asserts:
   (a) main rows 5-8 on clean days, thin days ratcheted; upper bounds beginner <= 5, intermediate <= 6
   and advanced >= 7 at 60/90 on a clean day; (b) STORED `restSeconds` of every rep-based exercise,
   every week, equals `restForArchetype(archetype)`; (c) deload sets equal EXACTLY
   `min(s, max(2, floor(.6 s)))` per exercise and the day keeps its count; (d) no group exceeds its
   weekly top (lighter phase: the bottom), no group exceeds its session cap, EXCEPT none: both stay
   hard; (e) `countForced` days only at short sessions and only over the CLOCK; (f) copy days equal;
   (g) a fixture with an expensive earlier slot and a cheaper later one (R1 skip keeps the lead lift);
   (h) an empty-day fixture; (i) a fixture whose non-budgeted rows push a day toward 9 rows
   (`hardMax`); (j) a rep-based custom priced and stamped identically in allocator, week-2 gains and
   `apply`. The tester case (intermediate, basic_gym, 4 days, 55 kg, build_muscle): all four days 5-8.
8. Mutation proofs (rule 21), each confirmed applied with `grep -c`: floor removed; floor 4 and 6;
   level max +1 (beginner 6, intermediate 7); hardMax 9 (killable only via fixture (i)); deload floor
   1 and 3; H/M rest swap; unknown-archetype default; clamp on the LOWER end; `_weekTwoGains` reading
   `ex.restSeconds`; `restFor(intensity)` restored; skip replaced by swap; empty-day guard removed;
   pass A2 forcing past the cap or top; pass B removed. Record reddened counts in the diagnose-doc.
9. Docs: `plan-engine-detail.md:334` ("Rest by day intensity: strength 150...") rewritten, plan_engine `CLAUDE.md` ("Session set budget" bullet, "Exercise count per day" paragraph and
   the sentence "lead lift is protected ... not from the clock" kept true), `plan-engine-detail.md`,
   SoT entry (with `behavioral_test_path`), registry ranges recomputed from anchors.
10. Diagnose-doc `docs/diagnoses/2026-11-04-exercise-count-band-<id>.md` (full template), prior
    instances from `docs/diagnoses/INDEX.md` in `related_bugs:`.
11. Full gate loop (whole-project `flutter analyze --no-fatal-infos`, `TZ=Asia/Kolkata flutter test`,
    pre-commit loop), then B-pass `/code-review`, then `land_pr.sh`.
12. Mint the OI for the swap/add rest divergence (4.5).

## 6. Out of scope (named, not deferred)

- OI-454 (Quads floor): not started; it re-measures on top of this batch (founder order, 2026-11-03).
- OI-457 (level safeguard): onboarding change, parked by the founder.
- OI-458 (Upper repeats Push/Pull accessories): its own OI.
- Anything that edits onboarding, the `sessionDuration` question, or cloud data (no migration; the
  plan is regenerated locally and backed up in `user_progress.plan_json`).

## 7. Risks the reviewers should attack

- C1 / R1: swapping slots can drop a lead lift; the lead-lift protection rules (week and empty day)
  must still hold.
- The hard weekly top may leave a clean day under 5 (esp. lighter phases); the sweep must report how
  often, and a non-thin shortfall goes to the founder with numbers.
- Existing plans on tester devices are not regenerated; only new generations and phase advances move.
- `generator_golden_test` / scorecard pins on exercise counts.
