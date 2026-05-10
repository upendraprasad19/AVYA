---
bug_id: 89d079
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: Hard-deleting an auth user CASCADE-deleted community contributions (custom foods, exercises, reviews) that should be retained pseudonymously for community signal.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: supabase/migrations/049_account_deletion_pseudonymize.sql, method_or_widget: migration, line: 1 }
readers:
  - { file: supabase/migrations/049_account_deletion_pseudonymize.sql, method_or_widget: migration, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: account_deletion_log
cloud_columns: [deleted_user_id, deleted_at, razorpay_cancel_status, storage_purge_status]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Migration 049 changes 5 community FKs from CASCADE to SET NULL; adds account_deletion_log table; adds onesignal_player_id column.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 89d0790c210cf6eded339d82e54535bad3b37578
Subject: feat(db): migration 049 — pseudonymize 5 FKs + deletion audit log (Test #11 H1 db)
Files changed: supabase/migrations/049_account_deletion_pseudonymize.sql
