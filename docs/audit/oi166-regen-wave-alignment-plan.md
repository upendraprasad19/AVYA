# OI-166 — one schedule-row builder, and the wave alignment that falls out of it

**Branch:** `regen-wave-alignment` · **Blast radius: `platform`** — measured against the ACTUAL
staged file list on 2026-09-08 (`git diff --cached --name-only | dart run
scripts/blast_radius_from_diff.dart -` → `platform`).

⚠ **This header said `account` until 2026-09-08, and its own parenthetical was the tell.** It
justified `account` by citing *"positive control `sync_workout.dart` → `platform`, so the
classifier discriminates"* — a control that only works while that file is OUT of the diff. Folding
in OI-170 (§10) put it IN, so the sentence proving the tier became the sentence refuting it. The
number was never re-derived against the real file list; it was carried forward from a measurement
of a planned file set that the batch then outgrew.

`platform` requires the ×2 plan review, a self-initiated B-pass before the merge (§4.3), AND a
**`feature_flag`** (`docs/blast_radius.yaml:25`). Nothing enforces that last one mechanically —
`check_blast_radius_coverage.dart` does not read the `requires:` list — so the whole gate loop ran
green without it and the B-pass is what caught the gap. Kill-switch:
`disable_day_of_week_derive`.

---

## ⚠ STATUS 2026-09-07 — SPLIT AFTER ROUND 5 (§4.12.1)

**Five review rounds, none converged.** Round 1: 11 findings. Round 2: 5 new P1s *inside round 1's
corrections*. Round 3: 2 P1 + 6 P2. Round 4: 5 P1 + 5 P2. Round 5: 7 P1 + 9 P2, **four of the P1s
inside round 4's own remediations**. §4.12.1: *"When successive reviews keep surfacing new material
issues, that is the signal the unit is too large — split it and ship the smallest converged piece,
don't review the large thing a fifth time."*

Round 5 independently recommended the same split point this session had already committed to.

| | Scope | State |
|---|---|---|
| **UNIT 1 — ships now** | §9.1 the gate (warn default) · §9.2 `rawWeekNumber()` · §9.3 implementation D's stamps | **Converged.** Round 5 found nothing blocking in any of it; its one defect here (P1-5, D's stamps read the wall clock) is fixed below. Each piece is independent of the others and of the builder |
| **UNIT 2 — re-planned from scratch** | §9.4–§9.7: `buildScheduleRows`, callers A/B/C, the deload dual write (§4a), the coach blob write (§5), Q6's apply-time re-run | **Not converged.** Every unresolved P1 lives here. Re-planned against §17's findings, then reviewed ×2 from the corrected plan — NOT a sixth round on this text |

⚠ **UNIT 1 does NOT fix OI-166's filed symptom.** The stale phase-arc is caused by the coach never
writing `current_plan`, which is Unit 2's §5. Unit 1 ships the guard that makes the class
detectable, the week-number primitive Unit 2 needs, and a real but separate defect in the hotel
planner. Sequencing this against the pending APK is a founder decision, recorded rather than
assumed.

⚠ **No closure ledger yet, deliberately.** Round 5 (P2-15) is right that §4.2's structural
`closed==N` invariant binds a batch this size. But §4.10 is explicit that the ledger is validated
on **every commit repo-wide**, so *"do not create it until every finding is terminal — a half-filled
ledger blocks a concurrent session's commits too."* It is created when Unit 1 lands, covering
Unit 1's items, and extended when Unit 2 lands.

§§0–11 are the spec. §§12–17 are the record of all five rounds.

---

## 0. What this does, and why the shape changed

Three review rounds each found *new* ways the AI-coach planner diverges from the canonical
scheduler — one or two at a time, always while looking for something else. The cause was not the
design (all three rounds confirmed the diagnosis and the arithmetic). It was that **nobody had an
inventory**, so every round wrote a rule against an incomplete picture of what it had to be true for.

The inventory now exists — `docs/audit/oi166-regen-implementation-inventory.md`: **17 numbered rows
— 8 real drifts, 7 legitimate seams, 2 withdrawn as phantom** (rounds 4 and 5 both re-derived these
counts). All 7 seams reduce to one fact: *the coach previews before it writes; Edit Profile writes
immediately.*

**Founder decision, 2026-09-07: one logic, implemented once, used by both.** So this unit is a
de-duplication that makes the wave-alignment bug — and eight of its siblings — structurally
impossible, rather than a layout patch applied twice.

**Live defects closed:**

1. The phase-arc strip highlights the wrong node after any mid-phase regen.
2. The Home today-card shows the wrong week number (`row['week']` from the loop index).
3. The coach schedules workouts on the **wrong weekdays** (Monday-indexed pattern applied as an
   offset from an arbitrary start).
4. The coach **ignores `preferred_training_days` entirely.**
5. ~~The coach drops 4 of 10 `PlanGenerator` inputs (`bodyFocus`, `sessionDuration`,
   `cardioPreference`, `preferredDays`).~~ ⚠ **RESTATED (round 5, P1-7) — the original count was
   inflated three ways.** `preferredDays` is defect 4, counted twice. `bodyFocus` and
   `cardioPreference` are supplied by **no live caller anywhere**: repo-wide,
   `grep -rn "bodyFocus:\|cardioPreference:" lib/` returns only pass-throughs
   (`workout_schedule_read_service.dart:211/:213`, `:351/:353`, `:584/:586`;
   `workout_schedule_service.dart:100/:102`, `:127/:129`, `:153/:155`;
   `plan_engine/plan_generator.dart:67/:69`, `:265`, `:327`) — every real argument site is in
   `test/`, and `test/contracts/cardio_goal_default_test.dart:4` says outright *"there is no
   cardioPreference UI/field"*. `bodyFocus` is resolved internally anyway
   (`plan_engine/plan_generator.dart:249-255` reads the profile when the override is empty). **The
   real gap is `preferredDays`, plus `sessionDuration` — which no regeneration path supplies today,
   canonical or coach.** Kept visible rather than quietly deleted, because "10 arguments" was the
   headline number in three rounds of review and someone will look for it.
6. The coach never writes `current_plan` — OI-166 as originally filed. **This is the one the
   founder reported, and it lives in UNIT 2.**

## 1. The implementations

| | Function | Used by | Changes here |
|---|---|---|---|
| **A** | `generateAndSchedule` — `workout_schedule_read_service.dart:170-320` | onboarding, phase advance, missing-plan repair (6 call sites) | adopts the shared builder |
| **B** | `generateAndScheduleFromDate` — `:325-521` | Edit Profile (`edit_profile_screen.dart:2029`) | adopts the shared builder |
| **C** | `RegeneratePlanPlanner.plan` — `regenerate_plan_planner.dart:135-340` | coach `regenerate_plan_block` AND `switch_goal` | adopts the shared builder |
| **D** | `HotelWorkoutPlanner` — `hotel_workout_planner.dart:179-199` | coach `generateHotelWorkout` | **stamps corrected; does NOT adopt the builder** (§8a) |

⚠ **A is in scope.** The founder's framing is B-vs-C, but the inventory found A and B disagree too
(`finisher` written at `:285-287`, absent from B). Leaving A out would keep a third variant alive
and re-open the class the moment someone touches it.

⚠ **A is NOT a no-op conversion, and the earlier claim that it was is withdrawn (round 4).** This
section previously read *"A's callers re-anchor `plan_start` (`:225-227`) so they compute
`rawWeek == 1` and their behaviour is unchanged"*. Both halves are false, verified:

