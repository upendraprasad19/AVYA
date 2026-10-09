---
bug_id: 7ad035
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 5 SECURITY DEFINER functions had no search_path config (injection risk); coach_tool_invocations_v view ran as creator bypassing RLS; 9 SECURITY DEFINER functions granted EXECUTE to anon and authenticated allowing PostgREST RPC bypass of Edge Function business rules.
concept: security_definer_hardening
sot_registry_entry: security_definer_hardening
writers:
  - { file: supabase/migrations/053_security_definer_hardening.sql, method_or_widget: alter_set_search_path_plus_recreate_view_plus_revoke_execute, line: 1 }
readers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: rpc_increment_promo_used_count, line: 1 }
  - { file: supabase/functions/redeem-referral/index.ts, method_or_widget: rpc_redeem_referral_atomic, line: 1 }
hive_key_prefix: "n/a"
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: pg_proc
cloud_columns: [proconfig, proacl]
contract_test_path: "n/a — SQL-only migration verified via MCP pre/post queries"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["security_definer_no_search_path", "anon_execute_grant"]
proposed_fix: Migration 053 sets search_path=public on 5 functions; recreates coach_tool_invocations_v WITH (security_invoker=true); revokes EXECUTE on 9 functions from anon and authenticated (service_role retains).
regression_test_planned: []
---
# Audit H-35 + H-36 + H-37: SECURITY DEFINER hardening

## Bug

1. **H-35** — 5 SECURITY DEFINER functions had no SET search_path; search-path injection risk
2. **H-36** — coach_tool_invocations_v view bypassed RLS on ai_coach_interactions
3. **H-37** — 9 SECURITY DEFINER functions had EXECUTE granted to anon + authenticated. Combined with leaked anon JWT (audit C-3), callable from anywhere via PostgREST RPC. Most consequentially `extend_subscription(uuid, days)` — second PRO-grant path beyond C-1.

## Fix

Migration 053:
1. `ALTER FUNCTION ... SET search_path = public` on 5 unprotected functions
2. Drop + recreate `coach_tool_invocations_v WITH (security_invoker=true)`
3. REVOKE EXECUTE on 9 functions FROM anon, authenticated

Codebase audit confirmed zero client-side RPC calls. All callers are Edge Functions using service_role.

## Verification

Pre-migration: 5 functions config='<none>'; 9 functions had anon=X authenticated=X.
Post-migration: all 9 have search_path=public; only service_role retains EXECUTE.

## Related

- 7ad0c1 (subscriptions RLS, migration 052)
- 7ad054 (RLS policy cleanup, migration 054)
- 7ad029 (WITH CHECK sweep, migration 055)
- CLAUDE.md §11
