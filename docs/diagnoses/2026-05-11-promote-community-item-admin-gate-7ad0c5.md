---
bug_id: 7ad0c5
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: promote-community-item ran as service-role with verify_jwt only at gateway level - any authenticated user could call POST functions v1 promote-community-item and trigger global writes to food_database and exercise_library. The 10-vote community threshold was the only caller-identity gate.
concept: promote_community_item_admin_gate
sot_registry_entry: promote_community_item_admin_gate
writers:
  - { file: supabase/functions/promote-community-item/index.ts, method_or_widget: serve_handler_admin_gate, line: 1 }
readers: []
hive_key_prefix: "n/a"
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: food_database
cloud_columns: [id, name, source]
contract_test_path: "n/a — Edge Function gate change verified via curl pre + post deploy"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["service_role_call_no_admin_check"]
proposed_fix: promote-community-item v8 adds explicit caller-identity gate. Service-role-key literal match passes (cron / dashboard / MCP). Authenticated JWTs are admin-checked against ADMIN_USER_IDS env var. Everything else returns 403 - including anon JWT which previously bypassed via getUser-returns-null path.
regression_test_planned: []
---
# Audit C-5: promote-community-item admin gate

## Bug

`promote-community-item` was deployed with `verify_jwt: true` AND a comment claiming "admins only". But the handler never validated caller identity. Any authenticated user could trigger global writes to `food_database` / `exercise_library` via service-role privileges inside the function.

## Cause

`verify_jwt: true` at the gateway only validates JWT format/signing. It does NOT verify the caller is admin. The author conflated "JWT-validated" with "admin-only."

## Fix

v8 deployed 2026-05-11 with explicit gate:
1. Service-role key literal match (`token === SUPABASE_SERVICE_ROLE_KEY`) — passes
2. Authenticated admin JWT (`user.id ∈ ADMIN_USER_IDS`) — passes
3. Everything else (anonymous, anon JWT, authenticated non-admin) → 403

### v7 false-pass

First attempt (v7) had a regression: `auth.getUser(anon_key)` returns null user. v7 gate treated null-user as service-role caller and allowed. Curl test caught it: anon JWT → HTTP 200, not 403.

v8 fixes by checking `token === SUPABASE_SERVICE_ROLE_KEY` FIRST literally, then running auth.getUser only for the authenticated path. Null user on that branch is now rejected.

### Hermes-R2 #6 bonus fix

Same v8 deploy fixes unreachable `if (countErr && !list)` log path. `list` is always set via `??` fallback returning `[]` so `!list` was always false. Changed to `if (countErr && list.length === 0)`.

## Verification

```bash
# Anonymous → HTTP 401 (gateway verify_jwt rejects)
# Anon JWT → HTTP 403 "Admin only" (our handler rejects)
# Service-role key → would pass (not tested live; would mutate prod)
```

## Related

- 7ad0c1 (subscriptions RLS, migration 052)
- 7ad035 (SECURITY DEFINER hardening — `auto_approve_community_item` revoked anon EXECUTE)
- CLAUDE.md §11