- **Not all callers yield `rawWeek == 1`.** `auth_session_bootstrapper.dart:646-649` anchors on
  `resolvePlanRegenStart(hiveIso: getPhaseStartedAtIso(), now: …)`, which returns the parsed
  `phase_started_at` **verbatim** (`:134-135`). A then writes
  `plan_start = _normalizeToMonday(phase_started_at)`, so a mid-phase login-restore computes
  `rawWeek` of 2, 3 or 4. The OI-150 comment at `:620-631` says this historical anchoring is
  deliberate.
- **`rawWeek == 1` would not make the pre-today skip inert anyway.** A's write loop (`:259-315`)
  has **no `isBefore(today)` guard and no completed-row check at all** — it upserts every one of
  the seven days and relies on `upsertScheduled`'s planGenerator refusal
  (`workout_write_service.dart:544-556`) to protect completed rows. And the onboarding default
  start is `this_monday`, which `onboarding_provider.dart:262-264` resolves to **this week's**
  Monday — in the past for any mid-week onboarder. So A really does write pre-today rows today.

**Consequence for the design: A passes `today: planStart`.** That makes the builder's pre-today
skip vacuous on the A path, preserving A's current behaviour exactly. It also means §2's "every
caller supplies `today` from one place" is about a single *parameter*, not a single *value* — A
deliberately supplies its window start rather than the wall clock. Stated here because a reader who
assumes A passes the real today will conclude the conversion is safe when it is not.

⚠ **One more A-path behaviour to preserve:** because A has no completed check of its own, the
refusal at `upsertScheduled` emits `upsert_scheduled_skipped_completed_day` telemetry on every
completed day it walks over. If the builder filters completed rows out before the write, that event
stops firing. A's conversion must keep emitting it (T14).

## 2. The shared core

```dart
// lib/core/services/schedule_row_builder.dart  — NEW, pure
class ScheduleRowPlan {
  final List<Map<String, dynamic>> rows;      // what to write
  final List<String> skippedCompletedDates;   // completed days walked over
  final List<String> replacedDates;           // existing non-completed rows overwritten
  final int additionalWorkoutDayCount;        // weeks 2..N, for the coach's diff footer
}

ScheduleRowPlan buildScheduleRows({
  required Phase phase,          // the generated 4-week phase
  required DateTime planStart,   // Monday-normalized, from plan_start_date
  required int rawWeek,          // 1..4 — the plan week to start at
  required DateTime today,       // supplied by the caller; this function reads NO clock
  required int phaseNumber,
  required List<int> dayPattern, // preferredDays ?? _getDayPattern(daysPerWeek)
  required Map<String, Map> existingRows,  // date-key → row, for completed/skip decisions
  required String? generatedVia, // null for A/B; 'ai_coach_regenerate' for C
  required String? preserveWeek4Character,  // 'working' when a deload was lifted (§4)
});
```

**Pure by construction — no Hive writes, no clock reads.** That is what makes it directly unit
testable and what removes the three-clock problem (§3a).

⚠ **`today` is a PARAMETER supplied by each caller, not one shared value.** B and C pass the real
today; **A passes `planStart`** (§1), which makes the pre-today skip vacuous on its path and keeps
its current behaviour. The invariant the builder buys is that the branch decision and the date
arithmetic use the *same* value as each other — not that all three callers use the same value.

⚠ **The return type is a record, not a bare row list (round 4, P2-7).** C's preview needs the
skipped days, the replaced days and `additionalWorkoutDayCount` — `regenerate_plan_planner.dart`
emits a `firstWeekDisplay` entry for a completed day (`:249-267`, `willSkip: isCompleted`) while
**excluding** it from `rawSchedules` (`:274`), so those days are unrecoverable from the written
rows alone. A bare `List<Map>` return would force C to keep a second pass over `existingRows` and
re-derive them — a fourth copy of the very logic this batch exists to remove.

### What collapses INTO the builder

⚠ **Corrected by round 4.** This section previously claimed inventory rows 1, 2, 3, 5, 6, 7, 8, 9,
10 all collapse and that "drift becomes impossible". Three of those are wrong, and the overclaim
matters because this list *is* the argument for the design.

**Genuinely structural** — the builder computes it, so no caller can get it wrong: rows **1, 5, 8,
9, 10** (Monday anchoring · the pre-today skip · the clock · `finisher` · the `workout_name`
fallback).

**Reduced to one call signature, NOT made impossible**: rows **2 and 3**. The builder receives a
finished `Phase` and a finished `dayPattern`; both are computed at the caller
(`PlanGenerator.instance.generate` at `read_service.dart:196-211` (A, 14 args), `:342-354` (B, 10),
`regenerate_plan_planner.dart:190-197` (C, 6); `dayPattern` at `:220`, `:433`, `:206`). A pure
function handed a finished `Phase` cannot police which arguments produced it. So **§0 defects 4 and
5 are fixed by editing C's caller** — exactly as a layout patch would have — and what the design
buys is *visibility at one signature*, not impossibility. §8's gate keys on row construction and
cannot see a divergent `generate()` call; §9.5 therefore makes the argument set an explicit
conversion step with its own test (T15), rather than assuming it away.

**Withdrawn — never differences**: rows **6 and 7**. `workoutDayIndex++` at
`regenerate_plan_planner.dart:241` is unconditional inside the `isWorkoutDay` branch, 33 lines
above the `isCompleted` gate at `:274`, so C already advances across completed days exactly as B
does at `:455-462`.

**Net: five rows become structurally impossible, two become visible at one signature, two were
phantom.**

### What stays at the callers (the legitimate seam)

| Concern | A | B | C |
|---|---|---|---|
| Delete stale rows first | no | yes `:362-376` | no — it previews |
| Write timing | inline | inline | cache → write on Confirm |
| `plan_start`/`plan_end` | always `:225-226` | first-gen only `:382-386` | never |
| `current_plan` blob | yes `:227` | yes `:388` | **yes — NEW** (§5) |
| Sync trigger | yes | `:389-390` | dispatcher's |
| Week count | 4 | 4 | `weeks.clamp(1,12)` → bounded by the phase end (§6) |
| `generated_via` stamp | absent | absent | **`'ai_coach_regenerate'` — MUST SURVIVE** (§7.2) |

## 3. The alignment rule

### 3a. One week number, one clock

```dart
int rawWeekNumber() {                       // NEW, no clamp
  final startStr = MigratedKey.read<String>(_planStartKey);
  if (startStr == null) return 1;
  final planStart = DateTime.parse(startStr);
  return nowWall().difference(planStart).inDays ~/ 7 + 1;
}
int getCurrentWeekNumber() => rawWeekNumber().clamp(1, 4);   // behaviour unchanged
```

Round 3 verified this refactor is behaviour-preserving across all 12 `getCurrentWeekNumber()`
callers, and that `startStr == null → 1 → clamp → 1` is identical.

⚠ **`nowWall()`, not `istMidnight`, and not `DateTime.now()`.** There are three clocks today —
`nowWall()` (`:1261`), `istMidnight(fromDate)` (`:357`), and C's raw non-seam-aware
`DateTime.now()` (`:387-389`). Round 2 caught the first-vs-second confusion; round 3 caught the
third. The builder taking `today` as a **parameter** is what forces each caller to name one source.

### 3b. Layout

