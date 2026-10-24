---
bug_id: 7c4e5d
date: 2026-05-17
batch: open-issues OI-05 (post-+27 install observation root-cause closure)
status: fixed
symptom: |
  On APK +27 fresh install, founder observed:
  (a) tapping "VIEW WORKOUT CARD" on Friday May 15's calendar day
      detail did nothing (silent no-op).
  (b) train_screen showed "FRI · HYBRID A · DONE · No exercise data
      logged" — DONE chip implies logged data exists, but the
      expanded view contradicts it.
  Test #16.1 / `daffac` patched the receipt-side null gracefully but
  didn't address WHY the data state ("schedule.completed without
  exlogs") exists or how it should be communicated.
concept: marked_done_without_logging_ux
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/workout_schedule_service.dart, method: markCompleted, line: 851 }
  - { file: lib/core/services/workout_write_service.dart, method: markCompleted, line: 333 }
readers:
  - { file: lib/features/home/widgets/day_detail_sheet.dart, method: _buildCompletedFooter + _hasExerciseLogsForDate, line: 328 }
  - { file: lib/features/train/screens/train_screen.dart, method: _buildExpandedExercises, line: 830 }
hive_key_prefix: "schedule_"
hive_key_formula: "'schedule_${istDateStr(date)}'"
sync_methods: [_syncScheduleCompletions]
restore_methods: [_restoreScheduleCompletions]
cloud_table: workout_schedule_completions
cloud_columns: [user_id, scheduled_date, day_of_week, workout_name, duration_seconds, completed_at, created_at]
contract_test_path: test/contracts/marked_done_vs_logged_ux_test.dart
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, line: 801, fn: istDateStr }
provider_invalidations: [currentPlanProvider, calendarWeekProvider, todayWorkoutProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "workoutBox user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "always render 'COMPLETED' regardless of exlogs", absent: true }
proposed_fix: |
  Day detail sheet `_buildCompletedFooter` and train screen
  `_buildExpandedExercises` now branch on whether canonical exlog
  rows exist for the IST date:

  Has exlogs (genuine logged completion):
    - DONE chip reads "COMPLETED"
    - VIEW WORKOUT CARD button visible
  No exlogs (marked-done-without-logging — used markCompleted directly):
    - DONE chip reads "MARKED DONE"
    - No View Card button; replaced with italic dim hint
      "Marked done outside the app — no exercises were logged."
    - Train screen expanded view reads the same copy

  Cheap probe helper `_hasExerciseLogsForDate()` mirrors the
  `WorkoutReceiptData.fromExerciseLogs` index+grep lookup so the
  probe agrees with the receipt builder by construction.
regression_test_planned:
  - test/contracts/marked_done_vs_logged_ux_test.dart
---
# Body

## Live cloud verification (2026-05-17)

Live query against `dedsavbjuwgarrhphgnl`:

```
SELECT scheduled_date, workout_name, has_exlog_rows, has_workout_log_row
FROM workout_schedule_completions sc
LEFT JOIN ... -- (full join in commit body)
WHERE user_id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b'
ORDER BY scheduled_date;
```

Result (11 rows total):

| date | workout | has_exlog | has_wlog |
|---|---|---|---|
| 2026-05-02 | Back Day A | true | true |
| 2026-05-04 | Leg Day A | true | true |
| 2026-05-05 | Pull A | true | true |
| 2026-05-06 | Push Day | true | true |
| 2026-05-07 | Leg Day A | true | true |
| 2026-05-09 | Back Day A | true | true |
| 2026-05-11 | Leg Day A | true | true |
| 2026-05-12 | Pull A | true | true |
| **2026-05-14** | **Hybrid A** | **false** | **false** |
| **2026-05-15** | **Hybrid A** | **false** | **false** |
| 2026-05-16 | Legs B | true | true |

9 of 11 completions have matching exlog + workout_log rows. The 2
that don't (both "Hybrid A") match the founder's observation surface
exactly. Pattern: user marked Hybrid A as completed via the day card's
quick-tap completion affordance WITHOUT going through active workout
mode. Schedule status flipped → cloud row stamped → fresh install
restored → UI implied logged data exists.

## Root cause

`WorkoutScheduleService.markCompleted` (line 851) and the AI coach
`markWorkoutComplete` tool path (`tool_dispatcher.dart:421`) both
flip `schedule.status = 'completed'` without requiring exlog rows.
This is INTENTIONAL — the founder explicitly wants users to be able
to track "I trained outside the app" days for streak/adherence
purposes. The bug is purely UX clarity downstream.

## Fix

Branch the day-card and train-expanded UX based on
`_hasExerciseLogsForDate(date)`. See `proposed_fix` in frontmatter.
No data-layer changes. No writer-side gating. The "marked done
outside app" UX is now explicit instead of looking like a broken
receipt link.

## Why this matters

Closes OI-05 (`docs/audit/open_issues.md`). Without this fix, every
user who has ever used the quick-tap completion affordance will see
the same misleading UX on fresh install — schedule restored, exlog
empty, UI implies data should exist. This is the third surface of
the writer/reader drift class touched in this session
(`cb1ab1` PR cumulative, `daffac` View Card no-op, `7c4e5d` this).

## Regression test

`test/contracts/marked_done_vs_logged_ux_test.dart` — 4 source-grep
cases pinning the differentiation. Each surface (day_detail_sheet
chip, day_detail_sheet button visibility, probe helper presence,
train_screen copy branch) has its own assertion.
