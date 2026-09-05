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

-- ===========================================================================
-- OI-162 slice 2 (2026-09-05) -- the same three triggers, now backed by
-- consume_quota()/usage_counters instead of count(*) over ai_coach_interactions.
--
-- WHY THESE LIVE HERE rather than in a Dart contract test: source-greps prove
-- the trigger bodies CONTAIN a consume_quota call; only a live INSERT proves the
-- cap still refuses at N+1, that PRO still bypasses, that the unit lands under
-- the right quota_key + IST window, and that an aborted row does not leak a
-- consumed unit. Migration 129's header explains why each is load-bearing.
--
-- ⚠ WHICH OF THESE ACTUALLY DISCRIMINATE — measured, not assumed (2026-09-05).
-- The pre-129 trigger bodies were restored inside a rolled-back transaction and
-- these assertions re-run against them. FIVE OF SEVEN PASSED, i.e. they were
-- green against the very code this slice replaced. Running is not
-- discriminating, and the difference is invisible unless someone runs the
-- experiment. The split, stated so nobody mistakes one kind for the other:
--
--   DISCRIMINATING (fail pre-129, because no ledger row exists at all):
--     slice2_chat_ledger_counts_to_10, slice2_vision_shares_one_key,
--     slice2_food_text_free_10 -- these read `used` and require a number.
--     slice2_pro_consumes_nothing and slice2_aborted_row_refunds_unit were NOT
--     in this group and now are: each gained a guard requiring a REAL ledger
--     row to exist first (see the notes at each). Without those guards both
--     compared NULL to NULL and reported "ok" against pre-129.
--
--   BEHAVIOUR-INVARIANTS (pass pre-129 BY DESIGN, and should):
--     slice2_chat_11th_refused, slice2_vision_21st_refused,
--     slice2_ungated_channel_untouched. The cap firing with the right P0001
--     identifier, and an ungated channel being left alone, must hold under ANY
--     implementation. They are regression tests for the contract, not proof of
--     the ledger. Keeping them is correct; citing them as evidence that slice 2
--     landed is not.
-- ===========================================================================

