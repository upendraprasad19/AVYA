---
bug_id: f4e1d9
date: 2026-06-01
batch: derive-only-ai-coach-tool-surface
status: fixed
blast_radius: feature
symptom: >
  Completed past-phase weeks in the Train week-selector render every day as a
  generic "Workout" with no exercise count and no way to see what was done — a
  flat read-only list (the "Completed history" sheet). The founder expected them
  to look like the current-week view: the real workout name (Push/Pull/Legs),
  exercise count, and an expandable drop-down showing the exercises actually
  performed. Surfaced live as amar (post year-sim, fresh-build login → restore).
concept: past_week_history_display
sot_registry_entry: exercise_logs_read_path
writers:
  - lib/core/services/workout_write_service.dart logExercise (writes exlog_<date>_<hash> exercise rows)
  - lib/core/services/workout_write_service.dart markCompleted (writes wlog_<date> session row with workout_name)
readers:
  - lib/features/train/widgets/week_selector.dart derivePastDayLog (NEW — name from wlog_<date>, exercises from the canonical reader)
  - lib/core/services/workout_read_service.dart exerciseLogsForIstDate (canonical exlog reader, reused)
hive_key_prefix: schedule_ / wlog_ / exlog_
hive_key_formula: schedule_<istDateStr> ; wlog_<istDateStr> ; exlog_<istDateStr>_<hash(exercise_name)>
sync_methods:
  - sync_workout.dart push wlog_* rows to workout_logs
  - sync_workout.dart push exlog_* rows to workout_log_exercises/workout_logs
restore_methods:
  - sync_workout.dart _restoreWorkoutLogs (recreates wlog_<date> WITH workout_name from cloud)
  - sync_workout.dart _restoreScheduledWorkouts (hydrates schedule workout_name ONLY when template_id is set)
cloud_table: scheduled_workouts (no name col) + workout_logs (has workout_name)
cloud_columns: >
  scheduled_workouts: id, user_id, template_id, scheduled_date, week_number,
  day_of_week, status, completed_at, created_at (NO workout_name, NO exercises);
  workout_logs: id, user_id, scheduled_workout_id, template_id, exercise_id,
  workout_name, logged_at, date, sets_completed, reps_completed, weight_kg,
  duration_seconds, distance_km, rpe, notes, is_pr, created_at.
contract_test_path: test/contracts/past_week_history_derives_from_logs_test.dart
ist_handling: >
  The IST date-string is taken from the schedule key suffix (schedule_<dateStr>),
  which is keyed identically to wlog_<dateStr> + the exlog rows (all via
  istDateStr). No new date math introduced.
provider_invalidations: not_applicable (read-only display path; no mutation occurs in the past-week sheet)
telemetry_op_types: not_applicable (read-only render; no write to instrument)
cross_account_guard: >
  Reads go through HiveService.instance.workoutBox (user-scoped via
  wrapUserScopedBox) and WorkoutReadService.exerciseLogsForIstDate (same
  user-scoped box) — no cross-account exposure introduced.
forbidden_patterns_checked:
  - "Reading schedule_*.workout_name as the SOLE name source — now derives from wlog_<date> first (the schedule row loses the name on restore for plan-gen days)."
  - "Adding a parallel exlog reader — reuses the canonical exerciseLogsForIstDate (no drift)."
proposed_fix: >
  Rewrite the past-day row (_PastDayRow) to DERIVE its content from the logs via a
  new testable helper derivePastDayLog(scheduleKey, fallbackName): name precedence
  = wlog_<date>.workout_name → schedule row name → 'Workout'; exercises from the
  canonical WorkoutReadService.exerciseLogsForIstDate. The row becomes expandable
  (drop-down) showing each logged exercise (name + N sets · weight, PR star). No
  schema/writer/restore change — the data is already restored (wlog carries the
  name, exlog carries the exercises); only the bare schedule row lacked the name.
