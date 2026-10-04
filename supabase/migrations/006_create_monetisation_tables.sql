-- ============================================================
-- Migration 006: Monetisation Tables
-- ============================================================

-- 1. subscriptions
CREATE TABLE subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan text NOT NULL,
  status text DEFAULT 'active',
  start_date timestamptz NOT NULL,
  end_date timestamptz NOT NULL,
  razorpay_order_id text,
  razorpay_payment_id text,
  razorpay_signature text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "subscriptions_select_own" ON subscriptions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "subscriptions_insert_own" ON subscriptions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "subscriptions_update_own" ON subscriptions FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "subscriptions_delete_own" ON subscriptions FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_razorpay_order_id ON subscriptions(razorpay_order_id);
CREATE INDEX idx_subscriptions_razorpay_payment_id ON subscriptions(razorpay_payment_id);

-- 2. food_corrections
CREATE TABLE food_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  food_id uuid REFERENCES food_database(id),
  original_values jsonb,
  corrected_values jsonb,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE food_corrections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "food_corrections_select_own" ON food_corrections FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "food_corrections_insert_own" ON food_corrections FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "food_corrections_update_own" ON food_corrections FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "food_corrections_delete_own" ON food_corrections FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_food_corrections_user_id ON food_corrections(user_id);

-- 3. telegram_connections
CREATE TABLE telegram_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phone text,
  chat_id text,
  connected_at timestamptz DEFAULT now(),
  is_active bool DEFAULT true,

  CONSTRAINT telegram_connections_user_id_unique UNIQUE (user_id)
);

ALTER TABLE telegram_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "telegram_connections_select_own" ON telegram_connections FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "telegram_connections_insert_own" ON telegram_connections FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "telegram_connections_update_own" ON telegram_connections FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "telegram_connections_delete_own" ON telegram_connections FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_telegram_connections_user_id ON telegram_connections(user_id);
