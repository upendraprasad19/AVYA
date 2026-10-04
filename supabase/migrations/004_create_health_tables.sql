-- ============================================================
-- Migration 004: Health Tables
-- ============================================================

-- 1. weight_logs
CREATE TABLE weight_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date date NOT NULL,
  weight_kg numeric NOT NULL,
  notes text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE weight_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "weight_logs_select_own" ON weight_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "weight_logs_insert_own" ON weight_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "weight_logs_update_own" ON weight_logs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "weight_logs_delete_own" ON weight_logs FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_weight_logs_user_id ON weight_logs(user_id);
CREATE INDEX idx_weight_logs_date ON weight_logs(date);

-- 2. body_measurements
CREATE TABLE body_measurements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date date NOT NULL,
  chest numeric,
  waist numeric,
  hips numeric,
  arms numeric,
  notes text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE body_measurements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "body_measurements_select_own" ON body_measurements FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "body_measurements_insert_own" ON body_measurements FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "body_measurements_update_own" ON body_measurements FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "body_measurements_delete_own" ON body_measurements FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_body_measurements_user_id ON body_measurements(user_id);
CREATE INDEX idx_body_measurements_date ON body_measurements(date);

-- 3. streaks
CREATE TABLE streaks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_start date NOT NULL,
  workouts_planned int,
  workouts_completed int,
  is_streak_maintained bool DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "streaks_select_own" ON streaks FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "streaks_insert_own" ON streaks FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "streaks_update_own" ON streaks FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "streaks_delete_own" ON streaks FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_streaks_user_id ON streaks(user_id);
CREATE INDEX idx_streaks_week_start ON streaks(week_start);

-- 4. sleep_logs
CREATE TABLE sleep_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date date NOT NULL,
  duration_hrs numeric,
  quality text,
  bed_time time,
  wake_time time,
  notes text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE sleep_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sleep_logs_select_own" ON sleep_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "sleep_logs_insert_own" ON sleep_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "sleep_logs_update_own" ON sleep_logs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "sleep_logs_delete_own" ON sleep_logs FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_sleep_logs_user_id ON sleep_logs(user_id);
CREATE INDEX idx_sleep_logs_date ON sleep_logs(date);
