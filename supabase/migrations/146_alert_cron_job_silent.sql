-- Intent: Alert when a pg_cron job STOPS RUNNING or is left switched off —
--   the second half of OI-178. Migration 145 sees a job that ran and FAILED
--   (a status='failed' row in cron.job_run_details). A job that is deactivated
--   (cron.job.active = false, the documented kill switch) or that pg_cron stops
--   launching writes NO run row at all, so 145 cannot see it and nothing else
--   could either: "a failing job and a job that never ran are the same
--   observation here: nothing" (OI-178). This adds ONE hourly job,
--   alert_cron_job_silent, reading cron.job + cron.job_run_details.
--
--   Design (live-measured, diagnose f7a3d2):
--   - Expected gap from the job's OWN SCHEDULE, not from run history:
--     cleanup_cron_job_run_details keeps 14 d and spares only each job's NEWEST
--     run, so a weekly job's previous run is pruned before a history-based
--     threshold could be reached. The newest run always survives, so "last
--     launched" is always known. Fields, checked in THIS order so that, for
--     every shape it judges, the expected gap is never shorter than reality:
--     not judged (NULL) first for the two shapes whose real gap is unbounded
--     by any fixed guess — both day fields set with one of them starting
--     `*` (pg_cron then ANDs them, e.g. `0 0 */2 * 1` = Mondays on odd
--     dates), and a set month with day-of-month 29–31 (`0 0 29 2 *` runs
--     every 4 y, `0 0 30 2 *` never); then month set → 366 d; day-of-week
--     set → 7 d (with both day fields plainly set cron runs on either);
--     day-of-month set → 62 d (29–31 skip short months: up to 61 d); hour
--     set → 1 d; `*/N` minutes → N min; else 1 h; @hourly/@daily/@weekly/
--     @monthly/@yearly mapped; any other shape → not judged (NULL).
--   - SILENT (critical): active AND launched at least once AND
--     now() - last launch > expected * 1.25 + 1 h (daily 31 h, hourly 2.25 h,
--     */30 1.6 h, weekly 8.75 d). A launch that FAILED still counts as a
--     launch — failures are 145's job. Replayed over all retained history
--     (09-06 → 09-26): exactly 2 flags, both real — alert_payment_flow_health
--     and alert_cron_silence were not launched for 5 h on 2026-09-21 12:07/12:17
--     (DB saturation, e8b4a1), which nothing reported.
--   - INACTIVE (warn): active = false. 0 such jobs live today.
--   - ONE aggregated alert per run. Dedup: critical — an open (unacknowledged)
--     critical from the last 23 h that already names every silent job; warn —
--     any warn (acknowledged or not) from the last 7 d naming every inactive
--     job, so a deliberately disabled job is re-surfaced weekly, not hourly.
--   Residuals, stated:
--   - a job that has NEVER been launched (no run row at all) is not judged:
--     cron.job has no creation time to measure from;
--   - if THIS job itself stops running, or is deactivated, it cannot say so,
--     and neither can 145 (it sees this job only if it FAILS). A correlated
--     non-launch of both (the pg_cron launcher halted, or both slots skipped,
--     as :07/:17 were on 09-21) is seen by NOTHING — that needs a watcher
--     outside pg_cron (OI-250, diagnose f7a3d2);
--   - a list/range in the minute field of an hourly schedule is judged as
--     hourly, and a weekday-only schedule (`M H * * 1-5`) as weekly — both
--     conservative (slower detection, never a false page);
--   - RE-ENABLING a job, or shortening its schedule (cron.alter_job), pages
--     ONE false critical: cron.job has no timestamps, so "last launched" still
--     predates the change until the job's next scheduled run. Suppressing it
--     would need a reactivation time nothing records, and keying it off the
--     earlier warn would leave a re-enabled job that NEVER launches unjudged,
--     which is the failure this alert exists for. Both suggested_actions say
--     so; acknowledge that one page (146 R2 P2-1);
--   - a job that recovers and goes silent again within 23 h of an
--     UNACKNOWLEDGED page naming it is not re-paged (the open page stands);
--   - a job still RUNNING past its threshold reads as not launched; `why`
--     carries the newest run's status so 'running' is visible;
--   - depends on cron.log_run = on: if it is ever turned off (e8b4a1 Fix A),
--     last-launch times freeze and EVERY active job would false-page here
--     (and 145 goes inert). Turning it off must retire or rework both jobs
--     (OI-250). Retention jobs that "succeed" but delete nothing: OI-251.
-- Destructive?: no -- cron.schedule of one new read-only-then-INSERT job.
-- Rollback strategy: inline
-- Linked diagnose-doc: 2026-09-26-cron-job-silence-invisible-to-alerting-f7a3d2

-- Idempotency guard by jobid, NOT by quoted name: Gate 31 reads raw text and
-- treats any quoted-name unschedule call as "this job is gone" (OI-193).
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'alert_cron_job_silent';

