# Database Schema — Supabase Postgres

> ⚠️ **STALE — DO NOT TRUST TABLE LIST BELOW.** This file documents the 21 tables that existed in the project pre-2026-04. The actual current schema has **46 tables**. The authoritative, up-to-date schema lives in [`docs/architecture/database.md`](../architecture/database.md). Migrations under `supabase/migrations/` are the ultimate source of truth.
>
> Last regen: never (this snapshot is from project bootstrap). Kept around only because some older diagnose-docs link to specific sections here. Do not extend.

## Identity (4)

```sql
users (id uuid PK, email text UNIQUE, phone text, full_name text,
  subscription_status text DEFAULT 'free', subscription_expires_at timestamptz,
  telegram_chat_id text, telegram_connected bool, ai_chat_started_at timestamptz,
  onboarding_completed bool, last_active_at timestamptz, created_at timestamptz)

user_profile (user_id uuid FK→users, date_of_birth date, gender text,
  height_cm numeric, current_weight_kg numeric, target_weight_kg numeric,
  primary_goal text, fitness_experience text, days_per_week int,
  equipment_access text, activity_level text, diet_preference text,
  injuries text, wake_up_time time, city text, bmr numeric, tdee numeric)

user_preferences (user_id uuid FK→users, motivational_style text,
  biggest_obstacle text, preferred_language text DEFAULT 'English',
  coaching_notes text)

user_progress (user_id uuid FK→users, current_phase int DEFAULT 1,
  current_week int DEFAULT 1, phase_started_at timestamptz,
  plan_generated_at timestamptz, total_workouts_done int DEFAULT 0,
  current_streak_weeks int DEFAULT 0, detected_experience_level text,
  experience_last_calculated timestamptz)
```

## Fitness (6)

```sql
exercise_library (id uuid PK, name text, name_aliases text[], category text,
  movement_pattern text, exercise_type text, primary_muscles text[],
  secondary_muscles text[], equipment_needed text[], logging_type text NOT NULL,
  difficulty_level text, suitable_for text[], instructions text,
  coaching_cues text[], common_mistakes text[], alternative_ids uuid[],
  regression_id uuid, progression_id uuid, default_sets int, default_reps text,
  default_rest_secs int, default_duration_secs int, source text,
  is_active bool, is_indian_context bool)

workout_templates (id uuid PK, user_id uuid FK, name text, description text,
  workout_type text, estimated_duration_mins int, source text,
  is_active bool, created_at timestamptz, last_used_at timestamptz)

template_exercises (id uuid PK, template_id uuid FK, exercise_id uuid FK,
  exercise_name text, order_index int, logging_type text,
  prescribed_sets int, prescribed_reps text, prescribed_weight text,
  prescribed_time_secs int, rest_seconds int, notes text)

scheduled_workouts (id uuid PK, user_id uuid FK, template_id uuid FK,
  scheduled_date date, week_number int, day_of_week int,
  status text DEFAULT 'planned', completed_at timestamptz,
  UNIQUE(user_id, scheduled_date))  -- prevents duplicate schedules on sync

workout_logs (id uuid PK, user_id uuid FK, scheduled_workout_id uuid FK,
  template_id uuid FK, exercise_id uuid FK, exercise_name text,
  logged_at timestamptz, date date, sets_completed int, reps_completed int,
  weight_kg numeric, duration_seconds int, distance_km numeric,
  rpe int, notes text, is_pr bool DEFAULT false)

user_custom_exercises (id uuid PK, user_id uuid FK, name text,
  logging_type text NOT NULL, category text, primary_muscles text[],
  equipment_needed text[], notes text, default_sets int, default_reps text,
  default_rest_secs int, default_duration_secs int,
  submitted_to_library bool, approved_for_library bool, times_used int)
```

> Note: Cloud `workout_log_exercises` is the per-exercise summary table written by the Flutter app.
> See CLAUDE.md §11 "Exercise Log Cloud Contract" for the field semantics — `set_number` is total
> completed sets, `weight_kg` is best across sets, `exercise_id` = exercise_name (stable identity).

