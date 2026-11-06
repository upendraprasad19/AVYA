-- Intent: founder_metrics_ops()'s client_errors_today count must not include
--   error_code='info' rows — migration 134's critical-alert-dispatch
--   telemetry writes a client_errors row with error_code='info' on every
--   SUCCESSFUL alert-critical-notify send, which inflated /status's "Client
--   errors today" number by one per successful dispatch even though nothing
--   had actually gone wrong. Mirrors the exclusion pattern migrations
--   086/087 already established on the alert-spike side (error_code='info'
--   is never a real error).
-- Destructive?: no   -- replaces one function body only; no table/data touched
-- Rollback strategy: inline   -- reverse DDL (restore the un-excluded body) is commented at file end
-- Linked diagnose-doc: 82b018 (R2-10, telegram-admin-bot review round 2)
--
-- Applied live 2026-09-14 after explicit founder authorization via
-- AskUserQuestion, per CLAUDE.md §4.3 (plan approval != deploy approval).
-- See backups/applied_migrations.json for the paired record.
--
-- Full function body copied verbatim from the highest-numbered migration
-- that defines founder_metrics_ops() — 101_admin_dashboard_metrics_functions.sql
-- (102/103/120 only reference it in comments or grant/revoke ACL statements,
-- never redefine the body) — with ONLY the client_errors_today subquery
-- changed to add `and error_code is distinct from 'info'`. Every other
-- column/subquery is untouched.

CREATE OR REPLACE FUNCTION public.founder_metrics_ops()
RETURNS TABLE (
  client_errors_today  bigint,
  client_errors_7d     bigint,
  open_alerts_count    bigint,
  cron_failures_24h    bigint,
  generated_at         timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  select
    (select count(*) from public.client_errors
       where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
                            at time zone 'Asia/Kolkata')
         and error_code is distinct from 'info')::bigint,
    (select count(*) from public.client_errors
       where created_at >= now() - interval '7 days')::bigint,
    (select count(*) from public.alerts
       where resolved_at is null)::bigint,
    (select count(*) from public.cron_call_log
       where started_at >= now() - interval '24 hours'
         and (status = 'failed'
              or (status = 'started' and started_at < now() - interval '1 hour')))::bigint,
    now();
$$;

REVOKE ALL ON FUNCTION public.founder_metrics_ops() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.founder_metrics_ops() TO service_role;

-- Post-apply verification (run in the SQL editor):
--   select has_function_privilege('anon',          'public.founder_metrics_ops()', 'execute');  -- expect false
--   select has_function_privilege('authenticated', 'public.founder_metrics_ops()', 'execute');  -- expect false
--   select has_function_privilege('service_role',  'public.founder_metrics_ops()', 'execute');  -- expect true
--   select * from public.founder_metrics_ops();  -- client_errors_today must now EXCLUDE 'info' rows

-- =============================================================================
-- Rollback (inline) — restore the un-excluded client_errors_today body:
--
-- CREATE OR REPLACE FUNCTION public.founder_metrics_ops()
-- RETURNS TABLE (
--   client_errors_today  bigint,
--   client_errors_7d     bigint,
--   open_alerts_count    bigint,
--   cron_failures_24h    bigint,
--   generated_at         timestamptz
-- )
-- LANGUAGE sql
-- SECURITY DEFINER
-- SET search_path = public
-- AS $$
--   select
--     (select count(*) from public.client_errors
--        where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
--                             at time zone 'Asia/Kolkata'))::bigint,
--     (select count(*) from public.client_errors
--        where created_at >= now() - interval '7 days')::bigint,
--     (select count(*) from public.alerts
--        where resolved_at is null)::bigint,
--     (select count(*) from public.cron_call_log
--        where started_at >= now() - interval '24 hours'
--          and (status = 'failed'
--               or (status = 'started' and started_at < now() - interval '1 hour')))::bigint,
--     now();
-- $$;
-- REVOKE ALL ON FUNCTION public.founder_metrics_ops() FROM PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.founder_metrics_ops() TO service_role;
-- =============================================================================
