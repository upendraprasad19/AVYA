-- ──────────────────────────────────────────────────────────────────────────
-- QA seed data for local Supabase instance.
-- Run via:  supabase db reset
-- Or apply directly: psql $DATABASE_URL -f supabase/seed_qa.sql
--
-- Creates the QA test user used by all integration tests:
--   Email:    test6@gmail.com
--   Password: <set via SUPABASE_TEST_PASSWORD>
-- ──────────────────────────────────────────────────────────────────────────

-- ⚠⚠ READ BEFORE RUNNING — THE UUID BELOW NAMES A REAL ACCOUNT ⚠⚠
--
-- This file used to seed a placeholder id (00000000-…-0001) that matched no
-- auth.users row anywhere, so running it against PRODUCTION by mistake failed
-- loudly on a foreign-key violation. It now carries test6@gmail.com's REAL
-- production id, because the tests sign in as that account and the seed has to
-- agree with them.
--
-- That trade makes an accidental prod run WORSE, not better: every statement
-- below is an upsert (ON CONFLICT DO UPDATE), so instead of erroring it would
-- SILENTLY overwrite that account's profile, goal, subscription_status and
-- measurements, and insert synthetic workout/nutrition/weight rows into its
-- real history. The failure mode moved from loud to silent, which is the
-- opposite of the direction you want.
--
-- The check below ENFORCES that rather than asking you to run it by hand. A
-- guard written as a comment is not a guard — the first version of this warning
-- was exactly that, and a Hermes lens called it correctly.
-- Raised by the B-pass on 36a5740eae0d; diagnose f7a2c4.

DO $seed_guard$
BEGIN
  -- Local Supabase listens on loopback. A managed/remote Postgres does not.
  -- inet_server_addr() is NULL over a unix socket, which is also local.
  IF inet_server_addr() IS NOT NULL
     AND NOT (inet_server_addr() <<= inet '127.0.0.0/8'
              OR inet_server_addr() = inet '::1') THEN
    RAISE EXCEPTION
      'seed_qa.sql refused: this is not a local database (server=%). Every '
      'statement here is an upsert keyed on a REAL account uuid, so running it '
      'against a remote/production project would silently overwrite that '
      'account rather than erroring. There is deliberately NO override flag: if '
      'you genuinely need to seed a remote project, delete this block in a '
      'branch and say so in the commit, so the decision is reviewable.',
      inet_server_addr();
  END IF;
END
$seed_guard$;

-- NOTE: Supabase local uses GoTrue (auth.users). Use the signup API or
-- the Supabase Dashboard's "Create user" button for the actual auth user.
-- This script seeds the public.users row and related profile tables.

-- ── 1. Insert QA user into public.users ──────────────────────────────────

INSERT INTO public.users (
  id,
  email,
  full_name,
  subscription_status,
  subscription_expires_at,
  telegram_chat_id,
  telegram_connected,
  ai_chat_started_at,
  onboarding_completed,
  last_active_at,
  created_at
)
VALUES (
  '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',   -- fixed UUID for QA user
  'test6@gmail.com',
  'QA Tester',
  'free',
  NULL,
  NULL,
  false,
  NOW(),
  true,
  NOW(),
  NOW()
)
ON CONFLICT (id) DO UPDATE
  SET email               = EXCLUDED.email,
      full_name           = EXCLUDED.full_name,
      subscription_status = EXCLUDED.subscription_status,
      onboarding_completed = EXCLUDED.onboarding_completed,
      last_active_at      = NOW();

-- ── 2. Insert QA user profile ────────────────────────────────────────────

INSERT INTO public.user_profile (
  user_id,
  date_of_birth,
  gender,
  height_cm,
  current_weight_kg,
  target_weight_kg,
  primary_goal,
  fitness_experience,
  days_per_week,
  equipment_access,
  activity_level,
  diet_preference,
  injuries,
  bmr,
  tdee
)
VALUES (
  '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',
  '1995-06-15',
  'male',
  175,
  75.0,
  70.0,
  'build_muscle',
  'beginner',
  4,
  'basic_gym',
  'moderate',
  'vegetarian',
  '',
  1800,
  2200
)
ON CONFLICT (user_id) DO UPDATE
  SET height_cm         = EXCLUDED.height_cm,
      current_weight_kg = EXCLUDED.current_weight_kg,
      primary_goal      = EXCLUDED.primary_goal;

