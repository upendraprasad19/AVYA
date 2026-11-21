> ✅ **SUPERSEDED 2026-09-12 — the banner below is HISTORY, not the current state.** It was written
> on 2026-09-10 after v3 failed round 3, and its forward-looking recommendation ("stop Unit 2") was
> NOT taken: the unit was re-planned from the window model up as **v4** (`oi166-unit2-plan-v4.md`,
> the exact first step this banner asks for), survived rounds 4-9 (`docs/plan-reviews/
> regen-wave-unit2-round{4..9}.md`), converged as **v10** (`oi166-unit2-plan-v10.md`), was
> implemented on 2026-09-11, B-pass-reviewed (`docs/reviews/9c7cbabe4d3d-review.md`) and is
> recorded in the keystone `docs/plan-reviews/regen-wave-unit2.md` (diagnose `d7f3b2`). This file is
> kept as-is below because the v2/v3 failure account — and the reason v3's text is gone — is real
> history the later versions build on. Do not implement THIS text; do read it before re-deriving
> why the window model came first.

> ⛔ **OI-166 UNIT 2 IS REJECTED — DO NOT IMPLEMENT ANY VERSION OF THIS PLAN.** *(2026-09-10 — see
> the superseding note above.)*
> Status: **NOT CONVERGED**, 2026-09-10, after three versions and three review rounds
> (six independent context-blind reviewers, all negative).
>
> **What the text below is.** This is **v2**, the last COMMITTED version, itself rejected in
> round 2 (`docs/plan-reviews/regen-wave-unit2-round2.md`). Its load-bearing claim — *"the window
> is always exactly four weeks"* — is **false**: `redoWeek4` extends `plan_end` without moving
> `plan_start`.
>
> **A v3 existed and is GONE.** It was written on 2026-09-10, reviewed in round 3, rejected, and
> then **destroyed by my own tooling error while I was adding this banner** — a Python
> `open(path, 'w')` truncated the file before an encoding error aborted the write, and v3 had never
> been committed. That is my mistake, not a process gap. Nothing else was lost.
>
> **Nothing of v3's substance is missing from the record.** Its design (anchor `plan_start`,
> explicit `weekCount = 4`, `nominalEnd = planStart + 27d`), every round-3 finding, and the reason
> it failed are all in `docs/plan-reviews/regen-wave-unit2-round3.md` — including the P0 it
> introduced: writes bounded at `planStart + 27d` against a delete loop bounded by `plan_end`
> (`workout_schedule_read_service.dart:358-377`), leaving **7 days of workouts deleted and never
> rewritten**, a regression `main` does not have.
>
> **Recommendation on the board: stop Unit 2, take the APK on what is already merged.** When
> OI-166 is re-opened, the FIRST step is what no version has done — model what the plan window
> actually IS (`plan_start`, `plan_end`, the delete range, every extension path) with the
> reachable states enumerated. All three failures are downstream of that document not existing.

# OI-166 Unit 2 — one schedule-row builder, used by all three writers

**Branch:** `regen-wave-unit2` · **Blast radius: MEASURE BEFORE DISPATCHING REVIEW.**
Do not copy a number into this header. `blast_radius_from_diff.dart` FAILS OPEN on paths that do
not exist yet, so a tier "verified" before the files are written is the path-glob tier, not the
real one. Unit 1's header carried `account` on exactly that mistake and was refuted by its own
positive control. Write the files, classify the ACTUAL staged list, then fill this in.

Expected `account` (`lib/core/services/**` and `lib/features/ai_coach/**` are both `account`,
`blast_radius.yaml:326`/`:235`) — **but that is a prediction, not a measurement.** If anything in
`lib/core/services/sync/**` enters the diff it becomes `platform` and pulls in the `feature_flag`
requirement that nothing enforces.

---

## Why this unit exists, in one paragraph

`RegeneratePlanPlanner` (C) is a hand-written COPY of `generateAndScheduleFromDate` (B), and its
own header asserts they match — *"Day-of-week pattern matches [_getDayPattern] EXACTLY"*, *"Mirrors
… keep these in sync"*. They do not. The inventory found **15 confirmed differences**, of which 7
are legitimate (they reduce to one fact: the coach previews before it writes; Edit Profile writes
immediately) and the rest are drift. Three plan-review rounds each discovered new divergences one
or two at a time, always while looking for something else. The fix is not to correct the copies. It
is to delete the copying.

## What Unit 1 already shipped (do not re-do)

The §4.11 detection gate (`check_single_schedule_row_builder.dart`, WARN-only), the
`rawWeekNumberFor` / `planWeekAndCharacterFor` extraction, the hotel planner's stamps, OI-170 and
OI-171. Unit 1 deliberately did NOT fix OI-166's filed symptom — that is item 5 below.

---

## 1. The design

