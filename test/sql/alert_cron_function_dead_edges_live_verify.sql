-- OI-473 / OI-472 (diagnose f7b3d1): behavioural rehearsal of the NEW alert_cron_function_dead body
-- (migration 170). BEGIN ... ROLLBACK, REPEATABLE READ: re-run on a serialization failure. Nothing persists.
-- The body between the $b$ tags is byte-identical to migration 170's `command := $$ ... $$` (md5 asserted
-- below, and test/contracts/alert_cron_function_dead_rehearsal_sync_test.dart keeps the two in step).
-- WHERE TO RUN IT: a LOCAL scratch Postgres (docker image public.ecr.aws/supabase/postgres:17.6.1.084 with minimal
-- alerts + cron_call_log tables from migrations 076/068 and a no-op trigger named trg_dispatch_critical_alert_notify), as
-- done for OI-473. Against the live project only with the founder's go: the first statements take a lock on public.alerts,
-- hence the lock_timeout / statement_timeout below (an unbounded wait here once stalled a session for over an hour).
-- Trigger 133 is DISABLED inside the transaction so no notification can be queued; DDL rolls back too.
-- Run it ONCE against the OLD (144) body to see the storm cases redden, then against this body.
-- Counted by id > max_id_before, never by whole-table counts. Seeds use severity 'warn'.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '60s';
ALTER TABLE public.alerts DISABLE TRIGGER trg_dispatch_critical_alert_notify;
DELETE FROM public.cron_call_log;
DELETE FROM public.alerts WHERE source = 'alert_cron_function_dead';
CREATE TEMP TABLE _b (t text);
INSERT INTO _b VALUES ($b$
  WITH dead AS (
    SELECT
      function_name,
      MAX(started_at) AS last_success,
      EXTRACT(EPOCH FROM (now() - MAX(started_at))) / 86400.0 AS days_silent
    FROM public.cron_call_log
    WHERE status = 'success'
      AND started_at > now() - interval '14 days'
      -- excluded: alert-critical-notify is trigger-dispatched (silence is healthy and a critical about it would dispatch it, OI-179 R2-11); weekly-recalc has no cron job (OI-472)
      AND function_name NOT IN ('alert-critical-notify', 'weekly-recalc')
    GROUP BY function_name
  ),
  fresh AS (
    SELECT d.function_name, d.last_success, d.days_silent
    FROM dead d
    WHERE d.days_silent >= 8
      AND NOT EXISTS (
        SELECT 1 FROM public.alerts a
        WHERE a.source = 'alert_cron_function_dead'
          AND a.detected_at > now() - interval '72 hours'
          AND (a.context_json ->> 'function_name' = d.function_name
               OR a.context_json -> 'function_names' @> to_jsonb(d.function_name))
      )
  ),
  n AS (
    SELECT count(*) AS c FROM fresh
  ),
  singles AS (
    INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
    SELECT
      'alert_cron_function_dead',
      'critical',
      'Cron function "' || f.function_name || '" has not succeeded since '
        || to_char(f.last_success, 'YYYY-MM-DD HH24:MI') || ' UTC ('
        || round(f.days_silent::numeric, 1) || ' days) though it ran before',
      jsonb_build_object(
        'function_name', f.function_name,
        'last_success', f.last_success,
        'days_silent', round(f.days_silent::numeric, 2)
      ),
      'This single function is dead while the rest of the fleet is fine, so alert_cron_silence cannot see it. Check its Edge Function logs for a boot failure (a module that fails to load writes NO cron_call_log row at all, and pg_cron still reports success). If the function was retired on purpose this is the one alert; it stops once its rows leave cron_call_log. See diagnose c3f8a1 and f7b3d1.'
    FROM fresh f, n
    WHERE n.c <= 3
    RETURNING id
  )
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_function_dead',
    'critical',
    n.c || ' cron functions have not succeeded in 8+ days (newly detected, not already alerted): '
      || (SELECT string_agg(x.function_name || ' (' || round(x.days_silent::numeric, 1) || ' d)', ', ' ORDER BY x.days_silent DESC, x.function_name)
          FROM (SELECT function_name, days_silent FROM fresh ORDER BY days_silent DESC, function_name LIMIT 20) x)
      || CASE WHEN n.c > 20 THEN ' and ' || (n.c - 20) || ' more' ELSE '' END,
    jsonb_build_object(
      'count', n.c,
      'function_names', (SELECT jsonb_agg(function_name ORDER BY days_silent DESC, function_name) FROM fresh)
    ),
    'Many cron functions are dead at once, which usually means a shared cause (a Vault service_role_key or cron_secret drift killed 12+ jobs together once), not many separate failures. Check alert_cron_silence and the cron.job_run_details of the listed jobs first. One summary replaces one critical per function. See diagnose f7b3d1.'
  FROM n
  WHERE n.c > 3;
  $b$);
CREATE TEMP TABLE _r (c text, ok boolean, detail text);
INSERT INTO _r SELECT 'md5 of the embedded body = migration body', md5(t) = 'f890669f0389e0febd5976ee0185c9f1', md5(t) FROM _b;
CREATE FUNCTION pg_temp.reset() RETURNS void LANGUAGE sql AS $f$
  DELETE FROM public.cron_call_log; DELETE FROM public.alerts WHERE source = 'alert_cron_function_dead' $f$;
