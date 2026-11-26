# Plan v3: past weeks inside the Train list (retire the "Completed history" sheet)

Branch `train-history-sheet-style`. Founder decisions 2026-11-26: option B (tap a past
chip, the Train list itself shows that week), same rows as the current week, no popup;
a missed day behaves as Train already treats a missed day; nothing is capped; OI-530
(plan_json size) is filed separately and is NOT part of this plan.
Mockup: `docs/mockups/2026-11-26-train-past-week-in-place-v4.html` (v3 + a week label line).

**Tier: account** (blast radius): one new reader lands in `lib/core/services/**`
(`WorkoutReadService`) and one copy string in `lib/core/copy/wardroom_copy.dart` (`lib/core/**`);
the final tier is COMPUTED with `scripts/blast_radius_from_diff.dart <paths>` after the last edit
and recorded. The merge therefore needs this record, `bpass: accepted`, and the full suite on a
main push. The D1 refactor runs for every user's Train screen, so verification is full-pipeline.
Execution mode (section 4.12.7): **inline**, one worktree, one writer. Reviews use fresh subagents.
v3 = rounds 1-2 applied; rounds 3 and 4 were convergence checks (section 7). `pastWeekRangeLabel` lives
in `lib/features/train/services/past_week_days.dart` (pure) and is imported by `week_selector.dart`.

## 1. Problem (verified 2026-11-26, founder account d7a67a37, Fri 16 Oct)

1. The Train week list and the "Completed history" sheet are two renderers of the same
   `schedule_*` rows. The sheet (`week_selector.dart` `_PastWeekSheet` / `_PastDayRow` /
   `_ExerciseLine` / `weekExerciseLineDetail`) was built 2026-05-23 (`218069ce`) and never
   followed the Train redesign: different row, chips, icons, and its OWN detail formatter.
2. Formatter drift is user-visible: the sheet prints a 20 s hold as `0 min`
   (`(durationSec / 60).round()` in `weekExerciseLineDetail`) and omits reps; Train's
   `exerciseLogDetail` (`train/utils/exercise_log_detail.dart:12`) prints `20s` and reps. A day
   with logs but never completed read "Not completed" over 40 exercises.
3. The 40 exercises on Fri 16 Oct are real cloud rows (`workout_log_exercises`,
   workout_log_id `f9204a65-...` = UUID v5 of `workout_2026-10-16`, 40 live rows pushed in a
   45 s burst at 03:29 IST 18 Oct). The sheet showed them correctly. Not a defect of this
   batch; the cause is not established. Cleaning that test data is a founder action through the
   app's Edit Log, outside this plan.

## 2. Verified facts the design rests on (file:line, worktree at 02f70bf8)

- Train list render: `screen.dart:123-125` `plan.getWeek(selectedWeek)`; `screen.dart:324`
  `_buildCompactWeekRows(context, weekDays)`; `week_rows.dart:65` takes ANY
  `List<WorkoutDayData>`. Row status comes from the day's own fields and dates
  (`week_rows.dart:143-170`), not the plan window.
- `plan.getWeek(w)` = `WorkoutScheduleReadService.getWeek` (`:1435-1451`): each of 7 dates goes
  through `getScheduleForDate` (`:1063`), which returns null for terminal `moved` / `dropped`
  rows (`terminalScheduleStatuses`, `:1045`) and demotes a completed row whose `completed_at`
  date is earlier than the row date (`:1093-1107`). A raw `schedule_<date>` read does neither.
