-- Intent: Restore migration 140's 6-hour upper bound on the stuck-job branch
--   of the alert_cron_failures alert, which migration 141 silently reverted
--   when it consolidated alert_cron_failures into the combined ops_alerts_30min
--   job. 141 was authored from an older branch snapshot that predated 140 (its
--   own header at line ~90 notes awareness that migration 139 created
--   alert_cron_failures on a separate branch, but has no awareness that 140
--   later patched it on that same branch) — so 141's copy of the
--   alert_cron_failures sub-query carries the pre-140, unbounded
--   `status = 'started' AND started_at < now() - interval '1 hour'` form with
--   no upper bound. Migration 140's own file was never touched (migrations are
--   immutable) and still reads correctly; only the LIVE job diverged from it.
--   Confirmed live via `SELECT command FROM cron.job WHERE jobname =
--   'ops_alerts_30min'` (jobid 42, active) before drafting this migration —
--   it byte-for-byte matches 141's unbounded form, not 140's bounded one.
--   This migration re-schedules ops_alerts_30min, reproducing the
--   alert_edge_function_health and alert_client_errors_spike sub-blocks
--   VERBATIM from 141 (out of scope for this fix) and restoring only the
--   alert_cron_failures sub-block's upper bound + matching summary/context
--   text.
-- Destructive?: no -- cron.unschedule+cron.schedule only; no data changes.
-- Rollback strategy: inline
-- Linked diagnose-doc: 2026-09-22-merge-integration-review-alert-cron-failures-regression

SELECT cron.unschedule('ops_alerts_30min')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ops_alerts_30min');

