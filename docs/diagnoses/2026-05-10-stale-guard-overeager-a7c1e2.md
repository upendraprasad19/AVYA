---
bug_id: a7c1e2
date: 2026-05-10
batch: APK Test #14
status: in_progress
symptom: Calendar checkmarks for May 5/6/7 vanished on the founder's account after restore, despite cloud workout_logs and scheduled_workouts.status='completed' being correct for those dates.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: markCompleted, line: 789 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreScheduledWorkouts, line: 3758 }
readers:
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: getScheduleForDate, line: 530 }
  - { file: lib/features/home/widgets/weekly_calendar.dart, method_or_widget: WeeklyCalendar.build, line: 31 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: todayWorkoutProvider, line: 1 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getThisWeekWorkouts, line: 1 }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods:
  - SyncService._syncScheduledWorkouts
restore_methods:
  - SyncService._restoreScheduledWorkouts
cloud_table: scheduled_workouts
cloud_columns:
  - status
  - completed_at
  - scheduled_date
contract_test_path: test/contracts/stale_completion_guard_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_service.dart, line: 553, fn: getScheduleForDate }
  - { file: lib/core/utils/date_utils.dart, line: 1, fn: formatDateKey }
provider_invalidations:
  - calendarWeekProvider
  - todayWorkoutProvider
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "if \\(requestedDateStr != completedDateStr\\)", absent: true }
  - { pattern: "_dateKey\\(completedDate\\.toLocal\\(\\)\\)", absent: true }
proposed_fix: |
  Replace the equality-based stale guard with an impossible-past guard:
  fire only when completedDateStr.compareTo(requestedDateStr) < 0. This
  preserves rejection of clock-skewed/test-data corruption while allowing
  retroactive logs and late-night IST-midnight-crossing completions to
  render correctly.
regression_test_planned:
  - test/contracts/stale_completion_guard_test.dart
---

# Bug A — Stale-completion guard is over-eager (APK Test #14)

## Symptom

Founder's calendar showed no checkmarks for May 5, 6, 7 even though `scheduled_workouts` cloud table held `status='completed'` rows for all three dates. Cloud restore reported success. Hive `schedule_<date>` keys held `status='completed'` after restore. Yet UI rendered them as unmarked.

## Root cause

`WorkoutScheduleService.getScheduleForDate(date)` (lib/core/services/workout_schedule_service.dart:530–568) carried a stale-completion guard that downgraded any `status='completed'` row to `status='planned'` when the IST-date of `completed_at` did not equal the schedule's IST-date. Two legitimate completion patterns hit this guard wrongly:

1. **Retroactive logging.** User logs Tuesday's workout on Sunday night → `completed_at` IST date = Sunday, schedule date = Tuesday → mismatch → guard downgrades.
2. **Late-night IST-midnight crossing.** Cloud `completed_at='2026-05-07T21:19:47Z'` = `2026-05-08 02:49 IST`. Schedule date = `2026-05-07`. Mismatch → guard downgrades.

The guard's premise — "if `completed_at` IST date differs from schedule date, the row is stale" — is wrong. It treats every IST-midnight crossing and every retroactive log as corruption.

The earlier `Bug 5.3` (Test #13) fix removed `.toLocal()` from `_dateKey(completedDate.toLocal())` to fix a *different* timezone double-shift, but did not change the guard's premise. With the double-shift gone, the equality check now fires correctly on the actually-different-IST-dates case described above.

## Fix

Relax the predicate from equality (`!=`) to strict-less-than (`compareTo(...) < 0`). The guard now flags only impossible-past completions — rows whose `completed_at` claims a date *before* the schedule date, which can only occur from clock skew or test-data corruption.

Defensive-copy semantics, single-shift `_dateKey`, and the no-Hive-mutation contract are preserved by `test/contracts/stale_completion_guard_test.dart`.

## Verification

- Source-grep contract test pins:
  - `compareTo(requestedDateStr) < 0` predicate present
  - `if (requestedDateStr != completedDateStr)` predicate absent
  - `_dateKey(completedDate.toLocal())` absent (Test #13 regression guard)
  - Defensive copy via `Map<String, dynamic>.from(...)` present in guard window
  - No `workoutBox.put` inside guard window
- After-state cloud check on founder's user_id `d7a67a37-...`:
  - `scheduled_workouts.status='completed'` for May 5/6/7 unchanged in cloud
  - On next app launch, `getScheduleForDate(May 5)` returns `status='completed'` (was `'planned'` due to guard pre-fix)
  - Calendar will render gold ✓ for those days

## Related

- CLAUDE.md §6 rule 22 — discipline doc required
- CLAUDE.md §15 "Source of Truth Rules" — `getScheduleForDate` is the canonical reader of schedule status
- docs/sot_registry.yaml — `workout_completion_status` writers and readers
