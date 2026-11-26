# Generator Unit 3D: "Keep training Phase 1" is the Monday-aligned hold week (OI-175, closes OI-166's residual)

Tier L (Train UI, schedule writer, two Edge Functions). Blast radius platform. Execution mode: inline (one worktree,
`.claude/worktrees/generator-step3d`, one writer). Base: main c760037e (3C merged). Rev 5 (3D-a: round 4 P1 settled, round 5 converged with P2/P3 folded in; 3D-b: round 4 pending).

**Split (§4.12.1, rev 4).** Three rounds each surfaced new P1s, so 3D lands in two pieces, each with its own PR,
CI, B-pass and one more review round: **3D-a, the server** (section 2.3, FOB-4: two Edge Functions and
`_shared/hold_week.ts`; no client change; inert for every non-holder, and no holder exists before 3D-b) lands
FIRST; **3D-b, the client flip** (sections 2.1, 2.2, 2.4) lands second and records FOB-4 as code closed by 3D-a.

## 0. Decisions

| Id | Decision |
|---|---|
| d57 (2026-11-15) | Switch "Keep training Phase 1" to the Monday-aligned `holdWeek`, delete the old `redoWeek4` in the same batch, and make the NOW marker follow the 4-week cycle past week 4. Founder device check at the end. |
| d80 (2026-11-16) | Hold weeks keep their July design (Peak, Peak, Peak, Deload, repeat; `isDeloadHold(n) = n % 4 == 0`). Only the "you are here" marker changes: during a hold, W4 stops being gold, only the current H chip is gold, and the card word says Peak or Deload (the hold cycle, not the 4-week wave). |
| OI-125 (earlier founder split of FOB-6) | Selectable past hold weeks are a separate feature. This unit does not make hold chips selectable and does not change what the week list shows under the chips. |
| CLAUDE.md §1 | Pre-launch: every account is a testing account. A tester holding a `redoWeek4`-made window is not a real-user migration risk. |

## 1. What happens today (main c760037e)

- **The write.** `runFreeTierRepeatWrite` (`lib/features/train/widgets/keep_training_phase1_action.dart:29-36`) is the
  ONE branch point: `PlanEngineFlags.holdWeeksEnabled` (`plan_engine_flags.dart:163-169`, `configBox['enable_hold_weeks']
  == true`, default OFF) -> `WorkoutScheduleWriteService.holdWeek()` (`workout_schedule_write_service.dart:264-381`),
  else `redoWeek4()` (`:191-243`; wrapper `workout_schedule_service.dart:241-242`). Callers: `PlanExpiredCard._handleRedoWeek4`
  (`plan_expired_card.dart:57-90`, then `onRedoComplete`, wired at `home_screen.dart:814-815` and
  `train/screen.dart:206-209`) and `keepTrainingPhase1` (`keep_training_phase1_action.dart:38-58`, from
  `graduation_screen.dart:134`, then `context.go('/train')`).
- **`redoWeek4`** copies the TRAILING week (the deload, every time), extends `plan_end` by 7 days from `plan_end` or
  from today (`today + 6` when today is past `plan_end`), so `plan_end` can land on any weekday; rows keep `week: 4`.
- **`holdWeek`** starts at `normalizeToMonday(nowWall())` (`:273`); when that is not after `plan_end` it moves to the
  Monday after `plan_end` (`:278-280`); ordinal n = 1 + max `hold_ordinal` of rows before the start (`_nextHoldOrdinal`,
  `:399-415`); copies the Peak week (`plan_start + 14..20`), every 4th the deload week (`+21..27`), stamps `week: 4 + n`,
  `is_hold: true`, `hold_ordinal: n`, resets status / completion / swap keys, keeps `phase` and `week_character` verbatim
  (`:300-325`); writes each row through `WorkoutWriteService.upsertScheduled(source: schedSwap)` (cloud
  `scheduled_workouts.week_number = 4 + n`, `sync_workout.dart:2350`); `plan_end = rollStart + 6` (`:340`); logs
  `hold_week_started` (FOB-5 consumer, migration 120); pushes plan_json after the mutex (`:376`).
- **The read gate.** `activeHoldWeeks()` / `activeHoldOrdinalFor()` (`workout_schedule_read_service.dart:1229-1235`)
  return empty / null while the flag is OFF; `weekIdentity()`, `holdSnapshotBlock()` (coach `hold` key),
  `holdStatusProvider` (`train_provider.dart:1122-1135`), the reconciler's hold gather
  (`plan_integrity_reconciler.dart:424-431, 498`) and the streak caller (`workout_completion_bookkeeping.dart:213`) all
  go through it. Ungated readers (`holdWeeks()`, `holdOrdinalForDate()`, `_withoutHoldRows`, `completedWeekNumbers`)
  already ignore the flag.
