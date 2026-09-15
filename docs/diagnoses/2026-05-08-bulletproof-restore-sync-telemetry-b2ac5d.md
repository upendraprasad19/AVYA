---
bug_id: b2ac5d
date: 2026-05-08
batch: APK Test #12.8
status: shipped
symptom: Multiple restore failures — _restoreXxx methods keyed Hive by cloud UUID instead of deterministic WriteService key (calendar dup explosion); _restoreUserProfile missed users.full_name so greeting showed USER; _restoreScheduledWorkouts had early-skip closing Mon-only DONE marker; templates upsert caused 23503 FK loops. Telemetry sweep added 22 new op_types.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: restoreFromCloudForUser, line: 1 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: HomeProvider, line: 1 }
hive_key_prefix: "schedule_"
hive_key_formula: "null"
sync_methods: [syncWorkoutData]
restore_methods: [_restoreScheduledWorkouts, _restoreUserProfile, _restoreWorkoutTemplates]
cloud_table: scheduled_workouts
cloud_columns: [scheduled_date, status, workout_name]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [currentPlanProvider, calendarWeekProvider]
telemetry_op_types:
  success: []
  failure: [restore_scheduled_workouts, restore_user_profile, upsert_template]
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: 6 of 16 _restoreXxx methods rekey to deterministic WriteService keys; _restoreUserProfile reads users.full_name; remove early-skip in _restoreScheduledWorkouts; drop id from templates upsert payload.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: b2ac5d10624f33e6f0ec8ad9f55259c392bdbbda
Subject: feat: APK Test #12.8 — bulletproof restore + sync paths + telemetry sweep (1.0.0+15)
Files changed: lib/core/services/guarded_box.dart (+9 lines), lib/core/services/hive_user_session.dart (+21 lines), lib/core/services/subscription_service.dart (+67 lines), lib/core/services/sync_service.dart (+316 lines), lib/features/auth/providers/auth_provider.dart (+34 lines), lib/features/home/providers/home_provider.dart (+17 lines)
