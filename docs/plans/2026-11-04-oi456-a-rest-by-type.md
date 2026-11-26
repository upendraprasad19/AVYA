# OI-456 piece A plan: rest by exercise type, the same base sets every day

Status: v5, ready to build. Review rounds on piece A: A#1 (2 P1), A#2 (3 P1), A#3 (2 P1), A#4 (1 P1 + fixture-precision P2/P3, NO design finding; the reviewer's verdict was "not converged" on the P1, which v5 folds in). Mechanism and counts confirmed independently by A#1, A#2, A#3. The ≥platform B-pass is the remaining backstop. Tier: L (plan engine). Execution mode: inline, one worktree
(`exercise-count-band`), decided at batch start (CLAUDE.md 4.12.7). Rule 14: `plan_generator.dart`
is NOT touched (it has no call to `restFor`/`desiredFor`; verified by grep in an earlier review);
the OI-456 waiver is unused.

Piece B (the 5-8 count band, the 30-minute question, the floor pass) is parked in
`2026-11-04-oi456-b-count-band.md` with the review findings it must answer. It is re-planned from
the counts piece A measures. Piece A removes the INTENSITY-DRIVEN cause of the 4/6/4/9 skew (it narrows the spread; it does not
guarantee 5-8); whether a 5-8 band
still needs enforcing is then a measured question, not a guess.

## 1. Problem and cause (writers and readers by file:line)

A tester's 4-day plan got Push 4, Pull 6, Legs 4, Upper 9 exercises. The rest and base sets of every
exercise of a day come from the DAY'S INTENSITY:

- Source of the intensity: the literals in `_get4DayV4` (`split_resolver.dart:581-647`: strength,
  hypertrophy, strength, endurance); `_profiles4` (`:10`) feeds only the V3 path, same values.
- WRITER of rest/sets by intensity: `SessionBudget.restFor` (`session_budget.dart:381`: 150 / 75 / 38)
  and `SessionBudget.desiredFor` (`:389`: 4 / 3 / 2).
- READERS: `session_set_allocator.dart:191` (`dayRest`), `:197` (non-budgeted rep-based custom priced
  at `dayRest`), `:209` (`desired`); `periodization_engine.dart:158` (`_weekTwoGains` prices at
  `dayRest`), `:83-85` and `:262` (`_profileParams` rest stamped by `_applyWave`); test mirrors
  `session_set_allocator_behavioral_test.dart:171,691`, `session_budget_test.dart:208-236`.
- Effect: on a 60-minute clock a 150 s / 4-set day fits 4 exercises, a 38 s / 2-set day fits 9.
- Estimate for the NEW scheme (review A#1's time model, which reproduces the OLD scheme as 4/7/4/9 against
  the observed 4/6/4/9): every 4-day build_muscle day has 9 selector slots (3 compound + 6 isolation, Legs
  2 + 7). Time-only fill, 3 sets, archetype rest: 60 min lands 6/6/6/6 (all compounds heavy) to 7/6/7/6
  (all other-compound); 45 min lands 4/4/4/4 to 5/4/5/5; 30 min 3; 90 min 9 (slot ceiling). So the
  spread falls from 5 to about 1, but 30-45 min days stay under 5 (piece B) and the weekly tops and
  session caps (shoulders/triceps/biceps are credited on several days) may still remove 1-2 late
  accessories: UNMEASURED, measured in Task 5(f).

## 2. Founder decisions that apply to piece A (accepted 2026-11-03)

- Rest by exercise type: heavy compound (archetype H) 150 s, other compound (M) 120 s, isolation (I)
  75 s, timed / calisthenics (B) 60 s. Day intensity changes reps and load only.
- Deload keeps the count and cuts sets, floor 2 sets per exercise.
- Rule-14 waiver: unused (see above). OI-457 and OI-458 are not touched.

## 3. Design

### 3.1 `session_budget.dart`

