-- Intent: Let non-purchase subscriptions (referral/promo/trial grants) exist without Razorpay IDs, and make the grant trigger's expiry write monotonic.
-- Destructive?: no   -- relaxes 3 NOT NULL constraints (widening) + CREATE OR REPLACE of a trigger fn; no column/row drop, no data change
-- Rollback strategy: inline   -- reverse DDL (re-add NOT NULL [needs zero NULL rows first] + restore prior trigger body) commented at file end
-- Linked diagnose-doc: a1c9f4   -- docs/diagnoses/2026-06-16-referral-subscriptions-notnull-a1c9f4.md
--
-- 094_subscriptions_razorpay_nullable.sql
-- Referral redemption has 500'd for every user since inception: redeem_referral_atomic
-- (migration 038) INSERTs a `referral_trial` subscription WITHOUT the razorpay_* columns,
-- which migration 052 set NOT NULL (no default) -> 23502 -> the redeem-referral Edge Function
-- returns 500. (Unit 1 / d2b9e6 fixed the auth context so the EF finally reached the RPC,
-- exposing this.) See the diagnose-doc for the full live evidence (zero referral_trial rows ever).
--
-- (a) DROP NOT NULL on the 3 Razorpay-only columns. They are legitimately NULL for any
--     non-purchase subscription (referral/promo/trial/comp). Real purchases are unaffected:
--     verify-payment + razorpay-webhook always SET these. Chosen over a conditional CHECK
--     because the self-grant exploit is closed by 052's POLICY drop (not the NOT NULL), and
--     verify-payment already passes `order_id ?? null` (so the NOT NULL was a latent paid-path
--     liability). UNIQUE(razorpay_payment_id) is NULLS-DISTINCT (indnullsnotdistinct=false),
--     so multiple referral rows with NULL payment_id never collide.
--
-- (b) Harden the SHARED grant trigger update_user_subscription_status() to a MONOTONIC expiry
--     write. The referral RPC's ELSE branch UPDATEs an existing active row; the trigger fires
--     on that UPDATE and previously overwrote users.subscription_expires_at unconditionally -- a
--     reachable expiry-demotion vector (concurrent redemption race / a shorter-dated row flipped
--     to active) that this fix arms for the first time. GREATEST mirrors verify-payment's F1/F2
--     guard: expiry only ever raises-or-keeps, never lowers. status is still set to 'pro'; the
--     WHEN(status='active') trigger condition is unchanged. Idempotent (CREATE OR REPLACE).

ALTER TABLE public.subscriptions ALTER COLUMN razorpay_order_id   DROP NOT NULL;
ALTER TABLE public.subscriptions ALTER COLUMN razorpay_payment_id DROP NOT NULL;
ALTER TABLE public.subscriptions ALTER COLUMN razorpay_signature  DROP NOT NULL;

CREATE OR REPLACE FUNCTION public.update_user_subscription_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status = 'active' THEN
    UPDATE users SET
      subscription_status = 'pro',
      -- Monotonic (a1c9f4): never lower an existing future expiry. COALESCE handles a
      -- first-time grant where the old value is NULL.
      subscription_expires_at = GREATEST(COALESCE(subscription_expires_at, NEW.end_date), NEW.end_date)
    WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$function$;

-- Post-apply verification (run in the SQL editor):
--   select count(*) from information_schema.columns
--     where table_name='subscriptions' and column_name like 'razorpay_%' and is_nullable='YES';  -- expect 3
--   -- a referral_trial insert now succeeds (proven in a rollback txn):
--   begin;
--     insert into subscriptions (user_id, plan, status, start_date, end_date)
--       values ('<a real user id>', 'referral_trial', 'active', now(), now() + interval '7 days');
--   rollback;

-- Rollback (inline):
-- -- Re-adding NOT NULL requires ZERO NULL rows first (delete/backfill any referral_trial rows):
-- ALTER TABLE public.subscriptions ALTER COLUMN razorpay_order_id   SET NOT NULL;
-- ALTER TABLE public.subscriptions ALTER COLUMN razorpay_payment_id SET NOT NULL;
-- ALTER TABLE public.subscriptions ALTER COLUMN razorpay_signature  SET NOT NULL;
-- -- Restore the prior (unconditional-overwrite) trigger body:
-- CREATE OR REPLACE FUNCTION public.update_user_subscription_status() RETURNS trigger
--  LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
-- BEGIN
--   IF NEW.status = 'active' THEN
--     UPDATE users SET subscription_status = 'pro', subscription_expires_at = NEW.end_date
--       WHERE id = NEW.user_id;
--   END IF;
--   RETURN NEW;
-- END; $f$;
