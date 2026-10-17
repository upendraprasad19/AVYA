---
bug_id: b4e2a9
date: 2026-06-08
batch: regression-prevention-wi1-2026-06-08
status: fixed
blast_radius: platform
symptom: >
  delete-account Edge Function SELECTs subscriptions.razorpay_subscription_id, a
  column that never existed (the app uses one-time Razorpay orders, not recurring
  subscriptions). PostgREST returns 42703; the function treats any subscription
  lookup error as fatal and returns jsonError(502, "razorpay_cancel_failed")
  BEFORE deleting anything. Result: every account-deletion request aborts. The
  account_deletion_log audit table confirms the last successful deletion was
  2026-05-11 (2 rows), none since — a live DPDP section-17 right-to-erasure
  compliance gap. Surfaced 2026-06-08 by the WI-1 server-seam extension of the
  schema-column gate (which previously scanned lib/ only and was blind to Edge
  Functions).
concept: subscription_state
sot_registry_entry: subscription_state
writers:
  - { file: supabase/migrations/088_add_razorpay_subscription_id.sql, line: 6 }
readers:
  - { file: supabase/functions/delete-account/index.ts, line: 210 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [id, user_id, plan, status, start_date, end_date, razorpay_order_id, razorpay_payment_id, razorpay_signature, created_at, razorpay_subscription_id]
contract_test_path: scripts/check_schema_column_refs.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [delete_account_subscription_lookup]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "EF from('subscriptions').select of a column absent from live schema", absent: true }
proposed_fix: >
  Lowest-risk fix to a payment/DPDP-critical function: add the nullable column
  rather than change the code. Migration 088 adds
  subscriptions.razorpay_subscription_id (text, nullable). The deployed function's
  SELECT then resolves, returns NULL for every current one-time-order row, the
  cancel loop skips all NULLs (if (!sub.razorpay_subscription_id) continue), and
  erasure proceeds. No Edge Function code change or redeploy needed. Pre-stages the
  schema for the planned recurring-subscription billing model. Applied to prod
  dedsavbjuwgarrhphgnl 2026-06-08 (founder-authorized).
regression_test_planned:
  - scripts/check_schema_column_refs.dart
touched_layers_checked:
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 088 applied to dedsavbjuwgarrhphgnl; information_schema confirms subscriptions now has razorpay_subscription_id (verified post-apply)" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: verified, evidence: "get_edge_function delete-account v3 ACTIVE confirmed the deployed code SELECTs razorpay_subscription_id byte-for-byte; the additive column fixes it with no code change" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "account_deletion_log: 2 successful deletions, last 2026-05-11, none since — empirical confirmation the path was broken" }
  - { tier: 12, layer: end_to_end_contract, status: verified, evidence: "extended check_schema_column_refs.dart (lib/ + functions/) green post-fix: 751 refs, 0 drift; the gate is the regression guard that fails until the column exists" }
impact_analysis: >
  Platform blast radius — account deletion (a legal DPDP section-17 right) was
  globally broken for ~4 weeks. No data corruption, but a compliance failure: users
  who requested erasure were silently refused with a 502. The migration restores
  the capability. Recommended follow-up when recurring billing launches: make the
  Razorpay-cancel step non-fatal (log-and-continue) so a future Razorpay API hiccup
  can never again permanently block a legally-required erasure. Same client/cloud
  schema-drift class as d7c3f1; both invisible to the lib/-only gate until WI-1.
related_bugs: [e2a4f7, b9f4d2, 9e1d4c, a7c3e1]
recurrence: >
  Same cloud-contract wrong/missing-column class as the 2026-05-30 web-E2E batch
  (e2a4f7 user_profile.full_name, b9f4d2 rank-cron columns, a7c3e1 daily_steps/
  sleep_logs, 9e1d4c coach_interactions). Those were all client-side or caught by
  hand; this one lived in an Edge Function and survived 72 gates + 266 tests for
  ~4 weeks because check_schema_column_refs.dart scanned lib/ only. WI-1 extends it
  to supabase/functions/ — this is the first server-side catch.
---

# delete-account: SELECT of nonexistent subscriptions.razorpay_subscription_id aborts every erasure (DPDP P0)

See frontmatter for the structured diagnosis. Found by the WI-1 server-seam
extension of `scripts/check_schema_column_refs.dart` on its first run. Live-verified
against `information_schema` (column absent) and the deployed function source
(`get_edge_function` v3 contained the buggy SELECT byte-for-byte). The
`account_deletion_log` audit table empirically confirmed the breakage (last success
2026-05-11, none since). Fixed by migration 088 (additive nullable column) —
the lowest-risk change to a payment/DPDP-critical function.
