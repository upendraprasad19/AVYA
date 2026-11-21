-- ============================================================
-- Migration 009: Additional Workout Sync Tables
--
-- Existing tables reused from earlier migrations:
--   workout_logs          (002) — per-exercise log rows
--   user_custom_exercises (002) — user-created exercises
--   user_custom_foods     (003) — user-created foods
--
-- This migration adds:
--   workout_log_exercises        — per-set granular data for cloud restore
--   workout_schedule_completions — which scheduled days were completed
-- ============================================================

-- 1. workout_log_exercises — one row per set per exercise per workout
CREATE TABLE IF NOT EXISTS workout_log_exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_log_id text,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  exercise_id text NOT NULL,
  exercise_name text NOT NULL,
  logging_type text,
  set_number int NOT NULL DEFAULT 1,
  reps int,
  weight_kg numeric(6,2),
  duration_seconds int,
  distance_km numeric(8,3),
  is_pr bool DEFAULT false,
  has_warmup_sets bool DEFAULT false,
  notes text,
  completed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE workout_log_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wle_select_own" ON workout_log_exercises FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "wle_insert_own" ON workout_log_exercises FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "wle_update_own" ON workout_log_exercises FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "wle_delete_own" ON workout_log_exercises FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_wle_user_id ON workout_log_exercises(user_id);
CREATE INDEX idx_wle_workout_log_id ON workout_log_exercises(workout_log_id);
CREATE INDEX idx_wle_completed_at ON workout_log_exercises(completed_at);

-- 2. workout_schedule_completions — tracks which scheduled dates the user completed
CREATE TABLE IF NOT EXISTS workout_schedule_completions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  scheduled_date date NOT NULL,
  day_of_week text,
  workout_name text,
  duration_seconds int,
  completed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, scheduled_date)
);

ALTER TABLE workout_schedule_completions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wsc_select_own" ON workout_schedule_completions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "wsc_insert_own" ON workout_schedule_completions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "wsc_update_own" ON workout_schedule_completions FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "wsc_delete_own" ON workout_schedule_completions FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_wsc_user_id ON workout_schedule_completions(user_id);
CREATE INDEX idx_wsc_date ON workout_schedule_completions(scheduled_date);