- New `restForArchetype(String archetype) -> int`: H 150, M 120, I 75, B 60; any other value 60
  (`exerciseSeconds` already treats an unknown archetype as B).
- DELETE `restFor`. Replace `desiredFor` with `static const int baseSets = 3` (the old hypertrophy
  value): every day, every intensity.
- The comment block "Day intensity" (`:374-376`) is rewritten: the intensity no longer sets rest or
  sets; the engine's `_profileParams` keeps only the reps column.

### 3.2 `session_set_allocator.dart` (no algorithm change; two inputs change)

- `:191` `dayRest` is deleted. A budgeted slot's rest is `restForArchetype(arch)` (`_Slot.rest`,
  `:209` argument); copy days and `_label` already read `s.rest`.
- `:197` a not-budgeted REP-BASED row (a custom) is priced at
  `restForArchetype(archetypeOfPlanned(ex, ctx))`; a timed row keeps `ex.restSeconds`.
- `:209` `desired = SessionBudget.baseSets`. `firstLifts.desired`, `boundBy`, `why` are computed by
  the existing code (pass A still loops `k = desired..2`), so their definitions do not change.
- Pass A, empty-day guard, passes C and D, the rank-0 reservation, weekly top, session cap: UNCHANGED.

### 3.3 `periodization_engine.dart`

- `_profileParams` keeps reps only (`strength 5 / hypertrophy 10 / endurance 18`); the rest column and
  the `baseRest` read at `:85` are removed.
- `_applyWave` takes the RESOLVED rest as an int (computed once in `apply` as
  `restForArchetype(archetypeOfPlanned(ex, budget))`; the `workingReps` stash call at `:111` uses only
  `.reps`, so the rest argument there is plumbing, not behaviour) and stamps it on a rep-based row (a
  non-rep-based row is untouched, as today).
- `_weekTwoGains` (`:147-208`) runs on `populated` BEFORE rests are stamped, so `ex.restSeconds` is
  still the selector default (`default_rest_secs ?? 60`, `exercise_selector.dart:1438,1761`). It prices
  a budgeted row and a rep-based custom at `restForArchetype(archetypeOfPlanned(ex, budget))` (the same
  value the allocator used) and a timed row at its own `ex.restSeconds`.
- Deload (week 4, `:97`): `min(ex.sets, max(2, floor(0.6 x ex.sets)))`, so a 1-set row is never RAISED.
  Stated consequence: a 2-set exercise keeps 2; 3 and 4 become 2; 5 becomes 3. `workingSets: ex.sets`
  (the stash, `:115`) is unchanged.
