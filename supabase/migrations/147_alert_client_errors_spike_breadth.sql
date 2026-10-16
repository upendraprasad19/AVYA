-- Intent: Rewrite the alert_client_errors_spike sub-block of ops_alerts_30min
--   (jobid 43) to fix a recurrence of the 2026-06-06 spike-filter-drift class
--   (diagnose f0b9d3, docs/diagnoses/2026-06-06-alert-spike-counts-breadcrumbs-f0b9d3.md):
--   the live filter still counts raw client_errors ROWS rather than distinct
--   events, has no offline-noise exclusion (a phone losing signal on a train
--   can write dozens of rows in one minute that are not a product regression),
--   and has no per-user or server-error-class breadth signal, so a single
--   noisy device can both trigger AND fail to trigger the alert depending only
--   on how many times it retried. This migration:
--     1. Counts DISTINCT (user, message-prefix, second) MOMENTS instead of raw
--        rows, so retry storms from one client don't inflate the count.
--     2. Excludes offline-caused errors via a regex signature, with an
--        explicit never-offline override for real HTTP status codes and for
--        PostgrestException/FunctionsHttpException/FunctionsRelayException/
--        AuthApiException (these types mean the request reached a server and
--        got an answer, so they are never network-loss noise even if their
--        message also happens to contain an offline-shaped substring).
--        Offline-caused client TIMEOUTS are deliberately still counted as
--        real (residual, matches the client-side offlineSignature contract
--        B2a-2b will add — a stalled request without a clear connectivity
--        signal is ambiguous, and undercounting is the worse failure mode).
--     3. Adds a per-user breadth arm (>=3 distinct users trips at least warn)
--        counted over EXCEPTION-SHAPED rows only (error_code NOT IN
--        ('event','info')) — the routine `event`-coded
--        subscription_refresh_query_returned_null breadcrumb
--        (lib/core/services/subscription_service.dart:911-912 — verified live
--        at this path/line before drafting, since a stale citation here would
--        itself be the exact class of bug this migration exists to fix)
--        would otherwise inflate this arm on its own; live 36-day replay
--        with this filter never exceeded 2 distinct users/hour.
--     4. Adds a server-error-class arm (>=3 distinct server-shaped events
--        trips at least warn, >=10 trips critical) matching Postgres/Edge
--        Function failure signatures (PGRST00x, 57014 statement-timeout,
--        WORKER_RESOURCE_LIMIT, a bare 5xx status) — these are infra
--        incidents regardless of how many or few distinct users hit them.
--   KNOWN, TRACKED ASYMMETRY (OI-254, found by the self-triggered B-pass,
--   docs/reviews/46c9b9ff3bde-review.md finding 1): `cnt` does NOT get the
--   `error_code NOT IN ('event','info')` guard the `users`/`server_events`
--   arms get, so it still inherits any event/info-coded row whose op_type
--   matches the outer breadcrumb-reinclusion regex from 087/f0b9d3
--   (including subscription_refresh_query_returned_null, 28x/36d, currently
--   non-material: max(cnt)=24 vs the 40 floor). This is DELIBERATE, not an
--   oversight — narrowing `cnt` to match would undo 087's own P0 fix (it
--   exists specifically to catch genuine failures the client mislabels
--   error_code='event'), and a name-based denylist for this one op_type is
--   the exact "transient denylist" f0b9d3 already evaluated and rejected
--   (the same client-side mislabeling recurs under ~25 other op_types). The
--   real fix is a CLIENT-side rename of the offending op_type, tracked as
--   OI-254 and naturally in scope for B2a-2b (client telemetry), not this
--   pure-SQL migration. Pinned by
--   test/contracts/ops_alerts_spike_breadth_test.dart's "cnt is DELIBERATELY
--   NOT scoped..." test.
--   The edge_function_health and alert_cron_failures sub-blocks are
--   reproduced VERBATIM from migration 143 (out of scope for this fix;
--   test/contracts/ops_alerts_spike_breadth_test.dart asserts byte-identity).
--   Live command body confirmed unchanged since 143 via
--   `SELECT command FROM cron.job WHERE jobname = 'ops_alerts_30min'`
--   (jobid 43, active) before drafting this migration.
-- Destructive?: no   -- cron.alter_job only; no data changes; jobid/schedule/history preserved
-- Rollback strategy: inline
-- Linked diagnose-doc: 2026-09-27-alert-client-errors-spike-filter-drift-recurrence-d2c9f4

