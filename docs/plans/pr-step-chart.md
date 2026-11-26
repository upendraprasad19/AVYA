# PR chart: the record as a step, the lifted weight as its own line

Founder observation 2026-11-26 (web, after PR #345). Diagnose `592da4`.

## 1. Observation

"I join on 1 Jan, bench 40 kg. In Feb I only do 35, but my PR in Feb is still 40. In Mar I reach
42.5, so the PR steps up. A user should not see his PR going up and down: it should be a stepwise
graph. The real lifted weight can fluctuate, so there are two ingredients. The small PR graph is
the step graph of the PR; the full screen shows both: the PR step and the real lifted line."

## 2. Cause (spec gap, not drift)

The #345 plan (`docs/plans/pr-strength-charts.md:13`) specified "a line chart of the best value per
workout day". The code does exactly that, so the chart titled as a PR dips to 35.

- **Writer** (unchanged, correct): `buildExercisePrSeries`,
  `lib/features/train/services/exercise_pr_series.dart:180` (per-day point at `:207`): one point
  per workout day, the day's best set, in the PR's unit.
- **Readers** (main):
  - `prSparkValues`, `lib/features/home/widgets/pr_snapshot.dart:208`, used by the tile spark
    (`:233`, `:269`) and the see-all row spark (`:305`, `:354`): plots `p.value` per day.
  - `_PrTrendSheetState._chart`, `lib/features/home/widgets/pr_trend_sheet.dart:235` (spots
    `:251`): one line of `p.value` per day.
  - `prJourneyLine`, `pr_trend_sheet.dart:41`: "now" = `pts.last.value` (`:46`), the last day's
    lift, so a light last session reads "now 35 kg" under a 40 kg PR.
- No reader outside these two files (grep of `lib/` and `supabase/` for `prSparkValues`,
  `prJourneyLine`, `buildExercisePrSeries`, `exercisePrSeriesProvider`). No server reader.

Bug history: no prior diagnose on the PR chart (grep of the local `docs/diagnoses/INDEX.md` and
`docs/diagnoses/*.md` for pr_snapshot / pr_trend / ExercisePR / personal record). `cb1ab1` is the
PR VALUE summing sets, a different defect. Nearest class: debugging 2.19 (monotonic field demoted
by a recompute) -- same shape (a "highest-ever" concept rendered from a current-state value) but at
the display layer with nothing stored. Not a recurrence; cited as related.

## 3. Design

Data unchanged. Display only, two files in `lib/features/home/widgets/`.

1. `prRunningBest(List<PrSeriesPoint>) -> List<double>` (pure, `pr_trend_sheet.dart`): the PR as
   of each point, oldest first: a running max. Never dips.
2. Tile and see-all sparks: `prSparkValues` returns `prRunningBest(points)` (still empty under two
   days). `WardSpark` is shared and index-spaced; it is NOT modified, so a step there is drawn as a
   short slope between two index slots. SUPERSEDED by section 8 (round 1): a `step` flag.
3. Sheet, two bars on one axis:
   - bar 0, the PR: `isStepLineChart: true` (fl_chart step, jump at the next point), accent gold,
     2.5 px, the existing below-area tint; the existing PR marker dot (first day at the PR) sits on
     this bar. Its value per shown day is the running best over the FULL series looked up by date,
     so a PR set before the selected range still holds inside it. One extra point carries the
     step on to today (`istTodayStr()`) when today is after the last shown day.
   - bar 1, best set each day: the old line, `textDim`, 1.5 px, straight segments, small dots when
     <= 30 points.
   - y range over both bars' values; x range ends at the PR bar's last point (today).
   - Tooltip only on bar 1 (bar 0 returns null): `<day label>\nPR <value>`.
   - Legend under the chart: "Personal record" / "Best set that day" in a `Wrap` (a `Row`
     overflows 92 px at 360 dp under Ahem).
4. `prJourneyLine` "now" = `prRunningBest(points).last` (the standing PR).

Decisions taken from the founder brainstorm (2026-11-26): the PR line runs on to today; the same
step logic for every unit (reps, seconds, km); a tie is not a new step (running max with `>`).

## 4. Tier

Paths `lib/features/home/widgets/{pr_snapshot,pr_trend_sheet}.dart` and, after round 1,
`lib/shared/widgets/wardroom/ward_spark.dart` (a shared widget with four other callers, its default
path pinned by a test): 3 product files, NOT a recurrence, over 100 lines => **M**: two plan-review
rounds before the code is treated as final, the gate loop + CI before every reviewer dispatch, a
`/code-review` B-pass before the merge. Blast radius `feature` (`blast_radius_from_diff.dart` on
all three paths, re-run after round 1). Execution inline (one worktree,
`pr-step-chart`). NOTE: a draft diff was written BEFORE this plan (process miss, memory
`feedback_fix_authorisation_is_not_a_tier_decision`); it is a draft that this reviewed plan
governs.

## 5. Tests

- Contract (Hive write -> read): `test/contracts/exercise_pr_series_writer_to_reader_test.dart`
  B11: log Bench 40 (day 1), 35 (day 2), 42.5 (day 3) through `WorkoutWriteService.logExercise`;
  the series stays `[40, 35, 42.5]` (lifted), `prRunningBest` / `prSparkValues` on it is
  `[40, 40, 42.5]`, the last running best equals the PR.
- Widget/unit (`test/features/home/pr_trend_widgets_test.dart`): `prRunningBest` dip case and
  empty; `prSparkValues` dip; `prJourneyLine` "now" after a lighter last day; the sheet has two
  bars, bar 0 stepped with `[40, 40, 42.5]` first, bar 1 not stepped with `[40, 35, 42.5]`, a
  legend. Existing W2 runs every range at 360 dp with no exception.
- Mutants (each applied, `grep -c` confirmed, reverted): M1 running max -> per-day value;
  M2 `isStepLineChart: true -> false`; M3 `prSparkValues` back to `p.value`; M4 journey "now" back
  to `pts.last.value`; M5 PR spots from the WINDOW only instead of the full series (a PR before
  the range).
- Gate loop before each review dispatch; CI via `land_pr.sh --ci-only`.

## 6. Docs

SoT registry `exercise_pr_series`: reader notes for `prSparkValues` (running best) and the sheet
(two bars), a class constraint "the PR line is the running best; it never dips".
`lib/features/home/CLAUDE.md`: one line on the chart meaning.

## 7. Mutants run (after round 1)

M1-M5 as in section 5, plus M6 step direction middle, M7/M11 tile / see-all spark `step: false`,
M8 the spark's corner removed, M9 no carry to today, M10 tooltip on the PR bar. All 11 red.

## 8. Round 1 (needs-changes: 1 P1, 1 P2, 4 P3), all folded

- P1 (verified in fl_chart 1.2.0 `line_chart_data.dart:514-523`, `line_chart_painter.dart:675-690`):
  `LineChartStepData` defaults to `stepDirectionMiddle` (0.5), so the riser sat half-way between two
  log days, showing the PR BEFORE it was set. Now `stepDirectionForward` (0.0: flat to the next
  point, rise there). Test asserts the direction; mutant M6.
- P2 the tile / see-all spark was a slope, not a step. `WardSpark` gets `step` (default false);
  vertices extracted to pure `wardSparkVertices` (a corner at the next x with the current y). The
  two PR sparks pass `step: true`. A hand-computed vertex test pins the step-off path for the four
  other callers (admin ops/growth/engagement tabs, weekly report card). Blast radius stays
  `feature`.
- P3 day maths on UTC midnights (`_utcDay`), so a DST zone cannot lose a day; IST has no DST.
- P3 tests for the today carry (a 2020 series: PR bar has one more spot, maxX = its x) and the
  tooltip (null on bar 0, `35 kg x 8 · 10 Feb\nPR 40 kg` on bar 1); mutants M9, M10.
- P3 (note, no change) a long-idle user sees a long flat PR line to today; legend fits at 360 dp
  (W2 runs every range at 360 dp).
- Checked: new widget tests pass under TZ=Etc/GMT+12 too; the contract file's old B1-B8 fail there
  on main as well (IST host assumption, CI pins IST).

## 9. Round 2 (converged: 0 P0/P1, 1 P2, 4 P3), all folded

- P2 the painter's use of `step` was untested (a mutant passing `step: false` inside `paint` stayed
  green). Test paints `WardSpark` on a recording canvas and compares the stroke length with the
  stepped / plain vertex polylines; mutant M12.
- P3 `shouldRepaint` on `step` (M13); `_utcDay` under a real DST change (8 Mar 2026,
  `TZ=America/New_York`, M14); the PR dot only at the PR day on bar 0 and the tint (M15); legend
  labels (M16); vertex test with rises AND a fall.
- P3 the touched-spot marker was drawn on the PR bar too: `prTouchedIndicators` (none on the
  stepped bar, fl_chart's default on the lifted one); M17.
- P3 section 4 refreshed (3 product files, the shared widget); a >80-column spark line wrapped.
- 17 mutants in all (M1-M17), every one red; no compile errors.
