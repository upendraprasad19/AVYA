# Audit C-1: Three independent PRO-grant paths via subscriptions table

**Bug ID:** `audit-c1-subscriptions`
**Severity:** CRITICAL — direct revenue loss + AI quota leak
**Date:** 2026-05-11
**Source:** Audit doc `docs/audit/2026-05-11/code-review-2026-05-11.md` finding C-1 (verified live on prod via MCP)

## Bug

Any authenticated user could self-grant PRO indefinitely. Three independent paths confirmed live on prod:

1. **Open RLS write policies on `subscriptions`** — `subscriptions_insert_own`, `subscriptions_update_own`, `subscriptions_delete_own` all granted INSERT/UPDATE/DELETE to `auth.uid() = user_id`. A user could `INSERT INTO subscriptions(user_id, status, end_date) VALUES (auth.uid(), 'active', now() + interval '10 years')` directly via PostgREST.

2. **Nullable Razorpay proof-of-payment columns** — `razorpay_order_id`, `razorpay_payment_id`, `razorpay_signature` were all `NULL`-able. The entitlement check (status='active' AND end_date > now()) passes without any payment trail. The `unique_razorpay_payment_id` UNIQUE constraint added in migration 010 was bypassable via NULL (Postgres allows multiple NULLs in UNIQUE).

3. **`extend_subscription` SECURITY DEFINER anon-callable** — addressed in C-1 fix continuation (Phase 1 task 9, migration 053).

After (1) granted PRO, the trigger `trg_subscription_update_user` (migration 010:30-34) automatically wrote `users.subscription_status='pro'`. The trigger `trg_food_text_rate_limit` (migration 026) reads `subscriptions.status` to compute the 50/200/day food-text cap — so the same exploit also bypassed the AI quota cap, costing Gemini billing.

## Cause

Migration 006 (`006_create_monetisation_tables.sql:13-24`) created the table and policies in one shot. Initial design treated subscriptions as user-owned data following the same pattern as `weight_logs` / `nutrition_logs` (user can write their own rows). That's correct for those tables; **wrong** for `subscriptions` because the entitlement check uses table state directly.

No security review caught this at the time. The subsequent payment-hardening work (migrations 010, 023, 025) added trigger logic and Razorpay UNIQUE constraints but never revisited the RLS policy.

## Past attempts

None. This is the first attempt to lock down `subscriptions` writes.

## Fix

Migration 052 (`052_subscriptions_rls_lockdown.sql`):
1. DROP `subscriptions_insert_own`, `subscriptions_update_own`, `subscriptions_delete_own`
2. KEEP `subscriptions_select_own` (users still need to read their own state for `SubscriptionService.verifyFromServer()`)
3. `ALTER COLUMN razorpay_order_id SET NOT NULL`
4. `ALTER COLUMN razorpay_payment_id SET NOT NULL`
5. `ALTER COLUMN razorpay_signature SET NOT NULL`
6. Defensive `DO` block that asserts no NULLs exist before applying NOT NULL (would fail loudly if a NULL slipped in between audit and apply).

## Verification

**Pre-migration audit (run 2026-05-11 via MCP):**

```sql
-- 4 total subscription rows on prod
-- 0 with NULL razorpay_*
-- 1 currently active
```

**Codebase audit:**

```bash
grep -rn "from('subscriptions').\(insert\|update\|upsert\|delete\)" lib/
# Returns zero matches. All client-side reads go through SELECT only.
# All writes happen in Edge Functions (razorpay-webhook, verify-payment,
# create-razorpay-order) using service-role which bypasses RLS.
```

## Regression test

`test/contracts/no_client_subscriptions_writes_test.dart` — source-greps `lib/` for any `.from('subscriptions')` immediately followed by `.insert(`, `.update(`, `.upsert(`, or `.delete(`. Fails on any match.

This codifies the rule: client never writes to `subscriptions` directly. All writes flow through service-role-gated Edge Functions.

## Why not also lock down `users.subscription_status`?

`users.subscription_status` is set ONLY by `trg_subscription_update_user` (a trigger on `subscriptions` INSERT/UPDATE). With the `subscriptions` write path locked down to service-role, the `users` column cannot be promoted to PRO via the trigger by an unauthorized writer.

Direct UPDATE of `users.subscription_status` by an authenticated user is **also** blocked because RLS on `users` (migration 008) only grants UPDATE if `auth.uid() = id`, AND `users` doesn't expose `subscription_status` for client UPDATE — the column is set ONLY by the trigger. Direct PostgREST UPDATE of that column passes RLS but is functionally a no-op against the entitlement check (which reads `subscriptions`, not `users.subscription_status`). Belt-and-suspenders OK.

## Related

- Audit C-13 (false alarm — see audit §10)
- Migration 053 (Phase 1 task 7+9 — SECURITY DEFINER hardening, addresses `extend_subscription` anon path)
- Migration 010 (added `unique_razorpay_payment_id` UNIQUE — now actually enforced post-NOT-NULL)
- CLAUDE.md §16 (payment security rules)