SELECT cron.alter_job(
  job_id := (SELECT jobid FROM cron.job WHERE jobname = 'ops_alerts_30min'),
  command := $$
  -- alert_edge_function_health (verbatim from migration 141 — out of scope here)
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
    SELECT COUNT(*) AS total,
           AVG(CASE WHEN http_status >= 200 AND http_status < 300 THEN 0 ELSE 1 END)::float AS err_rate
    FROM public.cron_call_log
    WHERE started_at > now() - interval '30 minutes' AND http_status IS NOT NULL
  ) c
  WHERE c.total >= 5 AND c.err_rate >= 0.05
    AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_edge_function_health' AND acknowledged = false AND detected_at > now() - interval '1 hour');

  -- alert_client_errors_spike: distinct-event counting + offline exclusion +
  -- per-user and server-error-class breadth arms (this migration's fix;
  -- recurrence of 2026-06-06 diagnose f0b9d3's raw-row-count / no-breadcrumb-
  -- exclusion class). severity_rank is computed once in the `c` subquery and
  -- reused both for the emitted severity text and for the rank-based dedup
  -- comparison below, so the fire condition, the severity CASE and the dedup
  -- check can never independently drift out of sync with each other.
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_client_errors_spike',
    CASE c.severity_rank WHEN 3 THEN 'critical' WHEN 2 THEN 'warn' ELSE 'info' END,
    'client_errors spike: ' || c.cnt || ' distinct events (' || c.users || ' users, ' || c.server_events || ' server-error events) in last hour (excl offline + benign breadcrumbs)',
    jsonb_build_object(
      'distinct_events', c.cnt,
      'distinct_users', c.users,
      'server_events', c.server_events,
      'rows', c.rows,
      'window_hours', 1,
      'excludes', 'offline-caused errors (regex signature; PostgrestException/FunctionsHttpException/FunctionsRelayException/AuthApiException and real HTTP status codes never treated as offline); benign event/info breadcrumbs unless failure-shaped op_type; offline-caused client timeouts still counted as real (deliberate)'
    ),
    'Inspect docs/diagnoses for recent regression; correlate with last APK build. server_events firing usually means a Postgres/Edge-Function-side issue (PGRST/statement-timeout/WORKER_RESOURCE_LIMIT/5xx), not a client bug.'
  FROM (
    SELECT
      raw.cnt,
      raw.users,
      raw.server_events,
      raw.rows,
      CASE WHEN raw.cnt >= 200 OR raw.users >= 5 OR raw.server_events >= 10 THEN 3
           WHEN raw.cnt >= 100 OR raw.users >= 3 OR raw.server_events >= 3 THEN 2
           ELSE 1 END AS severity_rank
    FROM (
      SELECT
        COUNT(DISTINCT (coalesce(user_id::text, 'anon'), left(coalesce(error_message, ''), 200), date_trunc('second', created_at))) AS cnt,
        COUNT(DISTINCT coalesce(user_id::text, 'anon')) FILTER (
          WHERE coalesce(error_code, '') NOT IN ('event', 'info')
        ) AS users,
        COUNT(DISTINCT (coalesce(user_id::text, 'anon'), left(coalesce(error_message, ''), 200), date_trunc('second', created_at))) FILTER (
          WHERE coalesce(error_code, '') NOT IN ('event', 'info')
            AND error_message ~* '(PGRST00[0-9]|57014|canceling statement due to statement timeout|WORKER_RESOURCE_LIMIT|status(Code)?: ?5[0-9]{2})'
        ) AS server_events,
        COUNT(*) AS rows
      FROM public.client_errors
      WHERE created_at > now() - interval '1 hour'
        AND ((error_code IS DISTINCT FROM 'event' AND error_code IS DISTINCT FROM 'info')
             OR op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)')
        AND NOT (
          coalesce(error_message, '') ~* '(failed host lookup|socketexception|connection (refused|reset|closed|abort)|network is unreachable|software caused connection abort|failed to fetch|load failed|xmlhttprequest error)'
          AND NOT (
            coalesce(error_message, '') ~* 'status(Code)?: ?[1-9][0-9]{2}'
            OR coalesce(error_message, '') ~ '(PostgrestException|FunctionsHttpException|FunctionsRelayException|AuthApiException)'
          )
        )
    ) raw
  ) c
  WHERE (c.cnt >= 40 OR c.users >= 3 OR c.server_events >= 3)
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts a
      WHERE a.source = 'alert_client_errors_spike'
        AND a.acknowledged = false
        AND a.detected_at > now() - interval '1 hour'
        AND CASE a.severity WHEN 'critical' THEN 3 WHEN 'warn' THEN 2 ELSE 1 END >= c.severity_rank
    );

  -- alert_cron_failures (verbatim from migration 143 — out of scope here)
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_failures',
    'critical',
    'cron_call_log shows ' || cnt || ' failed (last 1h) or currently-stuck (last 6h) job(s)',
    jsonb_build_object('count', cnt, 'failed_window_hours', 1, 'stuck_window_hours', 6),
    'Check cron_call_log for the failing function_name (status=''failed'' or stuck status=''started''). See docs/operations/CRON_REGISTRY.md and _shared/cron_auth.ts for the auth-gate failure class (diagnose c3f8a1 lineage).'
  FROM (
    SELECT COUNT(*) AS cnt FROM public.cron_call_log
    WHERE (status = 'failed' AND started_at >= now() - interval '1 hour')
       OR (status = 'started'
           AND started_at < now() - interval '1 hour'
           AND started_at >= now() - interval '6 hours')
  ) c
  WHERE c.cnt >= 1
    AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_cron_failures' AND acknowledged = false AND detected_at > now() - interval '1 hour');
  $$
);

