# Phase 1: Database (21 Tables + RLS + Indexes)

## Agent: @database-agent
## Deps: Phase 0 (DONE)

## Tasks

### 1.1 Identity Tables
- [ ] `users` — 11 columns, lean identity
- [ ] `user_profile` — onboarding fitness data
- [ ] `user_preferences` — AI chat collected over time
- [ ] `user_progress` — phase, week, streak, experience

### 1.2 Fitness Tables
- [ ] `exercise_library` — 200+ exercises (seeded later)
- [ ] `workout_templates` — reusable blueprints
- [ ] `template_exercises` — exercises per template
- [ ] `scheduled_workouts` — templates assigned to dates
- [ ] `workout_logs` — actual performance data
- [ ] `user_custom_exercises` — personal exercises per user

### 1.3 Nutrition Tables
- [ ] `food_database` — 5,000 foods (seeded later)
- [ ] `nutrition_logs` — meal entries per day
- [ ] `nutrition_log_items` — ingredient breakdown
- [ ] `user_saved_meals` — reusable meal combos
- [ ] `user_custom_foods` — user-added foods

### 1.4 Health Tables
- [ ] `weight_logs` — daily weigh-ins
- [ ] `body_measurements` — monthly measurements
- [ ] `streaks` — weekly completion tracking
- [ ] `sleep_logs` — sleep tracking

### 1.5 AI & Intelligence Tables
- [ ] `user_daily_snapshots` — daily JSON blob for AI context
- [ ] `ai_coach_interactions` — every conversation, training data

### 1.6 Monetisation Tables
- [ ] `subscriptions` — Razorpay records
- [ ] `food_corrections` — PRO macro edits
- [ ] `telegram_connections` — phone → chat_id mapping

### 1.7 Security
- [ ] Enable RLS on ALL 21 tables
- [ ] User-scoped policies: `auth.uid() = user_id` for all user tables
- [ ] Public read policies on `exercise_library` and `food_database`

### 1.8 Indexes
- [ ] `user_id` index on all user-scoped tables
- [ ] `date` index on all log tables
- [ ] `exercise_id` on workout_logs, template_exercises
- [ ] `food_id` on nutrition_log_items

## Completion Criteria
- All 21 tables created in `supabase/migrations/`
- RLS enabled on every table
- Indexes on frequently queried columns
- Migration files numbered sequentially (001-006)

## Schema Reference
See `/CLAUDE.md` Section 7 and `Knowledgebase/schema.txt`
