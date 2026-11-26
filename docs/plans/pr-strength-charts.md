# PR strength charts (Home PR tiles, see-all list, full chart sheet)

Founder brainstorm 2026-11-25. Branch `pr-strength-charts`. Batch 1 of 2 (batch 2 = Nutrition History).
Revision 2 (after review round 1; section 8 lists what changed).

## 1. What the user gets

1. Each of the four Home PR tiles shows a small sparkline of that exercise's history at the
   right edge. The whole tile is tappable.
2. Each row of the "SEE ALL" sheet shows a sparkline between the name/date and the value.
   The whole row is tappable.
3. A tap opens a bottom sheet: exercise name, current PR and its date, range chips
   (All / 1Y / 6M / 3M / 1M / 1W), a line chart of the best value per workout day with the PR
   point marked, a touch tooltip (value, reps for weighted lifts, date), and one summary line
   ("First log 12 Aug: 8s · now 15s").

Founder decisions (2026-11-25): weighted lifts chart the HEAVIEST WEIGHT per day (reps shown
on tap); the full chart is a SHEET; FREE for every user (no gate); everything from Hive, no
Supabase call.

Out of scope: Train's `StatsGrid` (it also shows PRs; the founder asked for Home and the
see-all list), estimated 1RM, any cloud change.

## 2. Tier, mode, discipline

- Blast radius: `feature` (measured with `scripts/blast_radius_from_diff.dart` on the product
  paths, the new ones as scratch files; `docs/blast_radius.yaml` has no `account` rule for them).
- Tier M (more than 2 product files, more than 100 lines): x2 plan review, gate loop, CI on the
  PR. Below `account`, so no B-pass and no merge-seam record is demanded; a plan-review record
  is written anyway (`docs/plan-reviews/pr-strength-charts.md`).
- Execution mode: INLINE (one session, this worktree). Not switched mid-batch.
- Two commits' worth of content in one PR: the feature (`feat`), and ONE bug fix found by
  review round 1 (section 4.5, `fix`, with its own slim diagnose doc and regression test).
- No feature flag: Home display only, none of payment / sync / auth / AI prompt / plan
  generator (section 4.6 does not apply). No migration, no Edge Function, no new Hive key.

## 3. Ground truth (verified against this worktree, main at 18540ef8)

Writers (unchanged by this batch):
- `lib/core/services/workout_write_service.dart:1732` `exlogKey` = `exlog_<IST date>_<8 hex of
  v5(lower-cased trimmed name)>`: one row per (day, exercise) from `logExercise`. Row fields:
  `exercise_name`, `logging_type`, `date`, `sets[]` (`weight_kg`, `reps`, `duration_sec`,
  `distance_km`), top-level `weight_kg` (max), `reps_completed` (SUM).
- Restore writer `lib/core/services/sync/sync_workout.dart` `_restoreExerciseLogs`: `set_number`,
  top-level `duration_seconds`, `sets[]` only when the per-set join is non-empty. Legacy and
  restored rows can carry a key whose date differs from the row's `date` field, or a non-dated
  key; two rows for one (day, exercise) are therefore possible.

Readers today:
- `lib/features/train/repositories/workout_repository.dart:949-1034` `loadAllExercisePRs`.
  Every branch:
  - pass 1 (960-967): rows with RAW `logging_type == 'cardio'` (no default) and a non-empty
    lower-cased trimmed name whose `aggregateDistanceKm > 0` enter `cardioWithKm`;
  - pass 2: empty name skipped; `loggingType = logging_type ?? 'weight_reps'`; day =
    `istDateForExlogRow(log) ?? ''`, `date = DateTime.tryParse(day) ?? DateTime(2020)`;
  - value: `weight_reps` / `weighted_bodyweight` -> `bestPerSetWeight`, unit null;
    `bodyweight_reps` -> `bestPerSetReps`; `timed` -> `bestPerSetDuration`; `cardio` -> km
    (unit `km`) when the name is in `cardioWithKm`, else `bestPerSetDuration` (unit `sec`);
    `distance` -> `aggregateDistanceKm` (unit `km`); `default` -> top-level `weight_kg`, unit
    null; `value <= 0` skipped;
  - keeps the row with the STRICTLY greater value, in `workoutBox.toMap()` key order;
  - values of different units under one name are compared as raw numbers (no unit per name);
    the winner's `loggingType` and `unit` become the PR's;
  - sort: date descending, then name.
