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
-- ============================================================
-- Migration 002: Fitness Tables
-- ============================================================

-- 1. exercise_library (PUBLIC read)
CREATE TABLE exercise_library (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  name_aliases text[],
  category text,
  movement_pattern text,
  exercise_type text,
  primary_muscles text[],
  secondary_muscles text[],
  equipment_needed text[],
  logging_type text NOT NULL,
  difficulty_level text,
  suitable_for text[],
  instructions text,
  coaching_cues text[],
  common_mistakes text[],
  alternative_ids uuid[],
  regression_id uuid,
  progression_id uuid,
  default_sets int,
  default_reps text,
  default_rest_secs int,
  default_duration_secs int,
  source text DEFAULT 'system',
  is_active bool DEFAULT true,
  is_indian_context bool DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE exercise_library ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exercise_library_public_read" ON exercise_library FOR SELECT USING (true);

CREATE INDEX idx_exercise_library_category ON exercise_library(category);
CREATE INDEX idx_exercise_library_logging_type ON exercise_library(logging_type);
CREATE INDEX idx_exercise_library_difficulty ON exercise_library(difficulty_level);

-- 2. workout_templates
CREATE TABLE workout_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  workout_type text,
  estimated_duration_mins int,
  source text DEFAULT 'generated',
  is_active bool DEFAULT true,
  created_at timestamptz DEFAULT now(),
  last_used_at timestamptz
);

ALTER TABLE workout_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workout_templates_select_own" ON workout_templates FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "workout_templates_insert_own" ON workout_templates FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "workout_templates_update_own" ON workout_templates FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "workout_templates_delete_own" ON workout_templates FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_workout_templates_user_id ON workout_templates(user_id);

-- 3. template_exercises
CREATE TABLE template_exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES workout_templates(id) ON DELETE CASCADE,
  exercise_id uuid REFERENCES exercise_library(id),
  exercise_name text,
  order_index int,
  logging_type text,
  prescribed_sets int,
  prescribed_reps text,
  prescribed_weight text,
  prescribed_time_secs int,
  rest_seconds int,
  notes text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE template_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "template_exercises_select_own" ON template_exercises FOR SELECT
  USING (EXISTS (SELECT 1 FROM workout_templates wt WHERE wt.id = template_id AND wt.user_id = auth.uid()));
CREATE POLICY "template_exercises_insert_own" ON template_exercises FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM workout_templates wt WHERE wt.id = template_id AND wt.user_id = auth.uid()));
CREATE POLICY "template_exercises_update_own" ON template_exercises FOR UPDATE
  USING (EXISTS (SELECT 1 FROM workout_templates wt WHERE wt.id = template_id AND wt.user_id = auth.uid()));
CREATE POLICY "template_exercises_delete_own" ON template_exercises FOR DELETE
  USING (EXISTS (SELECT 1 FROM workout_templates wt WHERE wt.id = template_id AND wt.user_id = auth.uid()));

CREATE INDEX idx_template_exercises_template_id ON template_exercises(template_id);
CREATE INDEX idx_template_exercises_exercise_id ON template_exercises(exercise_id);

-- 4. scheduled_workouts
CREATE TABLE scheduled_workouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  template_id uuid REFERENCES workout_templates(id),
  scheduled_date date,
  week_number int,
  day_of_week int,
  status text DEFAULT 'planned',
  completed_at timestamptz,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE scheduled_workouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "scheduled_workouts_select_own" ON scheduled_workouts FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "scheduled_workouts_insert_own" ON scheduled_workouts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "scheduled_workouts_update_own" ON scheduled_workouts FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "scheduled_workouts_delete_own" ON scheduled_workouts FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_scheduled_workouts_user_id ON scheduled_workouts(user_id);
CREATE INDEX idx_scheduled_workouts_template_id ON scheduled_workouts(template_id);
CREATE INDEX idx_scheduled_workouts_date ON scheduled_workouts(scheduled_date);

