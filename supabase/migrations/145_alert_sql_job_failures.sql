-- Intent: Make pg_cron SQL-job failures visible (OI-178). Until now the
--   alerting stack read only public.cron_call_log, which only Edge Functions
--   write, so a pure-SQL cron job that failed emitted nothing any alert read:
--   db_maintenance_nightly (jobid 41) failed 5/5 nights 2026-09-22 → 09-26 and
--   nobody knew (diagnose d6b2f9). This adds ONE hourly job,
--   alert_sql_job_failures, that reads cron.job_run_details directly.
--
--   Design, from plan-review R1-R3 of ops-alerting-b2a (live-measured):
--   - ONE aggregated alert per run, not one per job: on 2026-09-21 14 jobs
--     failed, in two clusters spanning 01:46-16:30 UTC (DB starvation,
--     e8b4a1); per-job criticals would have sent 14 Telegram pages that day
--     (~35 in 30 days).
--   - Severity by failure KIND: 'critical' (pages, trigger migration 133) only
--     when at least one failure is NOT a pg_cron CAPACITY failure (job startup
--     timeout / connection failed / connection slots / server restarted /
--     could not connect); capacity alone is 'warn' (DB saturation, not a bug).
--   - Window on END time (coalesce(end_time, start_time)), not start time: a
--     run's row reads 'failed' only once it ends, and 18 of 100 failed runs in
--     30 d ran > 5 min (max 1h09m) — a start_time window missed 9 of them.
--   - Dedup: an open (unacknowledged) alert of the SAME severity from the last
--     23 h suppresses; for CRITICAL only if it already names EVERY job now
--     failing with a real (non-capacity) error — context key sql_jobs. So an
--     open warn never hides a critical, a NEW real failure always pages, a
--     saturation storm cannot re-page a critical hourly, and a job that keeps
--     failing nightly re-pages once a night (23 h,
--     not 24: a 24 h window sits on the check-to-check boundary and pages at
--     random). Replayed hourly over 30 d: 5 criticals (jobid 41, each night
--     from night one) and 4 warns (one per DB-saturation episode).
--     Acknowledge: UPDATE public.alerts SET acknowledged = true,
--     acknowledged_at = now() WHERE id = <id>; — that re-arms it.
--   - NULL-safe: a failed row whose job was since unscheduled has no cron.job
--     row (50 such rows in the last 30 days); coalesce keeps summary NOT NULL,
--     otherwise the INSERT itself would fail every hour.
--   Residuals, stated:
--   - if THIS job itself fails every run it cannot report itself;
--     alert_cron_silence/ops_alerts are unaffected (separate jobs);
--   - the window overlap is 5 min: if this job starts > 5 min late or its own
--     run fails, failures that ENDED in the gap are never scanned (R3 P3-3);
--     one that ends inside the overlap is seen twice, absorbed by dedup unless
--     acknowledged in between (R3 P3-4);
--   - a job that is deactivated or stops being launched writes NO run row, so
--     it is invisible here — the second half of OI-178, covered by the
--     separate job-silence alert (B2a-1b), not by this one.
-- Destructive?: no -- cron.schedule of one new read-only-then-INSERT job.
-- Rollback strategy: inline
-- Linked diagnose-doc: 2026-09-26-sql-cron-job-failures-invisible-to-alerting-b4c8e2

-- Idempotency guard by jobid, NOT by quoted name: Gate 31 reads raw text and
-- treats any quoted-name unschedule call as "this job is gone" (OI-193).
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'alert_sql_job_failures';

SELECT cron.schedule('alert_sql_job_failures', '23 * * * *', $$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_sql_job_failures',
    a.severity,
    'pg_cron: ' || a.failed_runs || ' failed run(s) in the last 65 min across '
      || a.job_count || ' job(s): ' || left(a.job_list, 300),
    jsonb_build_object(
      'failed_runs', a.failed_runs,
      'sql_failures', a.sql_failures,
      'capacity_failures', a.capacity_failures,
      'jobs', a.jobs,
      'sql_jobs', a.sql_jobs,
      'sample_error', left(coalesce(a.sample_error, ''), 300),
      'window_minutes', 65
    ),
    CASE WHEN a.severity = 'critical'
      THEN 'A pg_cron job failed with a real error (not a capacity failure). Read cron.job_run_details for the jobname(s) in context_json; a multi-statement command runs as ONE transaction, so one failing statement rolls back the rest (diagnose d6b2f9).'
      ELSE 'Only pg_cron capacity failures (job startup timeout / connection failed / connection slots / server restarted / could not connect) — worker/connection capacity, typically DB saturation (diagnose e8b4a1). Check CPU/IO and connection counts before touching any job.'
    END
  FROM (
    SELECT
      CASE WHEN count(*) FILTER (WHERE NOT f.capacity_failure) > 0
           THEN 'critical' ELSE 'warn' END                        AS severity,
      count(*)                                                    AS failed_runs,
      count(*) FILTER (WHERE NOT f.capacity_failure)               AS sql_failures,
      count(*) FILTER (WHERE f.capacity_failure)                   AS capacity_failures,
      count(DISTINCT f.jobkey)                                    AS job_count,
      string_agg(DISTINCT f.jobkey, ', ')                         AS job_list,
      jsonb_agg(DISTINCT f.jobkey)                                AS jobs,
      jsonb_agg(DISTINCT f.jobkey) FILTER (WHERE NOT f.capacity_failure) AS sql_jobs,
      max(f.return_message) FILTER (WHERE NOT f.capacity_failure)  AS sample_error
    FROM (
      SELECT
        coalesce(j.jobname, 'jobid ' || d.jobid)                  AS jobkey,
        d.return_message,
        coalesce(d.return_message, '')
          ~* '(job startup timeout|connection failed|remaining connection slots|server restarted|could not connect)'
                                                                  AS capacity_failure
      FROM cron.job_run_details d
      LEFT JOIN cron.job j ON j.jobid = d.jobid
      WHERE d.status = 'failed'
        -- end_time, not start_time: a run's row reads 'failed' only once it
        -- ENDS, so a start_time window misses any run longer than the gap
        -- (R2 P1-1: 9 of 100 failed rows in 30 d were never visible).
        AND coalesce(d.end_time, d.start_time) > now() - interval '65 minutes'
    ) f
    HAVING count(*) > 0
  ) a
  WHERE NOT EXISTS (
    SELECT 1 FROM public.alerts x
    WHERE x.source = 'alert_sql_job_failures'
      AND x.acknowledged = false
      AND x.severity = a.severity
      -- critical: only if the open alert already names EVERY job now failing
      -- with a REAL error (sql_jobs — capacity-only jobs excluded, R3 P2-1), so
      -- a new real failure always pages and a saturation storm's shifting mix
      -- cannot re-page it hourly. warn (capacity only): severity alone.
      AND (a.severity = 'warn' OR x.context_json -> 'sql_jobs' @> a.sql_jobs)
      -- 23 h, not 24: a nightly failure is checked ~24 h apart, and 24 h would
      -- page on random nights (R2 P3-5). 23 h re-pages it once per night.
      AND x.detected_at > now() - interval '23 hours'
  )
$$);

-- Post-apply verification (read-only):
--   SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'alert_sql_job_failures';
--   -- after the next :23, a run row reads 'succeeded':
--   SELECT status, start_time, return_message FROM cron.job_run_details
--    WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'alert_sql_job_failures')
--    ORDER BY start_time DESC LIMIT 3;

-- Rollback (commented; unquoted name on purpose — Gate 31 scans raw text, OI-193):
-- SELECT cron.unschedule(<the alert job scheduled above>);
