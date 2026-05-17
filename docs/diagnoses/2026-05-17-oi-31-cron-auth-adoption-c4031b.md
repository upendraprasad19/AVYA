---
bug_id: c4031b
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase B (P1 security)
status: shipped
symptom: |
  3 cron-invoked Edge Functions (expiry-reminder, morning-alert,
  rolling-context) created service-role clients without calling
  `isAuthorizedCronCall(req)`. Public POSTs could trigger expensive
  fan-outs: morning-alert AI generation + push to every user;
  rolling-context Gemini summarization across every user with >50
  messages; expiry-reminder push to every PRO user expiring within
  3 days. Both a cost vector AND a DoS vector — one POST drains
  shared quotas.

  OI-21 closure earlier today wired logCronStart / logCronEnd
  TELEMETRY into 14 cron functions. AUTH adoption is a SEPARATE
  gate — Hermes's grep + my live verification surfaced the gap.
concept: cron_edge_function_auth_gate
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: supabase/functions/expiry-reminder/index.ts, method: serve handler auth gate, line: 38 }
  - { file: supabase/functions/morning-alert/index.ts, method: serve handler auth gate, line: 580 }
  - { file: supabase/functions/rolling-context/index.ts, method: serve handler auth gate, line: 98 }
readers:
  - { file: supabase/functions/_shared/cron_auth.ts, method_or_widget: isAuthorizedCronCall helper, line: 1 }
  - { file: test/contracts/cron_auth_adoption_test.dart, method_or_widget: 14-function adoption contract, line: 1 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/cron_auth_adoption_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "isAuthorizedCronCall verifies JWT signature + role=service_role"
forbidden_patterns_checked:
  - { pattern: "cron-invoked Edge Function without isAuthorizedCronCall", absent: true }
  - { pattern: "service-role createClient before auth gate", absent: true }
proposed_fix: |
  Added `import { isAuthorizedCronCall } from '../_shared/cron_auth.ts';`
  to each function's import block. Inserted the canonical gate right
  after CORS handling, BEFORE `createClient(SUPABASE_SERVICE_ROLE_KEY)`:

  ```typescript
  if (!await isAuthorizedCronCall(req)) {
    console.warn(`[cron-auth-gate] <fn> unauthorized; status=401`);
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  ```

  Mirrors clean-orphan-media's canonical pattern (wired in OI-15 batch
  2026-05-17).

  Deploys: expiry-reminder v13 → v14, morning-alert v24 → v25,
  rolling-context v13 → v14. All HTTP 201, verify_jwt: false (cron
  uses service-role JWT + the new gate, not the gateway's verify_jwt).

  Scope decision: limited to currently-active cron-invoked functions
  (live `cron.job` query). The 6 additional service-role functions
  Hermes's subagent flagged (compute-coach-signals, weekly-recalc,
  weekly-report, daily-snapshot, beat-my-coach, future-prediction)
  are NOT in the active cron schedule:
  - compute-coach-signals: cron uses Postgres RPC directly, Edge Function dead code
  - weekly-recalc / weekly-report / daily-snapshot: verify_jwt=true,
    accept caller JWTs (any authenticated user can trigger — separate
    smaller risk tracked as follow-up OI)
  - beat-my-coach / future-prediction: verify_jwt=true, client-callable
    with their own per-function JWT validation

  admin-verify-payment + admin-wipe-storage are 410 Gone stubs — no
  privileged code path.

  Why missed by today's audit: OI-21 charter was "cron telemetry"; auth
  adoption was conflated. Memory `feedback_audit_methodology_lenses.md`
  Round 3 splits L4 into L4a (auth) + L4b (telemetry) so the next
  audit catches them separately.
regression_test_planned:
  - test/contracts/cron_auth_adoption_test.dart
---

# Bug c4031b — 3 cron Edge Functions lacked auth gate

closes-oi: OI-31

## Root cause

OI-15 (Test #16.1 batch) created `_shared/cron_telemetry.ts` and wired
`logCronStart` / `logCronEnd` into 4 cron functions. OI-21 (2026-05-17
morning) extended telemetry to 10 more — covering 14 of 14 active
cron-invoked Edge Functions for OBSERVABILITY.

Authentication (`isAuthorizedCronCall`) is a separate concern, wired
into only 11 of the 14 cron functions. The 3 holdouts —
expiry-reminder, morning-alert, rolling-context — predated the
audit-2026-05-16 E.14.C pattern that made `isAuthorizedCronCall` the
canonical shape. Each had its own (or no) inline JWT check.

## Threat model

For each of the 3 functions, the cost of a public unauth POST:

| Function | Cost | DoS surface |
|---|---|---|
| expiry-reminder | OneSignal push to every PRO user expiring within 3 days | Push fatigue + OneSignal quota burn |
| morning-alert | Gemini call PER user + OneSignal push to every user in the 15-minute IST quarter | Gemini cost + push fatigue + AI quota burn |
| rolling-context | Gemini summarization PER user with >50 messages | Gemini cost (worst — per-user summary, scales with user count) |

Worst case: an attacker who knows the public URL can hit any of these
unauthenticated, scale with our user count, and drain shared quotas
(Gemini + OneSignal). The functions return 200 with the work done.

## Fix

Three identical-shape edits — import + early gate. Mirrors the
canonical pattern from clean-orphan-media (lines 25-31).

The gate uses JWT signature + role verification (NOT env-equality —
that's the audit-2026-05-16 E.14.C / Test #16 P1-D drift class that
silently breaks on env rotation).

## Verification

```
$ flutter test test/contracts/cron_auth_adoption_test.dart
All tests passed! (29 cases — 1 helper exists + 14 functions × 2 assertions each)
```

Live: 3 deploys returned HTTP 201. Post-deploy SQL:

```sql
SELECT jobid, fn_slug, succeeded_30m, failed_30m
FROM cron.job_run_summary
WHERE fn_slug IN ('expiry-reminder', 'morning-alert', 'rolling-context');
```

shows the functions still succeed when invoked by pg_cron with the
service-role JWT. Manual unauth POST returns 401 as expected.

## Related

- OI-15 (cron_telemetry helper, 2026-05-17 morning)
- OI-21 (telemetry adoption sweep, 2026-05-17 morning)
- OI-11 (Vault drift, 2026-05-17 morning)
- audit-2026-05-16 E.14.C (env-equality JWT compare deprecation)
- `docs/audit/LENS_REGISTRY.md` — L4 (now split: L4a auth + L4b telemetry)
- Memory `feedback_audit_methodology_lenses.md` Round 3