For `1 ≤ rawWeek ≤ 4` the builder emits `phase.weekPlans[rawWeek-1 .. 3]` over plan weeks
`rawWeek..4`, where plan week `k` occupies `planStart + (k-1)*7 … +6`; stamps `'week': k` (the
plan week, §3c); emits no row dated after `plan_end`; skips dates before `today`; and preserves
`completed` rows while still advancing the workout index across both kinds of skip.

Round 3 verified the arithmetic for `rawWeek` = 1, 2, 3, 4, and that `plan_start` is a Monday from
every writer — so `planStart + (rawWeek-1)*7 == _normalizeToMonday(today)`, and the delete range
`[today, plan_end]` is a subset of the write range in every case.

**Outside `1 ≤ rawWeek ≤ 4` → today's behaviour, verbatim.** ⚠ Round 3 corrected the justification
the draft used: *"today's code always rewrites what it deletes"* is **false** — `:374-376` deletes
`displaced_*` unconditionally with no restore, which OI-175 already records. The true, narrower
statement: **the fallback is byte-identical to today, including today's own `displaced_*`
violation, which OI-175 owns.** The core unit neither introduces nor fixes it.

⚠ **Stated precondition, which nobody had written down:** the delete range is bounded by
`plan_end` (`:362`) and the new write range by `plan_start+27`, so the rule requires
`plan_end ≤ plan_start + 27`. `redoWeek4` grows `plan_end`
(`workout_schedule_write_service.dart:213-214`) and `plan_window_reanchor.dart:58-59` keeps the
later value — which is exactly the `rawWeek > 4` state the fallback covers. T7 pins it.

⚠ **"by 7 per call" was imprecise** (round 4): `rollStart = todayMidnight.isAfter(planEnd) ?
todayMidnight : planEnd + 1` (`:187-189`), then `newEnd = rollStart + 6`. After a long gap the jump
is from *today*, not from `plan_end`, so it can exceed 7 — which widens the `rawWeek > 4` window
rather than narrowing it, so the fallback still holds, but a test fixture built on "+7 per call"
would model the wrong state.

### 3c. The `'week'` stamp — six readers

`hold_week_labels.dart:133`, `:146` (Home card, day-detail) · `train_provider.dart:618, 622`
(`dayNumber` → `'D$n'`) · `week_selector.dart:341` · `sync_workout.dart:1619` (**cloud push**
`'week_number': entry['week']`) and `:1975-1976` (restore, `'week': map['week_number']`).

Round 3 verified the round-trip is consistent and that the change **improves** it; that cloud
`week_number` is a bare nullable int with no CHECK
(`supabase/migrations/002_create_fitness_tables.sql:103`); and that **no Edge Function reads it**
(`grep -rn "week_number" supabase/functions/` → 0, with `scheduled_workouts` as a positive control
returning 5). Also verified NOT affected: `getWeek` is date-driven (`:1070-1085`), so
`deloadPhaseFromWeek4`, `currentDeloadReason`, `currentPhaseCompletionRate` never read the stamp.

⚠ **The WRITER census was incomplete — three more, found by round 4.** `:414` (`'week': 1`, the
"Joined later" backfill row) is first-generation only. But `workout_schedule_write_service.dart`
holds two more: `:285` `copy['week'] = 4 + n` (holdWeek — behind `enable_hold_weeks`, currently
OFF) and **`:417` `..['week'] = targetWeek` (`copyWeek`, LIVE**, reachable from
`train_provider.dart:866-874`).

⚠ **`copyWeek` matters beyond the census.** It carries the source week's `week_character` forward
unchanged, so copying week 3 onto week 4 leaves rows saying `peak` while the blob says `deload` —
the exact rows-vs-blob disagreement §4 is built to prevent, arriving by a different door. Out of
scope for this batch (it is not a regeneration path) but named here so the §4 invariant is not
mistaken for airtight.

⚠ Note also that B's entire `isFirstGeneration` branch (`:382-386`, `:394-399`, `:400-425`,
including `:414`) is **unreachable from B's only live caller** — `edit_profile_screen.dart:2029`
runs after onboarding, so `plan_start_date` always exists, and onboarding itself uses **A**
(`onboarding_provider.dart:554`). §9.5 decides explicitly whether the de-dup keeps or drops it
rather than carrying it silently.

## 4. The deload interaction — a DUAL write

A regen **reads** the deload decision, never re-runs it; `deload_evaluated_for_phase_<N>` is never
cleared.

⚠ **Round 3 P1-1, and this is the one that would have re-created the bug Unit B shipped yesterday
to fix.** Lifting a deload writes **both** the rows (`deload_evaluator.dart:223`) *and* the blob
(`:245` — the code labels it `// 2. Dual-write the current_plan blob's deload week`). A freshly
generated phase always carries `deload` at `week_plans[3]`
(`periodization_engine.dart:164`, unconditional). So preserving `working` on the rows while
overwriting the blob would leave rows=`working`, blob=`deload` — the strip renders a deload node
over a working week and the reason line silently vanishes.

**Therefore:** when week 4's current character is `working`, the regen writes `working` to **both**
the rows and the new blob's `week_plans[3]`, in the same operation — and the old character must be
read **before** the blob is overwritten. T5 asserts `currentWaveCharacters()[3] == 'working'`, not
only the rows.

### 4a. Who owns which half (round 4, P1-5)

The dual write straddles the seam, so the split must be stated or each side will assume the other
did it:

1. **The CALLER reads first.** Before touching anything it reads week 4's current character —
   from the existing rows, which is where `deload_evaluator.dart:223` wrote it — and passes it in
   as `preserveWeek4Character` (§2's signature). Reading before writing is the caller's job because
   the caller is the only side that knows the blob is about to be overwritten.
2. **The BUILDER stamps the rows.** Given `preserveWeek4Character == 'working'`, it emits
   `week_character: 'working'` on plan-week-4 rows and applies `_liftExercise`'s rewrite
   (`deload_evaluator.dart:280-291`) to them.
3. **The CALLER writes the blob**, using the same value it read in step 1, in the same operation
   that writes the rows.

**Ordering is load-bearing**: read (1) strictly before write (3). A caller that overwrites the blob
first has destroyed the only record of the lift.

⚠ **A is in this too, and the earlier draft never said what it does.** This section scoped itself
to "the regen" (B and C), but `plan_engine_flags.dart:225-231` names **both** blob-rewriting paths
— `generateAndScheduleFromDate` (`:388`) *and* `generateAndSchedule` (`:227`). A's login-restore
call site (§1) regenerates the **current phase's own window**, exactly where a lifted week 4 can
exist. **A passes `preserveWeek4Character` on the same terms as B.** Its other five call sites
(onboarding, phase advance) start a fresh phase where no lift exists, so the value is `null` there
and the branch is inert — but it must be wired, not omitted.

**Q1 decided, with round 3's correction to the mechanism.** Re-derive the working variant from the
**newly generated** phase rather than re-reading the old stash (on `switch_goal` the stash holds the
OLD exercises). ⚠ The draft said "the same `_applyWave(…, 2, …)` shape" — that method is `static`
and **private** (`periodization_engine.dart:175`) and cannot be called. The implementable form:
the new phase **already carries the stash** — `PlannedExercise.toMap()` emits
`working_sets`/`working_reps` (`lib/shared/repositories/plan_engine/models.dart:236-237`) whenever
`stashWorkingBase` is set (`periodization_engine.dart:126` ←
`lib/shared/repositories/plan_engine/plan_generator.dart:270`) — so apply `_liftExercise`'s rewrite
(`deload_evaluator.dart:280-291`) to the **new** rows.

⚠ Both filenames are ambiguous and must be cited in full: a second `plan_generator.dart` exists at
`lib/shared/repositories/`, where `stashWorkingBase` returns **zero** hits.

## 5. The coach becomes a `current_plan` writer

This is OI-166's originally-filed symptom and it needs its own naming, not a clause.
`RegeneratePlanPlanner.plan()` returns `(plan: RegeneratePlanResult, rawSchedules: …)` and
`RegeneratePlanResult` (`:330-337`) carries **no `Phase`**. The dispatcher writes only rows
(`tool_dispatcher.dart:853-880`, `:1009-1035`). So the generated `Phase` must be threaded out of
`plan()`, through the cache, to the apply step.

Because the coach now supplies the full `PlanGenerator` argument set (§0 defect 5), its blob is no
longer strictly poorer than the one it overwrites — which is what makes this safe to do at all.

⚠ **The blob write must fire the sync fan-out explicitly (round 4, P2-6).** `sync_workout.dart:1045-1056`
builds `plan_json` from the `current_plan` blob, and the two **regeneration** blob writers each pair
their `workoutBox.put(_planKey, …)` with `unawaited(SyncService.instance.syncWorkoutData())` —
`read_service.dart:227` followed by `:246-247`, and `:388` by `:389-390`.

⚠ **"every existing blob writer" was false and is withdrawn (round 5, P2-9).** There are **four**
(`grep -rn "put(_planKey\|put(_kPlanKey\|put('current_plan'" lib/`): the two above,
`sync_workout.dart:1108` (the restore, correctly firing nothing), and **`deload_evaluator.dart:264`,
the deload lift, which fires only `pushSnapshot()` at `:273`**. The requirement below still stands;
the universal offered as its justification did not. ⚠ Round 5 further concluded the lifted blob
*"never reaches `plan_json`"* — **that overreached and was corrected on verification**: the lift's
row writes go through `upsertScheduled`, which fires `syncWorkoutData()` itself
(`workout_write_service.dart:566`). The real defect is an ORDERING one — those fan-outs run *before*
the blob write at `:264` — and is filed as **OI-171**, not fixed here.

The coach's blob write
lands in `tool_dispatcher.dart`, which sits **outside** the five-file union pinned by
`test/contracts/workout_schedule_service_uses_write_service_test.dart:47-51` (exact `putCount == 4`
and `>= 3` fan-out assertions). Without an explicit fan-out the coach's blob never reaches the
cloud, and OI-166's filed symptom — a stale phase-arc — returns after the next restore. The
contract test gains a row for the dispatcher's blob write (T16).

## 6. Coach truncation

Enforcement is the **silent** clamp at `regenerate_plan_planner.dart:143`
(`final n = weeks.clamp(1, 12);`); `:61` is only a doc comment. `RegeneratePlanResult` is built at
`:330-337` with only `totalWeeks: n`, so stating a truncation needs a new **requested-vs-granted**
field — a signature change, not copy.

Copy must reach all six card strings: `regenerate_plan_diff.dart:108`, `:126`, `:138-139`;
`switch_goal_diff.dart:153-154`, `:165`, `:178`. ⚠ `switch_goal_diff.dart:54` defaults `weeks` to
**4**, so a `switch_goal` in plan week 3 would claim 4 and write 2.

- **Card context line:** `Rest of phase rebuilt — 3 weeks`
- **Coach reply** (model-generated ⇒ a prompt / tool-result instruction): *"Rebuilt the rest of
  this phase — 3 weeks, through 27 Sep. Weeks beyond that come with your next phase."*

**Q2 (founder default, reversible):** a request SHORTER than the remaining weeks rounds **up** to
the phase end. ⚠ Recorded cost: this makes `weeks` inert for short requests (always `5 − rawWeek`),
so the tool schema and prompt must say so.

## 7. What must not break

1. **Completed history** — `:365-372` deletes only non-`completed`; `:455-462` skips them.
2. ⚠ **`generated_via` MUST survive the merge.** `deload_evaluator.dart` guard 5 refuses an
   un-deload on any week-4 row whose `generated_via` starts `ai_coach`. Unifying the two paths into
   identical provenance would silently stop that guard firing. Its *reason* goes away once coach
   weeks are aligned, but **removing the guard is a separate decision** (§10) and removing the
   stamp is not the same thing.
3. **`plan_start` / `plan_end` unchanged by a regen** — the four writers of `_planStartKey` are
   `:225`, `:385` (first-gen only), `plan_integrity_reconciler.dart:286`, `sync_workout.dart:1126`.
   This unit adds none.
4. **`PlanGenerator` untouched** — coding rule 14.
5. **Rest rows keep `week_character`** (`regenerate_plan_planner.dart:358`). ⚠ Round 3 corrected
   the *reason*: the `type == 'workout'` filter runs first, so rest rows are invisible to guard 6.
   The requirement stands; the old justification was wrong. ⚠ Round 4 corrected the CITATION on
   that very line: guard 6 is `deload_evaluator.dart:92-97` and its filter `:88-89`; `:198-206` is
   `_liftWeekFour`'s own filter. True at both, but naming the wrong construct on a line that
   advertises itself as a correction is its own trap.
6. **The 12 `getCurrentWeekNumber()` callers** — round 3 enumerated them; none changes.

## 8. The gate, before the refactor (§4.11)

This refactor touches a known bug class (writer/reader drift), so per §4.11 the detection gate
lands in an **earlier commit** than the first refactor commit:

`scripts/check_single_schedule_row_builder.dart` — asserts that only
`schedule_row_builder.dart` constructs a schedule-row map (keyed on the co-occurrence of
`'week_character':` with `'day_of_week':` in a map literal outside the builder). Ships
**mutation-proven** per rule 24 with a `docs/audit/gate_test_ledger.yaml` entry.

⚠ **`--warn-only` must be the script's built-in DEFAULT for the baseline window, not a flag passed
at the call site.** Both `scripts/pre-commit.sh:324` and `.github/workflows/test.yml:234` auto-wire
every `scripts/check_*.dart` by glob, so the gate is live from the commit it lands in and nothing
passes it arguments. §9.1 lands it defaulting to warn; §9.7 flips the default.

⚠ **The gate's input set is `lib/` ONLY, and this is load-bearing (round 5, P2-11).** Run
repo-wide, the heuristic returns **five** files — the three in `lib/` plus
`test/contracts/deload_eval_behavioral_test.dart` and
`test/contracts/deload_reason_staleness_behavioral_test.dart`, which legitimately seed schedule
rows in fixtures. Every behavioural test Unit 2 adds (T2, T5, T6, T7, T8, T11, T14, T17) will match
too. Unscoped, the hard-fail flip would break the build on the batch's own tests. Verified by
running it both ways:

```
$ grep -rl "'week_character':" lib/ | xargs grep -l "'day_of_week':"     → 3 files
$ grep -rl "'week_character':" . --include=*.dart | xargs grep -l "'day_of_week':"  → 5 files
```

### 8a. The gate already has a violation — implementation D

⚠ **Round 4 ran the proposed heuristic and it returns a FOURTH file** that no earlier round and no
version of the inventory named:

```
$ grep -rl "'week_character':" lib/ | xargs grep -l "'day_of_week':"
lib/core/services/workout_schedule_read_service.dart          (A + B)
lib/features/ai_coach/services/hotel_workout_planner.dart     (D)
lib/features/ai_coach/services/regenerate_plan_planner.dart   (C)
```

`hotel_workout_planner.dart:179-199` builds a schedule row in one map literal carrying both
literals, caches it (`:69`), and the dispatcher applies it. So the sentence this section used to
end on — *"nothing stops a fourth implementation appearing"* — was written about a fourth
implementation that already existed.

**D does not adopt the builder.** A hotel workout is a single ad-hoc replacement day, not a phase
layout; running it through a builder whose job is to lay `weekPlans[rawWeek-1..3]` across plan
weeks would be forcing an unrelated shape through the wrong abstraction. **Its stamps are corrected
in place instead**, and it is added to the gate's allowlist by name with that reason recorded.

⚠ **The allowlist must be closed, or it is the hole the gate exists to prevent (round 5, P2-12).**
Nothing in the first draft stopped a *fifth* implementation being allowlisted instead of using the
builder — which would make the gate a rubber stamp. The repo already has the idiom: rule 24's
`grandfathered:` list, *"enumerated BY NAME"* and terminal. So the allowlist is a **hard-coded
literal in the gate script**, pinned by a test asserting its **exact contents** — adding an entry
means editing an assertion that states why, in a diff a reviewer sees. It is not a config file, not
a glob, and not a directory exemption.

⚠ **Both stamps derive from the ROW'S OWN DATE, never from the clock (round 5, P1-5).** The first
draft of this list said `'week'` comes from *"`rawWeekNumber()` clamped to 1..4"* while the very
next bullet said `week_character` is *"the week the row actually lands in"* — two adjacent bullets
contradicting each other. `rawWeekNumber()` takes **no date parameter** (§3a: it reads `nowWall()`),
and D lays out up to **seven consecutive days** (`hotel_workout_planner.dart:79` `n = days.clamp(1, 7)`)
from a possibly-future supplied start (`:81-83`, `:137` `d = start.add(Duration(days: i))`). A
Friday-start 5-day hotel plan spans two plan weeks; a clock-derived stamp would put today's week
number on all five rows — the identical defect shape to C's `'week': weekIdx + 1` that §0 defect 2
exists to fix. Correct form, per row:

```dart
final k = (d.difference(planStart).inDays ~/ 7 + 1).clamp(1, 4);
// 'week': k
// 'week_character': currentWaveCharacters()[k - 1]
```

That is the arithmetic `template_service.dart:113-121` already uses (`:119`), which §8b names as the
eleventh writer — so this makes D agree with an existing precedent rather than inventing one.

- `'week': 1` (`:182`) → `k` above.
- `'week_character': 'baseline'` (`:192`) → `currentWaveCharacters()[k - 1]`, so a hotel day inside
  a `deload` week 4 no longer claims `baseline`.
- `'day_of_week': d.weekday` (`:183`) → `d.weekday - 1`. This is the local half of the off-by-one
  in §10's OI-170; the cloud half is out of scope there and stated as such.

### 8b. What the heuristic cannot see

Two row constructors omit `week_character` and are therefore invisible to it:
`template_service.dart:127-138` (a `custom_template` row with neither literal) and
`sync_workout.dart:1965-1980` (the restore overlay, `'day_of_week':` only). Both are named here
rather than left implicit, because a gate whose blind spot is undocumented reads as wider coverage
than it has. Neither is a phase-layout writer, so neither is a candidate for the builder; the
`template_service` week re-derivation is instead pinned by the new SoT entry (§9.6).

## 9. Ordering

1. **The gate** (§8), defaulting to warn.
2. `rawWeekNumber()` + `getCurrentWeekNumber()` delegation. Small, provable, no behaviour change.
3. **D's stamps corrected** (§8a) + added to the gate allowlist. Independent of the builder and of
   every other step, so it lands early and takes the known violation off the board before §9.6 can
   trip on it.
4. `buildScheduleRows` extracted, with **A** converted first.

   ⚠ **The reason A goes first has been rewritten (round 4).** The earlier text — *"A's callers
   re-anchor `plan_start`, so `rawWeek == 1` and A's output must be byte-identical"* — is false on
   both halves (§1). A goes first because it is the **narrowest** conversion: it has no delete
   step, no blob merge and no preview, so a defect in the extraction shows up there with the fewest
   confounders. Byte-identity is still the acceptance bar, but it is achieved by **A passing
   `today: planStart`** (§1), not by `rawWeek` happening to be 1 — and it must be *measured*, not
   assumed: capture a golden of A's written entries before the extraction, compare after, ignoring
   only `source` and `updated_at_ms`, which `upsertScheduled:557-562` stamps fresh on every write
   (T11).
5. **B** converted (Edit Profile) — the alignment rule becomes live here.
6. **C** converted (coach) — Monday anchoring, `preferred_training_days`, the blob write (§5), the
   truncation (§6). ⚠ **The `PlanGenerator.generate` argument set is its own sub-step** (§2): it is
   fixed at C's *call site*, not by the builder, and nothing structural prevents it regressing, so
   it lands with T15 pinning all ten arguments.
7. Gate default flipped to hard-fail. SoT registry rows (`docs/sot_registry.yaml:7945-7987`
   `phase_arc_display`; `:7988-8023` `deload_working_base_stash`) plus a new entry for the
   `'week'` stamp, which §3c makes a cross-tier contract — and which must also name
   `template_service.dart:115-120`, an eleventh writer that re-derives the week number inline
   (`weekNum = (diff ~/ 7 + 1).clamp(1, 4)`) and is invisible to both the caller census and the
   §8 gate.

## 10. Out of scope — each with a terminal owner

- **OI-175** — the `rawWeek > 4` branch (carries founder Q5). Sequenced after OI-174.
- **OI-174** — the orphan-row prune. ⚠ Round 3 P2-8: bounding C's writes at `plan_end` means a
  `switch_goal` no longer refreshes orphan rows past it, so those keep **old-goal** workouts where
  today they are rewritten. See §11 Q7 — this needs a decision, it is not silently accepted.
- **Removing `deload_evaluator` guard 5** — see §7.2.
- **OI-173** — cold-start weight estimate.
- ~~**OI-170**~~ — **FOLDED IN 2026-09-08. This bullet is superseded and kept only so the reversal
  is legible.** It read: *"Filed, not folded in… the repair needs a behavioural test against
  already-corrupt cloud state… it is a different field, in a different layer, from anything this
  batch touches."*

  Both reasons turned out to be wrong, and in the same direction. The repair does NOT need a
  corrupt-cloud fixture, because deriving `day_of_week` from the row's own `scheduled_date` makes
  the transmitted value **unread** — there is nothing to fixture. And it is not a different layer:
  D's local half was already being fixed here, so leaving the cloud half out would have shipped
  the SAME off-by-one fixed on one side and live on the other, which is the writer/reader drift
  class this whole batch exists to attack.

  ⚠ **The real cost of folding it in, stated plainly: the batch's blast radius rises from
  `account` to `platform`,** because `lib/core/services/sync/**` is pinned `platform`
  (`blast_radius.yaml:63`). That is not free — it pulls in the `feature_flag` requirement
  (`blast_radius.yaml:25`), which this batch initially MISSED and a B-pass caught. The kill-switch
  `disable_day_of_week_derive` closes it. Diagnose `c4e8b2`.

- ~~**OI-171**~~ — **FOLDED IN 2026-09-08** (deload lift blob push ordering). One line in
  `deload_evaluator.dart`, discovered while verifying a round-5 finding that had overreached.
  Diagnose `b6d1f4`.

- **OI-173** (was OI-167) / **OI-174** (was OI-168) / **OI-175** (was OI-169) — renumbered
  2026-09-08 after a three-way collision with numbers `main` minted concurrently. Still out of
  scope, each with a terminal owner on the board.

  ⚠ **The blast-radius argument was dropped (round 5).** An earlier draft leaned on `sync/**` being
  `platform` against this batch's `account`. True (`docs/blast_radius.yaml:63`) but nearly weightless:
  per §4.12.3 the only added requirement at `platform` is `bpass: accepted`, which this plan's own
  header already commits to. A boundary argument should rest on its strongest leg, not its
  longest list.
- **Hold-aware phase arc** — OI-60 / OI-125-127; `enable_hold_weeks` is OFF.
- **The `finisher` divergence** (A writes it, B does not) — collapses into the builder as a side
  effect of §2. Verified latent: 0 readers of `row['finisher']`, positive control `['warmup']` → 3.

## 11. Open questions

**Q4** — expired-phase coach copy. Cosmetic; does not block.

**Q6 — §2f, the preview cache.** `plan()` freezes rows at preview time
(`regenerate_plan_diff.dart:51-55` → `cache` `:368-375`); the dispatcher applies on Confirm
(`tool_dispatcher.dart:841-843`, `:979-985`). Under the new rule the cache encodes `rawWeek`, the
`'week': k` stamps and the `plan_end` bound, so a card left open across a Monday applies the
previous week's layout. **Decide one shape** — re-run `buildScheduleRows` at apply time (cheap now
that it is pure) or stamp `rawWeek` and compare. ⚠ Round 3 flagged that the draft recorded this
without deciding it, and that no test covers it. **My lean was: re-run at apply time** — the builder
is pure, so re-running is nearly free and removes the staleness class rather than detecting it.

