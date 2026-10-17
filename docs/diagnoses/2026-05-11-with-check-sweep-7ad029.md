---
bug_id: 7ad029
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 35 RLS policies on UPDATE / ALL had USING expressions but no WITH CHECK; meaning a user could UPDATE their own row's user_id to another user's UUID, transferring or poisoning cross-user data.
concept: rls_with_check_completeness
sot_registry_entry: rls_with_check_completeness
writers:
  - { file: supabase/migrations/055_rls_with_check_sweep.sql, method_or_widget: alter_policy_with_check_35x, line: 1 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: every_table_writer_uses_upsert, line: 1 }
hive_key_prefix: "n/a"
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: pg_policies
cloud_columns: [tablename, policyname, qual, with_check]
contract_test_path: "n/a — SQL-only migration verified via MCP query (0 missing post-apply)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["update_policy_null_with_check"]
proposed_fix: Migration 055 runs ALTER POLICY ... WITH CHECK (<same as USING>) on all 35 policies. Two patterns covered - standard auth.uid() = user_id and EXISTS-subquery for nutrition_log_items and template_exercises.
regression_test_planned: []
---
# Audit H-29: 35 RLS policies missing WITH CHECK

## Bug

Postgres UPDATE / ALL policies need WITH CHECK; defaults to TRUE when omitted. Without it, a user can UPDATE their own row's user_id to point at someone else's UUID — cross-user data poisoning.

Audit advisor said 12 tables. Actual prod count: 35 policies across ~33 tables.

## Fix

Migration 055: `ALTER POLICY ... WITH CHECK (<same as USING>)` on all 35. Two patterns:
1. Standard: `WITH CHECK (auth.uid() = user_id)` — 33 policies. Exceptions: users (column is `id`), community_reviews (column is `reviewer_id`).
2. EXISTS-subquery: nutrition_log_items, template_exercises — parent-ownership mirrored to WITH CHECK.

## Verification

Pre: 35 missing. Post: 0 missing.

## Related

- 7ad0c1 (subscriptions RLS, migration 052)
- 7ad035 (SECURITY DEFINER hardening, migration 053)
- 7ad054 (RLS policy cleanup, migration 054)
- Migration 008 (original RLS enablement now retroactively repaired)