- **The UI branches.** `plan_expired_card.dart:74` (snackbar copy) and `:159-190` (ON: `_holdTheLineCta` pill +
  `_templateHint`; OFF: the "OR HOLD THE LINE — FREE" three-link layout with "Run Week 4 again"); the dev toggle
  (`dev_panel_screen.dart:265-272, 449, 471`).
- **The marker.** The week selector's W chip is gold when `w == selectedWeek` (`week_selector.dart:991`, `_WeekChip`
  `:1045-1061`); `selectedWeekProvider` defaults to the clamped `getCurrentWeekNumber()` (`train_provider.dart:1170-1179`),
  so during a hold W4 is gold. The hold chip is gold when `hold.ordinal == todayHoldOrdinal`
  (`hold_chip_group.dart:80`). So today a holder sees TWO gold chips (FOB-6's first sentence). The phase-arc strip the
  OI-175 text names was deleted on 2026-11-02 (FOB-8 is moot). The today card's word comes from `weekModeForRow`
  (`read_service:1604`): the row's `week_character` stamp wins; hold rows carry the copied Peak / deload stamp.
- **Server.** `weekly-recap-ready` (PRO only, Sunday 20:00 IST) says `Week ${current_week} debrief ready`
  (`index.ts:80`) and `weekly-report` (one lifetime free report, every PRO week) prompts `Current week: ${current_week}`
  (`index.ts:573`), both from `user_progress.current_week`, which the client fills with the clamped program week
  (`sync_profile.dart:347-354`, `currentWeekColumnProjection`): 4 for every hold week. FOB-1 forbids writing `4 + n`
  there. The coach already knows holds (`captain_manual.ts:133-160`, the snapshot `hold` block, FOB-3 closed, ai-proxy
  v108 carries it).

## 2. The change

### 2.1 The write (d57)

- `runFreeTierRepeatWrite` calls `holdWeek()` unconditionally and returns its `HoldWeekOutcome` (signature
  `Future<HoldWeekOutcome>`, was `Future<void>`). Delete `redoWeek4`, its wrapper (`workout_schedule_service.dart:241-242`),
  the flag getter `PlanEngineFlags.holdWeeksEnabled`, the dev toggle and display rows, and every OFF branch
  (`plan_expired_card.dart` snackbar and three-link layout; `_handleRedoWeek4` renamed `_handleHoldWeek`; the
  `phase_1_day_29_redo_week_4_tapped` event name stays: a stored telemetry key, renaming splits its history;
  `phase_1_cycle_repeat_started` fires only on `written`).
- `activeHoldWeeks()` / `activeHoldOrdinalFor()` keep their names and signatures and return `holdWeeks()` /
  `holdOrdinalForDate(date)` (every gated reader turns on without a call-site edit; doc comments say there is no gate).
  A stored `enable_hold_weeks` value on a tester device becomes an inert key with no reader.
- **The read cost (round 1 A-F7).** The flag used to short-circuit `_holdDatesByOrdinal`
  (`workout_schedule_read_service.dart:1158-1178`), which copies the whole workoutBox (`box.toMap()`) on every call;
  now it runs for every user on every `holdStatusProvider` / `weekIdentityProvider` rebuild and each coach send. The
  rewrite walks `box.keys` (prefix `schedule_` first, then `get`), no map copy (round 2 A-F6: equivalent filters).
  `holdStatusProvider` and `holdSnapshotBlock` each call it twice per rebuild; a test times one call on a 3,000-row
  box (365 schedule rows + wlog / exlog rows) and the diagnose doc records it. If one call exceeds 5 ms on this VPS,
  the batch adds a per-call memo keyed on the box's length and a write counter before landing (decided now, so the
  number decides, not a later batch).
- **One rule for "a hold row counts" (round 2 A-F1 / A-F2).** A hold row counts only when the current phase window
  covers it: `plan_start <= date <= plan_end`. Today the lower bound is `_holdWindowStart()`
  (`workout_schedule_read_service.dart:1150-1156`) and there is no upper bound; rev 3 adds the upper bound to
  `_holdDatesByOrdinal` and `holdOrdinalForDate` and exposes the read as two public methods,
  `latestCoveredHoldDate()` and `maxCoveredHoldOrdinalBefore(DateTime)`. The bounds compare DATES only: `plan_end` is
  stored as an ISO instant and some writers store a time of day (`PlanWindowReanchor`, restore), so the rule uses
  `DateTime(y, m, d)` of `plan_end` like `_holdWindowStart` does, inclusive (the hold's Sunday is covered) (round 3
  A-F2). Stated (round 3 A-F3): a `plan_end` moved back by a stale-cloud re-anchor (`plan_integrity_reconciler.dart:552-576`)
  makes restored hold rows past it stop counting; `sweepNonCompletedRowsPastPlanEnd` already deletes such rows on the
  next generation, so the end state is the same as today's. `_nextHoldOrdinal`
  (`workout_schedule_write_service.dart:401-418`, unwindowed today) is replaced by `maxCoveredHoldOrdinalBefore(rollStart) + 1`.
  Why: a crash-partial hold (rows written, `plan_end` not moved) is not a hold until `plan_end` covers it, so (a) a
  retry in the SAME week recomputes the same start and n and overwrites (as today); (b) a retry in a LATER week no
  longer counts the orphan rows, so n stays 1 (today: n = 2, a 3-day H1 then H2); (c) an earlier phase's holds (dated
  before `plan_start`) never inflate n for a user who held, advanced, lapsed and holds again (today they do). Orphan
  rows stay in Hive (dated before today, outside the window), invisible to every hold reader;
  `_withoutHoldRows` (`:1481`) still drops them from completion counts as today.
