-- Migration 068 — cron_call_log table for per-invocation cron-execution telemetry.
--
-- Audit 2026-05-16 / E.14.B (closes-diagnose: telemetry-hardening).
-- Test #16 P1-D root cause: `cron.job_run_details.status='succeeded'` means
-- "pg_net dispatched POST", NOT "Edge Function responded 2xx". When Vault
-- drift produced `Bearer ' || NULL` and every cron HTTP 401-stormed, the
-- `cron.job_run_details` table kept reporting "succeeded" indefinitely.
-- Founder noticed only because pr-detection logs spammed 401s in the
-- Edge Function dashboard. This table closes the visibility gap by
-- recording the FUNCTION-side status (start/success/failed + http_status)
-- alongside the pg_cron dispatch-side status.
--
-- Each cron Edge Function INSERTs a row at the TOP of its handler (status
-- 'started') and UPDATEs at exit (status 'success' or 'failed', plus
-- http_status if applicable). Retention is 7 days — long enough to catch
-- a weekend regression, short enough to not bloat the table.
--
-- DO NOT add user_id to this table. Cron jobs are system actors; rows
-- are not user-scoped. RLS stays disabled (service-role only writes).

CREATE TABLE IF NOT EXISTS public.cron_call_log (
  id            BIGSERIAL PRIMARY KEY,
  function_name TEXT NOT NULL,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  status        TEXT NOT NULL DEFAULT 'started',
    -- 'started' | 'success' | 'failed'
  http_status   INTEGER,
  request_id    TEXT,
  error_summary TEXT
);

-- Reverse-chronological lookup by function name for the audit + ops
-- dashboards ("last successful pr-detection run?").
CREATE INDEX IF NOT EXISTS idx_cron_call_log_function_started
  ON public.cron_call_log(function_name, started_at DESC);

-- Sanity index for "all failures in last 24h" cross-function queries.
CREATE INDEX IF NOT EXISTS idx_cron_call_log_status_started
  ON public.cron_call_log(status, started_at DESC)
  WHERE status = 'failed';

-- 7-day retention. Run nightly via pg_cron (separate registration —
-- migration only ships the cleaner function so it can be wired by
-- founder after dashboard review).
CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.cron_call_log
  WHERE started_at < now() - INTERVAL '7 days';
END;
$$;

-- RLS — disabled by design. Service-role only.
-- (No policies. Verified intentional: ops table, never user-facing.)

COMMENT ON TABLE public.cron_call_log IS
  'Per-invocation cron Edge Function telemetry. Captures the function-side '
  'status (start/success/failed + http_status) that cron.job_run_details '
  'cannot see. Audit 2026-05-16 / E.14.B.';
