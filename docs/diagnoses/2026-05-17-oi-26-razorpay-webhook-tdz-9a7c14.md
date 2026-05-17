---
bug_id: 9a7c14
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase A (P0 payment blockers)
status: shipped
symptom: |
  Razorpay webhook threw `ReferenceError: Cannot access 'supabaseClient'
  before initialization` on every `payment.captured` / `payment.authorized`
  event that wasn't an early-return (HMAC fail / age fail). Razorpay
  retried for 24h with the same TDZ. Users paying with a credit card +
  webhook arrival never had `subscriptions` row written. Combined with
  OI-27 fallback failure, PRO never unlocked.
concept: razorpay_webhook_handler_correctness
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method: serve handler (const supabaseClient declaration), line: 300 }
readers:
  - { file: supabase/functions/razorpay-webhook/index.ts, method: H-19 idempotency pre-SELECT, line: 309 }
  - { file: test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart, method_or_widget: decl-order contract test, line: 1 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns:
  - user_id
  - razorpay_payment_id
  - razorpay_order_id
  - razorpay_signature
  - plan
  - status
  - start_date
  - end_date
contract_test_path: test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — webhook is HMAC-verified from Razorpay, not user-scoped"
forbidden_patterns_checked:
  - { pattern: "first use of supabaseClient before const declaration", absent: true }
  - { pattern: "duplicate const supabaseClient declaration", absent: true }
proposed_fix: |
  Move `const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)`
  from the user-id-validation block (~line 431 pre-fix) to immediately
  before the H-19 idempotency pre-SELECT (~line 300 post-fix). The
  declaration now precedes ALL uses inside the serve handler.

  The original placement was a side-effect of the audit-2026-05-11 H-19
  refactor that hoisted the idempotency pre-SELECT above auto-capture
  but didn't notice supabaseClient still lived below. The fix is a
  one-line move; the test pins handler-relative declaration-before-use
  order using brace-scoped scan.

  Why missed by today's audit: lens L21 (Edge Function semantic
  correctness — TDZ, variable hoisting, async control flow) did not
  exist. OI-14 covered input validation only.

  Why missed by /build-apk gates: none of Gates 1-17 read Edge Function
  source for semantic correctness; they audit RLS policies, migrations,
  Hive contracts, and source-grep client code only. Hermes (external)
  caught this; we cannot rely on external audits alone.
regression_test_planned:
  - test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart
---

# Bug 9a7c14 — razorpay-webhook supabaseClient temporal dead zone

closes-oi: OI-26

## Root cause

The serve handler at `serve(async (req: Request) => {...})` ran top-down.
Inside the handler body:

- Line ~301 (pre-fix): `const { data: idemRow } = await supabaseClient.from("subscriptions")...maybeSingle()` — H-19 idempotency pre-SELECT, added 2026-05-11.
- Line ~431 (pre-fix): `const supabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);` — service-role client declaration.

JS/TS `const` is in the temporal dead zone (TDZ) before its declarator
executes. Line 301 ran first → TDZ → `ReferenceError: Cannot access
'supabaseClient' before initialization`. Razorpay then retried (it
treats 5xx as retryable for 24h), each retry hit the same TDZ.

The H-19 refactor (audit-2026-05-11) moved the idempotency pre-SELECT
above the Razorpay auto-capture call to prevent the "already captured"
race. The author didn't notice supabaseClient was declared below
auto-capture, not above the pre-SELECT.

## Why this matters

Without the fix, `subscriptions` row is never written for any
successful payment (only the early-return rejection paths exit safely).
The verify-payment fallback (called by client polling) would normally
catch this, but OI-27 made the fallback throw 23502 (NOT NULL violation
on `razorpay_signature`). Combined failure: user pays → webhook throws
→ fallback throws → PRO never unlocks.

## Fix

Single-line move: declare `supabaseClient` immediately after the
HMAC + age-check early-return block (now line 300) and before the H-19
comment + SELECT. Old declaration removed.

## Verification

```
$ flutter test test/contracts/razorpay_webhook_supabase_client_decl_order_test.dart
All tests passed! (2 cases)
```

Manual: re-read the serve handler top-to-bottom. The declaration is
now the first appearance of `supabaseClient` after the early-return
boilerplate. Subsequent uses (H-19 SELECT, derivePlanFromAmount,
computeExpectedAmount, insert, redeemPromoCode) all fall after.

## Related

- CLAUDE.md §16 — Razorpay payment flow + H-19 audit-2026-05-11
- `feedback_audit_methodology_lenses.md` — L21 Edge Function semantic correctness (NEW)
- `docs/audit/LENS_REGISTRY.md` — canonical lens registry
- `feedback_audit_verifier_cannot_trust_own_subagent.md` — my first verification subagent labeled this FALSE_ALARM by confusing source order with execution order; I caught it only by re-reading the file with a sharper question
