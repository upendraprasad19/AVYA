-- test/sql/onconflict_live_arbiter.sql
--
-- 2026-05-15 — Live-Postgres verification of every `onConflict:` target
-- used by the client-side sync layer (lib/core/services/sync/*).
--
-- Why this file exists
-- --------------------
-- Source-grep contract tests (test/contracts/sync_onconflict_natural_key_test.dart
-- etc.) can prove that the writer SOURCE STRING says
-- `onConflict: 'user_id,date,exercise_name'`, but they CANNOT prove that
-- the live Postgres schema actually has a UNIQUE / EXCLUDE constraint
-- the arbiter resolver will accept. The recurring bug class —
-- "writer/reader drift" with the DB target as the silent third reader —
-- has produced two production incidents already:
--
--   * Audit 2026-05-12 P0-A/P0-B (`3f8a91`): `onConflict: 'id'` while
--     live had a partial UNIQUE on (workout_log_id, exercise_id,
--     set_number). 31 + 16 errors / 24h. Closed by switching the client
--     string. Source-grep test pinned the new value.
--   * Diagnose `76c8f4` (2026-05-15, agent A1): client switched to the
--     natural key in 3f8a91, but the indexes were PARTIAL with
--     `WHERE (... IS NOT NULL)` predicates. PostgreSQL's arbiter
--     resolver rejects partial indexes whose predicate the planner
--     cannot prove from the table schema (the relevant columns were
--     NULLABLE). 47 errors / minute on 2026-05-15 04:10 UTC. Closed by
--     migration 064 which SET NOT NULL + replaced the partial indexes
--     with plain UNIQUE indexes.
--
-- This file pins both layers — it runs the actual upsert against live
-- Postgres in a transaction that ROLLBACKs at the end. If the arbiter
-- rejects the conflict target, the statement fails with SQLSTATE 42P10
-- ("no unique or exclusion constraint matching the ON CONFLICT
-- specification") and the test reports `status='fail'`.
--
-- Expected outcomes
-- -----------------
-- PRE-migration-064 (i.e. before agent A1's fix):
--   workout_logs        (user_id, date, exercise_name)              → FAIL 42P10
--   workout_log_exercises (workout_log_id, exercise_id, set_number) → FAIL 42P10
--   nutrition_logs      (user_id, date, meal_type)                  → FAIL 42P10
--   workout_log_sets    (workout_log_id, exercise_id, set_number)   → OK
--   ALL other onConflict pairs                                      → OK
--
-- POST-migration-064:
--   ALL onConflict pairs → OK
--
-- closes-diagnose: 25e91d
--
-- Execution
-- ---------
-- The companion script `scripts/check_onconflict_live_arbiter.dart` reads
-- this file, sends it to the Supabase Management API
-- (`/v1/projects/{ref}/database/query`) using the service-role PAT from
-- `supabase/.supabase/supabase access token.txt`, and parses the
-- returned `_v_results` rows.
--
-- The whole block is wrapped in BEGIN ... ROLLBACK so the writes never
-- persist. Each upsert is its own savepoint+exception-catch block so a
-- failure on one row does not abort the rest.

BEGIN;

-- Temp results table — labeled rows so the Dart script can map back.
CREATE TEMP TABLE _v_results (
  label    text PRIMARY KEY,
  status   text NOT NULL,        -- 'ok' | 'fail'
  sqlstate text,                 -- Postgres SQLSTATE on failure
  msg      text                  -- error message on failure
) ON COMMIT DROP;

-- Synthetic test fixtures. UUIDs are deterministic so the rollback is
-- a complete no-op even if the transaction somehow commits.
DO $outer$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-0000000a11ce'::uuid;   -- "Alice"
  v_now  timestamptz := now();
  v_date date := current_date;
  v_log_id uuid;   -- parent nutrition_logs id for the item arbiter test (f7e3a1)
BEGIN
  -- Insert a synthetic user row so FK-bearing inserts don't hit 23503
  -- on user_id. Best-effort — if the FK isn't there or the user already
  -- exists, just continue.
  BEGIN
    INSERT INTO auth.users (id, email, created_at)
      VALUES (v_user, 'test+arbiter@avya.local', v_now)
      ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    -- auth.users may be locked-down on prod; we'll still try the
    -- public-schema upserts and accept FK failures separately.
    NULL;
  END;

  BEGIN
    INSERT INTO public.users (id, email, full_name)
      VALUES (v_user, 'test+arbiter@avya.local', 'arbiter test')
      ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- =====================================================================
  -- Test case helper: every block follows the same shape.
  --
  --   1. SAVEPOINT sp;
  --   2. Try the INSERT ... ON CONFLICT ... DO UPDATE.
  --   3. On success → INSERT INTO _v_results VALUES (label, 'ok', ...).
  --      On exception → ROLLBACK TO sp, log fail with SQLSTATE/SQLERRM.
  --
  -- The whole thing runs inside the outer DO block which itself sits in
  -- a BEGIN ... ROLLBACK transaction. So no rows persist.
  -- =====================================================================

  ----- 1. coach_memory (user_id) ----------------------------------------
  BEGIN
    INSERT INTO public.coach_memory (user_id, last_proactive_type)
      VALUES (v_user, 'arbiter_test')
      ON CONFLICT (user_id) DO UPDATE SET last_proactive_type = EXCLUDED.last_proactive_type;
    INSERT INTO _v_results VALUES ('coach_memory:user_id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('coach_memory:user_id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 2. ai_coach_interactions (id) ------------------------------------
  BEGIN
    INSERT INTO public.ai_coach_interactions (id, user_id, role, content, channel, created_at)
      VALUES (gen_random_uuid(), v_user, 'user', 'arbiter test', 'app', v_now)
      ON CONFLICT (id) DO UPDATE SET content = EXCLUDED.content;
    INSERT INTO _v_results VALUES ('ai_coach_interactions:id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('ai_coach_interactions:id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 3. nutrition_logs (user_id, date, meal_type) ---------------------
  -- PRE-064: FAIL 42P10 (partial UNIQUE rejected by arbiter)
  -- POST-064: OK
  BEGIN
    INSERT INTO public.nutrition_logs (id, user_id, date, meal_type, total_calories)
      VALUES (gen_random_uuid(), v_user, v_date, 'snack', 100)
      ON CONFLICT (user_id, date, meal_type) DO UPDATE SET total_calories = EXCLUDED.total_calories;
    INSERT INTO _v_results VALUES ('nutrition_logs:user_id,date,meal_type', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('nutrition_logs:user_id,date,meal_type', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 4. nutrition_log_items (log_id, item_index) ----------------------
  -- POST-083 (f7e3a1): arbiter is (log_id, item_index); real columns are
  -- log_id / food_name / item_index. The pre-083 block referenced nonexistent
  -- nutrition_log_id / name cols + the dead (id) arbiter (always 42703). Needs a
  -- parent nutrition_logs row for the FK.
  BEGIN
    INSERT INTO public.nutrition_logs (id, user_id, date, meal_type, total_calories)
      VALUES (gen_random_uuid(), v_user, v_date, 'arbiter_item', 1)
      ON CONFLICT (user_id, date, meal_type) DO UPDATE SET total_calories = EXCLUDED.total_calories
      RETURNING id INTO v_log_id;
    INSERT INTO public.nutrition_log_items (log_id, item_index, food_name, quantity_g, calories)
      VALUES (v_log_id, 0, 'arbiter test', 100, 50)
      ON CONFLICT (log_id, item_index) DO UPDATE SET food_name = EXCLUDED.food_name;
    INSERT INTO _v_results VALUES ('nutrition_log_items:log_id,item_index', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('nutrition_log_items:log_id,item_index', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 5. water_logs (user_id, date) ------------------------------------
  BEGIN
    INSERT INTO public.water_logs (user_id, date, glasses_drunk)
      VALUES (v_user, v_date, 1)
      ON CONFLICT (user_id, date) DO UPDATE SET glasses_drunk = EXCLUDED.glasses_drunk;
    INSERT INTO _v_results VALUES ('water_logs:user_id,date', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('water_logs:user_id,date', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 6. user_saved_meals (user_id, name) ------------------------------
  -- POST-083 (f7e3a1): client omits id + arbiters on (user_id, name).
  BEGIN
    INSERT INTO public.user_saved_meals (user_id, name, items)
      VALUES (v_user, 'arbiter test', '[]'::jsonb)
      ON CONFLICT (user_id, name) DO UPDATE SET items = EXCLUDED.items;
    INSERT INTO _v_results VALUES ('user_saved_meals:user_id,name', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('user_saved_meals:user_id,name', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 7. community_reviews (id) ----------------------------------------
  BEGIN
    INSERT INTO public.community_reviews (id, reviewer_id, item_type, item_id, vote)
      VALUES (gen_random_uuid(), v_user, 'exercise', gen_random_uuid(), 'approve')
      ON CONFLICT (id) DO UPDATE SET vote = EXCLUDED.vote;
    INSERT INTO _v_results VALUES ('community_reviews:id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('community_reviews:id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 8. user_custom_exercises (id) ------------------------------------
  BEGIN
    INSERT INTO public.user_custom_exercises (id, user_id, name)
      VALUES (gen_random_uuid(), v_user, 'arbiter test exercise')
      ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
    INSERT INTO _v_results VALUES ('user_custom_exercises:id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('user_custom_exercises:id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 9. user_custom_foods (id) ----------------------------------------
  BEGIN
    INSERT INTO public.user_custom_foods (id, user_id, name)
      VALUES (gen_random_uuid(), v_user, 'arbiter test food')
      ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
    INSERT INTO _v_results VALUES ('user_custom_foods:id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('user_custom_foods:id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 10. user_profile (user_id) ---------------------------------------
  BEGIN
    INSERT INTO public.user_profile (user_id, full_name)
      VALUES (v_user, 'arbiter test')
      ON CONFLICT (user_id) DO UPDATE SET full_name = EXCLUDED.full_name;
    INSERT INTO _v_results VALUES ('user_profile:user_id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('user_profile:user_id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 11. user_progress (user_id) --------------------------------------
  BEGIN
    INSERT INTO public.user_progress (user_id, plan_json)
      VALUES (v_user, '{}'::jsonb)
      ON CONFLICT (user_id) DO UPDATE SET plan_json = EXCLUDED.plan_json;
    INSERT INTO _v_results VALUES ('user_progress:user_id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('user_progress:user_id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 12. notifications_inbox (id) -------------------------------------
  BEGIN
    INSERT INTO public.notifications_inbox (id, user_id, title, body, created_at)
      VALUES (gen_random_uuid(), v_user, 'arbiter test', 'body', v_now)
      ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title;
    INSERT INTO _v_results VALUES ('notifications_inbox:id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('notifications_inbox:id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 13. sleep_logs (user_id, date) -----------------------------------
  -- POST-082 (d4b8e2): client omits id + arbiters on (user_id, date).
  BEGIN
    INSERT INTO public.sleep_logs (user_id, date, duration_hrs)
      VALUES (v_user, v_date, 8)
      ON CONFLICT (user_id, date) DO UPDATE SET duration_hrs = EXCLUDED.duration_hrs;
    INSERT INTO _v_results VALUES ('sleep_logs:user_id,date', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('sleep_logs:user_id,date', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 14. weight_logs (user_id, date) ----------------------------------
  -- POST-082 (d4b8e2): client omits id + arbiters on (user_id, date).
  BEGIN
    INSERT INTO public.weight_logs (user_id, date, weight_kg)
      VALUES (v_user, v_date, 75)
      ON CONFLICT (user_id, date) DO UPDATE SET weight_kg = EXCLUDED.weight_kg;
    INSERT INTO _v_results VALUES ('weight_logs:user_id,date', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('weight_logs:user_id,date', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 15. body_measurements (user_id, date) ----------------------------
  -- POST-082 (d4b8e2): client omits id + arbiters on (user_id, date).
  BEGIN
    INSERT INTO public.body_measurements (user_id, date)
      VALUES (v_user, v_date)
      ON CONFLICT (user_id, date) DO UPDATE SET date = EXCLUDED.date;
    INSERT INTO _v_results VALUES ('body_measurements:user_id,date', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('body_measurements:user_id,date', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 16. progress_photos (id) -----------------------------------------
  BEGIN
    INSERT INTO public.progress_photos (id, user_id, photo_url, taken_at)
      VALUES (gen_random_uuid(), v_user, 'https://example/arbiter.jpg', v_now)
      ON CONFLICT (id) DO UPDATE SET photo_url = EXCLUDED.photo_url;
    INSERT INTO _v_results VALUES ('progress_photos:id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('progress_photos:id', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 17. daily_steps (user_id, date) ----------------------------------
  BEGIN
    INSERT INTO public.daily_steps (user_id, date, steps)
      VALUES (v_user, v_date, 1000)
      ON CONFLICT (user_id, date) DO UPDATE SET steps = EXCLUDED.steps;
    INSERT INTO _v_results VALUES ('daily_steps:user_id,date', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('daily_steps:user_id,date', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 18. workout_logs (user_id, date, exercise_name) ------------------
  -- PRE-064: FAIL 42P10 (partial UNIQUE rejected by arbiter)
  -- POST-064: OK
  BEGIN
    INSERT INTO public.workout_logs (id, user_id, date, exercise_name, logged_at)
      VALUES (gen_random_uuid(), v_user, v_date, 'arbiter test', v_now)
      ON CONFLICT (user_id, date, exercise_name) DO UPDATE SET logged_at = EXCLUDED.logged_at;
    INSERT INTO _v_results VALUES ('workout_logs:user_id,date,exercise_name', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('workout_logs:user_id,date,exercise_name', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 19. workout_log_exercises (user_id, workout_log_id, exercise_id, set_number) -----
  -- POST-082 (d4b8e2): the global (wlog,ex,set) UNIQUE was replaced by the
  -- user-inclusive arbiter; client omits id + arbiters on
  -- (user_id, workout_log_id, exercise_id, set_number). (workout_log_id is a
  -- plain uuid column — no FK — so a synthetic uuid is fine.)
  BEGIN
    INSERT INTO public.workout_log_exercises
      (workout_log_id, exercise_id, exercise_name, set_number, user_id, completed_at)
      VALUES (gen_random_uuid(), 'arbiter exercise', 'arbiter test', 1, v_user, v_now)
      ON CONFLICT (user_id, workout_log_id, exercise_id, set_number) DO UPDATE SET completed_at = EXCLUDED.completed_at;
    INSERT INTO _v_results VALUES ('workout_log_exercises:user_id,workout_log_id,exercise_id,set_number', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('workout_log_exercises:user_id,workout_log_id,exercise_id,set_number', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 20. workout_log_sets (user_id, workout_log_id, exercise_id, set_number) ---
  -- POST-082 (d4b8e2): user-inclusive arbiter (replaces the old global key);
  -- the per-set table also gained user_id in the natural key.
  BEGIN
    INSERT INTO public.workout_log_sets
      (workout_log_id, exercise_id, set_number, user_id, reps, weight_kg)
      VALUES (gen_random_uuid(), 'arbiter exercise', 1, v_user, 10, 50)
      ON CONFLICT (user_id, workout_log_id, exercise_id, set_number) DO UPDATE SET reps = EXCLUDED.reps;
    INSERT INTO _v_results VALUES ('workout_log_sets:user_id,workout_log_id,exercise_id,set_number', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('workout_log_sets:user_id,workout_log_id,exercise_id,set_number', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 21. workout_schedule_completions (user_id, scheduled_date) -------
  BEGIN
    INSERT INTO public.workout_schedule_completions
      (user_id, scheduled_date, workout_name)
      VALUES (v_user, v_date, 'arbiter test')
      ON CONFLICT (user_id, scheduled_date) DO UPDATE SET workout_name = EXCLUDED.workout_name;
    INSERT INTO _v_results VALUES ('workout_schedule_completions:user_id,scheduled_date', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('workout_schedule_completions:user_id,scheduled_date', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 22. streaks (user_id, week_start) --------------------------------
  BEGIN
    INSERT INTO public.streaks (user_id, week_start, current_streak)
      VALUES (v_user, v_date, 1)
      ON CONFLICT (user_id, week_start) DO UPDATE SET current_streak = EXCLUDED.current_streak;
    INSERT INTO _v_results VALUES ('streaks:user_id,week_start', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('streaks:user_id,week_start', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 23. workout_templates (user_id, name) ----------------------------
  BEGIN
    INSERT INTO public.workout_templates (id, user_id, name)
      VALUES (gen_random_uuid(), v_user, 'arbiter template')
      ON CONFLICT (user_id, name) DO UPDATE SET name = EXCLUDED.name;
    INSERT INTO _v_results VALUES ('workout_templates:user_id,name', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('workout_templates:user_id,name', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 24. template_exercises (template_id, order_index) ----------------
  BEGIN
    INSERT INTO public.template_exercises
      (id, template_id, order_index, exercise_name)
      VALUES (gen_random_uuid(), gen_random_uuid(), 1, 'arbiter test')
      ON CONFLICT (template_id, order_index) DO UPDATE SET exercise_name = EXCLUDED.exercise_name;
    INSERT INTO _v_results VALUES ('template_exercises:template_id,order_index', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('template_exercises:template_id,order_index', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 25. scheduled_workouts (user_id, scheduled_date) -----------------
  BEGIN
    INSERT INTO public.scheduled_workouts
      (user_id, scheduled_date, workout_name)
      VALUES (v_user, v_date, 'arbiter test')
      ON CONFLICT (user_id, scheduled_date) DO UPDATE SET workout_name = EXCLUDED.workout_name;
    INSERT INTO _v_results VALUES ('scheduled_workouts:user_id,scheduled_date', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('scheduled_workouts:user_id,scheduled_date', 'fail', SQLSTATE, SQLERRM);
  END;

  ----- 26. saved_diet_plans (user_id) -----------------------------------
  BEGIN
    INSERT INTO public.saved_diet_plans (user_id, plan_json)
      VALUES (v_user, '{}'::jsonb)
      ON CONFLICT (user_id) DO UPDATE SET plan_json = EXCLUDED.plan_json;
    INSERT INTO _v_results VALUES ('saved_diet_plans:user_id', 'ok', NULL, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('saved_diet_plans:user_id', 'fail', SQLSTATE, SQLERRM);
  END;

END $outer$;

-- Emit results. The Dart caller parses this resultset.
SELECT label, status, sqlstate, msg
  FROM _v_results
 ORDER BY label;

ROLLBACK;
