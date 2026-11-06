---
bug_id: c2e8b4
date: 2026-06-09
batch: apk34-obs-2026-06-09
status: fixed
blast_radius: feature
symptom: >
  APK +34 obs 2 — the Weekly Report ("Weekly Dispatch") "This Week" summary card
  showed "19 Workouts" — an impossible weekly number. The value was the LIFETIME
  total_workouts_done shown under a "This Week" label. The streak in the same
  card read "0w" (weeks), but the value is actually the day streak.
concept: weekly_report_data
sot_registry_entry: weekly_report_data
writers: >
  not_applicable for this fix — no writer change. The displayed values come from
  read paths: WorkoutRepository.getWeeklyWorkoutCounts() (4-week rolling window,
  index 0 = current week) and UserStatsData (profile_provider.dart) which already
  reads the canonical live day-streak via WorkoutRepository.currentStreak().
readers: >
  lib/features/profile/screens/reports_screen.dart _buildWeeklySummary — the
  "Workouts" tile now binds to getWeeklyWorkoutCounts()[0] (this week) instead of
  stats.totalWorkouts (lifetime user_progress.total_workouts_done), and the
  streak tile is labeled 'd' (days) instead of 'w'. The 4-week frequency chart
  (_buildWorkoutFrequency) already used getWeeklyWorkoutCounts()[0] for its
  "This Week" bar — the summary tile was the lone lifetime reader under a weekly label.
hive_key_prefix: not_applicable (reads aggregate workout_logs via getWeeklyWorkoutCounts)
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: user_progress (total_workouts_done was the wrongly-read lifetime field)
cloud_columns: total_workouts_done
contract_test_path: test/contracts/reports_this_week_count_test.dart
ist_handling: >
  not_applicable to the fix. getWeeklyWorkoutCounts already buckets by the IST
  week internally; this change only swaps which aggregate the tile reads.
provider_invalidations:
  - userStatsProvider (already watched by reports_screen via ref.watch)
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (userStatsProvider watches authUserIdTokenProvider)
forbidden_patterns_checked:
  - "The reports 'This Week' summary tile must not bind the Workouts value to the lifetime stats.totalWorkouts, and must not label the day-streak with a 'w' (weeks) suffix. Pinned by test/contracts/reports_this_week_count_test.dart (comment-stripped source-grep)."
proposed_fix: >
  In _buildWeeklySummary, compute thisWeekWorkouts = getWeeklyWorkoutCounts()[0]
  and bind the "Workouts" tile to it (not stats.totalWorkouts). Change the streak
  tile suffix from 'w' to 'd' to match the value's true unit (days) and Home's
  "N DAYS" rendering.
regression_test_planned: >
  test/contracts/reports_this_week_count_test.dart — comment-stripped source-grep:
  reports_screen uses getWeeklyWorkoutCounts + thisWeekWorkouts for the Workouts
  tile (the lifetime binding `'Workouts', '${stats.totalWorkouts}'` is gone) and
  labels the streak 'd' not 'w' (the `'${stats.currentStreak}w'` binding is gone).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "reports_screen _buildWeeklySummary rebound to getWeeklyWorkoutCounts()[0] + streak 'w'->'d'; dart analyze clean; reports_this_week_count_test green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "getWeeklyWorkoutCounts reads workout_logs/schedule rows for the rolling 4 weeks; index 0 is the current IST week, identical to the frequency chart's existing This-Week bar" }
impact_analysis: >
  Feature blast radius — Weekly Report honesty. No data, schema, sync, or auth
  change; a pure reader rebinding from a lifetime counter to the already-trusted
  weekly aggregate, plus a unit-label correction (days). Removes a confusing,
  impossible-looking "19 workouts this week". The data source
  (getWeeklyWorkoutCounts) is unchanged and behaviorally pinned elsewhere.
---

# Weekly Report "This Week" showed the lifetime workout count

## What happened
APK +34 obs 2: the Weekly Report "This Week" card read "19 Workouts" — the
lifetime `total_workouts_done`, mislabeled as a weekly figure. The streak in the
same card showed "0w" though the value is a day streak.

## Root cause
`reports_screen.dart` `_buildWeeklySummary` bound the "Workouts" tile to
`stats.totalWorkouts` (lifetime `user_progress.total_workouts_done`) under a
"This Week" header. The streak tile suffixed the live day-streak with 'w'.

## Fix
Bind the Workouts tile to `getWeeklyWorkoutCounts()[0]` (this week — the same
source the frequency chart already uses) and label the streak 'd' (days).

## Verification
`dart analyze` clean; `reports_this_week_count_test.dart` (this-week binding +
day-streak label).

## See also
- `lib/features/profile/screens/reports_screen.dart` `_buildWorkoutFrequency` (already used the weekly source)