SELECT cron.schedule('alert_cron_job_silent', '33 * * * *', $$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_job_silent',
    a.severity,
    'pg_cron: ' || a.silent_count || ' active job(s) not launched on schedule, '
      || a.inactive_count || ' deactivated: ' || left(a.job_list, 300),
    jsonb_build_object(
      'silent_jobs', a.silent_jobs,
      'inactive_jobs', a.inactive_jobs,
      'detail', a.detail
    ),
    CASE WHEN a.severity = 'critical'
      THEN 'pg_cron has stopped launching an active job. Check cron.job_run_details for its last run, the pg_cron launcher (cron.use_background_workers, max_connections) and DB saturation (diagnose e8b4a1) — 145 cannot see this, no run row is written. If the job was just re-enabled or its schedule just shortened, this page is expected once, until its next scheduled run; acknowledge it.'
      ELSE 'A pg_cron job is switched off (cron.job.active = false). If deliberate, acknowledge this alert; if not: UPDATE cron.job SET active = true WHERE jobname = <name>. Re-enabling pages ONE critical from this alert until the next scheduled run of that job (its last launch predates the switch-off); acknowledge it.'
    END
  FROM (
    SELECT
      CASE WHEN count(*) FILTER (WHERE s.kind = 'silent') > 0
           THEN 'critical' ELSE 'warn' END                            AS severity,
      count(*) FILTER (WHERE s.kind = 'silent')                       AS silent_count,
      count(*) FILTER (WHERE s.kind = 'inactive')                     AS inactive_count,
      jsonb_agg(DISTINCT s.jobkey) FILTER (WHERE s.kind = 'silent')   AS silent_jobs,
      jsonb_agg(DISTINCT s.jobkey) FILTER (WHERE s.kind = 'inactive') AS inactive_jobs,
      jsonb_object_agg(s.jobkey, s.why)                               AS detail,
      string_agg(s.jobkey || ' (' || s.why || ')', ', ' ORDER BY s.jobkey) AS job_list
    FROM (
      SELECT coalesce(j.jobname, 'jobid ' || j.jobid) AS jobkey,
             'inactive' AS kind, 'active=false' AS why
      FROM cron.job j
      WHERE NOT j.active
      UNION ALL
      SELECT e.jobkey, 'silent',
             'last launched ' || to_char(e.last_start, 'YYYY-MM-DD HH24:MI')
               || ' UTC (' || coalesce(e.last_status, '?') || '), schedule '
               || e.schedule
      FROM (
        SELECT coalesce(j.jobname, 'jobid ' || j.jobid) AS jobkey,
               j.schedule,
               (SELECT max(d.start_time) FROM cron.job_run_details d
                 WHERE d.jobid = j.jobid)                             AS last_start,
               -- 'running' here means a long run, not a non-launch (R1 P3-5)
               (SELECT d.status FROM cron.job_run_details d
                 WHERE d.jobid = j.jobid
                 ORDER BY d.start_time DESC NULLS LAST, d.runid DESC LIMIT 1) AS last_status,
               CASE
                 WHEN trim(j.schedule) = '@hourly' THEN interval '1 hour'
                 WHEN trim(j.schedule) IN ('@daily', '@midnight') THEN interval '1 day'
                 WHEN trim(j.schedule) = '@weekly' THEN interval '7 days'
                 WHEN trim(j.schedule) = '@monthly' THEN interval '31 days'
                 WHEN trim(j.schedule) IN ('@yearly', '@annually') THEN interval '366 days'
                 WHEN coalesce(array_length(p.f, 1), 0) <> 5 THEN NULL
                 -- Order matters: each branch must give a gap >= reality for
                 -- every schedule it catches (R1 P1 — a restricted month under
                 -- a 31 d guess would false-page a yearly job at ~39 d).
                 -- Unbounded shapes first (R2 P3-1): pg_cron ANDs the day
                 -- fields when either starts with *, and a set month with a
                 -- 29-31 day can recur every 4 years or never.
                 WHEN p.f[3] <> '*' AND p.f[5] <> '*'
                      AND (p.f[3] LIKE '*%' OR p.f[5] LIKE '*%') THEN NULL
                 WHEN p.f[4] <> '*' AND p.f[3] ~ '(29|30|31)' THEN NULL
                 WHEN p.f[4] <> '*' THEN interval '366 days'
                 WHEN p.f[5] <> '*' THEN interval '7 days'
                 WHEN p.f[3] <> '*' THEN interval '62 days'
                 WHEN p.f[2] <> '*' THEN interval '1 day'
                 WHEN p.f[1] ~ '^[*]/[0-9]+$'
                   THEN make_interval(mins => substring(p.f[1] from 3)::int)
                 ELSE interval '1 hour'
               END                                                    AS expected
        FROM cron.job j
        CROSS JOIN LATERAL (SELECT regexp_split_to_array(trim(j.schedule), '[[:space:]]+') AS f) p
        WHERE j.active
      ) e
      WHERE e.expected IS NOT NULL
        AND e.last_start IS NOT NULL
        AND now() - e.last_start > e.expected * 1.25 + interval '1 hour'
    ) s
    HAVING count(*) > 0
  ) a
  WHERE NOT EXISTS (
    SELECT 1 FROM public.alerts x
    WHERE x.source = 'alert_cron_job_silent'
      AND x.severity = a.severity
      AND (
        (a.severity = 'critical'
          AND x.acknowledged = false
          AND x.detected_at > now() - interval '23 hours'
          AND x.context_json -> 'silent_jobs' @> a.silent_jobs)
        OR
        (a.severity = 'warn'
          AND x.detected_at > now() - interval '7 days'
          AND x.context_json -> 'inactive_jobs' @> a.inactive_jobs)
      )
  )
$$);

-- Post-apply verification (read-only):
--   SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'alert_cron_job_silent';
--   -- after the next :33, a run row reads 'succeeded':
--   SELECT status, start_time, return_message FROM cron.job_run_details
--    WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'alert_cron_job_silent')
--    ORDER BY start_time DESC LIMIT 3;

-- Rollback (commented; unquoted name on purpose — Gate 31 scans raw text, OI-193):
-- SELECT cron.unschedule(<the silence job scheduled above>);
