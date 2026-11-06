-- test/sql/oi153_pro_media_caps_live_verify.sql
--
-- OI-153 (diagnose a9d4e7). Live-Postgres verification, three parts, every
-- part wrapped in BEGIN … ROLLBACK — nothing persists. Run by hand via the
-- MCP `execute_sql` (one part per call; the tool returns the LAST result
-- set only) or the generic harness:
--
--   dart run scripts/check_onconflict_live_arbiter.dart \
--       --sql test/sql/oi153_pro_media_caps_live_verify.sql
--
-- Why this file exists. The contract test
-- (test/contracts/pro_media_daily_caps_writer_to_reader_test.dart) proves
-- ai-media-proxy SAYS `consume_quota(proQuotaKey, istDayStartIso(), proCap)`
-- with the right arrangement; it cannot prove the ledger BEHAVES that way
-- for a 50-cap and a 10-cap key, nor that the two keys are independent
-- counters for one user, nor that a refusal leaves `used` untouched (the
-- property the founder digest's "at cap" reading depends on). Those are
-- Part A. Part B is the migration-132 guard — read-only text check AND a
-- behavioural probe that is RED before 132 and GREEN after it (CLAUDE.md
-- §4.9: "a new behavioural test that executes green tells you nothing until
-- you run it against the code it replaces" — here that is explicit). Part C
-- is the cron row migration 131 adds.
--
-- Discrimination, stated per assertion (the OI-162 slice-2 lesson):
--   * A1/A2 (1..cap succeed, cap+1 refuses) and A3 (key independence) hold
--     under ANY correct consume_quota — behaviour-invariants, not evidence
--     this batch changed anything; kept because the proxy's new keys and
--     caps are exactly what they exercise.
--   * A4 (`used` unchanged after a refusal) is the property migration 128
--     documents and the digest's "at cap = used >= cap" relies on; a
--     consume_quota that incremented on refusal would push `used` to 51.
--   * B2 DISCRIMINATES 132: with 129's `NOT IN` guard, a NULL-channel insert
--     calls consume_quota and a `vision_analysis` row appears; with 132's
--     `IS NULL OR` guard it returns early and no row appears.
--
-- Fixture: `v_user` must be a real `public.users.id` — usage_counters has an
-- ON DELETE CASCADE FK, so a random uuid aborts the transaction on the first
-- insert (slice-4's file learned this). The seeding block below mirrors
-- oi46_daily_cap_triggers_live_verify.sql: best-effort synthetic auth/public
-- user rows, ON CONFLICT DO NOTHING, all rolled back.
--
-- Status: written 2026-09-13 in the OI-153 apply commit; results of the live
-- run are recorded in the commit message and the closure ledger, not here.

-- ============================================================================
-- PART A — the two PRO keys on consume_quota (rolled back)
-- ============================================================================
BEGIN;

DO $$
DECLARE
  v_user   uuid        := '00000000-0000-0000-0000-000000000153';
  v_window timestamptz := '2099-01-01T00:00:00+05:30'; -- an IST-day start far in the future; cannot collide
  v_result integer;
  v_used   integer;
  i        integer;
BEGIN
  BEGIN
    INSERT INTO auth.users (id, email, created_at)
      VALUES (v_user, 'test+oi153@avya.local', now()) ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name)
      VALUES (v_user, 'test+oi153@avya.local', 'oi153 probe') ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  CREATE TEMP TABLE oi153_probe (seq serial, step text, result integer);

  -- A1: image, cap 50 — calls 1..50 succeed and report their ordinal; 51 refuses.
  FOR i IN 1..50 LOOP
    v_result := public.consume_quota(v_user, 'oi153_test_pro_image_daily', v_window, 50);
    INSERT INTO oi153_probe (step, result) VALUES ('image call ' || i, v_result);
  END LOOP;
  v_result := public.consume_quota(v_user, 'oi153_test_pro_image_daily', v_window, 50);
  INSERT INTO oi153_probe (step, result) VALUES ('image call 51 (cap+1, must refuse)', v_result);

  -- A4: the refusal left `used` at exactly 50 — the digest reads `used >= cap`
  -- as "at cap"; an increment-on-refusal would read 51 and the row could not
  -- distinguish "hit the ceiling" from "was refused N times".
  SELECT used INTO v_used FROM public.usage_counters
    WHERE user_id = v_user AND quota_key = 'oi153_test_pro_image_daily' AND window_start = v_window;
  INSERT INTO oi153_probe (step, result) VALUES ('image used after refusal (must be 50)', v_used);

  -- A3: video is an INDEPENDENT counter for the same user and window —
  -- the image key at its ceiling must not touch it.
  -- A2: video, cap 10 — calls 1..10 succeed; 11 refuses.
  FOR i IN 1..10 LOOP
    v_result := public.consume_quota(v_user, 'oi153_test_pro_video_daily', v_window, 10);
    INSERT INTO oi153_probe (step, result) VALUES ('video call ' || i, v_result);
  END LOOP;
  v_result := public.consume_quota(v_user, 'oi153_test_pro_video_daily', v_window, 10);
  INSERT INTO oi153_probe (step, result) VALUES ('video call 11 (cap+1, must refuse)', v_result);

  -- A5: the NEXT IST day is a fresh counter (the midnight-IST reset the copy promises).
  v_result := public.consume_quota(v_user, 'oi153_test_pro_image_daily', v_window + interval '1 day', 50);
  INSERT INTO oi153_probe (step, result) VALUES ('image, NEXT IST day (must be fresh, ==1)', v_result);
END $$;

SELECT
  step,
  result,
  CASE
    WHEN step LIKE '%must refuse)%'      THEN result = -1
    WHEN step LIKE '%must be 50)%'       THEN result = 50
    WHEN step LIKE '%NEXT IST day%'      THEN result = 1
    ELSE result = substring(step FROM 'call (\d+)')::integer
  END AS ok
FROM oi153_probe
ORDER BY seq;

ROLLBACK;

-- ============================================================================
-- PART B — migration 132's NULL-safe vision guard (rolled back)
-- ============================================================================
BEGIN;

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000153';
  v_rows integer;
  v_def  text;
BEGIN
  BEGIN
    INSERT INTO auth.users (id, email, created_at)
      VALUES (v_user, 'test+oi153@avya.local', now()) ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name)
      VALUES (v_user, 'test+oi153@avya.local', 'oi153 probe') ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  CREATE TEMP TABLE oi153_b_probe (seq serial, step text, ok boolean, detail text);

  -- B1 (text): the live definition carries the guard.
  v_def := pg_get_functiondef('public.enforce_vision_analysis_daily_limit()'::regprocedure);
  INSERT INTO oi153_b_probe (step, ok, detail)
    VALUES ('B1 live body has IS NULL OR guard', v_def LIKE '%NEW.channel IS NULL OR%', left(v_def, 60));

  -- B2 (behaviour): a NULL-channel insert must NOT consume a vision unit.
  -- Pre-132 this row appears (NULL NOT IN (...) is NULL, the IF does not
  -- fire, consume_quota runs); post-132 it does not.
  INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, ai_response, model_used, tokens_used)
    VALUES (v_user, NULL, 'oi153 null-channel probe', 'n/a', 'none', 0);
  SELECT count(*) INTO v_rows FROM public.usage_counters
    WHERE user_id = v_user AND quota_key = 'vision_analysis';
  INSERT INTO oi153_b_probe (step, ok, detail)
    VALUES ('B2 NULL channel consumed no vision unit', v_rows = 0, 'vision_analysis rows for probe user: ' || v_rows);

  -- B3 (control): a REAL scan_meal insert still consumes exactly one.
  INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, ai_response, model_used, tokens_used)
    VALUES (v_user, 'scan_meal', 'oi153 scan probe', 'n/a', 'none', 0);
  SELECT coalesce(sum(used), 0) INTO v_rows FROM public.usage_counters
    WHERE user_id = v_user AND quota_key = 'vision_analysis';
  INSERT INTO oi153_b_probe (step, ok, detail)
    VALUES ('B3 scan_meal still consumes one', v_rows = 1, 'vision_analysis used for probe user: ' || v_rows);
END $$;

SELECT step, ok, detail FROM oi153_b_probe ORDER BY seq;

ROLLBACK;

-- ============================================================================
-- PART C — migration 131's cron row (read-only)
-- ============================================================================
SELECT jobid, jobname, schedule, active,
       command LIKE '%/functions/v1/founder-digest%'      AS targets_digest,
       command LIKE '%private.cron_get_secret()%'         AS uses_cron_secret,
       command NOT LIKE '%morning_alert_get_service_key%' AS not_service_key
FROM cron.job
WHERE jobname = 'founder_digest_daily';
-- expect exactly one row: schedule '30 2 * * *', active, all three booleans true.
