-- Intent: Refine alert_client_errors_spike (087, supersedes 086's cron body) — RE-INCLUDE failure-shaped events. 086 excluded ALL error_code 'event'/'info' rows, but the client logs genuine failures (widget_error_fallback, *_failed, *_returned_null, *_unknown_error) via ErrorTelemetry.logEvent which hardcodes error_code='event' — so 086 went blind to a whole failure class. This re-includes any breadcrumb-coded row whose op_type is failure-shaped, while still excluding the benign breadcrumbs (restore_op_done ×3581, *_success, *_done, hive_session_*, ...). Caught in pre-push adversarial review (diagnose f0b9d3).
-- Destructive?: no   -- only cron.unschedule + cron.schedule of the ONE existing job; no table/data touched; alert_edge_function_health + alert_payment_flow_health unchanged.
-- Rollback strategy: inline   -- reverse DDL (re-schedule the 086 body) is commented at file end.
-- Linked diagnose-doc: f0b9d3

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
    'client_errors spike: ' || cnt || ' errors in last hour (excl benign breadcrumbs)',
    jsonb_build_object('count', cnt, 'window_hours', 1,
                       'excludes', 'benign event/info breadcrumbs; failure-shaped op_types re-included'),
    'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
  FROM (
    -- Count real errors: any non-breadcrumb error_code, PLUS breadcrumb-coded
    -- rows whose op_type is failure-shaped. ErrorTelemetry.logEvent stamps
    -- error_code='event' even for genuine failures (*_failed, widget_error_fallback,
    -- *_returned_null, *_unknown_error), so filtering on error_code alone would
    -- hide them. op_type carries the real severity signal.
    SELECT COUNT(*) AS cnt
    FROM public.client_errors
    WHERE created_at > now() - interval '1 hour'
      AND (
        (error_code IS DISTINCT FROM 'event' AND error_code IS DISTINCT FROM 'info')
        OR op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)'
      )
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
-- Rollback (inline) — restore the 086 body (excludes ALL event/info, NO failure
-- re-inclusion → re-introduces the blind spot; use only to revert this refine):
--
-- SELECT cron.unschedule('alert_client_errors_spike')
--  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alert_client_errors_spike');
-- SELECT cron.schedule('alert_client_errors_spike', '*/15 * * * *', $$
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT 'alert_client_errors_spike',
--     CASE WHEN cnt >= 500 THEN 'critical' WHEN cnt >= 250 THEN 'warn' ELSE 'info' END,
--     'client_errors spike: ' || cnt || ' errors in last hour (excl breadcrumbs)',
--     jsonb_build_object('count', cnt, 'window_hours', 1, 'excludes', array['event','info']),
--     'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
--   FROM (SELECT COUNT(*) AS cnt FROM public.client_errors
--         WHERE created_at > now() - interval '1 hour'
--           AND error_code IS DISTINCT FROM 'event' AND error_code IS DISTINCT FROM 'info') c
--   WHERE c.cnt >= 100
--     AND NOT EXISTS (SELECT 1 FROM public.alerts
--       WHERE source='alert_client_errors_spike' AND acknowledged=false
--         AND detected_at > now() - interval '1 hour');
-- $$);
-- =============================================================================
