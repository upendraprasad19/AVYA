-- Intent: Bundle four independent, low-risk fixes surfaced by the 2026-09-21/22
--   disk-IO-budget-exhaustion investigation: (1) retune memory_embeddings' IVFFlat
--   index for its actual row count, (2) fix readiness_daily's RLS auth-initplan
--   perf warning, (3) drop two verified-dead indexes on high-churn tables, and
--   (4) consolidate 9 cron jobs into 3 (same behavior, fewer scheduler entries).
--   None of these are behavior changes from the app's perspective except the two
--   cadence changes noted in section 4 (ops alerts 15min->30min; PR detection
--   15min->hourly), which were explicit product decisions, not accidents.
-- Destructive?: no — every change here is DROP+CREATE of a derived structure
--   (index, RLS policy, cron schedule entry), never a data-bearing table/column.
--   No rows are read, written, or deleted by this migration.
-- Rollback strategy: inline — see commented block at end of file
-- Linked diagnose-doc: e8b4a1

-- ============================================================================
-- 1. Retune memory_embeddings IVFFlat index (lists=100 -> lists=10)
--    Verified: 839 rows in the table today, not the ~1M the original lists=100
--    was tuned for (see migration 20260331000001's header). At ~8 rows per list,
--    the index was 25x the size of the actual table data (9040kB index vs 360kB
--    table) for no recall benefit. pgvector guidance: lists ~= rows/1000 for
--    corpora under 1M rows; 10 is a safe, conservative value at this scale that
--    can be re-tuned upward as the corpus grows.
-- ============================================================================

DROP INDEX IF EXISTS public.idx_memory_embeddings_ivfflat;

CREATE INDEX idx_memory_embeddings_ivfflat
  ON public.memory_embeddings
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 10);

-- ============================================================================
-- 2. Fix readiness_daily RLS auth-initplan warning (Supabase advisor, verified)
--    auth.uid() was being re-evaluated per row instead of once per query.
-- ============================================================================

DROP POLICY IF EXISTS users_own_readiness_daily ON public.readiness_daily;

CREATE POLICY users_own_readiness_daily ON public.readiness_daily
  FOR ALL
  USING ((select auth.uid()) = user_id)
  WITH CHECK ((select auth.uid()) = user_id);

-- ============================================================================
-- 3. Drop 2 verified-dead indexes on high-churn tables (idx_scan=0, confirmed
--    live against pg_stat_user_indexes, not just the advisor's own claim).
--    The other 12 advisor-flagged unused indexes are intentionally left alone —
--    two are auth/payment-adjacent and may be low-frequency rather than dead;
--    tracked as OI-236 for a separate, unhurried review.
-- ============================================================================

DROP INDEX IF EXISTS public.idx_ai_coach_interactions_tool_calls_failed;
DROP INDEX IF EXISTS public.idx_nutrition_log_items_food_id;

-- ============================================================================
-- 4. Cron consolidation: 9 jobs -> 3, same functionality, fewer scheduler
--    entries. See docs/operations/CRON_REGISTRY.md for the updated registry.
-- ============================================================================

-- 4a. Nightly housekeeping (6 -> 1). clean_orphan_media_daily is deliberately
--     excluded — it's an HTTP call to an Edge Function, not pure SQL, and
--     mixing network I/O with DELETE/VACUUM statements risks a slow HTTP call
--     delaying the SQL cleanup behind it.
SELECT cron.unschedule('cron_call_log_cleanup_daily');
SELECT cron.unschedule('usage_counters_retention_daily');
SELECT cron.unschedule('jrd_retention_daily');
SELECT cron.unschedule('client_errors_retention_daily');
SELECT cron.unschedule('jrd_vacuum_daily');
SELECT cron.unschedule('client_errors_vacuum_daily');

SELECT cron.schedule(
  'db_maintenance_nightly',
  '30 3 * * *',
  $$
  SELECT public.cleanup_cron_call_log();
  SELECT public.cleanup_usage_counters();
  SELECT public.cleanup_cron_job_run_details();
  SELECT public.cleanup_client_errors();
  VACUUM (ANALYZE) cron.job_run_details;
  VACUUM (ANALYZE) public.client_errors;
  $$
);

-- 4b. Ops alerts (3 -> 1), cadence 15min -> 30min (explicit founder decision:
--     keep fast enough to matter for incident detection, slow enough to save
--     real CPU on a Nano-tier instance already reading 91% CPU utilization).
--     Note: alert_edge_function_health's err_rate guard is independently known
--     to be structurally broken (never fires — 401s write no cron_call_log
--     row) — tracked as OI-234, NOT fixed here, rides along broken as-is.
--     alert_cron_failures was created live by migration 139 on a separate
--     in-flight branch (uncommitted there as of this writing) — this migration
--     assumes it already exists by the time 141 runs.
SELECT cron.unschedule('alert_edge_function_health');
SELECT cron.unschedule('alert_client_errors_spike');
SELECT cron.unschedule('alert_cron_failures');

SELECT cron.schedule(
  'ops_alerts_30min',
  '*/30 * * * *',
  $$
  -- alert_edge_function_health
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

  -- alert_client_errors_spike
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_client_errors_spike',
    CASE WHEN cnt >= 500 THEN 'critical' WHEN cnt >= 250 THEN 'warn' ELSE 'info' END,
    'client_errors spike: ' || cnt || ' errors in last hour (excl benign breadcrumbs)',
    jsonb_build_object('count', cnt, 'window_hours', 1, 'excludes', 'benign event/info breadcrumbs; failure-shaped op_types re-included'),
    'Inspect docs/diagnoses for recent regression; correlate with last APK build.'
  FROM (
    SELECT COUNT(*) AS cnt FROM public.client_errors
    WHERE created_at > now() - interval '1 hour'
      AND ((error_code IS DISTINCT FROM 'event' AND error_code IS DISTINCT FROM 'info')
           OR op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)')
  ) c
  WHERE c.cnt >= 100
    AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_client_errors_spike' AND acknowledged = false AND detected_at > now() - interval '1 hour');

  -- alert_cron_failures
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_failures', 'critical',
    'cron_call_log shows ' || cnt || ' failed (last 1h) or currently-stuck job(s)',
    jsonb_build_object('count', cnt, 'failed_window_hours', 1, 'stuck_after_hours', 1),
    'Check cron_call_log for the failing function_name (status=''failed'' or stuck status=''started''). See docs/operations/CRON_REGISTRY.md and _shared/cron_auth.ts for the auth-gate failure class (diagnose c3f8a1 lineage).'
  FROM (
    SELECT COUNT(*) AS cnt FROM public.cron_call_log
    WHERE (status = 'failed' AND started_at >= now() - interval '1 hour')
       OR (status = 'started' AND started_at < now() - interval '1 hour')
  ) c
  WHERE c.cnt >= 1
    AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'alert_cron_failures' AND acknowledged = false AND detected_at > now() - interval '1 hour');
  $$
);

