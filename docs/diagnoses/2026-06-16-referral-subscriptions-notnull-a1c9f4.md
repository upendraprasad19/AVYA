---
bug_id: a1c9f4
date: 2026-06-16
batch: referral-notnull-fix
status: fixed
blast_radius: account
symptom: >
  On live web (test2@gmail.com), applying AVYA-TESTCODE in Profile → "Apply Referral Code"
  returns "Internal server error" (HTTP 500). Reproduced on a CALM backend (so not the
  Free-tier compute throttle): two fresh 500s (request_ids e862c521, 32f9ca07). subscriptions
  has 0 referral_trial rows EVER and referral_redemptions is empty for the referee — referral
  redemption has never once succeeded in prod.
concept: subscription_state
sot_registry_entry: referral_trial_subscription_grant
writers: >
  supabase/migrations/038_redeem_referral_atomic.sql — redeem_referral_atomic() INSERTs the
  referral_trial subscription for the referrer (line 35) and the referee (line 57) providing
  only (user_id, plan, status, start_date, end_date). supabase/functions/redeem-referral/index.ts
  calls the RPC (index.ts:113). Migration 094 (this batch) ALTERs the 3 razorpay_* columns to
  DROP NOT NULL and CREATE OR REPLACEs the shared grant trigger update_user_subscription_status()
  with a monotonic GREATEST expiry write.
readers: >
  Trigger trg_subscription_update_user -> update_user_subscription_status() reads NEW.status /
  NEW.end_date on the subscriptions INSERT/UPDATE and writes users.subscription_status='pro' +
  subscription_expires_at. users.subscription_status is read by the client PRO gate
  (subscription_service.dart isPro / gate()). The payment writers verify-payment/index.ts +
  razorpay-webhook/index.ts use razorpay_payment_id only as a .eq() idempotency filter VALUE
  (never read off a referral_trial row).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (Edge Function + Postgres RPC; cloud-only grant)
sync_methods: []
restore_methods: []
cloud_table: subscriptions, referral_redemptions, referral_codes
cloud_columns: >
  subscriptions(user_id, plan, status, start_date, end_date, razorpay_order_id,
  razorpay_payment_id, razorpay_signature); users(subscription_status, subscription_expires_at)
contract_test_path: test/contracts/referral_trial_subscription_grant_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - referral_repository_redeem
cross_account_guard: not_applicable
forbidden_patterns_checked:
  - "redeem_referral_atomic INSERT INTO subscriptions omits razorpay_order_id/payment_id/signature, which migration 052 set NOT NULL (no default) -> SQLSTATE 23502 -> RPC throws -> EF returns 500. FIXED by migration 094 dropping NOT NULL on the 3 columns (legitimately null for non-purchase grants)."
  - "update_user_subscription_status() overwrote users.subscription_expires_at = NEW.end_date unconditionally (no GREATEST) -> a monotonic-demotion foot-gun in the SHARED grant trigger that the referral fix arms for the first time. FIXED to GREATEST(COALESCE(subscription_expires_at, NEW.end_date), NEW.end_date)."
  - "DROP NOT NULL chosen over a conditional CHECK: the self-grant exploit is closed by migration 052's POLICY drop (not the NOT NULL); both payment writers set the columns structurally; verify-payment already passes order_id ?? null so the NOT NULL was a latent paid-path liability. UNIQUE(razorpay_payment_id) verified indnullsnotdistinct=false -> multiple NULLs allowed."
proposed_fix: >
  Migration 094: (a) ALTER COLUMN razorpay_order_id / razorpay_payment_id / razorpay_signature
  DROP NOT NULL on subscriptions so the referral_trial INSERT (and any non-purchase grant)
  succeeds; (b) CREATE OR REPLACE update_user_subscription_status() with a monotonic expiry
  write GREATEST(COALESCE(subscription_expires_at, NEW.end_date), NEW.end_date). No
  RPC/EF/client code change. Once the INSERT succeeds, the trigger grants 7-day PRO to both
  referrer and referee. Gate 19 (check_schema_payload_parity.dart) rewritten as an ordered
  SET/DROP-NOT-NULL resolver so it stops asserting NOT NULL on the now-nullable columns.
regression_test_planned: >
  test/contracts/referral_trial_subscription_grant_test.dart — (1) a live rollback-txn calling
  redeem_referral_atomic for a no-active-sub referrer+referee asserts TWO referral_trial rows
  land (both NULL razorpay_payment_id -> proves no UNIQUE-NULL collision; errors 23502 pre-094);
  (2) an active-status referral_trial INSERT flips users.subscription_status='pro' and does NOT
  lower an existing higher subscription_expires_at (pins the GREATEST guard); (3) a source-grep
  that migration 094 contains the 3 DROP NOT NULL + the GREATEST trigger change. Plus a live
  smoke: redeem AVYA-TESTCODE as test2 grants a 7-day referral_trial to BOTH test2 and amar, then
  cleaned up (0 residual).