- `ExercisePR.unit` = stated unit, else `ExercisePR.defaultUnitFor(loggingType)` (`:45-60`).
- `lib/features/home/providers/home_provider.dart:1097` `AllExercisePRsNotifier`: watches
  `authUserIdTokenProvider` only, returns `[]` for `<anon>`. Invalidated from 5 direct sites
  (`edit_workout_log_sheet.dart:148`, `graduation_screen.dart:481`, `day_swap_provider.dart:81`,
  `train_provider.dart:2634`, `day_rollover_service.dart:270`) plus the shared list
  `workout_surface_invalidation.dart:23`.
- **Gap found by review round 1, verified:** nothing refreshes `allExercisePRsProvider` after a
  background restore. `home_screen.dart:156-191` `invalidateOnRetry` (also the body of
  `invalidateOnBackgroundRestore`, `:202`) does not list it and the notifier does not watch
  `restoreCompletedTickProvider`. A returning user whose logs arrive by background restore keeps
  an empty or stale PR card until a workout is logged or the day rolls over. Fixed in 4.5.
- No exlog delete UI exists (`WorkoutWriteService.deleteLog` has no caller in `lib/`), so there
  is no delete path to refresh.
- `lib/features/home/widgets/pr_snapshot.dart`: `PrSnapshot` (tiles, `_PrTile`),
  `_showAllPRsSheet(BuildContext, List<ExercisePR>)` (list; no `WidgetRef` inside). Neither is
  tappable today.
- `lib/shared/widgets/wardroom/ward_spark.dart` `WardSpark(data, width, height)`: fewer than 2
  points renders an empty box; x is evenly spaced by INDEX; equal values draw a flat line at the
  bottom edge.
- `lib/shared/widgets/weight_trend_chart.dart:20-21` `weightTrendWindow` is annotated
  `@visibleForTesting`; its carrier is `WeightTrendPoint({required date, required weight})`.
  The function itself is generic (sort, window anchored at the latest sample, one carry-forward
  point before the window; the lone-dot fix e1c6a9). `WeightTrendChart` the widget is
  weight-only and is NOT reused.
- Tile geometry: `AppSpacing.gutter` = 22 (`lib/core/theme/spacing.dart:29`); at 360 dp a tile
  is (360 - 44 - 6) / 2 = 155 wide, 129 inside its padding and border.

Bug history (section 4.1.5): `docs/diagnoses/INDEX.md` grepped for personal record / PR snapshot
/ sparkline / weight trend. Classes applied:
- cb1ab1: PR readers showed the cumulative SUM as "best per set": the series uses the SAME
  per-row value function as the PR, never `reps_completed`.
- OI-389: one unit per cardio exercise: the series takes its unit from the PR itself.
- e1c6a9: a lone dot after a gap: the sheet reuses `weightTrendWindow`.
- 7c3e91: a longer name must not borrow a shorter name's history: exact name key, no fuzzy.
- 81c4e2: never filter exlog rows on `type`: key-prefix predicate only.
- b3c9d4 / 9c8958 (a Hive-reading provider missing from a refresh list): the gap in 4.5 is a
  recurrence of this class; its diagnose doc cites both.

## 4. Design

### 4.1 One value rule

New file `lib/features/train/services/exercise_pr_series.dart` (pure; imports only
`WorkoutReadService` statics and `ExercisePR`; never reads `log['distance_km']`,
`log['type']` or `best_single_set_*`, which existing source-grep tests forbid):

```dart
/// Lower-cased trimmed name: the PR reader's grouping key.
String exercisePrNameKey(String name) => name.trim().toLowerCase();

/// Name keys of rows with RAW logging_type == 'cardio' and any km (pass 1, verbatim).
Set<String> cardioExercisesWithKm(Iterable<Map<String, dynamic>> rows);

/// Pass 2's switch, verbatim. loggingType = logging_type ?? 'weight_reps'.
/// `unit` is non-null: the stated unit, else ExercisePR.defaultUnitFor(loggingType).
/// Null when value <= 0.
({double value, String loggingType, String unit, String? statedUnit})?
    exercisePrValueOfRow(Map<String, dynamic> log, {required bool cardioHasKm});

/// 'yyyy-MM-dd' when istDateForExlogRow starts with that shape, else null.
String? exercisePrDayOfRow(Map<String, dynamic> log);
```

