---
bug_id: a3c8e2
date: 2026-07-20
batch: unit0-workout-logging-fixes
blast_radius: feature
status: fixed
symptom: >
  A completed workout could be written to a PAST date. `completeWorkout` dated the
  whole session from `state.workoutDay?.date` — the plan-day being performed — and
  `CurrentPlanData.todayWorkout`'s fallback ("first non-rest, non-done workout in the
  current week", train_provider.dart:453-456) returns a PAST day whenever today has
  no matching entry. A user opening the app and tapping START on the hero card
  (which legitimately shows their next unfinished workout) therefore logged
  `exlog_<pastDate>_*`, `wlog_<pastDate>`, and marked the PAST `schedule_<pastDate>`
  row completed — while today's row stayed `planned` forever. Found while live-testing
  the free-tier Phase-1 wall on amar.
concept: exercise_logs_read_path
sot_registry_entry: exercise_logs_read_path
writers:
  - { file: lib/features/train/providers/train_provider.dart, line: 1565, source: "completeWorkout — was `state.workoutDay?.date ?? now`; now delegates to the pure resolveSessionDate() clamp" }
  - { file: lib/features/train/providers/train_provider.dart, line: 479, source: "resolveSessionDate — pure helper, extracted so the guard is behaviorally testable without driving completeWorkout's full side-effect chain" }
readers:
  - { file: lib/core/services/workout_write_service.dart, line: 55, source: "logExercise(date:) — exlog_<istDate>_<hash> key + exercise_log_index_<istDate>" }
  - { file: lib/core/services/workout_write_service.dart, line: 408, source: "markCompleted(date:) — schedule_<istDate>.status='completed'; also writes wlog_<istDate>" }
  - { file: lib/features/train/providers/train_provider.dart, line: 1571, source: "dateStr = formatDateKey(workoutDate) — feeds the daily + weekly streak math" }
hive_key_prefix: exlog_
hive_key_formula: "'exlog_' + istDateStr(date) + '_' + uuidv5(exerciseName)[0:8]"
sync_methods: [_syncExerciseLogs, _syncWorkoutLogs, _syncScheduleCompletions]
restore_methods: [_restoreExerciseLogs, _restoreScheduledWorkouts]
cloud_table: workout_log_exercises
cloud_columns: [user_id, workout_log_id, exercise_id, set_number, reps_completed, weight_kg, volume_kg]
contract_test_path: test/contracts/session_date_and_home_start_behavioral_test.dart
ist_handling:
  - { file: lib/features/train/providers/train_provider.dart, line: 1453, fn: "now = nowWall() — switched from raw DateTime.now() so the dev/test clock seam reaches the session date; byte-identical to DateTime.now() in release (ist_date.dart:56-57)" }
  - { file: lib/core/utils/date_utils.dart, line: 26, fn: formatDateKey }
provider_invalidations: [currentPlanProvider, todayWorkoutProvider, calendarWeekProvider, streakProvider, workoutStatsProvider, allExercisePRsProvider, aiInsightProvider]
telemetry_op_types:
  success: [workout_write_service_log_exercise, workout_write_service_mark_completed]
  failure: [workout_write_service_log_exercise, workout_write_service_mark_completed]
cross_account_guard: >
  Unchanged — all writes continue through WorkoutWriteService, which wraps
  wrapUserScopedBox. The fix alters only WHICH DATE is written, never which box.
forbidden_patterns_checked: >
  Verified `completeWorkout` has exactly ONE production caller
  (finish_dialog.dart:163 — a live user finishing a session now), so "today" is
  always the correct session date. Confirmed the year-sim harness is NOT affected:
  simulation_service.dart bypasses this method entirely, calling
  WorkoutWriteService.logExercise (:444) / markCompleted (:452) directly and driving
  dates via setTestClockTo (:242). Confirmed the local `now` was used at exactly one
  site (:1565), so switching it to nowWall() has no other behavioral surface.
