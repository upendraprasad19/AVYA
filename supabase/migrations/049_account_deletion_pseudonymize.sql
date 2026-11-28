-- supabase/migrations/049_account_deletion_pseudonymize.sql
-- DPDP §17 erasure prep: keep community contributions after author deletion.
-- Changes 5 FKs from default/CASCADE to ON DELETE SET NULL.
-- Drops NOT NULL on user_id (or reviewer_id) for those 5 tables.
-- Creates account_deletion_log audit table (no FK, survives auth delete).
--
-- NOTE: community_reviews uses column `reviewer_id` (not `user_id`).
-- All other 4 tables use `user_id`.

-- =========================================================================
-- account_deletion_log audit table
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.account_deletion_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deleted_user_id UUID NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  request_id TEXT,
  razorpay_cancel_status TEXT,
  storage_purge_status JSONB
);

CREATE INDEX IF NOT EXISTS idx_account_deletion_log_deleted_at
  ON public.account_deletion_log(deleted_at DESC);

COMMENT ON TABLE public.account_deletion_log IS
  'DPDP §17 erasure audit trail. Admin-only (no RLS), survives auth.users delete.';

-- No RLS — admin-read only via service role.

-- =========================================================================
-- Pseudonymization FKs (5 community surfaces)
-- =========================================================================

-- Helper: each block (a) drops the existing FK if present, (b) drops NOT NULL,
-- (c) adds the new FK with ON DELETE SET NULL. The existing FK constraint name
-- may vary; we use a DO block to find and drop dynamically.

-- 1. user_custom_exercises (user_id column)
DO $$
DECLARE fkname TEXT;
BEGIN
  SELECT conname INTO fkname FROM pg_constraint
    WHERE conrelid = 'public.user_custom_exercises'::regclass
      AND contype = 'f' AND conname LIKE '%user_id%';
  IF fkname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.user_custom_exercises DROP CONSTRAINT %I', fkname);
  END IF;
END $$;
ALTER TABLE public.user_custom_exercises
  ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.user_custom_exercises
  ADD CONSTRAINT user_custom_exercises_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.user_custom_exercises.user_id IS
  'NULL = original author deleted; exercise retained for community use.';

-- 2. user_custom_foods (user_id column)
DO $$
DECLARE fkname TEXT;
BEGIN
  SELECT conname INTO fkname FROM pg_constraint
    WHERE conrelid = 'public.user_custom_foods'::regclass
      AND contype = 'f' AND conname LIKE '%user_id%';
  IF fkname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.user_custom_foods DROP CONSTRAINT %I', fkname);
  END IF;
END $$;
ALTER TABLE public.user_custom_foods
  ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.user_custom_foods
  ADD CONSTRAINT user_custom_foods_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.user_custom_foods.user_id IS
  'NULL = original author deleted; food retained for community use.';

-- 3. community_reviews — NOTE: column is reviewer_id, not user_id
DO $$
DECLARE fkname TEXT;
BEGIN
  SELECT conname INTO fkname FROM pg_constraint
    WHERE conrelid = 'public.community_reviews'::regclass
      AND contype = 'f' AND conname LIKE '%reviewer_id%';
  IF fkname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.community_reviews DROP CONSTRAINT %I', fkname);
  END IF;
END $$;
ALTER TABLE public.community_reviews
  ALTER COLUMN reviewer_id DROP NOT NULL;
ALTER TABLE public.community_reviews
  ADD CONSTRAINT community_reviews_reviewer_id_fkey
  FOREIGN KEY (reviewer_id) REFERENCES public.users(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.community_reviews.reviewer_id IS
  'NULL = original reviewer deleted; review retained for community signal.';

-- 4. food_corrections (user_id column)
DO $$
DECLARE fkname TEXT;
BEGIN
  SELECT conname INTO fkname FROM pg_constraint
    WHERE conrelid = 'public.food_corrections'::regclass
      AND contype = 'f' AND conname LIKE '%user_id%';
  IF fkname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.food_corrections DROP CONSTRAINT %I', fkname);
  END IF;
END $$;
ALTER TABLE public.food_corrections
  ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.food_corrections
  ADD CONSTRAINT food_corrections_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.food_corrections.user_id IS
  'NULL = original reporter deleted; correction retained.';

-- 5. promo_code_uses (user_id column — already nullable, DROP NOT NULL is no-op)
DO $$
DECLARE fkname TEXT;
BEGIN
  SELECT conname INTO fkname FROM pg_constraint
    WHERE conrelid = 'public.promo_code_uses'::regclass
      AND contype = 'f' AND conname LIKE '%user_id%';
  IF fkname IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.promo_code_uses DROP CONSTRAINT %I', fkname);
  END IF;
END $$;
ALTER TABLE public.promo_code_uses
  ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.promo_code_uses
  ADD CONSTRAINT promo_code_uses_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;
COMMENT ON COLUMN public.promo_code_uses.user_id IS
  'NULL = redeemer deleted; promo use retained for accounting.';

-- =========================================================================
-- onesignal_player_id column on user_progress (for delete-account unsub)
-- =========================================================================

ALTER TABLE public.user_progress
  ADD COLUMN IF NOT EXISTS onesignal_player_id TEXT;

COMMENT ON COLUMN public.user_progress.onesignal_player_id IS
  'OneSignal player ID for push notification targeting. Cleared on account delete.';