`loadAllExercisePRs` changes:
1. it materialises `WorkoutReadService.exlogRows(_hive.workoutBox).toList()` once (same
   predicate, same `box.keys` order as `toMap()`), and calls `cardioExercisesWithKm` and
   `exercisePrValueOfRow` in place of the inline pass 1 and switch (`statedUnit` is passed to
   `ExercisePR(unit:)`, so the stored nullable unit is unchanged);
2. ONE deliberate behavior change, the tie rule: a row replaces the current best when its value
   is strictly greater, OR equal AND its day is resolved AND (the current best's day is
   unresolved OR this day is earlier). The PR date is then "the first day the best was
   achieved" regardless of Hive key order. For data whose key order equals date order (every
   row `logExercise` wrote) the result is identical to today.
Grouping, the `DateTime(2020)` filing of an unresolved day, and the sort are untouched.

### 4.2 The series is derived FROM the PR list

```dart
class PrSeriesPoint { final String date; final double value; final int? reps; }
class ExercisePrSeries { final List<PrSeriesPoint> points; } // ascending by date, one per day

/// nameKey -> series, for the exercises in [prs]. One pass over [rows].
Map<String, ExercisePrSeries> buildExercisePrSeries(
    Iterable<Map<String, dynamic>> rows, List<ExercisePR> prs);
```

Rules:
- a row contributes to the series of the PR with the same name key ONLY when its resolved
  `unit` equals that PR's `unit` (mixed units under one name: the chart shows the PR's unit
  only, so the y axis is one unit and the PR's own row is always eligible);
- rows with no resolved day are skipped (a chart cannot place them);
- per day the MAX value; on equal values the first row in iteration order;
- `reps` = for `weight_reps` / `weighted_bodyweight` rows with `sets[]`, the highest `reps`
  among the sets at the day's max weight; otherwise null (top-level `reps_completed` is a SUM);
- a cardio day with 0 km in a km-ranked exercise yields no point (value <= 0).

Invariants (asserted by tests): the series maximum is `<= pr.bestValue`; it EQUALS
`pr.bestValue` whenever the PR's own row has a resolved day; in that case the FIRST point
holding the maximum has `date == pr day`. When the PR's row has no resolved day the series may
peak lower: the sheet then draws no PR marker (4.4).

`WorkoutRepository.loadAllExercisePrSeries(List<ExercisePR> prs)` =
`buildExercisePrSeries(WorkoutReadService.exlogRows(_hive.workoutBox), prs)`.

### 4.3 Provider

New file `lib/features/home/providers/pr_series_provider.dart` (a new file: no line of
`home_provider.dart` moves for this part):

```dart
final exercisePrSeriesProvider = Provider<Map<String, ExercisePrSeries>>((ref) {
  final prs = ref.watch(allExercisePRsProvider); // [] for <anon>
  if (prs.isEmpty) return const {};
  return WorkoutRepository.instance.loadAllExercisePrSeries(prs);
});
```

It needs the PR list as INPUT, so the watch is structural, not a refresh trick: the series
recomputes exactly when the PR list does (a rebuilt notifier always yields a new list). The
series is therefore as fresh as the PR list, no fresher; 4.5 closes the one known gap.
Cost: one extra pass over the exlog rows when Home builds the PR card.

### 4.4 Widgets

`lib/features/home/widgets/pr_snapshot.dart`:
- `PrSnapshot.build` watches `exercisePrSeriesProvider`; `_showAllPRsSheet` receives that map
  as a parameter (the sheet is a static snapshot today; unchanged).
- `_PrTile(pr, series, onTap)`: a `Row` of the existing name + number column in `Expanded`
  and, when shown, an 8 px gap + `WardSpark(width: 40, height: 22)`. The spark is shown only
  when the series has 2 or more points AND the tile's `LayoutBuilder` width is >= 150 AND
  `MediaQuery.textScalerOf(context).scale(1) <= 1.3`; otherwise the tile is exactly today's.
  The number keeps `Flexible` + ellipsis.
- List rows: 8 px gap + `WardSpark(width: 64, height: 22)` before the value when 2+ points.
- Both are wrapped in `InkWell` with `Semantics(button: true, label: '<name> personal record,
  <value>. Show trend')`. The list sheet stays open under the trend sheet.