SELECT cron.schedule(
  'ops_alerts_30min',
  '*/30 * * * *',
  $$
  -- alert_edge_function_health (verbatim from migration 141 — out of scope here)
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_edge_function_health',
    CASE WHEN err_rate >= 0.20 THEN 'critical'
         WHEN err_rate >= 0.10 THEN 'warn'
         ELSE 'info' END,
    'Edge Function non-2xx rate ' || round((err_rate*100)::numeric, 1) || '% over last 30min (' || total || ' calls)',
    jsonb_build_object('err_rate', err_rate, 'total_calls', total, 'window_minutes', 30),
    'Check Supabase Edge Function logs for the offending function. Last deploy via .claude/deploy_via_api.js?'
  FROM (
    SELECT COUNT(*) AS total,
           AVG(CASE WHEN http_status >= 200 AND http_status < 300 THEN 0 ELSE 1 END)::float AS err_rate
    FROM public.cron_call_log
    WHERE started_at > now() - interval '30 minutes' AND http_status IS NOT NULL
  ) c
  WHERE c.total >= 5 AND c.err_rate >= 0.05
    AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_edge_function_health' AND acknowledged = false AND detected_at > now() - interval '1 hour');

  -- alert_client_errors_spike (verbatim from migration 141 — out of scope here)
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_client_errors_spike',
    CASE WHEN cnt >= 500 THEN 'critical' WHEN cnt >= 250 THEN 'warn' ELSE 'info' END,
    'client_errors spike: ' || cnt || ' errors in last hour (excl benign breadcrumbs)',
    jsonb_build_object('count', cnt, 'window_hours', 1, 'excludes', 'benign event/info breadcrumbs; failure-shaped op_types re-included'),
    'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
  FROM (
    SELECT COUNT(*) AS cnt FROM public.client_errors
    WHERE created_at > now() - interval '1 hour'
      AND ((error_code IS DISTINCT FROM 'event' AND error_code IS DISTINCT FROM 'info')
           OR op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)')
  ) c
  WHERE c.cnt >= 100
    AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_client_errors_spike' AND acknowledged = false AND detected_at > now() - interval '1 hour');

  -- alert_cron_failures: bound restored (this migration's fix). 141's copy had
  -- no upper bound on the stuck branch, matching pre-140 migration 139's
  -- design — the exact form that was ALREADY misfiring live within days of
  -- 139 shipping (a job stuck 2.5 days kept paging every cycle indefinitely,
  -- Hermes diagnose h1a2b3), which is what 140 fixed in the first place.
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_failures',
    'critical',
    'cron_call_log shows ' || cnt || ' failed (last 1h) or currently-stuck (last 6h) job(s)',
    jsonb_build_object('count', cnt, 'failed_window_hours', 1, 'stuck_window_hours', 6),
    'Check cron_call_log for the failing function_name (status=''failed'' or stuck status=''started''). See docs/operations/CRON_REGISTRY.md and _shared/cron_auth.ts for the auth-gate failure class (diagnose c3f8a1 lineage).'
  FROM (
    SELECT COUNT(*) AS cnt FROM public.cron_call_log
    WHERE (status = 'failed' AND started_at >= now() - interval '1 hour')
       OR (status = 'started'
           AND started_at < now() - interval '1 hour'
           AND started_at >= now() - interval '6 hours')
  ) c
  WHERE c.cnt >= 1
    AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_cron_failures' AND acknowledged = false AND detected_at > now() - interval '1 hour');
  $$
);

-- Post-apply verification (run in the SQL editor):
--   SELECT jobid, jobname, schedule, active, command FROM cron.job WHERE jobname = 'ops_alerts_30min';
--   -- expect one row, schedule = '*/30 * * * *', active = true, command containing
--   -- "started_at >= now() - interval '6 hours'" (the bound 141 dropped)
--
--   -- Sanity: no row currently stuck past 6h should be counted (none expected live):
--   SELECT count(*) FROM public.cron_call_log
--     WHERE status = 'started' AND started_at < now() - interval '6 hours';
--
--   -- Sanity: the alert_edge_function_health and alert_client_errors_spike
--   -- sub-blocks are unchanged from 141 — diff the command text against
--   -- 141's file to confirm only the alert_cron_failures WHERE clause and
--   -- its summary/context_json literal changed.

-- =============================================================================
-- Rollback (inline — restores 141's exact unbounded body):
-- =============================================================================
-- SELECT cron.unschedule('ops_alerts_30min')
--  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ops_alerts_30min');
-- SELECT cron.schedule('ops_alerts_30min', '*/30 * * * *', $$
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT 'alert_edge_function_health',
--     CASE WHEN err_rate >= 0.20 THEN 'critical' WHEN err_rate >= 0.10 THEN 'warn' ELSE 'info' END,
--     'Edge Function non-2xx rate ' || round((err_rate*100)::numeric, 1) || '% over last 30min (' || total || ' calls)',
--     jsonb_build_object('err_rate', err_rate, 'total_calls', total, 'window_minutes', 30),
--     'Check Supabase Edge Function logs for the offending function. Last deploy via .claude/deploy_via_api.js?'
--   FROM (SELECT COUNT(*) AS total, AVG(CASE WHEN http_status >= 200 AND http_status < 300 THEN 0 ELSE 1 END)::float AS err_rate
--     FROM public.cron_call_log WHERE started_at > now() - interval '30 minutes' AND http_status IS NOT NULL) c
--   WHERE c.total >= 5 AND c.err_rate >= 0.05
--     AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_edge_function_health' AND acknowledged = false AND detected_at > now() - interval '1 hour');
--
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT 'alert_client_errors_spike',
--     CASE WHEN cnt >= 500 THEN 'critical' WHEN cnt >= 250 THEN 'warn' ELSE 'info' END,
--     'client_errors spike: ' || cnt || ' errors in last hour (excl benign breadcrumbs)',
--     jsonb_build_object('count', cnt, 'window_hours', 1, 'excludes', 'benign event/info breadcrumbs; failure-shaped op_types re-included'),
--     'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
--   FROM (SELECT COUNT(*) AS cnt FROM public.client_errors WHERE created_at > now() - interval '1 hour'
--     AND ((error_code IS DISTINCT FROM 'event' AND error_code IS DISTINCT FROM 'info')
--          OR op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)')) c
--   WHERE c.cnt >= 100
--     AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_client_errors_spike' AND acknowledged = false AND detected_at > now() - interval '1 hour');
--
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT 'alert_cron_failures', 'critical',
--     'cron_call_log shows ' || cnt || ' failed (last 1h) or currently-stuck job(s)',
--     jsonb_build_object('count', cnt, 'failed_window_hours', 1, 'stuck_after_hours', 1),
--     'Check cron_call_log for the failing function_name (status=''failed'' or stuck status=''started''). See docs/operations/CRON_REGISTRY.md and _shared/cron_auth.ts for the auth-gate failure class (diagnose c3f8a1 lineage).'
--   FROM (SELECT COUNT(*) AS cnt FROM public.cron_call_log
--     WHERE (status = 'failed' AND started_at >= now() - interval '1 hour')
--        OR (status = 'started' AND started_at < now() - interval '1 hour')) c
--   WHERE c.cnt >= 1
--     AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_cron_failures' AND acknowledged = false AND detected_at > now() - interval '1 hour');
-- $$);
