-- Intent: rework alert_cron_function_dead's body so a fleet-wide outage raises ONE summary row instead of one critical per function, dedup holds 72 h regardless of acknowledgement, and weekly-recalc is excluded (OI-473, OI-472).
-- Destructive?: no   -- changes one pg_cron job command (cron.alter_job by jobname); schedule, name and every table are untouched; no rows are written by this migration
-- Rollback strategy: inline   -- re-apply the command body of migration 144 (lines 65-102, the version this replaces) through cron.alter_job by jobname as a NEW forward migration; see the commented block at the end
-- Linked diagnose-doc: f7b3d1

-- WHY. Migration 169 made alert_cron_function_dead satisfiable for the first time. Its body
-- (migration 144) then has three edges that could not matter while it never fired:
--   1. one CRITICAL row PER dead function in one statement, and trigger 133 dispatches
--      alert-critical-notify per row, so an 8-10 day fleet outage inserts up to 17 critical
--      rows at once;
--   2. the dedup was `acknowledged = false AND detected_at > now() - interval '24 hours'`, so an
--      acknowledged alert re-fires the next day and pg_cron start jitter decides whether it holds;
--   3. the exclusion was one hard-coded name; weekly-recalc logs runs but has no cron job (OI-472).
--
-- WHAT CHANGES (the 144 body, plus exactly these):
--   * CAP: if more than 3 functions are NEW (after dedup) the run inserts ONE critical summary row
--     (context_json = {count, function_names}, no function_name key); 3 or fewer keep one row each.
--   * DEDUP: 72 h, on the function name, independent of acknowledgement. A dead function's last
--     success is visible on 2 or 3 consecutive daily runs (retention 10 d from 169, prune 03:30 UTC,
--     scan 06:47 UTC; ages 8 d to 10 d 3 h 17 m), and run 3 lands at run 1 + 48 h + jitter, so 48 h
--     would re-fire it; 72 h exceeds the whole visible span. A function named in a summary row's
--     function_names array counts as already alerted.
--   * EXCLUSION: function_name NOT IN ('alert-critical-notify', 'weekly-recalc').
--
-- STATEMENT SHAPE. One statement, no semicolon inside the command: data-modifying CTEs. `dead` is
-- its own CTE closing right after GROUP BY, so the `FROM public.cron_call_log` scope contains
-- exactly one interval ('14 days') and the 72 h interval sits in `fresh`; the contract tests read
-- the body that way (alert_threshold_below_retention_test.dart). All CTEs see one snapshot and the
-- singles arm (n.c <= 3) and the summary arm (n.c > 3) are mutually exclusive.
--
-- STATED LIMITS (not solved here): functions scheduled after 06:47 UTC look dead on the first
-- morning after an outage (one summary or up to 3 singles); functions crossing 8 days on different
-- days raise another summary or singles on the second day; a keep-set row (169:40-45) can keep one
-- function visible past day 10 so it re-fires about every 3 days up to the 14-day lookback; a
-- function retired from the repo pages once before its rows leave the table. Silence beyond 10
-- days stays invisible until OI-199's per-function keep-set.

SELECT cron.alter_job(
  job_id := (SELECT jobid FROM cron.job WHERE jobname = 'alert_cron_function_dead'),
  command := $$
  WITH dead AS (
    SELECT
      function_name,
      MAX(started_at) AS last_success,
      EXTRACT(EPOCH FROM (now() - MAX(started_at))) / 86400.0 AS days_silent
    FROM public.cron_call_log
    WHERE status = 'success'
      AND started_at > now() - interval '14 days'
      -- excluded: alert-critical-notify is trigger-dispatched (silence is healthy and a critical about it would dispatch it, OI-179 R2-11); weekly-recalc has no cron job (OI-472)
      AND function_name NOT IN ('alert-critical-notify', 'weekly-recalc')
    GROUP BY function_name
  ),
  fresh AS (
    SELECT d.function_name, d.last_success, d.days_silent
    FROM dead d
    WHERE d.days_silent >= 8
      AND NOT EXISTS (
        SELECT 1 FROM public.alerts a
        WHERE a.source = 'alert_cron_function_dead'
          AND a.detected_at > now() - interval '72 hours'
          AND (a.context_json ->> 'function_name' = d.function_name
               OR a.context_json -> 'function_names' @> to_jsonb(d.function_name))
      )
  ),
  n AS (
    SELECT count(*) AS c FROM fresh
  ),
  singles AS (
    INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
    SELECT
      'alert_cron_function_dead',
      'critical',
      'Cron function "' || f.function_name || '" has not succeeded since '
        || to_char(f.last_success, 'YYYY-MM-DD HH24:MI') || ' UTC ('
        || round(f.days_silent::numeric, 1) || ' days) though it ran before',
      jsonb_build_object(
        'function_name', f.function_name,
        'last_success', f.last_success,
        'days_silent', round(f.days_silent::numeric, 2)
      ),
      'This single function is dead while the rest of the fleet is fine, so alert_cron_silence cannot see it. Check its Edge Function logs for a boot failure (a module that fails to load writes NO cron_call_log row at all, and pg_cron still reports success). If the function was retired on purpose this is the one alert; it stops once its rows leave cron_call_log. See diagnose c3f8a1 and f7b3d1.'
    FROM fresh f, n
    WHERE n.c <= 3
    RETURNING id
  )
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_function_dead',
    'critical',
    n.c || ' cron functions have not succeeded in 8+ days (newly detected, not already alerted): '
      || (SELECT string_agg(x.function_name || ' (' || round(x.days_silent::numeric, 1) || ' d)', ', ' ORDER BY x.days_silent DESC, x.function_name)
          FROM (SELECT function_name, days_silent FROM fresh ORDER BY days_silent DESC, function_name LIMIT 20) x)
      || CASE WHEN n.c > 20 THEN ' and ' || (n.c - 20) || ' more' ELSE '' END,
    jsonb_build_object(
      'count', n.c,
      'function_names', (SELECT jsonb_agg(function_name ORDER BY days_silent DESC, function_name) FROM fresh)
    ),
    'Many cron functions are dead at once, which usually means a shared cause (a Vault service_role_key or cron_secret drift killed 12+ jobs together once), not many separate failures. Check alert_cron_silence and the cron.job_run_details of the listed jobs first. One summary replaces one critical per function. See diagnose f7b3d1.'
  FROM n
  WHERE n.c > 3;
  $$
);

-- Post-apply verification (read-only):
--   SELECT md5(command) FROM cron.job WHERE jobname = 'alert_cron_function_dead';
--   -- must equal the md5 of the raw text between the two dollar tags above (sed -n, leading
--   -- newline included), NOT of the comment-stripped body the test helper returns.
--   SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'alert_cron_function_dead';
--   -- schedule is still '47 6 * * *', active true.
--   -- First real observation: the next 06:47 UTC run. Nothing is dead today, so expect 0 new rows.

-- Rollback (commented; apply as a NEW forward migration): re-apply the alert_cron_function_dead
-- command body of migration 144 (its alter_job, lines 65-102) with cron.alter_job by jobname.
-- That restores the per-function critical rows, the 24 h dedup that depends on acknowledgement,
-- and the single-name exclusion.
