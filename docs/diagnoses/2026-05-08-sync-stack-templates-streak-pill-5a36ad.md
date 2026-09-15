---
bug_id: 5a36ad
date: 2026-05-08
batch: APK Test #12.7
status: shipped
symptom: Sync stack had systemic failures — workout templates were not deduped (UNIQUE constraint added), streak pill showed cached value instead of live calculateCurrentStreak(), completed_at was overwritten to NOW on every sync retry corrupting founder's Tue+Wed logs.
concept: workout_templates
sot_registry_entry: workout_templates
writers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: _syncWorkoutTemplates, line: 1 }
readers:
  - { file: lib/core/services/guarded_box.dart, method_or_widget: GuardedBox, line: 1 }
hive_key_prefix: "tmpl_"
hive_key_formula: "null"
sync_methods: [syncWorkoutData]
restore_methods: [_restoreWorkoutTemplates]
cloud_table: workout_templates
cloud_columns: [user_id, name, exercises, assigned_days]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: [currentPlanProvider, streakProvider]
telemetry_op_types:
  success: []
  failure: [sync_templates, upsert_workout_log]
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Migration 050 adds UNIQUE(user_id, name) to workout_templates; _resolveCompletedAt priority chain (created_at → row fields → IST prefix → telemetry-logged NOW fallback); GuardedBox auto-open at wrapper layer.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 5a36ad802bf744454e455b82d84c0f2326affde6
Subject: feat: APK Test #12.7 — sync stack systemic fix + templates dedup + streak pill UX (1.0.0+14)
Files changed: lib/core/services/guarded_box.dart (+51 lines), lib/core/services/sync_service.dart (+281 lines), lib/features/home/providers/home_provider.dart (+17 lines), supabase/migrations/050_workout_templates_unique_user_name.sql (new), test/safety/guarded_box_auto_open_test.dart (new), test/sync/completed_at_preservation_test.dart (new)