regression_test_planned: >
  test/contracts/past_week_history_derives_from_logs_test.dart — seeds via the
  canonical writers (logExercise ×2 + markCompleted 'Push Day'), then simulates
  the post-restore drift by overwriting the schedule row with NO workout_name, and
  asserts derivePastDayLog returns name='Push Day' (from wlog, not 'Workout') + 2
  exercises (from exlog). Plus a planned-no-logs fallback case and a
  schedule-name-when-no-wlog case. 3/3 pass.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "week_selector.dart derivePastDayLog + expandable _PastDayRow + _ExerciseLine; flutter analyze week_selector.dart = No issues found; 3/3 behavioral tests pass" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "test seeds exlog_* + wlog_<date> + schedule_<date> via canonical writers and asserts the derived name/exercises; wlog_<date> carries workout_name (workout_write_service.dart:373)" }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "live information_schema on dedsavbjuwgarrhphgnl confirms scheduled_workouts has NO workout_name/exercises column; workout_logs HAS workout_name — the asymmetry the fix works around" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "amar (0f35f3dd) has 27 workout_logs rows with distinct workout_name in {Push, Pull, Legs, Upper} — the names exist in cloud + restore" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "_restoreWorkoutLogs recreates wlog_<date> with workout_name (sync_workout.dart:543); _restoreScheduledWorkouts hydrates schedule name only when template_id set (sync_workout.dart:1615) — confirms why plan-gen past days were name-less" }
impact_analysis: >
  Feature blast radius (Train past-week 'Completed history' sheet). Affects EVERY
  user who reinstalls/restores and views a past plan-generator phase week — the
  completed-week review (the most interesting week to look back on) showed the
  least information. Not a sim artifact: it's the cloud-schema asymmetry
  (scheduled_workouts stores no name) exposed by restore. Client-only fix; no data
  migration, no writer/sync change; the corrective data was already on-device after
  restore. Risk is low — read-only display reusing the canonical exlog reader.
---

# Completed past-phase weeks rendered a generic "Workout" with no detail

## What happened

In the Train week-selector, tapping a completed PAST phase week opens the
"Completed history" sheet (`_PastWeekSheet`). Every day showed the generic label
**"Workout"** with a Completed / Not-completed status — no workout name, no
exercise count, no way to drop down and see what was done. The current week, by
contrast, shows "PUSH · 7 exercises" with an expand affordance.

The founder hit this live as amar (who has a completed Phase I from the
year-simulation) after logging into a fresh build (which triggers a cloud restore).

## Root cause (verified live)

A storage asymmetry exposed by restore:

- **`scheduled_workouts` (cloud) has no `workout_name` and no exercises column** —
  only `template_id`, `week_number`, `day_of_week`, `status`, `completed_at`
  (confirmed against `dedsavbjuwgarrhphgnl`).
- The current week looks rich because it is **regenerated live** by the plan
  generator; the name/exercise count are derived at render time, never stored.
- On restore, `_restoreScheduledWorkouts` hydrates a schedule row's `workout_name`
  **only when `template_id` is set** (custom templates). Plan-generator days have
  `template_id IS NULL` → no hydration → the restored `schedule_<date>` row has an
  empty `workout_name`. `_PastDayRow` read that field → fell back to "Workout".
- The truth IS restored elsewhere: `_restoreWorkoutLogs` recreates `wlog_<date>`
  **with** `workout_name` (amar: Push/Pull/Legs/Upper across 27 `workout_logs`
  rows), and the `exlog_*` rows carry the exercises.

## Fix

`derivePastDayLog(scheduleKey, fallbackName)` (week_selector.dart) derives the
day's name from `wlog_<date>.workout_name` (fallback → schedule name → "Workout")
and the exercises from the canonical `WorkoutReadService.exerciseLogsForIstDate`.
`_PastDayRow` is now an expandable tile (drop-down) listing each logged exercise
(name + "N sets · W kg" + PR star). No schema/writer/restore change.

## Lesson / class

A "history" view that reads a different (poorer) source than the live view will
drift — here the live view regenerates from the plan while history read the bare
restored schedule row. For completed state, **derive from the logs** (the single
source of what actually happened), reusing the canonical reader rather than a
parallel one. Adjacent to this batch's derive-only theme (ADR-0012).

## See also

- `lib/features/train/widgets/week_selector.dart` (`derivePastDayLog`, `_PastDayRow`, `_ExerciseLine`)
- `lib/core/services/workout_read_service.dart` (`exerciseLogsForIstDate`)
- `lib/core/services/sync/sync_workout.dart` (`_restoreWorkoutLogs:514`, `_restoreScheduledWorkouts:1518`)
- `test/contracts/past_week_history_derives_from_logs_test.dart`
