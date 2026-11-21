-- test/sql/cleanup_cron_call_log_retention_live_verify.sql
--
-- 2026-11-05 - Live-Postgres behavioural pin for migration 169 (OI-179, diagnose
-- c9e2a7): public.cleanup_cron_call_log() keeps 10 days, always sparing the
-- newest SUCCESS row and the newest row of ANY status (table-wide in 169).
-- 2026-11-06 (migration 172, OI-199, diagnose b3e7d2): that keep-set is now PER
-- FUNCTION_NAME (each function's newest success and newest row). Both scenarios
-- below therefore seed the rows they compare under ONE function name and assert
-- by started_at; under distinct names every row would be its own function's
-- newest and survive. Valid against the 169 body and the 172 body alike. The
-- per-function cases live in cleanup_cron_call_log_per_function_verify.sql, which
-- test/sql/cleanup_cron_call_log_per_function_local.sh runs in a local container.
--
-- Why this file exists
-- --------------------
-- The retention interval and the keep-set live inside a SQL function body with
-- no Dart/TS reader, so a source-grep test proves PRESENCE only
-- (alert_threshold_below_retention_test.dart reads the number). This file RUNS
-- the function. Same shape as test/sql/migration_140_*_live_verify.sql.
--
-- Safety: everything is inside ONE transaction that ROLLBACKs, and the
-- transaction first EMPTIES public.cron_call_log (rolled back with the rest) so
-- the running fleet's recent rows cannot be the "newest row" and mask the
-- keep-set. REPEATABLE READ (below) keeps a fleet insert that commits mid-run
-- out of this transaction's snapshot: under READ COMMITTED it would become the
-- newest row and falsely redden the keep-set checks (B-pass finding 5). The
-- DELETE and INSERT take row-level and RowExclusive locks only, so they do not
-- block the fleet's inserts. If a concurrent UPDATE of a row this run deletes
-- makes Postgres raise a serialization failure, just run it again. Needs the
-- founder's go (CLAUDE.md section 4.3) because it executes against prod.
--
-- Run it TWICE to be believed (CLAUDE.md section 4.9): once against the OLD
-- 7-day body (expect retention_9d_survives = fail), once after migration 169
-- (expect every row ok). Mutating the new body to drop the UNION newest-row arm
-- must turn keep_set_newest_row_survives red.
--
-- closes-diagnose: c9e2a7

BEGIN;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

CREATE TEMP TABLE _v_results (
  label  text PRIMARY KEY,
  status text NOT NULL,        -- 'ok' | 'fail'
  msg    text
) ON COMMIT DROP;

DO $c9e2a7$
DECLARE
  v_now timestamptz := now();
  v_n   int;
BEGIN
  -- Scenario A - the retention boundary: 1 h, 9 d and 11 d old success rows.
  DELETE FROM public.cron_call_log;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('c9e2a7_a', 'success', v_now - interval '1 hour'),
    ('c9e2a7_a', 'success', v_now - interval '9 days'),
    ('c9e2a7_a', 'success', v_now - interval '11 days');
  PERFORM public.cleanup_cron_call_log();

  SELECT count(*) INTO v_n FROM public.cron_call_log
    WHERE function_name = 'c9e2a7_a' AND started_at = v_now - interval '9 days';
  INSERT INTO _v_results VALUES ('retention_9d_survives',
    CASE WHEN v_n = 1 THEN 'ok' ELSE 'fail' END,
    format('9-day-old success row count after cleanup = %s (expect 1; 7-day body gives 0)', v_n));

  SELECT count(*) INTO v_n FROM public.cron_call_log
    WHERE function_name = 'c9e2a7_a' AND started_at = v_now - interval '11 days';
  INSERT INTO _v_results VALUES ('retention_11d_pruned',
    CASE WHEN v_n = 0 THEN 'ok' ELSE 'fail' END,
    format('11-day-old success row count after cleanup = %s (expect 0)', v_n));

  -- Scenario B - the keep-set: only OLD rows exist, so the newest success and the
  -- newest row overall are both older than the cut and survive ONLY because of
  -- the keep-set. The 31 d success is not the newest success of its function
  -- (the 30 d one is), so it is pruned.
  DELETE FROM public.cron_call_log;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('c9e2a7_s', 'success', v_now - interval '31 days'),
    ('c9e2a7_s', 'success', v_now - interval '30 days'),
    ('c9e2a7_x', 'failed',  v_now - interval '29 days');
  PERFORM public.cleanup_cron_call_log();

  SELECT count(*) INTO v_n FROM public.cron_call_log
    WHERE function_name = 'c9e2a7_s' AND started_at = v_now - interval '30 days';
  INSERT INTO _v_results VALUES ('keep_set_newest_success_survives',
    CASE WHEN v_n = 1 THEN 'ok' ELSE 'fail' END,
    format('newest success older than the cut: count = %s (expect 1)', v_n));

  SELECT count(*) INTO v_n FROM public.cron_call_log WHERE function_name = 'c9e2a7_x';
  INSERT INTO _v_results VALUES ('keep_set_newest_row_survives',
    CASE WHEN v_n = 1 THEN 'ok' ELSE 'fail' END,
    format('newest row of any status older than the cut: count = %s (expect 1)', v_n));

  SELECT count(*) INTO v_n FROM public.cron_call_log
    WHERE function_name = 'c9e2a7_s' AND started_at = v_now - interval '31 days';
  INSERT INTO _v_results VALUES ('keep_set_older_success_pruned',
    CASE WHEN v_n = 0 THEN 'ok' ELSE 'fail' END,
    format('an older success OF THE SAME FUNCTION is not in the keep-set: count = %s (expect 0)', v_n));
END
$c9e2a7$;

SELECT label, status, msg FROM _v_results ORDER BY label;
SELECT CASE WHEN count(*) FILTER (WHERE status = 'fail') = 0
            THEN 'ALL OK (' || count(*) || ' checks)'
            ELSE 'FAILED: ' || count(*) FILTER (WHERE status = 'fail') || ' of ' || count(*) END AS summary
  FROM _v_results;

ROLLBACK;