touched_layers_checked:
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "live information_schema.columns: razorpay_order_id/payment_id/signature were is_nullable=NO no-default (migration 052); migration 094 drops NOT NULL. pg_constraint: UNIQUE(razorpay_payment_id) indnullsnotdistinct=false so multiple NULLs OK; only FK(user_id) + PK + that UNIQUE exist (no CHECK)." }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live SELECT plan,count(*) FROM subscriptions -> only monthly/pro_monthly, 0 referral_trial rows ever; all rows have non-null razorpay_order_id -> dropping NOT NULL strands nothing, no backfill needed." }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: verified, evidence: "redeem-referral v12 (Unit 1) is deployed; no EF change this batch. EF log: POST 500 execution_time 11980ms (a DB error, not fast logic) for request_id 40ec6771 -> the RPC's 23502 was the 500." }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "live non-persisting DO-block proved the exact 23502 on razorpay_order_id; post-094 the RPC-call rollback test lands 2 referral_trial rows; the founder live retry of AVYA-TESTCODE (200 + both grants + both users PRO) is the end-to-end proof, run after the gated apply." }
impact_analysis: >
  Account-tier (referral 7-day PRO grant). Referral redemption has been broken end-to-end since
  inception. Unit 1 (d2b9e6) fixed the auth/RLS context so the EF finally REACHED the RPC, which
  exposed this second, deeper, previously-masked bug: the RPC's subscriptions INSERT violates the
  razorpay_* NOT NULL that migration 052 added without auditing the older 038 writer
  (cross-migration writer drift). The coupled trigger GREATEST guard closes a monotonic-demotion
  vector in the SHARED grant trigger that this fix arms for the first time (mirrors
  verify-payment's F1/F2 guard). Two independent context-blind reviews (CLAUDE.md 4.12) verified
  RLS does not block the SECURITY DEFINER insert, the UNIQUE allows multiple NULLs, no reader
  breaks on NULL, and all other NOT-NULL columns are supplied or defaulted.
  related: d2b9e6 (referral RLS context, Unit 1 — the masking layer above this bug);
  feedback_monotonic_field_recompute_demotion (the trigger GREATEST, 2nd instance);
  cross-migration NOT-NULL writer drift (new debugging-skill class, this batch).
---

# redeem_referral_atomic INSERT violates subscriptions razorpay_* NOT NULL → every redemption 500s (a1c9f4)

## What happened
Applying AVYA-TESTCODE (Profile → "Apply Referral Code") returns "Internal server error" on a
**calm** backend — not the Free-tier throttle. `subscriptions` has **0 `referral_trial` rows ever**
and `referral_redemptions` is empty for the referee, so the 7-day-PRO referral has never once
worked. Unit 1 (d2b9e6) fixed the auth/RLS context so the Edge Function now *reaches* the RPC,
exposing this previously-masked second bug.

## Root cause
`redeem_referral_atomic` (`supabase/migrations/038_redeem_referral_atomic.sql:35,57`) inserts the
trial grant as:
```sql
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date)
VALUES (..., 'referral_trial', 'active', now(), now() + (p_days || ' days')::interval);
```
But `subscriptions.razorpay_order_id / razorpay_payment_id / razorpay_signature` are **NOT NULL,
no default** — set by `052_subscriptions_rls_lockdown.sql`, which audited only the then-existing
Razorpay rows and never reconciled the older 038 writer (**cross-migration writer drift**). The
INSERT dies with `23502 null value in column "razorpay_order_id" … violates not-null constraint`
(verified live via a non-persisting DO block) → the RPC throws → the EF catch (not a 23505) returns
500 (`supabase/functions/redeem-referral/index.ts:134`).

## Fix (migration 094 — two coupled changes)
1. **Drop NOT NULL** on the three Razorpay-only columns — they are legitimately null for
   non-purchase subscriptions. Chosen over a conditional CHECK: the self-grant exploit is closed by
   052's *policy* drop, both payment writers set the IDs structurally, and `verify-payment:514`
   already passes `order_id ?? null` (so the NOT NULL was a latent paid-path liability).
2. **Harden the shared grant trigger** `update_user_subscription_status()` from an unconditional
   `subscription_expires_at = NEW.end_date` to a monotonic
   `GREATEST(COALESCE(subscription_expires_at, NEW.end_date), NEW.end_date)` — closing a reachable
   expiry-demotion vector (concurrent redemption race / a shorter-dated row flipped to active) that
   the referral fix arms for the first time. Mirrors verify-payment's F1/F2 guard.

Once the INSERT succeeds, `trg_subscription_update_user` fires (`WHEN status='active'`) and grants
the 7-day PRO to both referrer and referee. No RPC/EF/client code change.

## Verification
- Pre-fix: a non-persisting DO-block insert of a `referral_trial` row errors `23502` on
  `razorpay_order_id` (demonstrated live).
- Post-apply: `test/contracts/referral_trial_subscription_grant_test.dart` (a live rollback-txn that
  calls the RPC for a no-active-sub pair → 2 `referral_trial` rows, both NULL payment_id, no
  collision) + the GREATEST behavioral assertion + a source-grep of migration 094.
- Live smoke: redeem AVYA-TESTCODE as test2 → HTTP 200 + a `referral_redemptions` row + a 7-day
  `referral_trial` subscription for BOTH test2 and amar + both users `subscription_status='pro'`;
  then cleaned up (0 residual).

## See also
- supabase/migrations/038_redeem_referral_atomic.sql · supabase/migrations/052_subscriptions_rls_lockdown.sql
- supabase/migrations/094_subscriptions_razorpay_nullable.sql (this batch)
- docs/diagnoses/2026-06-13-referral-rls-context-d2b9e6.md (Unit 1 — the masking layer above this)
- scripts/check_schema_payload_parity.dart (Gate 19 — rewritten to honor DROP NOT NULL)
