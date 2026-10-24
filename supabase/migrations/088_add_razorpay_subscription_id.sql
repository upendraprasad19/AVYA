-- Intent: Add nullable razorpay_subscription_id to subscriptions. Fixes the delete-account live P0 (the deployed Edge Function SELECTs this column; it never existed → 42703 → 502 → the entire erasure aborts; account deletion has been broken in prod since ~2026-05-11). Additive nullable column = the lowest-risk fix to a payment/DPDP-critical function (no code change). Also pre-stages the schema for the planned recurring-Razorpay-subscription billing model.
-- Destructive?: no   -- nullable ADD COLUMN IF NOT EXISTS; instant metadata-only change; no backfill; existing rows survive with NULL
-- Rollback strategy: inline   -- reverse DDL (DROP COLUMN) commented at file end
-- Linked diagnose-doc: b4e2a9

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS razorpay_subscription_id text;

COMMENT ON COLUMN public.subscriptions.razorpay_subscription_id IS
  'Razorpay recurring-subscription id. NULL for one-time orders (current billing model). Read by the delete-account Edge Function (cancel-before-erase loop, which skips NULLs); will be populated by verify-payment / razorpay-webhook when recurring billing launches. Added migration 088 (diagnose b4e2a9).';

-- Rollback (inline):
-- ALTER TABLE public.subscriptions DROP COLUMN IF EXISTS razorpay_subscription_id;
