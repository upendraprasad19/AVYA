---
bug_id: c8e4a1
date: 2026-05-10
batch: APK Test #14
status: in_progress
symptom: 10 PostgrestException 23503 (scheduled_workouts_template_id_fkey) errors fired in 5 seconds on the founder's account at 2026-05-10 12:45 UTC. Saturday's completed workout never reached cloud and the calendar tick vanished after force-restart.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncScheduledWorkouts, line: 3739 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncWorkoutTemplates, line: 3451 }
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
  - SyncService._syncWorkoutTemplates
restore_methods:
  - SyncService._restoreScheduledWorkouts
cloud_table: scheduled_workouts
cloud_columns:
  - status
  - completed_at
  - scheduled_date
  - template_id
  - week_number
  - day_of_week
contract_test_path: test/contracts/scheduled_workouts_fk_resilience_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_service.dart, line: 530, fn: getScheduleForDate }
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - calendarWeekProvider
  - todayWorkoutProvider
  - currentPlanProvider
telemetry_op_types:
  success:
    - scheduled_workout_fk_recovered
  failure:
    - scheduled_workout_template_orphaned
    - upsert_scheduled_workout
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "_deterministicId\\(rawTemplateId\\)", absent: true }
proposed_fix: |
  Replace v5-hash template_id derivation with name-based lookup against
  cloud workout_templates. Per-call cache (templateNameToCloudId) avoids
  N×SELECT on shared template names. On 23503: re-run
  _syncWorkoutTemplates(userId) once per call, clear cache, retry. On
  second 23503: fall back to template_id: null so status='completed'
  and completed_at still reach cloud (template attribution lost). Both
  outcomes log telemetry op_types for audit. Sequencing fix moves
  _syncWorkoutTemplates OUT of Future.wait in weeklyFullSync and
  syncWorkoutData so it always completes before _syncScheduledWorkouts.
regression_test_planned:
  - test/contracts/scheduled_workouts_fk_resilience_test.dart
  - test/contracts/sync_template_before_schedule_order_test.dart
---

# Bug B.1 — `_syncScheduledWorkouts` FK violation on Saturday push (APK Test #14)

## Symptom

Founder's account user_id `d7a67a37…` accumulated 10 × `upsert_scheduled_workout` PostgrestException 23503 errors in `client_errors` between 2026-05-10 12:45:00 and 12:45:05 UTC. Each carried `scheduled_workouts_template_id_fkey` as the violating constraint. The user's Saturday workout was completed locally (Hive `schedule_2026-05-09.status='completed'` with non-null `completed_at`) but the cloud `scheduled_workouts` row stayed at `status='planned'` — and after force-restart, the cloud-authoritative restore (Bug B.2) overwrote the local 'completed' state.

## Root cause

`_syncScheduledWorkouts` (lib/core/services/sync_service.dart:3739) coerced the raw Hive `tmpl_<ms>` key into a v5 UUID via `_deterministicId(rawTemplateId)` and sent that as `template_id` on the schedule upsert.

But `_syncWorkoutTemplates` (sync_service.dart:3451) deliberately does NOT use `_deterministicId` — it omits `id` from the template upsert payload and relies on cloud's `gen_random_uuid()` default + `onConflict: 'user_id,name'`, then SELECTs the real cloud id by name (lines 3499-3511, since APK Test #12.8 / Bug #4 fix).

Result: every cloud `workout_templates.id` is a `gen_random_uuid()` value, while the schedule push was sending a v5 hash of the local Hive key. The two never matched. Every push that carried a non-null `template_id` slammed into the FK constraint and 23503'd. Templates synced fine, schedules silently failed.

A secondary issue compounded this: in `weeklyFullSync` (line 541-565 pre-fix) and `syncWorkoutData` (line 589-602 pre-fix), `_syncWorkoutTemplates` and `_syncScheduledWorkouts` were both inside the same `Future.wait`. On a cold start where templates hadn't yet reached cloud, the schedule push could race ahead and FK-reference a parent that didn't exist at all (compounding the v5 hash mismatch).

## Fix

Three parts:

1. **Lookup-by-name resolver.** New per-call function `resolveCloudTemplateId(rawHiveTemplateId)` reads the local template's `name` and SELECTs `workout_templates.id WHERE user_id AND name`. Per-call cache (`templateNameToCloudId`) so a week's worth of schedule rows sharing the same template don't N×SELECT.

2. **23503 self-heal.** Wrap the upsert in try/catch. On `error.toString().contains('23503')`:
   - First time this call: re-run `_syncWorkoutTemplates(userId)` (one shot, gated by `templatesResynced` bool), clear cache, re-resolve, retry. Successful retry logs `scheduled_workout_fk_recovered`.
   - Second 23503: upsert with `template_id: null` so `status='completed'` + `completed_at` still reach cloud. Logs `scheduled_workout_template_orphaned`.
   - Other errors rethrow into the existing outer catch.

3. **Sequencing.** Move `_syncWorkoutTemplates` OUT of `Future.wait` in both call sites and run it sequentially before the parallel batch. Templates always finish before schedules start.

## Verification

- Source-grep contract test pins:
  - `templateNameToCloudId` cache identifier present
  - `'23503'` literal present
  - `scheduled_workout_fk_recovered` op_type emitted on successful retry
  - `scheduled_workout_template_orphaned` op_type emitted on null fallback
  - `_deterministicId(rawTemplateId)` (v5 hash) absent
- Sequencing test pins `_syncWorkoutTemplates` await before `Future.wait` containing `_syncScheduledWorkouts` in both `weeklyFullSync` and `syncWorkoutData`.
- After-state cloud check on founder's user_id `d7a67a37…`:
  - On next app launch + Bug B.3 migrator run, `scheduled_workouts.status` for May 9 transitions `planned → completed` with the local `completed_at`.

## Related

- CLAUDE.md §6 rule 22 — discipline doc required.
- CLAUDE.md §15 "Sync fan-out contract" — `_syncScheduledWorkouts` is part of `syncWorkoutData()` fan-out.
- docs/sot_registry.yaml — `workout_completion_status` writers and readers.
- Bug B.2 (`docs/diagnoses/2026-05-10-restore-overwrite-d9b2c5.md`) — paired non-destructive merge.
- Bug B.3 (`docs/diagnoses/2026-05-10-resync-migrator-e3f7a8.md`) — one-shot heal of pre-fix divergence.