-- 5. workout_logs
CREATE TABLE workout_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  scheduled_workout_id uuid REFERENCES scheduled_workouts(id),
  template_id uuid REFERENCES workout_templates(id),
  exercise_id uuid REFERENCES exercise_library(id),
  exercise_name text,
  logged_at timestamptz DEFAULT now(),
  date date,
  sets_completed int,
  reps_completed int,
  weight_kg numeric,
  duration_seconds int,
  distance_km numeric,
  rpe int,
  notes text,
  is_pr bool DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE workout_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "workout_logs_select_own" ON workout_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "workout_logs_insert_own" ON workout_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "workout_logs_update_own" ON workout_logs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "workout_logs_delete_own" ON workout_logs FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_workout_logs_user_id ON workout_logs(user_id);
CREATE INDEX idx_workout_logs_exercise_id ON workout_logs(exercise_id);
CREATE INDEX idx_workout_logs_date ON workout_logs(date);

-- 6. user_custom_exercises
CREATE TABLE user_custom_exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  logging_type text NOT NULL,
  category text,
  primary_muscles text[],
  equipment_needed text[],
  notes text,
  default_sets int,
  default_reps text,
  default_rest_secs int,
  default_duration_secs int,
  submitted_to_library bool DEFAULT false,
  approved_for_library bool DEFAULT false,
  times_used int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE user_custom_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_custom_exercises_select_own" ON user_custom_exercises FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_custom_exercises_insert_own" ON user_custom_exercises FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_custom_exercises_update_own" ON user_custom_exercises FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "user_custom_exercises_delete_own" ON user_custom_exercises FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_user_custom_exercises_user_id ON user_custom_exercises(user_id);
-- ============================================================
-- Migration 003: Nutrition Tables
-- ============================================================

-- 1. food_database (PUBLIC read)
CREATE TABLE food_database (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  category text,
  calories_per_100g numeric,
  protein_per_100g numeric,
  carbs_per_100g numeric,
  fat_per_100g numeric,
  fiber_per_100g numeric,
  standard_serving_desc text,
  standard_serving_g numeric,
  calories_std numeric,
  protein_std numeric,
  carbs_std numeric,
  fat_std numeric,
  common_additions text[],
  is_indian bool DEFAULT true,
  source text DEFAULT 'system',
  created_at timestamptz DEFAULT now()
);

ALTER TABLE food_database ENABLE ROW LEVEL SECURITY;

CREATE POLICY "food_database_public_read" ON food_database FOR SELECT USING (true);

CREATE INDEX idx_food_database_category ON food_database(category);
CREATE INDEX idx_food_database_name ON food_database(name);

-- 2. nutrition_logs
CREATE TABLE nutrition_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date date NOT NULL,
  total_calories numeric,
  total_protein numeric,
  total_carbs numeric,
  total_fat numeric,
  meal_type text,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE nutrition_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nutrition_logs_select_own" ON nutrition_logs FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "nutrition_logs_insert_own" ON nutrition_logs FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "nutrition_logs_update_own" ON nutrition_logs FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "nutrition_logs_delete_own" ON nutrition_logs FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_nutrition_logs_user_id ON nutrition_logs(user_id);
CREATE INDEX idx_nutrition_logs_date ON nutrition_logs(date);

-- 3. nutrition_log_items
CREATE TABLE nutrition_log_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  log_id uuid NOT NULL REFERENCES nutrition_logs(id) ON DELETE CASCADE,
  food_id uuid REFERENCES food_database(id),
  food_name text,
  quantity_g numeric,
  calories numeric,
  protein numeric,
  carbs numeric,
  fat numeric,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE nutrition_log_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nutrition_log_items_select_own" ON nutrition_log_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM nutrition_logs nl WHERE nl.id = log_id AND nl.user_id = auth.uid()));
