-- Intent: Bound the two unbounded log tables — 14-day retention on cron.job_run_details and 30-day on public.client_errors — plus a daily VACUUM (ANALYZE) on each.
-- Destructive?: yes   -- deletes ~29,044 run records and ~10,654 client_errors rows on the first pass; rows are NOT recoverable
-- Rollback strategy: inline   -- reverse block at the end of this file; DDL ONLY (deleted rows cannot be restored)
-- Linked diagnose-doc: c8e5b3

-- ─────────────────────────────────────────────────────────────────────
-- ⚠ THIS FILE IS A RECONSTRUCTION. DO NOT APPLY IT.
--
-- These statements ALREADY RAN on prod as `log_table_retention`
-- (supabase_migrations.schema_migrations version 20260815155823, applied
-- 2026-08-15). What did NOT happen is any of the artifacts that make an applied
-- migration legible afterwards: no .sql file, no backups/applied_migrations.json
-- entry, no diagnose-doc (the header above cites c8e5b3, which did not exist),
-- and no CRON_REGISTRY entries for the four jobs it created.
--
-- The body below is recovered VERBATIM from
-- `supabase_migrations.schema_migrations.statements` on 2026-08-20, not
-- rewritten from memory. Filed and explained in OI-132.
--
-- WHY THE ABSENCE MATTERED MORE THAN THE MIGRATION:
-- Gate 31 (scripts/check_cron_registry.dart) enforces cron-registry parity by
-- SCANNING `supabase/migrations/*.sql` for `cron.schedule(...)`. A migration
-- with no file is therefore invisible to the gate built to catch exactly this —
-- the missing file does not merely skip the gate, it defeats it by
-- construction, and the gate reports green while four undocumented jobs (two of
-- them row-destructive) run daily against prod.
--
-- Measured 2026-08-20: 28 live cron jobs, 24 in the registry, 4 missing — and
-- the 4 missing are precisely this migration's. Gate 31's blind spot accounted
-- for 100% of the registry gap; the registry was otherwise perfect.
--
-- Re-applying is not needed and not wanted. `cron.schedule` on an existing name
-- updates in place rather than duplicating, so a replay would be survivable, but
-- the DELETEs would run again immediately rather than on schedule.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cleanup_cron_job_run_details()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  DELETE FROM cron.job_run_details d
  WHERE d.start_time < now() - interval '14 days'
    AND d.runid NOT IN (
      SELECT k.runid FROM (
        SELECT DISTINCT ON (jobid) runid
        FROM cron.job_run_details
        ORDER BY jobid, start_time DESC, runid DESC
      ) AS k
    );
$fn$;

-- NOTE for anyone editing this file later: these three lines are CORRECT and
-- must not be "simplified". A SECURITY DEFINER function created fresh inherits
-- Supabase's default privileges on schema public, which grant EXECUTE to `anon`
-- and `authenticated`; `REVOKE ALL ... FROM PUBLIC` does NOT remove an explicit
-- role grant. Migration 120 got this wrong and shipped an anon-executable
-- SECURITY DEFINER function to prod for ~3m12s (diagnose a9d3f1). This
-- migration got it right.
--
-- `service_role` IS NOT MISSING. Verified live 2026-08-20: the ACL on both
-- functions reads `postgres=X/postgres | service_role=X/postgres` — no anon,
-- no authenticated, no PUBLIC. The service_role grant comes from Supabase's
-- ALTER DEFAULT PRIVILEGES on schema public, not from this migration (the
-- recovered statements mention `service_role` zero times). Do not "restore" a
-- GRANT that was never here; the observed ACL is what these lines produce.
REVOKE ALL ON FUNCTION public.cleanup_cron_job_run_details() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_cron_job_run_details() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_cron_job_run_details() TO postgres;

CREATE OR REPLACE FUNCTION public.cleanup_client_errors()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  DELETE FROM public.client_errors
  WHERE created_at < now() - interval '30 days';
$fn$;

REVOKE ALL ON FUNCTION public.cleanup_client_errors() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_client_errors() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_client_errors() TO postgres;

SELECT cron.schedule(
  'jrd_retention_daily',
  '22 4 * * *',
  $job$ SELECT public.cleanup_cron_job_run_details(); $job$
);

SELECT cron.schedule(
  'client_errors_retention_daily',
  '25 4 * * *',
  $job$ SELECT public.cleanup_client_errors(); $job$
);

SELECT cron.schedule(
  'jrd_vacuum_daily',
  '38 4 * * *',
  $job$ VACUUM (ANALYZE) cron.job_run_details; $job$
);

SELECT cron.schedule(
  'client_errors_vacuum_daily',
  '41 4 * * *',
  $job$ VACUUM (ANALYZE) public.client_errors; $job$
);

-- ── ROLLBACK (inline) ────────────────────────────────────────────────
-- DDL only. The rows these jobs have already deleted are NOT recoverable —
-- roughly 29,044 cron run records and 10,654 client_errors rows on the first
-- pass alone, plus everything aged out since 2026-08-15.
--
-- SELECT cron.unschedule('jrd_retention_daily');
-- SELECT cron.unschedule('client_errors_retention_daily');
-- SELECT cron.unschedule('jrd_vacuum_daily');
-- SELECT cron.unschedule('client_errors_vacuum_daily');
-- DROP FUNCTION IF EXISTS public.cleanup_cron_job_run_details();
-- DROP FUNCTION IF EXISTS public.cleanup_client_errors();
