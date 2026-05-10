---
bug_id: a9f3d2
date: 2026-05-12
batch: APK Test #13
status: shipped
symptom: Home today-card showed "BACK DAY A · DONE" (green DONE pill) for Sat May 9, but the calendar-strip's Sat May 9 cell showed only the gold today-border with NO checkmark, while earlier completed days (Mon May 4) correctly showed a checkmark.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/workout_write_service.dart, method: markCompleted, line: 325 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: todayWorkoutProvider, line: 403 }
  - { file: lib/features/home/widgets/weekly_calendar.dart, method_or_widget: WeeklyCalendar._buildIndicator, line: 183 }
hive_key_prefix: "schedule_"
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods: [_syncScheduleCompletions, _syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts, _restoreScheduleCompletions]
cloud_table: scheduled_workouts
cloud_columns: [user_id, scheduled_date, status, completed_at]
contract_test_path: "must add: test/contracts/today_card_vs_calendar_strip_same_source_test.dart"
ist_handling:
  - { file: lib/features/home/widgets/weekly_calendar.dart, line: 38, fn: istMidnight }
provider_invalidations: [todayWorkoutProvider, calendarWeekProvider, currentPlanProvider, streakProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "isToday.*isCompleted.*mutually exclusive", absent: true }
  - { pattern: "if.*isToday.*return.*without.*isCompleted", absent: true }
proposed_fix: In WeeklyCalendar._buildIndicator, add an explicit isToday+isCompleted branch before the bare isToday branch that returns the checkmark icon in AppColors.ok (green, contrasting) color so it is visually distinct from the gold today-border. The color block in build() is unchanged; the isToday and isCompleted signals remain independent visual layers. The golden border signals today; the green check signals completion.
regression_test_planned: ["test/contracts/today_card_vs_calendar_strip_same_source_test.dart"]
---

# Bug a9f3d2 — Today-card vs Calendar-strip Completed-Today Mismatch

## Root Cause

Two readers of `schedule_<date>.status`:

1. **`todayWorkoutProvider`** (home_provider.dart:403) calls
   `WorkoutScheduleService.instance.getScheduleForDate(DateTime.now())` and reads
   `status == 'completed'` → correctly shows the "DONE" pill.

2. **`WeeklyCalendar._buildIndicator`** (weekly_calendar.dart:183) is called with
   `isToday=true, isCompleted=true`. The function checks `isCompleted` BEFORE `isToday`
   (line 196 fires before line 209), so the checkmark icon IS returned for completed-today.
   However, the checkmark uses `color: AppColors.accent` (Campaign Gold #D4B270) — the
   SAME color as the full-gold border applied to today's cell by the parent `build()` block.

   Result: a tiny 10px gold checkmark inside a cell with a prominent 1.5px full-gold border
   on a gold-10%-alpha background (`accentSoft`). The checkmark is present but visually
   indistinguishable from the today-border gold. The founder perceived this as "no checkmark."

   Past completed days (Mon May 4) showed a clear checkmark because their border was
   `AppColors.accent.withValues(alpha: 0.33)` (light gold, 33%), making the full-gold
   check icon clearly visible by contrast.

## Two-Reader Divergence

The symptom is a VISUAL divergence, not a data divergence. Both readers get the same
`status='completed'` from Hive. The today-card's green DONE pill is green (`AppColors.ok`)
and always visible. The calendar-strip's checkmark is gold and blends into the today-gold
cell when `isToday=true`.

## Writer Notes

`WorkoutWriteService.markCompleted` (line 325) writes `completed_at_ms` (milliseconds, int)
NOT `completed_at` (ISO String). The stale-completion guard in `getScheduleForDate` reads
`completed_at` (String) — gets null — bypasses the guard entirely — returns
`status='completed'` correctly. No date-comparison failure.

## Fix

Add an `isToday && isCompleted` branch to `_buildIndicator` (before the bare `isToday`
branch at line 209) that returns `Icon(Icons.check, size: 10, color: AppColors.ok)`. The
green checkmark (`AppColors.ok = #7FB4A2`) is clearly visible against the gold-10% background
and is distinct from the full-gold today-border. The today-border and the checkmark now
serve as INDEPENDENT signals: gold border = today; green check = completed.

## Why isSwapped didn't interfere

`isSwapped` is checked FIRST in `_buildIndicator` (line 193). If `is_swapped=true` were
present in the completed entry, it would show 🔄 instead of ✓. However, `is_swapped` is
typically false for completed workouts (the swap happened before completion; swapping
back sets it to false). The BACK DAY A workout on May 9 was not a swapped day.
