---
bug_id: d6e3b8
date: 2026-11-26
batch: train-history-sheet-style
status: fixed
tier: m_fix
blast_radius: account
symptom: >-
  Founder, 2026-11-26 (account d7a67a37, a test account): the "Completed history" sheet a past week chip opens looked
  nothing like the Train screen's current week, and "Fri (Phase IV Week 1, 2026-10-16)" listed 40 exercises, which the
  founder knew they never logged in a day. Two causes. (1) Two renderers of the same entity: the sheet
  (`_PastWeekSheet` / `_PastDayRow` / `_ExerciseLine` in `week_selector.dart`) had its own look, its own hand-copied
  detail formatter (`weekExerciseLineDetail`) and its own name/exercise derivation (`derivePastDayLog`), so every Train
  row redesign (compact rows, the muted missed row, `exerciseLogDetail`) skipped it. (2) The sheet listed every
  `exlog_*` row of the date (test rows logged through Edit Log: 40 on Oct 16, 22 on Oct 25), not the planned or the
  completed day. The cleanup of those test rows is a founder action in Edit Log and is not part of this fix.
  Founder decision (option B): tapping a past chip shows that week in the Train screen's OWN list, same rows, no popup;
  a not-completed day is a missed row; no cap on exercises.
concept: past_week_in_place
sot_registry_entry: past_week_in_place
writers:
  - file: lib/features/train/widgets/week_selector.dart
    method_or_widget: _WeekSelectorState._selectPast (picked week = the chip's own stored dates)
    line: 310
  - file: lib/features/train/providers/train_provider.dart
    method_or_widget: PastWeekSelectionNotifier (build watches selectedWeekProvider; select toggles)
    line: 1271
readers:
  - file: lib/features/train/providers/train_provider.dart
    method_or_widget: pastWeekDaysProvider (getScheduleForDate(pastWeekDateTime(ymd)), pastDayView, per-row try/catch)
    line: 1296
  - file: lib/features/train/providers/train_provider.dart
    method_or_widget: workoutDayDataFromScheduleRow (extracted VERBATIM from currentPlanProvider; shared by both lists)
    line: 804
  - file: lib/features/train/services/past_week_days.dart
    method_or_widget: pastDayView / pastWeekDateTime / pastWeekRangeLabel / pastDayWantsLogName
    line: 1
  - file: lib/core/services/workout_read_service.dart
    method_or_widget: workoutLogName / workoutLogNameForIstDate (the wlog_<date> workout_name, by key)
    line: 299
  - file: lib/features/train/screens/train/screen.dart
    method_or_widget: _buildContent (effective week = plan.currentWeek in a past view; the list slot)
    line: 129
  - file: lib/features/train/screens/train/week_rows.dart
    method_or_widget: _buildCompactWeekRows(showAllowanceFooter) / _buildPastWeekLabel / _buildPastWeekEmpty
    line: 65
  - file: lib/features/train/screens/train/exercise_preview_sheet.dart
    method_or_widget: logsOnly (a day with logs and no stored exercises omits the empty PLANNED EXERCISES block)
    line: 37
hive_key_prefix: schedule_
hive_key_formula: "schedule_<yyyy-MM-dd> read through getScheduleForDate(DateTime.utc(y, m, d, 12)); wlog_<date> by key; exlog_ through the date index"
sync_methods: []
restore_methods: []
cloud_table: n/a
cloud_columns: []
contract_test_path: test/contracts/train_past_week_in_place_behavioral_test.dart
ist_handling:
  - "pastWeekDateTime(ymd) is UTC noon, so istDateStr maps it back to the SAME date on every device. A local-midnight DateTime.parse reads the previous IST day on a device east of IST (TZ=Etc/GMT-8 in the pure test)."
  - "pastWeekRangeLabel does UTC date arithmetic (no DST drift); the chip, the label line and the chip's Semantics label share it."
  - "workoutDayDataFromScheduleRow keeps DateTime.tryParse (local midnight) exactly as the current list does: parity, plan section 6. This zone dependence PRE-EXISTS (the unmodified code fails the golden under TZ=Etc/GMT-8 the same way)."
provider_invalidations:
  - "pastWeekDaysProvider watches currentPlanProvider: completion, edit-log, coach log, swap and regeneration already invalidate it (test: a completion refreshes the picked past week). Not added to workoutSurfaceProviders."
  - "pastWeekSelectionProvider watches selectedWeekProvider: a current/future chip tap, ref.invalidate(selectedWeekProvider) and an account switch reset the view; ExpandedDayNotifier.build watches the selection so the expanded index collapses on a pick."
telemetry_op_types:
  success: []
  failure:
    - past_week_row_skipped
cross_account_guard: "pastWeekDaysProvider returns null for the '<anon>' auth token (a2d9f4 window) and reads only user-scoped boxes through the existing services"
forbidden_patterns_checked:
  - "a second row renderer or a copy of a formatter for the past list - REJECTED: ONE builder (workoutDayDataFromScheduleRow) and ONE renderer (_buildCompactWeekRows); the sheet, _PastDayRow, _ExerciseLine, derivePastDayLog and weekExerciseLineDetail are deleted"
  - "a per-row whole-box read (exerciseLogsForIstDate falls back to a toMap() scan for a date with no index) - REJECTED: the count is read only for a row with NO stored exercises AND a date in the ONE key pass datesWithExerciseLogs(); a counting seam proves it (M17)"
  - "recomputing the chip's dates from the group start - REJECTED: the dates are the chip's own rows (M2)"
  - "a raw schedule_<date> read - REJECTED: getScheduleForDate carries the visibility rules (moved/dropped rows hidden) (M9)"
  - "a cap on exercises per day - REJECTED by the founder (no cap); the missed/completed split is the cure for the 40-exercise day"
  - "a feature flag - NOT USED: UI read path (section 4.6 lists payment/sync/auth/AI/plan generator); revert = revert the commit"
proposed_fix: >-
  D1 extract the Train day-object builder from currentPlanProvider into workoutDayDataFromScheduleRow (golden-captured
  BEFORE the move) and give WorkoutDayData a nullable exerciseCountFallback; D2 PastWeekSelection +
  pastWeekSelectionProvider (reset by selectedWeekProvider, collapses the expanded row); D3 pastWeekDaysProvider with the
  pure pastDayView (completed day: wlog name, row name, generic; not-done day: row name, wlog name, generic;
  placeholders skipped; count only for a row with no stored exercises and a date with logs); D4 the Train screen shows
  that list under a "PHASE I - WEEK 1 - OCT 7-13" label line (live region), header/hero keep the current week, no
  allowance footer, empty copy WardroomCopy.trainPastWeekEmpty; D5 the strip lights only the picked past chip
  (selectedWeek: 0 for the W chips), Semantics button/selected/label, pastWeekRangeLabel replaces the chip's own range
  code; the sheet and its helpers are deleted; D6 no production change, a budgeted scale guard; D7 the preview sheet
  omits the empty PLANNED EXERCISES block and "No exercises scheduled" for a day whose logs are its content.
regression_test_planned:
  - test/contracts/train_past_week_in_place_behavioral_test.dart (17 tests plus the font warm-up: rows, names, counts, real count reader, no cap with 12 logs and a timed set, footer, label, Wednesday-start W2, dropped/malformed/empty, completion refresh, stale picked week, holding user, semantics incl. the tap action, D7 sheet, selection lifecycle)
  - test/contracts/past_week_days_pure_test.dart (pastWeekDateTime, pastWeekRangeLabel, pastDayView precedence/count, workoutLogName)
  - test/contracts/workout_day_data_from_row_test.dart (GOLDEN, captured from the unmodified provider)
  - test/contracts/past_week_scale_guard_test.dart (two-year box, absolute budget)
  - repointed, not loosened: week_selector_past_phases_test.dart, past_week_history_derives_from_logs_test.dart, cardio_duration_distance_writer_to_reader_test.dart (T26 now pins exerciseLogDetail)
mutation_proof: >-
  24 mutants (plan M1-M20, plus M21-M24 for the B-pass fixes: the chip Semantics tap action, the notifier toggle, the
  stored-title fallback, the real count reader), each applied by an exact-match replace (refused on 0 or 2+ anchor matches, confirmed by a
  changed file), run against the four new/related test files, restored by cp and byte-compared. 24 of 24 red. Reddened
  tests per mutant: M21 1, M22 1, M23 1, M24 2, M1 1, M2 2, M3 2, M4 2, M5 1, M6 1, M7 1, M8 1, M9 3, M10 1, M11 3, M12 1, M13 1, M14 2, M15 2, M16 1,
  M17 1, M18 1, M19 1, M20 1. One survivor on the first run: M4 (isDone: false) was anchored on workoutDayForDate
  (line 787), not on the extracted builder (line 849 then); re-anchored on the builder it reddens the golden and one
  behavioral test. Runner: session scratchpad mutants.py / run_mutants.sh. Self-attested.
impact_analysis: >-
  Deliberate behaviour changes, none silent: (1) the Completed-history sheet is gone; (2) a past week renders as
  ordinary Train rows (a not-completed day is the muted "-" missed row, a dropped or moved row is hidden as in the
  current week); (3) a completed past day takes its title from the wlog_<date> row (completed_title_follows_log), a
  not-done day keeps its own row name; (4) no cap on exercises: a day that really holds 40 logs shows 40 (the cure
  is Edit Log); (5) the HoldChipGroup H chip stays lit during a past view (it means "you are here"); (6) a past hold
  week (an extended chip group) renders ordinary rows with no H label; (7) any background restore, day rollover, PRO
  phase advance, hero action or selectedWeekProvider invalidation closes an open past view (a transient view, the label
  line always says where the user is). Scale (founder question, a two-year user, all Hive, no Postgres call): 728
  schedule rows over 26 phases, ~3,700 exlog and 14 wlog rows, the picked week including a nameless day whose logs have
  no index entry (the whole-box fallback) and a nameless day with no logs: pastPhaseBlocksForDisplay 120 ms, a full
  past-week build 57 ms on the 4-core VPS (budget max(1000 ms, 10x measured) = 1000 ms); the app renders one week at a time, so there is
  no growing list to hang. The exlog fallback scan (a date with exlog_ keys but no index entry) is unchanged and is reached only for the
  nameless no-stored-exercise days of the picked week that hold logs; a restored key with no date inside it is not
  counted (the same key-only limit as the current list's hasLogs; ExlogKeyMigrator rewrites those keys).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "D1-D7 as listed in writers/readers; flutter analyze --no-fatal-infos clean on the project" }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "read-only path over schedule_/wlog_/exlog_; real-Hive behavioral tests; the goldens pin the builder output" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no cloud read or write" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "none touched (the plan_json size is OI-530, separate)" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "none touched" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "none touched" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "none touched" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "none touched" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "none touched" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "none" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "no server contract; restored rows (no name, no exercises) are covered by the nameless-with-logs and completed-nameless fixtures" }
recurrence: >-
  Recurrence of the writer/reader drift class, in its "second renderer copies the formatter" form: f4e1d9 (the same
  sheet rendered a generic Workout with no exercises for a restored row; fixed by deriving from logs, which is what then
  listed 40 test rows), 5c8e2a (the sheet listed only some days of its week), OI-389 / OI-50 ("seven readers each got it
  wrong", the sheet's weekExerciseLineDetail was one of them), OI-377 (a duplicate reader). The cure this time is
  structural: one builder, one renderer, so a future row redesign cannot skip the past list.
related_bugs:
  - f4e1d9
  - 5c8e2a
  - e7240a
  - docs/diagnoses/2026-06-01-past-week-history-generic-workout-f4e1d9.md
---

## What was wrong

See `symptom`. Plan: `docs/plans/train-past-week-in-place.md` (v3 + round-4 patch). Review record:
`docs/plan-reviews/train-history-sheet-style.md` (4 rounds, converged).

## Writer and reader

Rows are written by the existing schedule writers and `markCompleted` (unchanged). Past rows had TWO readers (the strip
chips and the sheet); they are now one list renderer fed by the strip's own chip dates: `_selectPast`
(`week_selector.dart:310`) writes the selection, `pastWeekDaysProvider` (`train_provider.dart:1296`) reads the rows
through `getScheduleForDate`, and `_buildCompactWeekRows` renders them.

## The fix

See `proposed_fix`.

## The golden (D1, captured from the UNMODIFIED `currentPlanProvider` before the extraction, then frozen)

`test/contracts/workout_day_data_from_row_test.dart` seeds week 1 of a plan (a planned push day with warm-up, cool-down
and a finisher, a completed pull day, a rest day, a hold day, a nameless day, a completed `logged` row, a rest day) and
asserts these literals:

```dart
const List<String> _golden = <String>[
  'n=1 name=PUSH sub=Push · 2 exercises label=Mon, Nov 2 date=2026-11-02T00:00:00.000 rest=false done=false ex=[Bench Press|3|8|90s|weight_reps|null|null;Overhead Press|3|10|60s|weight_reps|null|null] warm=[Arm Circles|1|10|60s|weight_reps|null|null] cool=[Chest Stretch|1|30s|60s|weight_reps|null|null] fin=[Stationary Bike Sprints|8|30s fast / 30s slow|0s|timed|finisher|8 rounds · 30s fast / 30s slow] finSec=0 budget=17 mode=Baseline count=2',
  'n=2 name=PULL sub=Pull · 1 exercises label=Tue, Nov 3 date=2026-11-03T00:00:00.000 rest=false done=true ex=[Pull Up|4|6|90s|weight_reps|null|null] warm=[] cool=[] fin=[] finSec=0 budget=10 mode=Baseline count=1',
  'n=3 name=REST DAY sub=Recovery & mobility label=Wed, Nov 4 date=2026-11-04T00:00:00.000 rest=true done=false ex=[] warm=[] cool=[] fin=[] finSec=0 budget=null mode=null count=0',
  'n=4 name=LEGS sub=Legs · 1 exercises label=Thu, Nov 5 date=2026-11-05T00:00:00.000 rest=false done=false ex=[Back Squat|5|5|120s|weight_reps|null|null] warm=[] cool=[] fin=[] finSec=0 budget=15 mode=Peak count=1',
  'n=5 name=REST DAY sub=Core · 0 exercises label=Fri, Nov 6 date=2026-11-06T00:00:00.000 rest=false done=false ex=[] warm=[] cool=[] fin=[] finSec=0 budget=null mode=null count=0',
  'n=6 name=LEFTOVER LEGS sub=Recovery & mobility label=Sat, Nov 7 date=2026-11-07T00:00:00.000 rest=true done=true ex=[] warm=[] cool=[] fin=[] finSec=0 budget=null mode=null count=0',
  'n=7 name=REST DAY sub=Recovery & mobility label=Sun, Nov 8 date=2026-11-08T00:00:00.000 rest=true done=false ex=[] warm=[] cool=[] fin=[] finSec=0 budget=null mode=null count=0',
];
```

It passes against the unmodified code under `TZ=Asia/Kolkata` (run in a detached worktree at `HEAD`) and against the
extracted builder. Under `TZ=Etc/GMT-8` it fails on BOTH the unmodified and the extracted code (the builder's
`DateTime.tryParse` is local midnight, an existing zone dependence kept for parity, plan section 6), so the golden is
an IST-zone (CI zone) contract. The pure helpers (`past_week_days_pure_test.dart`) pass under both zones.

## Verification

- `TZ=Asia/Kolkata flutter test` on the four new files plus the repointed and neighbouring Train tests: green
  (123 tests across the related Train files; the four new files: 17 behavioral, 14 pure, 1 golden, 1 scale guard).
- Mutation proof above (24 of 24 red).
- B-pass (two fresh Sonnet seats on 655c89b8, CI green): `docs/reviews/655c89b846c9-review.md`, every finding fixed or dispositioned there. The pure test also runs green under `TZ=America/New_York` and `TZ=Etc/GMT-8`.
- `flutter analyze --no-fatal-infos` on the whole project and the pre-commit gate loop: see the commit.
- Founder device check after the build: tap a past chip on the phone; the list matches the current week's look under
  the label line; Fri 16 Oct opens its preview with its logs; a holding user keeps the H chip lit.
