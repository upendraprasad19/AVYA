# Batch B2 — Session set budget (ship-dark) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Revision:** r6 (2026-10-24), a rebase onto main `70f1237c` and nothing else (no design change; the rebase notes are Ruling 14). r5 (2026-10-23): Round 4 returned `converged` (0 P0 / 0 P1); r5 applied its 6 P2 and 8 mechanical items; see "Round-4 resolution".
- **Execution mode (decided at batch start, §4.12.7): inline**, one worktree `session-set-budget`, tasks in order; one push, one PR. Never switched mid-batch.
- **Round 1:** `not_converged` (7 P1).
- **Round 2:** `not_converged`: 2 P1 in the allocator's admission rule, 13 P2, 12 mechanical.
- **r3:** replaces admission with a priority-rank rule, replayed before dispatch (scratchpad `b2r2/sim3.py`, `sim3b.py`).
- **Round 3:** `not_converged`. 1 P1: the lead-lift count can't pass when weekly tops bind. Plus 8 P2 and 8 mechanical.
- **r4:** adds a rank-0 reservation and the fixes listed in "Round-3 resolution". Resolution maps are at the end.

**Goal:** Behind a default-OFF flag, a generated session's size follows the user's minutes and evidence-based caps, instead of a fixed exercise count, a 4-set minimum and a phase multiplier. Minutes are timed with the engine's own rest per day intensity. The Train screen's time estimate uses the same model.

**Architecture:**
- **Pure pieces first:**
  - `SessionBudget`: minutes, time model, bands, caps, the shared `BudgetLedger`;
  - `BudgetMuscleGroups`: muscle normaliser;
  - `SessionSetAllocator`: priority-rank admission across the week.