proposed_fix: >
  Clamp rather than blanket-replace, so the healthy path is provably unchanged: a
  session is dated by WHEN IT WAS PERFORMED; `scheduledDate` is honoured only when it
  already IS today, otherwise `now`. Extracted as the pure `resolveSessionDate(
  scheduledDate:, now:)` (same pattern as RankService.shouldPromote) so the guard is
  behaviorally testable. `todayWorkout`'s fallback is left intact — it is correct for
  DISPLAY ("your next unfinished workout") — with a warning comment added that its
  `date` must never be treated as the session date.
regression_test_planned: >
  test/contracts/session_date_and_home_start_behavioral_test.dart — 4 cases over
  resolveSessionDate: stale/past scheduled day → today (FAILS before the fix,
  returning 2026-07-14 instead of 2026-07-20 — demonstrated by reverting the clamp);
  scheduled == today → returns the same instance (healthy path byte-identical);
  null → today; future → today.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on both changed files; 9/9 behavioral tests green" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "exlog_/wlog_/schedule_ keys now derive from the clamped date; pinned by the new behavioral test" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema change — same columns, different date value" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "existing back-dated rows in the wild are NOT retro-repaired; forward-only fix (see impact_analysis)" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "client-only change" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron reads the session date directly" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret surface" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "sync fan-out unchanged; the corrected date flows through the same _syncExerciseLogs/_syncWorkoutLogs path" }
impact_analysis: >
  Live and pre-existing for every user on every day — not tied to the free-tier hold
  feature that surfaced it. Any user completing a workout while the hero card showed a
  missed day had the session written to that past date. Because the log date is the
  key for exlog_/wlog_ and the input to the daily+weekly streak, PR rescan,
  ProgressionResolver (suggested weights), e1RM history and adherence, a single
  back-dated session corrupts all of them at once, and today's schedule row stays
  `planned` so the day reads as missed. Forward-only: rows already written to wrong
  dates are NOT repaired by this fix — a repair pass would need to correlate exlog
  rows against wlog completion timestamps and is deliberately not attempted here.
  Blast radius measured (not assumed) as `feature` via scripts/blast_radius_from_diff.dart.
---

# Back-dated workout logs — sessions written to a past date

## Root cause

`completeWorkout` trusted the plan-day being performed as the session date:

```dart
final workoutDate = state.workoutDay?.date ?? now;   // train_provider.dart:1565
```

`state.workoutDay` is whatever was handed to `startWorkout`. The Train hero card
sources it from `CurrentPlanData.todayWorkout`, which first tries today's actual date
and then **falls back** to the first non-rest, non-done day in the current week
(`:453-458`). That fallback is right for *display* — it surfaces the user's next
unfinished workout — but its `date` is in the **past**.

So the chain was: stale day displayed → `startWorkout(staleDay)` → `state.workoutDay.date`
is past → `completeWorkout` writes `exlog_<pastDate>`, `wlog_<pastDate>`, and
`markCompleted(pastDate)`.

## Fix

A session is dated by **when it was performed**. The scheduled date is honoured only
when it already is today:

```dart
final workoutDate = resolveSessionDate(
  scheduledDate: state.workoutDay?.date,
  now: now,
);
```

Clamped rather than unconditionally replaced so the healthy path (scheduled == today)
returns the identical instance and is provably unchanged.

Two supporting changes:
- `now` switched from raw `DateTime.now()` to `nowWall()` so the dev/test clock seam
  reaches it (release-identical). Verified `now` had exactly one use site.
- `todayWorkout` gained a warning comment: its fallback `date` must never be used as a
  session date.

## Why the year-sim is unaffected

The sim never calls `completeWorkout`. It writes through
`WorkoutWriteService.logExercise`/`markCompleted` directly and controls dates with
`setTestClockTo` (`simulation_service.dart:242/444/452`). `completeWorkout` has exactly
one production caller: `finish_dialog.dart:163`.
