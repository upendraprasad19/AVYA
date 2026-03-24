-- ============================================================
-- Migration 007: Water Logs, Daily Quotes, Avatar/Banner fields
-- ============================================================

-- 1. water_logs
CREATE TABLE IF NOT EXISTS water_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date date NOT NULL,
  total_ml int DEFAULT 0,
  glasses numeric DEFAULT 0,
  urine_color int,
  urine_status text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE water_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "water_logs_select_own" ON water_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "water_logs_insert_own" ON water_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "water_logs_update_own" ON water_logs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "water_logs_delete_own" ON water_logs FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_water_logs_user_id ON water_logs(user_id);
CREATE INDEX idx_water_logs_date ON water_logs(date);

-- 2. Add banner_url + avatar_url to user_profile
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS banner_url text;
ALTER TABLE user_profile ADD COLUMN IF NOT EXISTS avatar_url text;

-- 3. daily_quotes (public read)
CREATE TABLE IF NOT EXISTS daily_quotes (
  id serial PRIMARY KEY,
  day_of_year int NOT NULL UNIQUE CHECK (day_of_year >= 1 AND day_of_year <= 366),
  quote text NOT NULL,
  author text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE daily_quotes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "daily_quotes_public_read" ON daily_quotes FOR SELECT USING (true);

CREATE INDEX idx_daily_quotes_day ON daily_quotes(day_of_year);