- The sparkline is index-spaced (a shape cue); the sheet's chart is date-proportional. A flat
  history draws a flat line at the tile's bottom edge (`WardSpark`'s existing behavior, shared
  with other screens; left as is).

`lib/shared/widgets/weight_trend_chart.dart`: remove `@visibleForTesting` from
`weightTrendWindow` (it becomes a shared pure function with two production callers; its test
keeps importing it). No other change to that file.

New `lib/features/home/widgets/pr_trend_sheet.dart`: `showPrTrendSheet(context, pr, series)`.
- Header: name (mono eyebrow), `pr.formattedValue`, `pr.formattedDate`.
- Range chips (local widget state) -> `weightTrendWindow([WeightTrendPoint(date: p.date,
  weight: p.value)], window)`; the carry-forward point may sit before the chosen range, by
  design (no lone dot).
- fl_chart `LineChart`, gold line, date-proportional x, y padded 10 % (a flat series gets a
  fixed +/- 1 unit pad). PR marker: the FIRST point of the FULL series whose value equals
  `pr.bestValue`, drawn larger when it is inside the shown window; no marker when the series
  never reaches `pr.bestValue`.
- Pure helpers (unit-tested): `prPointLabel(point, pr)` -> `82.5 kg x 8 · 12 Nov` (reps only
  when known), `15 reps · 12 Nov`, `45s · 12 Nov`, `5.2 km · 12 Nov`, every value formatted by
  constructing an `ExercisePR` and reading `formattedValue` (one formatter);
  `prJourneyLine(series, pr)` over the FULL series, not the window: 2+ points -> `First log
  12 Aug: 8s · now 15s`; 1 point -> `Log it again to see your trend`; 0 points -> the same line.
- States: 0 or 1 point shows the line above and no chart axis; no loading state exists
  (synchronous Hive read).
- Wardroom: `AppColors` / `AppTypography` tokens only, dark theme, DM Sans via the tokens.

### 4.5 Fix: the PR card after a background restore

Writer: the restore (`sync_workout.dart` `_restoreExerciseLogs`) writes exlog rows.
Reader: `AllExercisePRsNotifier.build` (`home_provider.dart:1097`), never rebuilt by a restore.
Fix: `AllExercisePRsNotifier.build` adds `ref.watch(restoreCompletedTickProvider);` (the
mechanism the streak chip providers already use; it also covers Train's `StatsGrid` when Home
is not mounted). If that one added line shifts a registry-pinned range in `home_provider.dart`,
the registry ranges are recomputed from their anchors in the same commit (parity gate).
Diagnose doc (slim, with `related_bugs: b3c9d4, 9c8958` and `recurrence:`), regression test
`test/contracts/pr_list_follows_restore_tick_behavioral_test.dart`: seed an exlog row AFTER the
first read, bump the tick, read again -> the new PR is present; mutation = delete the watch.

### 4.6 Docs and registry

- `docs/sot_registry.yaml`: new concept `exercise_pr_series` (writer `logExercise`; readers
  `exercise_pr_series.dart`, `WorkoutRepository.loadAllExercisePrSeries`,
  `exercisePrSeriesProvider`, `pr_snapshot.dart`, `pr_trend_sheet.dart`; `behavioral_test_path`
  = the test in 5.2); refresh the `pr_snapshot.dart` range (`:5374`, `23-80`) and the
  `loadAllExercisePRs` notes of `exercise_personal_records` (shared value function, tie rule).
- `lib/features/home/CLAUDE.md`: layout row 8 and one SoT row. `lib/features/train/CLAUDE.md`:
  one clause in the `exercise_personal_records` row.
- `docs/naming_conventions.md`: add `pr_series` (absent today).
- Context-artifact budget re-check after the doc edits.

## 5. Tests

### 5.1 `test/contracts/load_all_exercise_prs_preservation_test.dart` — written FIRST, on the OLD code
Real Hive, a seeded box written directly (so legacy shapes are possible): every logging type,
null `logging_type`, an unknown type (default branch), cardio with km on some days and none on
others, cardio never with km, distance, restore-shaped rows without `sets[]`, an unresolved-day
row, a non-`exlog_` key, mixed units under one name, two names differing only in case. It
asserts a LITERAL expected list (name, loggingType, unit, bestValue, date). It must be green on
the code before step 1 and green after it. No fixture row creates a cross-day tie, so the tie
rule cannot affect it.