- Accepted edge (review A#1 item 12): a budgeted row whose logging type is neither rep-based nor
  timed/cardio/distance gets the archetype rest in the allocator but `_applyWave` stamps nothing on it
  (`:222`); this mismatch exists today with `dayRest` and is left as is.
- Titration (`volume_titration.dart:192,221,226`) reads the STAMPED rest, which is archetype-based
  after this change: no code change. Its trim floor stays 1 (decision 6's floor of 2 is the deload's);
  recorded so no reviewer reads it as an omission.

### 3.3b `swap_service.dart` (in this batch: this change creates the defect)

Today every exercise of a day carries the same stamped rest, so `swap_service.dart:529-530`
(`original['rest_seconds'] ?? newLib['default_rest_secs'] ?? 60`; the swapped-in exercise inherits the
OUTGOING slot's rest) is consistent. After piece A a swap across archetypes would keep the wrong
type's rest (isolation into a heavy slot keeps 150 s; the reverse keeps 75 s).

Fix, using the RESOLVED value (the one stored on the replacement and read later by
`estimateDaySecondsFromPlanDay`), not the raw library field:
1. Compute `resolved` = the replacement's `logging_type` exactly as `:518-524` builds it
   (`LoggingTypeResolver.resolve(...) ?? original['logging_type'] ?? 'weight_reps'`), once, before the
   map literal, and use it for both `'logging_type'` and the rest.
2. If `SessionBudget.isRepBased(resolved)`: `rest_seconds =
   restForArchetype(SessionBudget.archetypeOfRow({...newLib, 'logging_type': resolved}))`. Otherwise
   (timed / cardio / distance) keep today's expression `original['rest_seconds'] ??
   newLib['default_rest_secs'] ?? 60`.
3. Custom swap targets: the replacement stores `exercise_type` but no `rep_range` (`:534-541`), so for a
   custom target `archetypeOfPlanDayExercise` later falls to `archetypeOfRow(e)` with a null lower bound
   and an H custom ESTIMATES as M while its stored rest is 150. Decision: store `rep_range` from `newLib`
   on the replacement when present (one added line), so the stored rest and the later estimate use the
   same archetype; the test below covers a custom target.

Regression test (new harness, because no test calls `swapExerciseInDay`; model it on
`session_estimate_display_test.dart:439-451` for Hive + `SwapService` and
`swap_counters_behavioral_test.dart` for the write service): library rows in `exerciseBox` with
`exercise_type`, `rep_range`, `logging_type`; a `schedule_<date>` row; null equipment capability.
Cases: heavy compound -> isolation and back (stored rest follows the INCOMING archetype and
`estimateDaySecondsFromPlanDay` moves accordingly); a custom target with a heavy `rep_range`; a timed
incoming row keeps `original['rest_seconds'] ?? default ?? 60`. Also cover `exercise_type` as a List and as a String (both `_typesOf` branches). Note the intended
mismatch: for a LIBRARY target the later estimate (`session_estimate.dart:37-55`) reads the library
row's own `logging_type`/`rep_range`, which differs from `resolved` only when the row has no
`logging_type`; the rule then falls to the non-rep-based branch, which is the safe side. The "swap
keeps the outgoing rest" and
"archetype rest applied to timed rows" mutants must each redden it.
Left alone, with the reason in the diagnose-doc (not an OI): `swap_sheets.dart:18,166-181` builds an
IN-MEMORY active-workout row (`activeWorkoutProvider.swapExercise`) from the rest the user just typed
into the custom-exercise form, falling back to the original slot's rest; it is the user's own value
and never a generated-plan writer and `template_service.dart:340` (user-built templates,
rest absent only). The coach `swapExercise.ts` tool and `WorkoutScheduleService.swapExerciseInDay` both
delegate to this one site; no other copier of the outgoing rest exists.

### 3.4 What this does NOT do (piece B)

No per-level exercise count, no floor, no cap on rows, no new allocator pass, no `countForced`, no
change to how a 30-minute session fits. A 30-minute day can still hold fewer than 5 exercises.

## 4. Tasks

1. Value-semantics sweep (4.1.5.3) of the STORED rest and the old helpers: `restFor`, `desiredFor`,
   `_profileParams`, literals 150 / 75 / 38 near `rest`, in `lib/`, `test/`, `supabase/functions/`
   (the ai-proxy prompt snapshot builder), docs, `docs/sot_registry.yaml`, nested CLAUDE.md, plus the
   readers of the stored `rest_seconds`: active-workout rest timer, `swap_service`,
   `template_service`, coach `shortenDay`, `estimateDaySecondsFromPlanDay`. Add `session_estimate.dart:91` and
   `sync_workout.dart:2176,2740` (pass the value through untouched) to the list. Record the list in the
   diagnose-doc. Commit hygiene: OI-456 stays OPEN, so no `closes-oi:` trailer on these commits; the
   commits are `fix(...)`, so each carries `closes-diagnose:`; the plan-review record carries
   `bpass: accepted` and a `verdict: accepted` line in any cited file. Divergence FIXED by Task 10: `swap_service.dart:529-530` keeps the OUTGOING
   slot's stamped rest (`original['rest_seconds'] ?? library default ?? 60`), so after this change an
   isolation swapped into a heavy-compound slot keeps 150 s and the reverse keeps 75 s; only
   `swap_sheets.dart:166-180` (live session) and `template_service.dart:340` (no rest present) adopt the
   library default.
2. Code changes of section 3.
3. Repoint (never loosen) every test that pins old numbers: `session_set_allocator_behavioral_test.dart`
   (`desired` at 71, 124, 147 [`first.desired == 4` on a strength day], 282, 757; rest mirrors 171,
   691; the 150-180 block `[('chest',4),('back',3),('delts',3)]` and "strength day holds fewer sets
   than hypertrophy", which becomes "day intensity changes neither sets nor rest"; the rank-0
   reservation tests 92-147; every `f.day('strength', ...)` fixture), `session_budget_test.dart:208-236`
   (the mirror group becomes "restForArchetype agrees with the engine stamp"),
   `session_set_budget_gate_test.dart`, `session_set_budget_consumers_test.dart` (hand-priced rest
   75/30 at 175-186, 281, 492; AND the old deload formula: `:89` `[2,2,1]` -> `[2,2,2]`, `:142` `[1,3]` ->
   `[2,3]`, `:155-166` title "week 4 keeps a one-set exercise at one" `[1,1]` with the comment
   "floor(0.6 x 2) = 1" -> `[1,2]`, and the six-day assertion after `:142` `[2,1]` -> `[2,2]`), `session_set_budget_wiring_test.dart:109-110`,
   `session_estimate_display_test.dart:13-15` (verify only), `shared_contracts_test.dart:642,850`,
   `strength_archetype_test.dart:50-51`, `hypertrophy_archetype_test.dart:31-32`,
   `thin_day_topup_behavioral_test.dart:324,345,371,425,443`, `physique_focus_bringup_test.dart:85`,
   helpers `test/helpers/session_budget_fixtures.dart` and `test/plan_engine_v4/_helpers.dart`; also
   `deload_working_base_stash_behavioral_test.dart:104-110` (verify, expect unchanged: base 3 -> deload 2
   keeps `workingSets > sets`), `generator_golden_test.dart`, `plan_generator_test.dart:100,142,202,401` (hand-set `restSeconds: 150`; check whether `:202` reads a
   generated or a hand-built value),
   `volume_titration_behavioral_test.dart:41` and `plateau_escalation_behavioral_test.dart:45` (hand-set
   rest priced via `e.restSeconds`: re-run). `scorecard_gate_test` and `core_list_pool_gate_test` read
   only picks and a count > 0: unaffected, said so in the record.
4. Regenerate `test/fixtures/generator_golden_hashes.json` (every hash moves; review step = a
   before/after table of day counts, sets and rests per persona) and
   `session_set_budget_report.md`; re-measure `kThinCeilings` (`injury_floor_sweep_lib.dart:252-285`). The ratchet only accepts a LOWER
   count: if rest-by-type RAISES a thin-day count (isolation rest 38 -> 75 s on former endurance days),
   raising a ceiling is a RECORDED decision in the diagnose-doc with the before/after numbers, never a
   silent re-measure.
5. New proof `test/contracts/rest_by_type_behavioral_test.dart`:
   (a) (the expected rest is derived INDEPENDENTLY of the engine: from the fixture's `exercise_type` and
       `rep_range` against the literal table H 150 / M 120 / I 75 / B 60, or, in the real-library sweep,
       from `archetypeOfRow` plus the table, never from `archetypeOfPlanned`) stored `restSeconds` of every BUDGETED rep-based exercise in `exercises`, every week, A and B,
       equals `restForArchetype(archetype)`; exempt a timed row (keeps its own), a rep-based custom is
       included, and warm-up / cool-down / cardio-finisher items (`restSeconds: 0`,
       `warmup_cooldown.dart:320,337`, `cardio_finisher.dart:261`) and the budgeted-but-not-rep-based
       edge of 3.3 are exempt;
   (b) INVARIANCE (ample minutes, e.g. 90, so a time-bound fixture cannot hide an intensity-keyed
       `desired`; `grow()` and the rank-0 reservation depend on day order, so identical lists alone do
       not guarantee identical sets): one exercise per muscle group per day, each group's week total
       after pass A strictly between the band bottom and top so `grow` adds nothing; assert every slot
       holds exactly `baseSets` (non-vacuity) and no `grow` set was added; then the four days
       (strength / hypertrophy / strength / endurance, identical lists) are identical in (name, sets,
       rest) in the ALLOCATOR output and in week 1 (and week 3) of `apply` ONLY: week 2 is excluded
       because `_weekTwoGains` (`periodization_engine.dart:147-208`) grants +1 set rank-major in DAY order
       up to each group's weekly top, so identical days legitimately differ there. Pin goal and level
       to strength (or lose_fat) at intermediate, band (10, 14): one single-group exercise per day at 3
       sets gives 12 a week per group, inside the band and under the top (build_muscle intermediate
       (12,16) gives 12 = bottom, beginner (10,12) = top, advanced (14,20) is below bottom so `grow`
       would add sets); every fixture row names exactly ONE primary muscle (`BudgetMuscleGroups.of`
       credits every group a row names). Prove the fixture by running the intensity-keyed `desired` mutant (4 on strength); a 4-day fixture whose days hold identical exercise lists but intensities
       strength / hypertrophy / strength / endurance yields identical (name, sets, rest) on all four
       days through the real allocator and `apply`;
   (c) deload: call `PeriodizationEngine.apply` DIRECTLY with hand-built rows at 1, 2, 3, 4, 5 sets
       (the allocator never emits fewer than 2, so a 1-set row only exists this way) and assert exactly
       1->1, 2->2, 3->2, 4->2, 5->3 (today's formula gives 1,1,1,2,3: a real behaviour change), and that
       the day keeps its count;
   (d) week-2 gains equal an independent re-price of week 1 at archetype rests, on a fixture TUNED so one
       exercise gains at the archetype price and would not at the selector's stale default rest
       (`Fx.ex(rest:)` in `session_budget_fixtures.dart:27` sets the stale selector rest; an isolation
       row costs 1.2 x (47 + 75) = 146 s per extra set at the archetype rest against 1.2 x (47 + 30)
       = 92 s at a stale 30: pick `minutes` so the seconds left sit between 92 and 146; verify by
       running the `ex.restSeconds` mutant);
   (e) a rep-based custom is priced identically by the allocator and `_weekTwoGains` and stamped by
       `apply`, observed through a TUNED boundary: the custom sits on a day where the admission (or
       week-2 gain) of a neighbouring exercise flips if the custom is priced at a fixed rest or at
       `ex.restSeconds` (verify by running both mutants);
   (f) the tester case (intermediate, basic_gym, 4 days, 55 kg, build_muscle, 60 min): the four day
       counts are MEASURED first and written to the report; the test then asserts `max - min <= 2`
       across the four days IF the measurement supports it (the estimate is about 1), else if the measured spread is > 2 the plan
       STOPS and the number goes to the founder; it never asserts 5-8 (piece B). Because the bound is
       set after measuring it is a ratchet, not a proof: the diagnose-doc also records the measured
       counts for beginner and for 30 / 45 / 90 minutes (beginner loses accessories to cap 6 / top 12);
   (g) (not a new proof: weekly top, lighter-phase bottom and session cap are the existing gate, listed
       under "existing gates verified" in the diagnose-doc);
   (h) allocator price vs stamp: a tuned fixture at 30 min (1440 s) with 4+ isolations in DISTINCT muscle
       groups (so a cap, not the time price, cannot stop the 4th) and the finisher off
       (`finisherSeconds` 0). At 75 s rest a
       3-set isolation costs 403 s, so 3 fit (1209 s); a mutant pricing at 38 s costs 314 s and admits a
       4th (1612 s at the true price). Assert the day's summed seconds at `restForArchetype` are
       <= 1440 s. (The whole-day check stays with the existing gate,
       `session_set_budget_gate_test.dart:225-250,~300`, which prices warm-up and cool-down too and
       checks `<= effMinutes + 2`; `estimateDaySecondsFromPlanDay` includes warm-up/cool-down so it is
       NOT compared to the exercise-only budget);
   (i) literal pins in `session_budget_test.dart`: `restForArchetype` H 150, M 120, I 75, B 60,
       unknown 60, and `baseSets == 3` (the other assertions compare against the table itself, so a
       swapped table would otherwise survive).
6. Mutation proofs (rule 21), each confirmed applied with `grep -c`: allocator reads
   `restFor`-style intensity rest again; `desired` intensity-keyed again; `_applyWave` stamps a fixed
   rest; H/M rest swap and any literal change in `restForArchetype` (killed by (i)); unknown default 60 vs 75
   (killed by (i), since `archetypeOf` only returns H/M/I/B); allocator prices a budgeted slot at a
   wrong rest while `apply` stamps the right one (killed by (h)); deload floor 1 and 3; deload without the `min(ex.sets, ...)`;
   `_weekTwoGains` reading `ex.restSeconds`; custom priced at a fixed rest and at `ex.restSeconds`, ONE of each per pricing site
   (`session_set_allocator.dart:197`, `periodization_engine.dart:162`, the stamp in `apply`), each with a
   boundary the other two sites cannot cover (5(e));
   allocator at 38 s while `apply` stamps 75 s (killed by (h)); swap keeps the outgoing rest (killed
   by the swap regression test). Record reddened counts.
7. Docs: `plan-engine-detail.md:334` ("Rest by day intensity: strength 150...") and `:342` ("rep-based
   customs at the day's rest") rewritten; the deload formula text in `plan-engine-detail.md` (Consumers paragraph) and plan_engine `CLAUDE.md:83`;
   code comments `session_budget.dart:237`,
   `periodization_engine.dart:50-56,142,161-162` (deload formula text `max(1, floor ...)`); plan_engine
   `CLAUDE.md` ("Session set budget" bullet, "Exercise count per day" paragraph, the pitfalls row
   "Plan generator returns wrong number of exercises", the `shortenDay` description); SoT entry with
   `behavioral_test_path`; registry line ranges recomputed from anchors.
8. Diagnose-doc `docs/diagnoses/2026-11-04-rest-by-type-<id>.md` (full template; prior instances from
   `docs/diagnoses/INDEX.md` in `related_bugs:`; records that strength-goal users go from 4 to 3 base sets on strength days (founder-accepted) and the weaker deload: a 3-set exercise goes 3->2
   instead of 3->1 and an all-2-set day gets no week-4 cut; the SoT concept name is taken from the
   existing `session_set_budget` entry, not invented), plan-review record `docs/plan-reviews/<branch>.md`.
9. Full gate loop (whole-project `flutter analyze --no-fatal-infos`, `TZ=Asia/Kolkata flutter test`,
   pre-commit loop), B-pass `/code-review`, `land_pr.sh`, retire the worktree.
10. The swap fix of 3.3b with its regression test and harness (its own commit slice, so a reviewer can bisect it) (replaces the OI of v2: minting an OI for a defect this
    batch creates is the 4.2 re-wrap). `swap_sheets.dart` and `template_service.dart` stay as named.
11. After landing: run the sweep report, record the measured day counts per level and length, and
    write the piece-B re-plan from them (OI-456 stays OPEN until piece B lands).

## 5. Risks the reviewers should attack

- Does uniform `baseSets = 3` plus per-type rest really equalise counts, or does the exercise mix
  (heavy-heavy days) still skew them? Estimate from the time constants, do not assume.
- Existing plans on tester devices are not regenerated; only new generations and phase advances move.
- Any reader of the stored rest or of the old helpers the sweep (Task 1) would miss.
- `_applyWave` threading of `budget` into the `workingReps` stash call.
