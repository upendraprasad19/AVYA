---
bug_id: a1b2c3
date: 2026-09-13
batch: telegram-admin-bot-task-7-review-fix
status: fixed
blast_radius: account
symptom: |
  Edge Function `alert-critical-notify` accepts `body?.alert_id` without
  validating it is a number, allowing string or other types to reach the
  Supabase query on a bigint column. A caller sending `alert_id: "not-a-number"`
  would pass the `alertId == null` check and reach the database query, where it
  could fail or behave unpredictably.
concept: edge_function_input_validation
sot_registry_entry: |
  Not applicable — this is input validation in an Edge Function handler, not a
  Hive/Postgres writer-reader contract.
writers:
  - { file: supabase/functions/alert-critical-notify/index.ts, method_or_widget: "handler — validates alert_id is a number before passing to Supabase query", line: 62 }
readers:
  - { file: supabase/functions/alert-critical-notify/index.ts, method_or_widget: ".eq('id', alertId) — the Supabase query that receives the validated alert_id", line: 71 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: null
contract_test_path: supabase/functions/alert-critical-notify/index_test.ts
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — cron-triggered function, no user account context.
forbidden_patterns_checked:
  - { pattern: "alert_id used without type validation", absent: true }
proposed_fix: |
  Add a type check after the null check to ensure alert_id is a number before
  passing to the Supabase query. Return HTTP 400 with error message if type check fails.
regression_test_planned:
  - supabase/functions/alert-critical-notify/index_test.ts
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "Type validation added in handler; test passes (4/4 green in index_test.ts)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive involvement." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data migration." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "Type validation added to alert-critical-notify/index.ts; deno check passes." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Cron job unaffected." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No table." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: "Client → server contract", status: fixed_in_this_batch, evidence: "Handler now validates alert_id type before querying alerts table; API contract enforced." }
impact_analysis: |
  EXPOSURE: the alert-critical-notify Edge Function could accept malformed
  alert_id values (strings, objects, etc.) and pass them to a Supabase query
  on a bigint column, causing unpredictable behavior. Impact is low since the
  function is cron-triggered (not user-facing), and the alert_id comes from a
  trusted internal trigger, but type safety is still important for robustness.
  Cost of fix: one type check and one test. Regression test ensures the
  validation layer stays intact.
---

## Root Cause

The handler checks `if (alertId == null)` but does not validate the type. Since the `alerts.id` column is defined as `bigint` in the schema, a numeric value is required, but the code accepted any truthy value without type validation.

## Fix

Added a type check immediately after the null check (lines 67-71):

```typescript
if (typeof alertId !== "number") {
  await logCronEnd(logId, "failed", { httpStatus: 400, errorSummary: "alert_id must be a number" });
  return clientError("alert_id must be a number", 400);
}
```

## Verification

- Type check passes: `deno check --node-modules-dir=none supabase/functions/alert-critical-notify/index.ts` ✓
- All tests pass: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/alert-critical-notify/index_test.ts` — 4/4 ✓
- Regression test added (index_test.ts lines 43-57): sends `alert_id: "not-a-number"` with proper cron auth and asserts a 400 response with the correct error message.

## Related Bugs

None identified.

## Recurrence

None — this is a straightforward type validation gap found during code review.
