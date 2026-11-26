# Nutrition History v2 — readable, honest, more from the same Hive data

Founder observation 3 (2026-11-26, web). Mockup approved 2026-11-26:
`docs/mockups/2026-11-26-nutrition-history-v2.html` (artifact
https://claude.ai/artifact/2Qzui5cuFezSbGAADvc1cs). Branch / worktree `nutrition-history-v2`.
Base: `main` 60f9ab86. Builds on `docs/plans/nutrition-history.md` (v1, landed #346/#350).

## 1. Observation and founder decisions

Founder, verbatim summary: header "TRACKING SINCE 1 MAY · Day 210 · 27 days logged · 263 g protein
this month" is unclear and mixes time frames; trend charts have no axes; the consistency grid has
no month division; low protein shows yellow, make it red; HIT RATE & STREAKS is all zero, explain;
CALORIES VS WEIGHT is two unlabelled lines; top protein sources list three kinds of whey separately.
Asked for a brainstorm + research + psychology pass; the founder then approved (2026-11-26):

- D1 Header: days logged since the first day · days logged in the last 30 days · average protein
  on full days in the last 30 days · logging streak with a one-line next step. "Day N" removed.
  Eyebrow `SUPPLY LOG · SINCE <date>` (Wardroom voice; mockup approved).
- D2 Runs: a target run counts consecutive FULL days only; a day that is not a full day (not
  logged, partial) is SKIPPED, not a break. Only a full day that misses breaks the run. A separate
  LOGGING streak counts consecutive logged calendar days; there a day with no log breaks it.
- D3 Calories vs weight: two stacked charts on one shared date axis, each with its own labelled
  y-scale (mockup section 5).
- D4 Top foods: a FIXED family list (whey, paneer, eggs, chicken, ...) folds spellings; a family
  row shows "N kinds"; each protein row shows its share of all item protein; one concentration line.
- D5 New views, all four: protein by meal, protein hit rate by weekday, on-target vs missed day,
  monthly report.
- D6 Monthly report: the last 6 months as rows; months older than that fold into ONE row per year,
  collapsed; tap a year to show its months. Never more than 6 + (years) rows when collapsed.
- D7 Low protein red (`AppColors.bad`), over stays amber (`AppColors.warn`).
- D8 Every chart gets readable axes: y values (0 / mid / max) and start / mid / end dates.
- D9 Zero-state: a row at 0 hits (with >= 3 counted days) says why in one line and names one
  next step (psychology pass: goal-gradient, B=MAP). No shaming copy.
- Constraint: Hive only, no new Postgres / Edge Function call, no schema change.

## 2. Bug history (§4.1.5)

`docs/diagnoses/INDEX.md` grep (nutrition history, hit rate, heatmap, top foods, foodNameKey):
c2a4e8, d7b3f1, a9d5c3 (2026-11-25) — target history and weekly bucketing. None covers the header,
runs, axes, calendar months, colour or food grouping. Not a recurrence. Two items are defects of
v1 and get diagnose docs:
- **60dc46** — runs: `hitStats` (`nutrition_history.dart:470-492`) breaks a run on every
  non-counted day, so with sparse logging every run is 0 and the insight "best protein run"
  (`:762`) can never fire; "best run 0 · current 0" read as failure.
- **3cfcc6** — food grouping: `foodNameKey` (`:578-583`) only strips a trailing parenthetical and
  `x<n>`, so "Whey protein powder", "Whey protein isolate", "Whey protein" are three rows.
The rest (header, axes, months, colour, new views) is design change, not a defect.

## 3. Writers and readers (§4.1)

Writer (unchanged): `NutritionWriteService` writes `nutrition_logs` rows (`total_*`, `meal_type`,
`items[] {name, protein, calories}`); water by day; weigh-ins via `weightHistoryProvider`.
Reader entry: `NutritionRepository.loadHistoryInputs` -> `buildNutritionHistoryData`
(`nutrition_history_provider.dart:55-110`) -> `buildNutritionDays` (`nutrition_history.dart:124-172`),
`judgeDays`, `topFoods` (`:590-676`), `nutritionInsights` (`:688`).
Readers changed:
- `HistoryJourneyHeader` + `proteinThisMonth` (`history_sections.dart`, section 1).
- `hitStats` (`nutrition_history.dart:470`), `HistoryHitRates` (section 5), insight run (`:762`).
- `HistoryTrendChart` axes (`history_trend_chart.dart:86-171`).
- `HistoryHeatmap` / `heatmapShape` / `heatmapIndexAt` (`history_heatmap.dart:16-29`, painter).
- `statusColor(lowProtein)` (`history_common.dart:98`), also read by the day sheet
  (`history_day_sheet.dart:89`) — the same colour there is intended.
- `HistoryWeightOverlay` (section 6), `HistoryMacroSplit` (section 4) axes.
- `foodNameKey`, `topFoods`, `HistoryTopFoods` (section 7).
New readers: `NutritionDay.proteinBySlot` (filled in `buildNutritionDays` beside `caloriesBySlot`,
same `mealSlotOf`), and pure functions for the four new views.
No cloud reader of any of this (grep of `supabase/` for `foodNameKey|hitStats|proteinThisMonth`: none).

## 4. Changes (units)

U1 [revised §9] Header (D1). `journeyStats(days, todayKey)` -> `(logged, logged30, avgProtein30, streak,
   bestStreak)`; "last 30 days" = the 30 IST days ending yesterday plus today if logged.
   `avgProtein30` over FULL days in that window (null -> "—"). Remove `proteinThisMonth`.
U2 [revised §9] Runs (D2). `hitStats`: a day whose `hitOf` is null is skipped (neither hit nor break); today
   still skipped. `bestRun`/`currentRun` doc says "full days in a row". Insight line becomes
   "Your best protein run is N full days in a row." (`:762`, threshold unchanged at 5).
U3 [revised §9] Logging streak (D2). `loggingStreak(days, todayKey)` -> `(current, best)`: consecutive
   `day.logged` calendar days; today not logged does not break (in progress), today logged counts.
U4 [revised §9] Zero-state line (D9). `hitZeroReason(days, kind, todayKey)`: when hits == 0 and counted >= 3,
   the majority status among counted days: calories -> "Most of your full days were under / over
   your calorie target." + "Land within <band> kcal of <target> tomorrow to start a run." Protein ->
   "Your full days averaged <x> g against <90% target> g." + "Hit <90% target> g tomorrow to start
   a run." Target = the latest judged day's target. No line when counted < 3.
U5 [revised §9] Trend axes (D8). Left y labels 0 / half / max (`metricText`), faint gridlines at the same
   values; x labels first / middle / last day (replaces the "max" centre label).
U6 [revised §9] Calendar (D7). Month blocks: each month its own Monday-row grid with a label ("Nov", plus the
   year on January and on the first block); a gap between blocks; horizontally scrollable, newest
   right, opens scrolled to the end (as now). `heatmapIndexAt` replaced by a per-month layout
   function `monthBlocks(days)` -> list of `(label, firstRow, startIndex, length)`; tap maps through
   it. Low protein -> `AppColors.bad`. Legend gains "Not logged".
U7 [revised §9] Calories vs weight (D3). Two stacked painters, shared x positions (day index over the range):
   calories 7-day average with y labels (min / max, rounded to 100) and the target dashed line;
   weight with y labels (min / max to 0.1 kg) and an end dot; shared x labels first / mid / last.
   Summary line "<first> kg to <last> kg over <weeks> weeks while averaging <kcal> kcal" (average
   over full days in range). Same visibility rule as today (>= 2 weigh-ins, >= 2 average points).
U8 Macro split axis: right-hand 0 / 50 / 100 % labels and gridlines.
U9 [revised §9] Food families (D4). `kFoodFamilies` ordered list `(family, [patterns])`: whey, casein, paneer,
   egg, chicken, fish, mutton, prawn, tofu, soya, dal, rajma, chana, curd/yogurt, milk, cheese,
   peanut, almond, oats. Match = whole-word token contained in `foodNameKey(name)` (first family
   wins; "egg white" -> egg). Unmatched names keep today's key. `FoodStat` gains `kinds` (distinct
   keys folded) and `proteinShare` (of all item protein in range). Row "Whey · 3 kinds".
   Concentration line: smallest N top rows reaching >= 60 % share, shown when N <= 5 and the range
   has >= 10 items: "N foods give X% of your protein."
U10 [revised §9] Protein by meal (D5). `proteinBySlot` in `buildNutritionDays`; `slotProteinAverages` over full
   days (>= 3). Line: the lowest slot (breakfast/lunch/dinner only) and, when the average full day
   is under 90 % of the latest protein target, "Adding <gap> g at <slot> gets you to 90% of your
   <target> g target." (gap rounded up to 5 g).
U11 [revised §9] By weekday (D5). Protein hit rate per weekday over full days with a target; a weekday shows a
   bar when it has >= 3 counted days (else a ghost bar, no %). Line names best and worst weekday
   when both have >= 3 and differ by >= 20 points.
U12 [revised §9] On-target vs missed (D5). Averages of calories, protein, breakfast protein over `onTarget` days
   vs `under|over|lowProtein` days; shown when each side has >= 3 days.
U13 [revised §9] Monthly report (D5, D6). `monthlyRows(days, weights, todayKey)` over ALL days (not the range
   chip; the section says "All time"): per IST month logged days, average kcal and protein over full
   days (— when none), weight change = last weigh-in of month minus first weigh-in of month when the
   month has >= 2 weigh-ins (else —), protein arrow vs the previous month row when both have >= 3
   full days and differ by >= 5 g. Rows: the latest 6 months that have any logged day or weigh-in
   since the first day; months before those fold into year rows (same fields over the year);
   tapping a year row expands its months (local widget state, collapsed by default).
U14 [revised §9] Docs: nutrition `CLAUDE.md` (history section), `docs/architecture/functionality-flow.md` row,
   SoT registry lines for changed readers, two diagnose docs (60dc46, 3cfcc6).

Order on the screen: header, trend, consistency, what your logs show, hit rate & streaks, protein
by meal, by weekday, on-target day, macro split, calories vs weight, patterns, top foods, monthly
report.

## 5. Tier, blast radius, mode

Blast radius `feature` (`blast_radius_from_diff.dart` on the touched paths). Tier **M** (more than 2
product files, > 100 lines; S's hard filter fails). Full pipeline: ×2 plan review, gate loop + CI
before any reviewer sees a diff, B-pass not required at feature tier but run once on the final
diff (self-chosen, the batch is large). Mode: inline (one worktree), decided now.

## 6. Tests (each mutated once, §4.4 rule 21)

Pure-function unit tests in `test/features/nutrition/nutrition_history_v2_test.dart`; behavioral
contract `test/contracts/nutrition_history_v2_behavioral_test.dart` (real Hive rows -> provider ->
widgets): header numbers; a sparse log where runs used to be 0 and now count; logging streak with a
gap; zero-state line; month blocks (a month starting on Sunday, a year boundary, a 1-day month
block); low protein colour; whey family folding with three spellings and share; protein by meal;
weekday rates with a < 3 weekday; on-target table hidden below 3; monthly rows with 7+ months and
two years, a year row expanding; weight change dash with one weigh-in. Existing tests repointed:
`nutrition_history_screen_test.dart`, `nutrition_history_writer_to_reader_test.dart`.
Mutants planned: run-skip -> break; streak today-breaks; family match -> substring; share
denominator -> top-N only; month block start row off by one; year fold at 5 months; weight change
with one weigh-in; zero-state threshold 3 -> 0.

## 7. Not established / risks

- The founder's own zeros are inferred from the code, not seen in their Hive (web local storage).
  The behavioral test reproduces the shape (27 logged days over 210, under-target days).
- Food families are English names; Hindi/transliterated names ("anda", "dahi") — include "anda"
  under egg, "dahi" under curd; others fall back to today's key.
- Rendering at 360 dp with DM Sans not measured until the widget tests run (Ahem).

## 8. Round 1 (needs-changes: 0 P0, 6 P1, 10 P2, 10 P3) — all folded in §9

## 9. Revisions after round 1 (these supersede §4 where they differ)

Scope per section (P2-2; header corrected in §11): hit rates, zero-state, protein by meal, weekday, on-target table,
macro split, calories vs weight, patterns follow the RANGE chip (`shown`); calendar, insight lines,
top foods (all time, as today) and the monthly report use ALL days. Each section's note says which.

U1 (P1-2, P3) "Last 30 days" = the last 30 calendar days INCLUDING today (`days.sublist(len-30)`),
  so the count is <= 30; the stat reads "N of the last 30 days" and is hidden when the history is
  <= 30 days long (it would repeat "days logged"). Eyebrow adds the year when it is not the current
  year ("SINCE 1 MAY 2025").
U2 (P1-1, P2-4, P2-5) Runs skip a day whose hit is null (not a full day) for CALORIES and PROTEIN
  only (`hitStats(..., skipUnjudged: kind != HitKind.water)`); water keeps today's rule (a day with no
  water logged breaks). `currentRun` is 0 when the last counted day is more than 7 days before today
  (a stale run is not "current"). Row copy: "best run N · current M (full days in a row; days you
  did not log are skipped)"; section note: "Full days only. Today, half-logged and unlogged days are
  skipped." Insight: "Your best protein run is N full days in a row." Tests repointed:
  writer_to_reader_test 231-241 (gap now skipped for protein, still breaks water) and 364-368;
  screen_test 132 (`history_day_n` removed) and 298 (`proteinThisMonth`).
