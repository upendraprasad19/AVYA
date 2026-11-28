-- Intent: Make a cron-wide outage detectable — create the missing cleanup_cron_call_log() function and add an absence-based alert that fires when no cron execution has succeeded for hours.
-- Destructive?: no   -- creates one function and one pg_cron job; deletes only cron_call_log rows older than the stated retention when the daily job runs
-- Rollback strategy: inline   -- reverse block at end of file
-- Linked diagnose-doc: c3f8a1

-- ============================================================================
-- WHY AN ABSENCE ALERT AND NOT THE "MOVE logCronStart ABOVE THE AUTH GATE" FIX
-- ----------------------------------------------------------------------------
-- The batch plan originally proposed reordering every cron function so that
-- logCronStart runs BEFORE isAuthorizedCronCall, on the reasoning that a 401
-- currently writes no telemetry and so the outage was invisible.
--
-- That reorder is UNSAFE and is deliberately not being done.
--
-- 16 of the 18 cron-targeted Edge Functions are verify_jwt=false, meaning the
-- gateway lets ANY caller through and the module's own gate is the only check.
-- Logging before that gate would hand every anonymous caller on the internet an
-- unauthenticated INSERT primitive into public.cron_call_log — a storage and
-- cost amplification vector, on 16 publicly reachable endpoints. The reorder
-- would trade an observability gap for a genuine vulnerability.
--
-- The absence signal is strictly better and has no such vector:
--   * It needs no reorder and no Edge Function change at all.
--   * It detects the OUTCOME (nothing is succeeding) rather than one particular
--     cause (auth rejection) — so it also catches dispatch failures, boot
--     failures, quota exhaustion and pg_cron itself stopping.
--   * It would have fired on day one of this incident. cron_call_log has held
--     6 rows since 2026-05-30; every hour since would have alerted.
--
-- It also fixes the reason the EXISTING alert never fired.
-- alert_edge_function_health (jobid 27) computes an error RATE from
-- cron_call_log — but a 401 writes no row, so the table stayed empty, so its
-- `WHERE total >= 5` guard never matched. The alarm was wired to a sensor the
-- fire cuts power to. An absence check reads the same empty table and correctly
-- concludes "everything is broken" rather than "nothing to report".
--
-- These alert jobs are pure-SQL pg_cron entries and do NOT dispatch to an Edge
-- Function, so they keep working even while the entire Edge cron fleet is down
-- (verified: alert_client_errors_spike has fired throughout this outage).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The missing retention function.
--
--    cron.job jobid 23 (`cron_call_log_cleanup_daily`, 30 3 * * *) has been
--    calling public.cleanup_cron_call_log() since it was scheduled, but the
--    function has NEVER existed — verified live, to_regprocedure(...) IS NULL —
--    so every run has errored. Audit item OI-15 was marked CLOSED without
--    checking live state.
--
--    Retention is 7 days, matching the documented contract in
--    supabase/functions/_shared/cron_telemetry.ts.
-- ----------------------------------------------------------------------------
--    ⚠ The retention delete ALWAYS SPARES the most recent success row.
--    Without that clause this migration would destroy the incident's own
--    evidence: verified live, all 6 rows in cron_call_log predate the 7-day
--    window (oldest 2026-05-17, newest 2026-05-30), so the very first
--    successful cleanup tick after this function is created would wipe the
--    table entirely — and the new absence alert below would then report
--    "no cron execution has EVER succeeded", which is false. Keeping the last
--    success preserves both the forensic anchor and an honest alert message.
CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  DELETE FROM public.cron_call_log
  WHERE started_at < now() - interval '7 days'
    AND id IS DISTINCT FROM (
      SELECT id FROM public.cron_call_log
      WHERE status = 'success'
      ORDER BY started_at DESC
      LIMIT 1
    );
$fn$;

REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM PUBLIC;
-- NB in the `public` schema, Supabase's platform default privileges GRANT
-- EXECUTE directly to anon+authenticated, so REVOKE FROM PUBLIC alone is a
-- no-op for them (supabase/migrations/CLAUDE.md pitfall; diagnose a9d3f1).
-- Revoke from the roles explicitly, then grant only what runs it.
REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;

-- ----------------------------------------------------------------------------
-- 2. The absence alert.
--
--    Thresholds are derived from the fleet's own cadence: proactive_pr_detection
--    runs every 15 minutes, so under healthy operation a `success` row should
--    appear at least four times an hour. Two hours of total silence is already
--    unambiguous.
--
--    An empty table reads as infinite silence and correctly alerts critical —
--    which is the true state of this project at the time of writing.
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'alert_cron_silence',
  '17 * * * *',
  $job$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_silence',
    -- Severity matches the reasoning above: two hours of total fleet silence
    -- is already unambiguous, so it opens at `warn`, not `info`. An `info`
    -- first-fire would have left a total outage at the lowest severity for its
    -- first six hours — the opposite of what this alert is for.
    CASE WHEN c.hours_silent >= 6 THEN 'critical' ELSE 'warn' END,
    CASE WHEN c.last_success IS NULL
         THEN 'No cron execution has ever succeeded (cron_call_log holds no '
              || 'success row)'
         ELSE 'No cron execution has succeeded in '
              || round(c.hours_silent::numeric, 1) || 'h (last: '
              || to_char(c.last_success, 'YYYY-MM-DD HH24:MI') || ' UTC)'
    END,
    jsonb_build_object(
      'hours_silent', round(c.hours_silent::numeric, 2),
      'last_success', c.last_success,
      'threshold_hours', 2
    ),
    'Cron auth or dispatch is broken. Check Edge Function logs for 401s, then '
    || 'verify the CRON_SECRET Edge Function secret matches the `cron_secret` '
    || 'Vault entry character-for-character. See diagnose c3f8a1.'
  FROM (
    SELECT
      MAX(started_at) AS last_success,
      EXTRACT(EPOCH FROM (
        now() - COALESCE(MAX(started_at), TIMESTAMPTZ '2000-01-01')
      )) / 3600.0 AS hours_silent
    FROM public.cron_call_log
    WHERE status = 'success'
  ) c
  WHERE c.hours_silent >= 2
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts
      WHERE source = 'alert_cron_silence'
        AND acknowledged = false
        AND detected_at > now() - interval '6 hours'
    );
  $job$
);

-- ============================================================================
-- ROLLBACK (inline)
-- ----------------------------------------------------------------------------
-- SELECT cron.unschedule('alert_cron_silence');
-- DROP FUNCTION IF EXISTS public.cleanup_cron_call_log();
-- NOTE: dropping the cleanup function returns jobid 23 to erroring on every
-- run, which is the pre-migration state.
-- ============================================================================
