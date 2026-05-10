---
bug_id: 776478
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Streak freezes, notifications inbox, and saved diet plan had no cloud backing, so reinstalling the app silently lost these surfaces for paying users.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: supabase/migrations/048_restore_completeness.sql, method_or_widget: migration, line: 1 }
readers:
  - { file: supabase/migrations/048_restore_completeness.sql, method_or_widget: migration, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: [syncFreezes, syncNotificationsInboxEntry, syncSavedDietPlan]
restore_methods: [_restoreFreezes, _restoreNotificationsInbox, _restoreSavedDietPlan]
cloud_table: saved_diet_plans
cloud_columns: [user_id, plan_json, updated_at]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Migration 047/048 adds streak_freezes columns to user_progress, notifications_inbox table, saved_diet_plans table.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 7764787f8aa5c6c5da4faf226934ac224eaf0dc1
Subject: feat(db): migration 047 — restore completeness schema (Test #11 A)
Files changed: supabase/migrations/048_restore_completeness.sql (110 lines, new — note filename 048 because 047 was pre-existing cron cleanup)