- **Defect A, the double tap (found by the 3D map; round 1 A-F1 / A-F2).** Today a second tap writes the NEXT hold
  early, after expiry (the first hold sets `plan_end` to this Sunday, the second call moves to the Monday after it,
  n = 2) and before expiry from the graduation screen (`keepTrainingPhase1` is not gated by expiry: tap 1 on the
  Thursday of week 4 writes H1 for next week, tap 2 writes H2 the week after). The guard: `holdWeek` returns
  `alreadyHolding` (no write, no event, no push) when `latestCoveredHoldDate()` is not before
  `normalizeToMonday(nowWall())`. Under the covered rule the `plan_end` clause is built in. Traced by round 2 seat A:
  first tap before expiry, second tap the same day, first tap after expiry, second tap two days later, the Monday after
  H1 (n = 2), crash after 3 rows and after 7 rows with a same-week retry, a tap on H1's Sunday, old-phase holds, and a
  tester's `redoWeek4` rows (no `is_hold`): all correct. The existing multi-call tests
  (`hold_week_mechanic_behavioral_test.dart:155-185, 240-244, 322-328`) advance the clock by a week between calls
  and still pass.
- **The outcome (round 1 A-F4; round 2 A-F3).** `HoldWeekOutcome { written, alreadyHolding, inFlight, noPlan, failed }`. `inFlight` is the
  `_holdInFlight` early return (`:265`); `noPlan` the null `plan_start` / `plan_end` return (`:273`, silent today: both
  callers say "Line held"). Callers: `written` keeps today's UX; `alreadyHolding` shows `Already holding this week.`
  (`PlanExpiredCard`: no `onRedoComplete`; `keepTrainingPhase1`: still `context.go('/train')`); `inFlight` does
  nothing; `noPlan` and `failed` show the existing `Couldn't schedule again. Please try again.` snackbar and stay put.
  `failed` = any row write returned a `WriteResult` that is not ok (today `holdWeek` ignores the result of every
  `upsertScheduled`, `:327-331`, and moves `plan_end` anyway): the loop stops and `plan_end` does not move, so the
  partial rows are uncovered (above) and a retry is clean. Stated (round 3 A-F6): uncovered rows dated this week are
  real `schedule_<date>` rows, so the today card can show one while the expired card still shows, until the retry or
  the next generation's `sweepNonCompletedRowsPastPlanEnd`; a kept completed row stamped before the failure keeps its
  stamps and counts nowhere (`_withoutHoldRows` drops it).
- **Refresh after the write (round 3 B-F2).** Under the covered rule a reader that ran between the last row write and
  the `plan_end` write saw no hold, and `MigratedKey.write` invalidates nothing. `PlanExpiredCard`'s callers invalidate
  after the write (`home_screen.dart:810-817`, `train/screen.dart:202-209`); `keepTrainingPhase1` (graduation) only
  navigates, so on `written` it now invalidates `currentPlanProvider` and `selectedWeekProvider` before
  `context.go('/train')`. Test: the providers built before the tap read the hold after it.
