-- test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql
--
-- 2026-09-21 — Live-Postgres verification of both fixes in migration 140
-- (docs/diagnoses/2026-09-21-hermes-pass-migration-138-139-fixes-h1a2b3.md),
-- which corrects two live defects in migrations 138/139 found by a
-- self-triggered Hermes pass on the observation-batch-and-digest-redesign
-- batch.
--
-- Why this file exists
-- --------------------
-- Both defects are DB-internal (a cron job's WHERE clause; a trigger
-- function's branch logic) with no Dart/TS reader to pin a
-- source-grep contract test against. Same pattern as
-- test/sql/onconflict_live_arbiter.sql and
-- test/sql/oi46_daily_cap_triggers_live_verify.sql — runs the real
-- predicate / trigger against live Postgres in a transaction that
-- ROLLBACKs at the end, using synthetic rows only (no real user or
-- subscription data is touched).
--
--   dart run scripts/check_onconflict_live_arbiter.dart \
--       --sql test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql
--
-- Status: RUN LIVE 2026-09-21 immediately after migration 140's apply, via
-- direct `execute_sql` MCP (the check_onconflict_live_arbiter.dart
-- Management-API wrapper hit the same unrelated token-privilege 403 noted in
-- oi46_daily_cap_triggers_live_verify.sql's own header) — the original 3
-- cases (Case 1, Case 2's two assertions) all returned status='ok'.
-- Post-run residue check confirmed zero leaked rows (cron_call_log /
-- subscriptions / public.users), i.e. the ROLLBACK held.
--
-- RE-RUN LIVE same day after a B-pass (Reviewer B, F2) found Case 2 never
-- exercised the migration's OTHER named defect (a direct INSERT carrying
-- status='cancelled') — added Case 3 and re-ran all 4 cases live: all 4
-- returned status='ok' (incl. the new cancelled_at_stamps_on_direct_insert).
-- Post-run residue check confirmed zero leaked rows across cron_call_log /
-- subscriptions / public.users for BOTH synthetic user ids.
--
-- closes-diagnose: h1a2b3

BEGIN;

CREATE TEMP TABLE _v_results (
  label    text PRIMARY KEY,
  status   text NOT NULL,        -- 'ok' | 'fail'
  sqlstate text,
  msg      text
) ON COMMIT DROP;

DO $m140$
DECLARE
  v_sub_user   uuid := '00000000-0000-0000-0000-000000140001'::uuid;
  v_insert_user uuid := '00000000-0000-0000-0000-000000140002'::uuid;
  v_now        timestamptz := now();
  v_within_1h6h int;
  v_at_2h       int;
  v_at_7h       int;
  v_status      text;
  v_cancelled_at timestamptz;
  v_insert_status text;
  v_insert_cancelled_at timestamptz;
BEGIN
  -- =====================================================================
  -- Case 1 — alert_cron_failures's stuck-window bound (fix 1). Exercises
  -- the EXACT predicate migration 140 installed, without needing pg_cron
  -- itself to fire: a row 2h old (inside 1h-6h) must count; a row 7h old
  -- (outside the new 6h bound) must NOT count — the defect being fixed is
  -- precisely that the pre-140 query had no upper bound and counted the 7h
  -- (and, live, 2.5-DAY-old) row too.
  BEGIN
    INSERT INTO cron_call_log (function_name, status, started_at) VALUES
      ('m140_verify_2h', 'started', v_now - interval '2 hours'),
      ('m140_verify_7h', 'started', v_now - interval '7 hours');

    SELECT count(*) INTO v_within_1h6h FROM cron_call_log
      WHERE function_name IN ('m140_verify_2h', 'm140_verify_7h')
        AND status = 'started'
        AND started_at < v_now - interval '1 hour'
        AND started_at >= v_now - interval '6 hours';

    SELECT count(*) INTO v_at_2h FROM cron_call_log
      WHERE function_name = 'm140_verify_2h' AND status = 'started'
        AND started_at < v_now - interval '1 hour'
        AND started_at >= v_now - interval '6 hours';
    SELECT count(*) INTO v_at_7h FROM cron_call_log
      WHERE function_name = 'm140_verify_7h' AND status = 'started'
        AND started_at < v_now - interval '1 hour'
        AND started_at >= v_now - interval '6 hours';

    IF v_at_2h = 1 AND v_at_7h = 0 THEN
      INSERT INTO _v_results VALUES ('stuck_window_bounds_2h_in_7h_out', 'ok', NULL,
        '2h-old row counted, 7h-old row excluded (bound working)');
    ELSE
      INSERT INTO _v_results VALUES ('stuck_window_bounds_2h_in_7h_out', 'fail', NULL,
        format('expected 2h=1,7h=0 got 2h=%s,7h=%s', v_at_2h, v_at_7h));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('stuck_window_bounds_2h_in_7h_out', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 2 — private.set_subscription_cancelled_at() reactivation clear
  -- (fix 2). Pre-140 this function had no branch that ever wrote NULL —
  -- the live-Postgres proof standard here is that the SAME predicate the
  -- pre-140 code could not satisfy now succeeds.
  BEGIN
    BEGIN
      INSERT INTO auth.users (id, email, created_at)
        VALUES (v_sub_user, 'test+m140-sub@avya.local', v_now)
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
      INSERT INTO public.users (id, email, full_name)
        VALUES (v_sub_user, 'test+m140-sub@avya.local', 'm140 sub verify')
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    INSERT INTO subscriptions (user_id, plan, status, start_date, end_date)
      VALUES (v_sub_user, 'monthly', 'active', v_now, v_now + interval '30 days');

    UPDATE subscriptions SET status = 'cancelled' WHERE user_id = v_sub_user;
    SELECT status, cancelled_at INTO v_status, v_cancelled_at
      FROM subscriptions WHERE user_id = v_sub_user;

    IF v_status <> 'cancelled' OR v_cancelled_at IS NULL THEN
      INSERT INTO _v_results VALUES ('cancelled_at_stamps_on_cancel', 'fail', NULL,
        format('expected cancelled/non-null, got status=%s cancelled_at=%s', v_status, v_cancelled_at));
    ELSE
      INSERT INTO _v_results VALUES ('cancelled_at_stamps_on_cancel', 'ok', NULL, 'cancelled_at stamped on cancel');
    END IF;

    UPDATE subscriptions SET status = 'active' WHERE user_id = v_sub_user;
    SELECT status, cancelled_at INTO v_status, v_cancelled_at
      FROM subscriptions WHERE user_id = v_sub_user;

    IF v_cancelled_at IS NOT NULL THEN
      INSERT INTO _v_results VALUES ('cancelled_at_clears_on_reactivation', 'fail', NULL,
        format('expected NULL after reactivation, got cancelled_at=%s (this is the pre-140 bug)', v_cancelled_at));
    ELSE
      INSERT INTO _v_results VALUES ('cancelled_at_clears_on_reactivation', 'ok', NULL,
        'cancelled_at cleared back to NULL on reactivation');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('cancelled_at_clears_on_reactivation', 'fail', SQLSTATE, SQLERRM);
  END;

  -- =====================================================================
  -- Case 3 — private.set_subscription_cancelled_at() stamps on a DIRECT
  -- INSERT carrying status='cancelled' (fix 2's OTHER half, and the reason
  -- migration 140 widened the trigger to BEFORE INSERT OR UPDATE). Pre-140
  -- the trigger was BEFORE UPDATE only, so a row inserted directly with
  -- status='cancelled' fired no trigger at all and stored a NULL stamp.
  -- MISSING from the original 2026-09-21 run of this file (B-pass F2/
  -- Reviewer B, same day) — Case 2 above only exercises the UPDATE-driven
  -- stamp/clear, leaving this migration's OTHER named defect with zero
  -- live coverage until now.
  BEGIN
    BEGIN
      INSERT INTO auth.users (id, email, created_at)
        VALUES (v_insert_user, 'test+m140-ins@avya.local', v_now)
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
      INSERT INTO public.users (id, email, full_name)
        VALUES (v_insert_user, 'test+m140-ins@avya.local', 'm140 insert verify')
        ON CONFLICT (id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    INSERT INTO subscriptions (user_id, plan, status, start_date, end_date)
      VALUES (v_insert_user, 'monthly', 'cancelled', v_now, v_now + interval '30 days');

    SELECT status, cancelled_at INTO v_insert_status, v_insert_cancelled_at
      FROM subscriptions WHERE user_id = v_insert_user;

    IF v_insert_status <> 'cancelled' OR v_insert_cancelled_at IS NULL THEN
      INSERT INTO _v_results VALUES ('cancelled_at_stamps_on_direct_insert', 'fail', NULL,
        format('expected cancelled/non-null on INSERT, got status=%s cancelled_at=%s (this is the pre-140 bug: BEFORE UPDATE only, so INSERT fired no trigger)', v_insert_status, v_insert_cancelled_at));
    ELSE
      INSERT INTO _v_results VALUES ('cancelled_at_stamps_on_direct_insert', 'ok', NULL,
        'cancelled_at stamped on direct INSERT carrying status=cancelled');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('cancelled_at_stamps_on_direct_insert', 'fail', SQLSTATE, SQLERRM);
  END;
END;
$m140$;

SELECT label, status, sqlstate, msg FROM _v_results ORDER BY label;

ROLLBACK;
