---
bug_id: b3e052
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase A (P0 payment blockers)
status: shipped
symptom: |
  verify-payment Edge Function inserted/upserted `subscriptions` rows
  without the `razorpay_signature` column. Since migration 052
  (2026-05-13) that column is NOT NULL. Every fallback path (when
  webhook is slow or fails) threw Postgres 23502
  `not_null_violation`. Combined with OI-26 webhook TDZ, a paying user
  could never have PRO unlocked: webhook threw TDZ, fallback threw
  NOT NULL violation, subscription row never created.
concept: verify_payment_payload_completeness
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: supabase/functions/verify-payment/index.ts, method: razorpaySignatureSentinel declaration, line: 434 }
  - { file: supabase/functions/verify-payment/index.ts, method: subscription upsert (primary) razorpay_signature use, line: 448 }
  - { file: supabase/functions/verify-payment/index.ts, method: subscription insert (fallback) razorpay_signature use, line: 466 }
readers:
  - { file: supabase/migrations/052_subscriptions_rls_lockdown.sql, method_or_widget: NOT NULL constraint on razorpay_signature, line: 77 }
  - { file: test/contracts/verify_payment_payload_completeness_test.dart, method_or_widget: schema-vs-payload parity contract test, line: 1 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns:
  - user_id
  - plan
  - status
  - start_date
  - end_date
  - razorpay_payment_id
  - razorpay_order_id
  - razorpay_signature
contract_test_path: test/contracts/verify_payment_payload_completeness_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "userId extracted from caller JWT via auth.getUser; rows are owner-scoped via user_id column"
forbidden_patterns_checked:
  - { pattern: "subscription payload missing razorpay_signature column", absent: true }
  - { pattern: "razorpay_signature without verified_via_api sentinel", absent: true }
proposed_fix: |
  Add `razorpay_signature: 'verified_via_api:' + paymentId.substring(0, 12)`
  to BOTH subscription writes (the primary upsert at line 438 and the
  fallback insert at line 466). The sentinel `verified_via_api:<12-hex>`
  is grep-able for later analytics on which subscriptions were created
  via verify-payment (REST-API validated, no HMAC signature available)
  vs the HMAC-verified webhook (which stores the real signature).

  Considered + rejected: altering migration 052 to make razorpay_signature
  nullable + adding a CHECK constraint. Sentinel approach is faster,
  doesn't require a follow-up migration, and is reversible if we later
  decide on a different proof shape.

  Why missed by today's audit: lens L22 (schema-vs-payload parity)
  did not exist. Migration 052 was applied 4 days ago; nobody grepped
  every callsite that writes to `subscriptions`.

  Lens L22 charter: for every NOT NULL column added by any migration,
  grep every `.from('<table>').insert|upsert|update` callsite and
  assert the column is present in the payload. The contract test in
  this PR implements that lens for `subscriptions` specifically;
  generalize via `scripts/check_schema_payload_parity.dart` (OI-42).
regression_test_planned:
  - test/contracts/verify_payment_payload_completeness_test.dart
---

# Bug b3e052 — verify-payment subscription insert missing NOT NULL razorpay_signature

closes-oi: OI-27

## Root cause

Migration 052 (`supabase/migrations/052_subscriptions_rls_lockdown.sql`)
ran `ALTER TABLE public.subscriptions ALTER COLUMN razorpay_signature
SET NOT NULL` on 2026-05-13. The intent was to lock down
HMAC-verified webhook writes (which always carry the signature).

verify-payment is a SEPARATE entry path: client polls with the
`razorpay_payment_id`, function calls Razorpay's REST API to fetch
the captured payment, and writes the subscription row as a fallback
when the webhook is slow or has failed. There's no HMAC signature
available at this point because the call is server-initiated to
Razorpay's REST API, not the other way around.

Both insert payloads (the primary upsert at line 438 and the fallback
insert at line 466) sent the row without `razorpay_signature` —
which became 23502 after migration 052.

## Why this matters

verify-payment is the user-facing safety net for the webhook. The
client's polling loop in `razorpay_service.dart` calls verify-payment
up to 14 times after a successful checkout (12 by exact payment_id,
then 2 by plan-fuzzy match) — every attempt would hit 23502 and
return 500 to the client. Combined with OI-26 webhook TDZ:

1. User pays via Razorpay checkout.
2. Razorpay fires webhook → razorpay-webhook throws TDZ → 500.
3. Client polls verify-payment → throws 23502 → 500.
4. After 14 attempts, client gives up → "Payment verification failed"
   error to user.
5. Razorpay continues retrying webhook for 24h, each retry TDZ.
6. Subscription row never written. PRO never unlocked. User charged.

## Fix

Add `razorpay_signature: 'verified_via_api:' + paymentId.substring(0, 12)`
to both insert payloads. The sentinel format is:
- Grep-able: any future analyst can run
  `SELECT COUNT(*) FROM subscriptions WHERE razorpay_signature LIKE 'verified_via_api:%'`
  to see how many rows came via verify-payment vs the HMAC webhook.
- Stable: derived deterministically from paymentId; idempotent across
  retries.
- Schema-compatible: stored as TEXT, which is what the column is.

## Verification

```
$ flutter test test/contracts/verify_payment_payload_completeness_test.dart
All tests passed! (2 cases)
```

Test 1 enumerates every `.from("subscriptions")` payload via
brace-balanced scan and asserts every NOT NULL column from migration
052 is present. Test 2 pins the sentinel prefix `verified_via_api:`
so a future refactor doesn't silently set the column to an empty
string to pass test 1.

## Why the test covers FUTURE migrations too

When the next migration adds another NOT NULL column to subscriptions,
update `_requiredColumns` in the contract test in the SAME PR. The
test will fail loudly if a payload misses the new column.

## Related

- CLAUDE.md §16 — Razorpay payment flow + verify-payment polling
- `supabase/migrations/052_subscriptions_rls_lockdown.sql` — the NOT NULL ALTER
- `feedback_audit_methodology_lenses.md` — L22 schema-vs-payload parity (NEW)
- `docs/audit/LENS_REGISTRY.md` — canonical lens registry
- OI-42 — proposed permanent gate `scripts/check_schema_payload_parity.dart` generalizing this lens to every NOT NULL column on every user-tagged table
