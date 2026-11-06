-- Intent: Restore nightly retention, which has not run since migration 141.
--   141 consolidated six maintenance jobs into ONE pg_cron job,
--   db_maintenance_nightly, whose command holds four `SELECT cleanup_*()` calls
--   followed by two `VACUUM (ANALYZE)` statements. With
--   `cron.use_background_workers=off` (live) pg_cron sends the command over
--   libpq as ONE simple query, which Postgres runs as one implicit
--   transaction — and VACUUM cannot run inside a transaction block — so the job has FAILED every night since 2026-09-22
--   (cron.job_run_details, jobid 41: 5/5 failed, `ERROR: VACUUM cannot run
--   inside a transaction block`). Because it is one transaction, the error
--   also ROLLS BACK the four cleanups: cron_call_log, usage_counters,
--   cron.job_run_details and client_errors have not been pruned since 09-21.
--   The same two VACUUMs succeeded every night 2026-09-06 → 09-20 while each
--   was its own single-statement job (pre-141 jobids 35/36) — that is the
--   shape restored here. Diagnose d6b2f9 / OI-247.
--
--   Second change, defence in depth for OI-179: with the cron_call_log prune
--   dead, alert_cron_function_dead (`days_silent >= 8`, daily 06:47 UTC) can
--   see 12 days of history for the first time, and `alert-critical-notify`
--   (last success 2026-09-22 11:00) crosses 8 days at 2026-10-01 06:47 — a
--   false CRITICAL. That function is TRIGGER-dispatched (it runs when a
--   critical alert is inserted), not cron-scheduled, so "silent for N days"
--   is healthy for it; and a critical about it would dispatch it, write a
--   fresh success row, and reset its own clock — the self-sustaining loop
--   OI-179's R2-11 precondition names. It is excluded by name here. The
--   restored prune alone would also defuse the 10-01 fire. The exclusion removes
--   ONLY the trigger-dispatched self-reset case: weekly-cadence functions (e.g.
--   weekly-recap-ready) stay exposed to a lost success row (OI-194) whenever
--   retention is broken (plan-review R2 F1). OI-179's threshold-vs-retention
--   defect is NOT addressed here and stays open.
--
--   Both jobs are changed with cron.alter_job, preserving their jobids and
--   cron.job_run_details history (141's own §4c precedent).
-- Destructive?: no -- cron.alter_job + cron.schedule only; no data changes by
--   this migration. The restored cleanups delete rows past their existing
--   retention windows on their next scheduled run, exactly as before 141.
-- Rollback strategy: inline
-- Linked diagnose-doc: 2026-09-26-db-maintenance-vacuum-in-transaction-block-d6b2f9

-- 1. db_maintenance_nightly: cleanups only (VACUUM removed from this command).
SELECT cron.alter_job(
  job_id := (SELECT jobid FROM cron.job WHERE jobname = 'db_maintenance_nightly'),
  command := $$
  SELECT public.cleanup_cron_call_log();
  SELECT public.cleanup_usage_counters();
  SELECT public.cleanup_cron_job_run_details();
  SELECT public.cleanup_client_errors();
  $$
);

-- 2. The two VACUUMs, each as its OWN single-statement job (pre-141 shape),
--    scheduled after the 03:30 cleanups so they reclaim what was just deleted.
SELECT cron.unschedule('jrd_vacuum_daily')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'jrd_vacuum_daily');
SELECT cron.schedule('jrd_vacuum_daily', '40 3 * * *',
  $$VACUUM (ANALYZE) cron.job_run_details$$);

SELECT cron.unschedule('client_errors_vacuum_daily')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'client_errors_vacuum_daily');
SELECT cron.schedule('client_errors_vacuum_daily', '43 3 * * *',
  $$VACUUM (ANALYZE) public.client_errors$$);

-- 3. alert_cron_function_dead: exclude the trigger-dispatched function.
--    Body is the live command verbatim (md5 1cc8a0fd…, plan-review R1) plus two
--    added lines: one comment, one predicate.
SELECT cron.alter_job(
  job_id := (SELECT jobid FROM cron.job WHERE jobname = 'alert_cron_function_dead'),
  command := $$
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
    'This single function is dead while the rest of the fleet is fine, so alert_cron_silence cannot see it. Check its Edge Function logs for a boot failure (a module that fails to load writes NO cron_call_log row at all, and pg_cron still reports success). See diagnose c3f8a1.'
  FROM (
    SELECT
      function_name,
      MAX(started_at) AS last_success,
      EXTRACT(EPOCH FROM (now() - MAX(started_at))) / 86400.0 AS days_silent
    FROM public.cron_call_log
    WHERE status = 'success'
      AND started_at > now() - interval '14 days'
      -- trigger-dispatched, not cron-scheduled: silence is healthy (OI-179 R2-11, d6b2f9)
      AND function_name <> 'alert-critical-notify'
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
  $$
);

-- Post-apply verification (read-only):
--   SELECT jobname, command FROM cron.job
--    WHERE jobname IN ('db_maintenance_nightly','jrd_vacuum_daily',
--                      'client_errors_vacuum_daily','alert_cron_function_dead');
--   -- db_maintenance_nightly must contain no VACUUM; each *_vacuum_daily
--   -- exactly one statement. After the next 03:30/03:40/03:43 UTC runs:
--   SELECT j.jobname, d.status, d.start_time FROM cron.job_run_details d
--     JOIN cron.job j USING (jobid)
--    WHERE j.jobname IN ('db_maintenance_nightly','jrd_vacuum_daily','client_errors_vacuum_daily')
--    ORDER BY d.start_time DESC LIMIT 6;   -- expect 'succeeded'

-- Rollback (commented — apply as a NEW migration if ever needed; this restores
-- 141's live state, which is the broken one, so prefer a forward fix):
-- SELECT cron.unschedule(<the jrd VACUUM job scheduled above>);  -- unquoted on purpose: Gate 31 scans raw text (OI-193)
-- SELECT cron.unschedule(<the client_errors VACUUM job scheduled above>);
-- SELECT cron.alter_job(job_id := (SELECT jobid FROM cron.job WHERE jobname = 'db_maintenance_nightly'),
--   command := $$ SELECT public.cleanup_cron_call_log(); SELECT public.cleanup_usage_counters();
--   SELECT public.cleanup_cron_job_run_details(); SELECT public.cleanup_client_errors();
--   VACUUM (ANALYZE) cron.job_run_details; VACUUM (ANALYZE) public.client_errors; $$);
-- (alert_cron_function_dead: re-apply the command without the alert-critical-notify line.)