### 5.2 `test/contracts/exercise_pr_series_writer_to_reader_test.dart` (Hive write -> read)
Rows through `WorkoutWriteService.logExercise` unless a legacy shape is needed.
- B1 one point per day, ascending by date even when a legacy key sorts first; two rows on one
  day, the HIGHER value on the EARLIER key, give ONE point holding the max.
- B2 per logging type, a literal expected series AND `max == pr.bestValue`, first max date ==
  PR day.
- B3 bodyweight 3 sets of 10/9/8 gives 10, never 27 (class cb1ab1).
- B4 weighted: `reps` = reps of the heaviest set; a row with no `sets[]` gives the top-level
  weight and `reps == null`.
- B5 "Push Up" and "Push Up to Side Plank" are two series (class 7c3e91).
- B6 an unresolved-day row is skipped; when it holds the PR the series max is lower and the
  invariant `max <= bestValue` holds.
- B7 mixed units under one name: only rows in the PR's unit appear.
- B8 km-ranked cardio: a duration-only day yields no point.
- B9 tie rule: the same best on two days, the LATER day on the earlier-sorting key -> PR date
  is the earlier day and the first max point matches it.

### 5.3 `test/contracts/exercise_pr_series_provider_behavioral_test.dart`
ProviderContainer on real Hive: read (empty) -> log -> invalidate `allExercisePRsProvider` ->
the series has the exercise; `<anon>` token -> `{}`.

### 5.4 `test/features/home/pr_trend_widgets_test.dart`
- W1 at 360 dp: a tile with 2+ points renders a `WardSpark`; with 1 point none; at 360 dp with
  textScale 1.4 none; no overflow error in any of the three.
- W2 tapping a tile opens the sheet with the name and PR value; tapping a see-all row does too.
- W3 one-point sheet shows the "log it again" line, no exception.
- W4 range chip `1M` on a series spanning 6 months: the chart receives the windowed points
  plus one carry-forward point (asserted through a pure `prWindowPoints` helper).
- W5 PR marker index: first max inside the window -> that index; series never reaching the PR
  -> null (pure helper `prMarkerIndex`).
- Unit tests of `prPointLabel` and `prJourneyLine` for each unit.
- Font and Hive handling per the root section 4.9 pitfalls.

### 5.5 `test/contracts/pr_list_follows_restore_tick_behavioral_test.dart` (section 4.5)

