# One personal-records card (Home + Train) and one plateau definition (coach)

Founder observation 2026-11-26 (web, after PR #354). Mockup (approved, v2):
`docs/mockups/2026-11-26-pr-card-unify-v1.html`. Diagnoses `83e031` (Train PR card), `8300e1`
(coach plateau). Branch / worktree `pr-card-unify`.

## 1. Observation and founder decisions

"Home has PERSONAL RECORDS with SEE ALL; Train has YOUR STATS with VIEW ALL EXERCISE PRS. Why two
things? They should be in sync and reusable. Train's see-all has no graph. What is 'First
logged'?" Decisions (2026-11-26, recorded in chat and the mockup):

- D1 Both screens show the TOP 4 = Home's rule: the 4 most recently set PRs
  (`loadAllExercisePRs` sorts newest PR day first, `workout_repository.dart:1010`). Kept as is.
- D2 Train heading `PERSONAL RECORDS` (was `YOUR STATS`).
- D3 Train KEEPS its full-width `VIEW ALL EXERCISE PRS →` button; it opens Home's sheet (sparks,
  rows open the trend sheet). Home keeps its `SEE ALL N →` link (shown past 4).
- D4 The coach's plateau insight is fixed in this batch (it is the other reader of the code being
  deleted).
- D5 Plateau definition = the plan engine's (`plateau_scan.dart`): per exercise, best-set Epley
  e1RM per session, >= 3 sessions spanning >= 28 days inside 63 days, (max-min)/max <= 5 %,
  compound lifts by exact library name, not under readiness fatigue. Reps count (40 x 6 -> 40 x 8
  is progress). Per lift (bench flat, deadlift rising: only bench). A > 5 % decline is not "flat":
  no plateau; a separate "declining" insight is NOT in scope (founder agreed, new feature).
  Bodyweight / timed rows have no e1RM: skipped, as the plan engine does.
- D6 (after round 1) With ZERO PRs Train shows Home's line `Log workouts to see your PRs here`
  and NO button (today: the button always, a snackbar on tap, and a "No stats yet" card).
- D7 (after round 1) The coach flags only a lift whose LAST session is within 14 days (a lapsed
  lifter is not told "time to adjust"), and the copy says "over your last N weeks" (N <= 9: the
  63-day window caps what it can see).

## 2. Bug history (§4.1.5)

Grep of `docs/diagnoses/*.md` for StatsGrid / loadKeyLiftPRs / workoutStatsProvider / key lift.
- **Recurrence of cb1ab1** (2026-05-16, PR readers showed the cumulative sum). Its doc says "three
  readers downstream (`allExercisePRsProvider`, `StatsGridWidget`, `PRSnapshot`) all derive from
  `loadAllExercisePRs` -- fixing the canonical reader closes all three". False for StatsGrid's
  key-lift branch: `loadKeyLiftPRs` is a SECOND PR reader that never used the canonical one. Same
  class as OI-377 (a duplicate reader of one concept) and the writer/reader drift class 2.1.