U3 (P2-9) Named "logging run" in code and copy ("Logged 3 days in a row"), NOT "streak", so it is
  never confused with the app streak (`streakProvider`, freezes). Glossary row added to
  `docs/naming_conventions.md` ("logging run: consecutive IST days with a meal logged, History only;
  not the app streak").
U4 (P2-2, P2-3) Calories, 0 hits, >= 3 counted: under > over -> "Most of your full days were under
  your calorie target."; over > under -> "...over..."; tie -> "Your full days landed both under and
  over your calorie target." Next step uses the LATEST judged day's target, worded as "your current
  target". Protein: "Your full days averaged X g; 90% of your current target is Y g." where X is the
  mean of protein over counted days and Y is from the latest target, plus "Hit Y g tomorrow to start
  a run." Water: no line. No target known (hasTargets false): no line.
U5 (P1-4, P3) Y labels sit in a fixed 36 dp column OUTSIDE the GestureDetector; the chart rect and
  tap mapping are unchanged, so the existing tap test still maps. Labels use the painter's own top
  value (`maxY * 1.1`): 0, half, top. One bar -> one date label. Test taps first and last bar.
U6 (P1-4, P2-6, P3) `monthBlocks(days)` is the ONE layout source for painter and tap:
  `(label, firstRow, startIndex, length, x)`. Block width = max(columns * step, 28 dp) so a 1-day
  block fits "Oct"; the year is added on January and the first block only when it differs from the
  current year. A 14 dp label row on top; the weekday letters shift down by it. A tap in a gap or in
  the label row returns null (test). "Not logged" legend entry already exists (dropped from U6).
U7 (P2-7) The painter scales to the SAME rounded bounds the labels print (calories floor/ceil to
  100, weight to 0.5 kg); a flat series gets +/- one step; (target-inside clause superseded by §11 chartBounds)
  the bounds. The x axis is the range; the summary uses the weigh-in span: "<a> kg to <b> kg over
  <d> days while averaging <k> kcal" (d < 14 -> days, else weeks), where k is the mean of full-day
  calories between the first and last weigh-in. Semantics label states both summaries.
U9 (P2-1) Tokeniser: lower-case, split on any non-letter; a family matches when ALL its pattern
  tokens appear as consecutive tokens. Negative guard: a token followed by "free" or "less" ("whey
  free", "eggless" is a different token and never matches). Multi-token patterns are checked first,
  in this order: "peanut butter", "almond milk", "soya milk", "soy milk", "chana dal", "moong dal",
  "egg white"(-> egg), then single tokens with plural forms listed: whey; casein; paneer; egg, eggs,
  anda; chicken; fish; mutton; prawn, prawns; tofu; soya, soy; dal, daal, dhal; rajma; chana, chole;
  curd, dahi, yogurt, yoghurt; milk; cheese; peanut, peanuts; almond, almonds; oats. "chana dal" and
  "moong dal" map to dal; "almond milk" to almond; "soya milk" to soya; "peanut butter" to peanut.
  Negatives tested: eggplant, eggless, milkshake (one token "milkshake", no match), buttermilk (no
  match), whey-free, egg-free mayo. Family rows display the family name ("Whey"); "N kinds" only when
  N >= 2. The plural fold runs on UNMATCHED keys only and merges `kinds` as a set. Share = of
  ITEMISED protein in range; the section note says "Share of the protein in your itemised meals."
  The concentration line uses the full sorted list (not the top 8), shows when N <= 5, >= 10 items
  and itemised protein >= 50 % of day-total protein in range; "1 food gives 72%" singular.
U10 (P2-3, P3) `proteinBySlot` sums to the day's protein (unit invariant test). Averages over full
  days in range (>= 3). The suggestion shows only with a known target, when the average full day is
  under 90 % of it; gap rounded up to 5 g and capped at 30 g ("Adding 30 g at breakfast closes most
  of the gap").
U11 (P1-5) A weekday shows a % when it has >= 4 counted days; the best/worst line needs both >= 4
  and a gap >= 30 points. Hidden without targets. Semantics label lists every weekday's %.
U12 (P1-6) Replaced: "WHERE YOUR ON-TARGET DAYS DIFFER" compares protein BY MEAL (breakfast, lunch,
  dinner, snacks) on onTarget days vs lowProtein days (not under/over; the calorie and total protein
  rows are dropped as true by definition). Shown when each side has >= 3 days; hidden without targets.
U13 (P1-3, P2-8) Rows = the last 6 CALENDAR months ending this month (an empty month shows "No
  logs"); the current month is labelled "Nov (so far)" and carries no arrow. Earlier months fold into
  one row per calendar year, labelled by the months it covers when partial ("May-Jun 2026"); a year
  row has no arrow. The arrow compares with the immediately preceding calendar month only, when both
  have >= 3 full days and differ by >= 5 g. Weight change: the month's last weigh-in minus the
  previous month's last weigh-in (month-end to month-end); dash when either is missing. Same-day
  weigh-ins dedupe (last wins); weigh-in dates parsed with `parseDayKey` on the first 10 chars, an
  unparseable date is skipped. History shorter than 6 months shows only months since the first day.
U14 (P3) functionality-flow.md: ADD a Nutrition History row (none exists). nutrition CLAUDE.md line
  50 (runs "break") updated. sot_registry `nutrition_history` concept: method list and the new
  behavioral test path. Text-scale tests cover the new sections (7+ months, 2 years, a year row
  expanded).
Semantics (P2-10): month blocks get a summary per month; weekday bars, the two stacked charts and
  protein by meal each get one Semantics label; the heatmap summary stays.
Added mutants: 30 vs 31 window; currentRun recency; water skip; zero-state tie; family order
  (chana dal); tokeniser negatives; kinds merge; weekday threshold 4; month tap in a gap; trend tap
  with the label column; on-target table shown at >= 3 each side; month-end weight change.

## 10. Round 2 (needs-changes: 0 P0, 2 P1, 7 P2, 10 P3) — all folded in §11

## 11. Revisions after round 2 (supersede §4 and §9 where they differ)

Header scope (R2 P1-1): the header uses ALL days, like the calendar, insight lines, top foods and
  the monthly report. It never follows the range chip. Test: header numbers identical on 1W and All.
Logging run (R2 P1-2): ONE function `loggingRun(days, todayKey) -> (current, best)`; `journeyStats`
  returns only `(logged, logged30, avgProtein30)`. The logging run shows in the HEADER only (not in
  HIT RATE & STREAKS, which follows the chip). Copy, one line under the header stats:
  - today not logged, current N >= 1: "Logged N days in a row. Log today to make it N+1."
  - today logged, current N: "Logged N days in a row, today included."
  - current 0: "Log a meal today to start a logging run."
  - best > current and best >= 3: append " Best: B."
  `current` counts back from today (if logged) or yesterday; a day not logged ends it.
Water row (R2 P2-1): water keeps today's break rule and its own copy "days in a row at your water
  target"; the section note reads "Calories and protein count full days only; days you did not log
  are skipped." The 7-day recency bound applies to calories and protein only.
Monthly weight (R2 P2-2): a month's change = its last weigh-in minus the LATEST weigh-in before that
  month (any earlier month, including before the first day); labelled "since <Mon>" when that
  anchor is not the previous calendar month. Dash when the month has no weigh-in or no anchor. A
  year row's change = its last weigh-in minus the latest weigh-in before the year's first covered
  month. The "(so far)" month uses its latest weigh-in. `monthlyRows` computes over ALL days and
  weights, so the first shown month compares with folded data. Expanded year months show the same
  fields as month rows, arrows included. Month and year labels carry the year whenever the shown
  rows span two calendar years ("Jan 2027", "Dec 2026"). The fold label covers months since the first
  day ("May-Jun 2026"). Weigh-in day keys stay `substring(0,10)` as stored (device-local; noted, not
  changed — pre-existing, the overlay does the same).
Food families (R2 P2-3): matching order is the list order, top to bottom; the multi-token entries
  come first ("peanut butter", "almond milk", "soya milk", "soy milk", "oat milk", "coconut milk",
  "chana dal", "moong dal", "egg white"), then single tokens in §9's order (whey first). So "whey in
  almond milk" -> almond (accepted, tested); "chicken biryani with egg" -> chicken; "dal makhani" ->
  dal; "paneer tikka" -> paneer; "whey protein isolate" -> whey. "oat milk" -> oats; "coconut milk" ->
  no family (excluded entry maps to none). The guard: a match is rejected when the token right after
  the last pattern token is exactly "free" or "less". `kinds` = distinct keys after trailing-s
  normalisation, shown on family rows only ("Egg"/"Eggs" = 1 kind). The concentration line reads "N
  foods give X% of the protein in your itemised meals."
Y labels (R2 P2-4): number-only labels (unit is in the average line); the column width is measured
  with `TextPainter` from the widest label (min 28 dp), the same width for both U7 charts; a 1.3
  text-scale test asserts no label ellipsises.
Trend tap test (R2 P2-5): the CustomPaint gets key `history_trend_plot`; the tests tap the first and
  last bar centres in THAT rect and assert the chart's left edge is right of the label column.
Month labels (R2 P2-6, P3): block width = max(cells width, measured label width); the label is the
  3-letter month, plus the year on the first block and on every January when the calendar spans more
  than one year; test a 1-day first block with a year label. Tap mapping tests the cell rect, so a
  tap in the empty part of a widened block returns null (test).
Repointed tests added (R2 P2-7): screen_test 130 (eyebrow), 241-248 (heatmapIndexAt -> monthBlocks,
  tap offset), 217 ("Dal Rice" -> family row "Dal"), 260 (heatmap summary stays one Semantics
  container with `excludeSemantics`; month labels are excluded from it). Text-scale tests for the new
  sections.
P3 folds: the U7 bounds come from one pure function `chartBounds(values, target)` that widens to
  include the target; weeks = days ~/ 7. U10 compares the range average with the latest target
  (stated in the line: "your current target"). U11 hides the whole section when no weekday reaches 4
  counted days. U12 section titled "ON-TARGET VS LOW-PROTEIN DAYS". U2 signature:
  `hitStats(..., {bool? skipUnjudged})`, null -> `kind != HitKind.water`. hitStats doc comment
  (":~463", the word "break") and nutrition CLAUDE.md line 50 updated. Protein row colour stays
  `metricColor(protein)` (the mockup's red row was wrong; only low-protein CELLS turn red). SoT
  `nutrition_history` keeps its existing behavioral_test_path and lists the v2 test in its notes.
  The share mutant's fixture holds 10+ foods.

## 12. Round 3 (delta, converged: 0 P0, 0 P1, 1 P2, 8 P3) — folded

- Family order (P2-1): single tokens in this final order: whey; casein; chicken; fish; mutton;
  prawn, prawns; paneer; egg, eggs, anda; tofu; soya, soy; dal, daal, dhal; rajma; chana, chole;
  curd, dahi, yogurt, yoghurt; oats; milk; cheese; peanut, peanuts; almond, almonds. So "chicken
  biryani with egg" and "chicken egg roll" -> chicken; "oats with milk" -> oats. Tested.
- First-ever month (P3-1): no earlier anchor and >= 2 weigh-ins in the month -> last minus first,
  labelled "within <Mon>"; else dash.
- Year row (P3-2): last weigh-in WITHIN the covered months minus the anchor before them.
- Plurals (P3-3): "Logged 1 day, today included." / "Logged 1 day in a row. Log today to make it 2."
- §9 U7's "target only when inside" is superseded: `chartBounds` always includes the target (P3-4).
- Tests (P3-5): `history_trend_chart` stays on the GestureDetector (screen_test 228 unchanged); the
  new `history_trend_plot` key is on the CustomPaint. The day sheet keeps raw item names
  (screen_test 280 unchanged). `history_days_logged` key and the "Days logged" label stay (135).
  Family display names are title-case ("Egg", "Dal"), so writer_to_reader 283-303 and 464 still hold.
- Label measurement (P3-6) uses `MediaQuery.textScalerOf(context)`.
- Macro split labels (P3-7) are "0", "50", "100" with "%" in the note; section renamed
  "HIT RATE & RUNS".
- Guard rejection (P3-8): a rejected match continues with the next family in order; no later
  match -> the name keeps its own key. Test "egg free paneer" -> paneer.

## 13. Build: mutants run (§4.4 rule 21)

Scripted (each replacement count confirmed 1, no compile errors), run against
`nutrition_history_v2_test.dart`, `nutrition_history_writer_to_reader_test.dart` and
`nutrition_history_screen_test.dart`, reverted. Red tests per mutant: M1 skip -> break 2; M2 recency
7 -> 30 1; M3 water skips 1; M4 31-day window 3; M5 today breaks the logging run 1; M6 zero-state tie
1; M8 prefix instead of whole-token match 1; M9 free/less guard off 1; M10 kinds without
normalisation 1; M11 concentration threshold 1; M12 weekday minimum 3 1; M14 compare minimum 2 1;
M15 weight anchor `<=` 1; M16 five month rows 1; M17 low protein gold 1.
Two survivors were EQUIVALENT (dead code), so the code was removed instead: M7 the "chana dal" /
"moong dal" multi-token entry (the single-token order already sends them to Dal), M13 the block
column check in `monthBlockIndexAt` (a column past the cells always gives an index >= length).
Not covered by a mutant: the trend y-label column outside the GestureDetector (the existing tap test
taps the chart rect; `history_trend_plot` key added for a future check).
