---
bug_id: 7ad0c4
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 8 cron Edge Functions had verify_jwt false at the gateway AND no manual auth check at handler entry. Anyone with the function URL could trigger expensive Gemini fanout, OneSignal pushes, or DB scans across the entire user base.
concept: cron_auth_gate
sot_registry_entry: cron_auth_gate
writers:
  - { file: supabase/functions/protein-gap-alert/index.ts, method_or_widget: serve_handler_cron_auth_gate, line: 1 }
  - { file: supabase/functions/streak-guardian/index.ts, method_or_widget: serve_handler_cron_auth_gate, line: 1 }
  - { file: supabase/functions/plateau-alert/index.ts, method_or_widget: serve_handler_cron_auth_gate, line: 1 }
  - { file: supabase/functions/re-engagement/index.ts, method_or_widget: serve_handler_cron_auth_gate, line: 1 }
  - { file: supabase/functions/pr-detection/index.ts, method_or_widget: serve_handler_cron_auth_gate, line: 1 }
  - { file: supabase/functions/workout-window-closing/index.ts, method_or_widget: serve_handler_cron_auth_gate, line: 1 }
  - { file: supabase/functions/i-see-you-callout/index.ts, method_or_widget: serve_handler_cron_auth_gate, line: 1 }
  - { file: supabase/functions/clean-orphan-media/index.ts, method_or_widget: serve_handler_cron_auth_gate, line: 1 }
readers: []
hive_key_prefix: "n/a"
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: "n/a — Edge Function gate verified per-function via curl"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["unauthenticated_cron_function"]
proposed_fix: Insert a Bearer-token gate immediately after the OPTIONS preflight in each of the 8 cron functions. Accept Bearer == SUPABASE_SERVICE_ROLE_KEY (existing pg_cron path) OR Bearer == CRON_SECRET (rotatable hardening, env-var-gated). If CRON_SECRET is unset, only the service-role-key path works - graceful rollout. Reject all others with 401.
regression_test_planned: []
---
# Audit C-4: 8 cron Edge Functions had no caller authentication

## Bug

Per the Agent 9 verify_jwt matrix, 8 cron Edge Functions had `verify_jwt: false` AND no manual auth check at handler entry. They use `SUPABASE_SERVICE_ROLE_KEY` directly inside for DB writes / Razorpay calls / OneSignal pushes, but the entry path was unauthenticated. Anyone with the function URL could fire them.

Functions: `protein-gap-alert`, `streak-guardian`, `plateau-alert`, `re-engagement`, `pr-detection`, `workout-window-closing`, `i-see-you-callout`, `clean-orphan-media`.

`morning-alert` (verify_jwt: true) and `promote-community-item` (handled via 7ad0c5 admin gate) and `delete-account` (handled via 7ad009 rate limit) use different patterns and were not touched here.

## Fix

Each function now has this block inserted after the OPTIONS preflight, before any business logic:

```ts
const authHeader = req.headers.get("Authorization") ?? "";
const token = authHeader.startsWith("Bearer ")
  ? authHeader.slice("Bearer ".length)
  : "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const cronSecret = Deno.env.get("CRON_SECRET");
const isServiceRole = !!serviceRoleKey && token === serviceRoleKey;
const isCronSecret = !!cronSecret && token === cronSecret;
if (!isServiceRole && !isCronSecret) {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401,
    headers: { "Content-Type": "application/json" },
  });
}
```

This accepts either:
1. **Service-role key** (the existing pg_cron Bearer) — keeps cron working unchanged
2. **CRON_SECRET** env var — rotatable hardening; can replace the service-role-key path once pg_cron is migrated

If `CRON_SECRET` is unset (default at deploy), only the service-role path works — graceful rollout, no breaking change to existing cron.

## Follow-up (user-action U-3)

Set `CRON_SECRET` env var on Supabase Dashboard → Edge Functions → Secrets. Rotate quarterly. Once set, update pg_cron registrations to send `CRON_SECRET` instead of service-role-key, and revoke the service-role-key path here.

## Related

- 7ad0c5 (promote-community-item admin gate) — different pattern, same family
- 7ad009 (delete-account rate limit) — different pattern, same family
- CLAUDE.md §11
