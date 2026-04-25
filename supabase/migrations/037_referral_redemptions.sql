-- supabase/migrations/037_referral_redemptions.sql
--
-- Two changes for the 7-day referral system:
--   1. Add `expires_at` to referral_codes so codes expire 7 days after generation.
--   2. Extend existing `referral_redemptions` table (created earlier) with `code`
--      and `days_granted_each` columns needed for the redeem-referral Edge Function.
--
-- Note: referral_redemptions table already exists from prior migrations with
-- referrer_id, referee_id, and reward-tracking booleans. This migration
-- adds the missing fields for 7-day code tracking.

-- 1. Code expiry on existing referral_codes table (added by migration 035)
ALTER TABLE referral_codes
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ
    NOT NULL DEFAULT (now() + interval '7 days');

-- Backfill existing rows: any pre-existing codes get a fresh 7-day window
-- starting now (we don't expire them retroactively — they were generated
-- under the "permanent" assumption).
UPDATE referral_codes
  SET expires_at = now() + interval '7 days'
  WHERE expires_at <= now();

-- 2. Extend referral_redemptions table with code and days_granted_each columns
ALTER TABLE referral_redemptions
  ADD COLUMN IF NOT EXISTS code TEXT;

ALTER TABLE referral_redemptions
  ADD COLUMN IF NOT EXISTS days_granted_each INT NOT NULL DEFAULT 7;

-- Ensure unique constraint on referee_id if it doesn't exist
-- (idempotent: if constraint exists, this does nothing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'referral_redemptions' AND constraint_name = 'unique_referee_redemption'
  ) THEN
    ALTER TABLE referral_redemptions ADD CONSTRAINT unique_referee_redemption UNIQUE (referee_id);
  END IF;
END $$;

-- Ensure no_self_referral check constraint if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'referral_redemptions' AND constraint_name = 'no_self_referral'
  ) THEN
    ALTER TABLE referral_redemptions ADD CONSTRAINT no_self_referral CHECK (referrer_id != referee_id);
  END IF;
END $$;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_referral_redemptions_referrer
  ON referral_redemptions (referrer_id);
CREATE INDEX IF NOT EXISTS idx_referral_redemptions_redeemed_at
  ON referral_redemptions (created_at);

-- RLS should already be enabled from prior migration, but ensure it is
ALTER TABLE referral_redemptions ENABLE ROW LEVEL SECURITY;

-- Ensure policy exists (idempotent via CREATE POLICY IF NOT EXISTS in newer Postgres)
-- This policy allows both referrer and referee to read their own redemption rows
DO $$
BEGIN
  EXECUTE 'CREATE POLICY "Users can read own redemptions" ON referral_redemptions
    FOR SELECT USING (auth.uid() = referrer_id OR auth.uid() = referee_id)';
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
