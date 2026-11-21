# Generator Unit 2D: a repeat phase with more minutes (OI-453)

Status: v4, 2026-11-15 (after review round 3, §5; built, §3 has the measurements). Written on main 0c383703 (2C-b merged, PR #279). Board step 2 (s2),
card t216. Execution mode: inline (§4.12.7), one worktree `generator-step2d`, one PR.

## 0. Scope and founder basis

- **The defect (OI-453, closure row `SBF-REPEAT-PHASE-MINUTES`).**
  - A repeat phase pins the previous phase's exercise list (`generateV4(pinnedExercisesByDay:)` →
    `ExerciseSelector.buildPinnedDays`).
  - When the user's session minutes go up between phases, the allocator grows the pinned rows, but it can never add an
    exercise. Past its own growth targets the extra time goes unused.
- **The founder's design (2026-11-03, OI-453, hybrid).** Keep the pinned compounds. When minutes rise, spend the spare
  time first on extra sets, then on accessories appended from the normal selector. Do not reshuffle the whole list.
- **What "sets first" means here (round 2, A-1; stated for the founder in the diagnose doc).**
  - The allocator's growth passes stop a row at the base sets (3), then at the weekly band's bottom (pass C) or the focus
    top (pass D). Above that they add no sets at any minutes, because more sets than the weekly target is over-volume.
    A FRESH plan at the new minutes spends its extra time the same way: the same set targets, then more rows.
  - So 2D gives the pins every set the allocator would give them at the new minutes, and keeps week 2's +1 set on every
    pinned row that had it without accessories (S5's reserve). Only the time left after both goes to accessories.
  - It does not grow a pinned row past the allocator's weekly targets. That would change the volume model, not the
    repeat.
- **d50 (2026-11-15), the rule-14 waiver: ONE optional pass-through argument.**
  - `repeatMinutesRose` on `generateV4` and on the `generate()` facade that `generateAndSchedule` calls
    (`plan_generator.dart:44`, which re-lists every parameter).
  - Forwarded to `buildPinnedDays` (`plan_generator.dart:192`).
  - That is one argument at its two signatures and its two forwards; nothing else in the file changes.
- **Done when (OI-453).**
  - The plan is reviewed twice.
  - A repeat with more minutes fills the extra time as above, and a repeat with the same minutes stays byte-identical
    to today.
  - The pins survive with their sets.
  - The repeat gate still tests adherence.
  - Mutants prove both branches.
  - Blast radius `platform`, tier L.
- **Out of scope.**
  - Fewer minutes (the allocator already trims).
  - A fresh phase.
  - The 2B / 2C kill switches (OI-506 / OI-509, after the device checks).
  - OI-496's arm swap (founder d51, its own unit after this one).

## 1. Writers and readers

| Concept | Writer | Reader |
|---|---|---|
| `last_phase_profile` (user-scoped) | `generateAndSchedule` `workout_schedule_read_service.dart:259` (gains `session_minutes`) | `_buildRepeatPins` `:758`; NEW: `generateAndSchedule` reads the OLD map before `generate()` |
| plan rows a repeat pins | `generateAndSchedule` (`:223`); `generateAndScheduleFromDate` `:373` (Edit Profile's reschedule, rows from today only); coach `regenerate_plan` (`regenerate_plan_planner.dart:217`, rows from today, no profile write) | `_buildRepeatPins` → `repeatPinsFrom` `:886` (weeks 1-2) |
| repeat pins | `_buildRepeatPins` (callers `autoGenerateNextPhaseIfNeeded` `:676`, `buildRepeatPinsForAdvance` `:861` → `pro_phase_advance.dart:858`) | `generate` `plan_generator.dart:44` → `generateV4` `:191` → `buildPinnedDays` `exercise_selector.dart:366` |
| minutes rose | NEW pure static `repeatMinutesRose(stored, now)`, called inside `generateAndSchedule` | `generate(repeatMinutesRose:)` → `generateV4` → `buildPinnedDays(appendAccessories:)` |
| accessory candidates | NEW, in `buildPinnedDays` → `PopulatedDay.repeatAccessoriesA/B`; carried by `topUpDays` (`:627`) | `SessionSetAllocator.allocate`'s new wrapper step |
| appended-row count | NEW, the wrapper step → `PopulatedDay.appendedA/B` | `PeriodizationEngine._weekTwoGains` (visits appended rows last) |

## 2. Design (v3)

**S1. The minutes the rows were built at.**
- `generateAndSchedule` adds `'session_minutes': <resolved minutes>` to `last_phase_profile`. That is the same
  `SessionBudget.resolveMinutes(param: sessionDuration, profileValue: sessionMinutesFromProfile())` that `generateV4`
  budgets with (`plan_generator.dart:169`). The write stays under `adherenceGateEnabled`, like the existing one.
- `generateAndScheduleFromDate` is NOT patched (round 2, B-1): a mid-phase reschedule rewrites only rows from today.
  The rows the next repeat pins (weeks 1-2) mostly keep the old minutes, so the old stored value is the truthful one.
- Two writers leave the stored value different from the minutes of some pinned rows: a reschedule (rows from today
  only) and the coach's `regenerate_plan`.
  - Stored OLDER than the rows (a reschedule early in week 1 at more minutes): `rose` reads true for rows already built
    at the new minutes. Benign: such rows leave little plain budget, so the step appends little or nothing.
  - Stored NEWER than the rows (round 3, F5): 60 stored, a reschedule to 30, then the advance at 45. `rose` reads false
    (45 < 60) although the pinned rows were built at 30, so that repeat gets no accessory. Rare, and the miss only
    keeps today's behaviour. Named in the diagnose doc.
  - A patch in the reschedule would make the first, common case (raise in Edit Profile, then repeat) miss instead.
- A profile with no `session_minutes` (every profile written before 2D) reads as "not raised".

**S2. The decision, inside `generateAndSchedule` (round 2, B-3).**
- Before `generate()`, while the OLD `last_phase_profile` is still stored, `generateAndSchedule` computes
  `rose = pinnedExercisesByDay != null && repeatMinutesRose(oldProfile, minutes)`.
- `repeatMinutesRose(Map? stored, int nowMinutes)` is a new pure static, true only when `stored?['session_minutes']` is
  an `int` and `nowMinutes > it`.
- No caller changes, no new parameter on `generateAndSchedule`, no new method on the read service.
  - `repeatPinsFrom`, `_buildRepeatPins` and `buildRepeatPinsForAdvance` keep their signatures.
  - `advance_choice_test.dart:145`'s source pin stays valid.
- Both advance paths resolve the same minutes: the auto path passes the profile minutes, and the graduation path passes
  none and resolves the profile.

**S3. `plan_generator.dart` (d50).**
- `generate({..., bool repeatMinutesRose = false})` forwards to `generateV4({..., bool repeatMinutesRose = false})`.
- `generateV4` passes `appendAccessories: repeatMinutesRose` to `buildPinnedDays` at `:192`. That call is reached only
  inside the pins branch.

**S4. The candidates, in `buildPinnedDays` (rounds 1 and 2).** With `appendAccessories` true, each frame and variant gets
a candidate list from that frame's `fresh()` pick (`exercisesA` for A, `exercisesB` for B).
- **Call order (A-9).** `fresh()` is memoized (`freshCache`, `:443`). The candidate step calls it after the existing
  empty-variant fills (`:463-478`) and before `feederNamesA/B.addAll` (`:482`). The memo then holds exactly the pick
  today's fill would use. On the 6-day path B is A and B's candidates are not computed.
- **A row qualifies when all of these hold.**
  - It is budgeted: `SessionBudget.isBudgeted(row, ctx)`, a library row matched by `archetypeByName`. That excludes
    customs, timed, cardio and distance rows.
  - `exerciseType == 'isolation'`: an accessory, never a second compound.
  - No pinned row of that variant-day holds its (movement pattern, first primary muscle). `PlannedExercise` has no
    pattern, so the pinned row's pattern comes from `exerciseRepo.getByExactName`. A custom pin has no row and
    excludes nothing.
  - Its name is held by no pinned row of that variant on ANY day, by no earlier candidate, and by no `SameMovement`
    partner of either (lower-cased on both sides).
- **SameMovement lookup (B-6 / A-5, round 3 F3).** One lazy `SameMovement` per `buildPinnedDays` call, built by a new
  `_sameMovementOf(repo)` helper that the thin-day top-up now uses too. The `.getAll()` text moves into the helper,
  so `exercise_selector.dart` keeps its 8 counted seam sites (`scripts/exercise_seam_lib.dart:72`).
- **The final screen (A-4, round 3 F3).** After the thin-day top-up, `_dropHeldCandidates` drops a candidate whose
  name or a same-movement partner is a row of its variant on ANY day (a fresh-filled or topped-up row the per-frame
  screen could not see yet). So the allocator needs no partner data.
- **Order.** Frame slot order.
- **Storage.** The candidates go in new `PopulatedDay.repeatAccessoriesA` / `repeatAccessoriesB` fields (default
  `const []`), never in `exercisesA/B`. So the thin-day top-up, every allocator pass, the floor, 2C-b and the 2A worlds
  never see them.
- **Top-up and feeders.**
  - `topUpDays` carries both fields when it rebuilds a thin day (`:627`). It runs only for injured users (`:553`), so
    the test uses an injured thin-day fixture.
  - Candidates do NOT feed `feederNamesA/B`.

**S5. The step: a wrapper over `allocate` (round 2, A-2 / B-7).**
- The current `allocate` body becomes `_allocateCore`, unchanged. Both of its branches run there: the kill-switch path
  that returns at `:283`, and `_allocateLeadFirst` (`:575`).
- `allocate` calls it, then, when any INPUT day holds candidates, runs `_appendRepeatAccessories(input, output, ...)`.
- With no candidates, `allocate` returns `_allocateCore`'s result as the same object, so it is byte-identical.

The step:
1. **The plain ledger, per variant (A-7).** It builds `BudgetLedger(ctx, n)` WITHOUT the allowance (d44) from the
   allocated output.
   - It prices each row exactly as `_weekTwoGains` does (`periodization_engine.dart:174-196`): a budgeted row and a
     rep-based custom at their archetype's rest, a timed row at its own.
   - It credits groups with `BudgetMuscleGroups.creditedOf(primaryMuscles, quadPrimaryCreditsGlutes:)`.
   - Rows the allocator evicted are absent from the output, so they cost nothing. The allowance, forced rows and floor
     or minimum overruns only make `secondsLeft` negative, so nothing is appended.
   - That is stricter than "the allowance never buys an exercise": a stamped day appends only past its whole unspent
     allowance (stated).
   - A test pins that the rebuilt `secondsLeft` per day equals the allocator's own end-of-variant ledger, with a timed
     hold, a rep-based custom and an evicted hold.
2. **The week-2 reserve (round 2, B-5).** Week 2 reads B (A on the 6-day path). For that variant only, the step first
   adds to the ledger the gains that `PeriodizationEngine._weekTwoGains` would grant the output without accessories,
   with `capToLead` = the lead-first value `allocate` resolved once (`leadFirst ?? flag`, round 3 F6; production reads
   the same flag in `apply`). Every fit check carries a 1e-6 margin, since the week-2 pass sums the same seconds in
   another order (round 3, F7).
   - The function is made package-visible as `PeriodizationEngine.weekTwoGains`, same body.
   - Each reserved gain adds its +1 set and its seconds.
   - Candidates are then seated against what is left.
3. **Seating.** Candidates are walked rank-major across days (rank 0 of every day, then rank 1). One is seated at 2 sets
   when all of these hold:
   - `ledger.fits(d, groups, 2, seconds(2))`, which checks the plain day budget, the session cap and the weekly top;
   - the day's rows (budgeted or not) are below `min(SessionBudget.countMax(level), hardMax)`;
   - its lower-cased name is held by no row of that variant's OUTPUT on any day, nor by an earlier seat. Partners
     were already screened in the selector against every input row; every allocator output row is an input row (the
     walk, the floor and the minimum only reorder, seat or swap input rows), so a name check here is enough;
   - with the lead-first rule on and no focus group credited, its sets stay at most the day's lead (`openerOf` over
     the output's budgeted rows) + 1 (d26 / d27).

   Seated rows then grow to the base sets (3) by the same checks.
4. **B (A-3, round 3 F2).** Each variant is seated on its own ledger from its own candidates; a B day that copies A in
   the allocator (its B candidates are A's, since B aliases A in the selector) is seated in B's walk against B's
   ledger, which holds the week-2 reserve and B's other days. So a copied day can hold a different accessory in A and
   B when B's week is tighter, but no seat ever skips a fit check (copying A's seats verbatim could pass B's weekly
   top and take a pinned row's week-2 gain). On the 6-day path B is A: one walk, the same list object.
5. **Output.**
   - Seated rows are appended after the day's rows in `exercisesA/B`. `PopulatedDay.appendedA/B` records how many
     trailing rows were appended.
   - Every other field of the core's day is copied, `allowance` included (round 3, F4: `_weekTwoGains` reads it), and
     the 6-day alias `identical(exercisesA, exercisesB)` is kept.
   - The candidate fields are not carried out of `allocate`.
   - `AllocationStats.repeatAccessorySeats[d]` records the seats. Copied B days inherit them.
   - `weekly`, `credited`, `belowFloor`, `firstLifts` and `leadSeats` describe the allocation before the step. The new
     gate recomputes weekly sets from the plan, never from these stats (A-10).
6. **Week 2, in `PeriodizationEngine._weekTwoGains`.**
   - The trailing `appended` rows of a day are kept out of `ranked` and out of the day's lead (`openerOf` sees only the
     other rows: round 3, F1, else an appended isolation could become the lead of an isolation-only or custom-only day
     and cap a pinned row), and are visited after every other row: after the ranked rows and the not-budgeted ones.
   - Every reserved gain still fits, because the ledger only grew by what step 2 already allowed for. So each pinned
     row's week-2 sets equal the run without accessories. A test pins this.
7. **Sequencing.** Stage 3 builds `[...compounds, ...isolations]`, so an appended isolation never sorts ahead of a
   pinned compound.
   - On a day whose pins are all isolations or customs, the opener follows `_cnsDemand`.
   - Test 9 asserts the actual opener there (A-8).

**S6. Byte-identical where nothing changed.**
- A fresh phase: pins null, so `appendAccessories` is never read.
- A same-minutes repeat, or a legacy profile: `rose` is false, so there are no candidates.
- With no candidates, `allocate` returns `_allocateCore`'s object and `appended` is 0, so `_weekTwoGains` visits rows
  as today.
- The golden's two pinned personas (`generator_golden_personas.dart:190-199`) prove the flag-false `buildPinnedDays`
  path. A `generate()`-level test covers the facade forward.

**S7. No new kill switch** (d37). The step is reached only through a repeat, and `disable_adherence_gate` already
turns repeats off.

**S8. Known limits, stated.**
- Stage 0 (progression, `plan_generator.dart:208-216`) reads `exercisesA/B` before the allocation. So an appended
  accessory gets no history-based starting weight and starts like a new exercise. Fixing that is a second
  `plan_generator.dart` edit that d50 does not cover.
- A build_muscle 3-5-day repeat that crosses 60 minutes changes split family (`SplitResolver.balancedWeekApplies`,
  `split_resolver.dart:410-416`). `repeatPinsFrom` then drops the foreign-named rows (`foreignDayNamesFor`, `:768`), so
  that repeat runs FRESH at the new minutes, as it does today. 2D never reaches it, and the user gets a whole new plan
  at the new minutes.

## 3. Tests, measurements and runtime

As built (v4). The fast files run in seconds; the gate runs 768 personas x 3 generations.

- **`test/contracts/repeat_minutes_behavioral_test.dart`** (16 tests, crafted `Fx` fixtures):
  - time left: seated at 2 then grown to 3 after the pins, pins' sets unchanged, the stats record;
  - no candidates: same result on both 2A paths; the step runs on the lead-first-off path;
  - no time left: nothing;
  - the count max, the weekly top, a same-name row on another day;
  - rank-major order;
  - the lead cap, the focus exemption (d27), lead-first off;
  - a custom or timed candidate is never seated;
  - the rebuilt plain ledger prices a timed hold at its own rest and a rep-based custom at its archetype rest
    (round 4, F4);
  - the plain budget: a candidate the allowance would fit is refused, and seated once the time is back (d44);
  - 6-day alias; non-6-day B from its own candidates; every field kept, the allowance stamp included;
  - week 2 through `PeriodizationEngine.apply` at 45 / 60 / 90 minutes: pinned week-2 sets unchanged with five
    candidates (the reserve);
  - an appended row is never the week-2 lead (a custom-only day keeps its gain).
- **`test/contracts/repeat_accessory_candidates_test.dart`** (9 tests, the real library):
  - `repeatCandidatesFor`: compound, (pattern, first muscle), pinned name, timed and custom refusals; the
    same-movement partner (Dumbbell Glute Bridge vs Glute Bridge, different patterns); `taken`; one per day;
  - `buildPinnedDays`: flag off leaves the fields empty; flag on leaves the days identical, holds candidates, and no
    candidate is a row of its variant on any day;
  - the final screen, directly (A and B held sets kept apart) and at its call site (pins on day 0 only, so days 1-2
    fresh-fill);
  - `topUpDays` carries the fields on a rebuilt (thin, injured) day.
- **`test/core/repeat_minutes_profile_test.dart`** (7 tests):
  - `repeatMinutesRose`: absent, null, equal, lower, higher, 0, a double, a String;
  - through the real `generateAndSchedule` and the production pin path (`buildRepeatPinsForAdvance`): the resolved
    minutes are stored; 30 -> 60 appends accessories and then stores 60; 30 -> 30 appends nothing; a pre-2D profile
    appends nothing.
  - `runGraduationPhaseAdvance` and `autoGenerateNextPhaseIfNeeded` are not run separately: the decision lives in
    their shared callee `generateAndSchedule` (S2), and neither caller changed.
- **`test/plan_generator/repeat_minutes_gate_test.dart`** (16 tests, one per (pair, tier)):
  - pins derived the production way, through `repeatPinsFrom` with `foreignDayNamesFor`;
  - asserted for every measured persona, all four weeks:
    - every flag-off row is in the flag-on plan with the same sets and reps;
    - extras are library isolations, no duplicate in a day;
    - weeks 1 / 3 and 2 / 4 hold the same extras;
    - weeks 1 and 2 (round 4, F3): no day above the count max; main work within the plain budget (week 2 adds the
      allowance under 60, since week 2's +1 sets follow it like every row's) whenever the flag-off day was;
    - no group an extra credits past its session cap or weekly top where the flag-off plan was not (budgeted rows
      only, as the ledger counts);
    - no extra repeats another row of its week, nor a same-movement partner of one.
  - Zero failures on the first run. Measured and pinned exactly (personas, fresh, measured, gained, extra rows and sets
    in weeks 1-2, extra week-1 seconds):

| pair | bodyweight | home_dumbbells | basic_gym | full_gym |
|---|---|---|---|---|
| 30 -> 45 | 48 / 0 / 48 / 41, 128 rows, 358 sets | 48 / 0 / 48 / 33, 119, 336 | 48 / 0 / 48 / 25, 75, 220 | 48 / 0 / 48 / 30, 84, 250 |
| 30 -> 60 | 48 / 7 / 41 / 41, 350, 997 | 48 / 7 / 41 / 41, 305, 920 | 48 / 7 / 41 / 41, 263, 711 | 48 / 7 / 41 / 41, 254, 716 |
| 45 -> 60 | 48 / 7 / 41 / 8, 22, 44 | 48 / 7 / 41 / 7, 14, 36 | 48 / 7 / 41 / 2, 4, 8 | 48 / 7 / 41 / 3, 6, 12 |
| 60 -> 90 | 48 / 0 / 48 / 4, 8, 28 | 48 / 0 / 48 / 6, 10, 33 | 48 / 0 / 48 / 1, 1, 2 | 48 / 0 / 48 / 2, 2, 5 |

  - The 7 fresh personas per tier crossing 60 are the build_muscle 3-5-day non-beginner splits (S8) plus one more.
  - Reach is large from 30 minutes, where the allocator's row cap and set targets leave most of a raise unused, and
    small at 45 -> 60 and 60 -> 90, where the allocator already grows rows to their targets and the level's count is
    nearly reached.
- **Pre-2D profiles** have no `session_minutes`, so their first repeat after the release gets no accessory. The app is
  pre-launch with testers only, so this is stated, not migrated.
- **Mutants:**
  - `>` → `>=`, and absent → true, in `repeatMinutesRose`;
  - reading the profile after the write;
  - each qualifying check in S4;
  - the `fresh()` call order;
  - the topUpDays carry;
  - each S5 guard: plain budget versus the allowance, count, cap, top, the output-duplicate check;
  - the week-2 reserve removed;
  - appended rows visited in rank order in `_weekTwoGains`;
  - rank-major versus day-major;
  - the B copy predicate on the output instead of the input;
  - the copied-seats-first order;
  - the wrapper placed inside `_allocateLeadFirst` only (red on `leadFirst: false`);
  - dropped forwards at `generate()`, `generateV4` and `generateAndSchedule`.
- **Docs and registry (round 2, B-8):**
  - the SoT registry entry for `last_phase_profile` / repeat pins (`docs/sot_registry.yaml`): the new key, the new
    reader, the shifted line ranges recomputed from anchors, and `behavioral_test_path:`;
  - `plan_engine/CLAUDE.md` and `plan-engine-detail.md`;
  - `naming_conventions.md`: `repeatAccessories`, `appended`, `repeatMinutesRose`;
  - the diagnose doc with the mutation table;
  - a closure ledger.

## 4. Risks

- **R1.** A candidate duplicates a pinned movement under another name. Excluded by name, by SameMovement and by
  (pattern, first muscle). A different isolation of the same muscle is allowed: that is the founder's "accessory".
- **R2.** The candidate fields are lost between `buildPinnedDays` and `allocate`. The only rebuild is `topUpDays`
  (`:627`), and a test pins it. Stage 0 only reads.
- **R3.** Stale stored minutes (S1). Older than the rows: benign. Newer than the rows (a down-then-up reschedule): that
  repeat gets no accessory, today's behaviour.
- **R4.** The append takes week 2's +1. Prevented by the reserve and the visit order (S5.2, S5.6), and pinned by test 13
  and the gate's week-2 assert.

## 5. Review log

- **Round 1 (v1, two Sonnet seats, read-only): not converged.** 21 findings (A: 2 P1, 7 P2, 1 P3; B: 5 P1, 6 P2, 1 P3).
  - The core of A-1 to A-5 and B-11: v1 ran the extras INSIDE the allocator's passes as marked slots, which collided
    with holds, custom-only days, the opener, the 2A world choice, the 2C-b re-runs, the count verdict and the top-up.
    v2 moved the mechanism after the allocation.
  - The rest: B-1 / A-8 (a reschedule patch, reversed in round 2), B-3 / A-7 (the `generate()` forward), B-4 / A-6 (the
    pin API stays), B-5 / B-6 (lower bound and reference), B-7 (the golden claim), B-8 (harness), B-10 (test rows),
    B-12 (measurements), A-9 (sets first) and A-10 (rank-major).
- **Round 2 (v2, two fresh Sonnet seats, read-only): no P0; 3 P1, 10 P2, 6 P3. All taken into v3.**
  - **Seat A.**
    - A-1 (P1), "sets first" is not literal: §0 now states it.
    - A-2, the step must cover both allocator branches: the S5 wrapper.
    - A-3, the B copy predicate on the input, and copied seats first: S5.4.
    - A-4, a duplicate of a top-up row or a minimum seat: S5.3.
    - A-5, lookups and the seam gate: S4.
    - A-6, crossing-60 cells: §3 and S8.
    - A-7, the ledger inputs: S5.1, test 12.
    - A-8, the opener: S5.7, test 9.
    - A-9, `fresh()` order: S4.
    - A-10, stale stats: S5.5.
    - A-11, the line slip (:192).
  - **Seat B.**
    - B-1 (P1), the reschedule patch stores minutes the pinned rows were not built at: dropped (S1, R3).
    - B-2, coach regen is a second rewriter: §1 and S1.
    - B-3, `rose` inside `generateAndSchedule`: S2.
    - B-4 (P1), unreachable gate cells: §3.
    - B-5 (P1), week-2 gains displaced: the reserve and the visit order (S5.2, S5.6; R4).
    - B-6, the seam gate: S4.
    - B-7, two return sites: S5.
    - B-8, docs and SoT: §3.
    - B-9, runtime timing: §3.
    - B-10, test shapes: the injured top-up fixture, the stored-key control, identity.

- **Round 3 (v3, one fresh Sonnet seat, read-only, code at HEAD): not converged; 2 P1, 4 P2, 2 P3. All taken into
  v4.**
  - F1 (P1), an appended row could become the week-2 lead: S5.6 keeps appended rows out of the lead.
  - F2 (P1), copied B-day seats skipped B's fit checks: S5.4, every variant seated on its own ledger.
  - F3, SameMovement reach and the allocator's partner data: S4 helper and the final screen; S5.3 name check.
  - F4, the allowance stamp and the alias: S5.5.
  - F5, R3 can go the other way: S1, R3.
  - F6, one `capToLead`: S5.2.
  - F7, summation order: the 1e-6 margin.
  - F8, the variant label on copied seats: moot (no copy).
  - Round 4 runs on the built diff after the full gate loop (§4.12.5).

## 6. Open questions

None. d50 covers the pass-through, the design is the founder's (OI-453), and §0 states how "sets first" is met.
