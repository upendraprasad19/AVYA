-- test/sql/two_user_cross_account.sql
--
-- WI-2 (regression-prevention batch) — live-Postgres TWO-USER cross-account
-- isolation harness. Run via the generic runner:
--   dart run scripts/check_onconflict_live_arbiter.dart \
--     --sql test/sql/two_user_cross_account.sql
--
-- Why this file exists
-- --------------------
-- The catastrophic class (diagnose d4b8e2 + f7e3a1): a sync natural key that
-- omitted user_id let two users' rows COLLIDE on the cloud — Bob's upsert
-- either 23505'd or DO-UPDATE-overwrote Alice's row (silent cross-account data
-- corruption that SCALES with the user base). Migrations 082/083 made every
-- per-user natural key user-INCLUSIVE. The suite had NO two-user dimension to
-- prove it. This harness inserts BOTH a synthetic Alice and Bob with IDENTICAL
-- natural-key values (same date / name / workout_log_id) and asserts both rows
-- coexist (count == 2 for that key across the two users). If a key were ever
-- user-less again, Bob would collapse onto Alice → count == 1 → status='fail'.
--
-- Everything runs in BEGIN ... ROLLBACK so nothing persists. Each table is its
-- own savepoint+exception block.
--
-- related-diagnose: d4b8e2, f7e3a1

BEGIN;

CREATE TEMP TABLE _v_results (
  label    text PRIMARY KEY,
  status   text NOT NULL,        -- 'ok' | 'fail'
  sqlstate text,
  msg      text
) ON COMMIT DROP;

DO $outer$
DECLARE
  v_alice uuid := '00000000-0000-0000-0000-0000000a11ce'::uuid;
  v_bob   uuid := '00000000-0000-0000-0000-0000000b0bbb'::uuid;
  v_date  date := current_date;
  v_now   timestamptz := now();
  v_cnt   int;
  v_shared_wlog uuid := '00000000-0000-0000-0000-00000000f00d'::uuid;
