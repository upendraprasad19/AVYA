---
bug_id: 7ad0c1
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: subscriptions table had open INSERT/UPDATE/DELETE RLS policies plus nullable Razorpay columns; any authenticated user could self-grant indefinite PRO with no payment trail.
concept: subscriptions_rls
sot_registry_entry: subscriptions_rls
writers:
  - { file: supabase/migrations/052_subscriptions_rls_lockdown.sql, method_or_widget: drop_policies_set_not_null, line: 1 }
readers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: verifyFromServer, line: 1 }
hive_key_prefix: "n/a"
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [razorpay_order_id, razorpay_payment_id, razorpay_signature, status, end_date]
contract_test_path: test/contracts/no_client_subscriptions_writes_test.dart
ist_handling: []
provider_invalidations: [subscriptionInfoProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["from-subscriptions-insert", "from-subscriptions-update", "from-subscriptions-upsert", "from-subscriptions-delete"]
proposed_fix: Migration 052 drops subscriptions_{insert,update,delete}_own policies (keep SELECT for verifyFromServer); makes razorpay_order_id/payment_id/signature NOT NULL with defensive DO-block precheck.
regression_test_planned:
  - { file: test/contracts/no_client_subscriptions_writes_test.dart, method_or_widget: source_grep_no_client_subscriptions_writes, line: 1 }
---
# Audit C-1: Three independent PRO-grant paths via subscriptions table

## Bug

Any authenticated user could self-grant PRO indefinitely. Three independent paths confirmed live on prod:

1. **Open RLS write policies on `subscriptions`** — `subscriptions_insert_own`, `subscriptions_update_own`, `subscriptions_delete_own` all granted INSERT/UPDATE/DELETE to `auth.uid() = user_id`. A user could INSERT a `status=active` row with no payment.

2. **Nullable Razorpay proof-of-payment columns** — entitlement check passed without any payment trail. The `unique_razorpay_payment_id` UNIQUE constraint was bypassable via NULL.

3. **`extend_subscription` SECURITY DEFINER anon-callable** — addressed in 7ad035 (migration 053).

After (1) granted PRO, the trigger `trg_subscription_update_user` wrote `users.subscription_status='pro'`. `trg_food_text_rate_limit` reads `subscriptions.status` — so the same exploit also bypassed the AI quota cap.

## Cause

Migration 006 created the table and policies in one shot, treating subscriptions as user-owned data following the same pattern as `weight_logs`. That's correct for those tables; wrong for `subscriptions` because the entitlement check uses table state directly. No security review caught it.

## Past attempts

None. First lockdown attempt.

## Fix

Migration 052 (`052_subscriptions_rls_lockdown.sql`):
1. DROP `subscriptions_insert_own`, `subscriptions_update_own`, `subscriptions_delete_own`
2. KEEP `subscriptions_select_own` (users still need to read their own state)
3. ALTER `razorpay_order_id/payment_id/signature` SET NOT NULL
4. Defensive DO-block asserts no NULLs before applying NOT NULL

## Verification

Pre-migration prod state: 4 rows, 0 NULL razorpay columns, 1 active. Post-migration: only SELECT policy remains; all 3 columns NOT NULL.

Codebase audit: zero client-side direct subscriptions writes.

## Regression test

`test/contracts/no_client_subscriptions_writes_test.dart` source-greps lib/ for any `.from('subscriptions')` followed by `.insert(`, `.update(`, `.upsert(`, or `.delete(`. Fails on any match.

## Related

- 7ad035 (SECURITY DEFINER hardening, migration 053)
- 7ad054 (RLS policy cleanup, migration 054)
- 7ad029 (WITH CHECK sweep, migration 055)
- CLAUDE.md §16