CREATE FUNCTION pg_temp.dead(fn text, age numeric DEFAULT 9) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES (fn, 'success', now() - age * interval '1 day') $f$;
CREATE FUNCTION pg_temp.seed(names text[], ago interval, as_summary boolean DEFAULT false) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO public.alerts (source, severity, summary, context_json, detected_at)
  SELECT 'alert_cron_function_dead', 'warn', 'seed',
    CASE WHEN as_summary THEN jsonb_build_object('count', cardinality(names), 'function_names', to_jsonb(names))
         ELSE jsonb_build_object('function_name', n) END, now() - ago
  FROM unnest(CASE WHEN as_summary THEN ARRAY[names[1]] ELSE names END) AS u(n) $f$;
CREATE FUNCTION pg_temp.run() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE m bigint;
BEGIN
  SELECT coalesce(max(id), 0) INTO m FROM public.alerts;
  EXECUTE (SELECT t FROM _b);
  RETURN (SELECT jsonb_build_object('rows', count(*), 'critical', count(*) FILTER (WHERE severity = 'critical'),
            'singles', count(*) FILTER (WHERE context_json ? 'function_name'),
            'summary_count', max((context_json ->> 'count')::int), 'has_names', bool_or(context_json ? 'function_names'))
          FROM public.alerts WHERE id > m AND source = 'alert_cron_function_dead');
END $f$;
-- (a) 5 dead: ONE summary, count 5
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1',9),pg_temp.dead('f2',9.1),pg_temp.dead('f3',9.2),pg_temp.dead('f4',9.3),pg_temp.dead('f5',9.4);
INSERT INTO _r SELECT 'a: 5 dead => 1 critical summary (count 5)', (j->>'rows')::int = 1 AND (j->>'singles')::int = 0 AND (j->>'summary_count')::int = 5 AND (j->>'critical')::int = 1, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (e) run again right after (a): dedup holds
INSERT INTO _r SELECT 'e: run again => 0 rows (summary names them)', (j->>'rows')::int = 0, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (f) acknowledge the summary, run again: acknowledgement does not re-fire
UPDATE public.alerts SET acknowledged = true WHERE source = 'alert_cron_function_dead';
INSERT INTO _r SELECT 'f: acknowledged then run again => 0 rows', (j->>'rows')::int = 0, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (b) 3 dead: three singles
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1'),pg_temp.dead('f2'),pg_temp.dead('f3');
INSERT INTO _r SELECT 'b: 3 dead => 3 singles', (j->>'rows')::int = 3 AND (j->>'singles')::int = 3 AND (j->>'critical')::int = 3, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (c) 4 dead: the boundary, ONE summary
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1'),pg_temp.dead('f2'),pg_temp.dead('f3'),pg_temp.dead('f4');
INSERT INTO _r SELECT 'c: 4 dead => 1 summary (3/4 boundary)', (j->>'rows')::int = 1 AND (j->>'summary_count')::int = 4, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (d) 0 dead: three alive functions
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1',1),pg_temp.dead('f2',2),pg_temp.dead('f3',7.5);
INSERT INTO _r SELECT 'd: 0 dead => 0 rows (no bogus summary)', (j->>'rows')::int = 0, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (k) the 8-day edge: 8.2 d silent fires, 7.9 d does not
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1',8.2);
INSERT INTO _r SELECT 'k1: 8.2 days silent => fires', (j->>'rows')::int = 1 AND (j->>'singles')::int = 1, j::text FROM (SELECT pg_temp.run() AS j) x;
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1',7.9);
INSERT INTO _r SELECT 'k2: 7.9 days silent => quiet', (j->>'rows')::int = 0, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (g) excluded names, 9 days silent
SELECT pg_temp.reset(); SELECT pg_temp.dead('weekly-recalc'),pg_temp.dead('alert-critical-notify');
INSERT INTO _r SELECT 'g: weekly-recalc and alert-critical-notify excluded => 0 rows', (j->>'rows')::int = 0, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (h) 4 already alerted (10 h ago) + 2 new, all 6 dead: the cap counts AFTER dedup => 2 singles
SELECT pg_temp.reset(); SELECT pg_temp.dead('f'||i) FROM generate_series(1,6) i; SELECT pg_temp.seed(ARRAY['f1','f2','f3','f4'], interval '10 hours');
INSERT INTO _r SELECT 'h: 2 new + 4 already alerted => 2 singles', (j->>'rows')::int = 2 AND (j->>'singles')::int = 2, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (i) a summary row 25 h old naming f1..f3, those 3 dead: no singles
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1'),pg_temp.dead('f2'),pg_temp.dead('f3'); SELECT pg_temp.seed(ARRAY['f1','f2','f3'], interval '25 hours', true);
INSERT INTO _r SELECT 'i: functions named in a 25 h old summary => 0 rows', (j->>'rows')::int = 0, j::text FROM (SELECT pg_temp.run() AS j) x;
-- (j) window boundary: 71 h 59 m suppresses, 72 h 1 m does not
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1'); SELECT pg_temp.seed(ARRAY['f1'], interval '71 hours 59 minutes');
INSERT INTO _r SELECT 'j1: alert 71h59m old => suppressed', (j->>'rows')::int = 0, j::text FROM (SELECT pg_temp.run() AS j) x;
SELECT pg_temp.reset(); SELECT pg_temp.dead('f1'); SELECT pg_temp.seed(ARRAY['f1'], interval '72 hours 1 minute');
INSERT INTO _r SELECT 'j2: alert 72h01m old => fires again', (j->>'rows')::int = 1 AND (j->>'singles')::int = 1, j::text FROM (SELECT pg_temp.run() AS j) x;
SELECT c, ok, detail FROM _r ORDER BY (ok), c;
ROLLBACK;
