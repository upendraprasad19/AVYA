---
source: CLAUDE.md §16
migrated: 2026-05-18
status: scaffold
---

# Payment Flow — Reference

> Razorpay checkout + verification + DPDP §17 erasure (delete-account Edge Function).
> Fetch via Read when working on payment, webhooks, or account deletion.

```
User taps "Upgrade to PRO"
  → Opens Razorpay WebView checkout (amount adjusted for promo if applied)
  → User pays
  → Razorpay webhook → Edge Function (razorpay-webhook)
  → Verify HMAC-SHA256 signature (MANDATORY)
  → Derive plan from payment amount (promo-aware)
  → Write to Supabase subscriptions table
  → Redeem promo code (increment used_count + audit trail)
  → App polls Supabase for confirmation (exact payment_id match)
  → Falls back to verify-payment Edge Function if webhook slow
  → Updates Hive configBox {isPro: true, expiresAt, plan}
  → PRO features unlock immediately
```

## Payment Security Rules (NON-NEGOTIABLE)
1. **Plan derived from amount, NEVER from client:** Both `razorpay-webhook` and `verify-payment` derive the plan (monthly/yearly) from `payment.amount` in paise via `derivePlanFromAmount(amountPaise, promoCode)` (mirrored helper, identical logic in both functions; razorpay-webhook hardened to match verify-payment in Test #11 / Theme I1, 2026-05-04). Client-supplied `body.plan` / `notes.plan` is ignored for entitlement. `computeExpectedAmount` runs as a belt-and-suspenders cross-check after derivation. Prevents a ₹349 monthly payment from getting yearly (365-day) entitlement.
2. **Promo-aware amount validation (tolerant):** If `notes.promo_code` exists, Edge Functions look up the promo in `promo_codes` table and compute discounted expected amount from `discount_pct`. **Tolerant:** accepts the discounted amount even if the promo has since expired or exhausted — the promo was valid when checkout opened, and Razorpay capture can take minutes. Only rejects if the promo code doesn't exist at all or the discount math doesn't match. Logs a warning for race-condition cases.
3. **Promo redemption on success:** After subscription insert, `increment_promo_used_count` RPC atomically increments `used_count`. Audit row written to `promo_code_uses`. This is non-fatal — subscription is already created.
4. **Two-tier polling with plan filter:** Client polls by exact `razorpay_payment_id` (attempts 0-11), then falls back to any active subscription for the SAME PLAN (monthly/yearly) created in last 5 minutes (attempts 12-14). The plan filter is the safety rail against a monthly→yearly upgrade matching the stale monthly row (audit H5, 2026-04-18). See `razorpay_service.dart` `_pollWithPlanFilter()` (function-name anchor; audit 2026-05-20 / Doc14 swept hard-coded line ranges).
5. **Webhook idempotency:** `razorpay-webhook` handles replay attempts safely:
   - **5-minute replay window (audit C4a, 2026-04-18):** After HMAC verification, the webhook rejects any event where `paymentEntity.created_at` is more than 5 minutes old with a 400. Razorpay's retry policy sends webhooks within seconds; anything older is either a replay attack or a lagging event we've already processed. See `razorpay-webhook/index.ts` HMAC + replay-window block (function-name anchor).
   - **Pre-SELECT** `subscriptions` table by `razorpay_payment_id` BEFORE the INSERT. If a row exists, return 200 immediately with `alreadyProcessed: true` and skip promo redemption.
   - **23505 race fallback:** If two webhook replays race past the pre-SELECT, the second INSERT hits the unique constraint on `razorpay_payment_id` → Postgres throws `23505`. The function catches this code specifically and returns 200 (treats as success).
   - **Promo redemption guard:** `increment_promo_used_count` RPC is ONLY called when `alreadyProcessed === false`. Prevents a replayed webhook from double-incrementing `used_count` and burning the promo for nobody.
   - Razorpay retries webhooks aggressively (up to 24h on non-200). Without idempotency, every retry would write a duplicate subscription row AND re-redeem the promo. Never remove the pre-SELECT or the 23505 catch.
6. **verify-payment rate limit (audit C4b, 2026-04-18; moved onto `usage_counters` OI-162 slice 4, f2c8d5):** 20 calls per user per 10 minutes, enforced atomically via `consume_quota()` against `usage_counters` (quota_key `verify_payment`, fixed 10-minute bucket). Over-limit returns 429 with `Retry-After` set to the bucket's exact remaining seconds (not a fixed 600 — that was the old constant-window value). Fails CLOSED on a counter error, unlike delete-account below — see `verify-payment/index.ts` rate-limit block for why the two differ. Protects Razorpay API quota from a runaway client polling on every tick. ⚠ The PRIOR mechanism (`ai_coach_interactions` rows, `channel='verify_payment_attempt'`) is retired; that channel no longer exists.
7. **Promo codes use year-suffix for annual reuse:** `promo_code_uses` has `UNIQUE(code, user_id)` (migration 023, 2026-04-18). A user who redeems `INDEPENDENCEDAY2026` cannot re-redeem the same code the next year — marketing must generate new codes per campaign (`INDEPENDENCEDAY2027`, etc.). Keeps accounting clean and enables per-year attribution.

## DPDP §17 erasure — hard delete account (Test #11 H1, 2026-05-04)

User-initiated hard delete via `/profile/delete-account` (2-step confirm UI: blast-radius page → type-name+`DELETE` confirm). Client invokes `delete-account` Edge Function with `confirmation_token: 'DELETE-MY-ACCOUNT-${userId.substring(0,8)}'`. Server flow (`supabase/functions/delete-account/index.ts`, `verify_jwt: true`):

1. JWT re-validated server-side via `userClient.auth.getUser()`.
2. **Rate limit — 5 attempts per user per hour** (Hermes-R2 #9, 7ad009), enforced atomically via `consume_quota()` against `usage_counters` (quota_key `delete_account`, fixed 1-hour bucket; OI-162 slice 4, f2c8d5). Fails OPEN on a counter error — a DPDP §17 erasure is a legal right and must not be blocked by a counter outage; contrast verify-payment above, which fails closed. ⚠ **This limit did not function before f2c8d5** — its prior mechanism (`ai_coach_interactions` insert) hit two schema violations (nonexistent columns, a NOT NULL column left unset) on every call, silently, so the count was always 0.
3. Confirmation token check — exact match required (token derivation defends against stolen-JWT replay where attacker doesn't know user ID prefix).
4. **Razorpay subscription cancel — best-effort, NON-FATAL (a2c8e6).** For every active sub on the user, POST to `https://api.razorpay.com/v1/subscriptions/{id}/cancel`. ⚠ This row previously said "MUST SUCCEED... any non-200/exception → return 502, abort" — that described the PRE-a2c8e6 behaviour and was stale by the time this correction was made (2026-09-11). The live code cancels FIRST (protects the user from post-deletion charges on success) but a FAILURE is now recorded durably in `account_deletion_log.razorpay_cancel_status` and the erasure PROCEEDS — a Razorpay outage must not indefinitely block a legally-required deletion. See `delete-account/index.ts` step 4 comment block (function-name anchor) for the full reasoning.
5. **OneSignal player_id unsub** (best-effort, logged on failure). Reads `user_progress.onesignal_player_id` (column added by migration 049). Note: Flutter app doesn't yet write this column — known gap. Delete still succeeds; push unsub silently no-ops until the write path is wired.
6. **Storage purge** across `progress-photos/<uid>/`, `chat-media/<uid>/`, `coach-media/<uid>/` (best-effort, per-bucket errors accumulated into `purgeStats.errors[]`).
7. **`auth.users` delete** via service role — CASCADE through `public.users` (FK with `ON DELETE CASCADE` from migration 039) and every user-scoped table. **5 community surfaces are exempt from cascade** (migration 049, `ON DELETE SET NULL`): `user_custom_exercises`, `user_custom_foods`, `community_reviews` (FK on `reviewer_id`, not `user_id`), `food_corrections`, `promo_code_uses`. Their rows survive with `user_id = NULL` ("deleted user" pseudonymization). Read consumers MUST tolerate NULL.
8. **Audit row** to `account_deletion_log` (no FK, survives cascade). Captures `deleted_user_id`, `deleted_at`, `request_id`, `razorpay_cancel_status`, `storage_purge_status` JSONB.
9. Client wipes Hive (`HiveService.instance.clearAllData`) + `signOut(global)` + routes to `/sign-in`.

Step 1 copy explicitly states: subscription cancelled with no refund, Razorpay payment receipts retained per Indian tax law, backups purge within 30 days. No refund automation, no 24-hour grace period, no soft-delete fallback.

`UserRepository.softDeleteAccount` is `@Deprecated` — kept for back-compat only, no active callers remain.