⚠ **Round 4 (P2-9) shows that lean is incomplete on its own, and the correction is the important
part.** Re-running at apply time changes what is *written* without changing what the user *read*.
The card's copy is frozen at preview: `plan.totalWeeks` (`regenerate_plan_diff.dart:108`, `:139`),
`replaceCount`/`skipCount` (`:126`), `additionalDaysCount` (`:138`). A card opened Sunday and
confirmed Monday would say "3 weeks" and write 2 — which is precisely the class §6 exists to
prevent, reintroduced at a different seam.

**Decided shape: re-run at apply time, then compare against the preview's counts, and if they
differ, refuse and re-prompt rather than writing.** The refusal is the same `null` shape the
dispatcher already checks (round 2 P1-D), never an empty list. This keeps the staleness class
structurally closed while making it impossible to write something the user did not read.
**T12 asserts BOTH halves** — that the rows are current, and that card copy and written rows agree
— since a test for only the first would pass on exactly the bug this paragraph describes.

**Q7 — the `switch_goal` refresh regression (round 3 P2-8).** Options: (a) accept, and orphans keep
old-goal content until OI-174; (b) extend the regen's delete range past `plan_end` to cover
existing forward rows, which is OI-174's prune scoped to a regen. **My lean: (b)** — a regeneration
leaving stale forward workouts contradicts what the user asked for, and scoping the deletion to
"rows this regen is replacing" is a smaller claim than a global prune. Needs review.

