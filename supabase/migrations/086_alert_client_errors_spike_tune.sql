-- Intent: Phase-2 tuning of alert_client_errors_spike — exclude telemetry breadcrumbs (error_code 'event'/'info') from the hourly count AND raise thresholds 20/50/100 → 100/250/500 (Tolerant). Closes the false-critical class where 81.5% of counted rows were non-error breadcrumbs (alert #24, founder's own reinstall/restore burst on +28).
-- Destructive?: no   -- only cron.unschedule + cron.schedule of the ONE existing job; no table/data touched; alert_edge_function_health + alert_payment_flow_health unchanged.
-- Rollback strategy: inline   -- reverse DDL (re-schedule the migration-076 placeholder body) is commented at file end.
-- Linked diagnose-doc: f0b9d3

-- Re-schedule the single client_errors spike job. Guarded unschedule first so
-- this is idempotent whether or not the job already exists; cron.schedule by the
-- same name then re-creates it with the tuned body.
SELECT cron.unschedule('alert_client_errors_spike')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alert_client_errors_spike');

SELECT cron.schedule(
  'alert_client_errors_spike',
  '*/15 * * * *',
  $$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_client_errors_spike',
    CASE WHEN cnt >= 500 THEN 'critical'
         WHEN cnt >= 250 THEN 'warn'
         ELSE 'info' END,
    'client_errors spike: ' || cnt || ' errors in last hour (excl breadcrumbs)',
    jsonb_build_object('count', cnt, 'window_hours', 1, 'excludes', array['event','info']),
    'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
  FROM (
    -- Count real errors only: 'event' + 'info' are telemetry breadcrumbs logged
    -- to the same client_errors sink (~81.5% of rows), not failures.
    SELECT COUNT(*) AS cnt
    FROM public.client_errors
    WHERE created_at > now() - interval '1 hour'
      AND error_code IS DISTINCT FROM 'event'
      AND error_code IS DISTINCT FROM 'info'
  ) c
  WHERE c.cnt >= 100
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts
      WHERE source = 'alert_client_errors_spike'
        AND acknowledged = false
        AND detected_at > now() - interval '1 hour'
    );
  $$
);

-- =============================================================================
-- Rollback (inline) — restore the migration-076 placeholder behaviour:
--
-- SELECT cron.unschedule('alert_client_errors_spike')
--  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alert_client_errors_spike');
-- SELECT cron.schedule('alert_client_errors_spike', '*/15 * * * *', $$
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT 'alert_client_errors_spike',
--     CASE WHEN cnt >= 100 THEN 'critical' WHEN cnt >= 50 THEN 'warn' ELSE 'info' END,
--     'client_errors spike: ' || cnt || ' rows in last hour',
--     jsonb_build_object('count', cnt, 'window_hours', 1),
--     'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
--   FROM (SELECT COUNT(*) AS cnt FROM public.client_errors
--         WHERE created_at > now() - interval '1 hour') c
--   WHERE c.cnt >= 20
--     AND NOT EXISTS (SELECT 1 FROM public.alerts
--       WHERE source = 'alert_client_errors_spike' AND acknowledged = false
--         AND detected_at > now() - interval '1 hour');
-- $$);
-- =============================================================================
