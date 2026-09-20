---
bug_id: d9b2c5
date: 2026-05-10
batch: APK Test #14
status: in_progress
symptom: Saturday's locally-completed workout was overwritten back to 'planned' on every cold-start restore, because cloud still held the older 'planned' row (Bug B.1's FK violation prevented push) and `_restoreScheduledWorkouts` was unconditionally cloud-authoritative for status/completed_at.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreScheduledWorkouts, line: 3927 }
readers:
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: getScheduleForDate, line: 530 }
  - { file: lib/features/home/widgets/weekly_calendar.dart, method_or_widget: WeeklyCalendar.build, line: 31 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: todayWorkoutProvider, line: 430 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method_or_widget: _getThisWeekWorkouts, line: 791 }
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
contract_test_path: test/contracts/restore_non_destructive_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_service.dart, line: 530, fn: getScheduleForDate }
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - calendarWeekProvider
  - todayWorkoutProvider
telemetry_op_types:
  success: []
  failure:
    - restore_scheduled_workouts
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "'status': cloudStatus,", absent: true }
proposed_fix: |
  Replace the unconditional cloud-authoritative overlay with a
  timestamp-aware merge:
    • local completed + cloud planned + local has completed_at → keep
      local. Cloud is stale (push must have failed). Bug B.3's migrator
      handles the re-push orthogonally.
    • local completed + cloud completed + both have completed_at →
      take whichever has the LATER completed_at via String.compareTo.
    • otherwise → existing rule (cloud authoritative).
  Preserves the non-status/non-completed_at fields (week_number,
  day_of_week, type, template_id) merged as before.
regression_test_planned:
  - test/contracts/restore_non_destructive_test.dart
---

# Bug B.2 — Cloud-authoritative restore destroys fresh local completions (APK Test #14)

## Symptom

Founder's local Hive `schedule_2026-05-09.status` was `'completed'` with `completed_at` set after Saturday's session. After force-restart, the calendar tick disappeared. Cause: `_restoreScheduledWorkouts` overwrote the local row with cloud's stale `status='planned'` (cloud was stale because Bug B.1's FK violation had prevented the completion push from landing).

## Root cause

`_restoreScheduledWorkouts` (lib/core/services/sync_service.dart:3927) merged each cloud row into Hive with this overlay (pre-fix):

```dart
if (cloudStatus != null && cloudStatus.isNotEmpty)
  'status': cloudStatus,
if (cloudCompletedAt != null && cloudCompletedAt.isNotEmpty)
  'completed_at': cloudCompletedAt,
```

The comment explicitly said "Cloud is authoritative for status/completed_at — don't let a stale local 'planned' override the cloud's 'completed'." That's the right rule for the case described, but the inverse — fresh local 'completed' getting overwritten by stale cloud 'planned' — was unhandled. Any time `_syncScheduledWorkouts` push had failed (Bug B.1), the next restore destroyed the local source of truth.

## Fix

Timestamp-aware merge with three branches:

1. **`local==completed && cloud==planned && local has completed_at`** → keep local. Cloud is stale; Bug B.3's one-shot migrator re-pushes.
2. **`local==completed && cloud==completed && both have completed_at`** → take whichever `completed_at` is `compareTo`-newer.
3. **Otherwise** → existing rule (cloud authoritative).

Other merge fields (`week_number`, `day_of_week`, `type`, `template_id`) preserved unchanged.

## Verification

Source-grep contract test pins:
- `localStatus` read present (merge inspects local before deciding)
- `localCompletedAt.compareTo(cloudCompletedAt)` present (newest-wins)
- Conditional `localStatus == 'completed' && cloudStatus == 'planned'` present
- Forbidden: bare `'status': cloudStatus,` overlay absent (the pre-fix shape)
- Replaced by `'status': mergedStatus` (the conditional result)

After-state on founder's account: after Bug B.1 ships and Bug B.3 migrator runs, future cold-starts find cloud + local in agreement. If a transient push failure recurs, restore now preserves local fresh state instead of destroying it.

## Related

- Bug B.1 (`docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md`) — paired push-side fix.
- Bug B.3 (`docs/diagnoses/2026-05-10-resync-migrator-e3f7a8.md`) — heals existing pre-fix divergence.
- CLAUDE.md §15 "Restore-completeness sync" — non-destructive-restore rule.
