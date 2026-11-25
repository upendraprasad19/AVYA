# Nutrition History (since-day-one trends, target history, four clean-ups)

> **Revision 2 (after review round 1).** Section 11 lists every change; where an earlier
> section and section 11 disagree, SECTION 11 WINS.

Founder brainstorm 2026-11-25. Branch `nutrition-history`. Batch 2 of 2 (batch 1 = PR strength
charts, PR #345).

## 1. What the user gets

"INSIGHTS & TRENDS" on the Nutrition tab keeps its two weekly cards and gains a
`SEE FULL HISTORY` row that opens a new screen, **Nutrition History**, built only from Hive:

1. Journey header: day N since joining, days logged, this month's protein total.
2. Trend chart with range chips (1W / 1M / 3M / 6M / 1Y / All) and a metric switch (calories,
   protein, carbs, fat, fibre, water): daily bars, a 7-day rolling average line, the target line.
   Ranges over 3 months show weekly averages.
3. Consistency heatmap: one cell per day since joining, coloured on target / under / over / not
   logged.
4. Macro split over time: protein / carbs / fat share of calories per week.
5. Hit-rate and streaks for calories, protein and water (this week, best run).
6. Calories vs weight: 7-day calorie average with the weight series.
7. Top foods: most logged, and top protein sources.
8. Patterns: weekday vs weekend, calories by meal slot, training days vs rest days.
9. Insight lines in plain words, computed on the phone (no AI call).
10. Day drill-down: tap a bar or a heatmap cell to see that day's meals and totals.

Founder decisions (2026-11-25): a full screen opened from Insights & Trends; all ten items;
free for every user; history starts at the join date (or the first log if earlier); "on target"
= calories within 10 % of target and protein >= 90 % of target; top foods grouped by food name;
water and weight in, sleep and steps out; web uses the phone layout; a target history going
forward, WITH a cloud column; days before the first recorded target use the current target.

Also in this batch (found during the brainstorm):
- C1 the weekly Insights cards do not refresh after a target change.
- C2 Home and Nutrition use different fallback targets for a profile with no stored targets.
- C3 leftover readers of the removed one-day calorie adjustment.
- C4 a dead weekly-report reader with wrong keys.

## 2. Landings, tier, mode

The migration rule (`supabase/migrations/CLAUDE.md`, OI-527): a PR whose client needs an additive
migration stays red on `Supabase Integration Tests` until the migration is applied, and applying
needs the founder's per-action go. So the feature lands in two parts:

- **Landing A (this plan, sections 3-8):** the screen, the target history on the phone, C1-C4.
  No cloud change, no migration. Has full standalone value.
- **Landing B (section 9, outline; its own plan revision and x2 review before it is built):**
  `user_profile.target_history` + a merge RPC + push + restore. Blocked on the founder's go for
  the migration (`blocked_on_user`), not a deferral: until it lands the history survives normal
  use but not a reinstall, and the screen degrades to "current target" for unknown days.

Tier: `account` (measured per path with `scripts/blast_radius_from_diff.dart`:
`profile_write_service.dart`, `day_rollover_service.dart`, `app_router.dart` are `account`; the
nutrition and home files are `feature`). L/M pipeline: x2 plan review, plan-review record,
gate loop, CI on the PR, B-pass (`/code-review`) before the merge.
Execution mode: INLINE, one worktree. Closure ledger `docs/audit/nutrition-history.closure.yaml`
(more than 4 units).

Not behind a flag: no payment / sync / auth / AI prompt / plan generator path changes in
Landing A. The target-history writer is local, additive and idempotent; kill switch
`configBox['disable_target_history']` (true = `reconcile` returns at once, readers then see an
empty history and use the current target, exactly today's behaviour).

## 3. Ground truth (worktree at 2b5068be)

Stored data:
- Meals: `nlog_<IST date>_<slot>_<8 hex>[_n]` in nutritionBox, written by
  `NutritionWriteService.logMeal`: `date`, `meal_type`, `total_calories`, `total_protein`,
  `total_carbs`, `total_fat`, `total_fiber`, `items[]` (`name`, `quantity_g`, `calories`,
  `protein`, `carbs`, `fat`, `fiber`), `is_saved_meal`. The same box also holds saved-meal
  templates (no `date` field), the slot ledgers `nslot_ledger_<date>` / `nslot_cursor` /
  `nslot_meta`, and legacy `target_override_<date>` rows (these DO carry a `date`, with
  `delta_kcal` / `reason` / `expires_at` and no `total_*`). There is no `flog_` key (the undo
  stash is in memory).
- The day total every screen shows: `NutritionReadService.totalMacrosForDate`
  (`lib/core/services/nutrition_read_service.dart:112`): every Map value whose `date` equals the
  IST day and whose `is_saved_meal` is not true.
- Old rows can lack `items[]` (diagnose acdcfb): totals exist, item names do not.
- Water: healthBox `water_ml_<IST date>` (int), reader `HealthReadService.waterMlForDate`
  (`:79`). Water target: `WaterTargetService.instance.currentTargetMl()`.
- Weight: `weight_<IST date>`, surfaced by `weightHistoryProvider` (`home_provider.dart`).
- Workout days: completed `schedule_<date>` rows / `wlog_<date>` rows.
- Join date: `profile['onboarding_completed_at']`; `WorkoutRepository._earliestUserAnchorKey`
  already takes the earlier of it and the first `wlog_`.
- Restore brings meals (with items), water and weight back with no date limit
  (`sync_service.dart` restore `since = 2020-01-01`).

Targets:
- Stored on the profile: `daily_calories`, `protein_grams`, `carb_grams` / `carbs_grams`,
  `fat_grams`, `water_target_ml`. One recompute function `recomputeDerivedTargets`
  (`lib/features/profile/services/profile_target_recompute.dart:92`).
- Every TARGET-changing profile write goes through `ProfileWriteService`
  (`lib/features/profile/services/profile_write_service.dart`): three `userBox.put('profile')`
  sites (`:68`, `:96`, `:136`); `_fireSync()` follows at `:69` (only when `!skipSync`), `:97`,
  `:145`. The restore writes the profile through `updateProfile(skipSync: true)`
  (`sync_profile.dart:917`). Two direct writers of the key change no target:
  `body_fat_default_healer.dart:73` and `auth_session_bootstrapper.dart:450`
  (`stampOnboardingCompletedAt`). The water override is written outside the profile by
  `WaterTargetService.setUserOverride` (`water_target_service.dart:76`).
- Shown targets: `_resolveNutritionTargets` (`nutrition_provider.dart:66`, private) = stored
  pack, else recompute from weight/height/goal, else the literal 2400 / 184 / 280 / 80; then
  `effectiveMacroTargets` (`lib/core/utils/effective_macro_targets.dart`) for a PRO user's
  Low carb / Keto (calories and protein unchanged, carbs/fat converted); then
  `_applyCalorieOverride` (`:234`).
- Home: `NutritionSummaryNotifier.build` (`home_provider.dart:630-700`) reads the stored values
  itself, with its OWN fallbacks 2000 / 120 / 250 / 65 and no recompute (C2), applies the same
  strategy conversion, and reads the override (`:690`).
- Weekly cards: `WeeklyNutritionNotifier.build` (`nutrition_provider.dart:~1808`) reads the
  profile directly; `weeklyNutritionProvider` is NOT in `profileDerivedSurfaceProviders`
  (`lib/features/profile/providers/profile_surface_invalidation.dart:22-29`), the list Edit
  Profile, the weigh-in refresh and the coach goal switch invalidate (C1).
- The one-day override: its only writer (the coach tool) was removed 2026-05-31
  (`nutrition_repository.dart:481` comment, `tool_dispatcher.dart:1930`). Readers left:
  `getActiveTargetOverride`, `getDailyCalorieTargetWithOverrides`, `_resolveBaseDailyCalories`
  (`nutrition_repository.dart:478-600`), `_applyCalorieOverride` and its two call sites
  (`nutrition_provider.dart:74,81,229-248`), `home_provider.dart:688-695`; the naming row
  `docs/naming_conventions.md:92` (C3).
- `NutritionRepository.computeWeeklyReportData` (`nutrition_repository.dart:97`): no caller in
  `lib/`; reads `tdee` as the calorie target and `protein_target`, a key nothing writes. Cited
  by `test/sync/nutrition_slot_store_readers_test.dart:66` and `docs/sot_registry.yaml:754,2771`
  (C4).
- Server: `weekly-report` uses only `daily_calories` / `protein_grams` plus a strategy line, so
  Keto needs no server change. Verified read-only on the live project: `user_daily_snapshots`
  has 411 rows / 38 accounts, 173 with a calorie target: no backfill (all accounts are test
  accounts before store launch; parked per the launch-status rule).

Screen size: `check_god_screen_max_lines.dart` caps `lib/**/screens/*_screen.dart` at 800 lines;
`nutrition_screen.dart` is 1340 (on the transitional allow-list). The new screen is composed
from widgets under `lib/features/nutrition/widgets/history/`, and the edit to
`nutrition_screen.dart` must not grow it (see 5.6).

Bug history (section 4.1.5), classes applied:
- acdcfb: rows without `items[]`: top foods skip them and say how many meals had no item detail.
- c7a1f5 / OBS-11: a second target computation drifting from the canonical one: ONE resolver
  (5.1) for Nutrition, Home, the weekly cards, the History screen and the target history.
- bae4dd / 9c8958: a Hive-reading provider missing from a refresh list: C1 is this class.
- e5abc7: long histories read with a silent cap: the series is one local pass, no cap, no paging.
- IST rule: every day key through `istDateStr`.

## 4. Data layer (pure, no Riverpod)

### 4.1 Daily series
New `lib/features/nutrition/services/nutrition_history.dart`:

```dart
class NutritionDay {
  final String date;              // IST yyyy-MM-dd
  final bool logged;              // at least one counted meal row
  final double calories, protein, carbs, fat, fiber;
  final int waterMl;              // 0 = none logged
  final Map<String, double> caloriesBySlot; // breakfast / lunch / dinner / snacks
}

/// Counted meal row: the SAME predicate as totalMacrosForDate (a Map with a
/// `date`, not a saved meal).
bool isCountedMealRow(Map row);

/// One pass over [nutritionRows]; continuous list from [fromDay] to [toDay]
/// (both IST keys, inclusive); a day with no row has logged == false and zeros.
List<NutritionDay> buildNutritionDays(Iterable<Object?> nutritionRows,
    Map<String, int> waterByDay, {required String fromDay, required String toDay});
```

`NutritionRepository.loadNutritionDays()` supplies the rows (`nutritionBox.values`), the water
map (one pass over healthBox keys with the `water_ml_` prefix through a new
`HealthReadService.waterMlByDay()` is `account` tier; to stay in the feature the repository
reads through the existing `waterMlForDate` only for days in range when the range is short, and
otherwise through ONE new static `HealthReadService.waterMlByDay()`; decision: add the static,
it is 10 lines and the tier is already `account`), `fromDay` = the earlier of the onboarding day
and the first counted meal day, `toDay` = `istDateStr(now)`.

Invariant (tested): for every day, the series totals equal `totalMacrosForDate(day)`.
An unlogged day is NEVER a zero in any average, hit-rate or pattern: every aggregate takes
`days.where((d) => d.logged)` (water aggregates take days with `waterMl > 0`).

### 4.2 Aggregates (same file, pure functions over `List<NutritionDay>`)
`rollingAverage(days, metric, window: 7)` (over logged days in the window; null when none),
`weeklyBuckets(days)` (IST Monday weeks: averages over logged days, macro kcal shares using
4/4/9), `hitRate(days, targetFor, metric)`, `bestRun(...)`, `weekdayWeekend(days)`,
`slotShares(days)`, `trainingVsRest(days, trainingDays)`, `dayStatus(day, target)` ->
{notLogged, onTarget, under, over} with on target = `|cal - target| <= 10 %` AND
`protein >= 90 %`; a day with no known target has status `logged` (neutral colour).

### 4.3 Top foods
`topFoods(nutritionRows, {fromDay, toDay})`: over counted rows with `items[]`; key = item name
lower-cased, trimmed, inner whitespace collapsed, a leading quantity token dropped
(`^\d+(\.\d+)?\s*(x|pcs?|g|ml|cups?|bowls?|pieces?|slices?|glass(es)?|tbsp|tsp|katori)?\s+`),
a trailing plural `s` dropped when the singular also occurs; display name = the most frequent
original spelling. Returns count, total protein, total kcal per food, and `mealsWithoutItems`.

### 4.4 Insight lines
`nutritionInsights(days, targetFor, weeks, trainingDays)` -> at most 4 short sentences, each
produced only above a stated minimum sample and a stated minimum effect:
weekend vs weekday calories (>= 4 logged weekend days and >= 8 weekdays, difference >= 150 kcal);
protein now vs first 30 days (>= 14 logged days in each, difference >= 10 g/day);
training vs rest day calories (>= 5 each, >= 150 kcal); logging consistency this month vs last
(>= 10 percentage points); best protein run (>= 5 days). Copy is plain and factual
("You eat about 310 kcal more on weekends"), no judgement words, Wardroom voice not required
for data lines (read `lib/shared/widgets/wardroom/CLAUDE.md`; headers use its eyebrow style).

## 5. Targets

### 5.1 ONE resolver (fixes C2, serves everything)
New `lib/features/nutrition/services/nutrition_targets_resolver.dart` (pure):

```dart
typedef ResolvedTargets = ({double calories, double protein, double carbs, double fat,
    DietStrategy strategy, bool isFallback});
/// stored pack -> recompute from inputs -> literal last resort (isFallback: true);
/// then effectiveMacroTargets. No override step (C3).
ResolvedTargets resolveNutritionTargets(Map<String, dynamic>? profile,
    {required bool strategyEnabled, required bool pro});
```

The body is `_resolveBaseTargets` + `_applyDietStrategy` moved verbatim from
`nutrition_provider.dart`. `_resolveNutritionTargets` there becomes a thin adapter returning
the existing `Map<String, double>` (same keys, same `strategy_index`), so no caller changes.
`NutritionSummaryNotifier.build` (Home) calls the resolver in place of its own reads and
fallbacks. Behaviour change, deliberate: a profile with NO stored targets shows on Home the
same recomputed (or 2400-pack) numbers as Nutrition, where today it shows 2000/120/250/65.
A profile with stored targets is byte-identical (pinned by a preservation test written first).

### 5.2 Target history (local, Landing A)
New `lib/features/nutrition/services/target_history.dart`:

- Stored at `userBox['target_history']`: a list, oldest first, of
  `{from: 'yyyy-MM-dd', calories, protein, carbs, fat, water_ml, strategy, at_ms}` (ints, the
  EFFECTIVE numbers). Max 400 entries (oldest dropped; ten years of monthly changes is 120).
- `TargetHistory.read()` -> entries (defensive parse; a malformed entry is skipped).
- `TargetHistory.targetFor(day, entries)` -> the last entry with `from <= day`; for a day before
  the first entry, the FIRST entry with `assumed: true`; null when there are no entries.
- `TargetHistory.reconcile({DateTime? now})`: kill switch; needs an open Hive session; resolves
  today's effective targets with the 5.1 resolver (`pro` from the PURE
  `SubscriptionService.proStateSnapshot()`, never `isPro()`) and
  `WaterTargetService.currentTargetMl()`; does nothing when `isFallback`; if the last entry's
  seven value fields equal today's, does nothing; else writes an entry with `from` = today's IST
  key, REPLACING a same-day entry (the last change of a day wins; if the replacement makes it
  equal to the previous entry, the same-day entry is removed). Never throws (non-fatal
  `target_history_reconcile`). Returns whether it wrote.

Triggers (each idempotent; a missed one is healed by the next):
- T1 `ProfileWriteService`: one private `_afterWrite()` called at the three `_fireSync()` sites
  -> `TargetHistory.reconcile()` (dated the day of the change).
- T2 `DayRolloverObserver._doRolloverWithRef` (cold start, resume, midnight): catches a change
  with no profile write (PRO start or lapse, the strategy flag, a water override).
- T3 `reckonAndNotifyAfterRestore`: after a restore merged cloud profile values.
- T4 the History screen's `initState` (so the screen never opens on a stale history).
`resetJourney` / sign-out need no new code: `userBox` is per user and already cleared by them
(verified in the test by key presence after `clearAllData`).

First run: the first reconcile writes one entry dated today; every earlier day reads it as
`assumed` (the founder's "old days use the current target").

### 5.3 C1
Add `weeklyNutritionProvider` to `profileDerivedSurfaceProviders`
(`profile_surface_invalidation.dart`), and the new `nutritionHistoryProvider` (6.1). The
existing unit test of that list is extended; behavioural test: change the stored target through
`invalidateProfileDerivedSurfaces`, the weekly data's `calorieTarget` follows.

### 5.4 C3
Delete `getActiveTargetOverride`, `getDailyCalorieTargetWithOverrides`,
`_resolveBaseDailyCalories` (after `grep -rn` proves no caller), `_applyCalorieOverride` and its
call sites, the override block in Home, the stale comment at `tool_dispatcher.dart:1930` stays
(history). `docs/naming_conventions.md:92` is marked RETIRED (the prefix stays reserved: old
rows may still sit in a nutritionBox). Old `target_override_*` rows are left in place (tiny,
unread; `isCountedMealRow` already ignores them: they have no `date` equal to a day... verified
in the test with a seeded row carrying a `date`, see 7.1 N3).

### 5.5 C4
Delete `computeWeeklyReportData`; remove its line from
`test/sync/nutrition_slot_store_readers_test.dart:66` and from the two registry method lists.

### 5.6 Entry point
`_buildInsightsSection` gains one tappable row `SEE FULL HISTORY` under the two cards
(`context.push('/nutrition/history')`). To keep `nutrition_screen.dart` from growing, the whole
Insights section moves to `widgets/insights_section.dart` (a `ConsumerStatefulWidget` owning
`_isInsightsExpanded`), which shrinks the screen file.
Route: `GoRoute(path: 'history')` under `/nutrition` in `lib/core/router/app_router.dart`.

## 6. Screen

### 6.1 Provider
`lib/features/nutrition/providers/nutrition_history_provider.dart`:
`nutritionHistoryProvider` (a `Provider`) watches `authUserIdTokenProvider` (returns an empty
value on `'<anon>'`), `restoreCompletedTickProvider`, `dailyNutritionProvider` (rebuilt on every
meal log), `macroTargetsProvider`; returns `NutritionHistoryData {days, targets (history
entries), weights, trainingDays, joinedDay}`. Registered in the signed-out case table and
`_kTokenWatchSites` (lesson of PR #345).

### 6.2 Layout (`lib/features/nutrition/screens/nutrition_history_screen.dart`, < 400 lines)
A `ListView` of section widgets in `widgets/history/`: `history_journey_header.dart`,
`history_trend_chart.dart` (fl_chart `BarChart` + line overlay; metric chips; range chips;
target as a stepped line from the history; tap -> day sheet), `history_heatmap.dart`
(`CustomPaint`, 7 rows by weeks, horizontally scrollable, newest at the right, legend, tap ->
day sheet), `history_macro_split.dart`, `history_hit_rates.dart`, `history_weight_overlay.dart`,
`history_top_foods.dart`, `history_patterns.dart`, `history_insights.dart`,
`history_day_sheet.dart` (the day's meals via `NutritionReadService` rows of that date, totals,
target and status).
States: no logs at all -> one empty card ("Log a meal to start your history") and nothing else;
each section hides itself below its own minimum sample (stated in the widget and tested);
no loading state (synchronous Hive). Tokens: `AppColors` / `AppTypography` only; status colours
`ok` / `warn` / `info` / `textGhost`; a legend always accompanies colour (never colour alone).
Performance: aggregates computed once per provider build; the heatmap paints, it does not build
one widget per day.

## 7. Tests

### 7.1 Pure / behavioural (real Hive where a writer exists)
- N1 `nutrition_history_writer_to_reader_test.dart`: meals through `NutritionWriteService.logMeal`
  on several days and slots, water through `HealthWriteService.setWaterMl`; every day's series
  totals == `totalMacrosForDate`; gaps are `logged: false`; first/last day bounds.
- N2 unlogged days never enter an average, hit-rate, pattern or weekly bucket (literal numbers).
- N3 non-meal rows in the box (saved meal, `nslot_` ledger, `flog_` stash, a seeded
  `target_override_` row with a `date`) : the series equals `totalMacrosForDate` for that day,
  whatever that reader does with them (consistency, not a new rule).
- N4 `dayStatus` boundaries: exactly 10 % calories and exactly 90 % protein are on target.
- N5 top foods: quantity prefixes, case, plural, rows without `items[]` counted in
  `mealsWithoutItems`.
- N6 each insight line: just below its sample or effect threshold -> absent; just above ->
  the literal sentence.
- T1 `nutrition_targets_resolver_preservation_test.dart` written FIRST on the old code: a table
  of profiles (stored singular carbs, stored plural carbs, missing pack with inputs, nothing,
  PRO keto, PRO low carb, free keto, flag off) -> the literal `macroTargetsProvider` map; green
  before and after the move.
- T2 Home == Nutrition for every row of that table after the change (and a literal for the
  no-stored-targets row that today differs).
- H1 `target_history_writer_to_reader_test.dart`: first reconcile writes one entry; an unchanged
  second does not; a goal change through `ProfileWriteService` writes a second dated today; two
  changes in one day leave one entry; a change back to the previous values removes the same-day
  entry; `targetFor` before / between / after entries; `assumed` flag; fallback profile writes
  nothing; kill switch; the 400 cap; a PRO lapse changes the effective carbs and is recorded at
  the rollover trigger; malformed stored entries skipped.
- H2 each trigger site calls reconcile (behavioural: a `patchProfile` then read; the rollover
  entry point then read; `bumpRestoreCompleted` path then read).
- C1 behavioural (5.3). C3/C4: `grep` proof of no caller + the existing suites.
- Provider: signed-out cases, token count, invalidation on meal log and on a target change.

### 7.2 Widgets
Screen at 360 dp and at text scale 1.3: no overflow with 0 logs, 1 day, 10 days, 400 days;
range and metric chips switch without exception; tapping a heatmap cell and a bar opens the day
sheet with that day's totals; sections below their minimum sample are absent; the entry row on
the Nutrition tab pushes the route; the moved Insights section still expands and shows both
weekly cards with the same labels (source pins in `test/` repointed, never loosened:
`grep -rn "INSIGHTS & TRENDS\|_buildInsightsSection\|WeeklyChartCard" test/` first).

### 7.3 Mutations (rule 21), each applied, counted, reverted
series counts a saved meal; unlogged day counted as zero in the average; 10 % -> 11 %;
protein >= -> >; resolver fallback order swapped; reconcile compares 6 of 7 fields; same-day
replace -> append; `from <=` -> `<`; T1 call removed; T2 call removed; C1 entry removed; top
foods key without the quantity strip; an insight threshold off by one; provider token guard
removed. Per-clause mutants for the compound on-target rule (AND -> OR).

## 8. Order of work (Landing A)

1. T1 preservation test on the old code. Extract the resolver; Home adopts it (C2).
2. C3, C4 deletions; C1.
3. Target history + triggers + tests.
4. Daily series, aggregates, top foods, insights + tests.
5. Provider, moved Insights section, route, screen sections + widget tests.
6. Mutations. Registry (`nutrition_history`, `nutrition_target_history`, resolver readers,
   line-range remap by script), nested CLAUDE.md (nutrition, home, core/services), naming
   glossary, closure ledger, diagnose docs for C1 and C2 (`fix` class; C3/C4 are removals).
7. Whole-project analyze, gate loop, the two provider contract tests, commit, PR,
   `land_pr.sh --ci-only`, B-pass on the diff, fix, land.
8. Device check (founder build): the screen on phone and web with a real account.

## 9. Landing B outline (own revision + x2 review before build; needs the founder's go)

- Migration (number from `scripts/mint_migration.sh`): `ALTER TABLE public.user_profile ADD
  COLUMN IF NOT EXISTS target_history jsonb`; function `public.merge_target_history(p_entries
  jsonb)` SECURITY INVOKER, keyed on `auth.uid()`, merging by `from` (the entry with the greater
  `at_ms` wins), capped at 400, both PUBLIC and role revokes then an `authenticated` grant, as
  migration 123 does for notification preferences. Never a plain column upsert: a device with a
  short history would overwrite a longer cloud one (class e4a1b7, a sparse value written
  wholesale into a jsonb column).
- Client: push through the RPC after a reconcile that wrote and inside the profile sync; restore
  merges cloud entries into the local list by the same rule (`_restoreUserProfile` already
  selects the row); then `reconcile`. Schema snapshot `backups/live_schema_columns.json` and
  `backups/applied_migrations.json` in the same commit as the apply. Rehearsed in the local
  docker image first, never on prod.
- Tier `platform` (`sync_profile.dart`): x2 review, B-pass, and the per-action go.

## 10. Risks

- Scope: ten sections in one landing. Mitigation: every section is a self-hiding widget over the
  same tested series, so a section that fails review can be cut without touching the others;
  the batch is NOT split by me without the founder (he asked for all ten in one go).
- `ProfileWriteService` is on every profile write: `reconcile` is synchronous-cheap (one
  resolver call, one small list compare), wrapped so it can never fail or delay the write
  (called after the put, unawaited, errors recorded).
- Home's fallback numbers change for a profile with no stored targets (5.1): intended (C2).
- Heatmap for a 2-year account: 730 cells painted, not built.
- The registry pins line ranges in `nutrition_provider.dart`, `home_provider.dart`,
  `nutrition_repository.dart`: remapped by script after the deletions.

## 11. Revision 2: changes from review round 1 (this section wins)

R1 **Logged vs counted (finding 1).** Totals stay identical to `totalMacrosForDate` (same
predicate). `logged` is narrower: the day has at least one counted row whose `meal_type` is a
String, or its summed calories are > 0. A `target_override_<date>` row (has `date`, no
`meal_type`, no totals) therefore never makes a day logged. Section 5.4's sentence that those
rows "have no date" is withdrawn. N3 seeds: an `is_saved_meal: true` row WITH a `date`, an
override row WITH a `date`, an `nslot_ledger_<date>` row: totals == reader, `logged == false`.

R2 **Day classes (finding 3).** Each day is one of: `notLogged`; `inProgress` (today, IST);
`partial` (logged, calories < 25 % of that day's target); `complete`. Only `complete` days enter
status (on target / under / over), hit-rates, runs, rolling and weekly averages, patterns and
insights. `partial` and `inProgress` days are drawn (bar in a muted tone, heatmap cell "partial"
with its own legend entry), count toward "days logged", and open the day sheet. Today never
breaks a run. Weekly rows show their sample ("4 days"). Water aggregates: days with
`waterMl > 0`, today excluded from hit-rate. Tests N2b (today), N2c (a 120 kcal snack day),
boundary exactly 25 %.

R3 **Files and layering (findings 6, 16).** Pure and core, next to `effective_macro_targets.dart`
and `water_target_service.dart`:
- `lib/core/utils/nutrition_targets_resolver.dart` (the resolver; it imports
  `recomputeDerivedTargets` from the profile feature, as `nutrition_provider.dart` does today;
  core importing a feature has precedent in `day_rollover_service.dart`);
- `lib/core/services/target_history_service.dart` (`TargetHistoryService`: read, targetFor,
  reconcile).
Blast radius is re-measured on the real paths before the record is written.

R4 **Raw-key pin (finding 2).** `test/contracts/diet_strategy_raw_target_reader_pin_test.dart`
allow-lists by path the files indexing `carb_grams` / `carbs_grams` / `fat_grams` and fails on
a stale allow-list entry. Repoint: add the resolver file; drop `home_provider.dart` and
`nutrition_provider.dart` if (and only if) they no longer index the keys after the move.
`resolveNutritionTargetsForTest` (`nutrition_provider.dart:178`) keeps its name and loses the
`date:` parameter; its callers (`nutrition_target_carb_dualname_test.dart`,
`cut_protein_base_test.dart`, `profile_edit_recompute_consistency_test.dart`,
`weekly_report_target_and_freshness_behavioral_test.dart`) are repointed where they pass it.

R5 **Triggers (findings 4, 5, 6, 7).**
- T1 is one private `_afterPut()` in `ProfileWriteService`, called after EACH of the three
  `put('profile')` (`:68`, `:96`, `:136`), independent of `skipSync`, so the restore's own
  profile write (`sync_profile.dart:917`) reconciles on BOTH restore paths (blocking fresh
  install and background). Not called when `patchProfileWith` writes nothing.
- T2 `_doRolloverWithRef`: real on cold start, at the midnight timer and on a resume AFTER a
  date change (resume is gated on `last_known_date != today`). A same-day PRO lapse with no
  profile write is therefore dated at the next cold start, T4 or T5. Stated limit, tested.
- T3 `reckonAndNotifyAfterRestore` stays (heals a restore whose profile write preceded PRO
  state).
- T4 screen open: `initState` calls `NutritionRepository.instance.reconcileTargetHistory()`
  (repository call, never Hive from the widget), then invalidates the history provider if it
  wrote. No write inside any provider `build`.
- T5 `WaterTargetService.setUserOverride` calls reconcile after its put / delete.
- Guard: `reconcile` returns unless `HiveService` has an open user session AND
  `AuthSessionBootstrapper.liveSessionOwnedBy(uid)` holds for the live Supabase uid (the guard
  the late-answer healer uses); a signed-out or switching session writes nothing.
- The two direct profile writers (onboarding stamp, body-fat healer) change no target and get
  no hook.

R6 **Entry shape (finding 8).** SIX compared value fields: `calories`, `protein`, `carbs`,
`fat`, `water_ml`, `strategy`; plus `from` and `at_ms`. `assumed` is NOT stored: `targetFor`
returns `(entry, assumed: day < firstEntry.from)`. When the 400 cap drops the oldest entry, the
new first entry becomes the assumed anchor for all earlier days (stated, tested). Mutation
"compares 5 of 6" with one H1 case per field.

R7 **Assumed days are labelled (finding 13).** Whenever a shown range contains an assumed day,
the chart and heatmap carry one line: "Days before <date> use your current target." The closure
ledger carries Landing B as `blocked_on_user` (reason: migration go).

R8 **Slots (finding 9).** `breakfast` / `lunch` / `dinner`; every other or missing value
(including `snack`) is `snacks`, as `todays_meals_card.dart` does. Test: slot calories sum to
the day total.

R9 **Header (finding 10).** Everything keys off `fromDay` (the earlier of the onboarding day
and the first counted meal day; a missing stamp = first meal day; no meals = today). Copy:
"TRACKING SINCE 12 AUG" and "Day 106"; never "since you joined" (the stamp can be re-stamped
to today on a restored account, `auth_session_bootstrapper.dart:442-452`).

R10 **Provider freshness (finding 7).** `nutritionHistoryProvider` also watches
`weightHistoryProvider` and `waterIntakeProvider` (`nutrition_provider.dart:577`), so a weight
or water log refreshes an open screen.

R11 **Named test and doc repoints (finding 11).**
`test/contracts/profile_surface_invalidation_test.dart:20-27` (set and lengths 6/5 -> 8/7);
`test/contracts/nutrition_screen_layout_test.dart:46` (`WeeklyChartCard` pin repointed to
`widgets/insights_section.dart`); `test/sync/nutrition_slot_store_readers_test.dart:66`;
`docs/sot_registry.yaml:754,2771`; unused helpers left by C3 (`_formatDate`, the doc comment at
`nutrition_provider.dart:48-55`) removed so the whole-project analyze stays warning-free.
Override greps use `\btarget_override_` so `water_target_override_ml` is not matched.

R12 **Existing aggregators (finding 12).** `NutritionRepository.getDailyMacros` /
`getWeeklyAverages` / `getWeekdayVsWeekendCalories` / `getProteinDeficitStreak`
(`nutrition_repository.dart:164-322`) serve the coach snapshot over a fixed recent window and
keep their semantics; the history aggregates are a separate registered concept
(`nutrition_history`, complete-days-only). Not merged: changing the coach's inputs is outside
this batch's contract and would alter AI prompts (section 4.6 class). The resolver is the one
source for DISPLAYED targets (Nutrition, Home, weekly cards, History, target history);
`ai_snapshot_builder.dart` and `pattern_detector.dart` keep their own reads (they already call
`effectiveMacroTargets`); no behaviour change there.

R13 **Top foods (finding 14).** Key = lower-case, trimmed, inner whitespace collapsed, a
trailing parenthetical and a trailing ` x<n>` removed, trailing plural `s` folded when the
singular also occurs. NO leading-number strip ("7 up", "5 star" stay intact). Per-food kcal and
protein are item-level sums and labelled "from logged items". N5 includes digit-led names.

R14 **Navigation (finding 15).** `context.go('/nutrition/history')`, as the diet-plan child
does; back returns to `/nutrition` (widget test).

R15 **Home adoption details (finding 17).** The adapter keeps the `DietStrategyFlags.enabled`
gating exactly (no PRO or restore-tick watch when the flag is off); Home keeps not exposing
`strategy_index`; `WeeklyNutritionNotifier` keeps calling with strategy off (calories and
protein only). Deliberate changes on Home, both part of C2/C3 and both tested with literals:
(a) an incomplete stored pack now resolves as on Nutrition; (b) the override read is gone.

R16 **Dates (finding 19).** Weekday, weekend and Monday-week maths run on the date KEY parsed
as a calendar date (UTC constructor), never on a device-local `DateTime`.

R17 **Process (finding 18).** Diagnose docs: C1 (weekly cards stale after a target change) and
C2 (Home/Nutrition fallback mismatch), each with its mutation evidence; C3 and C4 are removals
recorded in the closure ledger with grep evidence. Registry: `nutrition_history` (derived: no
`hive:` block, no `reader_manifest_complete`) and `nutrition_target_history` (stored key
`userBox['target_history']`, every reader listed); Gate 9 test names
`test/contracts/nutrition_history_writer_to_reader_test.dart` and
`test/contracts/nutrition_target_history_writer_to_reader_test.dart`; naming glossary rows;
record `docs/plan-reviews/nutrition-history.md`; the two provider contract tests run before the
first push.

R18 **Added tests (finding 20).** Fallback profile then a real profile (first entry appears
only then); restore-shaped `updateProfile(skipSync: true)` writes an entry; owner mismatch
writes nothing; water override change writes an entry dated today; 730-day heatmap paints
without overflow; duplicate `nlog_` + UUID-keyed rows equal the reader; N6 both sides of each
of the five insight thresholds; saved-meal mutant killed by the dated saved-meal seed.

## 12. Revision 3: changes from review round 2 (wins over sections 1-11)

S1 **Resolver imports (finding 1).** R3's import sentence is withdrawn. `_resolveBaseTargets`
(`nutrition_provider.dart:104`) calls `BmrCalculator.calculateTargets` (`:151`), not
`recomputeDerivedTargets`. `lib/core/utils/nutrition_targets_resolver.dart` imports ONLY core
(`bmr_calculator`, `effective_macro_targets`, `diet_strategies`): no feature import under
`lib/core/utils`. `strategyEnabled` and `pro` are parameters; callers supply them.
`TargetHistoryService` (core/services) reads `DietStrategyFlags.enabled` through a function
parameter defaulted by its feature-side caller if that flag class is not in core (checked at
build; core never imports the nutrition feature).

S2 **No target at all (finding 2).** With no history entry (kill switch on, or a profile that
only ever resolved to the fallback), `targetFor` returns null for every day: status is the
neutral `logged`, and the target line, hit-rate, run and target-based insight sections HIDE;
bars, averages, the neutral heatmap, macro split, weight overlay, top foods and the
non-target patterns still show. The `partial` rule then uses a fixed 300 kcal floor. One widget
test with the kill switch on.

S3 **T1 mechanics (finding 3).** `_afterPut()` is called inside the lock right after each
`put`, is synchronous in effect (the history write is not awaited), and has its OWN try/catch
that records `target_history_reconcile` and never rethrows, so it can neither fail the profile
write (the inner catch at `:70` rethrows) nor lengthen the lock. Test: a reconcile that throws
(injected) leaves the profile write succeeded.

S4 **C3 exact list (finding 4).** Removed in one commit: `nutrition_provider.dart` the `date:`
parameter of `_resolveNutritionTargets` and of `resolveNutritionTargetsForTest` (`:178-186`),
its two internal passers (`DailyNutritionNotifier`, `:460` and `:513`), `_applyCalorieOverride`
and the doc at `:48-55`; `nutrition_repository.dart` `getActiveTargetOverride`,
`getDailyCalorieTargetWithOverrides`, `_resolveBaseDailyCalories` (incl. its stored-pack read
at `:540-541`) and any helper left unused; `home_provider.dart:688-695` and its
`nutrition_repository.dart` import if nothing else there uses it. No test passes `date:`
(R4's last sentence is withdrawn).

S5 **Ledger rows (finding 5).** `nslot_ledger_<date>` / `nslot_cursor` / `nslot_meta` are
written by `lib/core/services/sync/nutrition_slot_engine.dart` (`:21-23`); the services
CLAUDE.md row states every whole-box reader is unaffected by them. N3 produces its ledger row
by running the real engine write (or copying its exact shape from that file), never an
invented map.

S6 **Slot case (finding 6).** `meal_type` is lower-cased before bucketing, as
`nutrition_provider.dart:~446` does. Test row `Lunch`.

S7 **C5: weekly cards bucket days wrongly (finding 7; fixed here, not left).**
`WeeklyNutritionNotifier.build` (`nutrition_provider.dart:1821-1838`) sets
`weekStart = now - (weekday - 1) days`, which keeps the current TIME OF DAY, then indexes a row
with `date.difference(weekStart).inDays` (truncating). Read on paper, at 15:00 a Tuesday row
(midnight) is 9 h after `weekStart` and lands on index 0 (Monday), every later day shifts one
left, and LAST Sunday (-9 h, truncated to 0) is also counted as Monday. This is a hypothesis
from reading: a test with a fixed clock is written FIRST against the old code; only if it goes
red is this a bug (then: diagnose doc, bug-history grep, regression test, mutation). Either
way the fix is the same and small: today from `istDateStr`, Monday from the date key, index by
calendar-day difference. If the notifier has no clock seam, a `now` parameter is added to a
pure helper `weekIndexOfDateKey(dateKey, todayKey)` and the test targets the helper plus one
provider case.

S8 **Entry row placement (finding 8).** `SEE FULL HISTORY` sits in the always-visible part of
the Insights card (under the header, outside `if (_isInsightsExpanded)`), so the screen is one
tap away while the section stays collapsed by default.

S9 **God-screen gate (finding 9).** The gate has no per-file ceiling for allow-listed files
(`scripts/check_god_screen_max_lines.dart:42-48`: a plain path allow-list; a stale entry only
warns). `nutrition_screen.dart` shrinks and stays on the list; the gate is run after the move.

S10 **Router (finding 10).** `history` child = builder-only `GoRoute` like `diet-plan`
(`app_router.dart:485-490`), plus the screen import.

S11 **Added H1 rows (findings 11, 12).** Stub profile with inputs, then a restore-shaped
`updateProfile(skipSync: true)` with other targets the same day: ONE entry, restored values.
Strategy flag toggled mid-history: two entries.

S12 **Water rebuild cost (finding 13).** Kept simple: the provider rebuild is one pass over
local rows (the 3,000-row PR pass measured 47 ms in batch 1); a timing test on 730 days x 4
meals asserts < 150 ms on the VPS. If it fails, water moves to its own provider in this batch.

S13 **Diagnose ids (finding 17).** Each new id is grepped in `docs/diagnoses/` before use, and
the commit hook's OK line is checked to name the new doc.

## 13. Revision 4: changes from review round 3 (wins over sections 1-12)

Three rounds kept finding issues in the same two mechanisms (the water field and the ownership
guard), so both are REMOVED rather than patched.

U1 **Water leaves the target history (finding 3).** Entries hold FIVE compared fields:
`calories`, `protein`, `carbs`, `fat`, `strategy` (+ `from`, `at_ms`). The water target follows
raw body weight (35 ml/kg, `water_target_service.dart:35-43`) and would write an entry at
nearly every weigh-in. Water days are judged against the CURRENT water target
(`WaterTargetService.currentTargetMl()`), labelled "vs today's water target". Consequences:
trigger T5 (`setUserOverride`) is dropped, `water_target_service.dart` is not edited, the
mutation becomes "compares 4 of 5". An H1 row: a 0.3 kg weigh-in through
`ProfileWriteService.patchProfileWith` writes NO entry. With calorie targets changing only on
the 2 kg drift band or a goal edit, the 400 cap is unreachable in practice; when it does drop
the oldest entry, the R7 label date moves to the new first entry (tested).

U2 **Guard (finding 1).** R5's `liveSessionOwnedBy` guard is withdrawn (it is
`@visibleForTesting`, and tests have no Supabase user). `reconcile` reads the profile from and
writes the history to the SAME `HiveService.instance.userBox` (a per-owner guarded box), so an
entry can only ever describe the profile sitting beside it. Guard = `HiveUserSession
.currentOwnerFullId != null` (public, `hive_user_session.dart`) inside the function's own
try/catch; a closed session returns false. No Supabase read, no auth file touched; an offline
signed-in user still gets entries. Test: no open session writes nothing and does not throw.

U3 **Flag and PRO source (finding 2).** `TargetHistoryService.reconcile()` takes no
parameters besides an optional `now`: it reads `DietStrategyFlags.enabled`
(`lib/features/nutrition/services/diet_strategy_flags.dart`, which imports only
`hive_service`; `core/services` importing a feature file has precedent at
`day_rollover_service.dart:16-26`) and `SubscriptionService.instance.proStateSnapshot()`, once
per call. S1's "function parameter defaulted by the caller" is withdrawn.

U4 **Resolver surface (finding 6).** `lib/core/utils/nutrition_targets_resolver.dart` exposes
`resolveBaseMacroTargets(profile, {DateTime? now})` (the moved `_resolveBaseTargets`, `now`
feeding the age calculation at today's `nutrition_provider.dart:142`) and
`resolveNutritionTargets(...)` on top. `resolveBaseMacroPack` (`nutrition_provider.dart:93`,
public, callers in `diet_plan_screen.dart`, `diet_strategy_actions.dart`,
`diet_plan_screen_swap.dart`) STAYS in `nutrition_provider.dart` with its name and `MacroPack?`
result, as a thin wrapper over the base step; no diet-plan file is edited.

U5 **C5 arithmetic (finding 4), stated correctly.** `weekStart` keeps the time of day t. A
Monday row (midnight) is -t h -> index 0; a Tuesday row is 24-t h -> truncates to index 0 for
any t > 0; Wednesday -> 1 ... Sunday -> 5; slot 6 stays empty. So Monday and Tuesday merge and
every later day shows one bar early, at any time other than exactly midnight. Last Sunday is
<= -24 h -> index -1, skipped (the earlier claim that it is counted is withdrawn). Fix: pure
`weekIndexOfDateKey(dateKey, todayKey)` in `nutrition_history.dart` (calendar-day difference
from the Monday of `todayKey`, both parsed as UTC calendar dates), the notifier passes
`istDateStr(DateTime.now())`. Test first on the helper AND one provider case that seeds a
Monday and a Tuesday row and expects two different bars (red on the old code at any non-midnight
run time). Diagnose doc, bug-history grep, mutation.

U6 **Registry repoints (finding 5).** Besides `:754` and `:2771`: the `diet_strategy_targets`
entry (`docs/sot_registry.yaml:1930-1938`: methods and ranges for `nutrition_provider.dart` and
`home_provider.dart`, plus the resolver file added as a reader) and the mention at `:11035`.
All ranges remapped by script from old-line content after the last code edit.

U7 **No-target mode and day classes (findings 7, 8, 12).**
- No entry at all: heatmap legend shows only `logged` / `partial` / `not logged`; target line,
  hit-rates, runs and target-based insights hide; `partial` uses the 300 kcal floor.
- Today: no counted meal -> `notLogged` (neutral, never breaks a run); otherwise `inProgress`.
- Complete days only: status, hit-rates, runs, rolling and weekly averages, macro split,
  weekday/weekend, slot shares, training vs rest, calories in the weight overlay, insights.
  ALL logged rows (incl. partial and today): top foods, "days logged", the day sheet.
- A weekly row's "n days" counts complete days.
- `logged` needs `meal_type is String` in any case; lower-casing applies only to bucketing.

U8 **Reconcile atomicity (finding 9).** Read list, compute, `put` with no `await` in between
(the put's future is not awaited either). H1 row: two profile writes back to back leave a
consistent single same-day entry.

U9 **T2 insertion point (finding 10).** In `_doRolloverWithRef`
(`day_rollover_service.dart:206`), right after the new date is stored, in its own try with the
`target_history_reconcile` non-fatal. On a returning user's cold start this runs before the
background restore: a stub profile resolves to the fallback and writes nothing; the restore's
own profile write (T1) then records the real targets.

U10 **Triggers, final list.** T1 (three puts in `ProfileWriteService`), T2 (rollover), T3
(`reckonAndNotifyAfterRestore`), T4 (History screen open through
`NutritionRepository.reconcileTargetHistory()`). Files edited outside the nutrition and home
features: `profile_write_service.dart`, `day_rollover_service.dart`, `app_router.dart`,
`profile_surface_invalidation.dart`; new core files: the resolver and the service.

U11 **Test caller list (round-3 confirmation).** `resolveNutritionTargetsForTest` has three
real callers (`nutrition_target_carb_dualname_test.dart`, `cut_protein_base_test.dart`,
`profile_edit_recompute_consistency_test.dart`); none passes `date:`; they need no edit.

U12 **Explicit withdrawals (round 4).** Withdrawn everywhere above: `water_ml` in the entry
shape (5.2 and R6), the water-override trigger text in 5.2, T5 and the
`water_target_service.dart` edit (R5), the R18 test row "water override change writes an
entry", and R4's fourth caller (`weekly_report_target_and_freshness_behavioral_test.dart` only
mentions the name in comments). Raw-key pin outcome: the resolver file is ADDED;
`nutrition_provider.dart` STAYS (it still indexes `base['carb_grams']`; reason text updated);
`home_provider.dart` is REMOVED (Home adopts the resolver and no longer indexes the keys).
U2's closed-session test uses a closed-session fixture and calls `reconcile` directly. U9
reworded: a cold-start stub profile with weight/height/gender may write a computed same-day
entry, which the restore's profile write (T1) replaces the same day (S11 test).

Review history: round 1 needs-changes (4 P1), round 2 needs-changes (5 P1), round 3
needs-changes (1 P1), round 4 converged (0 P0/P1).