**Q5** — moved to OI-175 (founder).

Q1, Q2, Q3 are decided (§4, §6, §2).

---

## 12. Round-1 findings of record (11, `not-converged`)

P0-1 clamped week / wrong guard / delete-before-write → §3a, §3b fallback, T7 · P1-2 `row['week']`
from the loop index → §3c · P1-3 "orphans fixed" was false → §10 · P1-4 coach date model → §2 ·
P1-5 census omitted `generateAndSchedule` → §1 · P2-6 phase-advance timing → §10 · P2-7 T3 vacuous
→ §13 · P2-8 no SoT row → §9.6 · P3-9 blast radius `account` → header · P3-10 `:61` is a comment →
§6 · P3-11 mutation mechanism → §13.
Confirmed: the diagnosis end to end; the worked example (1 Sep 2026 is a Tuesday; `plan_start`
Mon 31 Aug; regen 9 Sep ⇒ week 2).

## 13. Round-2 findings of record (5 new P1s, all inside round-1's corrections)

P1-A refusal + no-prune composed into a silent no-op → dissolved by the fallback · P1-B no lower
bound → §3b, T10 · P1-C `istMidnight` ≠ the reader's `nowWall()` → §3a · P1-D refusal placement →
§2 seam table · P1-E `row['week']` census was 2 of 6 → §3c · P2-F "Week 5" on Home → dissolved ·
P2-G blob merge inert and harmful → overwrite · P2-H extended window not week-aligned → dissolved ·
P2-I T7 under-specified → §14 · P2-J preview cache → §11 Q6 · P3-K/L/M/N citations → fixed.

## 14. Round-3 findings of record (2 P1s, 6 P2s — 8 of 10 on the coach path)

P1-1 the deload **dual write** → §4 · P1-2a/b/c coach lacks the pre-today skip, the index advance,
and `preferred_training_days` → all collapse into §2 · P2-3 "always rewrites what it deletes" is
false (`displaced_*`) + the unstated `plan_end` precondition → §3b · P2-4 a THIRD clock → §3a ·
P2-5 the `'week'` stamp pinned only for today → §15 tests · P2-6 the unresolved OR → §11 Q6 ·
P2-7 the coach as a blob writer, unnamed → §5 · P2-8 `switch_goal` refresh regression → §11 Q7 ·
P2-9 T7 must scope to `schedule_*` · P2-10 T8 must name the week and pin the preference ·
P3 ×9 citations → fixed throughout.

**Verified correct by round 3 and now settled:** §3a is behaviour-preserving across all 12 callers ·
the layout arithmetic for rawWeek 1–4 · `plan_start` is always a Monday · §2d's weekday claim is
TRUE, not fabricated · the `'week'` reader census and the cloud round-trip · the seam analysis ·
the six `generateAndSchedule` call sites · blast radius `account` · the mutation guidance ·
nothing clears the deload idempotency flag.

## 15. Round-4 findings of record (5 P1s, 5 P2s, `not-converged`)

Reviewed against the de-duplication rewrite. **Every P1 was re-verified against source by the
author before remediation**; all five held.

