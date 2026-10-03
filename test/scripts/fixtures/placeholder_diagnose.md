---
bug_id: a3f4c1e2
date: 2026-05-12
batch: APK Test #13
status: investigating
symptom: Calendar strip shows S9 with no checkmark when today-card reads DONE.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/workout_write_service.dart, method: completeWorkout, line: 247 }
readers:
  - { file: lib/features/home/widgets/weekly_calendar.dart, line: 60, source: schedule_<date>.status }
hive_key_prefix: schedule_<YYYY-MM-DD>
hive_key_formula: "schedule_${istDateStr(date)}"
sync_methods: [_syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [user_id, scheduled_date, status, completed_at]
contract_test_path: test/contracts/scheduled_workout_status_contract_test.dart
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, line: 252, fn: istDateStr }
provider_invalidations: [todayWorkoutProvider, calendarWeekProvider]
telemetry_op_types:
  success: [workout_completed]
  failure: [upsert_scheduled_workout]
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: '0xFF00D4FF', absent: true }
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "test/contracts/scheduled_workout_status_contract_test.dart green" }
impact_analysis:
  callers_audited: []
  callers_updated_in_this_batch: []
  callers_unchanged: []
proposed_fix: TBD
regression_test_planned: [test/contracts/calendar_strip_today_card_same_source_test.dart]
---
# proposed_fix is TBD — validator should reject
