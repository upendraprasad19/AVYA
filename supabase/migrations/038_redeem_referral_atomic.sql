-- supabase/migrations/038_redeem_referral_atomic.sql
--
-- Atomic both-side reward write for referral redemption. Used by the
-- redeem-referral Edge Function. Wraps the audit row insert + both
-- subscription extensions in a single transaction so partial failures
-- can't leave one side rewarded and the other not.

CREATE OR REPLACE FUNCTION redeem_referral_atomic(
  p_code TEXT,
  p_referrer_id UUID,
  p_referee_id UUID,
  p_days INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_referrer_expires TIMESTAMPTZ;
  v_referee_expires TIMESTAMPTZ;
BEGIN
  -- 1. Audit row (UNIQUE constraint on referee_id catches duplicates)
  INSERT INTO referral_redemptions (
    code, referrer_id, referee_id, days_granted_each
  ) VALUES (
    p_code, p_referrer_id, p_referee_id, p_days
  );

  -- 2. Extend referrer's subscription
  SELECT MAX(end_date) INTO v_referrer_expires
  FROM subscriptions
  WHERE user_id = p_referrer_id AND status = 'active';

  IF v_referrer_expires IS NULL OR v_referrer_expires < now() THEN
    INSERT INTO subscriptions (
      user_id, plan, status, start_date, end_date
    ) VALUES (
      p_referrer_id,
      'referral_trial',
      'active',
      now(),
      now() + (p_days || ' days')::interval
    );
  ELSE
    UPDATE subscriptions
    SET end_date = end_date + (p_days || ' days')::interval
    WHERE user_id = p_referrer_id AND status = 'active'
      AND end_date = v_referrer_expires;
  END IF;

  -- 3. Same for referee
  SELECT MAX(end_date) INTO v_referee_expires
  FROM subscriptions
  WHERE user_id = p_referee_id AND status = 'active';

  IF v_referee_expires IS NULL OR v_referee_expires < now() THEN
    INSERT INTO subscriptions (
      user_id, plan, status, start_date, end_date
    ) VALUES (
      p_referee_id,
      'referral_trial',
      'active',
      now(),
      now() + (p_days || ' days')::interval
    );
  ELSE
    UPDATE subscriptions
    SET end_date = end_date + (p_days || ' days')::interval
    WHERE user_id = p_referee_id AND status = 'active'
      AND end_date = v_referee_expires;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION redeem_referral_atomic(TEXT, UUID, UUID, INT)
  TO service_role;