-- Post-apply verification (run in the SQL editor):
--   SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'ops_alerts_30min';
--   -- expect jobid = 43 (unchanged), schedule = '*/30 * * * *', active = true
--
--   SELECT command FROM cron.job WHERE jobname = 'ops_alerts_30min';
--   -- expect the body above; confirm 'distinct_events' and 'server_events' both
--   -- appear (new arms present) and the edge_function_health / alert_cron_failures
--   -- sub-blocks are byte-identical to migration 143's file.
--
--   -- Sanity (read-only, safe to run live): replay the new filter over the last
--   -- 36 days without writing any alert row, to confirm no wildly different
--   -- count than the migration's own replay (8 firing ticks, all 'warn', over
--   -- 2026-08-29 / 09-15 / 09-17 / 09-19 — see the diagnose doc):
--   SELECT date_trunc('hour', created_at) AS bucket, count(*) AS rows
--   FROM public.client_errors
--   WHERE created_at > now() - interval '36 days'
--   GROUP BY 1 ORDER BY 1 DESC LIMIT 5;

-- =============================================================================
-- Rollback (inline — restores migration 143's exact body verbatim):
-- =============================================================================
-- SELECT cron.alter_job(
--   job_id := (SELECT jobid FROM cron.job WHERE jobname = 'ops_alerts_30min'),
--   command := $$
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT
--     'alert_edge_function_health',
--     CASE WHEN err_rate >= 0.20 THEN 'critical'
--          WHEN err_rate >= 0.10 THEN 'warn'
--          ELSE 'info' END,
--     'Edge Function non-2xx rate ' || round((err_rate*100)::numeric, 1) || '% over last 30min (' || total || ' calls)',
--     jsonb_build_object('err_rate', err_rate, 'total_calls', total, 'window_minutes', 30),
--     'Check Supabase Edge Function logs for the offending function. Last deploy via .claude/deploy_via_api.js?'
--   FROM (
--     SELECT COUNT(*) AS total,
--            AVG(CASE WHEN http_status >= 200 AND http_status < 300 THEN 0 ELSE 1 END)::float AS err_rate
--     FROM public.cron_call_log
--     WHERE started_at > now() - interval '30 minutes' AND http_status IS NOT NULL
--   ) c
--   WHERE c.total >= 5 AND c.err_rate >= 0.05
--     AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_edge_function_health' AND acknowledged = false AND detected_at > now() - interval '1 hour');
--
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT
--     'alert_client_errors_spike',
--     CASE WHEN cnt >= 500 THEN 'critical' WHEN cnt >= 250 THEN 'warn' ELSE 'info' END,
--     'client_errors spike: ' || cnt || ' errors in last hour (excl benign breadcrumbs)',
--     jsonb_build_object('count', cnt, 'window_hours', 1, 'excludes', 'benign event/info breadcrumbs; failure-shaped op_types re-included'),
--     'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
--   FROM (
--     SELECT COUNT(*) AS cnt FROM public.client_errors
--     WHERE created_at > now() - interval '1 hour'
--       AND ((error_code IS DISTINCT FROM 'event' AND error_code IS DISTINCT FROM 'info')
--            OR op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)')
--   ) c
--   WHERE c.cnt >= 100
--     AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_client_errors_spike' AND acknowledged = false AND detected_at > now() - interval '1 hour');
--
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT
--     'alert_cron_failures',
--     'critical',
--     'cron_call_log shows ' || cnt || ' failed (last 1h) or currently-stuck (last 6h) job(s)',
--     jsonb_build_object('count', cnt, 'failed_window_hours', 1, 'stuck_window_hours', 6),
--     'Check cron_call_log for the failing function_name (status=''failed'' or stuck status=''started''). See docs/operations/CRON_REGISTRY.md and _shared/cron_auth.ts for the auth-gate failure class (diagnose c3f8a1 lineage).'
--   FROM (
--     SELECT COUNT(*) AS cnt FROM public.cron_call_log
--     WHERE (status = 'failed' AND started_at >= now() - interval '1 hour')
--        OR (status = 'started'
--            AND started_at < now() - interval '1 hour'
--            AND started_at >= now() - interval '6 hours')
--   ) c
--   WHERE c.cnt >= 1
--     AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_cron_failures' AND acknowledged = false AND detected_at > now() - interval '1 hour');
--   $$
-- );
