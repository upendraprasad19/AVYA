-- test/sql/oi46_daily_cap_triggers_live_verify.sql
--
-- 2026-07-29 — Live-Postgres verification of the three new triggers added
-- for OI-46 (migrations 111, 112) plus the IST-boundary fix to the
-- pre-existing food_text trigger (migration 113).
--
-- Why this file exists
-- --------------------
-- Source-grep contract tests (test/contracts/chat_app_daily_cap_test.dart,
-- vision_analysis_daily_cap_test.dart, onboarding_required_fields_test.dart)
-- can prove the migration files + ai-proxy error-mapping strings exist, but
-- CANNOT prove the trigger actually rejects the 11th/16th same-day row on
-- live Postgres, that PRO correctly bypasses the chat cap, or that an
-- already-completed onboarding row survives an unrelated field update. This
-- file runs the real INSERT/UPDATE sequences against live Postgres in a
-- transaction that ROLLBACKs at the end — same pattern as
-- test/sql/onconflict_live_arbiter.sql (see that file for the harness
-- rationale). Reuses that file's companion script unmodified:
--
--   dart run scripts/check_onconflict_live_arbiter.dart \
--       --sql test/sql/oi46_daily_cap_triggers_live_verify.sql
--
-- (The script is fully generic — it just posts the given SQL file to the
-- Management API and parses `_v_results` rows. No script duplication
-- needed for a second SQL test file.)
--
-- PL/pgSQL note (fixed after the first draft failed live, 2026-07-29):
-- explicit `SAVEPOINT`/`ROLLBACK TO SAVEPOINT` statements are NOT valid
-- inside a PL/pgSQL block — PL/pgSQL provides savepoint-equivalent
-- semantics implicitly via nested `BEGIN ... EXCEPTION WHEN ... END`
-- blocks (each one establishes an implicit savepoint on entry, released
-- automatically when the handler catches an exception). This file uses
-- ONLY nested BEGIN/EXCEPTION/END, matching onconflict_live_arbiter.sql's
-- real (not its comment's shorthand) pattern.
--
-- Status: RUN LIVE 2026-07-29 against migrations 111/112/113 immediately
-- after they were applied — all 7 cases returned status='ok'. Case 3 (vision
-- combined cap) was UPDATED the same day, in the usage-counter-race batch,
-- to expect the migration-114-raised cap of 20 (was 15) — RE-RUN LIVE
-- 2026-07-30T06:06:57+05:30 immediately after migration 114's apply (via
-- direct execute_sql, the check_onconflict_live_arbiter.dart wrapper hit an
-- unrelated Management-API token-privilege 403): status='ok', 20 rows
-- succeeded, 21st raised P0001 'vision_analysis_daily_limit_reached
-- (cap=20)'. Re-run the full file any time after a change to any of the
-- four trigger functions.
--
-- closes-diagnose: f4a19c, c9e3b1

BEGIN;

CREATE TEMP TABLE _v_results (
  label    text PRIMARY KEY,
  status   text NOT NULL,        -- 'ok' | 'fail'
  sqlstate text,
  msg      text
) ON COMMIT DROP;

DO $outer$
DECLARE
  v_free_chat_user  uuid := '00000000-0000-0000-0000-0000000b46c1'::uuid;  -- free-tier chat cap
  v_pro_chat_user    uuid := '00000000-0000-0000-0000-0000000b46c2'::uuid; -- PRO chat exemption
  v_vision_user      uuid := '00000000-0000-0000-0000-0000000b46c3'::uuid; -- combined vision cap
  v_onboard_user     uuid := '00000000-0000-0000-0000-0000000b46c4'::uuid; -- onboarding transition gate
  v_now              timestamptz := now();
  i                  int;
