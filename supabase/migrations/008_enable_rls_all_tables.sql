-- ============================================================
-- Enable RLS on all 21 user-facing tables
-- Every user can only access their own data.
-- exercise_library and food_database are public read-only.
-- ============================================================

-- IDENTITY
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_progress ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_row" ON users FOR ALL USING (auth.uid() = id);
CREATE POLICY "users_own_profile" ON user_profile FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_preferences" ON user_preferences FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_progress" ON user_progress FOR ALL USING (auth.uid() = user_id);

-- FITNESS
ALTER TABLE workout_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE template_exercises ENABLE ROW LEVEL SECURITY;
ALTER TABLE scheduled_workouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_custom_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_workout_templates" ON workout_templates FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_template_exercises" ON template_exercises FOR ALL USING (
  EXISTS (SELECT 1 FROM workout_templates wt WHERE wt.id = template_id AND wt.user_id = auth.uid())
);
CREATE POLICY "users_own_scheduled_workouts" ON scheduled_workouts FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_workout_logs" ON workout_logs FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_custom_exercises" ON user_custom_exercises FOR ALL USING (auth.uid() = user_id);

-- NUTRITION
ALTER TABLE nutrition_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE nutrition_log_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_saved_meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_custom_foods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_nutrition_logs" ON nutrition_logs FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_nutrition_log_items" ON nutrition_log_items FOR ALL USING (
  EXISTS (SELECT 1 FROM nutrition_logs nl WHERE nl.id = log_id AND nl.user_id = auth.uid())
);
CREATE POLICY "users_own_saved_meals" ON user_saved_meals FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_custom_foods" ON user_custom_foods FOR ALL USING (auth.uid() = user_id);

-- HEALTH
ALTER TABLE weight_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE body_measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE sleep_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_weight_logs" ON weight_logs FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_body_measurements" ON body_measurements FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_streaks" ON streaks FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_sleep_logs" ON sleep_logs FOR ALL USING (auth.uid() = user_id);

-- AI & INTELLIGENCE
ALTER TABLE user_daily_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_coach_interactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_daily_snapshots" ON user_daily_snapshots FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_ai_interactions" ON ai_coach_interactions FOR ALL USING (auth.uid() = user_id);

-- MONETISATION
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE telegram_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_subscriptions" ON subscriptions FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "users_own_telegram" ON telegram_connections FOR ALL USING (auth.uid() = user_id);

-- SEED DATA (public read, no user writes via client)
ALTER TABLE exercise_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_database ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read_exercises" ON exercise_library FOR SELECT USING (true);
CREATE POLICY "public_read_food" ON food_database FOR SELECT USING (true);

-- food_corrections (if exists)
DO $$ BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'food_corrections') THEN
    ALTER TABLE food_corrections ENABLE ROW LEVEL SECURITY;
    EXECUTE 'CREATE POLICY "users_own_corrections" ON food_corrections FOR ALL USING (auth.uid() = user_id)';
  END IF;
END $$;
