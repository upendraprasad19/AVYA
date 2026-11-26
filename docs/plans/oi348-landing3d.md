# OI-348 Landing 3d (P3): rescue a missed workout into today

Status: CONVERGED. Round 1 (2 P1) and round 2 (3 P1) folded; per CLAUDE.md §4.12.1 the unit was SPLIT after round 2:
the per-row restore guard (old 3.5) is a pre-existing hole for EVERY day swap and leaves as its own OI and session
(3.5). Round 3 (narrow) found one P1 in a TEST claim (MS1's bound is false on main itself) and four P2; all folded as
plan-text / test-spec fixes, no change to the converged mechanism (section 7).
Branch / worktree: `oi348-landing3d`, off main `8cd4556f`. Blast radius `platform` (`day_swap_rules.dart`,
`streak_progress_service.dart`, `user_repository.dart` classify platform; `swap_service.dart` account). Tier L
(sync restore + freeze merge + streak). Execution: inline, one author (reviews by context-blind Sonnet agents).

## 1. Observation and decisions
Founder phone walk of AAB +50 (22 Nov), finding P3: a workout missed earlier this week cannot be done later; the
swap picker shows past days as PAST. Decided in principle 22 Nov, four detail calls locked 26 Nov
(`project_oi348_landing3cd_brainstorm_inflight.md`):

1. **Partner.** A past (missed) day may swap ONLY with TODAY, ONLY when today is a REST day, only inside the same
   Mon-Sun IST week. Missed = a planned training row before today with no `wlog_`/`exlog_` for that date (not
   stored; derived).
2. **Old day.** Shows the MOVED tag like any swap and counts as rest for the streak.
3. **Freeze.** A streak freeze spent on the missed day is REFUNDED when the day is rescued.
4. **Allowance.** The rescue spends the weekly swap (free 1, PRO 3). `consume-day-swap` EF unchanged (date-blind).

## 2. Writers and readers (file:line on main 8cd4556f, re-read this session; R1 confirmed the cites)
- Past lock: `DaySwapRules.lockOf` `lib/core/services/day_swap/day_swap_rules.dart:82-103`, `:92`
  `date.compareTo(today) < 0 -> past`, precedence completed -> paused -> past -> started -> ...
- Engine: `SwapService._firstLock` `lib/core/services/swap_service.dart:176-195` (both dates, `lockOf` each);
  `_hasLoggedSets` `:168-174` returns false for any non-today date (correct today, because past is locked first;
  wrong under P3); `weekStates`/`_stateOf` `:199-223`; `preview` `:227-255`; `swapDays` -> `_withWeekLock` ->
  `_swapDaysInWeek` `:262-403` (allowance check, `_firstLock`, `buildSwap`, write, `recordSwap`, `_pushPlan`).
- Content move: `DaySwapRules.landed` `:156-175` moves status/type with the content and never deletes; missed Wed
  (planned) <-> rest Fri leaves Wed = `type: rest, status: rest, is_swapped: true, original_date: Fri`, Fri = Wed's
  workout, `status: planned, is_swapped, original_date: Wed`. `isMoved` `:106` = MOVED tag on both.
- Atomic write: `WorkoutWriteService.swapScheduledDays` (`workout_write_service.dart`, completed-row guard
  `:877-878`); no date guard of its own.
- Streak walk (freeze SPEND): `WorkoutRepository._calculateStreak`
  `lib/features/train/repositories/workout_repository.dart:423-600`: `type == 'rest'` skipped `:531`; a used date
  skipped `:542`; a fresh missed day spends a freeze `:565-572`; persisted by `StreakProgressService.commitConsume`
  `:589-597`. Reckon `reckonStreakDecayAndPersist` `:338-359`, called by `DayRolloverObserver._doRolloverWithRef`
  (`lib/core/services/day_rollover_service.dart:241-247`, after `refillIfNewWeek` `:220-226`) and completion.
- Freeze writer (sole writer): `StreakProgressService` `lib/core/services/streak_progress_service.dart`:
  `commitRefill` `:64-105`, `prunePastHorizon` `:112-115`, `commitConsume` `:169-207`, `mergeFreezeProgress`
  `:403-453` (same week: LOWER `available`, UNION ledger: "never refund a freeze").
- Merge callers: `_restoreFreezes` (`sync/sync_restore_completeness.dart:390`), the push conflict retry
  `_retrySyncFreezesOnceAfterConflict` (`:128-284`, merges twice), `UserRepository._mergeFreezeFamily`
  (`lib/shared/repositories/user_repository.dart:840-953`; grant carry `:891-901` counts "local used dates the
  cloud has not seen" `:892-893`).
- Push: `syncFreezes` (`sync_restore_completeness.dart:34-119`) -> `update_streak_progress` (migration 115:
  overwrite on version match, NULL on mismatch -> client merge retry). Cloud column `text[]`, no CHECK; available
  `BETWEEN 0 AND 3` (migration 072).
- Per-row schedule restore: `_restoreScheduledWorkouts` `lib/core/services/sync/sync_workout.dart:2542`, status
  merge `:2611-2650` (cloud status wins unless local `completed` / terminal), type `'rest'` forced when the cloud
  status is rest `:2810-2812`, rest-content strip `:2860-2870`. Cloud `scheduled_workouts` has NO timestamp column
  (`backups/live_schema_columns.json`: id, user_id, template_id, scheduled_date, week_number, day_of_week, status,
  completed_at, created_at). Order: `_restoreWorkoutPlan` (plan bundle, L1/L3) runs BEFORE it
  (`sync_service.dart:1936-1962`), so it is the LAST writer of `schedule_<date>`.
- Freeze chip: `streakFreezeProvider` (`lib/features/home/providers/home_provider.dart:358`).
- UI: `SwapPickerSheet` (`lib/features/train/widgets/swap_picker_sheet.dart`, per-target `d.lock` `:91,:123`, no
  source check: the pre-existing Home bug), `DaySwapDragWrapper` (`day_swap_drag_wrapper.dart:81-85`, accept
  `:140`), `DaySwapRowTrailing` (`:55`), past Train rows render both (`week_rows.dart:288,:321`),
  `SwapConfirmSheet` toast (`swap_confirm_sheet.dart:181-186`), `DaySwapController._refresh`
  (`day_swap_provider.dart:66-93`).
- Coach: lookahead today..+6 only (`ai_snapshot_builder.dart:1362-1412`); BUT the coach tool path
  (`tool_dispatcher.dart:1048` -> `swapDays(origin: coach)`) takes model-supplied dates.
- Copy: `DaySwapCopy.pickerFooter` `lib/core/services/day_swap/day_swap_copy.dart:183`.

## 3. Design

### 3.1 Kill switches
- `configBox['disable_missed_day_rescue'] == true` disables the rescue (rules, refund, UI pair rule, footer, the
  rollover refund settle). Default (absent) = ON. Read once in `SwapService.missedDayRescueEnabled()` and passed
  into pure rules as `bool rescue`. With it set, every state, preview and swap is identical to main (T-K).
- The freeze merge's refund accounting is not switched: it acts only on `refund:` markers, which only a rescue
  writes; with no markers its output equals the old rule (M6 table test).
- Removal of the switch goes on the OI-348 board row in this landing's commit (a deliverable, section 3.7).

### 3.2 Pure rules (`day_swap_rules.dart`)
- `isRescueHost(row)`: `row != null && row['type'] == 'rest' && row['status'] == 'rest'` (a hybrid is NOT a host:
  landing a hybrid on the past date would read as a missed workout to the walk, R1-3).
- `isMissed({date, row, today, hasLogs, inProgressDate})`: `date < today`, `row != null`, `status == 'planned'`,
  `!isRest(row)`, `!hasLogs`, `inProgressDate != date`.
- `rescueLockOf(...)`: past date when a rescue is possible: `completed` / `paused` as `lockOf`; `isMissed` -> null;
  anything else -> `past`.
- `pairLock(dateA, dateB, today)`: if either date is before today and the other is not today -> `past` (pure, shared
  by engine, picker and drag).

### 3.3 Engine (`swap_service.dart`)
- `_hasAnyLogs(date, logDates)`: `logDates.contains(date)` (ONE `WorkoutReadService.datesWithExerciseLogs()` key
  pass per call, R1-9) or `wlog_<date>` present.
- `_rescueOn(origin)`: switch on AND `origin != DaySwapOrigin.coach` (the coach never sees past days; a
  model-supplied past date keeps today's `past` refusal, R1-7). `preview` gains an optional `origin` (R2-7):
  `DaySwapController.preview(dateA, dateB, {origin})`, and `tool_confirm_card.dart:378` passes
  `DaySwapOrigin.coach`, so the coach card and the coach apply give the same answer. `weekStates` stays
  origin-free (the picker and Train only; the coach snapshot lists today..+6, so a past state never reaches it).
  `SwapConfirmSheet` passes its own `widget.origin` to `preview` too (R3-4), so no caller relies on the default.
- `_lockFor(date, row, {today, inProgressDate, rescue, logDates})`: `date >= today` -> `lockOf` (unchanged); past
  and `rescue` -> `rescueLockOf`; else `lockOf`.
- `rescue` for a week = `_rescueOn` AND today is in that week AND `lockOf(today) == null` AND
  `isRescueHost(today row)`.
- `weekStates`: today's state first, derive `rescue`, then every date via `_lockFor`.
- `_firstLock`: switch off -> today's two `lockOf` calls verbatim. Switch on: `pairLock` first, then `_lockFor` on
  both with `rescue` from the LIVE rows inside the write lock (the host is one of the pair).
- After write + `recordSwap`, on a rescue: `StreakProgressService.instance.settleRescueRefunds(isPro: isPro)`
  (3.4) in try/catch (`day_swap_freeze_refund_threw`), then `WorkoutRepository.instance.
  reckonStreakDecayAndPersist()` in try/catch (R1-4: a chain the missed day broke is re-counted and the cloud
  `current_streak_days` refreshed). `DaySwapDone.freezeRefunded` (default false). `day_swap_done` message gains
  `rescue=1 refund=<n>` on a rescue.

### 3.4 Freeze refund (`streak_progress_service.dart`)
Ledger `streak_freeze_used_dates` (cloud `streak_freezes_used_dates`, `text[]`) gains `refund:<YYYY-MM-DD>`. The
plain date STAYS (still "covered", so a device whose schedule lags never spends on it again). No migration.
- `FreezeLedger` (pure): `dates`, `refunds`, `marker(date)`, `isMarker`.
- Durable rescue mark on the row (R2-6: the row SHAPE `rest + is_swapped` is also reachable without a rescue, e.g.
  a swap made earlier on another device arriving by restore after this device's walk spent on that day): inside the
  swap `build`, on a rescue, the past date's landed row gets `rescued_into: <today>` (a string key, written after
  `landed`; added to `DaySwapRules.markerKeys` so `contentOf` never carries it to another date (R3-2); new key
  appended to `docs/naming_conventions.md`). The hold-week and copy-week writers copy whole rows but reset
  `is_swapped` to false (`workout_schedule_write_service.dart:338-348`, `:525-539`), so the refund test below also
  requires `is_swapped == true`.
- DERIVED, idempotent refund (R1-5: a crash between the swap write and the refund cannot lose it):
  `settleRescueRefunds({required bool isPro})` -> number refunded. For each plain ledger date D with
  `DaySwapRules.mondayOf(today) <= D < today` (R2-5: the current week only, so a Monday rollover never refunds last
  week's day against the new stock; R3-3: the string form, equal to `istMondayKey(nowWall())` that `commitRefill`
  stamps) and no `refund:D`, whose `schedule_<D>` row has `type == 'rest'`, `is_swapped == true` and a string
  `rescued_into` with `D < rescued_into` in D's own week:
  `available = min(available + 1, isPro ? 3 : 1)`, add `refund:D`. One `updateProgress` write for all, notice count
  lowered (flag cleared at 0), `syncFreezes()`, event `streak_freeze_refund_done before= after= dates=`. Callers: the
  engine after a rescue and `DayRolloverObserver._doRolloverWithRef` after `refillIfNewWeek`, before the reckon
  (tier from the PURE `SubscriptionService.instance.proStateSnapshot()`), both behind the rescue switch. It only
  reads the local ledger and local rows, so running before the restore settled is safe (R2-9); it never reorders
  the settle-then-credit rule (it is a separate call after `refillIfNewWeek`).
- `prunePastHorizon`: a marker is kept/pruned by its date.
- `mergeFreezeProgress` (R1-1 corrected): a side is raised by +1 for each marker `refund:D` that the OTHER side has,
  it lacks, AND whose plain date D it HOLDS (it debited that spend), dated on/after that side's `last_refill`:
  - same week: raise both sides that way, take the LOWER;
  - cloud refill newer: cloud count + qualifying local-only markers (cloud holds D);
  - local refill newer: local count + qualifying cloud-only markers (local holds D) (R1-1 P2);
  - then `clamp3`; `scheduleSyncUp` also when local holds a marker the cloud lacks.
  A side that never saw the spend is never raised, so a spend can never be refunded twice and a free count cannot
  exceed what it had before its own spend this week (cap safe, test M-cap). Why "holds D" also covers a D that came
  into a ledger by an earlier UNION (R2-3): every branch that unions D into a ledger in the same week sets that
  side's count to the LOWER of the two, i.e. at most the count of the side that debited D; cross-week unions bring
  only dates before that side's `last_refill`, which the date bound excludes. Proven by sequence tests, not
  hand-picked states (section 4, MS1-MS3).
- `_mergeFreezeFamily` grant carry counts plain dates only (`FreezeLedger.dates`).

### 3.5 The per-row restore race: SPLIT OUT (R1-2 verified, R2-1/R2-2)
Verified (R1-2): `_restoreScheduledWorkouts` (`sync_workout.dart:2611` status merge, `:2810` rest type, `:2860`
rest strip) takes the cloud's `planned`/`rest` status over the local one, and the cloud row has no timestamp. A
restore that runs before ANY swap's push lands (offline swap, then a relaunch) turns the local workout row into
`rest` and strips its exercises, and gives the other row `type rest` + `status planned`. This is NOT new with the
rescue: an ordinary Fri<->Sat swap has the identical exposure today. R2 showed the guard this plan first proposed is
wrong in two ways (template days re-gain `template_id`, the b6e1c8 hybrid; `arranged_at_ms` is carried forward on
every later `upsertScheduled`, so the guard would be permanent and diverge two devices after a confirmed push). A
correct fix needs "is this row's swap still unpushed?" from the sched `SyncSkipIndex` and its own ×2 review, so it
is filed as OI-532 (by `scripts/mint_oi.sh`, in this landing's commit: "a stale per-row schedule restore undoes an
unpushed day swap") with the evidence above, and proposed to the founder as its own session. This landing does not
change the restore path; the rescue has exactly an ordinary swap's exposure, no more.

### 3.6 UI
- Picker: target lock = `d.lock ?? pairLock(source, d.date, today)` (switch on).
- Pre-existing Home bug: a locked SOURCE shows `DaySwapCopy.sourceLockedLine(reason, date)` ("Wednesday has
  already passed. It stays put.") and no day rows.
- Drag: `isValidTarget` also needs `pairLock(lifted, date, today) == null`.
- Footer (switch on): `DONE, STARTED, PAUSED AND PAST DAYS STAY PUT · A MISSED DAY CAN TAKE TODAY'S REST DAY`.
- Toast: `freezeRefunded` -> body ends ` Your Streak Freeze is back.` (picker + confirm sheet).
- `DaySwapController._refresh` also invalidates `streakFreezeProvider`.

### 3.7 Docs (deliverables)
Spec decision 4 + §5.2 rule 2 amended; `docs/sot_registry.yaml` (`day_swap_engine.class_constraints`, the freeze
ledger concept's marker shape, each with `behavioral_test_path:`); `lib/core/services/CLAUDE.md`,
`lib/features/train/CLAUDE.md`, `lib/features/home/CLAUDE.md` (day-swap rows); `docs/naming_conventions.md`
(`rescued_into`, the `refund:` marker); OI-348 board row (switch removal); the new restore-race OI (3.5); diagnose
doc (full template).

## 4. Tests (behavioural)
New behaviour (fail on main): T1, T7*, T8, T-W(movable), T-P, M1-M4b, M8-M9, MS1-MS3, picker/drag rescue cases.
Regression guards (pass on main by construction; teeth from mutations b, f, g, h, j): T2-T6, T-K.
`test/services/day_swap/missed_day_rescue_test.dart` (real Hive, engine harness; today = Fri 25 Sep 2026):
- T1 missed Wed + rest Fri(today): done; Wed rest+MOVED+`rescued_into: Fri`; Fri = Wed's workout MOVED; allowance 1.
- T2 today a workout day: `past`. T2b today a hybrid rest (status rest, workout type, no exercises): `past`.
- T3 partner not today (Wed <-> Sat rest): `past`. T3b `swapDays(origin: coach)` Wed <-> Fri(host): `past`.
- T-P `preview(origin: coach)` for the same pair: `past`; `preview()` (no origin): no refusal.
- T4 Wed has an `exlog_`: `past`; T4w only a `wlog_`: `past`; T4b Wed in progress: `past`.
- T5 past rest day: `past`; past completed: `completed`.
- T6 free allowance spent: `allowanceSpent`.
- T7 freeze spent on Wed (ledger [Wed], free, 0): available 1, ledger [Wed, refund:Wed], `freezeRefunded`; T7b no
  spend: none; T7c `settleRescueRefunds` twice: one refund; T7d refund seam throws: swap done, the next
  `settleRescueRefunds` refunds; T7e PRO at 2 -> 3, never above the cap; T7f a last-week rescued day on a Monday:
  no refund; T7g a ledger day whose row is `rest + is_swapped` WITHOUT `rescued_into`: no refund.
- T8 after T7, `currentStreak()` passes Wed (rest), no new spend; a chain Wed had broken (no freeze) is restored
  and `current_streak_days` is persisted by the reckon.
- T-K switch set: T1/T7 inputs refused `past`, no `rescued_into`, `weekStates` locks equal main's.
- T-W `weekStates`: Wed movable only with a host today; `preview` reason == `swapDays` reason for refusals by
  allowance, logs, not-a-host.
`test/core/streak_freeze_refund_merge_test.dart` (pure): M1 cloud stale before the spend: kept; M2 cloud saw the
spend, not the refund: kept; M3 other side never saw the spend and spent Thu: 0, not 1; M4 cloud refill newer +
local marker (cloud holds D) +1, (cloud lacks D) +0; M4b local refill newer + cloud-only marker; M5 marker before
last_refill: no raise; M6 marker-free table equals the old rule; M7 prune by marker date; M8 `_mergeFreezeFamily`
carry ignores markers and its push decision settles after one round (no loop); M9 `scheduleSyncUp`; M-cap a free
side never exceeds 1 (also after a PRO lapse clamp mid-week).
Sequence tests (R2-3, same file): a small simulator of two devices + cloud applying a fixed event set (refill,
spend, rescue-refund, push with the conflict-retry merge, restore) in EVERY interleaving (2 devices x 4 events):
MS1 (R3-1: the old rule already over-counts two devices' different spends, so no stock-minus-spends bound holds on
main) the merged count never exceeds the OLD rule's result on the same states plus the number of distinct
qualifying markers, and no date D is ever refunded twice across the whole sequence; MS2 `merge(merge(a,b),b) ==
merge(a,b)` (idempotent) and, for equal `last_refill`, `merge(a,b) == merge(b,a)` on `available` and the ledger set
(symmetric); MS3 with no rescue events every result equals the old rule's. The simulator calls the pure
`mergeFreezeProgress` and MODELS the conflict-retry's two merges (`sync_restore_completeness.dart:206-215` and
`:271-282`, inline in an async method that needs Supabase); it does not exercise that method.
- T8b after a refund, a stale restore re-plants Wed as a planned workout: the walk spends nothing on Wed (the plain
  ledger date is kept) and `settleRescueRefunds` refunds nothing more.
- T7h a copy-week / hold copy of a rescued row onto this week's spent date earns no refund.
- Coach card call site: a widget test of `ToolConfirmCard`'s swap preview for a past pair shows the refusal the
  apply gives (so dropping `origin: coach` at `tool_confirm_card.dart:378` reddens it).
Widget `test/widgets/swap_picker_rescue_test.dart`: from today (rest) Wed and Sat pickable; from Wed only today;
from Sat Wed is not pickable; locked source shows the reason line and no rows; footer per switch; toast refund line.
Pure `pairLock` table (used by the drag wrapper).
Mutations (each once, `cp` + `cmp` restore; reddened counts in the diagnose doc): (a) `isMissed` ignores logs;
(b) `pairLock` returns null; (c) refund skips the +1; (d) merge drops the "holds D" condition; (e) prune treats
markers as before; (f) `_firstLock` ignores the switch; (g) `isRescueHost` accepts a hybrid; (h) `_hasAnyLogs`
ignores `wlog_`; (j) coach origin allowed; (k) settle drops the Monday bound; (l) settle keys on the row shape, not
`rescued_into`; (m) `rescued_into` removed from `markerKeys` and the `is_swapped` check dropped (T7h); (n) the
coach card drops `origin: coach` (coach card test).

## 5. Gates before review dispatch with code
`flutter analyze --no-fatal-infos` (whole project), the pre-commit gate loop (incl.
`check_sot_behavioral_test_paths.dart`), targeted tests, then PR + CI green.

## 6. Risks
- An OLD build (+50) merging a marker keeps it (union) but takes the lower count: the refund can be lost on that
  device's merge until a new build pushes. Pre-launch testing accounts only.
- Under-refund only (R2-4): if the Monday credit lands on one device before it merges another device's refund of a
  last-week day, the marker is older than its `last_refill` and does not raise it.
- The per-row restore race (3.5) stays exactly as it is for every swap until its own OI lands. One rescue-specific
  consequence (R3-5): if that race undoes a rescue, the refund and its marker stay (the user keeps the freeze and
  sees the workout back on the past day; the kept plain date stops a second spend, T8b).

## 7. Review dispositions
| R | Sev | Disposition |
|---|---|---|
| R1-1 merge raises a side that never debited | P1 | 3.4 "holds D" rule, M3/M4/M4b |
| R1-2 `_restoreScheduledWorkouts` clobbers | P1 | verified; pre-existing for every swap; split to its own OI + session (3.5) |
| R1-3 hybrid host | P2 | `isRescueHost` needs `type rest`, T2b, mutation g |
| R1-4 no streak recompute | P2 | reckon after a rescue, T8 |
| R1-5 refund not atomic | P2 | derived `settleRescueRefunds` + rollover caller, T7d |
| R1-6 free cap | P2 | commit clamps by tier; merge raise bounded, M-cap |
| R1-7 coach tool | P2 | rescue off for `DaySwapOrigin.coach`, T3b, mutation j |
| R1-8 test teeth | P2 | section 4 split + mutations |
| R1-9 weekStates cost | P2 | one `datesWithExerciseLogs()` pass |
| R1-10 docs | P2 | 3.7 list |
| R2-1 guard + template_id | P1 | guard split out (3.5) |
| R2-2 guard permanent per row | P1 | guard split out (3.5); the new OI records the skip-index requirement |
| R2-3 merge proven only by hand-picked states | P1 | argument in 3.4 + sequence tests MS1-MS3 |
| R2-4 Monday-credit under-refund | P2 | stated in section 6 |
| R2-5 rollover refunds last week | P2 | Monday bound, T7f, mutation k |
| R2-6 row shape reachable without a rescue | P2 | durable `rescued_into` mark, T7g, mutation l |
| R2-7 coach preview vs swap | P2 | `preview(origin:)`, the coach card passes coach, T-P |
| R2-8 tests | P2 | T3b via `swapDays(coach)`, M8 no-loop, M-cap lapse, MS |
| R2-9 rollover placement, gates | P2 | stated in 3.4; gate loop in section 5 |
| R3-1 MS1 bound false on main | P1 (test) | MS1 restated vs the old rule + one refund per D; simulator models the retry |
| R3-2 `rescued_into` carried by copies | P2 | in `markerKeys`; refund also needs `is_swapped`; T7h, mutation m |
| R3-3 `istMondayKey` takes a DateTime | P2 | `DaySwapRules.mondayOf(today)` |
| R3-4 confirm sheet origin; card untested | P2 | sheet passes `widget.origin`; coach card test, mutation n |
| R3-5 restore undoing a rescue keeps the refund | P2 | stated in section 6, T8b |
