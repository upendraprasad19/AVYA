-- B.5: Promo codes / discount codes for subscription plans.
-- Tables: promo_codes (master list), promo_code_uses (audit trail).

CREATE TABLE IF NOT EXISTS promo_codes (
  code        text PRIMARY KEY,
  discount_pct int NOT NULL CHECK (discount_pct BETWEEN 1 AND 100),
  valid_until  date NOT NULL,
  max_uses     int,
  used_count   int DEFAULT 0,
  is_active    bool DEFAULT true,
  created_at   timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS promo_code_uses (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code            text REFERENCES promo_codes(code),
  user_id         uuid REFERENCES users(id),
  plan_purchased  text NOT NULL,
  original_amount int NOT NULL,
  discount_applied int NOT NULL,
  final_amount    int NOT NULL,
  used_at         timestamptz DEFAULT now()
);

-- RLS: Anyone can read active promo codes (needed for client validation).
ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read active promo codes"
  ON promo_codes
  FOR SELECT
  USING (is_active = true);

-- RLS: Users can only see their own promo code usage.
ALTER TABLE promo_code_uses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can see own promo uses"
  ON promo_code_uses
  FOR SELECT
  USING (auth.uid() = user_id);

-- Index for fast lookup on payment webhook.
CREATE INDEX IF NOT EXISTS idx_promo_code_uses_user
  ON promo_code_uses (user_id, used_at DESC);
