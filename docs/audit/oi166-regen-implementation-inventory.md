# Inventory — how the regeneration implementations differ

> ⚠ **Point-in-time document — read the dates. Unit 2 LANDED after this was written** (2026-09-11,
> diagnose `d7f3b2`, keystone `docs/plan-reviews/regen-wave-unit2.md`). It closed the `'week'` /
> `week_character` / `current_plan` rows for BOTH B and C and inserted its splice + `effectivePlanEnd`
> block into `workout_schedule_read_service.dart` immediately after the old `:386`, so **every B
> citation in this file at or below old `:388` is pre-Unit-2 and no longer resolves as written**
> (the shift is +42 to +49 depending on region — measured, e.g. old `:392` is now `:436`; the
> `:357`-`:386` citations above the insertion still resolve). Re-grep the symbol, do not cite the
> number. The founder's 2026-09-07 "one implementation" decision is NOT closed by
> Unit 2: B and C were fixed in place, deliberately unconverged (Unit 2's explicit scope boundary);
> the shared `schedule_row_builder.dart` de-duplication this inventory was written to feed is still
> owed, and `scripts/check_single_schedule_row_builder.dart` (Unit 1's §4.11 gate) still stands
> guard so a THIRD implementation cannot appear before it happens.

**Purpose.** Three plan-review rounds each discovered *new* ways the AI-coach planner diverges from
the canonical scheduler, one or two at a time. Non-convergence was never the design; it was that
**nobody had a list**. This is the list. Founder decision 2026-09-07: the two paths must become
**one implementation**, so this inventory is the input to that de-duplication.

**Method.** Both functions read end to end and compared dimension by dimension. Every row below
carries a verified `file:line`. Where a claim is about ABSENCE it was checked with a positive
control, because a grep returning nothing has two explanations.

⚠ **Corrected 2026-09-07 by review round 4.** The first version of this file asserted 15
differences across "three implementations" and got three rows wrong. Round 4 read the same code
and found a **fourth** implementation, and proved rows 6 and 7 describe a difference that does not
exist. Both corrections are below. The lesson is the file's own thesis turned on itself: an
inventory written to end guessing is worth only as much as its weakest row.

## The four implementations

| | Function | Used by |
|---|---|---|
| **A** | `generateAndSchedule` — `workout_schedule_read_service.dart:170-320` | onboarding, phase advance, missing-plan repair (6 call sites) |
| **B** | `generateAndScheduleFromDate` — `:325-521` | **Edit Profile** (`edit_profile_screen.dart:2029`) |
| **C** | `RegeneratePlanPlanner.plan` — `regenerate_plan_planner.dart:135-340` | **AI coach** — `regenerate_plan_block` AND `switch_goal` |
| **D** | `HotelWorkoutPlanner` — `hotel_workout_planner.dart:179-199` | **AI coach** — `generateHotelWorkout` |

**D was missed by the first version of this inventory and by three review rounds.** It is found by
the heuristic the gate itself proposes — files containing both `'week_character':` and
`'day_of_week':`:

```
$ grep -rl "'week_character':" lib/ | xargs grep -l "'day_of_week':"
lib/core/services/workout_schedule_read_service.dart          (A + B)
lib/features/ai_coach/services/hotel_workout_planner.dart     (D)  <-- unlisted
lib/features/ai_coach/services/regenerate_plan_planner.dart   (C)
```

⚠ **CORRECTED 2026-09-10 — Unit 1 FIXED all three of D's defects; OI-170 is CLOSED.** Verified
live: `hotel_workout_planner.dart:193` `'week': planWeek.week` · `:201` `'day_of_week': d.weekday - 1`
· `:215` `'week_character': planWeek.character ?? 'baseline'`. The paragraph below records the
PRE-Unit-1 state and is kept because the reasoning is the live lesson — but do not cite its line
numbers or its "permanent rather than conditional" verdict as current:

> D was worse than C on the exact dimensions this batch fixes, and its defects were permanent
> rather than conditional: `'week': 1` hardcoded (then `:182`), `'week_character': 'baseline'`
> hardcoded (then `:192` — the row can sit inside a `deload` week 4), and
> `'day_of_week': d.weekday` (then `:183`), which is **1..7 where every reader expects 0..6**.

The founder's scope is **B vs C** (the two regeneration paths). A and D are included where they
were verified, because it turns out **A and B also disagree** (row 14) — the drift is not simply
"the coach copied it wrong".

C's own header asserts the opposite of what this table shows, twice:
`:99-101` *"Day-of-week pattern matches [_getDayPattern] **exactly** so the rest-day distribution
stays consistent with manual plan generation"*, and `:115` *"Mirrors … keep these in sync"*.

## The differences — B vs C

**17 numbered rows: 8 real drifts (4 live), 7 legitimate seams, and 2 rows that turned out not to
be differences at all** (6 and 7, struck below).

| # | Dimension | B (Edit Profile) | C (coach) | Class |
|---|---|---|---|---|
| 1 | **Week anchor** | `monday = _normalizeToMonday(today)` `:379`, `weekStart = monday + week*7` `:439` | `weekStart = start + weekIdx*7` `:224` — NOT normalized; `:219-223` admits it | **DRIFT — live** |
| 2 | **Day pattern source** | `preferredDays ?? _getDayPattern(daysPerWeek)` `:433` | `_getDayPattern(resolvedDays)` `:206` — never reads `preferred_training_days` | **DRIFT — live** |
| 3 | **`PlanGenerator.generate` args** | all 10 `:343-354` | 6 — omits `preferredDays`, `bodyFocus`, `sessionDuration`, `cardioPreference` `:190-197` | **DRIFT — live** |
| 4 | **Writes `current_plan`** | yes `:388` | **no** (0 hits for the blob keys) | **DRIFT — live** (OI-166's filed symptom) |
| 5 | **Pre-today skip** | `if (date.isBefore(today)) { advance; continue; }` `:447-452` | none — writes every day from `start` | **DRIFT — latent today** (C's `start` defaults to today `:144-146`, so no past date is in range… until anchoring makes it one) |
| ~~6~~ | ~~Workout index advances across skipped days~~ | — | — | **NOT A DIFFERENCE** — withdrawn (round 4) |
| ~~7~~ | ~~Completed-row handling~~ | — | — | **NOT A DIFFERENCE** — withdrawn (round 4) |
| 8 | **Clock** | `istMidnight(fromDate)` `:357` | `_today()` = raw `DateTime.now()` truncated `:387-389` — **not seam-aware** | **DRIFT** (breaks dev time-travel / year-sim) |
| 9 | **`finisher` on the row** | **absent** | present `:286-293` | **DRIFT — latent** (see A-vs-B below) |
| 10 | **`workout_name` fallback** | `workoutDay.name` raw `:477` | `name.isEmpty ? 'Workout $i' : name` `:243-245` | DRIFT — cosmetic |
| 11 | **Deletes stale rows** | yes, `today..planEnd` + `displaced_*` `:362-376` | none (upsert-only) | SEAM — C previews, so it must not delete at plan time |
| 12 | **Writes `plan_start` / `plan_end`** | first generation only `:382-386` | no | SEAM |
| 13 | **Writes `preferred_training_days` / `phase_started_at`** | `:392`, `:395-399` | no | SEAM |
| 14 | **Sync trigger** | `syncWorkoutData()` + `pushSnapshot()` `:389-390` | no (dispatcher's job) | SEAM |
| 15 | **`generated_via` / `generated_at`** | absent | `'ai_coach_regenerate'` + timestamp `:299-300`, `:363-364` | SEAM — provenance, and `deload_evaluator` guard 5 depends on it |
| 16 | **Weeks written** | hard 4 `:435` | `n = weeks.clamp(1, 12)` `:143` | SEAM — a real coach feature |
| 17 | **Write mechanism** | inline `upsertScheduled(source: planGenerator)` | builds `rawSchedules`, cached `:368-375`, applied later by the dispatcher as `WriteSource.aiCoach` | SEAM — the preview |

### Rows 6 and 7 — withdrawn, and why the error is instructive

The original rows claimed C "increments only when a row is emitted `:241`" and "skips completed
rows, does NOT advance". Both are false. `regenerate_plan_planner.dart:239-241`:

```dart
if (isWorkoutDay) {
  final workoutDay = weekPlan.workoutDays[workoutDayIndex];
  workoutDayIndex++;                      // <-- unconditional inside the branch
```

The increment runs **33 lines before** the `if (!isCompleted)` gate at `:274`. C therefore advances
the index across a completed day exactly as B does at `:455-462`. The rows were written by reading
the *emission* site (`:274`) and inferring the increment's position from it rather than reading the
increment. Row 7's genuine content — `willSkip: isCompleted` at `:266` feeding the diff card — is a
**preview seam**, not a drift, and is already covered by row 17.

Consequence for the design: **the completed-row axis needs no unification, because the two paths
already agree on it.** The pre-today axis (row 5) is the only real skip difference.

## The `day_of_week` off-by-one — a live bug, wider than the coach

Separately from anything OI-166 touches, `day_of_week` is written in two incompatible encodings.

**The app's canon is 0..6.** `tool_dispatcher.dart:695` carries the explicit
`// 0=Mon..6=Sun`; `workout_schedule_read_service.dart:415` writes `d.weekday - 1`; the readers
`train_provider.dart:619` and `:816` compute `dayNumber = (week - 1) * 7 + day_of_week + 1`, which
renders as the `D2` / `D8` badges in `week_rows.dart:54`, `day_card.dart:54` and
`expandable_day_card.dart:196`, and is match-keyed by `preview_plan_provider.dart:117`.

⚠ **CORRECTED 2026-09-10 — THIS ENTIRE SECTION IS CLOSED. All three citations below are dead.**
(1) `hotel_workout_planner.dart:183` — fixed by Unit 1, now `:201` `d.weekday - 1`.
(2) `sync/sync_workout.dart:1620` — the code is **DELETED**; `:1594-1597` records that `parsedDate`
*"lived here solely to feed `'day_of_week': parsedDate?.weekday` … With that gone it had no other
reader, so it is deleted."*
(3) `sync_workout.dart:1977` — now the derive-on-restore FIX (`:1982-1984`), i.e. the repair this
section recommends **has shipped**, behind `SyncFlags.deriveDayOfWeekOnRestore`.
OI-170 is CLOSED (`closed_issues.md`). Retained as the diagnosis record, NOT as open work:

**Two writers emit 1..7 instead:**

1. `hotel_workout_planner.dart:183` — `'day_of_week': d.weekday`. Local, affects hotel workouts only.
2. `sync/sync_workout.dart:1620` — `'day_of_week': parsedDate?.weekday ?? entry['day_of_week']`.
   This is the **cloud push**, and it is the serious one. `parsedDate` comes from the row's own date
   key (`:1595`), so it is effectively never null and the stored canonical value is never sent.

**The restore then makes it durable.** `sync_workout.dart:1977` writes
`if (map['day_of_week'] != null) 'day_of_week': map['day_of_week']` — the cloud's 1..7 value,
verbatim, **after** the `existingMap` spread, so it OVERWRITES a correct local 0..6. Every schedule
row that round-trips through the cloud comes back one too high: Monday of week 1 renders `D2`, and
Sunday of week 1 renders `D8` inside a seven-day week.

**Which side is wrong: the PUSH.** `scheduled_workouts.day_of_week` is a bare `int` with no CHECK
and no comment (`002_create_fitness_tables.sql:104`), and **no Edge Function reads it**
(`grep -rn "day_of_week" supabase/functions/` → 0). There is no server-side contract to honour; the
app is the only consumer, and the app's canon is 0..6. The value is also a pure function of
`scheduled_date`, so the cleanest repair is for the RESTORE to derive it from the date rather than
trust the transmitted value — that self-heals every already-corrupted cloud row with no migration.

⚠️ **Corrected 2026-09-10 (round 3, F6) — this paragraph was stale on BOTH facts.**
**OI-170 is CLOSED** (2026-09-08, `regen-wave-alignment`, diagnose `c4e8b2`; `closed_issues.md:3460`),
so it is not "tracked" pending anything. And the tier contrast was **inverted**: this batch is
`platform`, not `account` — `supabase/functions/_shared/** → platform` (`blast_radius.yaml:61`)
wins on first-match, which round 2's ground-truth reviewer confirmed by re-running the classifier.
Reading it as `account` under-declares the requirements (`platform` `requires:` is **four** items,
`blast_radius.yaml:23-25`). The original wording follows, struck, so the rot is legible:

> ~~Tracked as **OI-170**. Not folded into this batch: it is a different field, its writers sit in
> `sync/**` (blast radius `platform`, against this batch's `account`), and the restore-side repair
> needs its own behavioural test against already-corrupt cloud state.~~ D's local half is handled
> here, because D is a schedule-row implementation and the §8 gate matches it.

### A vs B — the drift is not only the coach's

**`finisher` is written by A (`:285-287`) and NOT by B.** So the cardio finisher is present on rows
laid down at onboarding and **absent** from rows rewritten by an Edit-Profile regen.

⚠ **Not a live bug, and this was checked rather than assumed.** `grep -rn "\['finisher'\]" lib/`
returns **0** readers, with `['warmup']` as a positive control returning 3
(`template_service.dart:193`, `train_provider.dart:629`, `:792`). Nothing reads a row's finisher
back today. It is dead weight and a trap for whoever adds the first reader — a field that silently
exists or not depending on which code path last touched the row.

### An eleventh writer the gate cannot see

⚠ **CORRECTED 2026-09-10 — Unit 1 already closed this.** `template_service.dart:113-125`
now calls the SHARED `WorkoutScheduleReadService.rawWeekNumberFor(date, planStart).clamp(1, 4)`
and carries a comment recording that it replaced the inline copy. The paragraph below
describes the PRE-Unit-1 state and is kept because its *reasoning* is still the live lesson. It is invisible to a `getCurrentWeekNumber()` caller
census (it is not a caller) and invisible to the §8 gate (its row carries neither literal). It
happens to agree with the new semantics, but it is one more place the `'week'` contract lives
unpinned. Named in the SoT entry this batch mints.

## What this says

- **8 real drifts, not the ~5 the reviews had surfaced.** Rounds 1–3 found 1, 4, 2, 5, 6 — and one
  of those five (6) was not a difference. That rate of discovery, and that error rate, is exactly
  why three rounds could not converge: every round's rule was written against an incomplete picture
  of what it had to be true for.
- **Only 7 of the 17 rows are legitimate seams**, and all 7 reduce to one thing: **C previews
  before it writes; B writes immediately.**
- That is the de-duplication design, and it falls straight out of the table: **extract the
  computation, keep the side effects at the callers.**

## What the shared core actually collapses

⚠ **Corrected by round 4.** The first version claimed rows 1, 2, 3, 5, 6, 7, 8, 9, 10 all "collapse
into the shared function and become structurally impossible to drift again". That overclaims on
three counts, and the overclaim matters because it is the argument for the whole design.

**Genuinely structural** (the builder computes it, so no caller can get it wrong): rows 1, 5, 8, 9,
10 — the Monday anchor, the pre-today skip, the clock, `finisher`, the name fallback.

**Reduced to one call signature, NOT made impossible**: rows 2 and 3. The builder receives a
finished `Phase` and a finished `dayPattern`; it cannot police which arguments produced them. A
future caller can still call `PlanGenerator.generate` with the wrong argument set, or compute
`dayPattern` differently, and the builder will faithfully lay out the wrong plan. What the design
buys here is *visibility* — one signature, three call sites, greppable — not impossibility.

**Withdrawn**: rows 6 and 7 were never differences.

The honest summary: **five rows become structurally impossible, two become visible at one
signature, two were phantom.** That is still worth the change — but the §8 gate must be understood
as covering row construction only, which is why the `generate()` argument sets need their own
answer in the plan rather than being assumed away.

⚠ **Row 16 (weeks 1-12) is the one that does not fit cleanly** and needs a decision: the shared
function must take a week COUNT, and OI-166's rule bounds it at the phase end. Whether the coach's
1–12 parameter survives at all is the open product question already recorded as OI-166 §5 / Q2.

⚠ **Row 15 is load-bearing and must NOT be unified away.** `deload_evaluator.dart` guard 5 keys on
`generated_via` starting `ai_coach` to refuse an un-deload on coach-written weeks. If the two paths
become byte-identical in provenance, that guard silently stops firing. (Its *reason* goes away once
coach weeks are aligned — but that is a separate decision, and removing the stamp is not the same
as removing the guard.)
