-- Intent: Create alerts table + 3 pg_cron jobs for production-incident detection. Phase 1 of the incident playbook (six industry-gap closure 2026-05-28). Thresholds are PLACEHOLDER values picked low to fire during baseline week; Phase 2 (scheduled 2026-06-03) re-tunes from observed data.
-- Destructive?: no   -- CREATE TABLE + CREATE EXTENSION IF NOT EXISTS + cron.schedule. No existing data touched.
-- Rollback strategy: inline   -- DROP TABLE alerts; SELECT cron.unschedule('alert_client_errors_spike'); cron.unschedule('alert_edge_function_health'); cron.unschedule('alert_payment_flow_health');
-- Linked diagnose-doc: not applicable -- infrastructure batch, not a bug fix

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- =============================================================================
-- alerts: unacknowledged production-incident signals surfaced to founder on
-- session start via .claude/settings.json SessionStart hook.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.alerts (
  id                BIGSERIAL PRIMARY KEY,
  detected_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  source            TEXT NOT NULL,           -- 'alert_client_errors_spike' | 'alert_edge_function_health' | 'alert_payment_flow_health'
  severity          TEXT NOT NULL,           -- 'info' | 'warn' | 'critical'
  summary           TEXT NOT NULL,
  context_json      JSONB NOT NULL DEFAULT '{}'::jsonb,
  suggested_action  TEXT,
  acknowledged      BOOLEAN NOT NULL DEFAULT false,
  acknowledged_at   TIMESTAMPTZ,
  resolved_at       TIMESTAMPTZ,
  CONSTRAINT alerts_severity_check CHECK (severity IN ('info','warn','critical'))
);

CREATE INDEX IF NOT EXISTS alerts_unack_idx ON public.alerts (detected_at DESC)
  WHERE acknowledged = false;

CREATE INDEX IF NOT EXISTS alerts_source_idx ON public.alerts (source, detected_at DESC);

COMMENT ON TABLE public.alerts IS
  'Production-incident signals. Inserted by alert_* pg_cron jobs every 15min/hourly. Surfaced via SessionStart hook scripts/check_alerts.dart. Acknowledged by founder via natural-language triage (agent updates via service-role MCP call).';

-- =============================================================================
-- Cron: alert_client_errors_spike — every 15 minutes.
-- Fires when client_errors row count in the last hour exceeds threshold.
-- Placeholder threshold: 20/hour (will fire during baseline; Phase 2 re-tunes).
-- =============================================================================

SELECT cron.schedule(
  'alert_client_errors_spike',
  '*/15 * * * *',
  $$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_client_errors_spike',
    CASE WHEN cnt >= 100 THEN 'critical'
         WHEN cnt >= 50  THEN 'warn'
         ELSE 'info' END,
    'client_errors spike: ' || cnt || ' rows in last hour',
    jsonb_build_object('count', cnt, 'window_hours', 1),
    'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
  FROM (
    SELECT COUNT(*) AS cnt
    FROM public.client_errors
    WHERE created_at > now() - interval '1 hour'
  ) c
  WHERE c.cnt >= 20
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts
      WHERE source = 'alert_client_errors_spike'
        AND acknowledged = false
        AND detected_at > now() - interval '1 hour'
    );
  $$
);

-- =============================================================================
-- Cron: alert_edge_function_health — every 15 minutes.
-- Fires when non-2xx rate in cron_call_log over last 30min exceeds threshold.
-- Placeholder threshold: 5% non-2xx (Phase 2 re-tunes).
-- =============================================================================

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
      AVG(CASE WHEN status_code >= 200 AND status_code < 300 THEN 0 ELSE 1 END)::float AS err_rate
    FROM public.cron_call_log
    WHERE created_at > now() - interval '30 minutes'
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

-- =============================================================================
-- Cron: alert_payment_flow_health — hourly.
-- Fires when subscriptions 24h success rate dips below threshold.
-- Placeholder threshold: 99% success (Phase 2 re-tunes).
-- =============================================================================

SELECT cron.schedule(
  'alert_payment_flow_health',
  '7 * * * *',
  $$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_payment_flow_health',
    CASE WHEN ok_rate < 0.95 THEN 'critical'
         WHEN ok_rate < 0.99 THEN 'warn'
         ELSE 'info' END,
    'Payment success rate ' || round((ok_rate*100)::numeric, 2) || '% over last 24h (' || total_attempts || ' attempts)',
    jsonb_build_object('ok_rate', ok_rate, 'total_attempts', total_attempts, 'window_hours', 24),
    'Inspect razorpay-webhook logs + verify-payment Edge Function logs. ADR-0005 catastrophic-tier discipline applies.'
  FROM (
    SELECT
      COUNT(*) AS total_attempts,
      AVG(CASE WHEN status IN ('active','expired','cancelled') THEN 1 ELSE 0 END)::float AS ok_rate
    FROM public.subscriptions
    WHERE created_at > now() - interval '24 hours'
  ) c
  WHERE c.total_attempts >= 3
    AND c.ok_rate < 0.99
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts
      WHERE source = 'alert_payment_flow_health'
        AND acknowledged = false
        AND detected_at > now() - interval '6 hours'
    );
  $$
);

-- =============================================================================
-- RLS: alerts is service-role only. Client app never reads it directly.
-- =============================================================================

ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY alerts_service_role_only
  ON public.alerts
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Block authenticated/anon — they have no business with alerts.
REVOKE ALL ON public.alerts FROM authenticated, anon;
