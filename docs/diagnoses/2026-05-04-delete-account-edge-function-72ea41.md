---
bug_id: 72ea41
date: 2026-05-04
batch: APK Test #11
status: shipped
symptom: No server-side hard-delete path existed for DPDP §17 compliance, so user data could not be fully erased on account deletion request.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers:
  - { file: supabase/functions/delete-account/index.ts, method_or_widget: handler, line: 1 }
readers:
  - { file: supabase/functions/delete-account/index.ts, method_or_widget: handler, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: account_deletion_log
cloud_columns: [deleted_user_id, deleted_at, razorpay_cancel_status]
contract_test_path: "n/a — backfill"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: New delete-account Edge Function with JWT re-validation, Razorpay subscription cancel (must succeed), OneSignal unsub, Storage purge, auth.users delete with CASCADE, audit log write.
regression_test_planned: []
---
# Body

Backfill diagnose-doc for retroactive discipline coverage.

Commit: 72ea417d84849cbbf50cc2061ed5c10d46950e8b
Subject: feat(privacy): delete-account Edge Function with full erasure cascade (Test #11 H1 server)
Files changed: supabase/functions/delete-account/index.ts (370 lines, new)
