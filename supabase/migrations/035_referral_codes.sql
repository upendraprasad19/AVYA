-- 035_referral_codes.sql
-- Referral-code table for Profile > Invite Friends. Before this migration,
-- SupabaseService.getOrCreateReferralCode() targeted a table whose initial
-- state on prod had these gaps:
--   (a) FK on user_id pointed at public.users(id) instead of auth.users(id),
--       so any auth'd user not yet synced into public.users hit a silent FK
--       violation on insert -> 5 retries fail -> "Failed to generate referral
--       code" toast in the UI.
--   (b) No UNIQUE(user_id) constraint -> concurrent double-inserts could
--       produce duplicate codes for the same user.
--
-- This migration is idempotent and repairs prod in place:
--   - Creates the table if absent (fresh envs).
--   - Drops and re-adds the FK to target auth.users(id).
--   - Adds UNIQUE(user_id) if absent.
--   - Ensures indexes, RLS, and policies are in place.
--
-- Code format: `AVYA-XXXX####` where XXXX is a 4-letter name shard and ####
-- is a 4-digit random seed. Client retries up to 5 times on UNIQUE(code)
-- collision (see supabase_service.dart:98-113).

-- 1. Base table (idempotent).
CREATE TABLE IF NOT EXISTS referral_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  code TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Repoint FK to auth.users(id) if an older FK is in place.
ALTER TABLE referral_codes DROP CONSTRAINT IF EXISTS referral_codes_user_id_fkey;
ALTER TABLE referral_codes
  ADD CONSTRAINT referral_codes_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- 3. Tighten UNIQUE constraints.
ALTER TABLE referral_codes DROP CONSTRAINT IF EXISTS referral_codes_user_id_key;
ALTER TABLE referral_codes ADD CONSTRAINT referral_codes_user_id_key UNIQUE (user_id);

ALTER TABLE referral_codes DROP CONSTRAINT IF EXISTS referral_codes_code_key;
ALTER TABLE referral_codes ADD CONSTRAINT referral_codes_code_key UNIQUE (code);

-- 4. Secondary index for code lookups (referrer-side queries).
CREATE INDEX IF NOT EXISTS idx_referral_codes_code ON referral_codes(code);

-- 5. RLS (idempotent).
ALTER TABLE referral_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own referral code" ON referral_codes;
CREATE POLICY "Users can read own referral code"
  ON referral_codes FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own referral code" ON referral_codes;
CREATE POLICY "Users can insert own referral code"
  ON referral_codes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- No UPDATE / DELETE policies -- codes are immutable once issued.

COMMENT ON TABLE referral_codes IS
  'One referral code per user. Shown in Profile > Invite Friends. Format: AVYA-XXXX####. FK to auth.users so it does not depend on public.users sync state.';
COMMENT ON COLUMN referral_codes.code IS
  'Uppercase, AVYA-prefixed. 4-letter name shard + 4-digit seed. Retried up to 5x on UNIQUE(code) collision by client.';
