-- Migration 052: subscriptions RLS lockdown + Razorpay columns NOT NULL
--
-- closes-finding: C-1 (audit 2026-05-11)
--
-- Background:
-- The pre-existing policies subscriptions_{insert,update,delete}_own allowed
-- any authenticated user to write directly to public.subscriptions via
-- PostgREST. Combined with three nullable Razorpay columns, an attacker
-- could INSERT a row with `status='active', end_date=now()+10y` and no
-- proof of payment. Trigger trg_subscription_update_user (migration 010)
-- then promotes users.subscription_status='pro'. Three independent paths
-- to self-grant PRO.
--
-- This migration:
--   1. Drops the three open write policies (INSERT, UPDATE, DELETE)
--   2. Keeps SELECT policy (users need to read their own subscription)
--   3. Makes razorpay_order_id, razorpay_payment_id, razorpay_signature
--      NOT NULL — closes the second path (entitlement without proof of
--      payment) and ensures the razorpay_payment_id UNIQUE constraint
--      cannot be bypassed via NULL.
--
-- Pre-migration audit (run 2026-05-11 via MCP):
--   - 4 total subscription rows on prod
--   - 0 rows with NULL razorpay_order_id, razorpay_payment_id, or razorpay_signature
--   - 1 currently active subscription
--   Safe to apply NOT NULL with no backfill.
--
-- Pre-migration audit (Dart codebase):
--   `grep -rn ".from('subscriptions').insert/update/upsert/delete"` returns
--   zero matches. All client-side writes already go through Edge Functions
--   (razorpay-webhook, verify-payment, create-razorpay-order) which use
--   service-role and bypass RLS. The only thing this migration breaks is
--   the exploit path itself.

BEGIN;

-- ──────────────────────────────────────────────────────────────────────
-- Part 1: drop open write policies
-- ──────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS subscriptions_insert_own ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_update_own ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_delete_own ON public.subscriptions;

-- subscriptions_select_own (SELECT, auth.uid()=user_id) is intentionally
-- preserved — users must be able to read their own subscription state for
-- the SubscriptionService.verifyFromServer() path.

-- ──────────────────────────────────────────────────────────────────────
-- Part 2: NOT NULL on Razorpay proof-of-payment columns
-- ──────────────────────────────────────────────────────────────────────

-- Defensive: if any new NULLs sneaked in between the audit (2026-05-11)
-- and this migration applying, we want to know. Service role and
-- service-role-gated Edge Functions are the only writers, so this
-- should be impossible — but cheap to assert.
DO $$
DECLARE
  null_order_id INTEGER;
  null_payment_id INTEGER;
  null_signature INTEGER;
BEGIN
  SELECT
    COUNT(*) FILTER (WHERE razorpay_order_id IS NULL),
    COUNT(*) FILTER (WHERE razorpay_payment_id IS NULL),
    COUNT(*) FILTER (WHERE razorpay_signature IS NULL)
  INTO null_order_id, null_payment_id, null_signature
  FROM public.subscriptions;

  IF (null_order_id + null_payment_id + null_signature) > 0 THEN
    RAISE EXCEPTION
      'subscriptions has NULL Razorpay columns: order_id=%, payment_id=%, signature=%',
      null_order_id, null_payment_id, null_signature;
  END IF;
END $$;

ALTER TABLE public.subscriptions ALTER COLUMN razorpay_order_id   SET NOT NULL;
ALTER TABLE public.subscriptions ALTER COLUMN razorpay_payment_id SET NOT NULL;
ALTER TABLE public.subscriptions ALTER COLUMN razorpay_signature  SET NOT NULL;

-- ──────────────────────────────────────────────────────────────────────
-- Part 3: regression — UNIQUE on razorpay_payment_id with NULLs allowed
-- multiple inserts; making the column NOT NULL closes that side door.
-- The constraint added in migration 010 (`unique_razorpay_payment_id`)
-- is now actually unique. No further work needed.
-- ──────────────────────────────────────────────────────────────────────

COMMIT;