CREATE POLICY "nutrition_log_items_insert_own" ON nutrition_log_items FOR INSERT
  WITH CHECK (EXISTS (SELECT 1 FROM nutrition_logs nl WHERE nl.id = log_id AND nl.user_id = auth.uid()));
CREATE POLICY "nutrition_log_items_update_own" ON nutrition_log_items FOR UPDATE
  USING (EXISTS (SELECT 1 FROM nutrition_logs nl WHERE nl.id = log_id AND nl.user_id = auth.uid()));
CREATE POLICY "nutrition_log_items_delete_own" ON nutrition_log_items FOR DELETE
  USING (EXISTS (SELECT 1 FROM nutrition_logs nl WHERE nl.id = log_id AND nl.user_id = auth.uid()));

CREATE INDEX idx_nutrition_log_items_log_id ON nutrition_log_items(log_id);
CREATE INDEX idx_nutrition_log_items_food_id ON nutrition_log_items(food_id);

-- 4. user_saved_meals
CREATE TABLE user_saved_meals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  items jsonb,
  total_calories numeric,
  total_protein numeric,
  times_used int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE user_saved_meals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_saved_meals_select_own" ON user_saved_meals FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_saved_meals_insert_own" ON user_saved_meals FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_saved_meals_update_own" ON user_saved_meals FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "user_saved_meals_delete_own" ON user_saved_meals FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_user_saved_meals_user_id ON user_saved_meals(user_id);

-- 5. user_custom_foods
CREATE TABLE user_custom_foods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  calories_per_100g numeric,
  protein_per_100g numeric,
  carbs_per_100g numeric,
  fat_per_100g numeric,
  fiber_per_100g numeric,
  standard_serving_desc text,
  standard_serving_g numeric,
  calories_std numeric,
  protein_std numeric,
  carbs_std numeric,
  fat_std numeric,
  times_logged int DEFAULT 0,
  submitted_to_db bool DEFAULT false,
  approved bool DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE user_custom_foods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_custom_foods_select_own" ON user_custom_foods FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_custom_foods_insert_own" ON user_custom_foods FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_custom_foods_update_own" ON user_custom_foods FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "user_custom_foods_delete_own" ON user_custom_foods FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_user_custom_foods_user_id ON user_custom_foods(user_id);
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
-- ============================================================
-- Migration 005: AI & Intelligence Tables
-- ============================================================

-- 1. user_daily_snapshots
CREATE TABLE user_daily_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_date date NOT NULL,
  snapshot_json jsonb NOT NULL,
  created_at timestamptz DEFAULT now(),

  CONSTRAINT user_daily_snapshots_unique_per_day UNIQUE (user_id, snapshot_date)
);

ALTER TABLE user_daily_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_daily_snapshots_select_own" ON user_daily_snapshots FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "user_daily_snapshots_insert_own" ON user_daily_snapshots FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_daily_snapshots_update_own" ON user_daily_snapshots FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "user_daily_snapshots_delete_own" ON user_daily_snapshots FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_user_daily_snapshots_user_id ON user_daily_snapshots(user_id);
CREATE INDEX idx_user_daily_snapshots_date ON user_daily_snapshots(snapshot_date);

-- 2. ai_coach_interactions
CREATE TABLE ai_coach_interactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  snapshot_id uuid REFERENCES user_daily_snapshots(id),
  channel text DEFAULT 'app',
  user_message text NOT NULL,
  ai_response text,
  model_used text,
  tokens_used int,
  was_helpful bool,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE ai_coach_interactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_coach_interactions_select_own" ON ai_coach_interactions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "ai_coach_interactions_insert_own" ON ai_coach_interactions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "ai_coach_interactions_update_own" ON ai_coach_interactions FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "ai_coach_interactions_delete_own" ON ai_coach_interactions FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_ai_coach_interactions_user_id ON ai_coach_interactions(user_id);
CREATE INDEX idx_ai_coach_interactions_snapshot_id ON ai_coach_interactions(snapshot_id);
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