- `getScheduleForDate(DateTime)` keys the box with `_dateKey(date)` = `formatDateKey` =
  `istDateStr` (`workout_schedule_read_service.dart:2451`, `date_utils.dart:26-28`,
  `ist_date.dart:94-98`: `t.toUtc().add(+5:30)`). A date built with `DateTime.parse('2026-10-12')`
  is LOCAL midnight and reads the previous day's row on a device east of UTC+5:30. The current
  list already has this property (`getWeek` adds days to `DateTime.parse(plan_start)`, and the D1
  builder parses the row's date with `DateTime.tryParse`); parity with it is kept, not widened.
- Current-phase day objects are built inline: `train_provider.dart:962` `for (int w ...)`,
  `:966` `for (final dayMap in weekDays) {`, BODY `:967-1017` (closing `}` `:1018`; uses only
  `w` and `finisherContext` from outer scope); the "NO PLAN" placeholder days `:1020-1030` belong
  to the OUTER loop and stay there. The body upper-cases `workout_name` and defaults a null name to
  `'Rest Day'`. `_parseExerciseMaps` / `_parseFinisherMaps` are file-private, so the builder lives
  in `train_provider.dart`. `workoutDayForDate` (`:758`) is a third constructor and stays untouched.
- `selectedWeekProvider` = `SelectedWeek{week, picked}` (`train_provider.dart:1179-1209`); its
  `build()` already watches `authUserIdTokenProvider` (`:1190`). `select` makes a new instance each
  call and the class has no `==`, so a watcher is notified on every tap (flutter_riverpod ^3.3.1).
  Hold chips never call `onSelect` (rule `hold_display_read_path`). Invalidators:
  `screen.dart:87,202,208`, `hero_cards.dart:212`, `home_screen.dart:181`,
  `keep_training_phase1_action.dart:47`; a background restore reaches `screen.dart:86-87` through
  `invalidateOnRetry`. `restoreCompletedTick` is ALSO bumped by day rollover
  (`day_rollover_service.dart:171`) and `pro_phase_advance.dart:741,754`.
- Screen uses of `selectedWeek` / `weekDays`: `_buildPlanHeader(plan, selectedWeek)` `:169`
  (`plan_header.dart:48-49` prints `TRAIN · WK $selectedWeek OF n · PHASE p`, or the HOLDING pill
  during a hold), `showsTrainHeroSlot(selectedWeek: ...)` `:190`, the "Viewing Week N plan" card
  `:~219-262`, the empty-week branch `:316`, the list `:324`, the strip `selectedWeek:` `:278`.
  Providers guard the sign-out window with `token == '<anon>'` (`train_provider.dart:868-872`,
  `day_swap_provider.dart:106`); `TrainScreen` wraps `_buildContent` in a try/catch that replaces the
  whole tab with "Failed to load workouts" (`screen.dart:99-119`).
- The strip: `week_selector.dart:146` `_toPastPhases(...)`, `:185` past chip tap, `:299-310`
  `_showPastWeekSheet`; `_PastPhase.entriesForWeek(w)` = the rows chip `w` lists; each
  `_ScheduleEntry.key` is `'schedule_$dateStr'` (`:356`), the exact stored date string. All three
  `_PhaseGroup`s (`:196-235`) receive one `selected` lit by `weekChipLit` (`:1085`, signature pinned
  by `week_selector_hold_marker_test.dart`); `HoldChipGroup` is a fourth group lit from
  `todayHoldOrdinal` (`hold_chip_group.dart:80,116`), not from `selectedWeek`.
- Swap on past days: `DaySwapRules.lockOf` (`lib/core/services/day_swap/day_swap_rules.dart:82`,
  past check `:92`) refuses `date < today`; `DaySwapRowTrailing` shows the arrow only when
  `state.movable`; the drag wrapper starts no drag for a non-movable row
  (`day_swap_drag_wrapper.dart:81,154`). The "swaps left this week" footer (`week_rows.dart:50-60`)
  is added for ANY list with a dated day, so it must be suppressed.
- Row taps (`week_rows.dart:174-193`): done -> inline expand; rest-with-logs -> inline; today ->
  inline; any other past or future day -> `_showExercisePreviewSheet`, which lists a not-done day's
  logs above its plan (`exercise_preview_sheet.dart:25-50`, decision F). A done row's expansion
  and the done-day preview read `WorkoutRepository.getExerciseLogsForDate` (the OI-377 duplicate
  reader), while the `N EX` count here reads `WorkoutReadService`.
- Log reads: `WorkoutReadService.exerciseLogsForIstDate` (`workout_read_service.dart:387-415`) is
  index-first but falls back to `box.toMap()` over the whole box when `exercise_log_index_<date>`
  is missing or empty, i.e. for every day without logs; `datesWithExerciseLogs()` (`:367`) is a
  key-only pass. `_buildCompactWeekRows` already uses the key pass once per build on purpose.
- Restore: `_restoreScheduledWorkouts` writes a name and exercises only when hydrated from a
  template (`sync_workout.dart:~2795-2850`, hydration `:2846-2848`); a plan-generator past row can
  arrive name-less and exercise-less. `CompletedTitleHealer` is narrower than "heals names":
  completed rows only, after a SUCCEEDED full restore, skips template rows, `logged` rows,
  placeholder log names and `cloud_restore_completion` logs, and never writes `exercises`. The
  contract `completed_title_follows_log` (OI-284): a COMPLETED row's title is its `wlog_<date>`
  name. `kPlaceholderWorkoutNames` is compared trim + lower-case (`workout_write_service.dart:71`,
  `coach_day_completion.dart:136`).
- New devices restore ALL history first (`sync_service.dart:1934` `since = '2020-01-01...'`).

## 3. Design

Writers/readers (section 4.1): rows are written by the existing schedule writers and
`markCompleted` (unchanged). Past rows had TWO readers (the strip chips and the sheet); they
become one list renderer fed by the strip's own chip dates.

**D1. Shared day-object builder.** Extract the BODY `train_provider.dart:967-1017` into
`WorkoutDayData workoutDayDataFromScheduleRow(Map<String,dynamic> dayMap, {required int w,
required FinisherShowContext finisherContext, int? exerciseCountFallback})` in
`train_provider.dart`, called by `currentPlanProvider` (behaviour unchanged, fallback null) and
by D3. `WorkoutDayData` gains a nullable `exerciseCountFallback`; `exerciseCount` = `exercises.length`
when non-empty, else the fallback, else 0 (every current reader: `week_rows.dart:256`,
`hero_cards.dart:138`, `today_workout_card.dart:63`, gets null and is unchanged;
`estimatedDuration` reads `exercises`). `workoutDayForDate` is not unified.

**D2. Past selection state.** `PastWeekSelection {int phaseNumber, int weekInPhase,
List<String> dates, String phaseStart}`; `dates` = the raw stored date strings of the chip's entries
(`entry.key` minus `schedule_`); `phaseStart` = the raw date string of the group's FIRST entry
(`_PastPhase.startDate`, which is not always a Monday). The chip's range text is
`startDate + (w-1)*7` (`week_selector.dart:559-567`) and cannot be rebuilt from `dates` (empty for a
chip with no rows), so ONE pure function `pastWeekRangeLabel(String phaseStart, int weekInPhase)`
(UTC date arithmetic, `Oct 12–18` / `Oct 26–Nov 1`) replaces `_PastWeekChip._dateRange` and also feeds
the label line and the chip's Semantics label: three readers, one implementation. `pastWeekSelectionProvider` (`Notifier<PastWeekSelection?>`, default null) watches
`selectedWeekProvider` (which itself watches the auth token), so a current/future chip tap, every
`ref.invalidate(selectedWeekProvider)` and an account switch reset it. Real reset triggers, stated:
a background restore, a day rollover, a PRO phase advance, a hero action and the invalidators above
close an open past view; accepted (it is a transient view; the label below always says where the
user is). Tapping the lit past chip again clears it. `ExpandedDayNotifier.build()` watches
`pastWeekSelectionProvider`, so any change collapses the expanded row index. The dates are frozen at
tap time; they stay valid because a re-bucketing of history only happens on restore/merge, which
resets the selection.

**D3. Past week day objects.** `pastWeekDaysProvider` (`List<WorkoutDayData>?`): returns null for
`token == '<anon>'` (read via `authUserIdTokenProvider`) or no selection; watches
`pastWeekSelectionProvider` and `currentPlanProvider` (precedent `daySwapWeekProvider`; completion,
edit-log, coach log, swap and regeneration all invalidate `currentPlanProvider`; NOT added to
`workoutSurfaceProviders`, which is account tier and pinned by its own test). Per build it takes ONE
key pass `logDates = WorkoutReadService.instance.datesWithExerciseLogs()` and the finisher context
once. The count read goes through a small seam provider `pastDayLoggedCountReaderProvider`
(`Provider<int Function(String ymd)>`, default `(d) => WorkoutReadService.instance
.exerciseLogsForIstDate(d).length`) so a test can override it with a counting function. Per date it builds a DateTime with a pure helper `pastWeekDateTime(String ymd) =>
DateTime.utc(y, m, d, 12)` (maps to the same IST date on every device) and reads the row through the
existing public `WorkoutScheduleReadService.getScheduleForDate` (reached through
`workoutScheduleReadServiceProvider`): the SAME visibility rules as `getWeek`; null rows are skipped.
Each row is built inside its own try/catch: a malformed row is skipped and reported with
`ErrorTelemetry.logEvent('past_week_row_skipped')`, never thrown into `_buildContent`.
A pure function `pastDayView(row, {wlogName, loggedCount})` in
`lib/features/train/services/past_week_days.dart` returns the row copy handed to D1:
- name, COMPLETED row: the `wlog_<date>` name when non-empty and not a placeholder (trim +
  lower-case match against `kPlaceholderWorkoutNames`), else the row's `workout_name` when not a
  placeholder, else the generic; this is the `completed_title_follows_log` contract and the old
  sheet's precedence;
- name, NOT-done row: the row's `workout_name` when non-empty and not a placeholder, else the
  wlog name, else the generic (`'Workout'` for a workout row, `'Rest Day'` for a rest row); the
  D1 builder upper-cases whatever it is given, so fallbacks render as `WORKOUT` / `REST DAY`;
- count: nothing when the row has exercises (the builder uses their length); when `exercises` is
  empty AND the date is in `logDates`, `loggedCount` = `exerciseLogsForIstDate(date).length`
  (index-first because the date has logs); never a read for a date without logs.
The wlog name is read only for a completed row or a nameless one, by key, through the new reader
`WorkoutReadService.workoutLogNameForIstDate(String)` (+ static `workoutLogName(Object?)`, `is Map`
guard, beside `workoutLogDurationSeconds`). Widgets never read Hive.

**D4. Train screen.** `_buildContent` reads `pastDays = ref.watch(pastWeekDaysProvider)`;
`inPastView = pastDays != null`. In a past view `selectedWeek` is `plan.currentWeek`, so the header
(WK n OF m, or the HOLDING pill), the hero card (`holdTodayDay` for a holding user) and the future-
phase cards behave exactly as for the current week and the "Viewing Week N plan" card does not
appear; `weekDays` (the current week) serves only that hero/today logic. The list slot is `if (inPastView) ...[label line, past list or empty copy] else if (weekDays.isEmpty)
_buildEmptyWeek(...) else _buildCompactWeekRows(context, weekDays)`: the existing `if (weekDays.isEmpty)`
branch and its arguments stay literally as they are, because `train_phase_lock_empty_state_test.dart`
searches `screen.dart` for `if (weekDays.isEmpty)` and pins `_buildEmptyWeek(`,
`isFutureUngeneratedPhase(selectedWeek)` and `currentPhase: plan.phase` inside fixed windows, plus the
`else if (!(isFutureUngeneratedPhase(selectedWeek) &&` line; that test must stay green UNCHANGED.
The `selectedWeek` variable keeps its name (it holds the effective week). **A label line above the list** (mockup v4): a mono gold eyebrow
`PHASE IV · WEEK 1 · OCT 12–18` built from the selection (`phaseRoman`, the chip's own range),
wrapped in `Semantics(liveRegion: true)` so the swap is announced. The new providers live in `train_provider.dart` beside `selectedWeekProvider` (no import cycle). A selection that resolves to zero
rows shows `WardroomCopy.trainPastWeekEmpty` = "No workouts recorded for this week." instead of rows.
The allowance footer is suppressed for a past list (`showAllowanceFooter` argument on
`_buildCompactWeekRows`, default true). The `WeekSelector(` ... `// Compact week rows` source window
pinned by `reactive_subscription_three_sites_test.dart` stays in place and in order.

**D5. Strip.** `WeekSelector` gets OPTIONAL `pastSelection` and `onSelectPast` (it is constructed in
`week_selector_hold_marker_test.dart`). A past chip tap calls `onSelectPast(selection)` (a re-tap of
the selected chip calls it with null). While a past selection exists the strip is given
`selectedWeek: 0`, so no W chip in any of the three phase groups is lit (no `weekChipLit` signature
change); only the selected past chip is gold (`_PastWeekChip.selected`, same tokens as the current
chips) and gets `Semantics(button: true, selected: ..., label: 'Phase IV week 1, Oct 12 to 18')`.
A HOLDING user keeps today's `H` chip lit (it means "you are here"; `HoldChipGroup` lights from
`todayHoldOrdinal`): accepted and fixture-pinned. DELETED: `_showPastWeekSheet`, `_PastWeekSheet`,
`_PastDayRow`, `_ExerciseLine`, `derivePastDayLog`, `weekExerciseLineDetail` and their imports.
`HoldWeekSheet` is untouched. A past hold week (an extended chip group) renders ordinary rows with
no `H` label: stated, fixture-pinned.

**D6. Scale (founder question: a two-year user).** No production change: the box scan in
`_scheduleRowsBefore` is behaviour-neutral to rewrite and no problem is measured. A guard test seeds
a synthetic two-year box (about 730 schedule rows over 26 phases, 4,000 `exlog_`, 500 `wlog_`) and
asserts that `pastPhaseBlocksForDisplay` AND a full `pastWeekDaysProvider` build over a week of
missed, completed, nameless-with-logs and nameless-no-logs rows finish under an absolute budget set at the larger of
1,000 ms and 10x the time measured on this 4-core VPS when the test is written (never a ratio;
runner speed varies 2x). The measured numbers go into the diagnose-doc. The time budget guards gross regressions only; the structural rule (no per-row whole-box read) is
killed by test 1 through the counting seam, not by this timing test. If the measured time is not comfortably
inside the budget the code is fixed in this batch before the test is committed.

**D7. Preview sheet.** Today a NOT-done day with logs and empty `exercises` (a restored, never-completed
day) shows the heading `LOGGED`, the log rows, then `SizedBox(10)` + the label `PLANNED EXERCISES`
(built inside `notDoneLogRows`, `exercise_preview_sheet.dart:~43-49`), then the text "No exercises
scheduled" (`:~284`, rendered when `day.exercises.isEmpty`). Change, minimal: when
`notDoneLogs.isNotEmpty && day.exercises.isEmpty`, omit the `SizedBox`, the `PLANNED EXERCISES` label and
the "No exercises scheduled" line. Everything else stays (a not-done day with NO logs and NO exercises
still shows "No exercises scheduled"; a day with planned exercises is unchanged,
`train_logged_so_far_behavioral_test.dart:~516` stays green). Test.

No feature flag (section 4.6 lists payment/sync/auth/AI/plan generator; this is a UI read path).
Revert = revert the commit.

## 4. Tests (behavioural first; every fix cites its test)

1. `test/contracts/train_past_week_in_place_behavioral_test.dart` (new, pumps the real Train
   screen/provider stack; follow the GoogleFonts and Hive-close-hang pitfalls in section 4.9).
   Fixtures: (A) TWO past phases: a Monday-start phase IV holding the founder's Oct 12-18 week as its W1
   (6 planned workout days + a rest day, exlogs on Fri; the `OCT 12–18` label, chip and Semantics
   assertions are made on THIS chip) and, before it, a phase that STARTS ON A WEDNESDAY with rows past
   day 28 (test 1 taps its W2 chip and asserts the label line text, the Semantics label and the chip's own
   dates; M2 and M20 are killable only here, because on W1 the first row IS `phaseStart`); (B) a holding user.
   Asserts: same row widgets, `N EX` = planned count; missed style; a Fri tap opens the preview sheet
   with its logs and the list length equals the logged exercises; a completed past day expands inline
   with `exerciseLogDetail` text (`20s`, reps) and its list length matches; the label line text and
   its live region; ONLY the selected past chip is lit among the W chips of all three groups (fixture
   A) and, for the holder (fixture B), the `H` chip stays lit and the hero shows; the header, hero and
   no "Viewing Week" card read as the current week even when the user had picked another week first;
   the footer is absent for the past list and present for the current list; `dropped` and `moved` rows
   are absent; a chip whose rows are all hidden shows the empty copy; a restore-shaped completed row
   (no `workout_name`, no `exercises`, a `wlog_` name, some `exlog_` rows) shows the wlog name and the
   logged count; a completed row whose row name says "Push" and whose log says "Pull + Core" shows
   "PULL + CORE", and a NOT-done row shows its own name; a re-tap of the lit chip and a current-chip
   tap leave the view; a malformed row is skipped without breaking the screen; the signed-out
   `<anon>` token returns null without throwing.
2. `test/contracts/workout_day_data_from_row_test.dart` (new): literal expected `WorkoutDayData`
   values captured from the CURRENT `currentPlanProvider` BEFORE the extraction (the golden
   fixture covers a hold row, a finisher, `weekMode`, `budgetMinutes`, `dayNumber`, a rest row and a
   completed row; the captured output is pasted into the diagnose-doc), plus `pastDayView` and `pastWeekRangeLabel` cases (incl. a month-crossing range and a Wednesday phase start) for
   every row shape above, `pastWeekDateTime` (`isUtc`, `hour == 12`, and `istDateStr` of it equals the
   input), and `exerciseCountFallback` readers unchanged when null.
3. Selection lifecycle (unit): reset on a current-chip tap (including the same week), on
   `ref.invalidate(selectedWeekProvider)`, on an account change; the expanded index collapses on
   enter, leave and reset; an `ref.invalidate(currentPlanProvider)` (the completion / edit-log /
   coach-log shape) refreshes `pastWeekDaysProvider`.
4. Scale guard (D6) and the Preview-sheet test (D7) and a semantics test for the selected past chip.
5. Tests 2 and 3 and the pure helpers (`pastWeekDateTime`, `pastWeekRangeLabel`) also run once under
   `TZ=Etc/GMT-8`, the result recorded in the diagnose-doc. Test 1 runs under the CI zone only: the D1
   builder keeps `DateTime.tryParse` (local midnight, parity with the current list, section 6), so its
   preview and expansion assertions are IST-zone by construction.
6. Repointed, NOT loosened (grep `test/` and `scripts/` for every literal moved or deleted BEFORE
   editing, section 4.9): `week_selector_past_phases_test.dart` (pins `_PastWeekSheet`, `:134-140`),
   `past_phase_display_runs_behavioral_test.dart` (its helper still reports what each chip lists),
   `past_phase_display_recovery_behavioral_test.dart`, `past_week_history_derives_from_logs_test.dart`
   (its intent is re-asserted through the new path; it states the precedence above),
   `cardio_duration_distance_writer_to_reader_test.dart` (the pin on the sheet formatter moves to
   `exerciseLogDetail`), `week_selector_reads_current_phase_test.dart`,
   `reactive_subscription_three_sites_test.dart`, `week_selector_hold_marker_test.dart`,
   `week_completion_check_test.dart`, `train_screen_compact_layout_test.dart`,
   `phase_roman_single_source_test.dart`, `test/widgets/week_rows_kill_switch_test.dart`,
   `test/contracts/day_of_week_canon_writer_to_reader_test.dart`,
   `scripts/check_week_selector_phase_labels.dart`. Must stay green UNCHANGED (run, not edited):
`test/contracts/train_phase_lock_empty_state_test.dart` (see D4). Tests that read `expandedDayProvider` bare now
   pull `selectedWeekProvider` and the auth token through the new watch and need Hive and auth
   overrides: `expanded_exercise_log_row_test.dart:258`, `finisher_sections_test.dart:155`,
   `train_logged_so_far_behavioral_test.dart:173`, `coach_chat_log_train_refresh_behavioral_test.dart:173`
   are run explicitly.
7. Registry and docs, same commit. `docs/sot_registry.yaml` has NO `past_week_history_display`
   concept (do not invent it). Re-pin EVERY concept whose `line_range` cites ANY touched file
   (`train_provider.dart`, `screen.dart`, `week_rows.dart`, `week_selector.dart`,
   `exercise_preview_sheet.dart`, `workout_read_service.dart`, and `cardio_duration_distance`, which
   cites `weekExerciseLineDetail` and must be repointed) FROM ANCHORS after the last edit, then run
   `check_sot_registry_parity.dart` (a symbol outside its range is an ERROR there). Update
   `docs/architecture/functionality-flow.md` (TRAIN-04 still says "Tapping opens a read-only
   `_PastWeekSheet`"), `docs/architecture/train-detail.md` (~:115), `lib/features/train/CLAUDE.md`
   (`week_completion_check` row, the selection, the precedence rule), `docs/naming_conventions.md`
   (`PastWeekSelection`, `pastWeekSelectionProvider`, `pastWeekDaysProvider`,
   `workoutDayDataFromScheduleRow`, `pastDayView`, `pastWeekDateTime`, `workoutLogNameForIstDate`,
   `exerciseCountFallback`, `trainPastWeekEmpty`, `pastWeekRangeLabel`, `pastDayLoggedCountReaderProvider`) and regenerate `backups/gate19_drift_baseline.txt` if
   the gate asks.
8. Mutation proof (rule 21): each mutant applied, `grep -c` confirms it applied, then the new tests
   run; each must redden at least one named test. M1 selection not reset by `selectedWeekProvider`
   (test 3); M2 dates recomputed instead of the chip's own (needs the Wednesday-start fixture, test
   1); M3 footer not suppressed (1); M4 D1 drops `status` (2 golden); M5 W chips still lit in a past
   view (1); M6 no collapse on selection change (3); M7 `<anon>` guard removed (1); M8
   `pastWeekDaysProvider` does not watch `currentPlanProvider` (3); M9 raw `schedule_<date>` read
   instead of `getScheduleForDate` (1, dropped/moved fixture); M10 a throwing row not caught (1);
   M11 wlog-name fallback removed (1/2); M12 count fallback removed (1/2); M13 `pastWeekDateTime`
   uses `DateTime.parse` (2, `isUtc` assertion); M14 empty copy removed (1); M15 completed-row
   precedence reversed (1/2); M16 `Semantics.selected` removed (4); M17 count read without the
   `logDates` / empty-`exercises` guard (killed by test 1: a nameless, no-exercises, NO-LOGS row is in the
   fixture and the overridden counting reader must never be called for its date); M18 the `H`-chip fixture's hero removed (1); M20 the label/chip range built from the first ROW's date
   instead of `phaseStart` (1, Wednesday-start fixture, and 2);
   M19 D7 label guard removed (4).

## 5. Process

Diagnose-doc `docs/diagnoses/2026-11-26-history-sheet-second-renderer-<id>.md` (FULL template; grep
the new id first), recurrence: writer/reader drift (two renderers + a hand-rolled formatter copy;
related `f4e1d9`, `5c8e2a`, OI-389 / OI-50 "seven readers each got it wrong", OI-377 duplicate
reader). Memory: a `feedback_*` entry "a second renderer of a Train row copies the formatter, never
the redesign". Gate loop (section 4.12.8): `flutter analyze --no-fatal-infos` on the whole project and
the pre-commit gate loop locally; the full suite from CI through `sh scripts/land_pr.sh <pr>
--ci-only`. B-pass (`/code-review`) before the merge. Founder device check afterwards: tap a past
chip on the phone, the list matches the current week's look under the label line, Fri 16 Oct opens its
preview with the logs, a hold shows `20s`.

## 6. Deliberate behaviour changes and out of scope (each stated, none silent)

Dropped from the old sheet on purpose, because the Train list does not show them: the completed-at
`HH:mm`, the "N exercises · Completed" subtitle, inline expansion of a NOT-done day with logs (now
Train's preview sheet), and `moved` / `dropped` rows (Train hides them). The completed-day name
precedence is kept (log first); the not-done precedence follows Train (row first).
Out of scope: OI-530 plan_json size (filed); deleting the test data on 16 and 25 Oct (founder, through
Edit Log); the unexplained Push Up `1 min` of the OLD sheet (its formatter is deleted; Train's never
prints a time for a bodyweight row); `workoutDayForDate` (untouched); the local-midnight `DateTime`
parse that the CURRENT list also uses on devices east of IST (parity kept; the new date helper is
UTC-based); the chip tick reading the raw status while the list reads the demoted one (pre-existing,
only for a day completed before its scheduled date); the OI-377 duplicate exlog reader; the current
chips having no `Semantics` (only the past chip, which gains a selected state, gets one).
Product wording reconciled with the mockup: a past week's ROWS have no START and no swap/drag; the
hero card above the strip is today's and keeps its own START.

## 7. Review dispositions

Round 1 (2 seats, fresh Sonnet; every item verified before use): raw read vs `getScheduleForDate`
(accepted, D3); invalidation and `workoutSurfaceProviders` (D3); header/hero/week card (D4);
two other lit groups (D5); tier (header); missing tests/docs and a non-existent registry concept (4.6,
4.7); restored rows losing name/exercises (D3); line cites (section 2); `istDateStr` shift, frozen
dates, expanded index (D2, `pastWeekDateTime`); mutants and self-referential golden test (4.8, 4.2);
scale fix conditional (see round 2); Semantics (D5); MOVED/drag/hold rows (D5, section 2).
Round 2 (2 seats, fresh Sonnet; verified before use): `getScheduleForDate` re-derives the key from a
local DateTime, so the raw-string care did not reach D3 (accepted; `pastWeekDateTime` UTC helper,
M13 now killable by the `isUtc` assertion, a TZ=Etc/GMT-8 run); the per-row `exerciseLogsForIstDate`
hides a whole-box scan (accepted; one key pass + guarded read, M17); D1 body range 967-1017 and other
line cites (section 2); name precedence reversed against the old sheet and `completed_title_follows_log`
(accepted; completed rows log first, M15); unkillable M7 (replaced) and M13; scale test did not exercise
the key iteration (the iteration change is DROPPED: no measured problem; the test now guards D3);
`N EX` vs list readers (stated, OI-377); hold fixture and the lit `H` chip (accepted, fixture B);
restored not-done day shows "PLANNED EXERCISES" over nothing (accepted, D7); silently dropped old-sheet
behaviour (section 6); optional `WeekSelector` params, live region (D4/D5); chip tick vs demoted list and
real reset triggers (section 6, D2); registry re-pin scope (4.7); tests reading `expandedDayProvider`
bare (4.6); `<anon>` guard, per-row try/catch, lower-case placeholder match (D3); label line and exit
path (D4/D5, mockup v4).

Round 3 (convergence, fresh Sonnet): 5 P1 plan-text errors (selection lacked the phase start for the
label; a TZ run over tests that cannot pass there; `train_phase_lock_empty_state_test.dart` literal; D7
wording; M17 unkillable) all verified and patched. Round 4 (fresh Sonnet): converged; one wording patch
(fixture A vs M20) applied. `preview_sheet` empty-list arm: the `...(isEmpty ? [...] : [...])` branch needs
an empty-list arm for the omitted line (build detail). Tier recorded in `docs/plan-reviews/
train-history-sheet-style.md`.
