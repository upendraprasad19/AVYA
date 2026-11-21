-- Intent: Close two holes Hermes found in migration 109 — the absence alert is fleet-wide so single-function death is invisible, and the cleanup can wipe the whole table when no success row exists.
-- Destructive?: no   -- replaces one function body and adds one pg_cron job; deletes nothing beyond 109's existing retention
-- Rollback strategy: inline   -- reverse block at end of file
-- Linked diagnose-doc: c3f8a1

-- ============================================================================
-- WHY 110 AND NOT AN EDIT TO 109
-- ----------------------------------------------------------------------------
-- 109 is already applied to production. Editing an applied migration file would
-- make the file diverge from what actually ran, breaking the audit trail that
-- backups/applied_migrations.json exists to preserve. Forward-fix instead.
--
-- Both defects were introduced by 109 in this same batch and are fixed in it —
-- Hermes L28-F1/F5 and L31-F2h.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. cleanup_cron_call_log(): never wipe the table.
--
--    109's version spared "the most recent success row" via a scalar subquery.
--    If the table holds only 'started'/'failed' rows older than the retention
--    window, that subquery is NULL, `id IS DISTINCT FROM NULL` is TRUE for
--    every row, and the DELETE removes everything — after which
--    alert_cron_silence reports "no cron execution has ever succeeded", the
--    exact falsehood 109 was written to avoid.
--
--    Now spares the newest success row AND the newest row of any status, so a
--    fleet that is failing (rather than silent) still leaves a forensic anchor.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  DELETE FROM public.cron_call_log
  WHERE started_at < now() - interval '7 days'
    AND id NOT IN (
      SELECT id FROM (
        (SELECT id FROM public.cron_call_log
          WHERE status = 'success' ORDER BY started_at DESC LIMIT 1)
        UNION
        (SELECT id FROM public.cron_call_log
          ORDER BY started_at DESC LIMIT 1)
      ) AS keep_rows
    );
$fn$;

-- `id` is NOT NULL, so the NOT IN subquery can never yield NULL and the
-- NULL-semantics trap does not apply. An empty table yields an empty keep-set,
-- but there is also nothing to delete.
REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;

-- ----------------------------------------------------------------------------
-- 2. Per-function death detection.
--
--    109's alert_cron_silence aggregates the WHOLE fleet:
--      MAX(started_at) ... WHERE status='success'
--    proactive_pr_detection runs every 15 minutes, so that MAX is never more
--    than ~15 min old while pr-detection is healthy — meaning the >= 2h
--    threshold can NEVER be crossed, and the death of any single other job is
--    invisible.
--
--    Concretely missed: weekly-recap-ready boot-fails on its next redeploy (the
--    documented std/encoding dep-rot class). The module never loads, so
--    logCronStart never runs and NOT EVEN a 'failed' row is written. pg_cron
--    still reports "succeeded" because it only sees the dispatch. PRO weekly
--    reports stop indefinitely and nothing says a word. That is the original
--    8-week outage shape, scoped to one function.
--
--    This job is the per-function complement: any function that demonstrably
--    worked in the last 14 days but has not succeeded in 8 days is presumed
--    dead. 8 days is deliberately generous — it clears the slowest real cadence
--    in the fleet (weekly_recap_ready_sunday, Sundays only) without false
--    alarms, while still catching a daily job within a week of its death.
--
--    Keeps 109's fleet-wide alert as-is: that one catches a TOTAL outage fast
--    (2h), this one catches a SINGLE death slowly. Different failure shapes.
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
  'alert_cron_function_dead',
  '47 6 * * *',
  $job$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_function_dead',
    'critical',
    'Cron function "' || d.function_name || '" has not succeeded since '
      || to_char(d.last_success, 'YYYY-MM-DD HH24:MI') || ' UTC ('
      || round(d.days_silent::numeric, 1) || ' days) though it ran before',
    jsonb_build_object(
      'function_name', d.function_name,
      'last_success', d.last_success,
      'days_silent', round(d.days_silent::numeric, 2)
    ),
    'This single function is dead while the rest of the fleet is fine, so '
    || 'alert_cron_silence cannot see it. Check its Edge Function logs for a '
    || 'boot failure (a module that fails to load writes NO cron_call_log row '
    || 'at all, and pg_cron still reports success). See diagnose c3f8a1.'
  FROM (
    SELECT
      function_name,
      MAX(started_at) AS last_success,
      EXTRACT(EPOCH FROM (now() - MAX(started_at))) / 86400.0 AS days_silent
    FROM public.cron_call_log
    WHERE status = 'success'
      AND started_at > now() - interval '14 days'
    GROUP BY function_name
  ) d
  WHERE d.days_silent >= 8
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts a
      WHERE a.source = 'alert_cron_function_dead'
        AND a.acknowledged = false
        AND a.context_json ->> 'function_name' = d.function_name
        AND a.detected_at > now() - interval '24 hours'
    );
  $job$
);

-- ============================================================================
-- ROLLBACK (inline)
-- ----------------------------------------------------------------------------
-- SELECT cron.unschedule('alert_cron_function_dead');
-- -- and restore 109's cleanup body:
-- CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
-- RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
-- AS $fn$
--   DELETE FROM public.cron_call_log
--   WHERE started_at < now() - interval '7 days'
--     AND id IS DISTINCT FROM (
--       SELECT id FROM public.cron_call_log
--       WHERE status = 'success' ORDER BY started_at DESC LIMIT 1);
-- $fn$;
-- ============================================================================
