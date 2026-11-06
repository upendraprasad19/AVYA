---
bug_id: d3f9a2
date: 2026-09-14
batch: telegram-admin-bot-task-8-review-fix
status: fixed
blast_radius: account
symptom: |
  Two review findings on the telegram-admin-bot webhook skeleton (task 8,
  commit f216b9cd):
  (1) `update.message?.chat?.id` / `update.message?.text` optional-chained
  from `.message`, not from `update` itself. A POST body of the JSON literal
  `null` parses successfully (`req.json()` resolves to `null` without
  throwing), so the existing JSON-parse try/catch never fires — the next
  line then threw an uncaught TypeError reading `.message` off `null`,
  producing a non-200 response from `serve()`. That is a response shape
  distinguishable from every other branch, which breaks the endpoint's
  silent-200 invariant (an internet-facing admin console that must never
  confirm to a stranger that it does anything at all).
  (2) The lone `/help` behavioral test asserted only `res.status === 200`.
  Every failure branch (wrong token, wrong chat id, unknown command) also
  returns `status: 200` with an empty body, so the test could not
  distinguish a working `/help` route from a silently broken auth check.
concept: edge_function_input_validation
sot_registry_entry: |
  Not applicable — this is null-safety in an Edge Function handler's request
  parsing, not a Hive/Postgres writer-reader contract.
writers:
  - { file: supabase/functions/telegram-admin-bot/index.ts, method_or_widget: "handler — extracts chatId/text from the parsed update body", line: 84 }
readers:
  - { file: supabase/functions/telegram-admin-bot/index.ts, method_or_widget: "handler — chatId==null/!text short-circuit to bare 200", line: 86 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: null
contract_test_path: supabase/functions/telegram-admin-bot/index_test.ts
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — single founder-only allowlisted chat id, no multi-account context.
forbidden_patterns_checked:
  - { pattern: "update.message accessed without optional-chaining update itself", absent: true }
proposed_fix: |
  (1) Change `update.message?.chat?.id` / `update.message?.text` to
  `update?.message?.chat?.id` / `update?.message?.text` so the optional
  chain starts at the root `update`, which can legitimately be `null`.
  Widen the `update` local's type to `... | null` to match.
  (2) Export `routeCommand` and `HELP_TEXT` from index.ts and add a direct
  unit test asserting `routeCommand("help", [], null) === HELP_TEXT` —
  a much stronger assertion than the HTTP-level status-code check, which
  every failure branch also satisfies. Keep the existing HTTP-level /help
  test unchanged (it still has value for the response-shape assertion).
regression_test_planned:
  - supabase/functions/telegram-admin-bot/index_test.ts
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "No Flutter client involved — Telegram is the caller." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive involvement." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data change." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "Fix applied to supabase/functions/telegram-admin-bot/index.ts; deno check passes clean; not yet deployed (deploy is a separate explicit-approval step per CLAUDE.md §4.3)." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Webhook-triggered, not cron-dispatched." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No table read/write in this function's read-only v1." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret handling changed." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Telegram webhook contract unchanged." }
  - { tier: 12, name: "Client → server contract", status: fixed_in_this_batch, evidence: "Silent-200 invariant restored for a null JSON body; routeCommand's /help contract now has a direct assertion." }
impact_analysis: |
  EXPOSURE: an internet-facing admin webhook (verify_jwt=false, protected only
  by an app-level secret-token + chat-id allowlist) returned a non-200 for a
  POST body of literal `null`, which is a response shape distinguishable from
  the endpoint's normal silent-200-for-everything behavior. That is a
  reconnaissance signal — an unauthenticated prober could learn the endpoint
  exists and reacts differently to malformed bodies, which the design's
  Global Constraints explicitly forbid. Not yet deployed to prod (task 8 has
  not shipped an APK-facing surface; this is server-side-only and undeployed
  pending the batch's deploy step), so live exposure window is zero. The
  second finding was a test-coverage gap, not a live behavioral bug: the
  existing /help test would have stayed green even if the auth check had
  been silently broken by e.g. an env-var typo.
  Cost of fix: two optional-chaining operators, two exports (routeCommand,
  HELP_TEXT), two new tests. Mutation-proven: temporarily reverting the
  optional-chaining fix reddened exactly the new null-body regression test
  (1 of 8) with the exact original TypeError
  ("Cannot read properties of null (reading 'message')"), all 7 other tests
  stayed green — confirming the test actually detects this defect and
  nothing else masks it.
---

## Root Cause

`req.json()` resolves the JSON literal `null` to the JS value `null` without
throwing, so a POST body of the four bytes `null` sails past the existing
`try { update = await req.json(); } catch { return 200 }` block. The next
line, `const chatId = update.message?.chat?.id;`, chained `?.` from
`.message` onward but read `.message` directly off `update` — which is
`null` in this case — throwing an uncaught `TypeError`. Deno's `serve()`
turns an uncaught handler exception into a non-200 response, breaking the
"every branch returns a bare 200" invariant this endpoint depends on for
not confirming its own existence to an unauthenticated prober.

Separately, the only behavioral test for the `/help` command
(`handler replies to /help from the authorized founder chat`) asserted only
`res.status === 200` — a value shared by every failure branch (wrong
secret token, wrong chat id, unknown command), so the test could not tell
a working `/help` route apart from a silently broken auth check.

## Fix

`supabase/functions/telegram-admin-bot/index.ts`:
- Widened the `update` local's type to `{...} | null` (line 72).
- Changed `update.message?.chat?.id` → `update?.message?.chat?.id` and
  `update.message?.text` → `update?.message?.text` (lines 84-85), so the
  optional chain starts at the root value that can actually be null.
- Exported `HELP_TEXT` (line 20) and `routeCommand` (line 128) so the
  routing logic can be asserted directly in tests without going through
  the full HTTP handler + network-dependent `sendTelegram` call.

`supabase/functions/telegram-admin-bot/index_test.ts`:
- Added `handler stays a silent 200 for a request body that is the JSON
  literal null` (line 88) — POSTs the literal bytes `null` with a valid
  secret-token header and asserts `status === 200` and an empty body.
- Added `routeCommand('help', ...) returns HELP_TEXT exactly` (line 106) —
  a direct unit test asserting `routeCommand("help", [], null) ===
  HELP_TEXT`, which the HTTP-level status check could not distinguish from
  a silently broken auth path.
- Kept the existing HTTP-level `/help` test unchanged, per the review's
  explicit instruction — it still pins the response-shape contract.

## Verification

- Type check: `deno check --node-modules-dir=none supabase/functions/telegram-admin-bot/index.ts` — clean.
- Tests: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/telegram-admin-bot/index_test.ts` — 8/8 green.
- Mutation proof (rule 21): temporarily reverted the optional-chaining fix
  (`update?.message` → `update.message` in both spots) and re-ran the
  suite — 7 passed, 1 failed, exactly the new null-body regression test,
  with the pre-fix `TypeError: Cannot read properties of null (reading
  'message')` at the exact original line. Restored the fix; suite back to
  8/8 green and type check clean.

## Related Bugs

None identified — first instance of this pattern in this repo's Edge
Functions (grep for `\.message\?\.` optional-chaining off a possibly-null
parsed body found no other occurrence at time of writing).

## Recurrence

None — first instance; found by review round on task 8, not a repeat of a
prior diagnose-doc.
