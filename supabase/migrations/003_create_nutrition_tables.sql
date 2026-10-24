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