```dart
/// PURE. No Hive read, no Hive write, no clock read. Everything it needs is a
/// parameter, which is what makes the three callers structurally unable to
/// disagree again.
List<ScheduleRow> buildScheduleRows({
  required Phase phase,          // carries weekPlans
  required DateTime planStart,   // Monday-normalised anchor; NEVER moves (decision 1)
  required int rawWeek,          // wave index of the FIRST emitted week — see P1-1
  required DateTime today,       // pre-today skip boundary ONLY, never a week count
  required int phaseNumber,
  required List<int> dayPattern,
  required Map<String, Map<String, dynamic>> existingRows,  // keyed yyyy-MM-dd
  required String generatedVia,  // provenance — see the guard-5 note in §4
  String? week4Character,        // caller reads currentWaveCharacters()[3] — see P1-2
});
```

`ScheduleRow` is a small class, NOT a raw map and NOT a list of dates:

```dart
class ScheduleRow {
  final String date;                       // yyyy-MM-dd
  final int week;                          // 1..4, plan-relative
  final String weekCharacter;
  final int dayOfWeek;                     // 0=Mon..6=Sun (the Unit 1 canon)
  final String workoutName;
  final List<Map<String, dynamic>> exercises;
  final bool isRest;
  final bool replacing;                    // preview-only
  final bool willSkip;                     // preview-only: completed, sacred
  Map<String, dynamic> toHiveMap();        // the ONE place a row map is built
}
```

**Why a class and not `List<Map>` or a `ScheduleRowPlan` of dates.** Round 5 killed the
date-list shape (P1-4): C's preview needs per-day exercises, and `RegeneratePlanDay.exercises` is
`required` and non-nullable. A row that already carries `exercises`, `workoutName`, `replacing` and
`willSkip` makes C's preview a **pure projection** of the builder's output rather than a second
computation — which is the whole point. `toHiveMap()` keeps map construction in one place so the
gate's two-key heuristic has exactly one legitimate site to allowlist.

## 2. The five P1s from round 5, each with its answer

| # | Finding (verified against source 2026-09-08) | Answer |
|---|---|---|
| P1-1 | A's loop is hard-coded `for (week = 0; week < 4; week++)` (`workout_schedule_read_service.dart:252`). Wiring `rawWeek: rawWeekNumber()` would make a missing-plan REPAIR emit 2-3 weeks and leave the earliest weeks missing. | **A passes `rawWeek: 1` explicitly.** `today: planStart` on A's path too, which makes the pre-today skip vacuous there — A is a first generation, nothing is in the past. |
| P1-2 | "Read week 4's character from the rows" is wrong for most of week 4. `_liftWeekFour` writes `working` onto a FILTERED subset (`deload_evaluator.dart:206-216` skips `type != workout` — i.e. REST rows — plus non-`planned`, `shortened_via`, `is_swapped`, past dates, and rows with no `working_sets` stash). The first week-4 row is often a Monday rest day → reads back `deload` → silently discards the lift. | **Caller reads `currentWaveCharacters()[3]`** (`:1330`, a pure blob read) and passes it as `week4Character`. The blob is the SoT for wave character; the rows are a projection of it. |
| P1-3 | `_liftExercise` is private, instance-level, and `deload_evaluator.dart` has no `part of` (`:294`). A new file cannot call it. | **Extract `liftExerciseFromStash(Map) → Map` as a public pure top-level function** in the plan-engine layer; `deload_evaluator` and the builder both call it. Pure, no Hive, trivially testable. |
| P1-4 | `ScheduleRowPlan` cannot rebuild C's preview — `displayExercises` is built at `:250` for EVERY day including completed ones (the `!isCompleted` gate is at `:274`), and `RegeneratePlanDay.exercises` is required non-nullable. | Solved by the return type in §1. The preview becomes `rows.map(toRegeneratePlanDay)`. |
| P1-5 | §9 had no implementation step for two DECIDED subsystems — Q6's apply-time re-run and the deload dual write. | Steps 4 and 6 in §5 below. Named, sequenced, and each with its own test. |

## 3. A sixteenth difference, found while grounding this plan (2026-09-08)

