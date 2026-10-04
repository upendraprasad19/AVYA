---
bug_id: b7f30a
date: 2026-07-20
batch: unit0-workout-logging-fixes
blast_radius: feature
status: fixed
symptom: >
  Tapping START on Home's Today's Workout card dead-ended. The handler was a bare
  `onStart: () => context.go('/train/active-workout')` (home_screen.dart:875) — pure
  navigation with no call to `startWorkout()`. ActiveWorkoutScreen therefore mounted
  with a null `workoutDay` and rendered the empty state "No workout in progress" +
  "GO TO TRAINING". The only two `startWorkout` callsites are readiness_sheet.dart:30
  and :38, both reached via `beginWorkoutWithReadiness` from the TRAIN screen — so the
  workout could only ever be started from Train, never from Home. Found while
  live-testing the free-tier Phase-1 wall on amar.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/features/home/screens/home_screen.dart, line: 875, source: "TodayWorkoutCard onStart — now builds the day + routes through beginWorkoutWithReadiness before navigating" }
  - { file: lib/features/train/providers/train_provider.dart, line: 500, source: "workoutDayForDate — new helper building a WorkoutDayData from THAT date's schedule_* row" }
readers:
  - { file: lib/features/train/widgets/readiness_sheet.dart, line: 26, source: "beginWorkoutWithReadiness — the canonical start path (flag-gated readiness, then startWorkout)" }
  - { file: lib/features/train/providers/train_provider.dart, line: 1067, source: "ActiveWorkoutNotifier.startWorkout — sets state.workoutDay; without it the screen has nothing to render" }
  - { file: lib/features/train/screens/active_workout/screen.dart, line: 154, source: "empty state 'No workout in progress' — what the user hit before the fix" }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_' + istDateStr(date)"
sync_methods: [_syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [user_id, scheduled_date, week_number, day_of_week, status, completed_at]
contract_test_path: test/contracts/session_date_and_home_start_behavioral_test.dart
ist_handling:
  - { file: lib/core/utils/date_utils.dart, line: 26, fn: "formatDateKey — getScheduleForDate keys the row by IST date" }
provider_invalidations: [todayWorkoutProvider, currentPlanProvider, calendarWeekProvider]
telemetry_op_types:
  success: [workout_write_service_upsert_scheduled]
  failure: [workout_write_service_upsert_scheduled]
cross_account_guard: >
  Unchanged — `workoutDayForDate` reads via WorkoutScheduleService.getScheduleForDate,
  which goes through the user-scoped workoutBox (wrapUserScopedBox). No new box access.
forbidden_patterns_checked: >
  Verified `startWorkout` has exactly two callsites (readiness_sheet.dart:30 and :38),
  both behind `beginWorkoutWithReadiness` — so routing Home through the same helper
  keeps ONE canonical start path rather than adding a second. Deliberately did NOT use
  `CurrentPlanData.todayWorkout`: its fallback (train_provider.dart:453-458) can return
  a DIFFERENT (past) day than the card rendered, which would start a workout the user
  did not see. `workoutDayForDate` reads the SAME source Home's card renders from
  (todayWorkoutProvider → getScheduleForDate), so displayed == started. The exercise
  parsing reuses the existing private `_parseExerciseMaps` rather than duplicating it
  on Home (writer/reader drift is this repo's #1 recurring bug class).
proposed_fix: >
  Home's onStart builds today's WorkoutDayData via the new `workoutDayForDate(date)`
  helper — same schedule row the card rendered — then awaits
  `beginWorkoutWithReadiness(context, ref, day)` (the canonical Train path, preserving
  the flag-gated readiness check-in) and only then navigates. Returns early when the
  helper yields null (rest day / empty row / no row), so START is never offered into a
  dead end.
regression_test_planned: >
  test/contracts/session_date_and_home_start_behavioral_test.dart — behavioral: a
  seeded workout row yields a startable day dated to that date; rest row,
  exercise-less row and absent row each yield null. Plus a comment-stripped
  source-grep pinning that Home routes through beginWorkoutWithReadiness +
  workoutDayForDate and that the bare-navigation form does not return (FAILS before
  the fix — demonstrated by reverting the wiring).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean; 9/9 behavioral tests green; revert-demo proved the wiring test catches a regression" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "read-only path — workoutDayForDate reads schedule_<date>; no new writes introduced" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no data written by this fix" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "client-only change" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron surface" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret surface" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "starting a workout is local-only; the cloud contract is exercised later by completeWorkout, unchanged here" }
impact_analysis: >
  Live and pre-existing for every user on every day. Home is the app's default tab and
  its Today's Workout card is the most prominent START affordance, yet it could not
  start anything — the user was bounced to an empty "No workout in progress" screen and
  had to discover that Train's card was the only working entry point. Combined with
  a3c8e2 this was especially damaging on the free-tier Phase-1 wall, where Train's hero
  resolved to a stale day: Home showed the right workout but couldn't start it, while
  Train could start but logged to the wrong date. Blast radius measured (not assumed)
  as `feature` via scripts/blast_radius_from_diff.dart.
---

# Home's START button dead-ended

## Root cause

```dart
onStart: () => context.go('/train/active-workout'),   // home_screen.dart:875
```

Navigation only. `ActiveWorkoutNotifier.startWorkout` was never called, so
`state.workoutDay` stayed null and `ActiveWorkoutScreen` rendered its empty state
(`active_workout/screen.dart:154`). The two real `startWorkout` callsites
(`readiness_sheet.dart:30`, `:38`) are both reached through
`beginWorkoutWithReadiness`, which only the Train surfaces called.

## Fix

```dart
onStart: () async {
  final day = workoutDayForDate(DateTime.now());
  if (day == null) return;
  await beginWorkoutWithReadiness(context, ref, day);
  if (context.mounted) context.go('/train/active-workout');
},
```

Two deliberate choices:

1. **Reuse the canonical path.** `beginWorkoutWithReadiness` keeps the flag-gated
   readiness check-in and remains the single place `startWorkout` is invoked from —
   Home does not get a second, divergent start path.
2. **Build the day from the row Home rendered**, not from
   `CurrentPlanData.todayWorkout`. That getter's fallback can hand back a different
   (past) day than the card displayed, which would start a workout the user never saw.
   `workoutDayForDate` reads `getScheduleForDate(date)` — the same source
   `todayWorkoutProvider` uses — and reuses the existing `_parseExerciseMaps` so the
   exercise parsing cannot drift from the canonical builder.

Null is returned for rest days, exercise-less rows and absent rows, so START never
leads into an empty screen.