### 5.6 Mutations (rule 21), each applied (`grep -c`), counted, reverted
- M1 bodyweight branch of `exercisePrValueOfRow` -> `reps_completed`: 5.1, B2 literal and B3
  redden (B2's equality alone would not: both paths share the function).
- M2 per-day max -> last-wins: B1 reddens (fixture has the higher value on the earlier key).
- M3 unit filter removed in `buildExercisePrSeries`: B7 reddens.
- M4 tie rule removed: B9 reddens.
- M5 `points.length >= 2` guard removed: W1 reddens.
- M6 provider returns `const {}` unconditionally / stops watching the PR list: 5.3 reddens.
- M7 the restore-tick watch removed: 5.5 reddens.

### 5.7 Existing tests that must stay green
`exercise_personal_records_writer_to_reader_test`, `load_all_exercise_prs_per_set_semantic_test`
(forbids `best_single_set_*` literals: the new file has none),
`cardio_duration_distance_writer_to_reader_test`, `no_top_level_distance_km_reads_test` (scans
`lib/features/train`: the new file delegates to `aggregateDistanceKm`),
`exlog_type_field_read_ban_test`, `stats_grid_cardio_pr_test`,
`pr_snapshot_uses_pr_set_reps_test`, `weight_trend_chart_gap_connect_test`,
`signed_out_provider_rebuild_behavioral_test`, `workout_surface_invalidation_test`. Before
step 1: `grep -rn "cardioWithKm\|loadAllExercisePRs\|pr_snapshot\|invalidateOnRetry" test/` and
repoint any source pin (never loosen).

## 6. Order of work

1. Test 5.1 on the old code (green). Extract the value functions; `loadAllExercisePRs` calls
   them (no tie rule yet); 5.1 + 5.7 green.
2. Tie rule + B9. `buildExercisePrSeries`, repository method, provider; 5.2, 5.3.
3. Remove `@visibleForTesting`; tiles, list rows, sheet; 5.4.
4. Restore-tick fix + 5.5 + diagnose doc.
5. Mutations 5.6.
6. Registry, nested CLAUDE.md, naming glossary, budget.
7. `flutter analyze --no-fatal-infos` (whole project), pre-commit gate loop, commit, PR,
   `land_pr.sh --ci-only`, then land.
8. Device check (founder build): tiles, list, sheet on phone and web; PR card after a restore.

## 7. Risks

- The tie rule changes which DAY a tied PR reports for legacy-keyed data only; value never
  changes. `ExercisePR.date` feeds the PR list sort (newest first), so a tied legacy PR can
  move down the list. Accepted: the earlier day is the true first achievement.
- `Provider` recompute on every PR-list rebuild: one pass over exlog rows; measured once on a
  seeded box of 3,000 rows inside 5.2 (printed, not asserted).
- A registry-pinned line range in `home_provider.dart` shifts by the one added line (4.5): the
  parity gate reports it; ranges recomputed from anchors.

## 8. Changes after review round 1

P1: `weightTrendWindow` is `@visibleForTesting` -> annotation removed (4.4); `WeightTrendPoint`
named parameters used, only the window function reused (3, 4.4); the "peak == PR" claim
replaced by the derived-from-PR design with a unit filter, stated invariants and the tie rule
(4.1, 4.2); every branch of `loadAllExercisePRs`, the null-type handling, unit resolution and
the row source written out (3, 4.1). P2: the list sheet gets the series as a parameter (4.4);
spark 40 px with numeric show conditions and a 360 dp test (4.4, W1); the provider test has a
file (5.3); M2's fixture fixed; B2 carries literals; missing tests added (5.1, B6-B9, W4, W5).
P3: restore staleness verified as a real gap and fixed in this batch (4.5); `WardSpark` index
spacing and flat line stated (4.4); carry-forward and full-series summary stated (4.4).

## 9. Changes after review round 2 (verdict: converged, no P0/P1)

These override the text above where they differ.
- Tile layout (P2): the spark sits in the NUMBER row only (number `Flexible`, unit, `Spacer`,
  spark), so the name line keeps the tile's full width. W1 also asserts a 19-character name
  renders on one line with no overflow.
- Tap feedback (P2): each tile and list row is `Material(color: Colors.transparent)` +
  `InkWell` INSIDE its decorated box, so the ripple is visible.
- Import cycle (P3): `exercise_pr_series.dart` imports `workout_repository.dart` for
  `ExercisePR` and the repository imports it back. Accepted (Dart allows it; the alternative is
  a second copy of `defaultUnitFor`).
- Passes (P3): `loadAllExercisePrSeries` materialises the rows once (`.toList()`);
  `buildExercisePrSeries` computes the cardio-km set itself, then one pass. Two passes total.
- Resolved day (P3): a day is resolved exactly when `DateTime.tryParse(istDateForExlogRow(log))`
  succeeds, the PR reader's own test; the series day string is that parsed date formatted
  `yyyy-MM-dd`. The tie rule compares those day strings.
- 4.5 placement (P3): the `ref.watch(restoreCompletedTickProvider)` goes AFTER the `<anon>`
  return and before `loadAllExercisePRs`, as in `StreakNotifier.build` (`home_provider.dart:290`).
  Only the registry range `1097-1112` grows by one line.
- 5.5 harness (P3): modelled on `test/contracts/streak_chip_restore_tick_behavioral_test.dart`
  (`SyncHarness`, `SyncService.bumpRestoreCompleted`); the test first asserts the tick provider
  moved, so it cannot pass on the "no SyncService" fallback.
- Tie across units (P3): on an equal raw value of another unit on an earlier day the PR's unit
  follows the earlier row (legacy data only). Added to Risks; one case in B9.
- B10 (P3): "Push Up" on day 1 and "push up" on day 2 give ONE series; the sheet header shows
  `pr.exerciseName`.
- M5 finds the spark with `find.byType(WardSpark)` (the widget itself renders an empty box
  under 2 points, so a painted-pixels check would not see the mutation).
