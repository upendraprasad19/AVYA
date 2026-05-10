---
bug_id: d4e9c1
date: 2026-05-12
batch: APK Test #13 (process-discipline-batch)
status: shipped
symptom: |
  Founder logged Saturday May 9 BACK DAY A. Cloud confirmed
  scheduled_workouts row has status='completed'. After logout → login on
  Sunday May 10, the calendar strip showed S9 with NO checkmark. Saturday's
  completion had vanished despite cloud still holding the completed row.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: markCompleted, line: 782 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: _restoreScheduledWorkouts, line: 3756 }
readers:
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: getScheduleForDate, line: 530 }
  - { file: lib/features/home/widgets/weekly_calendar.dart, method_or_widget: WeeklyCalendar.build, line: 61 }
hive_key_prefix: "schedule_"
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods: [_syncScheduleCompletions, _syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts, _restoreWorkoutPlan, _restoreScheduleCompletions]
cloud_table: scheduled_workouts
cloud_columns: [user_id, scheduled_date, status, completed_at, week_number]
contract_test_path: test/contracts/logout_login_round_trip_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_service.dart, line: 544, fn: getScheduleForDate, issue: "completedDate.toLocal() passed to _dateKey → double-shift: UTC parse → .toLocal() (already IST on IST device) → istDateStr() shifts +5:30 again → next-day date" }
provider_invalidations: [currentPlanProvider, calendarWeekProvider, todayWorkoutProvider, streakProvider]
telemetry_op_types:
  success: []
  failure: [restore_scheduled_workouts]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "workoutBox.put.*schedule.*status.*planned", present: false }
proposed_fix: |
  Remove `.toLocal()` from line 544 of workout_schedule_service.dart.
  `_dateKey(completedDate)` instead of `_dateKey(completedDate.toLocal())`.
  `istDateStr` already handles UTC inputs correctly (calls `.toUtc().add(+5:30)`).
  Calling `.toLocal()` first converts UTC→IST-local, then `istDateStr` shifts +5:30
  again → date is next day at the IST midnight boundary → stale-guard always fires
  for completions restored from cloud (which arrive as UTC-offset strings from Postgres).
regression_test_planned:
  - test/contracts/logout_login_round_trip_test.dart
---
# Diagnosis body

## Symptom

Founder (IST) logged Saturday May 9 BACK DAY A at approximately 18:00–21:00 IST.
Cloud `scheduled_workouts` table confirmed: `status='completed'`, `completed_at` populated.

After logout → login on Sunday May 10 morning, Saturday's calendar cell showed
no checkmark. Restoring screen completed without error. Cloud still has the row.

## Writer path

`WorkoutScheduleService.markCompleted` (line 782) writes:
```dart
map['completed_at'] = DateTime.now().toLocal().toIso8601String();
```

This produces a **local-time ISO string** (e.g. `"2026-05-09T21:00:00.000"`).
`_syncScheduledWorkouts` pushes it to Postgres `scheduled_workouts.completed_at`
(a `TIMESTAMPTZ` column). Postgres stores it as UTC internally, and when
Supabase/PostgREST returns the row it serialises as UTC offset string e.g.
`"2026-05-09T15:30:00+00:00"`.

## Restore path

`_restoreScheduledWorkouts` (line 3756) fetches the row and writes:
```dart
if (cloudCompletedAt != null && cloudCompletedAt.isNotEmpty)
  'completed_at': cloudCompletedAt,
```

So Hive `schedule_2026-05-09['completed_at']` now holds the UTC-offset string
`"2026-05-09T15:30:00+00:00"`.

`_restoreScheduledWorkouts` also writes `status='completed'`. ✅

## Reader path — stale-completion guard (the bug)

`WorkoutScheduleService.getScheduleForDate` (line 538) has a guard to prevent
"stale" completions from showing checkmarks on the wrong date:

```dart
if (map['status'] == 'completed') {
  final completedAt = map['completed_at'] as String?;
  if (completedAt != null) {
    final completedDate = DateTime.tryParse(completedAt);           // UTC DateTime
    if (completedDate != null) {
      final requestedDateStr = _dateKey(date);                      // "2026-05-09"
      final completedDateStr = _dateKey(completedDate.toLocal());   // BUG
      if (requestedDateStr != completedDateStr) {
        // Returns 'planned' ← fires wrongly for cloud-restored completions
      }
    }
  }
}
```

**The double-shift**:
1. `completedDate = DateTime.tryParse("2026-05-09T15:30:00+00:00")` → UTC DateTime `2026-05-09 15:30 UTC`
2. `.toLocal()` → IST local DateTime `2026-05-09 21:00:00` (isUtc=false, but IST wall-clock)
3. `_dateKey(localIst)` = `istDateStr(localIst)` = `istDateOf(localIst)` = `localIst.toUtc().add(+5:30)`
   = `(2026-05-09T21:00:00 → UTC: 2026-05-09T15:30:00) + 5:30` = `2026-05-10T21:00:00`
4. Extracts date = **`2026-05-10`** ← WRONG (should be `2026-05-09`)

`requestedDateStr ("2026-05-09") != completedDateStr ("2026-05-10")` → guard fires → returns `status='planned'`.

Calendar reads `status == 'planned'` → no checkmark. Bug confirmed.

## Why it worked on-device (no logout)

When the workout is completed on-device, `markCompleted` writes:
```dart
map['completed_at'] = DateTime.now().toLocal().toIso8601String();
```
This produces `"2026-05-09T21:00:00.000"` — a **local-time string with NO timezone suffix**.
`DateTime.tryParse("2026-05-09T21:00:00.000")` → local DateTime with `isUtc=false`.
`.toLocal()` is a no-op on a local DateTime.
`_dateKey(localIst)` still double-shifts, BUT: local-time string has no UTC offset,
so `.toUtc()` inside `istDateOf` adds the device's local offset (which is IST), giving:
`2026-05-09T21:00:00 local → UTC: 2026-05-09T15:30:00 → +5:30 → 2026-05-09T21:00:00`
Date = `"2026-05-09"` ✅ matches `requestedDateStr`. Guard doesn't fire. All good.

**The double-shift only manifests when `completedAt` is a UTC-offset string (from Postgres),
which only happens after a cloud restore.**

## Fix

Remove `.toLocal()` at line 544. Pass the parsed `completedDate` directly to `_dateKey`:

```dart
final completedDateStr = _dateKey(completedDate);  // was: _dateKey(completedDate.toLocal())
```

`istDateStr` accepts any DateTime (UTC or local) and converts via `.toUtc().add(+5:30)`.
A UTC DateTime passed directly gives the correct IST date without double-shifting.

## Hypotheses ruled out

- **H1 (APK 12.9 merge guard)**: the merge guard in `_restoreWorkoutPlan` is correct —
  it checks `existingMap['status'] == 'completed'` BEFORE overlaying. Not the issue.
- **H2 (logout race)**: `clearAllData()` clears `workoutBox` fully (line 247). After
  sign-in, `HiveUserSession.openForUser` opens fresh boxes. Restore runs correctly.
  Not the issue.
- **H4 (day-of-week mapping)**: The key written is `schedule_<scheduled_date>` where
  `scheduled_date` is the DATE string from the cloud row, not computed from day_of_week.
  Not the issue.
- **H3 (status vs completed_at semantic drift)**: Closest to the truth. The calendar
  reads `status == 'completed'` correctly, but the stale-guard DOWNGRADE of status='planned'
  prevents the calendar from ever seeing `status='completed'` after a cloud restore.