- **Consumers** take an optional immutable `SessionBudgetContext` (null = today's code path): `PeriodizationEngine.apply`, `VolumeTitration.applyToWeeks` and `WarmupCooldownSelector.attach`. All three check headroom through the one `BudgetLedger`.
- **Wiring:** `generateV4` comes last (rule-14 waiver F1).
- **Display:** `WorkoutDayData.estimatedDuration` switches to the model under the flag.

**Tech Stack:** Flutter/Dart, Hive, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md` §5 and §10 Q2; founder decisions F1–F5. Evidence: scratchpad `batchb/q4_set_budget.md`; reviews `batchb/b2_review1.md` and `batchb/b2_review2.md`.

**Depends on:** B1 merged (B1's golden is the OFF proof; B1's trace serves Task 5). Own branch, built after B1 merges, with its own plan-review record.

**Blast radius:** `platform`. Full ×2 review, B-pass, flag in `docs/ship_dark_pending_review.yaml`. No bug fix. No new `check_*.dart`.

## Founder decisions (2026-10-22, locked)

- **F1.** Rule 14 waived, for this batch's wiring only (the `plan_generator.dart` call sites listed in Task 6).
- **F2.** An empty `session_duration_minutes` means 60 min. No new onboarding question.
- **F3.** When the weekly cap is reached before the minutes run out, focus muscles may go to about 25 hard sets a week. Otherwise the session ends early, and the shown time says so.
- **F4.** Exercises the user adds to a live plan are never trimmed and never count. A library exercise that returns as a repeat pin is generated content and is budgeted (Ruling 8).
- **F5.** A focus muscle's per-session cap is 12 sets; others stay at 6 / 8 / 10.

## Global Constraints

- **§5 / Q2 volume:**
  - 10–20 hard sets per muscle per week;
  - at most 8–10 per muscle per session (focus 12, F5);
  - total sized by minutes;
  - customs never count.
- **Flag:** `enable_session_set_budget`, default OFF (`configBox` value `== true`). OFF is byte-identical to the B1 golden, and OFF does no profile read: the minutes read sits inside `if (budgetOn)`.
- **Muscle maps:** `primary_muscles` and the frozen `muscleGroupOf` are unchanged. Budget accounting uses `BudgetMuscleGroups`; titration evidence keeps `muscleGroupOf` (Ruling 10).
- **Citations:**
  - Schoenfeld, Ogborn & Krieger 2017 (J Sports Sci; weekly dose-response);
  - Pelland et al. 2026 (Sports Med 56(2):481-505; diminishing returns);
  - Remmert, Pelland et al. 2025 (SportRxiv preprint, not peer reviewed; per-session plateau of about 11 fractional sets).
- **Process:** tests run with `TZ=Asia/Kolkata`; commits only via `scripts/safe_commit.sh`; one push; no APK.

## Review Focus

1. **Callers that pass no minutes.** Only `pro_phase_advance.dart:215,242` and `simulation_service.dart:586` forward the profile value. ON resolves minutes centrally for every other caller (Task 6):
   - onboarding;
   - login restore;
   - train regen;
   - graduation;
   - edit-profile regen;
   - hotel;
   - coach regen;
   - both previews.
2. **Strength days.** Every rep exercise rests 150 s, so the time model must use the real rest (Ruling 2; Tasks 1, 3 and 7).
3. **Priority.** Each day's first lift must reach its intended dose before accessories take a share (Task 3 priority tests; Task 7 primary-lift count).
4. **Deload and lighter phases.**
   - Phases 4/8/12 stay lighter, and focus pass D is skipped in them.
   - Week 4 is at most that exercise's baseline.
   - The stash equals the same exercise's allocated baseline.

   Covered by Tasks 3, 4 and 7.
5. **Short or thinned days** (30 min, injury-trimmed, all-custom): no crash, no empty strength day, and forced admissions are counted (Tasks 3 and 7).

---

## Rulings

1. **Volume grows by load, not by set inflation.**
   - Under ON, `cycleMultiplier` (`periodization_engine.dart:29-33`) and the 4-set minimum (`:202-204`) are not applied.
   - In archetype-`deload` phases (`archetypeForPhase`, `:15-18`, i.e. phases 4/8/12):
     - every group's weekly top, focus included, is the band's **bottom**;
     - pass D is skipped;

     so a lighter phase stays lighter.
   - Level promotion still moves the band and cap rows. That is the intended way volume grows.
2. **Time model: per exercise, with the engine's real rest.**
   - **Formula:** `exerciseSeconds(archetype, sets, restSeconds) = 1.20 × (overhead + sets × work + (sets − 1) × restSeconds)`.
   - **`archetypeOf`** reads the row's `exercise_type` list and the lower bound of `rep_range`. An exercise with no library row (a custom) uses its own stored `exercise_type` and `rep_range`, through the same function.
     - **Type precedence:** compound > isolation > calisthenics > other.
     - **Archetypes:**
       - **H:** compound with lower bound ≤ 6;
       - **M:** any other compound, or calisthenics with lower bound ≤ 10;
       - **I:** isolation;
       - **B:** any other calisthenics, any other type (flexibility, activation, cardio, yoga), and anything with `timed`, `cardio` or `distance` logging (M3).
     - The allocator, `apply`, titration and the display all use this same function (M7).
     - **Inputs always come from the library row** (`exercise_type` as a list, String or null; `rep_range`), never from a week's wave-adjusted `reps`. The wiring computes `SessionBudgetContext.archetypeByName` once, and `apply` and titration read it. The display looks up the row by `ExerciseData.exerciseId`; its own fields are only a fallback (round-3 P2-2).
     - `maxSetsPerExercise = 5` sits in the same table (M5).
   - **Constants** (Q4 §4.2):

     | archetype | H | M | I | B |
     |---|---|---|---|---|
     | work (s) | 23 | 35 | 47 | 40 |
     | overhead (s) | 120 | 90 | 45 | 30 |

   - **`restSeconds`** = the day intensity's `baseRest`: strength 150, hypertrophy 75, endurance 38. An unknown intensity uses hypertrophy, as `periodization_engine.dart:88` does (M4).
   - **The 1.20 factor** is a calibrated assumption. All constants live in one table in `session_budget.dart`.
3. **Warm-up and cool-down scale with minutes (affine).**
   - **`W+C(T)`:** 30 → 6, 45 → 8, 60 → 10, 75 → 12, 90 → 14 minutes; linear between, clamped to [6, 14].
   - **Scaled items:** the cardio lead-in and the cool-down walk are each `round(60 × (W+C − 4) / 2)` s. That gives 60 s at 30 min, 180 s at 60 min, and 300 s at 90 min (today's value).
   - Every other item is unchanged.
4. **Bands and caps.** Weekly hard sets per muscle, and the per-session cap per muscle:

   | goal | beginner | intermediate | advanced | cap B / I / A |
   |---|---|---|---|---|
   | build_muscle | 10–12 | 12–16 | 14–20 | 6 / 8 / 10 |
   | strength | 10–12 | 10–14 | 12–16 | 6 / 8 / 10 |
   | lose_fat | 10–12 | 10–14 | 12–16 | 6 / 8 / 8 |
   | general_fitness | 10–10 | 10–12 | 12–14 | 6 / 8 / 8 |

   - **Focus muscles:** weekly top 25 and session cap 12, except in deload phases (Ruling 1).
   - **Unknown inputs:** an unknown goal uses the build_muscle row; an unknown level uses intermediate.
5. **No superset time credit.** The allocator runs before `SupersetPairer`.
6. **No finisher time is reserved while no screen shows the finisher.**
   - The stored `finisher` key is written (`workout_schedule_read_service.dart:301-303`), but no file under `lib/features` reads it: `preview_plan_provider.dart:139` excludes it, and `WorkoutDayData` has no finisher field.
   - Reserving minutes for it would shorten the lifting with nothing to fill the gap. So `SessionBudgetContext.finisherSeconds = 0`, and the display ignores the finisher, as it does today.
   - **Closure:** `upstream_blocked` on the founder's finisher decision. It reopens when a screen shows the finisher; that change must then set the reserve from the built finisher.
7. **The Edit Profile default changes from 90 to 60, unflagged** (`edit_profile_screen.dart:239, 301, 1874-1875`). Pre-launch, every account is a test account. The 9 live rows at 90 stay 90. **Closure:** `upstream_blocked`; reopens at store-launch planning.
8. **F4 boundary.**
   - Repeat pins of library rows are budgeted.
   - Customs (`customOrigin != null`) are never budgeted.
   - Not-budgeted library rows (timed / cardio / distance) keep their sets and their time counts, timed at their **own** rest (`default_rest_secs`, i.e. `PlannedExercise.restSeconds`), not the day's (round-3 P2-1). Rep-based customs are timed at the day's rest, because the wave assigns them that rest (`periodization_engine.dart:238`).
   - **Custom detection:** a row counts as custom when `customOrigin != null` OR it has no row in `rowsByName`. `customOrigin` is stamped only when `SyncFlags.l2CustomStripEnabled` is on (`exercise_selector.dart:1448`, was `:968` before the thin-day top-up), so both checks are needed (M8). Their week-2 +1 applies only when the ledger's day time allows (P2-11c).
9. **Focus source:** `effectiveBodyFocus` (`plan_generator.dart:254-257`) through `BudgetMuscleGroups`. Tokens that map to no group are ignored.
10. **Titration under ON.**
    - MEV = band bottom; MRV = band top (25 for focus outside deload phases).
    - Counting uses `BudgetMuscleGroups`.
    - A +1 is refused when the `BudgetLedger` says no.
    - Delta keys with no budget group are skipped: `Forearms`, and any key `BudgetMuscleGroups` maps to nothing.
    - The evidence side (`resolveDeltas`, `muscleGroupOf`) is intentionally unchanged.
    - A plateau +1 is refused the same way, inside `applyToWeeks`, which receives the merged map (`plan_generator.dart:289-292`). `mergePlateauSetDeltas` stays as is (M8).
11. **Week-2 copy.**
    - Week 2 gives +1 per exercise only where the ledger allows.
    - An exercise that did not gain a set gets week 1's per-exercise cue instead of "Same weight, more volume".
    - The week note is swapped for week 1's note only when no exercise gained a set (`periodization_engine.dart:46-58`). With weekly tops binding, this is the common case, so week 2 usually shows week 1's note (M8).
12. **`lower back`, `erector` and `spinal` map to no budget group.** They name the erectors, not the lats and upper back.
    - **Replay effect:** Deadlift no longer spends the Back allowance. Legs A Deadlift goes from 2 to 4 sets, and Pull B keeps its rows.
    - **`lat`** matches only as a whole word, so `Lateral Delts` maps to Shoulders, not Back (M6).
13. **Display under ON.** `WorkoutDayData.estimatedDuration` is the sum, rounded to minutes, of:
    - `exerciseSeconds` over the day's exercises, user-added ones included (they are part of the real session).
      - **Archetype:** from the library row found via `ExerciseData.exerciseId`; when there is no row, from `ExerciseData.exerciseType` / `reps` / `loggingType`.
      - **Rest:** parsed from `ExerciseData.rest` as digits (`90s` → 90). A non-numeric string → 75. A missing rest uses the parser's existing `60s` default (`train_provider.dart:427`, M6).
    - the warm-up and cool-down item seconds.

    One shared function serves both estimators, `train_provider.dart:257-261` and `home_screen.dart:905-919` (round-3 P2-3, round-4 P2-6): `SessionBudget.estimateDayMinutesFromPlanDay(Map<String, dynamic> planDay, Map<String, Map<String, dynamic>> rowsById)` → `int`.
    - **Input:** the stored plan day map, i.e. its `exercises` (`sets`, `rest_seconds` defaulting to 60, `exercise_id`), `warmup` and `cooldown` lists.
    - **Train:** calls it when it builds `WorkoutDayData` from that map (`:713`, `:923`, `:944`) and stores the result for `estimatedDuration`.
    - **Home:** calls it on the same map.

    Same input, same minutes. User-added exercises are in the map.

    OFF keeps both estimators' `totalSets × 2.5` verbatim, as pinned by `regression_logic_test.dart:279-298`.
14. **Rebase onto the thin-day top-up (r6, 2026-10-24).** Main now carries B1 (PR #150), the injury re-check (#155) and the thin-day top-up (PR #164, `70f1237c`). Checked against the code, not assumed:
    - **Order.** `ExerciseSelector.topUpDays` runs inside `pickV4` (cascade end and the B1 `_pickCoreList` return) and `buildPinnedDays`, so it runs before the allocator, which sits between `plan_generator.dart:257` and `:260`.
    - **Rank.** `_topUpVariant` copies the variant list and appends (`out = [...current]`, `out.add(...)`, `exercise_selector.dart:1236`, `:1286`). Added moves therefore rank last and are budgeted like any generated exercise. No allocator change.
    - **Injured users only.** The top-up returns the same list instance when `injuries` is empty, so every uninjured B2 persona and the OFF golden are unaffected.
    - **OFF proof.** The OFF golden is `test/fixtures/generator_golden_hashes.json` as re-recorded by the top-up (two injury keys moved); "the B1 golden" in Tasks 0 to 6 means that file at `70f1237c`.
    - **Citations.** `exercise_selector.dart:968` is now `:1448` (Global ruling 8). `plan_generator.dart` anchors (`:165`, `:254`, `:260`, `:292`, `:299`, `:335`) and `warmup_cooldown.dart:195` (`attach`) are unchanged.
    - **Task 6 fixture.** The top-up should have filled the knee-injury thin legs day on main (Task 6 Step 1 computes whether it did before asserting anything); the test sets the kill-switch to build the thin day, plus an ON twin (Task 6 Step 1).
    - **Task 8 docs.** `plan_engine/CLAUDE.md` is at 19,516 B against a recorded 16,986 B (soft band 15%, about 18 B of headroom). The ON lines go to `docs/architecture/plan-engine-detail.md` with a one-line pointer in the nested file, or `check_context_artifact_budget.dart --record` re-baselines it deliberately; either way the §5 budget row is walked.

---

## File structure

| File | Responsibility |
|---|---|
| `plan_engine/session_budget.dart` (create) | Pure: minutes, archetype, time model, bands and caps, `SessionBudgetContext`, `BudgetLedger`. |
| `plan_engine/budget_muscle_groups.dart` (create) | Pure normaliser. |
| `plan_engine/session_set_allocator.dart` (create) | Pure allocator plus a `@visibleForTesting` stats sink. |
| `plan_engine/plan_engine_flags.dart`, `training_history_analyzer.dart` (modify) | Flag; `sessionMinutesFromProfile()`. |
| `plan_engine/periodization_engine.dart`, `volume_titration.dart`, `warmup_cooldown.dart`, `volume_filter.dart` (modify) | Optional context; `keepAllSlots`. |
| `plan_engine/plan_generator.dart` (modify, F1) | Wiring, plus the stale comment at `:144-146` (B1 Ruling 11). |
| `lib/features/profile/screens/edit_profile_screen.dart`, `lib/features/train/providers/train_provider.dart` (modify) | Default via `SessionBudget.defaultMinutes`; flagged display estimate. |

(`plan_engine/` = `lib/shared/repositories/plan_engine/`.)

---

### Task 0: Flag, minutes resolution, Edit Profile default

**Files:**
- `plan_engine_flags.dart`
- `session_budget.dart` (resolution part)
- `training_history_analyzer.dart`
- `edit_profile_screen.dart:87-89, 239, 1936-1938`
- Test: `test/plan_engine_v4/session_minutes_resolution_test.dart`

**Interfaces:**
- `PlanEngineFlags.sessionSetBudgetEnabled` → `configBox.get('enable_session_set_budget') == true`, `try/catch` → `false`.
- `SessionBudget.defaultMinutes` → `const int = 60`.
- `SessionBudget.resolveMinutes({int? param, Object? profileValue})` → `int`:
  - `param` if it is in 15..180;
  - else `profileValue`, if it is a finite `num` whose rounded value is in 15..180;
  - else `defaultMinutes`.
- `SessionBudget.initialSessionDuration(Map profile)` → `int` = `resolveMinutes(profileValue: profile['session_duration_minutes'])`.
- `TrainingHistoryAnalyzer.sessionMinutesFromProfile()` → `Object?`:
  - reads `HiveService.instance.userBox.get('profile')`, `try/catch` → null;
  - has a `@visibleForTesting static int debugReadCount` (M2).

- [ ] **Step 1: Failing tests.**
  - `resolveMinutes`:

    | param | profileValue | expected |
    |---|---|---|
    | 45 | 90 | 45 |
    | null | 75 | 75 |
    | null | null | 60 |
    | null | 'abc' | 60 |
    | 5 | null | 60 |
    | 5 | 75 | 75 |
    | null | `double.nan` | 60 |

  - `initialSessionDuration({}) == 60` and `initialSessionDuration({'session_duration_minutes': 90.0}) == 90`.
  - Source-grep (presence only): the screen contains `SessionBudget.initialSessionDuration(` and no `?? 90`.
- [ ] **Steps 2–4.** Watch the tests fail, then implement. Update the comments at `:87-89` and `:1936-1938` to say the field is consumed under the flag. Expected: all PASS, and the B1 golden PASSES.
- [ ] **Step 5: Mutate.** Set `defaultMinutes = 90` → the `(null, null)` case FAILS.
- [ ] **Step 6: Commit** `feat(plan-engine): session minutes resolution and the enable_session_set_budget flag`.

### Task 1: Budget model and ledger

**Files:** `session_budget.dart`; test `test/plan_engine_v4/session_budget_test.dart`.

**Interfaces:**
- **Time model and archetype:**
  - `warmCoolMinutes(int)` (Ruling 3).
  - `archetypeOf({required List<String> exerciseTypes, required String reps, required String loggingType})` → `H` / `M` / `I` / `B`.
  - `archetypeOfRow(Map row)` delegates to `archetypeOf`. It serves library rows and customs alike, because customs store `exercise_type` and `rep_range` too.
  - `exerciseSeconds({archetype, sets, restSeconds})`.
- **Day intensity:**
  - `restFor(String intensity)`; unknown → 75.
  - `desiredFor(String intensity)`: strength 4, hypertrophy 3, endurance 2, unknown 3.
- **Bands and caps:**
  - `weeklyBand(planGoal, level)` → `({int bottom, int top})`.
  - `sessionCap(planGoal, level)`.
  - `focusWeeklyTop = 25`, `focusSessionCap = 12`.
- **`SessionBudgetContext`** (immutable): `minutes`, `planGoal`, `level`, `bool lighterPhase`, `Set<String> focusGroups`, `int finisherSeconds` (always 0, Ruling 6), `Map<String, String> archetypeByName` (lowercased name → archetype, Ruling 2), `List<String> dayIntensities` (per day index, from the populated days).
- `archetypeOfRow` accepts `exercise_type` as a List, a String or null (M2).
- **`class BudgetLedger`**, built from `(ctx, dayCount)`. Callers pass seconds, so the ledger never reads an intensity (M4).
  - `int weeklyTop(String group)`: band top; 25 for focus; band bottom for every group when `lighterPhase`.
  - `int cap(String group)`.
  - `bool fits(int day, Set<String> groups, int addSets, double addSeconds)`.
  - `void add(int day, Set<String> groups, int addSets, double addSeconds)`.
  - `int week(String group)`, `int session(int day, String group)`, `double secondsLeft(int day)`.
  - **Day budget:** `(minutes − warmCoolMinutes) × 60 − finisherSeconds`, minus the seconds of not-budgeted rows (added through `add` with empty groups).

  The ledger is the single headroom predicate for the allocator, `apply` week 2 and titration (P2-3).

- [ ] **Step 1: Failing tests.** Compute each literal from the constants first.
  - `warmCoolMinutes`: `(52)` ≈ 8.933; `(20) == 6`; `(120) == 14`.
  - `exerciseSeconds`: `('M', 4, 75) == 546.0`; `('I', 3, 150) == 583.2`.
  - `archetypeOf`:
    - `(['calisthenics','isolation'], '12-20', 'bodyweight_reps') == 'I'` (precedence);
    - `(['compound'], '5-8', 'weight_reps') == 'H'`;
    - a `timed` row → `B`.
  - Bands and caps:
    - `weeklyBand('build_muscle','intermediate') == (12, 16)`;
    - `sessionCap('lose_fat','advanced') == 8`;
    - unknown goal or level → `(12, 16)`.
  - `BudgetLedger`:
    - `fits` refuses past the cap, past the weekly top, and past time;
    - with `lighterPhase`, `weeklyTop` = bottom for focus and non-focus groups.
- [ ] **Steps 2–4.** Watch them fail, implement, watch them pass.
- [ ] **Step 5: Mutate.**
  - 1.20 → 1.0 → the `exerciseSeconds` cases FAIL.
  - Drop the `lighterPhase` branch → its case FAILS.
- [ ] **Step 6: Commit** `feat(plan-engine): session budget model and ledger`.

### Task 2: Budget muscle groups

**Files:** `budget_muscle_groups.dart`; test `test/plan_engine_v4/budget_muscle_groups_test.dart`.

**Interface:** `groups` = Chest, Back, Shoulders, Biceps, Triceps, Quads, Hamstrings, Glutes, Core, Calves.

`static Set<String> of(List<String> tokens)` strips parentheticals and lowercases each token, then:
1. A token matching `lower back|erector|spinal` maps to no group (Ruling 12).
2. Otherwise:

   | token keyword | group |
   |---|---|
   | chest, pec | Chest |
   | `\blats?\b`, back, trap, rhomboid | Back |
   | delt, shoulder | Shoulders |
   | bicep, brachialis | Biceps |
   | tricep | Triceps |
   | quad | Quads |
   | hamstring | Hamstrings |
   | glute | Glutes |
   | abs, oblique, core, transverse | Core |
   | calf, calves, gastrocnemius, soleus | Calves |

3. Anything else maps to no group.

- [ ] **Step 1: Failing tests.**
  - Unit cases:

    | input | expected |
    |---|---|
    | `['Calves (Gastrocnemius)']` | `{Calves}` |
    | `['Lateral Delts']` | `{Shoulders}` |
    | `['Lats']` | `{Back}` |
    | `['Lower Back','Glutes','Hamstrings']` | `{Glutes, Hamstrings}` |
    | `['Upper Chest']` | `{Chest}` |
    | `['thoracic']` | `{}` |

  - Row-level, over the shipped library: the rep-based rows with no group are exactly the computed set. Compute it first under Ruling 12. Round 2 found E065 E078 E099 E100 E108 E137 E157 E184 E194 E200; rows whose only primary is Lower Back now join it.
  - The test's header says Batch C's new rows will change this set by design (M11).
- [ ] **Steps 2–4.** Fail, implement, pass.
- [ ] **Step 5: Mutate**, one at a time:
  - remove the parenthetical strip → the Calves case FAILS;
  - `\blats?\b` → `lat` → the Lateral Delts case FAILS;
  - remove the lower-back rule → its case FAILS.
- [ ] **Step 6: Commit**.

### Task 3: Allocator

**Files:** `session_set_allocator.dart`; test `test/contracts/session_set_allocator_behavioral_test.dart`.

**Interfaces:**
- **`allocate`:** `static List<PopulatedDay> allocate({required List<PopulatedDay> days, required SessionBudgetContext ctx, required Map<String, Map<String, dynamic>> rowsByName, required bool is6Day})`. It returns days whose `PlannedExercise.sets` are the baseline sets (weeks 1/3 for A, 2/4 for B), with removed exercises dropped.
- **`AllocationStats`**, one per variant (`'A'` / `'B'`):
  - `int timeForcedFirst`;
  - `int capForcedFirst`;
  - `Map<String, int> weekly`;
  - `Map<String, String> belowFloor`: group → `cap_limited` | `co_group_limited` | `time_limited` | `not_trained_by_split`;
  - `List<({int day, int rank, int sets, int desired, double secondsLeft, String? boundBy})> firstLifts`. `boundBy` names the group whose cap or top stopped the lead lift (M5).
- **Stats sink:** `@visibleForTesting static Map<String, AllocationStats>? debugLastStats`, set on every call, so the gate can read it after `generateV4` (P2-1).

**Algorithm (exact).** Run per variant, each with its own `BudgetLedger`.

1. **Variant order.**
   - Variant A is allocated over all days first.
   - For variant B on non-6-day plans: days whose B list is the same object as A's, or has the same names, copy A's sets into B's ledger; only the other days are allocated (P2-7).
   - 6-day plans use A only.
2. **Not-budgeted rows.** A row is not budgeted when it has `customOrigin != null`, logging `timed`, `cardio` or `distance`, or no row in `rowsByName`. It keeps its sets and is never removed. Its seconds go in with `ledger.add(day, {}, 0, seconds)`. Sets come from its row's `default_sets`. Rest follows Ruling 8: timed rows use their own `default_rest_secs`, and rep-based customs use the day's rest.
3. **Rank and desired.** Rank is an exercise's position among its day's budgeted exercises, in selection order (= slot priority). `desired = desiredFor(day.intensity)`.
4. **Pass A: priority-rank admission.** For rank r = 0, 1, …, visit each day in order and take its rank-r exercise.
   - Grant `k` = the largest value in [2, desired] for which `ledger.fits(day, groups, k, seconds(k))` holds.
   - **Rank-0 reservation (round-3 P1-1).** While r = 0, `k` must also leave, for each of the exercise's groups, `week room ≥ 2 × (later days in this round whose rank-0 exercise credits that group)`. Every day's lead lift then keeps at least 2 sets when time allows; earlier days give up their extra sets first.
     - **Which days count:** only later days still undecided in this variant's pass A. B days copied from A and days with no budgeted rank-0 exercise are excluded (M3).
     - **Limit:** the guarantee holds while `2 × (days whose rank-0 credits a group) ≤` that group's weekly top. The worst case in the stand-in data is 4 days × 2 = 8 against a top of 10. Beyond the limit, the EARLIEST such day's lead lift is the one removed (M6). Task 7 asserts the precondition for every split and persona.
   - If no such k exists, mark the exercise removed.
   - An exercise with no group is checked against time only.
5. **Empty-day guard.** A day with budgeted exercises but none admitted gets one exercise at 2 sets, ignoring time:
   - its rank-0 exercise, if every group of it has `week ≥ 2` room → `timeForcedFirst++`;
   - else the first exercise whose groups all have room → `timeForcedFirst++` (M4);
   - else rank 0 regardless → `capForcedFirst++` (the gate requires 0).

   A day with no budgeted exercises is left as is (M5).
6. **Pass C: floors.** Repeat rounds until one adds nothing. In each round, every group below its `bottom` gets +1 on the first admitted exercise in (rank, day) order that credits it, has sets < `maxSetsPerExercise`, and fits the +1 (M1).
7. **Pass D: focus (F3/F5).** Skipped when `lighterPhase`. Same rounds as pass C, with a target of 25 per focus group; `fits` checks every co-group's cap and top.
8. **Classification.** For each group still below `bottom`, take the FIRST label that applies, in this order (round-4 P2-5):
   - `not_trained_by_split`: no budgeted exercise in the week credits it;
   - `time_limited`: at least one crediting exercise was removed, or stopped growing, for time alone. This includes a group whose every crediting exercise was removed for time;
   - `co_group_limited`: at least one crediting exercise is refused only by another group's cap or top;
   - `cap_limited`: every remaining case. At least one admitted exercise credits the group, and each one is refused by its own session cap or already has 5 sets.
9. **Leftover time** stays unused, and the session ends early (F3).

**Replay** (`b2r2/sim3b.py` on r3; round 4 re-ran it with the reservation and own rest, `b2r4/alloc4.py`, and reproduced this table; 6-day PPL, intermediate, build_muscle; Q4 stand-in selections) (M2):

| minutes | result |
|---|---|
| 90 | every day's first lift at its desired 4 / 3; 0 empty days; Chest 16, Back 16; Quads 8 is `co_group_limited` (Glutes top 16) |
| 60 | first lifts kept; Pull B ends 18 min early |
| 30 | 2 lifts per A day |
| 90, focus Chest | Chest reaches 21 sets/week |

- [ ] **Step 1: Failing tests.** All crafted unless marked "real"; compute every literal first.
  - **`priority`:** a day with 4 Chest exercises (desired 4, cap 8) → sets `[4, 4, removed, removed]`, never `[2, 2, 2, 2]`. The admit-all-at-2 mutation must make this FAIL.
  - **`round-robin by rank`:** 4 days whose rank 0 and rank 1 both credit Back (top 16, desired 4, ample time) → every day keeps rank 0 at 4 sets, and `capForcedFirst == 0`. Mutation: process days sequentially → days 3–4 lose rank 0 → FAIL.
  - **`time`:** a crafted day where no cap binds (one exercise per group).
    - Each day's `Σ exerciseSeconds` is at most its budget.
    - The same list holds fewer sets on a strength day than on a hypertrophy day at equal minutes. The fixture removes caps and tops so that only time binds.
  - **`session cap`:** at intermediate, non-focus groups ≤ 8 sets and focus groups ≤ 12 per session.
  - **`weekly top`:** non-focus groups ≤ 16 (intermediate build_muscle), including when the guard fires.
  - **`lighter phase`:** with `lighterPhase`, every weekly total ≤ bottom, focus groups included.
  - **`focus reaches past 16`** (real persona: full_gym intermediate 6-day 90 min, focus Chest, through `generateV4` after Task 6) → Chest > 16 and ≤ 24.
  - **`terminates`:** all focus exercises at 5 sets with time left → returns.
  - **`no-group exercise`:** E065 Burpee on a lose_fat day is checked against time only and never throws.
  - **`not budgeted`:** a `customOrigin: 'repeat_pin'` row with 6 sets and a timed plank keep their sets, while a budgeted row on the same day IS trimmed.
  - **`guard`:** a 20-min day whose not-budgeted timed rows (planks at their own rest) use up the day budget → 1 budgeted exercise at 2 sets, `timeForcedFirst == 1`, `capForcedFirst == 0`. Compute first that the fixture really empties pass A (round-3 P2-4).
  - **`rank-0 reservation`:**
    - Fixture: general_fitness beginner 4-day. Every day's rank-0 exercise credits Chest (top 10, desired 4/3/2/2), and each day also has a rank-1 exercise on another group.
    - Assert: every rank-0 has ≥ 2 sets, `capForcedFirst == 0`, and weekly Chest ≤ 10.
    - Mutation: drop the reservation → the guard forces the last lead lift (`capForcedFirst == 1`, Chest 11) → FAIL (round-4 P2-2).
  - **`cap_limited`:** crafted cases for all four labels, including a group with one exercise removed for time and one at its cap → `time_limited`. Mutation: swap the label order → FAIL (round-4 P2-5).
  - **`not-budgeted rest`:** a timed row with `default_rest_secs: 30` on a strength day is timed at 30 s, not 150 s. Observable: the day's `secondsLeft`, and the budgeted exercise's sets that depend on it.
  - **`archetype agreement`:** for every shipped row, the allocator, `apply`, titration and the display (via `exerciseId`) see the same archetype (round-4 P2-3).
  - **`B equals A`:** in a 4-day plan whose day-2 B list equals A, that day has identical sets in A and B.
  - **`classification`:** one crafted case for each of the 4 labels.
- [ ] **Steps 2–4.** Fail, implement, pass.
- [ ] **Step 5: Mutate**, restoring by byte copy after each:

  | mutation | test that must fail |
  |---|---|
  | admit everything at 2 first | `priority` |
  | process days sequentially | `round-robin by rank` |
  | drop the cap check | `session cap` |
  | skip the guard's room check | `weekly top` |
  | remove pass D's stop | `terminates` (times out) |
  | ignore `lighterPhase` | `lighter phase` |
  | drop the rank-0 reservation | `rank-0 reservation` |
  | time not-budgeted rows at the day rest | `not-budgeted rest` |

- [ ] **Step 6: Commit** `feat(plan-engine): session set allocator`.

### Task 4: Consumers take the budget context

**Files:**
- `periodization_engine.dart:63-150, 175-259`
- `volume_titration.dart:158-258`
- `warmup_cooldown.dart:194-280`
- `volume_filter.dart:43-90`
- Test: `test/contracts/session_set_budget_consumers_test.dart`

**Interfaces.** Every new parameter is optional; null or false keeps today's path verbatim.
- **`PeriodizationEngine.apply(..., SessionBudgetContext? budget)`:**
  - base sets are the exercise's allocated `sets`: no multiplier, no min-4, no physique +1 (`:100-109`, `:135-146`);
  - week 2 (`weekIdx 1`) gives +1 per exercise in rank order, only where `fits`, using a fresh `BudgetLedger` seeded with that week's baseline;
  - week 4 (`weekIdx 3`) = `max(1, floor(0.6 × that exercise's allocated sets))`;
  - stash `workingSets` = **that same exercise's own allocated baseline** (P2-8);
  - Ruling 11 cues and notes; Ruling 8 for not-budgeted rows.
- **`VolumeTitration.applyToWeeks(weeks, deltas, {SessionBudgetContext? budget})`:** Ruling 10.
- **`WarmupCooldownSelector.attach(..., {SessionBudgetContext? budget})`:** Ruling 3.
- **`VolumeFilter.filterDays(..., {bool keepAllSlots = false})`.**
- **Ledger data flow (round-3 P2-7).** Per week, `apply` and `applyToWeeks` each build a fresh `BudgetLedger` from `ctx.dayIntensities`:
  - **Seeding:** every day's not-budgeted rows go in first, at their own rest; then the week's sets; archetypes come from `ctx.archetypeByName`.
  - **Order:** +1 candidates are visited rank-major across days (rank 0 of every day, then rank 1, …), as pass A does.
  - **Stash:** `workingSets` is a copy of the baseline, not a ledger entry.
  - **Titration's week-4 ledger** seeds from `workingSets`, as its own `workingBase` does (`volume_titration.dart:196-206`). Only budgeted rows are titration candidates (round-4 P2-4).
  - **Rank:** in `apply` and `applyToWeeks`, rank is the position among surviving budgeted exercises. That keeps the allocator's relative order, since removed exercises are gone (M7).

- [ ] **Step 1: Failing tests.**
  - **Base sets:** used as allocated at phase 9 (no ×1.2) and for an intermediate user (no min-4).
  - **Ledger agreement:** feed the allocator's output to `apply`. In the resulting week 2, no group exceeds its cap or top and no day exceeds its time, per a ledger replay (P2-3).
  - **Week 4 and stash,** for a 4-day plan (variant B) and a 6-day plan:
    - week 4 = `floor(0.6 × baseline)`;
    - a 2-set exercise gives 1;
    - `workingSets` equals the same exercise's baseline.
  - **Physique:** the physique +1 is absent with a budget.
  - **Week-2 cue:** an exercise that gained no set in week 2 carries week 1's cue.
  - **Ruling 8 week 2:** a timed library row gets its week-2 +1 only when the day's ledger time allows. Crafted: one day with time, one without → +1 on the first only (round-3 P2-8).
  - **Titration:**
    - never pushes a group past its top or cap;
    - counts `Lateral Delts` as Shoulders;
    - skips a `Forearms` delta;
    - refuses a plateau +1 at the cap, through `applyToWeeks`.
  - **Warm-up at 30 min:** lead-in 60 s and walk 60 s, asserted separately; the other items byte-equal today's (P2-12).
  - **Slots:** `keepAllSlots: true` returns every split slot.
  - **Null path:** each consumer with `budget: null` returns JSON-identical output on a fixture.
- [ ] **Steps 2–4.** Fail, implement, pass.
- [ ] **Step 5: Mutate** each guard → its test FAILS:
  - the week-2 `fits` check;
  - the stash;
  - the physique skip;
  - the titration clamp;
  - the Forearms skip;
  - the Ruling 8 week-2 time check.
- [ ] **Step 6: Commit** `feat(plan-engine): consumers honour an optional session budget`.

### Task 5: Production-path check of the extra slots

**Files:** test `test/contracts/keep_all_slots_selection_test.dart`.

- [ ] **Step 1.** Runs only after B1 merges, because it needs `CoreListSelector.debugTrace` and `enable_core_list_pool` (M7). Real library in Hive, every (goal × tier × days × level) at phase 1.
  - **OFF selection:** run `cascade_tracer.dart` (the OFF mirror) over `VolumeFilter.filterDays(..., keepAllSlots: true)` frames. Count slots beyond today's `targetCount` that resolve at attempt 5 or not at all.
  - **ON selection:** run `generateV4` with `enable_core_list_pool` on and B1's `CoreListSelector.debugTrace` attached. Count extra slots with source `drop`.
  - Report both counts. A non-zero attempt-5 count for gym tiers is a finding: fix it with a failing test first (P2-9).
- [ ] **Step 2: Commit**.

### Task 6: Wiring in `generateV4` (F1)

**Files:** `plan_generator.dart`, at exactly these places:
- `:89`;
- the flag read before `:165`;
- `:165-169` (`keepAllSlots: budgetOn`);
- `:183` (`populated` becomes non-final);
- the allocator call between `:257` and `:260`;
- `:260-271` (`budget:`);
- `:280-293`;
- `:335-342`;
- the stale comment at `:144-146` (B1 Ruling 11).

Test: `test/contracts/session_set_budget_wiring_test.dart`.

- [ ] **Step 1: Failing tests.**
  - **`OFF is the golden`** (4 B1 golden personas), and `debugReadCount == 0`.
  - **`ON uses the profile minutes when the caller passes none`:** profile 30 → every session's modelled seconds are within the budget.
  - **`ON with no minutes anywhere budgets 60`.**
  - **`ON level is the effective level`:** a beginner at phase 5 uses the advanced row.
  - **`ON with repeat pins`** (`pinnedExercisesByDay` with a library pin and a custom pin): the library pin is budgeted; the custom pin's sets are untouched (P2-11a).
  - **`ON with an injury-trimmed day`** (P2-11b, rebased by Ruling 14): the thin-day top-up now fills an injured day to 3 before the allocator runs, so a knee-injury legs day no longer ends with ≤ 2 exercises. Build the thin day with the top-up's kill-switch set (`configBox['disable_thin_day_topup'] = true`, cleared in `finally`) and assert, after computing it first, that a day has ≤ 2 exercises → no crash, no empty day. Add the top-up-ON twin: the day has 3 exercises, the added ones sit last in the list, and they are budgeted (their sets are allocator output, their seconds are in the day's ledger).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
  - Put `final budgetOn = PlanEngineFlags.sessionSetBudgetEnabled;` before `:165` (M1).
  - After `effectiveBodyFocus`, build the context:
    ```dart
    SessionBudgetContext? budget;
    if (budgetOn) {
      budget = SessionBudgetContext(
        minutes: SessionBudget.resolveMinutes(
          param: sessionDuration,
          profileValue: TrainingHistoryAnalyzer.sessionMinutesFromProfile(),
        ),
        planGoal: planGoal,
        level: effectiveExp,
        lighterPhase: PeriodizationEngine.archetypeForPhase(phase) == 'deload',
        focusGroups: BudgetMuscleGroups.of(effectiveBodyFocus),
        finisherSeconds: 0,
        archetypeByName: {
          for (final e in rowsByName.entries)
            e.key: SessionBudget.archetypeOfRow(e.value),
        },
        dayIntensities: [for (final d in populated) d.intensity],
      );
    }
    ```
  - Build `rowsByName` before the context.
  - `rowsByName` = `{for (final r in ExerciseRepository.instance.getAll()) (r['name'] as String).toLowerCase(): r}` (M3).
  - `if (budget != null) populated = SessionSetAllocator.allocate(...);`
  - Pass `budget` to `apply`, `applyToWeeks` and `attach`.
- [ ] **Step 4: Run** → PASS; the golden PASSES; `flutter analyze lib/` is clean.
- [ ] **Step 5: Mutate.** Change `keepAllSlots: budgetOn` to `false` on a beginner 6-day persona → the extra-exercise count (computed first) FAILS.
- [ ] **Step 6: Commit** `feat(plan-engine): wire the session set budget (ship-dark)`.

### Task 6b: Display estimate under the flag

**Files:** `train_provider.dart:257-261`; `lib/features/home/screens/home_screen.dart:905-919`; test `test/contracts/session_estimate_display_test.dart`.

- [ ] **Step 1: Failing tests.**
  - **Flag OFF:** both estimators keep `sets × 2.5`. `regression_logic_test.dart:279-298` stays green, unchanged, and a 12-set day reads `30 min`.
  - **Flag ON:** a day of the shipped Barbell Bench Press row (found by `exerciseId`; take its `rep_range` and type from the JSON), 4 sets, rest `150s`, plus its real warm-up items, reads the minutes `estimateDayMinutesFromPlanDay` computes. Compute the literal first from the row and `warmup_cooldown.dart` items (round-3 P2-2).
  - **Flag ON, home:** `home_screen` shows the same minutes for the same day.
  - **Flag ON:** adding one exercise raises the estimate by that exercise's own `exerciseSeconds`.
- [ ] **Steps 2–4.** Implement Ruling 13 behind `PlanEngineFlags.sessionSetBudgetEnabled`.
  - Parse `ExerciseData.rest` as digits, else 75.
  - A null `exerciseType` is treated as `['compound']`.
- [ ] **Step 5: Mutate.** Drop the rest term → the ON case FAILS.
- [ ] **Step 6: Commit** `feat(train): session estimate follows the budget model (ship-dark)`.

### Task 7: ON-world gate and report

**Files:** `test/plan_generator/session_set_budget_gate_test.dart` (`library;`, `@Timeout(Duration(minutes: 12))`, one `test()` per tier), plus the generated report.

- [ ] **Step 1: Write the gate.** Real `generateV4`, flag ON.
  - **Grid:**
    - 4 goals × 4 tiers × days {3,4,5,6} × 3 levels × phases {1, 4, 5} × minutes {30, 60, 90} = 1,728 runs;
    - plus 48 runs: build_muscle, all tiers, days and levels, phase 1, minutes null;
    - the core-list ON flag set for the build_muscle subset.
  - **Hard zeros:**
    - **Time:** sessions whose INDEPENDENT minutes exceed the user's minutes + 2. The oracle applies the Q4 constants to the final plan's sets and to each exercise's `restSeconds` as the plan carries it, over all 4 weeks, plus warm-up and cool-down (round-4 P2-1).
    - **Precondition (M6):** `2 × (days whose rank-0 credits a group) ≤` that group's weekly top, for every persona. Asserted. It checks bookkeeping, not the model's truth, and the report says so.
    - **Caps:** groups over the session cap (12 for focus) or the non-focus weekly top. A test-local mapper over raw `primary_muscles` counts them; it follows Ruling 12 and skips not-budgeted rows (round-3 P2-6).
    - **Lighter phase:** phase-4 weekly totals over the band bottom.
    - **Empty days:** strength days with no exercises.
    - **Forced:** `capForcedFirst`.
  - **Lead-lift count** (must be 0): a day's rank-0 exercise is removed, or holds < 2 sets, while the day ends with ≥ 5 min unused. The report adds how often rank 0 sits below `min(desired, cap)`, and which group's weekly top bound it (round-3 P1-1).
  - **Report** (written when `WRITE_SESSION_BUDGET_REPORT=1`):
    - median sets and minutes by minutes × days × level;
    - `belowFloor` labels per group;
    - `timeForcedFirst` counts;
    - focus weekly sets per split;
    - minutes unused per day;
    - the founder case: intermediate, build_muscle, full_gym, 6 days, 90 min, with focus none and with focus Chest, weeks 1–4.
- [ ] **Step 2: Run** with the report env → PASS. Record the founder case in the plan-review record.
- [ ] **Step 3: Mutate** the allocator's time check → the gate FAILS.
- [ ] **Step 4: Commit**.

### Task 8: Docs, registry, closure, gate loop, PR

- [ ] **SoT registry.**
  - New concept `session_set_budget`:
    - writer: the allocator;
    - readers: `apply`, titration, warm-up, display;
    - behavioural paths: Tasks 3, 4, 6b and 7.
  - New concept `session_duration_minutes`:
    - writer: `edit_profile_screen.dart:1874-1875`;
    - readers: `sessionMinutesFromProfile`, `pro_phase_advance.dart:215`, `simulation_service.dart:586`;
    - carried by `sync_profile.dart:243-244`, `sync_service.dart:1479` and `onboarding_provider.dart:889`, with allow-list `user_repository.dart:1471`.
  - Update `volume_titration`, `physique_focus_bringup`, `deload_working_base_stash` and `plateau_escalation`.
- [ ] **Docs.**
  - `plan_engine/CLAUDE.md`: the count table is OFF-only; one ON line per stage; the rule-14 waiver covered this batch only.
  - `docs/naming_conventions.md` §8: **set budget**, **session cap**, **weekly band**, **focus top**, **budget ledger**, and the four floor labels.
  - Spec §5: the constants and F2–F5.
  - Run `check_context_artifact_budget.dart`.
- [ ] **Ship-dark ledger.** Add the `docs/ship_dark_pending_review.yaml` entry.
- [ ] **Closure.** `docs/audit/session-set-budget.closure.yaml`:

  | item | terminal state |
  |---|---|
  | Tasks | `closed_in_commit` |
  | Ruling 6 (finisher reserve) | `upstream_blocked`; reopens when a screen shows the finisher |
  | Ruling 7 (rows stamped 90) | `upstream_blocked`; reopens at store launch |
  | `co_group_limited` / `time_limited` floors | `upstream_blocked`; reopen at the flip review, with the report as evidence |
  | `cap_limited` / `not_trained_by_split` floors | `verified_clean` |

- [ ] **Gate loop and PR.** Full gate loop (§4.12.8), B-pass, push, PR, `get_status` → `set_monitor`. The flip is a separate reviewed commit that deletes the OFF paths (§4.6 step 4).

---

## Round-2 resolution (b2_review2.md)

**P1:**
- **P1-A:** priority-rank admission (Task 3 step 4). Replay: first lifts at desired, 0 empty days. Covered by the `priority` test with the admit-all mutation, and by Task 7's primary-lift count.
- **P1-B:** `round-robin by rank` runs on a crafted week, with a sequential-days mutation. The `time` fixture removes caps and tops.

**P2:**
- 1: `debugLastStats`.
- 2: `lighterPhase` in the context and the ledger; pass D skipped; phase 4 added to the gate grid.
- 3: one `BudgetLedger`, plus the ledger-agreement test.
- 4: `timeForcedFirst` / `capForcedFirst`.
- 5: literals computed first; the real-persona focus test runs after Task 6.
- 6: four labels.
- 7: A first; B copies identical days.
- 8: stash = the same exercise's baseline.
- 9: `cascade_tracer` plus B1's trace.
- 10: the finisher is never shown, so no reserve (Ruling 6).
- 11: pin, injury, timed week-2, 2-set week-4 and cue tests.
- 12: warm-up legs asserted separately.
- 13: Forearms skip; titration evidence unchanged.

**Mechanical:** M1–M12 applied. M9: 48 runs. M6 and M7: Rulings 2 and 12.

## Round-4 resolution (b2_review4.md, verdict converged)

**P2:**
- 1: own rest for timed rows and day rest for rep-based customs; the oracle uses the plan's `restSeconds`.
- 2: reservation fixture and assertions.
- 3: stale `archetypeOfPlanned` and `reps` text removed; customs use `archetypeOfRow`; archetype-agreement test.
- 4: titration week-4 seeding and budgeted-only candidates.
- 5: label precedence, a test and a mutation.
- 6: one plan-day helper for Train and Home.

**Mechanical:** M1–M8 applied.

## Round-3 resolution (b2_review3.md)

**P1-1:** a rank-0 reservation in pass A; the gate counts lead lifts removed or under 2 sets; below-desired is reported. Covered by the `rank-0 reservation` test and its mutation.

**P2:**
- 1: not-budgeted rows timed at their own rest (Ruling 8), plus a test and a mutation.
- 2: archetype inputs come from the library row via `archetypeByName`; the display uses `exerciseId`; the fixture is a real row.
- 3: `home_screen.dart:905-919` shares `estimateDayMinutesFromPlanDay`.
- 4: the guard fixture uses timed rows.
- 5: the `cap_limited` definition is tightened.
- 6: the oracle mapper follows Ruling 12.
- 7: the ledger data flow is specified (Task 4).
- 8: Ruling 8 week-2 test and mutation.

**Mechanical:** M1–M8 applied.
