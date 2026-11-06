-- Migration 010: Add indexes, idempotency constraint, subscription trigger, summarized column, and RPC
-- Addresses: payment idempotency, subscription race condition, query performance, rolling-context AI

-- ============================================================
-- 1. UNIQUE CONSTRAINT on razorpay_payment_id (Idempotency)
--    Prevents duplicate payment processing from webhook retries
-- ============================================================
ALTER TABLE subscriptions
ADD CONSTRAINT unique_razorpay_payment_id UNIQUE (razorpay_payment_id);


-- ============================================================
-- 2. TRIGGER to auto-update users table on subscription insert
--    Fixes race condition where users.subscription_status could
--    be stale if the app didn't poll in time after payment
-- ============================================================
CREATE OR REPLACE FUNCTION update_user_subscription_status()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'active' THEN
    UPDATE users SET
      subscription_status = 'pro',
      subscription_expires_at = NEW.end_date
    WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_subscription_update_user
  AFTER INSERT OR UPDATE ON subscriptions
  FOR EACH ROW
  WHEN (NEW.status = 'active')
  EXECUTE FUNCTION update_user_subscription_status();


-- ============================================================
-- 3. Five missing indexes for query performance at scale
-- ============================================================

-- AI coach: cron jobs query by user + date
CREATE INDEX IF NOT EXISTS idx_ai_coach_user_created
  ON ai_coach_interactions(user_id, created_at DESC);

-- AI coach: weekly report filters by channel
CREATE INDEX IF NOT EXISTS idx_ai_coach_channel
  ON ai_coach_interactions(channel);

-- Snapshots: queries filter by user + date range
CREATE INDEX IF NOT EXISTS idx_snapshots_user_date
  ON user_daily_snapshots(user_id, snapshot_date DESC);

-- Users: cron jobs filter active users
CREATE INDEX IF NOT EXISTS idx_users_last_active
  ON users(last_active_at DESC);

-- Subscriptions: payment polling for active subs
CREATE INDEX IF NOT EXISTS idx_subscriptions_active
  ON subscriptions(user_id, end_date) WHERE status = 'active';


-- ============================================================
-- 4. Add `summarized` column to ai_coach_interactions
--    Used for rolling-context: marks messages that have been
--    condensed into a summary so they can be excluded from
--    future context windows
-- ============================================================
ALTER TABLE ai_coach_interactions
  ADD COLUMN IF NOT EXISTS summarized boolean DEFAULT false;


-- ============================================================
-- 5. RPC for rolling-context: find users with unsummarized
--    messages exceeding a threshold (for batch summarization)
-- ============================================================
CREATE OR REPLACE FUNCTION get_users_with_message_count(min_count INT)
RETURNS TABLE(user_id UUID, msg_count BIGINT) AS $$
  SELECT user_id, COUNT(*) as msg_count
  FROM ai_coach_interactions
  WHERE summarized = false
  GROUP BY user_id
  HAVING COUNT(*) >= min_count;
$$ LANGUAGE sql STABLE;
