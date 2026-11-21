---
bug_id: 8f3d22
date: 2026-05-12
batch: APK Test #15.3
status: in_progress
symptom: |
  `WorkoutScheduleService.assignTemplateToDate` silently returns `void`
  when the target date's schedule entry has `status == 'completed'`.
  The caller in `train_screen._scheduleTemplate` iterates over all
  selected dates and calls the service for each one; completed dates
  are skipped without any feedback — no snackbar, no telemetry, no
  returned rejection. User taps SCHEDULE on a date picker, sees
  "Scheduled for 1 day" toast, but the completed day was silently
  discarded.
concept: scheduled_workouts_mutations
sot_registry_entry: scheduled_workouts_mutations
writers:
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: assignTemplateToDate, line: 1441 }
readers:
  - { file: lib/features/train/screens/train_screen.dart, method_or_widget: _scheduleTemplate, line: 2043 }
  - { file: lib/features/train/screens/template_builder_screen.dart, method_or_widget: _buildScheduleRow, line: 406 }
  - { file: lib/features/ai_coach/services/tool_dispatcher.dart, method_or_widget: _executeScheduleTemplate, line: 1069 }
hive_key_prefix: schedule_
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods:
  - SyncService._syncScheduledWorkouts
restore_methods:
  - SyncService._restoreScheduledWorkouts
cloud_table: scheduled_workouts
cloud_columns:
  - id
  - user_id
  - template_id
  - scheduled_date
  - week_number
  - day_of_week
  - status
  - completed_at
contract_test_path: test/contracts/template_schedule_completed_day_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations:
  - calendarWeekProvider
  - todayWorkoutProvider
  - currentPlanProvider
telemetry_op_types:
  success: []
  failure:
    - template_assign_rejected_completed
cross_account_guard: |
  HiveUserSession-scoped writes: workoutBox is opened per-user via the
  user-scoped session (see lib/core/services/hive_user_session.dart).
  assignTemplateToDate writes only to the current user's namespaced
  schedule_<date> key; no cross-account leakage path exists. Telemetry
  op_type 'template_assign_rejected_completed' carries date + templateId
  payload only — no user_id or PII.
forbidden_patterns_checked:
  - { pattern: "return;  // silent on completed-day", absent: true }
  - { pattern: "Future<void> assignTemplateToDate", absent: true }
proposed_fix: |
  Change `assignTemplateToDate` return type from `Future<void>` to
  `Future<AssignTemplateResult>` (sealed class with `AssignTemplateOk`
  and `AssignTemplateRejected(reason)` variants).

  Replace the silent `return` on line 1455 with:
    `return AssignTemplateRejected(AssignTemplateRejectionReason.alreadyCompleted);`
  plus an `ErrorTelemetry.logEvent('template_assign_rejected_completed')`.

  The final successful write path returns `AssignTemplateOk()`.

  Callers updated:
  - `train_screen._scheduleTemplate`: collects rejections per date,
    shows one "already completed" snackbar after the loop summarising
    which dates were skipped. Does not inflate the "Scheduled for N days"
    count with skipped dates.
  - `template_builder_screen`: only increments `writtenCount` on
    `AssignTemplateOk`; rejected dates don't inflate the count.
  - `tool_dispatcher`: already pre-checks `status == 'completed'` before
    calling; continues to ignore the return value safely.
regression_test_planned:
  - test/contracts/template_schedule_completed_day_test.dart
---

# Bug 4b — assignTemplateToDate silent no-op on completed day

## Symptom

User opens the "Schedule template" bottom sheet on the Train tab, selects
a day that already has `status == 'completed'` (e.g. yesterday's logged
workout), and taps SCHEDULE. The `_scheduleTemplate` loop iterates the
selected dates and calls `WorkoutScheduleService.instance.assignTemplateToDate`
for each. For the completed date, the method hits line 1455 and returns
`void` with no signal. The loop continues. After the loop, the snackbar
fires with "Scheduled '$name' for N days" — but the completed date was
silently dropped.

## Root cause

`assignTemplateToDate` at line 1455 in
`lib/core/services/workout_schedule_service.dart`:

```dart
// Never displace a completed workout — history is sacred.
if (existingMap['status'] == 'completed') return;  // ← SILENT
```

The guard is CORRECT (completed history is sacred — do NOT overwrite).
The silence is the bug. The method signature is `Future<void>`, so there
is no channel to communicate a rejection back to the caller.

`_scheduleTemplate` in `train_screen.dart` (line 2041-2044):

```dart
for (final date in sortedDates) {
  await WorkoutScheduleService.instance.assignTemplateToDate(templateId, date);
}
// ... show "Scheduled for N days" snackbar regardless
```

Callers cannot distinguish "succeeded" from "silently rejected." The
"Scheduled for N days" toast always fires even if all selected dates were
completed and zero assignments were made.

## Fix

### 1. Introduce sealed result type in `workout_schedule_service.dart`

```dart
sealed class AssignTemplateResult {}
class AssignTemplateOk extends AssignTemplateResult {
  const AssignTemplateOk();
}
class AssignTemplateRejected extends AssignTemplateResult {
  const AssignTemplateRejected(this.reason);
  final AssignTemplateRejectionReason reason;
}
enum AssignTemplateRejectionReason {
  alreadyCompleted,
  templateMissing,
}
```

Change the method signature from `Future<void>` to `Future<AssignTemplateResult>`:

```dart
// BEFORE
if (tmpl == null) return;
// ...
if (existingMap['status'] == 'completed') return;
// ... end of method (implicit void return)

// AFTER
if (tmpl == null) return const AssignTemplateRejected(AssignTemplateRejectionReason.templateMissing);
// ...
if (existingMap['status'] == 'completed') {
  unawaited(ErrorTelemetry.logEvent(
    'template_assign_rejected_completed',
    message: 'date=$dateKey',
  ));
  return const AssignTemplateRejected(AssignTemplateRejectionReason.alreadyCompleted);
}
// ... at end of successful write path:
return const AssignTemplateOk();
```

### 2. Update `train_screen._scheduleTemplate`

Collect rejected dates per reason, build summary feedback:

```dart
final List<DateTime> skippedCompleted = [];
for (final date in sortedDates) {
  final result = await WorkoutScheduleService.instance.assignTemplateToDate(templateId, date);
  if (result is AssignTemplateRejected &&
      result.reason == AssignTemplateRejectionReason.alreadyCompleted) {
    skippedCompleted.add(date);
  }
}
// "Scheduled for N days" counts only the non-rejected
final scheduledCount = sortedDates.length - skippedCompleted.length;
```

If `skippedCompleted.isNotEmpty`, show a separate snackbar:
`"${skippedCompleted.length} day(s) already completed — can't reschedule."`

If `scheduledCount == 0` (all skipped), skip the success snackbar entirely.

### 3. Update `template_builder_screen`

Only increment `writtenCount` on `AssignTemplateOk`:

```dart
final result = await scheduleService.assignTemplateToDate(templateId, targetDate);
if (result is AssignTemplateOk) writtenCount++;
```

### 4. `tool_dispatcher` — no change needed

Already pre-checks `status == 'completed'` at line 1057 (`continue`) BEFORE
calling the method. Even after the type change, the dispatcher's `await` on
the method simply discards the return value — this is safe because the
pre-check handles the completed-day case at the dispatcher level.

## Why this matters

Without explicit rejection:
- User cannot tell whether the template was scheduled or not.
- "Scheduled for 1 day" snackbar is a lie when the day was completed.
- Support request: "I scheduled my template but it disappeared."

## Related

- Bug 4a (9e2c1a): restore joins workout_templates to hydrate schedule header — both are in the `assignTemplateToDate` + `_restoreScheduledWorkouts` neighborhood.
- `feedback_no_deferrals.md`: "When brainstorm/audit surfaces multiple bugs, fix all in same batch."
- `AssignTemplateRejectionReason.dateInPast` deferred: the UI calendar already suppresses past dates via the `isPast` visual cue, and `template_builder_screen` guards with `targetDate.isBefore(today)`. No runtime case to handle now.