| # | Sev | Finding | Where fixed |
|---|---|---|---|
| P1-1 | P1 | §2's collapse list overclaimed: rows 2 and 3 are **caller-side inputs**, so a pure builder handed a finished `Phase` and `dayPattern` cannot make them impossible — only visible at one signature. §0 defects 4+5 are still fixed at C's call site, exactly as a layout patch would have been. | §2 rewritten; T15 added |
| P1-2 | P1 | §9's ordering control was invalid on **both** halves. `auth_session_bootstrapper.dart:646-649` anchors on historical `phase_started_at` (`:134-135` returns it verbatim), so A's callers yield `rawWeek` 2–4, not 1. And `rawWeek == 1` would not make the skip inert anyway: A's loop (`:259-315`) has **no pre-today guard and no completed check**, and onboarding's `this_monday` default resolves to a **past** Monday (`onboarding_provider.dart:262-264`). | §1 + §9.4; A passes `today: planStart`; T11 given a real oracle; T14 added |
| P1-3 | P1 | Inventory rows 6 and 7 describe a difference that does not exist — `workoutDayIndex++` (`:241`) is unconditional inside `isWorkoutDay`, 33 lines above the `isCompleted` gate (`:274`). Row 10's citation was `:276-278`; actual `:243-245`. Counts were wrong (17 rows, not 15). | inventory rewritten |
| P1-4 | P1 | **A fourth implementation exists and the gate's own heuristic finds it**: `hotel_workout_planner.dart:179-199`, with `'week': 1` and `'week_character': 'baseline'` hardcoded and `'day_of_week': d.weekday` (1..7 vs the canonical 0..6). §9.6 would have flipped the gate hard-fail onto a live violation with no conversion step. | §8a + §9.3; OI-170 for the cloud half |
| P1-5 | P1 | §4 declared the deload dual write mandatory and gave it **no parameter in §2 and no owner in the seam table**; it also scoped itself to "the regen" while `plan_engine_flags.dart:225-231` names A's blob write too. | §2 signature + §4a |
| P2-6 | P2 | The coach's new blob write had no specified sync fan-out; every existing blob writer pairs one, and the dispatcher sits outside the contract test's five-file union. | §5; T16 |
| P2-7 | P2 | A bare `List<Map>` return cannot reconstruct C's preview — completed days appear in `firstWeekDisplay` (`:249-267`) but not in `rawSchedules` (`:274`). | §2 returns `ScheduleRowPlan` |
| P2-8 | P2 | §7.2 calls `generated_via` survival a MUST and names the silent-failure mode; no test covered it. | T17 |
| P2-9 | P2 | Q6's "re-run at apply time" lean changes what is written without changing what the user read — the card's copy is frozen at preview. | §11 Q6 decided: re-run, compare, refuse on divergence; T12 asserts both halves |
| P2-10 | P2 | `template_service.dart:115-120` re-derives the week number inline — invisible to both the caller census and the §8 gate. | §9.7 SoT entry; §8b |

**P3s** (all verified, all fixed): `redoWeek4`'s `plan_end` cite `:212-213` → `:213-214` and "+7 per
call" imprecise; guard 6 cited as `:198-206` → `:92-97`; `_liftExercise` `:282-291` → `:280-291`;
ambiguous `models.dart` / `plan_generator.dart` paths; the `'week'` writer census missing `:285` and
the live `:417` `copyWeek`; B's `isFirstGeneration` branch unreachable from its only live caller.

**What round 4 got right that matters most**: it ran the gate's proposed heuristic instead of
reasoning about it, and that single command found the fourth implementation. Three rounds and two
versions of an inventory had reasoned about the same code and missed it.

## 15a. Round-5 findings of record (7 P1s, 9 P2s, `not-converged` → SPLIT)

Reviewed against the round-4-hardened plan, scoped to the new content. **Every P1 re-verified
against source by the author before acting**; six held as stated, one (P2-9) overreached and was
corrected. **Four of the seven P1s sit inside round-4's own remediations** — the §4.12.1 signal.

**These are Unit 2's re-plan inputs. They are recorded here because the plan text they refer to is
being rewritten, and a finding whose only home is a rewritten document is a finding that is lost.**

| # | Sev | Finding | Owner |
|---|---|---|---|
| P1-1 | P1 | §9.4 says what `rawWeek` is *not* and never what it *is*. `today` governs only the pre-today skip; the **week count** comes from `rawWeek`, and A's loop is always 4 weeks (`read_service.dart:252`). An implementer wiring `rawWeek: rawWeekNumber()` — which §9.4 points at by disclaiming `rawWeek == 1` — makes A emit 2–3 weeks on a **missing-plan repair**, leaving the earliest weeks still missing. **A must pass `rawWeek: 1` explicitly**, on the same grounds as `today: planStart` | Unit 2 |
| P1-2 | P1 | §4a's read predicate is unspecified and "read the rows" is **wrong for most of week 4**: `_liftWeekFour` writes `working` onto a filtered subset only (`deload_evaluator.dart:207-216` skips rest rows, non-`planned`, swapped/shortened, and **past dates** at `:213`). Reading the first week-4 row — often a Monday rest day — returns `deload` and silently discards the lift. **Read `currentWaveCharacters()[3]` before overwriting the blob**, or state the predicate as guard 6's mirror (`:88-89` + `:92-97`) | Unit 2 |
| P1-3 | P1 | §4a step 2 tells the builder to call `_liftExercise` — **private, non-static, no `part of`** (`deload_evaluator.dart:280`; verified `grep -n "^part\|^library"` → empty, positive control `^import` → 13 hits at `:23-37`). A new file cannot reach it. **Verbatim the trap §4 catches for `_applyWave` one paragraph above.** Promote it to a public static as an explicit step; repoint `:222` and `:256` | Unit 2 |
| P1-4 | P1 | `ScheduleRowPlan` still cannot rebuild C's preview — P2-7's fix solved the wrong half. `regenerate_plan_planner.dart:250-260` builds `displayExercises` for a completed day **before** the `isCompleted` gate at `:274`, and `RegeneratePlanDay.exercises` is required non-nullable (`:17`, `:30`). A `List<String>` of dates cannot carry that. Return skipped days as **full row maps**, or emit all rows with a `willSkip` flag and let the caller partition | Unit 2 |
| P1-5 | P1 | §8a's D fix read the wall clock where it must read the row's date | **FIXED — Unit 1, §8a** |
| P1-6 | P1 | §9 has **no step** for two decided subsystems: Q6's apply-time re-run (needs a new cache payload — the cache holds only `RegeneratePlanResult` + `rawSchedules` at `:368-375`, not the builder's input tuple) and §4a's dual write (§9.4/§9.5 never mention `preserveWeek4Character`) | Unit 2 |
| P1-7 | P1 | T15 does not discriminate: three of the "ten arguments" are supplied by no live caller, and `bodyFocus` is resolved internally, so `bodyFocus: const [], sessionDuration: null, cardioPreference: null` passes it while changing nothing. Assert **values**, not parameter presence | **§0 defect 5 restated — Unit 1 doc; test is Unit 2** |
| P2-8 | P2 | §4a mis-enumerates A's call sites; the omitted one is the counter-example — **`train_provider.dart:669`** (missing-plan repair) passes the user's *current* phase and re-anchors `plan_start` to this week's Monday via `:225`. Full census: `auth_session_bootstrapper.dart:653`, `read_service.dart:575`, `pro_phase_advance.dart:582`, `onboarding_provider.dart:554`, `simulation_service.dart:162`, `train_provider.dart:669` | Unit 2 |
| P2-9 | P2 | §5's "every blob writer" universal is false — 4 writers, 2 pair `syncWorkoutData()` | **FIXED — §5; the residue filed as OI-171** |
| P2-10 | P2 | T9 and T11 contradict the plan on the A path: `read_service.dart:225-226` writes `plan_start`/`plan_end` **unconditionally** on every A call, so T9 must scope to B and C; T11's byte-identity must scope to `preserveWeek4Character == null`; T6 likewise (A rewrites pre-today rows both before and after) | Unit 2 |
| P2-11 | P2 | §8 never stated the gate's input set; repo-wide it matches 2 test files plus every behavioural test Unit 2 adds | **FIXED — Unit 1, §8** |
| P2-12 | P2 | §8a's allowlist had no closing mechanism | **FIXED — Unit 1, §8a** |
| P2-13 | P2 | T16's union extension collides with `expect(putCount, equals(4))` (`workout_schedule_service_uses_write_service_test.dart:101`) — **or silently does not**, because the alias detector at `:92` matches `final x = _hive.workoutBox;` and the dispatcher uses `final box = HiveService.instance.workoutBox;` (`tool_dispatcher.dart:849`), so an aliased put is invisible and the count stays 4 while the new write goes uncounted. Say which | Unit 2 |
| P2-14 | P2 | Q6's refusal reuses the dispatcher's *cache-absent* copy (*"Open the diff preview first…"*, `tool_dispatcher.dart:843-847`), which is actively misleading for a *divergence*. Needs its own result and re-prompt string | Unit 2 |
| P2-15 | P2 | No closure ledger planned | **ANSWERED — see the STATUS block: §4.10 forbids creating it before every finding is terminal** |
| P2-16 | P2 | The de-dup leaves `_getDayPattern` duplicated (`read_service.dart:1714-1727` / `regenerate_plan_planner.dart:117-130`, currently identical in value, kept in sync by a comment). §2 makes `dayPattern` caller-supplied, so the duplicate survives untouched — in a plan whose thesis is "one logic, implemented once" | Unit 2 |