DO $slice2$
DECLARE
  v_free_user  uuid := '00000000-0000-0000-0000-0000000b46d1'::uuid;
  v_pro_user   uuid := '00000000-0000-0000-0000-0000000b46d2'::uuid;
  v_vis_user   uuid := '00000000-0000-0000-0000-0000000b46d3'::uuid;
  v_now        timestamptz := now();
  v_window     timestamptz := (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata');
  v_used       int;
  v_before     int;
  i            int;
BEGIN
  BEGIN
    INSERT INTO auth.users (id, email, created_at) VALUES
      (v_free_user, 'test+oi162-free@avya.local', v_now),
      (v_pro_user,  'test+oi162-pro@avya.local',  v_now),
      (v_vis_user,  'test+oi162-vis@avya.local',  v_now)
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name) VALUES
      (v_free_user, 'test+oi162-free@avya.local', 'oi162 free'),
      (v_pro_user,  'test+oi162-pro@avya.local',  'oi162 pro'),
      (v_vis_user,  'test+oi162-vis@avya.local',  'oi162 vis')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  -- ⚠ NOT best-effort, unlike the two user seeds above: the PRO assertion is
  -- MEANINGLESS if this row does not exist. Swallowing a failure here makes
  -- `slice2_pro_consumes_nothing` assert about a FREE user, which is exactly
  -- what happened on the first live run — `plan` and `start_date` are NOT NULL
  -- and were omitted, the insert failed silently, and the test then reported
  -- the free cap firing as if it were a product defect. A fixture that
  -- manufactures a state the workflow never produces asserts nothing; a
  -- fixture that silently manufactures the WRONG state asserts something false.
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)
  VALUES (v_pro_user, 'pro_monthly', 'active', v_now, v_now + interval '30 days');

  -- POSITIVE CONTROL for the fixture itself, asserting the exact predicate the
  -- trigger evaluates. Without it, `slice2_pro_consumes_nothing` cannot tell
  -- "PRO correctly bypassed" from "the seed never happened and this is a free
  -- user who has not yet reached 10".
  DECLARE
    v_is_pro bool;
  BEGIN
    SELECT EXISTS (
      SELECT 1 FROM subscriptions
      WHERE user_id = v_pro_user AND status = 'active' AND end_date > now()
    ) INTO v_is_pro;
    INSERT INTO _v_results VALUES ('slice2_fixture_pro_seeded',
      CASE WHEN v_is_pro THEN 'ok' ELSE 'fail' END, NULL,
      'the trigger will see is_pro=' || v_is_pro);
  END;

  -- 1. The ledger is the source: 10 chat inserts leave used=10 under the
  --    'chat_app' key at the IST window start.
  BEGIN
    FOR i IN 1..10 LOOP
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
      VALUES (v_free_user, 'app', 'oi162 slice2 chat ' || i);
    END LOOP;

    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = v_free_user AND quota_key = 'chat_app'
       AND window_start = v_window;

    IF v_used IS DISTINCT FROM 10 THEN
      INSERT INTO _v_results VALUES ('slice2_chat_ledger_counts_to_10', 'fail', NULL,
        'expected used=10 under chat_app at the IST window, got ' || coalesce(v_used::text, 'NO ROW'));
    ELSE
      INSERT INTO _v_results VALUES ('slice2_chat_ledger_counts_to_10', 'ok', NULL,
        'usage_counters.used = 10 for quota_key=chat_app');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('slice2_chat_ledger_counts_to_10', 'fail', SQLSTATE, SQLERRM);
  END;

  -- 1b. The 11th is refused, with the identifier ai-proxy greps.
  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
    VALUES (v_free_user, 'app', 'oi162 slice2 chat 11 must fail');
    INSERT INTO _v_results VALUES ('slice2_chat_11th_refused', 'fail', NULL,
      'the 11th chat insert SUCCEEDED; the cap did not fire');
  EXCEPTION
    WHEN sqlstate 'P0001' THEN
      IF SQLERRM LIKE '%chat_app_daily_limit_reached%' THEN
        INSERT INTO _v_results VALUES ('slice2_chat_11th_refused', 'ok', 'P0001', SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('slice2_chat_11th_refused', 'fail', 'P0001',
          'P0001 raised but the ai-proxy identifier is missing: ' || SQLERRM);
      END IF;
    WHEN OTHERS THEN
      INSERT INTO _v_results VALUES ('slice2_chat_11th_refused', 'fail', SQLSTATE, SQLERRM);
  END;

  -- 2. PRO bypasses the chat cap AND consumes no unit.
  BEGIN
    FOR i IN 1..12 LOOP
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
      VALUES (v_pro_user, 'app', 'oi162 slice2 pro ' || i);
    END LOOP;

    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = v_pro_user AND quota_key = 'chat_app'
       AND window_start = v_window;
    SELECT used INTO v_before FROM public.usage_counters
     WHERE user_id = v_free_user AND quota_key = 'chat_app'
       AND window_start = v_window;

    -- ⚠ PAIRED WITH THE FREE USER DELIBERATELY. "PRO has no counter row" is
    -- ALSO true of the pre-129 count(*) triggers, which write no rows for
    -- anyone — so on its own this assertion passes against the code it is
    -- meant to prove replaced (measured 2026-09-05). Requiring the FREE user's
    -- row to exist in the SAME transaction is what makes it discriminate: the
    -- ledger is demonstrably live, and PRO is absent from it by exemption
    -- rather than by nothing working.
    IF v_before IS NULL THEN
      INSERT INTO _v_results VALUES ('slice2_pro_consumes_nothing', 'fail', NULL,
        'VACUOUS: the free user has no chat_app row either, so "PRO consumed '
        || 'nothing" proves nothing — the ledger is not being written at all.');
    ELSIF v_used IS NOT NULL THEN
      INSERT INTO _v_results VALUES ('slice2_pro_consumes_nothing', 'fail', NULL,
        'PRO wrote a chat_app counter row (used=' || v_used || '); the exemption must precede consume_quota');
    ELSE
      INSERT INTO _v_results VALUES ('slice2_pro_consumes_nothing', 'ok', NULL,
        '12 PRO chat rows and NO counter row, while the free user in the same '
        || 'transaction holds used=' || v_before::text);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('slice2_pro_consumes_nothing', 'fail', SQLSTATE, SQLERRM);
  END;

  -- 3. Vision: ONE shared 20/day budget across both channels. Split 11/9
  --    deliberately -- a per-channel implementation would let both through.
  BEGIN
    FOR i IN 1..11 LOOP
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
      VALUES (v_vis_user, 'scan_meal', 'oi162 slice2 scan ' || i);
    END LOOP;
    FOR i IN 1..9 LOOP
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
      VALUES (v_vis_user, 'cart_auditor', 'oi162 slice2 cart ' || i);
    END LOOP;

    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = v_vis_user AND quota_key = 'vision_analysis'
       AND window_start = v_window;

    IF v_used IS DISTINCT FROM 20 THEN
      INSERT INTO _v_results VALUES ('slice2_vision_shares_one_key', 'fail', NULL,
        'expected used=20 on the shared vision_analysis key, got ' || coalesce(v_used::text, 'NO ROW'));
    ELSE
      INSERT INTO _v_results VALUES ('slice2_vision_shares_one_key', 'ok', NULL,
        '11 scan_meal + 9 cart_auditor = 20 on ONE quota_key');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('slice2_vision_shares_one_key', 'fail', SQLSTATE, SQLERRM);
  END;

  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
    VALUES (v_vis_user, 'cart_auditor', 'oi162 slice2 vision 21 must fail');
    INSERT INTO _v_results VALUES ('slice2_vision_21st_refused', 'fail', NULL,
      'the 21st combined vision insert SUCCEEDED; the shared cap did not fire');
  EXCEPTION
    WHEN sqlstate 'P0001' THEN
      IF SQLERRM LIKE '%vision_analysis_daily_limit_reached%' THEN
        INSERT INTO _v_results VALUES ('slice2_vision_21st_refused', 'ok', 'P0001', SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('slice2_vision_21st_refused', 'fail', 'P0001',
          'P0001 raised but the ai-proxy identifier is missing: ' || SQLERRM);
      END IF;
    WHEN OTHERS THEN
      INSERT INTO _v_results VALUES ('slice2_vision_21st_refused', 'fail', SQLSTATE, SQLERRM);
  END;

  -- 4. An ABORTED row must not leak a consumed unit. The trigger runs inside the
  --    INSERT's transaction, so rolling the row back must roll the unit back --
  --    otherwise a failing downstream constraint silently burns quota.
  BEGIN
    SELECT used INTO v_before FROM public.usage_counters
     WHERE user_id = v_vis_user AND quota_key = 'vision_analysis'
       AND window_start = v_window;

    -- A PL/pgSQL BEGIN...EXCEPTION block IS an implicit savepoint: raising
    -- inside it rolls back everything the block did, including the trigger's
    -- consumed unit. Explicit SAVEPOINT / ROLLBACK TO is a syntax error in
    -- PL/pgSQL (42601) — caught by the first live run of this block, and
    -- invisible to the source-grep contract test, which is the argument for
    -- having both layers.
    BEGIN
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
      VALUES (v_vis_user, 'scan_meal', 'oi162 slice2 aborted row');
      RAISE EXCEPTION 'oi162 deliberate abort';
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = v_vis_user AND quota_key = 'vision_analysis'
       AND window_start = v_window;

    -- ⚠ THE NULL GUARD IS THE WHOLE ASSERTION. Without it this test is
    -- VACUOUS: against the pre-129 count(*) triggers no ledger row exists at
    -- all, so v_before and v_used are both NULL, NULL IS NOT DISTINCT FROM
    -- NULL, and it reports "ok" while proving nothing. Measured 2026-09-05 by
    -- running these assertions against restored pre-129 bodies in a rolled-back
    -- transaction: this one returned "before=NULL after=NULL" and PASSED.
    -- A refund can only be observed against a unit that was actually consumed.
    IF v_before IS NULL THEN
      INSERT INTO _v_results VALUES ('slice2_aborted_row_refunds_unit', 'fail', NULL,
        'VACUOUS: no ledger row existed before the abort, so there was no '
        || 'consumed unit to refund. Either consume_quota is not being called '
        || 'or the earlier vision block did not run.');
    ELSIF v_used IS DISTINCT FROM v_before THEN
      INSERT INTO _v_results VALUES ('slice2_aborted_row_refunds_unit', 'fail', NULL,
        'used moved from ' || v_before::text || ' to ' ||
        coalesce(v_used::text,'NULL') || ' across a rolled-back insert');
    ELSE
      INSERT INTO _v_results VALUES ('slice2_aborted_row_refunds_unit', 'ok', NULL,
        'used unchanged at ' || v_used::text || ' across an aborted insert');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('slice2_aborted_row_refunds_unit', 'fail', SQLSTATE, SQLERRM);
  END;

  -- 5. food_text free tier: 10 on its own key, then refused.
  BEGIN
    FOR i IN 1..10 LOOP
      INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
      VALUES (v_free_user, 'food_text_analysis', 'oi162 slice2 food ' || i);
    END LOOP;

    SELECT used INTO v_used FROM public.usage_counters
     WHERE user_id = v_free_user AND quota_key = 'food_text'
       AND window_start = v_window;

    IF v_used IS DISTINCT FROM 10 THEN
      INSERT INTO _v_results VALUES ('slice2_food_text_free_10', 'fail', NULL,
        'expected used=10 under food_text, got ' || coalesce(v_used::text, 'NO ROW'));
    ELSE
      INSERT INTO _v_results VALUES ('slice2_food_text_free_10', 'ok', NULL,
        'usage_counters.used = 10 for quota_key=food_text');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('slice2_food_text_free_10', 'fail', SQLSTATE, SQLERRM);
  END;

  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
    VALUES (v_free_user, 'food_text_analysis', 'oi162 slice2 food 11 must fail');
    INSERT INTO _v_results VALUES ('slice2_food_text_11th_refused', 'fail', NULL,
      'the 11th free food_text insert SUCCEEDED; the cap did not fire');
  EXCEPTION
    WHEN sqlstate 'P0001' THEN
      IF SQLERRM LIKE '%food_text_daily_limit_reached%' THEN
        INSERT INTO _v_results VALUES ('slice2_food_text_11th_refused', 'ok', 'P0001', SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('slice2_food_text_11th_refused', 'fail', 'P0001',
          'P0001 raised but the ai-proxy identifier is missing: ' || SQLERRM);
      END IF;
    WHEN OTHERS THEN
      INSERT INTO _v_results VALUES ('slice2_food_text_11th_refused', 'fail', SQLSTATE, SQLERRM);
  END;

  -- 6. A NON-gated channel must not touch the ledger at all -- the short-circuit
  --    has to precede consume_quota, which is what keeps a client's own writes
  --    working (migration 129's header, and the landmine).
  BEGIN
    INSERT INTO public.ai_coach_interactions (user_id, channel, user_message)
    VALUES (v_free_user, 'in_app_orphan', 'oi162 slice2 ungated channel');

    IF EXISTS (SELECT 1 FROM public.usage_counters
                WHERE user_id = v_free_user AND quota_key = 'in_app_orphan') THEN
      INSERT INTO _v_results VALUES ('slice2_ungated_channel_untouched', 'fail', NULL,
        'an ungated channel created a counter row');
    ELSE
      INSERT INTO _v_results VALUES ('slice2_ungated_channel_untouched', 'ok', NULL,
        'in_app_orphan insert succeeded and created no counter row');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('slice2_ungated_channel_untouched', 'fail', SQLSTATE, SQLERRM);
  END;

END;
$slice2$;

SELECT label, status, sqlstate, msg FROM _v_results ORDER BY label;

ROLLBACK;
