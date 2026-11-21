-- 012: Promo RPC + Streak UNIQUE constraint
-- Fixes: Finding 4 (streak dedupe) + Finding 5 (promo redemption)

-- 1. Deduplicate existing streak rows before adding UNIQUE constraint.
-- Keep the row with the latest created_at for each (user_id, week_start) pair.
DO $$
BEGIN
  DELETE FROM streaks
  WHERE id IN (
    SELECT id FROM (
      SELECT id,
             ROW_NUMBER() OVER (
               PARTITION BY user_id, week_start
               ORDER BY created_at DESC NULLS LAST
             ) AS rn
      FROM streaks
    ) ranked
    WHERE rn > 1
  );
END $$;

-- 2. Add UNIQUE constraint on (user_id, week_start) to prevent future duplicates.
ALTER TABLE streaks
  ADD CONSTRAINT uq_streaks_user_week UNIQUE (user_id, week_start);

-- 3. RPC to atomically increment promo code used_count.
-- Called by Edge Functions (razorpay-webhook, verify-payment) after successful payment.
CREATE OR REPLACE FUNCTION increment_promo_used_count(p_code text)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  UPDATE promo_codes
  SET used_count = used_count + 1
  WHERE code = p_code;
$$;

-- 4. Allow inserts to promo_code_uses (Edge Functions via service_role).
CREATE POLICY "Service role can insert promo uses"
  ON promo_code_uses
  FOR INSERT
  WITH CHECK (true);