BEGIN
  -- Seed both synthetic users so FK-bearing inserts don't 23503.
  BEGIN
    INSERT INTO auth.users (id, email, created_at)
      VALUES (v_alice, 'test+alice@avya.local', v_now), (v_bob, 'test+bob@avya.local', v_now)
      ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name)
      VALUES (v_alice, 'test+alice@avya.local', 'Alice'), (v_bob, 'test+bob@avya.local', 'Bob')
      ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- ===== weight_logs (user_id, date) — d4b8e2 =====
  BEGIN
    INSERT INTO public.weight_logs (user_id, date, weight_kg) VALUES (v_alice, v_date, 70)
      ON CONFLICT (user_id, date) DO UPDATE SET weight_kg = EXCLUDED.weight_kg;
    INSERT INTO public.weight_logs (user_id, date, weight_kg) VALUES (v_bob, v_date, 80)
      ON CONFLICT (user_id, date) DO UPDATE SET weight_kg = EXCLUDED.weight_kg;
    SELECT count(*) INTO v_cnt FROM public.weight_logs WHERE date = v_date AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('weight_logs:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('weight_logs:two_user', 'fail', '00000', format('cross-user collapse: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('weight_logs:two_user', 'fail', SQLSTATE, SQLERRM); END;

  -- ===== sleep_logs (user_id, date) — d4b8e2 =====
  BEGIN
    INSERT INTO public.sleep_logs (user_id, date, duration_hrs) VALUES (v_alice, v_date, 8)
      ON CONFLICT (user_id, date) DO UPDATE SET duration_hrs = EXCLUDED.duration_hrs;
    INSERT INTO public.sleep_logs (user_id, date, duration_hrs) VALUES (v_bob, v_date, 6)
      ON CONFLICT (user_id, date) DO UPDATE SET duration_hrs = EXCLUDED.duration_hrs;
    SELECT count(*) INTO v_cnt FROM public.sleep_logs WHERE date = v_date AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('sleep_logs:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('sleep_logs:two_user', 'fail', '00000', format('cross-user collapse: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('sleep_logs:two_user', 'fail', SQLSTATE, SQLERRM); END;

  -- ===== daily_steps (user_id, date) =====
  BEGIN
    INSERT INTO public.daily_steps (user_id, date, steps) VALUES (v_alice, v_date, 1000)
      ON CONFLICT (user_id, date) DO UPDATE SET steps = EXCLUDED.steps;
    INSERT INTO public.daily_steps (user_id, date, steps) VALUES (v_bob, v_date, 2000)
      ON CONFLICT (user_id, date) DO UPDATE SET steps = EXCLUDED.steps;
    SELECT count(*) INTO v_cnt FROM public.daily_steps WHERE date = v_date AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('daily_steps:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('daily_steps:two_user', 'fail', '00000', format('cross-user collapse: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('daily_steps:two_user', 'fail', SQLSTATE, SQLERRM); END;

  -- ===== water_logs (user_id, date) =====
  BEGIN
    INSERT INTO public.water_logs (user_id, date, total_ml) VALUES (v_alice, v_date, 250)
      ON CONFLICT (user_id, date) DO UPDATE SET total_ml = EXCLUDED.total_ml;
    INSERT INTO public.water_logs (user_id, date, total_ml) VALUES (v_bob, v_date, 500)
      ON CONFLICT (user_id, date) DO UPDATE SET total_ml = EXCLUDED.total_ml;
    SELECT count(*) INTO v_cnt FROM public.water_logs WHERE date = v_date AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('water_logs:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('water_logs:two_user', 'fail', '00000', format('cross-user collapse: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('water_logs:two_user', 'fail', SQLSTATE, SQLERRM); END;

  -- ===== nutrition_logs (user_id, date, meal_type) =====
  BEGIN
    INSERT INTO public.nutrition_logs (id, user_id, date, meal_type, total_calories) VALUES (gen_random_uuid(), v_alice, v_date, 'lunch', 100)
      ON CONFLICT (user_id, date, meal_type) DO UPDATE SET total_calories = EXCLUDED.total_calories;
    INSERT INTO public.nutrition_logs (id, user_id, date, meal_type, total_calories) VALUES (gen_random_uuid(), v_bob, v_date, 'lunch', 200)
      ON CONFLICT (user_id, date, meal_type) DO UPDATE SET total_calories = EXCLUDED.total_calories;
    SELECT count(*) INTO v_cnt FROM public.nutrition_logs WHERE date = v_date AND meal_type = 'lunch' AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('nutrition_logs:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('nutrition_logs:two_user', 'fail', '00000', format('cross-user collapse: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('nutrition_logs:two_user', 'fail', SQLSTATE, SQLERRM); END;

  -- ===== user_saved_meals (user_id, name) — f7e3a1 (same-named meal, two users) =====
  BEGIN
    INSERT INTO public.user_saved_meals (user_id, name, items) VALUES (v_alice, 'Protein Bowl', '[]'::jsonb)
      ON CONFLICT (user_id, name) DO UPDATE SET items = EXCLUDED.items;
    INSERT INTO public.user_saved_meals (user_id, name, items) VALUES (v_bob, 'Protein Bowl', '[]'::jsonb)
      ON CONFLICT (user_id, name) DO UPDATE SET items = EXCLUDED.items;
    SELECT count(*) INTO v_cnt FROM public.user_saved_meals WHERE name = 'Protein Bowl' AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('user_saved_meals:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('user_saved_meals:two_user', 'fail', '00000', format('cross-user meal theft: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('user_saved_meals:two_user', 'fail', SQLSTATE, SQLERRM); END;

  -- ===== workout_logs (user_id, date, workout_name) — d4b8e2 root =====
  BEGIN
    INSERT INTO public.workout_logs (id, user_id, date, workout_name, logged_at) VALUES (gen_random_uuid(), v_alice, v_date, 'Push Day', v_now)
      ON CONFLICT (user_id, date, workout_name) DO UPDATE SET logged_at = EXCLUDED.logged_at;
    INSERT INTO public.workout_logs (id, user_id, date, workout_name, logged_at) VALUES (gen_random_uuid(), v_bob, v_date, 'Push Day', v_now)
      ON CONFLICT (user_id, date, workout_name) DO UPDATE SET logged_at = EXCLUDED.logged_at;
    SELECT count(*) INTO v_cnt FROM public.workout_logs WHERE date = v_date AND workout_name = 'Push Day' AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('workout_logs:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('workout_logs:two_user', 'fail', '00000', format('cross-user collapse: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('workout_logs:two_user', 'fail', SQLSTATE, SQLERRM); END;

  -- ===== workout_log_exercises — d4b8e2 corruptive DO UPDATE =====
  -- SAME synthetic workout_log_id across two users — pre-082 the key lacked
  -- user_id, so Bob's set DO-UPDATE-overwrote Alice's. User-inclusive key → 2 rows.
  BEGIN
    INSERT INTO public.workout_log_exercises (workout_log_id, exercise_id, exercise_name, set_number, user_id, completed_at)
      VALUES (v_shared_wlog, 'sharedex', 'Alice', 1, v_alice, v_now)
      ON CONFLICT (user_id, workout_log_id, exercise_id, set_number) DO UPDATE SET completed_at = EXCLUDED.completed_at;
    INSERT INTO public.workout_log_exercises (workout_log_id, exercise_id, exercise_name, set_number, user_id, completed_at)
      VALUES (v_shared_wlog, 'sharedex', 'Bob', 1, v_bob, v_now)
      ON CONFLICT (user_id, workout_log_id, exercise_id, set_number) DO UPDATE SET completed_at = EXCLUDED.completed_at;
    SELECT count(*) INTO v_cnt FROM public.workout_log_exercises WHERE workout_log_id::text = v_shared_wlog::text AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('workout_log_exercises:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('workout_log_exercises:two_user', 'fail', '00000', format('cross-user DO-UPDATE corruption: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('workout_log_exercises:two_user', 'fail', SQLSTATE, SQLERRM); END;

  -- ===== workout_log_sets — d4b8e2 corruptive DO UPDATE =====
  BEGIN
    INSERT INTO public.workout_log_sets (workout_log_id, exercise_id, set_number, user_id, reps, weight_kg)
      VALUES (v_shared_wlog, 'sharedex', 1, v_alice, 5, 50)
      ON CONFLICT (user_id, workout_log_id, exercise_id, set_number) DO UPDATE SET reps = EXCLUDED.reps;
    INSERT INTO public.workout_log_sets (workout_log_id, exercise_id, set_number, user_id, reps, weight_kg)
      VALUES (v_shared_wlog, 'sharedex', 1, v_bob, 9, 90)
      ON CONFLICT (user_id, workout_log_id, exercise_id, set_number) DO UPDATE SET reps = EXCLUDED.reps;
    SELECT count(*) INTO v_cnt FROM public.workout_log_sets WHERE workout_log_id::text = v_shared_wlog::text AND user_id IN (v_alice, v_bob);
    IF v_cnt = 2 THEN INSERT INTO _v_results VALUES ('workout_log_sets:two_user', 'ok', NULL, NULL);
    ELSE INSERT INTO _v_results VALUES ('workout_log_sets:two_user', 'fail', '00000', format('cross-user DO-UPDATE corruption: count=%s (expected 2)', v_cnt)); END IF;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _v_results VALUES ('workout_log_sets:two_user', 'fail', SQLSTATE, SQLERRM); END;

END
$outer$;

SELECT label, status, sqlstate, msg FROM _v_results ORDER BY label;

ROLLBACK;
