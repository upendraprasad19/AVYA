---
bug_id: 7ad0d5
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: 3 payment-stack hardening gaps. (H-18) verify-payment's `.insert()` fallback after upsert error did not catch Postgres 23505 (unique_violation), so a concurrent webhook + verify-payment race would surface as a 500-ish error response instead of treating the existing row as success. (H-19) razorpay-webhook auto-captured `payment.authorized` events BEFORE the idempotency pre-SELECT, so a replayed `payment.authorized` for an already-captured payment fired a second Razorpay capture call → Razorpay 4xx ("already captured") → we returned 502 → Razorpay retried the same loop. (H-20) `RazorpayService._pollAndActivate` ran `Future.delayed` poll retries with no cancellation — if the user signed out / signed in as a different account mid-poll, the loop would write PRO state to the WRONG user's Hive.
concept: payment_hardening
sot_registry_entry: subscription_payment_grace
writers:
  - { file: supabase/functions/verify-payment/index.ts, method_or_widget: subscriptions fallback insert, line: 440 }
  - { file: supabase/functions/razorpay-webhook/index.ts, method_or_widget: idempotency pre-SELECT, line: 294 }
  - { file: lib/core/services/razorpay_service.dart, method_or_widget: _pollAndActivate session-cancel guard, line: 525 }
readers: []
hive_key_prefix: "userBox: paymentInFlightOrder, isPro, expiresAt, plan, localActivationAt"
hive_key_formula: "n/a — payment-stack hardening"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, razorpay_payment_id, razorpay_order_id, plan, status, end_date, created_at]
contract_test_path: "n/a — TS Edge Function + Dart fire-and-forget callbacks; verified via deploy + manual race scenarios documented in CLAUDE.md §16"
ist_handling: []
provider_invalidations: [subscriptionInfoProvider, trialInfoProvider, messageLimitProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: yes
forbidden_patterns_checked: ["verify_payment_fallback_insert_no_23505_catch", "webhook_capture_before_idempotency", "razorpay_poll_no_session_cancel"]
proposed_fix: (H-18) detect 23505 unique_violation in verify-payment's fallback insert and treat as success — the row already exists with the same (user_id, razorpay_payment_id). (H-19) move idempotency pre-SELECT BEFORE the auto-capture branch in razorpay-webhook; short-circuit (return 200 alreadyProcessed) before the second Razorpay capture call fires. (H-20) capture session userId at poll start; re-check on every iteration; abort if it changed.
regression_test_planned:
  - "n/a — payment-stack changes verified via deploy + Razorpay test-mode race scenarios"
---
# Audit H-18 / H-19 / H-20: payment-stack hardening

## H-18: verify-payment fallback insert ignored 23505

**File:** `supabase/functions/verify-payment/index.ts:440-456`

Pre-fix: upsert with `onConflict: 'user_id,razorpay_payment_id'`
sometimes fails (e.g., the constraint isn't present on the table).
The fallback is a plain `.insert()`. Under a concurrent
webhook+verify-payment race, the webhook may have already written
the row by the time the fallback fires → `.insert()` hits the
UNIQUE constraint on `razorpay_payment_id` → Postgres raises
`unique_violation` (SQLSTATE 23505) → we return a generic error
response.

**Fix:** detect 23505 (via `code` field on the PostgrestError or
the canonical "duplicate key value violates unique constraint"
substring) and fall through to the success path. Row exists with
the same `(user_id, razorpay_payment_id)`, so verified=true is
correct.

## H-19: webhook auto-capture fired before idempotency pre-SELECT

**File:** `supabase/functions/razorpay-webhook/index.ts:294-366` →
moved before line 480 pre-SELECT.

Pre-fix order:
1. Razorpay sends `payment.authorized` with `captured=false`.
2. Webhook fires capture call to Razorpay → success.
3. Pre-SELECT subscriptions → insert.
4. Razorpay sends `payment.captured` (replay-ish).
5. Webhook fires capture call AGAIN → Razorpay returns 4xx
   ("payment already captured") → we return 502 →
   Razorpay retries the webhook forever.

**Fix:** added a new idempotency pre-SELECT BEFORE the auto-capture
branch. If `subscriptions` already has a row for this
`razorpay_payment_id`, return 200 `alreadyProcessed: true`
immediately. The existing pre-SELECT at line 480 stays as
defense-in-depth.

## H-20: poll loop had no session-cancel guard

**File:** `lib/core/services/razorpay_service.dart:525-635`

Pre-fix: `_pollAndActivate` captures `userId` at line 517, then
runs 15 attempts of `await Future.delayed(...)` + Supabase query.
If the user signs out + signs in as a different account during the
~45s poll window, the loop writes the PRO row for the WRONG user
(stale `userId` from capture).

**Fix:** added per-iteration re-read of
`SupabaseService.instance.currentUser?.id` at the top of each
attempt. If it differs from the captured `userId`, abort. Same
check inserted into Phase 2 (verify-payment Edge Function call)
since that's also an awaited call with the same race surface.

## Regression check

Suite: 1569 pass / 0 fail / 2 skip (Dart-only).

## Deploys

- `verify-payment`
- `razorpay-webhook`

## Related

- CLAUDE.md §16 (Payment Security Rules — webhook idempotency,
  two-tier polling with plan filter, JWT refresh, etc.)
- 7ad0c1 (Phase 1 subscriptions RLS lockdown + Razorpay NOT NULL)
- 7ad0cf (H-41 event-based paymentInFlight)
