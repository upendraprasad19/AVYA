-- ============================================================================
-- Migration 001: Identity Tables
-- Tables: users, user_profile, user_preferences, user_progress
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1. USERS
-- --------------------------------------------------------------------------
CREATE TABLE users (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email                   text UNIQUE,
  phone                   text,
  full_name               text,
  subscription_status     text DEFAULT 'free',
  subscription_expires_at timestamptz,
  telegram_chat_id        text,
  telegram_connected      bool DEFAULT false,
  ai_chat_started_at      timestamptz,
  onboarding_completed    bool DEFAULT false,
  last_active_at          timestamptz,
  created_at              timestamptz DEFAULT now()
);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_select_own" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "users_insert_own" ON users
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "users_update_own" ON users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "users_delete_own" ON users
  FOR DELETE USING (auth.uid() = id);

-- --------------------------------------------------------------------------
-- 2. USER_PROFILE
-- --------------------------------------------------------------------------
CREATE TABLE user_profile (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date_of_birth     date,
  gender            text,
  height_cm         numeric,
  current_weight_kg numeric,
  target_weight_kg  numeric,
  primary_goal      text,
  fitness_experience text,
  days_per_week     int,
  equipment_access  text,
  activity_level    text,
  diet_preference   text,
  injuries          text,
  wake_up_time      time,
  city              text,
  bmr               numeric,
  tdee              numeric,
  created_at        timestamptz DEFAULT now(),
  updated_at        timestamptz DEFAULT now(),

  CONSTRAINT user_profile_user_id_unique UNIQUE (user_id)
);

CREATE INDEX idx_user_profile_user_id ON user_profile(user_id);

ALTER TABLE user_profile ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_profile_select_own" ON user_profile
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "user_profile_insert_own" ON user_profile
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_profile_update_own" ON user_profile
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "user_profile_delete_own" ON user_profile
  FOR DELETE USING (auth.uid() = user_id);

-- --------------------------------------------------------------------------
-- 3. USER_PREFERENCES
-- --------------------------------------------------------------------------
CREATE TABLE user_preferences (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  motivational_style  text,
  biggest_obstacle    text,
  preferred_language  text DEFAULT 'English',
  coaching_notes      text,
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now(),

  CONSTRAINT user_preferences_user_id_unique UNIQUE (user_id)
);

CREATE INDEX idx_user_preferences_user_id ON user_preferences(user_id);

ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_preferences_select_own" ON user_preferences
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "user_preferences_insert_own" ON user_preferences
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_preferences_update_own" ON user_preferences
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "user_preferences_delete_own" ON user_preferences
  FOR DELETE USING (auth.uid() = user_id);

-- --------------------------------------------------------------------------
-- 4. USER_PROGRESS
-- --------------------------------------------------------------------------
CREATE TABLE user_progress (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  current_phase               int DEFAULT 1,
  current_week                int DEFAULT 1,
  phase_started_at            timestamptz,
  plan_generated_at           timestamptz,
  total_workouts_done         int DEFAULT 0,
  current_streak_weeks        int DEFAULT 0,
  detected_experience_level   text,
  experience_last_calculated  timestamptz,
  created_at                  timestamptz DEFAULT now(),
  updated_at                  timestamptz DEFAULT now(),

  CONSTRAINT user_progress_user_id_unique UNIQUE (user_id)
);

CREATE INDEX idx_user_progress_user_id ON user_progress(user_id);

ALTER TABLE user_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_progress_select_own" ON user_progress
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "user_progress_insert_own" ON user_progress
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_progress_update_own" ON user_progress
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "user_progress_delete_own" ON user_progress
  FOR DELETE USING (auth.uid() = user_id);