## Nutrition (5)

```sql
food_database (id uuid PK, name text, category text, calories_per_100g numeric,
  protein_per_100g numeric, carbs_per_100g numeric, fat_per_100g numeric,
  fiber_per_100g numeric, standard_serving_desc text, standard_serving_g numeric,
  calories_std numeric, protein_std numeric, carbs_std numeric, fat_std numeric,
  common_additions text[], is_indian bool, source text)

nutrition_logs (id uuid PK, user_id uuid FK, date date,
  total_calories numeric, total_protein numeric, total_carbs numeric,
  total_fat numeric, meal_type text, created_at timestamptz)

nutrition_log_items (id uuid PK, log_id uuid FK, food_id uuid FK,
  food_name text, quantity_g numeric, calories numeric, protein numeric,
  carbs numeric, fat numeric)

user_saved_meals (id uuid PK, user_id uuid FK, name text,
  items jsonb, total_calories numeric, total_protein numeric,
  times_used int, created_at timestamptz)

user_custom_foods (id uuid PK, user_id uuid FK, name text,
  calories_per_100g numeric, protein_per_100g numeric,
  carbs_per_100g numeric, fat_per_100g numeric, fiber_per_100g numeric,
  standard_serving_desc text, standard_serving_g numeric,
  calories_std numeric, protein_std numeric, carbs_std numeric, fat_std numeric,
  times_logged int, submitted_to_db bool, approved bool, created_at timestamptz)
```

## Health (5)

```sql
weight_logs (id uuid PK, user_id uuid FK, date date, weight_kg numeric,
  notes text, created_at timestamptz)

body_measurements (id uuid PK, user_id uuid FK, date date,
  chest numeric, waist numeric, hips numeric, arms numeric,
  notes text, created_at timestamptz)

streaks (id uuid PK, user_id uuid FK, week_start date,
  workouts_planned int, workouts_completed int,
  is_streak_maintained bool, created_at timestamptz,
  UNIQUE(user_id, week_start))  -- prevents duplicate weeks on restore/sync

water_logs (id uuid PK, user_id uuid FK, date date,
  total_ml int, urine_color int, urine_status text,
  updated_at timestamptz, created_at timestamptz,
  UNIQUE(user_id, date))  -- prevents duplicate water entries on sync

sleep_logs (id uuid PK, user_id uuid FK, date date,
  duration_hrs numeric, quality text, bed_time time,
  wake_time time, notes text, created_at timestamptz)
```

## AI & Intelligence (2)

```sql
user_daily_snapshots (id uuid PK, user_id uuid FK, snapshot_date date,
  snapshot_json jsonb, created_at timestamptz)

ai_coach_interactions (id uuid PK, user_id uuid FK,
  snapshot_id uuid FK→user_daily_snapshots, channel text,
  user_message text, ai_response text, model_used text,
  tokens_used int, was_helpful bool, created_at timestamptz)
```

## Monetisation (5)

```sql
subscriptions (id uuid PK, user_id uuid FK, plan text,
  status text, start_date timestamptz, end_date timestamptz,
  razorpay_order_id text, razorpay_payment_id text,
  razorpay_signature text, created_at timestamptz)

promo_codes (code text PK, discount_pct int, valid_until date,
  max_uses int, used_count int DEFAULT 0, is_active bool, created_at timestamptz)

promo_code_uses (id uuid PK, code text FK→promo_codes, user_id uuid FK→users,
  plan_purchased text, original_amount int, discount_applied int,
  final_amount int, used_at timestamptz)
-- RPC: increment_promo_used_count(p_code text) — atomically increments used_count

food_corrections (id uuid PK, user_id uuid FK, food_id uuid FK,
  original_values jsonb, corrected_values jsonb, created_at timestamptz)

telegram_connections (id uuid PK, user_id uuid FK, phone text,
  chat_id text, connected_at timestamptz, is_active bool)
```
