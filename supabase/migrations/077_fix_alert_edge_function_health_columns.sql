-- Intent: Fix alert_edge_function_health cron — migration 076 assumed cron_call_log columns `status_code` + `created_at`, but the actual schema is `http_status` + `started_at`. The cron failed every 15min with "column status_code does not exist" since 076 shipped. Unschedule + reschedule with corrected columns + NULL guard.
-- Destructive?: no   -- cron.unschedule + cron.schedule. No table/data change.
-- Rollback strategy: inline   -- SELECT cron.unschedule('alert_edge_function_health'); then re-apply 076's (broken) body if ever needed (not advised).
-- Linked diagnose-doc: 2026-05-28-alert-edge-function-health-wrong-columns-b1f4e2

-- Root cause: column names assumed without querying information_schema first
-- (recurrence of feedback_mistake_fiber_backfill.md class). Actual
-- public.cron_call_log columns: id, function_name, started_at, status,
-- http_status, request_id, error_summary. Migration 076 used status_code +
-- created_at which do not exist.

SELECT cron.unschedule('alert_edge_function_health');

SELECT cron.schedule(
  'alert_edge_function_health',
  '*/15 * * * *',
  $$
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
    SELECT
      COUNT(*) AS total,
      AVG(CASE WHEN http_status >= 200 AND http_status < 300 THEN 0 ELSE 1 END)::float AS err_rate
    FROM public.cron_call_log
    WHERE started_at > now() - interval '30 minutes'
      AND http_status IS NOT NULL
  ) c
  WHERE c.total >= 5
    AND c.err_rate >= 0.05
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts
      WHERE source = 'alert_edge_function_health'
        AND acknowledged = false
        AND detected_at > now() - interval '1 hour'
    );
  $$
);