- The coach plateau: no prior diagnose. Related: debugging class 2.19 (highest-ever concepts
  rendered from current values) and the e1RM extraction rationale in `e1rm_history.dart` ("ONE
  loop ... instead of three, the #1 writer/reader-drift bug class").

## 3. Writers and readers (§4.1)

Writer (all PRs, unchanged): `WorkoutWriteService.logExercise` writes `exlog_*` rows.

PR readers today:
- Canonical: `WorkoutRepository.loadAllExercisePRs` (`workout_repository.dart:952`) via
  `exercisePrValueOfRow`; -> `allExercisePRsProvider` (`home_provider.dart:1073`) -> Home
  `PrSnapshot` (`pr_snapshot.dart:31`).
- DUPLICATE: `WorkoutRepository.loadKeyLiftPRs` (`workout_repository.dart:1035`): substring
  names ("bench press" anywhere: incline / dumbbell bench count as Bench; any squat but split;
  any deadlift but romanian), top-level `weight_kg`, `previous` = the earlier running max in Hive
  KEY order (not date). Readers: `workoutStatsProvider` (`train_provider.dart:1215`) ->
  `StatsGrid._loadPRs` (`stats_grid.dart:150`); `PatternDetector._plateauDetector`
  (`pattern_detector.dart:145`).
- `StatsGrid` fallback (`stats_grid.dart:165-183`): top 4 of `allExercisePRsProvider` with
  `previous: 0` -> `_PRData.changeText` (`:342-350`) prints `First logged!` on EVERY tile.
- `StatsGrid._showAllPRsSheet` (`:181-330`): a hand copy of Home's sheet, no sparks, no tap.
- `PrStatsGrid` (`lib/features/train/widgets/pr_stats_grid.dart`): no reference anywhere.

Plateau readers today:
- Plan engine: `PlateauScan.plateauedGroups` / `plateauedExerciseNames`
  (`plan_engine/plateau_scan.dart:80`, `:124`), each with its own copy of the scan loop, over
  `buildE1rmByDate` (`e1rm_history.dart`) and `isFlat`.
- Coach: `PatternDetector._plateauDetector` (`pattern_detector.dart:143-212`): gate by
  `loadKeyLiftPRs`, history by `getExercisePRHistory` (substring name, top-level `weight_kg`,
  device-local `DateTime.now()`), "stuck" = max weight in the last 42 days <= max before, and
  `weeksStuck = getExtendedWeeklyWorkoutCounts(weeks: 12).length.clamp(6, 12)`, which is the
  length of a 12-entry list: always 12 (bug). Its insights reach `insight_card.dart` (Home),
  `deep_analysis_card.dart`, `ai_snapshot_builder.dart:1076` (`pattern_ids` / `top_pattern`),
  `coach_memory_service.dart:197`, the dev panel. No reader keys on a `plateau_<key>` id (grep
  of lib/ and supabase/).
- Not changed: `ai_snapshot_builder.enrichContextForQuery` (`:439`) keeps
  `getExercisePRHistory(name)`: it answers FREE TEXT ("how has my squat been"), where a substring
  match is the intent.

## 4. Changes

### 4.1 One PR card (`lib/features/home/widgets/pr_snapshot.dart`)
- `PrSnapshot({PrSeeAll seeAll = PrSeeAll.link})`; new enum `PrSeeAll { link, button }`.
  `link`: today's `SEE ALL N →` past 4 (Home, unchanged output). `button`: a full-width
  `WardButton` `VIEW ALL EXERCISE PRS` (outline, trailing arrow: Train's current widget and
  style) shown whenever there is at least one PR; it opens the SAME `_showAllPRsSheet`.
- Empty (no PR): Home's existing line `Log workouts to see your PRs here` for both; the Train
  button is hidden (D6, founder decision).
- Home call site unchanged (default `link`): Home renders byte-for-byte as today.

### 4.2 Train (`lib/features/train/screens/train/screen.dart:335`)
- `const StatsGrid()` -> a `PERSONAL RECORDS` `WardEyebrow` (Home's `_buildSectionLabel` style:
  gutter padding) + `Padding(screenPadding, PrSnapshot(seeAll: PrSeeAll.button))`.
- Position unchanged: after the phase-unlock card, before the roadmap pill (pinned by
  `train_screen_compact_layout_test.dart`, repointed from `const StatsGrid()` to the new marker).
- Train imports `package:icanbefitter/features/home/widgets/pr_snapshot.dart` (Train already
  imports Home's providers; precedent).

### 4.3 Deletions
- `lib/features/train/widgets/stats_grid.dart` (whole file), `pr_stats_grid.dart` (whole file).
- `WorkoutRepository.loadKeyLiftPRs`; `workoutStatsProvider` (`train_provider.dart:1213-1223`).
- Every `ref.invalidate(workoutStatsProvider)` / list entry: `edit_workout_log_sheet.dart:144`,
  `template_builder_screen.dart:482`, `day_swap_provider.dart:77`, `train_provider.dart:2630`,
  `:2831`, `graduation_screen.dart:479`, `workout_surface_invalidation.dart:19`,
  `day_rollover_service.dart:277`. Checked 2026-11-26: the edit sheet (:144), `train_provider`
  :2630, the graduation screen, the day rollover, `day_swap_provider` (its list, :22) and
  `workoutSurfaceProviders` already invalidate `allExercisePRsProvider` next to it. The two that
  do not, template save (`template_builder_screen.dart:482`) and `TemplatesNotifier.deleteTemplate`
  (`train_provider.dart:2831`), change `schedule_*` / template rows only, never an `exlog_*` row,
  so no PR can change there: the line is dropped with no replacement.
- `scripts/check_mutation_invalidation_set.dart`: drop `workoutStatsProvider` from
  `workoutCanonical` (header comment too). Grandfathered gate (ledger unchanged).
- `WorkoutRepository.getExtendedWeeklyWorkoutCounts` (`workout_repository.dart:1316`): its only
  caller is the deleted `weeksStuck` line (`pattern_detector.dart:196`); deleted (round 2).
- `day_swap_provider.dart:72-73` comment ("the same six as tool_dispatcher...") rewritten to the
  remaining list.

### 4.4 One plateau scan (`lib/shared/repositories/plan_engine/plateau_scan.dart`)
- New public `static List<FlatLift> flatCompoundLifts({int? recentWithinDays})` (no flag / phase /
  fatigue gate). With `recentWithinDays`, a lift is kept only when
  `lastDate.compareTo(istDateStr(nowWall().subtract(Duration(days: recentWithinDays)))) >= 0`
  (IST day strings compared lexically, the file's existing form at `plateau_scan.dart:91-92`;
  INCLUSIVE: a session exactly 14 days ago counts). Never `DateTime.parse(istTodayStr())`
  (device-local midnight, the OI-390 / OI-494 class). The two plan-engine wrappers pass null.
  Body:
  the existing loop ONCE (cutoff `nowWall() - 63 d` IST, `buildE1rmByDate`, >= 3 sessions,
  compound by exact name, span >= 28 d, `isFlat`), returning
  `FlatLift { name, sessions, spanDays, bestE1rm, lastDate }` (`lastDate` = the last session's
  IST day, for the coach's recency rule). `plateauedGroups` and
  `plateauedExerciseNames` keep their gates and become thin maps over it (same output: the
  plateau tests, the titration / plateau gate and the generator golden prove it).
- `_fatiguePresent` becomes public `fatiguePresent()` (unchanged body).
- `plan_generator.dart` is NOT touched (rule 14).

### 4.5 Coach (`lib/features/ai_coach/services/pattern_detector.dart:143-212`)
- `_plateauDetector`: if `PlanEngineFlags.readinessEnabled && PlateauScan.fatiguePresent()`
  -> null (recover, not plateau). Else `PlateauScan.flatCompoundLifts()` filtered to
  via `flatCompoundLifts(recentWithinDays: 14)` (D7; the clock is the `nowWall` seam, so tests pin
  it with `setTestClockTo`); none -> null; pick the longest `spanDays`, ties by name;
  `weeks = spanDays ~/ 7` (4..9).
- Insight: `patternId: 'plateau_<lowercased name>'`, severity high, pushWorthy unchanged.
  `coachNotice: "<name> est. 1RM flat at ~<best>kg across <sessions> sessions over the last <weeks> weeks."`
  `userMessage: '<name>: no real progress over your last <weeks> weeks (est. 1RM ~<best> kg). Time to adjust!'`
  (D7). `pushWorthy` has no consumer outside pattern_detector.dart (round 1, verified).
  (`<best>` rounded to 0.5 kg).
- No phase / PRO gate (the coach insight had none; its consumers keep their own gates).
- `getExercisePRHistory` loses its plateau caller; the snapshot builder keeps it (section 3).
- Failure: the coach calls the scan outside the plan-engine wrappers' try/catch; every detector
  runs inside `PatternDetector._tryAdd` (`pattern_detector.dart:95-104`), which catches, so a
  closed box yields no insight (unchanged contract).
- Known, unchanged: `spanDays` uses `DateTime.parse` of IST day strings (device-local), so in a
  DST zone a span can read a day short (weeks 8 instead of 9). Pre-existing plan-engine maths;
  not changed (it would alter plan-engine outputs).

### 4.6 Docs
SoT registry: `exercise_personal_records` readers (StatsGrid out, Train `PrSnapshot` in, note
loadKeyLiftPRs deleted), the `provider_invalidation_set` lists at lines ~215, ~344, ~5438,
~19398 without `workoutStatsProvider`, the `pr_stats_grid.dart` row (~10465), the stats_grid
row (~19621); `plateau_escalation` / a new reader note for the coach. `lib/features/home/CLAUDE.md`
(row 8 "top 4 by volume when key lifts empty" -> "the 4 most recently set PRs; same card on
Train", the stale "Stats grid empty" pitfall), `lib/features/train/CLAUDE.md` (the compact-layout
paragraph :108 names `StatsGrid`; the PR row near :65), `docs/architecture/sync.md:581` / `:591`,
`docs/architecture/functionality-flow.md:156` (TRAIN-14's invalidation set), the registry note at `sot_registry.yaml:5362` ("StatsGrid / graduation" -> "the PR card /
graduation").

### 4.7 Registry line ranges (round 1 P1-1)
`check_sot_registry_parity.dart` treats a stale `line_range:` as an ERROR. After the LAST code
edit of each commit, map EVERY structured `line_range:` / `line:` cite of every edited file
(train_provider.dart ~27 cites, workout_repository.dart, pr_snapshot.dart 26-205, train
`screen.dart`, day_rollover_service.dart, edit_workout_log_sheet.dart, template_builder_screen.dart,
graduation_screen.dart, day_swap_provider.dart, workout_surface_invalidation.dart,
pattern_detector.dart, plateau_scan.dart) through
`git diff -U0 <merge-main-parent> -- <file>` hunks by script (skip 1-9999 sentinels; re-cite by
hand any cite inside a hunk), then run the parity gate. Whole entries for deleted files and
symbols go, not a re-cite: the `stats_grid.dart` reader rows (`sot_registry.yaml:5384`
`method: StatsGrid`, `:19621`) and the `pr_stats_grid.dart` row (~10465); the parity gate also
keys on `method:` symbols (`check_sot_registry_parity.dart:141`). No registry entry names
`loadKeyLiftPRs`, `_plateauDetector` or `getExercisePRHistory` (round 2 grep). Memory:
`feedback_registry_range_shift_measured_on_wrong_state`, `feedback_registry_range_base_is_the_merge_main_parent`. `docs/discipline.md`
quotes the provider inside historical worked examples: left as history.

## 5. Tier, blast radius, mode

Paths span home, train, ai_coach, core/services, plan_engine, scripts: **M by the S-filter, and
plan-engine-touching => treated as L** (full pipeline: x2 plan review, gate loop + CI before every
reviewer dispatch, B-pass, plan-review record). Blast radius **account**
(`blast_radius_from_diff.dart`: day_rollover_service.dart, pattern_detector.dart). Execution:
inline, one worktree. Multi-unit => closure ledger `docs/audit/pr-card-unify.closure.yaml`.

## 6. Units (closure ledger)

U1 Train shows Home's card (D1-D3). U2 duplicate PR reader deleted (`loadKeyLiftPRs`,
`workoutStatsProvider`, invalidation sites, gate set). U3 "First logged!" / "this month" text
gone (by U1). U4 Train's sheet copy gone (by U1). U5 dead `PrStatsGrid`. U6 coach plateau on the
shared e1RM scan (exact names, reps count). U7 `weeksStuck` always 12. U8 stale Home doc ("by
volume"). U9 orphan `getExtendedWeeklyWorkoutCounts` (round 2).

## 7. Tests (each mutated once, §4.4 rule 21)

- `test/contracts/pr_card_unify_behavioral_test.dart` (new): pumps Train's PR block and Home's
  with the same PR list: the same four tiles in the same order; Train has the eyebrow and the
  button, no `SEE ALL`; Home has the link past 4 and no button; the button opens the sheet whose
  rows carry `WardSpark`s and open `PrTrendSheet`; empty list -> the line, no button; no text
  `First logged`. The fixture has 6 PRs on 6 distinct days, so the order (newest first) and the
  cut at 4 are observable. Mutants: Train passing `link`; the button calling a different sheet;
  the button shown on empty; the empty branch returning before / after the button; the tiles'
  `take(4)`.
- Home byte-for-byte: existing `test/features/home/pr_trend_widgets_test.dart` stays green
  untouched.
- Port `test/features/train/stats_grid_cardio_pr_test.dart` (OI-389: a 1800 s cardio PR never
  prints km) to the Train PrSnapshot, then delete the old file.
- Repoint: `train_screen_compact_layout_test.dart`, `exercise_personal_records_writer_to_reader_test.dart`
  (:97 "stats_grid.dart exists"), `signed_out_provider_rebuild_behavioral_test.dart` (:484, and the
  per-file `_kTokenWatchSites` count for train_provider), `workout_surface_invalidation_test.dart`,
  `phase_unlock_end_to_end_test.dart`, `test/safety/provider_invalidation_test.dart` (9b: rewrite
  to the remaining set), `purchase_literal_inventory_test.dart` (:75 entry removed),
  `signed_out_provider_rebuild_behavioral_test.dart:161` (`train_provider.dart`: 6 -> 5 token
  watch sites). The day-swap list (`day_swap_provider.dart:75-`) has NO test pinning its members
  (checked: `tool_dispatcher_day_swap_invalidation_test.dart` and `day_swap_provider_test.dart`
  only override `currentPlanProvider`); removing one entry loses no pin. Its
  `allExercisePRsProvider` entry (:22 of the list) stays.
- Coach: `test/contracts/coach_plateau_insight_behavioral_test.dart` (new, real Hive exlog rows):
  (a) Barbell Bench Press 40x8 flat 3 sessions over 5 weeks -> one insight, name exact, weeks 5;
  (b) same weight with reps rising 6 -> 8 -> 10 -> null (e1RM rises > 5 %); (c) "Dumbbell Bench
  Press" flat, "Barbell Bench Press" rising -> the insight names Dumbbell only (exact names);
  (d) bench flat + deadlift rising -> bench only; (e) a > 5 % decline -> null; (f) bodyweight /
  timed only -> null; (g) readiness ON with >= 3 check-ins, most non-green -> null, and its mirror
  (readiness OFF, same rows) -> an insight; (h) 2 sessions -> null; (i) span 21 d -> null;
  (j) flat lift whose last session is exactly 14 days ago -> insight, exactly 15 -> null (D7,
  inclusive boundary); (k) spans of 40 and 49 days -> "last 5 weeks" / "last 7 weeks" (40 tells
  `~/ 7` from `.round()`); (l) two flat lifts, spans 35 and 49 -> the 49-day one; an equal-span
  pair -> the alphabetically first; (m) one exact-string assertion each on `userMessage`,
  `coachNotice`, `patternId` (lowercased), `severity`, `pushWorthy`, with a best e1RM that
  exercises the 0.5 kg rounding; (n) a flat lift whose earliest sessions fall outside 63 days ->
  judged on the in-window sessions only.
  `setUp` seeds the exercise library (`isCompoundByExactName` is false for unknown names) and
  pins the clock (`setTestClockTo`, `resetTestClock` in tearDown).
  Mutants: the fatigue gate; the readiness-flag condition; the span floor; the recency rule;
  weeks from a constant; `~/` -> `.round()`; 14 -> 15 and `>=` -> `>`; the pick rule (first /
  shortest / no tie-break); the rounding; the old substring / weight-only path restored.
  Also run (unchanged files that call `PatternDetector`): `bodyweight_trend_nudge_test.dart`,
  `day_of_week_completion_writer_to_reader_test.dart`.
- Plan engine unchanged in behaviour: `plateau_scan_test.dart`, `plateau_escalation_behavioral_test.dart`,
  `plateau_rotation_behavioral_test.dart`, the titration / plateau gates, `generator_golden_test.dart`
  green without edits.

## 8. Not established / risks

- Train's tiles now change with the most recent PRs (D1); a user who mostly sees Train loses the
  fixed Bench/Squat/Deadlift/OHP line-up (decided).
- The coach insight will fire less often than the old weight-only rule (reps count, exact names,
  span >= 4 weeks): intended.
- Device / web check by the founder after merge.

## 9. Round 1 (needs-changes: 2 P1, 4 P2, 2 P3), all folded

P1-1 registry ranges (4.7). P1-2 doc gaps (4.3 / 4.6). P2-1 lapsed lifter: recency 14 days
(D7, `FlatLift.lastDate`, test j). P2-2 wording (D7). P2-3 test strength (fixtures, mirrors,
mutants in section 7). P2-4 empty state made a founder decision (D6). P3-1 token count 6 -> 5,
library seeding. P3-2 the day-swap list's pin.

## 10. Round 2 (converged: 0 P0/P1, 2 P2, 4 P3), all folded

P2-1 recency maths inside `flatCompoundLifts(recentWithinDays:)` with IST strings, inclusive.
P2-2 orphan `getExtendedWeeklyWorkoutCounts` deleted. P2-3 4.7 list (+ workout_surface_invalidation,
whole-entry removals, `method:` keys). P3-1 boundary / pick / rounding / window tests and mutants.
P3-2 `_tryAdd` catches; DST span note (unchanged). P3-3 copy has no text consumer; two
PatternDetector tests to run. P3-4 functionality-flow TRAIN-14. Verified: byte-identical
plan-engine wrappers (Set outputs, no new exception path); weeks within 4..9.

## 11. Mutants run (§4.4 rule 21)

Card: K1 Train passes link (2 red), K2 button opens nothing (1), K3 empty branch skipped (1), K4 five tiles (1), K5 style inverted (4). Coach: C1-C12 each red (C11: 2). Every mutant applied by script with a confirmed count, no compile errors, reverted. Detail: diagnose docs 83e031, 8300e1.