BEGIN
  -- Best-effort synthetic user seeding — mirrors onconflict_live_arbiter.sql.
  BEGIN
    INSERT INTO auth.users (id, email, created_at) VALUES
      (v_free_chat_user, 'test+oi46-free@avya.local', v_now),
      (v_pro_chat_user, 'test+oi46-pro@avya.local', v_now),
      (v_vision_user, 'test+oi46-vision@avya.local', v_now),
      (v_onboard_user, 'test+oi46-onboard@avya.local', v_now)
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name) VALUES
      (v_free_chat_user, 'test+oi46-free@avya.local', 'oi46 free'),
      (v_pro_chat_user, 'test+oi46-pro@avya.local', 'oi46 pro'),
      (v_vision_user, 'test+oi46-vision@avya.local', 'oi46 vision'),
      (v_onboard_user, 'test+oi46-onboard@avya.local', 'oi46 onboard')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- =====================================================================
  -- Case 1 — chat_app_daily_limit: 10 free-tier 'app' rows succeed, 11th fails.
  BEGIN
    FOR i IN 1..10 LOOP
      INSERT INTO ai_coach_interactions (user_id, channel, user_message, ai_response, model_used, tokens_used)
        VALUES (v_free_chat_user, 'app', 'msg ' || i, '', 'pending', 0);
    END LOOP;
    -- 11th must raise P0001 chat_app_daily_limit_reached
    BEGIN
      INSERT INTO ai_coach_interactions (user_id, channel, user_message, ai_response, model_used, tokens_used)
        VALUES (v_free_chat_user, 'app', 'msg 11', '', 'pending', 0);
      -- If we get here, the trigger did NOT reject — that's a failure.
      INSERT INTO _v_results VALUES ('chat_app_daily_limit_11th_row_rejected', 'fail', NULL,
        'trigger did not raise on the 11th free-tier app row');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM LIKE '%chat_app_daily_limit_reached%' THEN
        INSERT INTO _v_results VALUES ('chat_app_daily_limit_11th_row_rejected', 'ok', 'P0001', SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('chat_app_daily_limit_11th_row_rejected', 'fail', 'P0001',
          'raised P0001 but wrong message: ' || SQLERRM);
      END IF;
    END;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('chat_app_daily_limit_11th_row_rejected', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 2 — PRO exemption: 11 'app' rows for a PRO user all succeed.
  BEGIN
    INSERT INTO subscriptions (user_id, plan, status, start_date, end_date)
      VALUES (v_pro_chat_user, 'yearly', 'active', v_now, v_now + interval '300 days');
    FOR i IN 1..11 LOOP
      INSERT INTO ai_coach_interactions (user_id, channel, user_message, ai_response, model_used, tokens_used)
        VALUES (v_pro_chat_user, 'app', 'pro msg ' || i, '', 'pending', 0);
    END LOOP;
    INSERT INTO _v_results VALUES ('chat_app_pro_exemption_11_rows_ok', 'ok', NULL, '11 rows inserted, no cap');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('chat_app_pro_exemption_11_rows_ok', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 3 — vision_analysis_daily_limit: 20 combined scan_meal/cart_auditor
  -- rows succeed, 21st (either channel) fails. Raised from 15/16th via
  -- migration 114 (usage-counter-race batch, 2026-07-29, same day as
  -- migration 111 that this case originally verified) — round-1 review of
  -- that batch caught this file still hardcoding the superseded 15/16
  -- values, which would have silently false-failed the moment migration 114
  -- went live while this file didn't change with it.
  BEGIN
    FOR i IN 1..20 LOOP
      INSERT INTO ai_coach_interactions (user_id, channel, user_message, ai_response, model_used, tokens_used)
        VALUES (
          v_vision_user,
          CASE WHEN i % 2 = 0 THEN 'scan_meal' ELSE 'cart_auditor' END,
          'vision ' || i, '', 'pending', 0
        );
    END LOOP;
    BEGIN
      INSERT INTO ai_coach_interactions (user_id, channel, user_message, ai_response, model_used, tokens_used)
        VALUES (v_vision_user, 'scan_meal', 'vision 21', '', 'pending', 0);
      INSERT INTO _v_results VALUES ('vision_combined_cap_21st_row_rejected', 'fail', NULL,
        'trigger did not raise on the 21st combined vision row');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM LIKE '%vision_analysis_daily_limit_reached%' THEN
        INSERT INTO _v_results VALUES ('vision_combined_cap_21st_row_rejected', 'ok', 'P0001', SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('vision_combined_cap_21st_row_rejected', 'fail', 'P0001',
          'raised P0001 but wrong message: ' || SQLERRM);
      END IF;
    END;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('vision_combined_cap_21st_row_rejected', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 4 — onboarding transition gate: setting onboarding_completed_at
  -- with a NULL required field is rejected.
  BEGIN
    -- Seed a minimal user_profile row (no onboarding fields yet).
    INSERT INTO user_profile (user_id) VALUES (v_onboard_user)
      ON CONFLICT (user_id) DO NOTHING;
    BEGIN
      UPDATE user_profile SET
        onboarding_completed_at = v_now,
        date_of_birth = '1995-01-01',
        gender = 'male',
        height_cm = 175,
        current_weight_kg = 75,
        target_weight_kg = 70,
        primary_goal = 'muscle_gain',
        fitness_experience = 'beginner',
        days_per_week = 4
        -- equipment_access deliberately omitted (stays NULL) — must reject.
      WHERE user_id = v_onboard_user;
      INSERT INTO _v_results VALUES ('onboarding_gate_rejects_missing_field', 'fail', NULL,
        'trigger did not raise with equipment_access NULL');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM LIKE '%onboarding_completed_with_missing_fields%' THEN
        INSERT INTO _v_results VALUES ('onboarding_gate_rejects_missing_field', 'ok', 'P0001', SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('onboarding_gate_rejects_missing_field', 'fail', 'P0001',
          'raised P0001 but wrong message: ' || SQLERRM);
      END IF;
    END;

    -- Case 5 — legitimate completion (all 9 fields present) succeeds.
    BEGIN
      UPDATE user_profile SET
        onboarding_completed_at = v_now,
        date_of_birth = '1995-01-01',
        gender = 'male',
        height_cm = 175,
        current_weight_kg = 75,
        target_weight_kg = 70,
        primary_goal = 'muscle_gain',
        fitness_experience = 'beginner',
        days_per_week = 4,
        equipment_access = 'full_gym'
      WHERE user_id = v_onboard_user;
      INSERT INTO _v_results VALUES ('onboarding_gate_allows_complete_row', 'ok', NULL, 'all 9 fields present');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO _v_results VALUES ('onboarding_gate_allows_complete_row', 'fail', SQLSTATE, SQLERRM);
    END;

    -- Case 6 — transition already happened (OLD.onboarding_completed_at IS
    -- NOT NULL from case 5, same block) — an unrelated-field update must
    -- NOT re-validate the 9 fields. Null out equipment_access first
    -- (simulating a legitimate Edit Profile field-clear) then update an
    -- unrelated column; this must succeed because the gate only fires on
    -- the NULL -> non-NULL transition of onboarding_completed_at, not on
    -- every subsequent update.
    BEGIN
      UPDATE user_profile SET equipment_access = NULL WHERE user_id = v_onboard_user;
      UPDATE user_profile SET days_per_week = 5 WHERE user_id = v_onboard_user;
      INSERT INTO _v_results VALUES ('onboarding_gate_ignores_post_completion_edits', 'ok', NULL,
        'post-completion edit with a null field succeeded (gate correctly did not re-fire)');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO _v_results VALUES ('onboarding_gate_ignores_post_completion_edits', 'fail', SQLSTATE, SQLERRM);
    END;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('onboarding_gate_case_group', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 7 — migration 113: enforce_food_text_daily_limit's deployed
  -- source uses the Asia/Kolkata boundary, not bare date_trunc('day', now()).
  BEGIN
    IF pg_get_functiondef('enforce_food_text_daily_limit'::regproc) LIKE '%Asia/Kolkata%'
       AND pg_get_functiondef('enforce_food_text_daily_limit'::regproc) NOT LIKE '%date_trunc(''day'', now())%'
    THEN
      INSERT INTO _v_results VALUES ('food_text_trigger_ist_boundary_fixed', 'ok', NULL,
        'deployed function uses Asia/Kolkata boundary');
    ELSE
      INSERT INTO _v_results VALUES ('food_text_trigger_ist_boundary_fixed', 'fail', NULL,
        'deployed function still uses the bare UTC-anchored date_trunc boundary');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('food_text_trigger_ist_boundary_fixed', 'fail', SQLSTATE, SQLERRM);
  END;

END;
$outer$;

SELECT label, status, sqlstate, msg FROM _v_results ORDER BY label;

ROLLBACK;