-- ── 3. Insert QA user preferences ───────────────────────────────────────

INSERT INTO public.user_preferences (
  user_id,
  motivational_style,
  biggest_obstacle,
  preferred_language,
  coaching_notes
)
VALUES (
  '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',
  'encouraging',
  'consistency',
  'English',
  ''
)
ON CONFLICT (user_id) DO NOTHING;

-- ── 4. Insert QA user progress ───────────────────────────────────────────

INSERT INTO public.user_progress (
  user_id,
  current_phase,
  current_week,
  phase_started_at,
  plan_generated_at,
  total_workouts_done,
  current_streak_weeks,
  detected_experience_level
)
VALUES (
  '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',
  1,
  1,
  NOW() - INTERVAL '7 days',
  NOW() - INTERVAL '7 days',
  3,
  0,
  'beginner'
)
ON CONFLICT (user_id) DO UPDATE
  SET current_phase       = EXCLUDED.current_phase,
      current_week        = EXCLUDED.current_week,
      total_workouts_done = EXCLUDED.total_workouts_done;

-- ── 5. Sample workout log for QA user ───────────────────────────────────

INSERT INTO public.workout_logs (
  id,
  user_id,
  exercise_name,
  logged_at,
  date,
  sets_completed,
  reps_completed,
  weight_kg,
  rpe,
  is_pr
)
VALUES (
  '10000000-0000-0000-0000-000000000001',
  '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',
  'Bench Press',
  NOW() - INTERVAL '1 day',
  (NOW() - INTERVAL '1 day')::date,
  3,
  10,
  60.0,
  7,
  false
)
ON CONFLICT (id) DO NOTHING;

-- ── 6. Sample nutrition log for QA user ─────────────────────────────────

INSERT INTO public.nutrition_logs (
  id,
  user_id,
  date,
  total_calories,
  total_protein,
  total_carbs,
  total_fat,
  meal_type,
  created_at
)
VALUES (
  '20000000-0000-0000-0000-000000000001',
  '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',
  CURRENT_DATE,
  1650,
  110,
  180,
  45,
  'lunch',
  NOW()
)
ON CONFLICT (id) DO NOTHING;

-- ── 7. Sample weight log for QA user ────────────────────────────────────

INSERT INTO public.weight_logs (
  id,
  user_id,
  date,
  weight_kg,
  created_at
)
SELECT
  -- DETERMINISTIC id per day-offset, not gen_random_uuid(). With a random id a
  -- bare `ON CONFLICT DO NOTHING` has no arbiter to conflict ON, so it never
  -- fires: every run inserted 7 MORE rows. This file is meant to be idempotent
  -- and every other block here is; this one silently was not.
  md5('qa-seed-weight-' || i)::uuid,
  '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',
  CURRENT_DATE - (i || ' days')::interval,
  75.0 - (i * 0.1),
  NOW() - (i || ' days')::interval
FROM generate_series(0, 6) AS i
ON CONFLICT (id) DO NOTHING;

-- ── 8. Sample streak for QA user ────────────────────────────────────────

INSERT INTO public.streaks (
  id,
  user_id,
  week_start,
  workouts_planned,
  workouts_completed,
  is_streak_maintained,
  created_at
)
VALUES (
  '30000000-0000-0000-0000-000000000001',
  '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',
  date_trunc('week', CURRENT_DATE),
  4,
  3,
  true,
  NOW()
)
ON CONFLICT (id) DO NOTHING;

-- ── 9. Mark QA user as free (no subscription) ───────────────────────────
-- This is the default state. Tests that need PRO use TestDataHelper.setProUser()
-- which writes to Hive configBox, not Supabase.

-- ── VERIFICATION ─────────────────────────────────────────────────────────
-- After running this seed, verify:
--   SELECT id, email, subscription_status FROM public.users
--     WHERE email = 'test6@gmail.com';
-- Expected: 1 row, subscription_status = 'free'
