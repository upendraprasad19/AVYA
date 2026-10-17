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
