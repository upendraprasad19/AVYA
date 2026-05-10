---
bug_id: ad7664
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Streak freezes, notifications inbox entries, and diet plan were written to Hive but never pushed to cloud, so they were silently lost on reinstall.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: syncFreezes, line: 1 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: StreakFreezeNotifier, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: [syncFreezes, syncNotificationsInboxEntry, syncSavedDietPlan]
restore_methods: []
cloud_table: user_progress
cloud_columns: [streak_freezes_available, streak_freezes_used_dates, streak_freezes_last_refill]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Add syncFreezes(), syncNotificationsInboxEntry(), syncSavedDietPlan() to SyncService; wire from mutation callsites (streak consume, inbox record, diet plan save).
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: ad7664c10f4d2a71f2e5f0bc59eb79b626d098eb
Subject: feat(sync): write restore-completeness surfaces to cloud (Test #11 A push)
Files changed: lib/core/services/sync_service.dart (+96 lines), lib/features/home/providers/home_provider.dart, lib/features/nutrition/screens/diet_plan_screen.dart, lib/features/profile/services/notification_inbox_service.dart, lib/features/train/repositories/workout_repository.dart
