-- test/sql/day_swap_sync_load_live_verify.sql
--
-- 2026-09-26 -- Live-Postgres verification of Migration 149 (no-op-update
-- suppression, the scheduled_workouts completed-day guard, and
-- user_progress.sync_epoch). Source-grep contract tests (the sibling
-- test/contracts/sync_noop_trigger_tables_test.dart) can prove the migration
-- FILE names the right 19 tables + the guard + the column, but cannot prove
-- the built-in trigger actually suppresses a real no-op UPDATE, that a
-- genuinely different UPDATE still writes, or that the completed-day guard
-- blocks a demote without raising. This file runs real INSERT/UPDATE
-- sequences against live Postgres in a transaction that ROLLBACKs at the
-- end -- same harness pattern as test/sql/oi46_daily_cap_triggers_live_verify.sql.
--
-- How to run: paste through MCP execute_sql. The documented runner,
-- scripts/check_onconflict_live_arbiter.dart, also runs it (the token resolves from any worktree,
-- OI-165 closed 2026-10-02; no CI runner: OI-283).
-- execute_sql may not return the final SELECT's rows before ROLLBACK, so
-- swap the last two statements for the RAISE EXCEPTION 'VERDICT %' block
-- in plan Task 7's apply-time section; its error text lists every
-- label=status pair. It writes to prod inside the rolled-back transaction,
-- so it needs its own founder go.
--
-- IMPORTANT (found while drafting this file, and worth stating so nobody
-- "fixes" it back): spec Section 9 says to check "xmin unchanged" for the
-- no-op case. That does NOT work inside a single BEGIN...ROLLBACK
-- transaction -- xmin records the CREATING TRANSACTION's id, and every
-- statement in this file runs inside the SAME transaction, so xmin is
-- identical before and after ANY update here, suppressed or not. This file
-- checks `ctid` instead (the tuple's physical location): a real UPDATE
-- always writes a new tuple at a new ctid, even within one transaction; a
-- BEFORE UPDATE trigger that RETURN NULLs the row writes no new tuple at
-- all, so ctid stays fixed. ctid is the correct signal for "was a new row
-- version physically written" here; xmin is not, in this harness shape.
--
-- PL/pgSQL note (same as the oi46 file): explicit SAVEPOINT/ROLLBACK TO
-- SAVEPOINT are not valid inside a PL/pgSQL block; nested
-- BEGIN...EXCEPTION...END blocks provide the equivalent isolation. This file
-- uses only that pattern.
--
-- Discrimination (CLAUDE.md Section 4.9 "green check input set width" /
-- Section 4.4 rule 21): after the primary cases pass, this file DROPS the
-- new triggers and function inside the SAME transaction, then re-runs the
-- two cases that matter most (workout_logs no-op, scheduled_workouts
-- demote) and asserts they now behave the OPPOSITE way. If they didn't, the
-- earlier "ok" rows would prove nothing about this migration.
--
-- Status: RUN LIVE 2026-09-28, right after migration 149 was applied
-- (Task 34, founder go; cloud version 20260928083027), through execute_sql.
-- Verdict: 18 labels, all =ok, including both discrimination cases. A
-- follow-up count confirmed the rollback (0 synthetic rows). Case 16 keeps
-- its own v_wl_id: it used to re-read workout_logs by v_id after cases 5-9
-- had reassigned it, which compared NULL ctids and would have failed
-- whatever the trigger did (fixed before that run).
--
-- closes-diagnose: a9d3f6

BEGIN;

CREATE TEMP TABLE _v_results (
  label    text PRIMARY KEY,
  status   text NOT NULL,        -- 'ok' | 'fail'
  sqlstate text,
  msg      text
) ON COMMIT DROP;

DO $outer$
DECLARE
  v_user            uuid := '00000000-0000-0000-0000-0000000147aa'::uuid;
  v_now             timestamptz := now();
  v_ctid_before     tid;
  v_ctid_after      tid;
  v_id              uuid;
  v_wl_id           uuid;  -- case 3's workout_logs row; v_id is reused by cases 5-9
  v_sched_id        uuid;
  v_status          text;
  v_completed_at    timestamptz;
  v_progress_epoch  int;
  v_rpc_result      bigint;
  v_missing         text[] := ARRAY[]::text[];
  v_cnt             int;
  v_tbl             text;
  v_tables          text[] := ARRAY[
    'workout_logs','workout_log_exercises','workout_log_sets',
    'workout_schedule_completions','streaks','workout_templates',
    'template_exercises','nutrition_logs','nutrition_log_items','water_logs',
    'user_saved_meals','readiness_daily','sleep_logs','weight_logs',
    'body_measurements','daily_steps','user_custom_exercises',
    'user_custom_foods','ai_coach_interactions'
  ];
BEGIN
  -- Best-effort synthetic user seeding -- mirrors oi46_daily_cap_triggers_live_verify.sql.
  BEGIN
    INSERT INTO auth.users (id, email, created_at)
      VALUES (v_user, 'test+day-swap-sync-load@avya.local', v_now)
      ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name)
      VALUES (v_user, 'test+day-swap-sync-load@avya.local', 'day-swap sync-load synthetic')
      ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- =====================================================================
  -- 1. STRUCTURAL: all 19 generic-trigger tables carry
  --    trg_suppress_redundant_updates as a BEFORE UPDATE, non-internal trigger.
  BEGIN
    FOREACH v_tbl IN ARRAY v_tables LOOP
      SELECT count(*) INTO v_cnt
        FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE c.relname = v_tbl
         AND t.tgname = 'trg_suppress_redundant_updates'
         AND NOT t.tgisinternal;
      IF v_cnt <> 1 THEN
        v_missing := array_append(v_missing, v_tbl);
      END IF;
    END LOOP;
    IF array_length(v_missing, 1) IS NULL THEN
      INSERT INTO _v_results VALUES ('structural_generic_trigger_present_all_19', 'ok', NULL,
        'all 19 tables carry trg_suppress_redundant_updates');
    ELSE
      INSERT INTO _v_results VALUES ('structural_generic_trigger_present_all_19', 'fail', NULL,
        'missing on: ' || array_to_string(v_missing, ', '));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('structural_generic_trigger_present_all_19', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 2. STRUCTURAL: scheduled_workouts carries the custom guard trigger, and
  --    NOT the generic one (would be redundant / order-dependent).
  BEGIN
    SELECT count(*) INTO v_cnt
      FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
     WHERE c.relname = 'scheduled_workouts'
       AND t.tgname = 'trg_scheduled_workouts_completed_guard'
       AND NOT t.tgisinternal;
    IF v_cnt = 1 THEN
      SELECT count(*) INTO v_cnt
        FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
       WHERE c.relname = 'scheduled_workouts'
         AND t.tgname = 'trg_suppress_redundant_updates';
      IF v_cnt = 0 THEN
        INSERT INTO _v_results VALUES ('structural_scheduled_workouts_only_custom_guard', 'ok', NULL,
          'custom guard present, generic trigger absent');
      ELSE
        INSERT INTO _v_results VALUES ('structural_scheduled_workouts_only_custom_guard', 'fail', NULL,
          'generic trigger ALSO present on scheduled_workouts');
      END IF;
    ELSE
      INSERT INTO _v_results VALUES ('structural_scheduled_workouts_only_custom_guard', 'fail', NULL,
        'custom guard trigger not found (count=' || v_cnt || ')');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('structural_scheduled_workouts_only_custom_guard', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 3. BEHAVIORAL: identical UPDATE on workout_logs writes no new tuple.
  BEGIN
    INSERT INTO workout_logs (user_id, workout_name, date, sets_completed, reps_completed)
      VALUES (v_user, 'Push Day', '2026-09-01', 3, 10)
      RETURNING id INTO v_id;
    v_wl_id := v_id;
    SELECT ctid INTO v_ctid_before FROM workout_logs WHERE id = v_id;
    UPDATE workout_logs SET workout_name = 'Push Day', date = '2026-09-01',
      sets_completed = 3, reps_completed = 10 WHERE id = v_id;
    SELECT ctid INTO v_ctid_after FROM workout_logs WHERE id = v_id;
    IF v_ctid_before = v_ctid_after THEN
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_workout_logs', 'ok', NULL,
        'identical UPDATE wrote no new tuple');
    ELSE
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_workout_logs', 'fail', NULL,
        'ctid changed on an identical UPDATE');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_workout_logs', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 4. CONTROL: a genuinely different UPDATE on workout_logs still writes
  --    (proves case 3 isn't just "this table never updates", i.e. it
  --    discriminates real changes from no-ops).
  BEGIN
    SELECT ctid INTO v_ctid_before FROM workout_logs WHERE id = v_id;
    UPDATE workout_logs SET sets_completed = 4 WHERE id = v_id;
    SELECT ctid INTO v_ctid_after FROM workout_logs WHERE id = v_id;
    IF v_ctid_before <> v_ctid_after THEN
      INSERT INTO _v_results VALUES ('changed_update_writes_new_tuple_workout_logs', 'ok', NULL,
        'a real change still wrote a new tuple');
    ELSE
      INSERT INTO _v_results VALUES ('changed_update_writes_new_tuple_workout_logs', 'fail', NULL,
        'a genuinely different UPDATE was also suppressed -- over-suppression');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('changed_update_writes_new_tuple_workout_logs', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 5. BEHAVIORAL: identical UPDATE on streaks writes no new tuple.
  BEGIN
    INSERT INTO streaks (user_id, week_start, workouts_planned, workouts_completed, is_streak_maintained)
      VALUES (v_user, '2026-09-01', 5, 5, true)
      RETURNING id INTO v_id;
    SELECT ctid INTO v_ctid_before FROM streaks WHERE id = v_id;
    UPDATE streaks SET workouts_planned = 5, workouts_completed = 5, is_streak_maintained = true
      WHERE id = v_id;
    SELECT ctid INTO v_ctid_after FROM streaks WHERE id = v_id;
    IF v_ctid_before = v_ctid_after THEN
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_streaks', 'ok', NULL,
        'identical UPDATE wrote no new tuple');
    ELSE
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_streaks', 'fail', NULL,
        'ctid changed on an identical UPDATE');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_streaks', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 6. BEHAVIORAL: identical UPDATE on nutrition_logs writes no new tuple.
  BEGIN
    INSERT INTO nutrition_logs (user_id, date, total_calories, meal_type)
      VALUES (v_user, '2026-09-01', 500, 'lunch')
      RETURNING id INTO v_id;
    SELECT ctid INTO v_ctid_before FROM nutrition_logs WHERE id = v_id;
    UPDATE nutrition_logs SET total_calories = 500, meal_type = 'lunch' WHERE id = v_id;
    SELECT ctid INTO v_ctid_after FROM nutrition_logs WHERE id = v_id;
    IF v_ctid_before = v_ctid_after THEN
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_nutrition_logs', 'ok', NULL,
        'identical UPDATE wrote no new tuple');
    ELSE
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_nutrition_logs', 'fail', NULL,
        'ctid changed on an identical UPDATE');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_nutrition_logs', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 7. BEHAVIORAL: identical UPDATE on water_logs writes no new tuple.
  BEGIN
    INSERT INTO water_logs (user_id, date, total_ml, glasses)
      VALUES (v_user, '2026-09-01', 1500, 6)
      RETURNING id INTO v_id;
    SELECT ctid INTO v_ctid_before FROM water_logs WHERE id = v_id;
    UPDATE water_logs SET total_ml = 1500, glasses = 6 WHERE id = v_id;
    SELECT ctid INTO v_ctid_after FROM water_logs WHERE id = v_id;
    IF v_ctid_before = v_ctid_after THEN
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_water_logs', 'ok', NULL,
        'identical UPDATE wrote no new tuple');
    ELSE
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_water_logs', 'fail', NULL,
        'ctid changed on an identical UPDATE');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_water_logs', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 8. BEHAVIORAL: identical UPDATE on user_custom_exercises writes no new tuple.
  BEGIN
    INSERT INTO user_custom_exercises (user_id, name, logging_type)
      VALUES (v_user, 'Synthetic Curl', 'reps')
      RETURNING id INTO v_id;
    SELECT ctid INTO v_ctid_before FROM user_custom_exercises WHERE id = v_id;
    UPDATE user_custom_exercises SET name = 'Synthetic Curl', logging_type = 'reps' WHERE id = v_id;
    SELECT ctid INTO v_ctid_after FROM user_custom_exercises WHERE id = v_id;
    IF v_ctid_before = v_ctid_after THEN
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_user_custom_exercises', 'ok', NULL,
        'identical UPDATE wrote no new tuple');
    ELSE
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_user_custom_exercises', 'fail', NULL,
        'ctid changed on an identical UPDATE');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_user_custom_exercises', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 9. BEHAVIORAL: identical UPDATE on ai_coach_interactions writes no new
  --    tuple. (Does NOT exercise the ai-proxy dedup-refresh call site flagged
  --    in the migration header -- that call always writes a FRESH now(),
  --    which is why it is low-risk rather than exercised here as a failure
  --    case.)
  BEGIN
    INSERT INTO ai_coach_interactions (user_id, channel, user_message, ai_response, model_used, tokens_used)
      VALUES (v_user, 'app', 'synthetic verify message', 'synthetic reply', 'pending', 0)
      RETURNING id INTO v_id;
    SELECT ctid INTO v_ctid_before FROM ai_coach_interactions WHERE id = v_id;
    UPDATE ai_coach_interactions SET ai_response = 'synthetic reply', model_used = 'pending'
      WHERE id = v_id;
    SELECT ctid INTO v_ctid_after FROM ai_coach_interactions WHERE id = v_id;
    IF v_ctid_before = v_ctid_after THEN
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_ai_coach_interactions', 'ok', NULL,
        'identical UPDATE wrote no new tuple');
    ELSE
      INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_ai_coach_interactions', 'fail', NULL,
        'ctid changed on an identical UPDATE');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('noop_update_no_new_tuple_ai_coach_interactions', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 10. BEHAVIORAL: scheduled_workouts identical UPDATE writes no new tuple
  --     (via the custom guard's own no-op branch, not the generic trigger).
  BEGIN
    INSERT INTO scheduled_workouts (user_id, scheduled_date, week_number, day_of_week, status)
      VALUES (v_user, '2026-09-01', 1, 1, 'planned')
      RETURNING id INTO v_sched_id;
    SELECT ctid INTO v_ctid_before FROM scheduled_workouts WHERE id = v_sched_id;
    UPDATE scheduled_workouts SET status = 'planned' WHERE id = v_sched_id;
    SELECT ctid INTO v_ctid_after FROM scheduled_workouts WHERE id = v_sched_id;
    IF v_ctid_before = v_ctid_after THEN
      INSERT INTO _v_results VALUES ('scheduled_workouts_noop_no_new_tuple', 'ok', NULL,
        'identical UPDATE wrote no new tuple');
    ELSE
      INSERT INTO _v_results VALUES ('scheduled_workouts_noop_no_new_tuple', 'fail', NULL,
        'ctid changed on an identical UPDATE');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('scheduled_workouts_noop_no_new_tuple', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 11. BEHAVIORAL: a non-completed status change is allowed (planned -> rest).
  BEGIN
    UPDATE scheduled_workouts SET status = 'rest' WHERE id = v_sched_id;
    SELECT status INTO v_status FROM scheduled_workouts WHERE id = v_sched_id;
    IF v_status = 'rest' THEN
      INSERT INTO _v_results VALUES ('scheduled_workouts_non_completed_status_change_allowed', 'ok', NULL,
        'planned -> rest applied');
    ELSE
      INSERT INTO _v_results VALUES ('scheduled_workouts_non_completed_status_change_allowed', 'fail', NULL,
        'expected status=rest, got ' || coalesce(v_status, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('scheduled_workouts_non_completed_status_change_allowed', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 12. BEHAVIORAL: rest -> completed is allowed (not a demote), then
  --     completed -> planned (a demote) is BLOCKED without raising.
  BEGIN
    UPDATE scheduled_workouts SET status = 'completed', completed_at = v_now WHERE id = v_sched_id;
    -- The demote attempt itself must not raise:
    BEGIN
      UPDATE scheduled_workouts SET status = 'planned' WHERE id = v_sched_id;
      SELECT status INTO v_status FROM scheduled_workouts WHERE id = v_sched_id;
      IF v_status = 'completed' THEN
        INSERT INTO _v_results VALUES ('scheduled_workouts_completed_demote_blocked_no_raise', 'ok', NULL,
          'demote UPDATE ran without error and status stayed completed');
      ELSE
        INSERT INTO _v_results VALUES ('scheduled_workouts_completed_demote_blocked_no_raise', 'fail', NULL,
          'status changed to ' || coalesce(v_status, 'NULL') || ' -- demote was NOT blocked');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO _v_results VALUES ('scheduled_workouts_completed_demote_blocked_no_raise', 'fail', SQLSTATE,
        'the demote UPDATE RAISED -- spec Section 5.10 point 2 requires it never raise: ' || SQLERRM);
    END;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('scheduled_workouts_completed_demote_blocked_no_raise', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 13. BEHAVIORAL: a completed_at correction on the (still-completed) row
  --     is allowed.
  BEGIN
    UPDATE scheduled_workouts SET completed_at = v_now + interval '1 hour' WHERE id = v_sched_id;
    SELECT status, completed_at INTO v_status, v_completed_at FROM scheduled_workouts WHERE id = v_sched_id;
    IF v_status = 'completed' AND v_completed_at = v_now + interval '1 hour' THEN
      INSERT INTO _v_results VALUES ('scheduled_workouts_completed_at_correction_allowed', 'ok', NULL,
        'completed_at corrected, status unchanged');
    ELSE
      INSERT INTO _v_results VALUES ('scheduled_workouts_completed_at_correction_allowed', 'fail', NULL,
        'status=' || coalesce(v_status, 'NULL') || ' completed_at=' || coalesce(v_completed_at::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('scheduled_workouts_completed_at_correction_allowed', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 14. BEHAVIORAL: user_progress.sync_epoch defaults to 0 on a fresh insert.
  BEGIN
    INSERT INTO user_progress (user_id) VALUES (v_user)
      ON CONFLICT (user_id) DO NOTHING;
    SELECT sync_epoch INTO v_progress_epoch FROM user_progress WHERE user_id = v_user;
    IF v_progress_epoch = 0 THEN
      INSERT INTO _v_results VALUES ('sync_epoch_defaults_to_zero', 'ok', NULL, 'sync_epoch=0 on fresh row');
    ELSE
      INSERT INTO _v_results VALUES ('sync_epoch_defaults_to_zero', 'fail', NULL,
        'sync_epoch=' || coalesce(v_progress_epoch::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('sync_epoch_defaults_to_zero', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- 15. BEHAVIORAL: bumping sync_epoch by hand, then calling
  --     update_user_progress_snapshot, leaves sync_epoch untouched.
  BEGIN
    UPDATE user_progress SET sync_epoch = 7 WHERE user_id = v_user;
    SELECT public.update_user_progress_snapshot(
      v_user, 0::bigint, 1, 1, v_now, v_now, 0, 0, 'beginner', 0, 0, NULL, 0
    ) INTO v_rpc_result;
    -- v_rpc_result is expected 1 here: case 14's bare INSERT left
    -- streak_progress_version at its column DEFAULT (0, migration 056), so
    -- p_expected_version=0 MATCHES and the RPC's real UPDATE branch runs
    -- (bumping the version to 1 and writing its 11 named fields) rather than
    -- returning NULL on a version mismatch. That is a STRONGER assertion for
    -- this case's actual purpose than a no-op RPC call would be: it proves
    -- sync_epoch survives a REAL write to the same row, not just an RPC call
    -- that touched nothing.
    SELECT sync_epoch INTO v_progress_epoch FROM user_progress WHERE user_id = v_user;
    IF v_progress_epoch = 7 THEN
      INSERT INTO _v_results VALUES ('sync_epoch_untouched_by_progress_snapshot_rpc', 'ok', NULL,
        'sync_epoch stayed 7 across update_user_progress_snapshot');
    ELSE
      INSERT INTO _v_results VALUES ('sync_epoch_untouched_by_progress_snapshot_rpc', 'fail', NULL,
        'sync_epoch changed to ' || coalesce(v_progress_epoch::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('sync_epoch_untouched_by_progress_snapshot_rpc', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- DISCRIMINATION (CLAUDE.md Section 4.9 / rule 21): drop the new triggers
  -- and function, then re-run the two most important cases and assert the
  -- OPPOSITE outcome, proving the earlier 'ok' rows actually measure this
  -- migration and not some other reason the writes looked stable.
  BEGIN
    DROP TRIGGER IF EXISTS trg_suppress_redundant_updates ON public.workout_logs;
    DROP TRIGGER IF EXISTS trg_scheduled_workouts_completed_guard ON public.scheduled_workouts;
    DROP FUNCTION IF EXISTS private.scheduled_workouts_completed_guard();
    INSERT INTO _v_results VALUES ('discrimination_setup_drop_triggers', 'ok', NULL,
      'dropped trg_suppress_redundant_updates (workout_logs) and the scheduled_workouts guard');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('discrimination_setup_drop_triggers', 'fail', SQLSTATE, SQLERRM);
  END;

  -- 16. Without the trigger, an identical UPDATE on workout_logs now DOES
  --     write a new tuple -- the opposite of case 3.
  BEGIN
    -- v_wl_id, not v_id: by here v_id holds case 9's ai_coach_interactions
    -- row, so a workout_logs lookup on it reads NULL twice and NULL <> NULL
    -- would report 'fail' whatever the trigger did (found before the first
    -- live run, 2026-09-28).
    SELECT ctid INTO v_ctid_before FROM workout_logs WHERE id = v_wl_id;
    UPDATE workout_logs SET workout_name = workout_name WHERE id = v_wl_id;
    SELECT ctid INTO v_ctid_after FROM workout_logs WHERE id = v_wl_id;
    IF v_ctid_before <> v_ctid_after THEN
      INSERT INTO _v_results VALUES ('discrimination_workout_logs_noop_now_writes', 'ok', NULL,
        'with the trigger dropped, the identical UPDATE wrote a new tuple -- case 3 is proven');
    ELSE
      INSERT INTO _v_results VALUES ('discrimination_workout_logs_noop_now_writes', 'fail', NULL,
        'still no new tuple after dropping the trigger -- case 3 proves nothing');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('discrimination_workout_logs_noop_now_writes', 'fail', SQLSTATE, SQLERRM);
  END;

  -- 17. Without the guard, demoting a completed scheduled_workouts row now
  --     SUCCEEDS -- the opposite of case 12.
  BEGIN
    UPDATE scheduled_workouts SET status = 'planned' WHERE id = v_sched_id;
    SELECT status INTO v_status FROM scheduled_workouts WHERE id = v_sched_id;
    IF v_status = 'planned' THEN
      INSERT INTO _v_results VALUES ('discrimination_scheduled_workouts_demote_now_succeeds', 'ok', NULL,
        'with the guard dropped, the demote succeeded -- case 12 is proven');
    ELSE
      INSERT INTO _v_results VALUES ('discrimination_scheduled_workouts_demote_now_succeeds', 'fail', NULL,
        'status is still ' || coalesce(v_status, 'NULL') || ' after dropping the guard -- case 12 proves nothing');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('discrimination_scheduled_workouts_demote_now_succeeds', 'fail', SQLSTATE, SQLERRM);
  END;

END;
$outer$;

SELECT label, status, sqlstate, msg FROM _v_results ORDER BY label;

ROLLBACK;