- **A completed day on a target date (round 1 A-F3; round 2 A-F3; round 3 A-F1 / A-F4).** `holdWeek` overwrites
  whatever sits at each target date (`:300-325`). The target week starts after `plan_end`, so a row there exists only
  when the user scheduled or logged something after expiry; the case that loses data is a `completed` day (a template
  day or coach log the user trained before tapping). Rev 4: a `completed` target row keeps its content, status,
  `completed_at` and keys and gains only `is_hold: true`, `hold_ordinal: n`, `week: 4 + n` (so the hold week stays 7
  contiguous hold days: `weekStart`, `holdOrdinalForDate(today)`, the chip's range and dots, the streak ordinal). Every
  other target (no row, `planned`, `rest`, a `planned` template day the user scheduled) takes the source copy, as
  today: stated. No `ifUnchangedFrom` (rev 3 had it: it compares by identity and cannot guard an absent date, round 3
  A-F1); the window between the row read and its write is one `await` in the same call. A kept completed day makes the
  H chip show its tick at once (`HoldWeekInfo.isCompleted` is any-day): stated and tested.
- **A tester's `redoWeek4` window (defect B).** A non-Sunday `plan_end` makes the first hold start inside the redo
  window. Not reachable for a real user (the method is deleted before any store launch, CLAUDE.md §1);
  `verified_clean` in the closure ledger with that reason. Likewise a tester device with `is_hold` rows from earlier
  dev toggling sees them once the gate is gone (round 2 A-F7): pre-launch data, stated.

### 2.2 The marker (d80)

- **State (round 1 B-F1).** `SelectedWeekNotifier` becomes `Notifier<SelectedWeek>` with `SelectedWeek { int week;
  bool picked }`: `build()` = (default week, false), `select(w)` = (w, true) (a new object, so selecting the week
  already shown still notifies). The one widget read (`train/screen.dart:124`) and the one test
  (`train_logged_so_far_behavioral_test.dart:178`, `.select(w)` unchanged) take `.week`. `select()` has one caller, the
  chip tap (`screen.dart:308`). The five `ref.invalidate(selectedWeekProvider)` sites (`home_screen.dart:180`,
  `hero_cards.dart:212`, `screen.dart:87, 203, 209`) and the auth rebuild reset both fields: a pick is cleared by them
  (as the selection itself is today) and during a hold no W chip is lit again. Stated, tested.
- **Lit (round 1 B-F6).** Pure `weekChipLit({week, selected, holdingToday})` where `selected` is the `SelectedWeek`:
  `week == selected.week && !(holdingToday && !selected.picked)`. `_PhaseGroup` gets `holdingToday` for the CURRENT
  phase's group only (`week_selector.dart:183`); the two PRO groups (`:209`, `:220`) pass false and are unchanged;
  `_PastPhaseGroup` does not read the selection. `WeekSelector` keeps its `final int selectedWeek` parameter
  (`week_selector.dart:47`, pinned by `week_selector_past_phases_test.dart:151-154`) and reads `picked` itself with
  `ref.watch(selectedWeekProvider).picked` (it is already a consumer, `:153`), and `holdingToday` =
  `holdStatus.todayHoldOrdinal != null` from the same `holdStatusProvider` the hold chip reads (round 2 B-F4), so the
  two never disagree. `SelectedWeek` has no `==` override (Riverpod 3 filters with `==`; a new object always
  notifies). The screen's single read (`screen.dart:124`) feeds `weekDays`, `isFutureUngeneratedPhase` and the
  `WeekSelector` argument, each taking `.week`. `_WeekChip.isSelected` is renamed `isLit` and its date sub-label
  (`:1050`) follows it, so an unlit W4 no longer prints its month-old range. Hold chips still never drive the selection.
- The week list below the chips still shows `plan.getWeek(selected.week)` (OI-125's territory).
- **The card word (round 1 A-F5, B-F2, B-F3).** Unchanged code: `weekModeForRow` returns the row's stamp, and a hold
  row carries its source week's stamp, so H1-H3 say Peak and H4 says Deload. A lifted deload source (`working`) makes
  H4's workout days say Baseline: honest, because that week's content is the working week, not a deload (d80 asked
  the card to say what the hold trains). The lift rewrites only planned, unshortened workout rows dated
  today or later (`deload_evaluator.dart:171-187`), so a lifted source week can mix `working` and `deload` rows, and
  H4 copies that mix verbatim; rest rows show no word at all (`train_provider.dart:1007`). The test uses a mixed week
  and pins the copied row stamps and the workout-day card words (round 3 B-F4). A stamp-less hold row (a row written before stamps existed) keeps returning null; the plan no
  longer changes that branch, so `train_hero_week_mode_behavioral_test.dart:185` stays as it is.

### 2.3 The server (FOB-4)

- `_shared/hold_week.ts` (new, platform tier like all of `_shared/**`):
  - pure `holdOrdinalFromWeekNumbers(weeks: unknown[]): number | null`: max `week_number - 4` over integer values > 4,
    else null (a non-integer is ignored; `week_number` has no CHECK in the cloud);
  - pure `istWeekBounds(now: Date): { monday: string; sunday: string }`: `monday = istWeekStartIso(now).substring(0,
    10)` (`_shared/ist_date.ts:63` returns `YYYY-MM-DDT00:00:00+05:30`), `sunday` = `monday` plus 6 days: parse `monday` as UTC midnight, add 6 x 86,400,000 ms, take the first 10
    characters of the ISO string (inlined, the same
    arithmetic as `nextIstDate` in `_shared/exercise_day.ts:42`, without importing that file's `uuid_v5` chain);
    tested at Sunday 14:30 UTC (the cron: this IST week) and at Sunday 18:40 UTC (= Monday 00:10 IST: the NEXT IST
    week, the bounds follow the IST date) (round 2 B-F3; round 3 B-F7);
  - pure `phaseOneUserIds(rows: {user_id, current_phase}[]): string[]` (round 3 B-F3: the phase filter lives here, not
    in each `index.ts`, so a test can reach it). Fail closed (round 4 a-F1): only a PRESENT row with
    `current_phase === 1` counts; a missing row, a null phase or a failed progress read gives no holder and today's
    wording. Measured live 2026-11-16 (read-only `GROUP BY`): phase 2 / 3 / 5 users' `scheduled_workouts.week_number`
    is 1-4 only (each phase writes its own weeks 1-4), so the filter guards a future numbering change, not today's
    data; one phase-1 tester holds hold rows (weeks 5-7) from earlier dev toggling (pre-launch data, stated: 3D-a's
    texts name those holds once deployed). Stated limit: a stale `current_phase` (a promotion not yet synced) is read
    as it is;
  - pure `recapMessage(firstName, week, holdOrdinal)`: `${firstName} — Hold H${n} debrief ready. Stand to.` for a
    holder, today's `${firstName} — Week ${week} debrief ready. Stand to.` otherwise;
  - pure `reportWeekLine(week, holdOrdinal)`: `Current week: hold week H${n} (the user chose to keep training Phase I;
    a repeat of a Phase I week)` for a holder (no Peak / Deload claim: a lifted deload makes it untrue, round 2
    B-F5), today's `Current week: ${week}` otherwise;
  - `fetchHoldOrdinals(supabase, userIds, fromDate, toDate)`: `scheduled_workouts (user_id, week_number)` with
    `scheduled_date` between the two IST date strings and `week_number > 4`, through `fetchAllByIds` (`orderBy: "id"`,
    the uuid primary key). **It never throws** (round 3 B-F1; round 4 a-F3): the `try` wraps the whole
    `fetchAllByIds` call AND the per-user reduction (a page error, a throwing builder, a non-array `data`), logs
    `[hold_week] read failed` and returns `{ map: empty, failed: true }` (its result is `{ map, failed }`, so a caller
    can tell "no holders" from "read failed", round 5 F3; the recap adds `hold_read_failed` to its response JSON and
    its console summary line, `index.ts:290-293`), and both texts fall back to today's wording. A
    throw would otherwise end the whole Sunday Brief cron run (the call sits outside `processUser`'s try/catch) or
    lose a user's report.
- `weekly-recap-ready` (PRO only, Sunday 20:00 IST) (round 2 B-F2; round 4 a-F3): the progress read selects
  `user_id, current_week, current_phase` (today `user_id, current_week`); `progressMap` becomes
  `Map<string, {week: number; phase: number | null}>` (still built only when the `allSettled` read is fulfilled); after
  it, inside the batch loop and before the per-user loop, `holdMap = await fetchHoldOrdinals(supabase,
  phaseOneUserIds(rows), monday, sunday)` (skipped, empty, when the progress read failed); `processUser(user,
  notifPrefs, progressMap, holdMap, supabase)` reads `progressMap.get(userId)?.week ?? 1` and builds the message with
  `recapMessage(firstName, week, holdMap.get(userId) ?? null)`. A phase-1 PRO user with a hold this week is one who upgraded during a hold (round 1
  B-F4: a small set).
- `weekly-report` (per-user, on demand, a trailing 7-day window `istDatesEnding(7, now)`, `index.ts:182`; round 2
  B-F1): the line describes where the user is NOW, as the app does (`holdOrdinalForDate(today)`), so it asks
  `fetchHoldOrdinals` for this one user only when `userProgress != null && userProgress.current_phase === 1` (the row
  is `.single()` with its error ignored, `:225-228`; a null row is not phase 1, round 4 a-F1) with
  `fromDate = toDate = ` today's IST date (the window's last day), and builds the line with `reportWeekLine`. A report
  asked the Monday after a hold says `Current week: 4` (no hold row today), as the app shows. Stated (round 3 B-F6): a
  hold date with no row (a missing source day, `holdWeek` `:301`, or a template placed on a hold date, which clamps
  `week` to 1..4) says `Current week: 4` in the report (as the app does that day) while the Sunday push names the
  hold (any hold row that week). Stated (round 5 F4): the cloud has no `is_hold` column and no "covered by
  `plan_end`" rule, so rows of a failed or crash-partial hold (3D-b's `failed` outcome) that already synced with
  `week_number = 4 + n` can make the push say `Hold H1` while the app shows none, until the next generation's
  sweep deletes them; cosmetic, accepted.
- Tests: `supabase/functions/_shared/hold_week_test.ts`: the five pure functions (a phase-2 user is filtered out, a
  missing row / null phase / empty input gives no ids, a phase-1 user with only `week_number <= 4` rows gets no hold
  line, a non-integer, the two cron instants: Sunday 2026-11-15 14:30Z -> 2026-11-09..15, 18:40Z -> 2026-11-16..22)
  and `fetchHoldOrdinals` against a hand-written stub client (round 4 a-F2: `postgrest_fake_fetch.ts` models no
  `gte` / `lte` / `in` and ignores ranges): the builder records `in` / `gt` / `gte` / `lte`, `.order` returns itself,
  `.range(from, to)` returns rows for `from = 0` and `[]` after (`fetchAllPages` stops only on an empty page), 101+
  ids to cross the 100-id chunk (the stub keys its `from = 0` rows by the `in` chunk it recorded for that call, and
  one chunk has no rows, round 5 F5), and two failure stubs (a `{error}` page, a throwing `.range`) -> empty map, today's
  texts and source pins (new `weekly-recap-ready/index_test.ts`, the existing `weekly-report/index_test.ts`
  comment-stripped style) that each function selects `current_phase`, filters phase 1 and calls `fetchHoldOrdinals`
  and the pure builder. `deno check --node-modules-dir=none` both functions; `deno test --no-check --allow-all
  --node-modules-dir=none` the files. Both deploy only with the founder's go (§4.3); until then the push and report
  say "Week 4", as today. Before the deploy (round 3 B-F5; `edge-function-deploy-rollback` skill §3.4): record each
  function's live version and the SHA it was built from (`get_edge_function` compared with `git show`), and the
  previous payloads (`backups/edge_function_payloads/weekly-report/`, `weekly-recap-ready/`) as the rollback; the
  plan-review record says the server half's switch is its undeployed state (no flag; platform tier; NOT the
  ship-dark tier: the record carries the full rounds and `bpass: accepted`, round 4 a-F4). 3D-a is cut from main as branch
  `generator-step3d-a` (its own worktree; this plan file is committed there), and 3D-b's branch `generator-step3d`
  is synced with main after 3D-a merges (round 5 F1). 3D-a's record `docs/plan-reviews/generator-step3d-a.md`:
  `branch: generator-step3d-a`, `review_rounds: 5` (rounds 1-3 reviewed the combined plan, 4-5 the 3D-a section; the
  record says so), `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, `bpass_review:
  docs/reviews/generator-step3d-a-bpass.md` (line-anchored bare `verdict: accepted`, a dated `## Tuning entry`)
  (round 5 F2); its commit is `feat(weekly):` with FOB-4's
  diagnose doc cited anyway. Registry (round 4 a-F4): `program_week_projection`'s two reader rows
  (`docs/sot_registry.yaml` ~13439-13453; the recap row's `172-190` is already stale, the interpolation is `index.ts:80`) get re-derived ranges and lose the "Pure interpolation, no EF redeploy
  needed" note; FOB-4 in `docs/ship_dark_pending_review.yaml` gets `code_closed:` with 3D-a's commit. Docs:
  `docs/operations/CRON_REGISTRY.md` row 061 adds the `scheduled_workouts` read; `supabase/functions/CLAUDE.md` gets a
  NEW row for `weekly-recap-ready` (it has none) and an edited one for `weekly-report`.

### 2.4 Records

- `docs/ship_dark_pending_review.yaml` (round 1 A-F8; round 2 A-F4): the four `enable_hold_weeks` entries move under
  `resolved:` with `flip_reviewed: true`, `flip_review_record: docs/plan-reviews/generator-step3d.md` and
  `flip_commit: pending — stamped in the post-merge records landing` (the file's own convention: existing entries are
  stamped by a later landing, e.g. `:291`); the stale annotation `:857` ("FOB-3, FOB-4, FOB-7(a), FOB-7(b) — STILL
  OPEN") is rewritten; `closed:` lines go on FOB-3, FOB-6, FOB-7, FOB-8; FOB-4 gets `code_closed:` (this commit) and
  `deploy_pending: founder go`, and the annotation states it does not block the flip (until the deploy the two texts
  say "Week 4", as they do today for every user).
- Closure ledger `docs/audit/generator-step3d.closure.yaml` (Gate 40; fields per `validate_audit_closure.dart:275-296`):
  - `verified_clean` (+ `evidence:`): FOB-1, FOB-2, FOB-5, FOB-7c, FOB-7d (cite each earlier closure file); FOB-6
    (split to OI-125 by the founder); FOB-7a (b9d4c2, `status: fixed`); FOB-7b (e7c4a2, `status: fixed`); FOB-8 (the
    strip was deleted 2026-11-02); defect B (pre-launch); FOB-3 and FOB3-F (the deploy leg): evidence is a LIVE check
    run during this batch: `get_edge_function` for `ai-proxy` on `dedsavbjuwgarrhphgnl` and a grep of the deployed
    bundle for `HOLD WEEKS` (the v108 deploy payload built from 862f0bc carries it; the live read is the proof, not the
    payload); FOB3-H (how hold state crosses to the server: settled by 2.3 reading `scheduled_workouts`, no column, no
    RPC).
  - `closed_in_commit` (+ `commit:` in the validator's labelled-placeholder form `:25`, stamped with the SHA in the
    post-merge records landing, + `verification:` naming the test): defect A, the covered rule, the outcome enum and
    `failed`, the target-row keep and `ifUnchangedFrom`, the read cost, the marker, FOB-4-code.
  - `blocked_on_user` (+ `reason:`): FOB-4-deploy (the two function deploys need the founder's go).
- SoT: every entry citing the flag or `redoWeek4` (round 2 A-F4 grep: `docs/sot_registry.yaml:5350, 8423, 9973-9975,
  10005, 10089, 10576-10590, 11054, 11586`; re-read each, the final grep decides) rewritten; new concepts `hold_week_marker` (writer
  `SelectedWeekNotifier.select`, reader `weekChipLit`) and `hold_week_server_signal` (writer the hold rows' cloud
  `week_number`, `sync_workout.dart:2350`; readers `fetchHoldOrdinals` in both functions; `behavioral_test_path:
  supabase/functions/_shared/hold_week_test.ts`, the Deno precedent at `docs/sot_registry.yaml:1089`, with a note that
  the two call sites are pinned by source only, round 2 B-F6). `hold_week_marker` takes
  `test/features/train/week_selector_hold_marker_test.dart` (Gate 42).
- Docs: OI-175 closed (archived to `closed_issues.md`) with OI-166's residual note; OI-125 untouched;
  `lib/features/train/CLAUDE.md` rows `hold_display_read_path` / `hold_week_identity`; `docs/naming_conventions.md:356`;
  `supabase/functions/CLAUDE.md` rows for both functions; `docs/architecture/train-detail.md` and
  `docs/operations/FOUNDER_LAPTOP_HANDOFF.md` (flag mentions); the stale "flag OFF" comments in `lib/` (round 1 A-F6
  list: `home_screen.dart:365`, `profile_content.dart:31`, `journey_timeline.dart:91, 185`, `profile_provider.dart:430`,
  `ai_snapshot_builder.dart:287`, `phase_roadmap_screen.dart:63`, `train_provider.dart:596, 610, 632, 1074, 1126`,
  `train/screen.dart:127`, `week_selector.dart:150`, `engagement_tab.dart:66`, `graduation_screen.dart:127`,
  `plan_window_reanchor.dart:58`, `service_providers.dart:121`, `workout_schedule_service.dart:10`,
  `workout_schedule_write_service.dart:8, 230, 260`, `workout_schedule_read_service.dart:8`,
  `plan_integrity_reconciler.dart:424, 498`, the gate header `scripts/check_workout_schedule_split.dart:13`), each
  grepped in `test/` first for a source pin.

## 3. Tests

- **Fixtures (round 3 A-F3):** every test that seeds `is_hold` rows by hand (`hold_week_labels_test`,
  `train_hero_week_mode_behavioral_test:185`, `day_swap_rules_test`, `hold_display_read_path_test` ~449-466 / 532,
  `hold_week_streak_identity_behavioral_test` :432-470) is checked for a `plan_end` that covers its rows.
- **Rewritten (OFF groups deleted, ON is the only world):** `hold_display_read_path_test.dart` (incl. the `redoWeek4`
  group), `hold_week_mechanic_behavioral_test.dart`, `hold_week_identity_behavioral_test.dart` ("the ONE gate"
  `:229-235` deleted), `hold_snapshot_block_behavioral_test.dart`, `hold_snapshot_block_writer_to_reader_test.dart`,
  `reconciler_gather_hold_rows_behavioral_test.dart`, `reconciler_hold_heal_split_behavioral_test.dart` (`:101`),
  `hold_week_streak_identity_behavioral_test.dart` (`:418`; the redoWeek4 regression `:432-470` renamed "plan_end
  rolled +1 week on a legacy row", its arm stays reachable), `phase_completion_excludes_holds_behavioral_test.dart`,
  `hold_telemetry_writer_reader_parity_test.dart`, `admin_hold_telemetry_renders_behavioral_test.dart`.
- **Repointed:** `workout_schedule_split_invariant_test.dart:46`; `oi189_plan_end_bound_behavioral_test.dart:951-975`
  slices from `Future<HoldWeekOutcome> holdWeek()` to `_nextHoldOrdinal(` (not a fixed length); the SoT
  forbidden-pattern regex `:10590`; comment-only mentions in `oi166_unit2_regen_content_cycling_behavioral_test.dart`
  and `plan_week_for_date_behavioral_test.dart` reworded. After the edit `grep -rn "redoWeek4\|holdWeeksEnabled\|enable_hold_weeks" lib test scripts docs/sot_registry.yaml docs/architecture docs/operations supabase`
  lists only history notes the plan names.
- **New `test/contracts/hold_week_d57_behavioral_test.dart`** (real Hive, `nowWall()` pinned through its seam;
  the pre-expiry double tap is the exact Thursday-of-week-4 case):
  the free-tier write with no flag set (both callers; `PlanExpiredCard` through a real `WidgetRef` captured from a
  `Consumer` in `testWidgets`, Hive I/O in `tester.runAsync`); the double tap after expiry and before expiry ->
  `alreadyHolding`, no write, no `hold_week_started`; the Monday after H1 -> H2; a crash-partial hold -> re-written
  the same week, same n, `plan_end` extended; a crash-partial hold retried a week later -> n = 1, the orphan rows
  invisible to `holdWeeks()`; an earlier phase's hold rows do not raise n; a failed row write (the third of seven,
  through a new `@visibleForTesting` hook on `WorkoutScheduleWriteService` that wraps its `upsertScheduled` call) ->
  `failed`, `plan_end` unmoved, a same-day retry writes the whole week; a completed target row kept with all three hold stamps and its content (Monday and today cases); a tap on
  H1's Sunday and a graduation tap on week 4's Sunday (round 3 A-F5); the clock seam set back one week; a `plan_end`
  stored with a time of day still covers the hold's Sunday (round 3 A-F2); the graduation path's providers read the
  hold after the tap (round 3 B-F2); `noPlan` shows the error and `phase_1_cycle_repeat_started` fires only on
  `written`; an H1-then-H2 box (max, not min) and a same-day crash retry (`<`, not `<=`); a completed day on a target date keeps status / content / logs and gains the hold
  stamps (Monday and today cases: `weekStart` and `holdOrdinalForDate(today)` hold); `inFlight`; `noPlan` -> the error
  snackbar; the read-cost timing (recorded only).
- **New `test/features/train/week_selector_hold_marker_test.dart`:** the `weekChipLit` table; during a hold W4 is not
  lit and H1 is; a tap on W2 lights W2; a tap on W4 lights W4 (select of the shown week notifies); an invalidation
  clears the pick (no W chip lit); a PRO-locked W5 chip unaffected; the sub-label only on a lit chip; H1 says Peak
  and H4 says Deload from copied stamps, a lifted-deload H4 says Baseline.
- **Deno:** `supabase/functions/_shared/hold_week_test.ts` plus the source pins.
- **Mutations (one at a time, nothing else compiling):** the unconditional call back to a flag read (the mutant
  reinstates the getter, default false); the guard
  removed; the guard without its `plan_end` clause (crash-partial goes red); the guard keyed on today's week only
  (pre-expiry double tap goes red); the completed keep removed; `inFlight` mapped to `written`; `weekChipLit`
  ignoring `picked`; ignoring `holdingToday`; `holdingToday` passed to a PRO group; the server phase filter removed;
  the ordinal off by one; `_holdDatesByOrdinal` dropping the `is_hold` check or the `schedule_` prefix; the upper
  bound as `<` (the Sunday drops); the keep stamping `week` without `is_hold`; `noPlan` mapped to `written`;
  `fetchHoldOrdinals` without its catch; the covered rule's upper bound removed
  (later-week retry goes red); its lower bound removed (old-phase holds go red); a failed
  row write still moving `plan_end`; the graduation invalidation removed; the recap's `fetchHoldOrdinals` call removed (the source pin); the week bounds in
  UTC; `week_number > 4` dropped.
- No golden changes (the generator is not touched). The full suite on CI.

## 4. Order of work

**3D-a (server, first):** `_shared/hold_week.ts` and its tests; `weekly-recap-ready` and `weekly-report` wiring and
source pins; `deno check` + `deno test`; docs (CRON_REGISTRY, functions CLAUDE.md, SoT `hold_week_server_signal`);
diagnose doc (FOB-4); plan-review record (rounds 1-3 shared + one 3D-a round); PR, CI, B-pass, merge; then the
founder's go for the two deploys (live SHA recorded first).

**3D-b (client flip, second):**
1. Flag + `redoWeek4` deletion, `runFreeTierRepeatWrite`, the covered rule, the guard, the completed keep, the outcome
   enum and both callers, the graduation refresh; the 11 rewritten test files, the repointed greps, the fixtures.
2. The marker (2.2) with its tests.
3. Records (2.4; FOB-4 cites 3D-a), the diagnose doc (full template: the hold class has history: d7f3a9, c8b3f2,
   a3f8d1, f4c8e1, d5b8f3, b6e1f4, e7c4a2, b9d4c2, d7f3b2), the plan-review record (full ×2 + B-pass, §4.12.4: this
   commit removes a ship-dark flag), the FOB-3 live check (`get_edge_function` grep for `HOLD WEEKS`).
4. Gate loop, PR, CI, B-pass, merge; founder device check (t308).
