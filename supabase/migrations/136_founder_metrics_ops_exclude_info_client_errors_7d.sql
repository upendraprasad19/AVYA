-- Intent: founder_metrics_ops()'s client_errors_7d count must not include
--   error_code='info' rows either — migration 135 fixed this exclusion for
--   client_errors_today but left its sibling client_errors_7d subquery on
--   the same table with the same inflation bug. Migration 134's critical-
--   alert-dispatch telemetry writes a client_errors row with
--   error_code='info' on every SUCCESSFUL alert-critical-notify send, which
--   inflates BOTH client_errors_today (now fixed by 135) AND client_errors_7d
--   (this migration) — same table, same root cause, same fix, applied to the
--   remaining subquery 135 missed. Corroborated independently by 3 Hermes
--   lenses (L1, L22, L35) on 2026-09-14 (F1,
--   docs/audit/2026-09-14-hermes-telegram-admin-bot.md).
-- Destructive?: no   -- replaces one function body only; no table/data touched
-- Rollback strategy: inline   -- reverse DDL (restore 135's un-excluded client_errors_7d body) is commented at file end
-- Linked diagnose-doc: 82b018 (R2-10 / F1, telegram-admin-bot Hermes pass 2026-09-14)
--
-- Applied live 2026-09-14 after explicit founder authorization via
-- AskUserQuestion, per CLAUDE.md §4.3 (plan approval != deploy approval).
-- See backups/applied_migrations.json for the paired record.
--
-- Full function body copied verbatim from the highest-numbered migration
-- that defines founder_metrics_ops() — 135_founder_metrics_ops_exclude_info_
-- client_errors.sql (the immutable, already-applied live definition) — with
-- ONLY the client_errors_7d subquery changed to add
-- `and error_code is distinct from 'info'`, matching what 135 already did
-- for client_errors_today. Every other column/subquery is untouched.

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
       where created_at >= now() - interval '7 days'
         and error_code is distinct from 'info')::bigint,
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
--   select * from public.founder_metrics_ops();  -- client_errors_7d must now EXCLUDE 'info' rows too

-- =============================================================================
-- Rollback (inline) — restore 135's client_errors_7d body (un-excluded):
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
--                             at time zone 'Asia/Kolkata')
--          and error_code is distinct from 'info')::bigint,
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