The inventory recorded *"`finisher` is written by `generateAndSchedule` (A) and NOT by
`generateAndScheduleFromDate` (B)"*. That is true but incomplete: **C writes it too**
(`regenerate_plan_planner.dart:291-293`, same shape as A's `:285-287`). So it is not A-vs-B — **two
of the three write it and B is the outlier**, which is a stronger argument for the builder than the
inventory made.

Still LATENT, re-verified here rather than taken on trust: `grep -rn "\['finisher'\]" lib/` → **0**,
positive control `['warmup']` → **3**. The 53 other `finisher` hits are the plan-engine's own
generation code plus three COMMENTS. ⚠ One of those comments
(`preview_plan_provider.dart:139`) says the finisher is *"shown separately in the preview"* — and
nothing in that file does so. Not this unit's problem; noted so it is not mistaken for a reader.

**Decision: the builder emits `finisher` uniformly.** Zero risk (no reader), closes B's gap, and
matches the majority of existing behaviour.

## 4. The deload dual write

A lift is a **DUAL write** — rows (`deload_evaluator.dart:223`) AND the blob (`:264`, labelled
*"Dual-write the current_plan blob's deload week"*). A fresh phase always carries `deload` at
`week_plans[3]` (`periodization_engine.dart:164`, unconditional). So "preserve the character on the
rows, overwrite the blob" would re-create **exactly the bug Unit B shipped 2026-09-06 to fix**.

Ordering, explicitly, because this is where round 4 went wrong:
1. READ `currentWaveCharacters()[3]` **before** anything is overwritten.
2. Pass it to the builder as `week4Character`.
3. Builder stamps it on week-4 rows, and emits the WORKING exercise variant via
   `liftExerciseFromStash` when it is `working`.
4. Caller writes rows, THEN writes the blob with the same character.
5. Caller fires the narrow plan push — Unit 1's OI-171 fix, already live.

⚠ **`generated_via` must survive the merge.** `deload_evaluator` guard 5 refuses an un-deload on
rows stamped `ai_coach*`. Unify provenance carelessly and that guard silently stops firing — a
guard that stops firing is invisible, so this needs its own test asserting the guard still refuses.

## 5. Sequencing — ONE branch, ONE push, ONE APK

Founder locked (2026-09-08): Unit 2 lands before the APK, and everything ships in a single +40.
§4.3's rule that sequential slices of one feature consolidate into one push/CI/APK cycle applies,
so these are commits, not pushes.

1. **`liftExerciseFromStash` extraction** + tests. `deload_evaluator` calls it. No behaviour change;
   mutation-proven that the stash mapping is unchanged.
2. **`schedule_row_builder.dart` + `ScheduleRow`** — pure, fully tested, called by NOBODY. Byte-
   identical-output tests against each caller's current behaviour are written HERE, before any
   caller moves.
3. **Wire B** (`generateAndScheduleFromDate`) behind `disable_shared_schedule_builder`. B is the
   best-tested path and the simplest. Kill-switch default ON (fix live), legacy path preserved.
4. **Wire C** (the coach) — including the preview projection AND the `current_plan` write that
   **fixes OI-166's filed symptom**. Q6's apply-time re-run lands here.
5. **Wire A** (`generateAndSchedule`) with `rawWeek: 1`, `today: planStart`.
6. **The deload dual write** through the builder (§4).
7. **Flip `check_single_schedule_row_builder.dart` to hard-fail** and remove both `pendingUnit2`
   allowlist entries. This is the commit that proves the de-duplication actually happened — the
   gate cannot go green while a fourth implementation survives.

Step 7 is the forcing function. If it cannot go green, the unit is not done.

## 6. Q7 — the open design question (founder)

Bounding a regen's writes at `plan_end` means a `switch_goal` no longer refreshes orphan rows past
it, so those keep **old-goal** workouts where today they are rewritten. Options: (a) accept until
OI-174's prune; (b) extend the regen's delete range past `plan_end` to cover existing forward rows.
**Lean (b)** — a regeneration leaving stale forward workouts contradicts what the user asked for,
and "rows this regen is replacing" is a smaller claim than a global prune. Needs a founder answer
before step 4.

## 7. Tests (each mutation-proven, each mutation leaving the file COMPILING)

- Pure builder: week-boundary straddle, `rawWeek` 1..4 and >4, completed-day preservation, pre-today
  skip with workout-index advance, empty `dayPattern`, short/absent `weekPlans`.
- **Byte-identical-output tests per caller** — the ship-dark discipline: with the flag OFF the
  three callers must produce output identical to today's. This is what makes steps 3-5 safe.
- P1-2 regression: a week-4 whose FIRST row is a rest day, with the blob saying `working`, must
  still emit `working` on the workout rows. This is the test that fails under the round-4 design.
- `generated_via` provenance: `deload_evaluator` guard 5 still refuses an un-deload on `ai_coach*`.
- Gate flip: step 7's commit must show the gate hard-failing on a planted fourth implementation.

## 8. Explicitly NOT in this unit

- **OI-174** (past-`plan_end` prune) — a DESTRUCTIVE migration over existing user rows, its own
  blast radius, its own founder question. On the board.
- **OI-175** (`rawWeek > 4` semantics) — carries founder Q5, and is sequenced after OI-174 because
  round 2 proved the two are not separable. On the board.
- **OI-176** (the vacuous-PASS collision gate) — founder decided 2026-09-08 it stays on the board.
- **The gate's named-constant residual** — closed structurally by step 7, not by more regex.

---

## Review plan

×2 context-blind rounds per §4.12.1, round 2 on the hardened plan. ⚠ **This unit failed to converge
across five rounds already.** If round 1 surfaces new *material design* issues rather than citation
errors, split again at step 3/4 and ship the smallest converged piece — do not push through to a
seventh round. Run `sh scripts/pre-commit.sh` before dispatching any round that has a draft diff:
roughly half of Unit 1's 17 findings were mechanical things a gate already catches.