-- 4c. proactive_pr_detection: 15min -> hourly (explicit product decision — PR
--     congratulation notifications have no meaningful latency requirement).
--     NOTE: registry flags this job as the de-facto heartbeat alert_cron_silence
--     implicitly relies on for "something succeeded recently". Hourly still
--     clears the 2-hour silence threshold with a full hour of margin. Recommend
--     watching alert_cron_silence for false positives for one week after this
--     ships. Uses cron.alter_job (pg_cron >=1.5) to preserve the existing jobid
--     and its cron.job_run_details history, rather than unschedule+reschedule.
SELECT cron.alter_job(
  job_id := (SELECT jobid FROM cron.job WHERE jobname = 'proactive_pr_detection'),
  schedule := '0 * * * *'
);

-- Rollback (commented — apply as a follow-up migration if needed):
-- DROP INDEX IF EXISTS public.idx_memory_embeddings_ivfflat;
-- CREATE INDEX idx_memory_embeddings_ivfflat ON public.memory_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
--
-- DROP POLICY IF EXISTS users_own_readiness_daily ON public.readiness_daily;
-- CREATE POLICY users_own_readiness_daily ON public.readiness_daily FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
--
-- CREATE INDEX idx_ai_coach_interactions_tool_calls_failed ON public.ai_coach_interactions USING gin (tool_calls) WHERE (tool_calls IS NOT NULL);
-- CREATE INDEX idx_nutrition_log_items_food_id ON public.nutrition_log_items USING btree (food_id);
--
-- SELECT cron.unschedule('db_maintenance_nightly');
-- SELECT cron.schedule('cron_call_log_cleanup_daily', '30 3 * * *', $$SELECT public.cleanup_cron_call_log();$$);
-- SELECT cron.schedule('usage_counters_retention_daily', '45 3 * * *', $$SELECT public.cleanup_usage_counters();$$);
-- SELECT cron.schedule('jrd_retention_daily', '22 4 * * *', $$SELECT public.cleanup_cron_job_run_details();$$);
-- SELECT cron.schedule('client_errors_retention_daily', '25 4 * * *', $$SELECT public.cleanup_client_errors();$$);
-- SELECT cron.schedule('jrd_vacuum_daily', '38 4 * * *', $$VACUUM (ANALYZE) cron.job_run_details;$$);
-- SELECT cron.schedule('client_errors_vacuum_daily', '41 4 * * *', $$VACUUM (ANALYZE) public.client_errors;$$);
--
-- SELECT cron.unschedule('ops_alerts_30min');
-- -- (recreate alert_edge_function_health, alert_client_errors_spike, alert_cron_failures individually at */15 * * * * — see migrations 076, 077, 139)
--
-- SELECT cron.alter_job(job_id := (SELECT jobid FROM cron.job WHERE jobname = 'proactive_pr_detection'), schedule := '*/15 * * * *');