**P3 citation corrections** (all re-derived by round 5, all real): §2 `read_service.dart:196-211` →
**`:203-218`** · §2 `:342-354` → `:343-354` · §5 `:245-246` → `:246-247` · §9.4/T11
`upsertScheduled:557-562` → `:558-562` · §4 `_liftExercise` `:280-291` → `:280-290` · §7.5
`_liftWeekFour` filter `:198-206` → `:207-218` · §1 OI-150 comment `:620-631` → `:619-630` · §8a
"caches it (`:69`)" → `:69` is the field, `cache()` is `:206` · inventory row 9 `finisher`
`:286-293` → `:291-293` · T8 must pin `rawWeek ≤ 3` (it asserts on plan week `rawWeek+1`, which
does not exist at `rawWeek == 4`).

**What round 5 verified as settled** (do not re-audit): round 4's withdrawal of rows 6 and 7 ·
round 4's discovery of D, heuristic reproduced · the inventory's counts · the `finisher` absence
with its positive control · §7.3's `plan_start` census · §8's auto-wiring reasoning · §3c's new
writers · §3b's `redoWeek4` correction · §4's whole mechanism incl. `triggeredDeloadEnabled`
default-ON · T8's discrimination arithmetic · T3's fixture · T14's telemetry · §11's card-copy
citations · the SoT ranges · §8b's blind spots · that the extraction is mechanically feasible
(public wrappers `getDayPattern` `:1671`, `normalizeToMonday` `:1674`, `dateKey` `:1710` exist).

**Round 5's §4.2 verdict on the out-of-scope items: boundary, not deferral** — all four are on the
board with populated fields and substantive reasons, and the batch fixes the half of OI-170 its own
gate can see. It recommends §10 drop the blast-radius leg and lead with the fixture leg, since
`platform` over `account` costs only `bpass: accepted`, which the header already commits to.

## 16. Tests

Mutation-proven per rule 21; a mutation must leave the code **compiling and semantically wrong**.
Because the builder is **pure**, T1–T8 are cheap unit tests over it, and the caller tests only need
to prove each caller feeds it correctly and writes what it returns.

| # | Kind | Asserts |
|---|---|---|
| T1 | builder unit | `weekPlans[rawWeek-1+i]` lands on plan week `rawWeek+i`, positionally, for rawWeek 1–4 |
| T2 | behavioral ×3 callers | `currentWaveCharacters()[getCurrentWeekNumber()-1]` == TODAY's row `week_character` — the agreement oracle |
| T2b | builder unit | **every** written week `k` stamps `'week': k` — not only today's (round 3 P2-5: a constant `rawWeek` would otherwise pass) |
| T3 | behavioral | fixture **pre-seeds** orphan rows past `plan_end` (`phase_adherence_rate_test.dart:191-208`); the regen adds none |
| T4 | builder unit | `rawWeek=4` emits exactly one week |
| T5 | behavioral | a lifted (`working`) week 4 survives a `rawWeek=4` regen as `working` **in the rows AND in `currentWaveCharacters()[3]`** (§4) |
| T6 | behavioral | `completed` and pre-today rows byte-identical across a regen |
| T7 | behavioral | the `redoWeek4` state — fixture pins **today** as well as `plan_end`; asserts today's behaviour preserved and no `schedule_*` key deleted without replacement (⚠ scoped to `schedule_*`: `displaced_*` IS deleted without replacement today, so an unscoped assertion goes red for the wrong reason) |
| T8 | behavioral | coach weekday alignment: a user with `preferred_training_days` = Tue/Thu/Sat who regenerates on a Wednesday is scheduled **Tue/Thu/Sat**, asserted on plan week `rawWeek+1` (fully future, so the pre-today skip cannot mask it). ⚠ Pin `daysPerWeek: 3` explicitly and assert `type == 'rest'` on the off days — with `_getDayPattern(3) == [0,2,4]`, a Monday-anchoring failure yields Thu/Sat/Mon and a preferred-days failure yields Mon/Wed/Fri, so both are distinguishable only if the full week is asserted |
| T9 | contract | `plan_start` / `plan_end` unchanged by a regen |
| T10 | builder unit | `rawWeek < 1` does not throw. ⚠ Round 3 could construct no non-corrupt route to it — say "reachable only via a corrupt cloud value", not that it is ordinary |
| T11 | behavioral | **A is byte-identical** before and after the extraction (§9.4). ⚠ Not assertable as a literal map comparison: `upsertScheduled:557-562` stamps `'source'` and a fresh `'updated_at_ms'` on every write, so the test compares entry maps **minus those two keys** against a golden captured BEFORE the extraction. Capturing that golden is a step of §9.4, not an afterthought |
| T12 | behavioral | the preview cache (§11 Q6), **both halves**: a cached plan applied after a week boundary writes the CURRENT week's layout, AND the card's copy (`totalWeeks`, `replaceCount`, `skipCount`, `additionalDaysCount`) agrees with what was written — or the apply refuses |
| T13 | gate | `check_single_schedule_row_builder.dart`, mutation-proven (rule 24) |
| T14 | behavioral | **A still emits `upsert_scheduled_skipped_completed_day`** when it walks a completed day (§1). A has no completed check of its own; if the builder filters those rows out before the write, the telemetry silently stops — a guard that fails green |
| T15 | contract | **C passes all ten `PlanGenerator.generate` arguments.** Row 3 is fixed at the call site, not in the builder (§2), so nothing structural holds it — this is the only thing that does |
| T16 | contract | the dispatcher's `current_plan` write fires `SyncService.syncWorkoutData()` (§5), extending `workout_schedule_service_uses_write_service_test.dart` past its current five-file union |
| T17 | behavioral | **`generated_via` survives the merge** (§7.2): a coach-applied row carries `'ai_coach_regenerate'`, an A/B row does not, and a week-4 coach row still blocks `deload_evaluator` guard 5 from lifting. §7.2 calls this a MUST and names the silent-failure mode; before round 4 no test covered it |

⚠ **Mutation guidance.** `currentWaveCharacters()` (`:1273-1281`) has **no `catch` above it**, so an
unreadable-blob mutation makes T2 throw RangeError — red for the *wrong reason*. Mutate the **index
arithmetic**. (The swallowing method is `currentDeloadReason()` `:1116-1127`, which T2 never calls.)
