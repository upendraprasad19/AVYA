---
bug_id: f5d8c3
date: 2026-06-08
batch: psych-skill-and-audit-2026-06-07 (Hermes E-pass catch — pre-merge)
status: fixed
blast_radius: catastrophic
symptom: >
  verify-payment failed to BOOT (module-load SyntaxError) — every authenticated
  call returned a gateway 5xx, so the client's payment-verification fallback was
  dead. Cause: the Batch-6 F31/F33 refactor (upsert → pre-SELECT + insert) declared
  `const { data: existingSub, error: preSelectError }` at line ~490, but a
  pre-existing `const { data: existingSub }` (the active-subscription early-return)
  already sat at line ~279 in the SAME serve→try handler scope. Two `const
  existingSub` in one block = "Identifier 'existingSub' has already been declared"
  → the module never parses. It shipped to prod as v14 and the deploy smoke
  MISSED it: verify-payment is verify_jwt=true, so the unauthenticated smoke gets a
  401 from the GATEWAY before the module ever loads — a boot error is invisible to
  an unauthenticated probe.
concept: edge_function_duplicate_const_boot_failure
sot_registry_entry: "n/a — boot-failure of the subscriptions writer; regression guard in audit_2026_06_07_batch6_server_test.dart"
writers:
  - "{ file: supabase/functions/verify-payment/index.ts, line: 493 } — idempotency pre-SELECT now binds `paymentSubRow` (was a duplicate `existingSub`)"
readers:
  - "{ file: supabase/functions/verify-payment/index.ts, line: 279 } — the ORIGINAL `existingSub` (active-sub early-return), untouched"
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: subscriptions
cloud_columns: "n/a — module boot failure, not a schema change"
contract_test_path: test/contracts/audit_2026_06_07_batch6_server_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: "n/a — verify-payment fallback path; Razorpay webhook + retries still grant PRO so no payment lost"
cross_account_guard: n/a
forbidden_patterns_checked: >
  audit_2026_06_07_batch6_server_test.dart now asserts verify-payment has <=1
  `const { data: existingSub` declaration AND contains the distinct `paymentSubRow`
  binding. The deploy now uses an anon-Bearer boot-probe for verify_jwt=true
  functions (an unauth probe is gateway-masked).
proposed_fix: >
  Rename the line-490 binding `existingSub` → `paymentSubRow` (+ its 2 uses); the
  line-279 active-sub `existingSub` is untouched. Redeployed v15 and verified boot
  with an anon-Bearer POST (returns the MODULE's own 401 "Invalid or expired token",
  proving the module loads — not a 503 BOOT_ERROR).
regression_test_planned: test/contracts/audit_2026_06_07_batch6_server_test.dart (Hermes f5d8c3 assertion) — GREEN
touched_layers_checked:
  - "{ layer: edge_function_code, status: fixed_in_this_batch, evidence: distinct binding; source-grep regression assertion green }"
  - "{ layer: edge_function_deploy, status: verified, evidence: verify-payment v15 redeployed; anon-Bearer boot-probe returns module-level 401 (not 503) twice — boot confirmed }"
  - "{ layer: client_server_contract, status: verified, evidence: the F31/F33 redeem-once + canonical-expiry logic is intact (only the binding name changed) }"
impact_analysis: >
  A live payment function was un-bootable in prod (v14). Impact bounded because the
  webhook + Razorpay 24h retry still grant PRO, but the verify-payment fallback was
  dead. Two lessons: (1) a diff-only B-pass cannot see a name collision with code
  200 lines away — the Hermes full-read E-pass (L21 + L36, independently) caught it;
  (2) for verify_jwt=true functions an unauthenticated smoke is gateway-masked and
  does NOT confirm boot — use an anon-Bearer probe (reaches the module).
closes-diagnose: f5d8c3
---

# verify-payment duplicate `const existingSub` → boot failure (Hermes catch)

The Batch-6 F31/F33 upsert→pre-SELECT refactor introduced a second
`const existingSub` in the same handler as the pre-existing active-subscription
check (line 279) → module-load SyntaxError → verify-payment v14 wouldn't boot.

## Why it survived to prod
- 4 per-commit B-pass reviews + my own re-reads worked off the **diff hunk**, which
  doesn't show the line-279 declaration 200 lines up.
- The deploy smoke returned 401 — but for **verify_jwt=true** the gateway 401s an
  unauthenticated request BEFORE loading the module, so a boot error is invisible.

## Fix + verification
- Rename the new binding to `paymentSubRow` (line 493 + its uses at 504/572).
- Redeploy **v15**; boot-verify with `Authorization: Bearer <anon-key>` → the module
  runs and returns its OWN `{"error":"Invalid or expired token"}` 401 (not 503).
- Regression: `audit_2026_06_07_batch6_server_test.dart` asserts a single
  `existingSub` declaration + the `paymentSubRow` binding.
