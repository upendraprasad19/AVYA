-- Intent: 6th SQL-only alert cron job — pages when cron_call_log shows a recently-failed or currently-stuck-'started' job, mirroring the 5 existing alert_* jobs' idiom (plain INSERT...SELECT...WHERE...NOT EXISTS, no Edge Function).
-- Destructive?: no   -- only ADDs a new cron.schedule() entry; no table/data touched, no existing job modified.
-- Rollback strategy: inline   -- end-of-file commented-out cron.unschedule() call.
-- Linked diagnose-doc: n/a   -- new feature (Part B / B4 of the observation-batch-and-digest-redesign spec), not a bug fix

-- 139_alert_cron_failures.sql
--
-- Prior art check (spec B4, corrected after round-1 review found this was
-- scoped as greenfield against infra that already exists): live cron.job
-- query confirmed 5 existing pg_cron jobs already do exactly this pattern —
-- plain SQL INSERT into public.alerts, no Edge Function, no new secret, all
-- wired to trg_dispatch_critical_alert_notify (migration 133) via the
-- severity='critical' WHEN clause. This job is the 6th, same shape.
--
-- None of the 5 existing jobs check cron_call_log for status='failed' or a
-- stuck status='started' the way private.founder_metrics()'s sibling
-- founder_metrics_ops() RPC's own cron_failures_24h column already does.
-- 0 'failed' rows, 2 'started' rows in the last 30 days as of 2026-09-21 —
-- so this job is expected to stay silent most days, same as
-- alert_payment_flow_health's low-volume posture.
--
-- CORRECTED same day (self-triggered B-pass review on this batch's full
-- staged diff, before merge) — the first draft borrowed
-- founder_metrics_ops()'s 24-HOUR window verbatim, which is right for a
-- once-a-day DIGEST summary and wrong for a 15-MINUTE, paging, critical
-- alert: paired with this job's own 1-hour dedup window, a SINGLE
-- already-resolved failure would keep re-triggering a critical page roughly
-- hourly for up to 24 hours after the underlying problem was fixed — the
-- lookback window and the dedup window need to agree on "how long does one
-- event stay relevant", and 24h vs 1h do not. The two branches also need
-- DIFFERENT time semantics, not one shared outer bound: a 'failed' row is a
-- discrete, immutable past event (self-resolving once it ages past the
-- window is correct — same 1-hour lookback == 1-hour dedup ratio
-- alert_client_errors_spike already uses successfully), while a
-- 'started'-stuck row describes an ONGOING condition (as long as the job
-- genuinely remains stuck, it should keep being detectable — an outer
-- bound shared with the 'failed' branch would make an old-enough stuck job
-- silently invisible forever once its started_at ages past that bound,
-- which is worse than the re-paging bug it would have been patching around).
-- So the WHERE clause below gives each branch its own independent time
-- check instead of one shared `started_at >= now() - interval 'N'` bound.
--
-- Dedup convention: the SAME acknowledged-based convention the 5 existing
-- jobs share (source + acknowledged=false + a lookback window) — NOT
-- gemini_failure_alert.ts's resolved_at+severity-downgrade convention. This
-- table already has two incompatible dedup conventions coexisting; this job
-- does not add a third.
--
-- Single-tier severity (unlike alert_client_errors_spike's 3-tier
-- info/warn/critical scale): ANY failure/stuck-job pages immediately —
-- Phase-1 placeholder threshold (fire_at: 1), no baseline data exists yet to
-- tune a higher floor. Documented alongside the other Phase-1/2 thresholds in
-- alerts/_thresholds.yaml (same commit).
--
-- Overlap with alert_cron_silence (fleet-wide, no success in 2h) and
-- alert_cron_function_dead (one function, no success in 8 days), noted
-- explicitly per spec review round 2: a persistently-failing function could
-- eventually trigger all three for one root incident, at three different
-- time horizons (this job: within 15min of a single failed/stuck row;
-- alert_cron_silence: 2h of total fleet silence; alert_cron_function_dead:
-- 8 days of one function's silence). Accepted as different time horizons
-- genuinely serving different purposes, not a duplicate to be collapsed.
--
-- Cadence: */15 * * * * — same as alert_client_errors_spike and
-- alert_edge_function_health, so a new failure is caught within 15 minutes
-- of crossing the threshold (the existing jobs' own rolling-window pattern
-- already resolves the boundary-miss concern; this job reuses it rather than
-- inventing a new cadence).

SELECT cron.schedule(
  'alert_cron_failures',
  '*/15 * * * *',
  $$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_failures',
    'critical',
    'cron_call_log shows ' || cnt || ' failed (last 1h) or currently-stuck job(s)',
    jsonb_build_object('count', cnt, 'failed_window_hours', 1, 'stuck_after_hours', 1),
    'Check cron_call_log for the failing function_name (status=''failed'' or '
    'stuck status=''started''). See docs/operations/CRON_REGISTRY.md and '
    '_shared/cron_auth.ts for the auth-gate failure class (diagnose c3f8a1 lineage).'
  FROM (
    SELECT COUNT(*) AS cnt
    FROM public.cron_call_log
    WHERE
      (status = 'failed' AND started_at >= now() - interval '1 hour')
      OR (status = 'started' AND started_at < now() - interval '1 hour')
  ) c
  WHERE c.cnt >= 1
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts
      WHERE source = 'alert_cron_failures'
        AND acknowledged = false
        AND detected_at > now() - interval '1 hour'
    );
  $$
);

-- Post-apply verification (run in the SQL editor):
--   SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'alert_cron_failures';
--   -- expect one row, schedule = '*/15 * * * *', active = true

-- =============================================================================
-- Rollback (inline):
--
-- SELECT cron.unschedule('alert_cron_failures')
--  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alert_cron_failures');
-- =============================================================================
