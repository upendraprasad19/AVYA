-- DRAFT (OI-519 U6): NOT a migration yet. At its live step (after the L2 deploy of `revenuecat-reconcile`, with its own
-- founder go) the number is minted with `sh scripts/mint_migration.sh revenuecat_reconcile_cron`, this file moves
-- byte-identical (`git mv`) to `supabase/migrations/<n>_revenuecat_reconcile_cron.sql`, is applied with MCP
-- `apply_migration`, and the ledger + the CRON_REGISTRY row (NOT SCHEDULED YET -> scheduled) change in the same commit.
-- The 182 precedent (plan section 23).
--
-- Intent: Schedule `revenuecat-reconcile` hourly — pg_cron job `revenuecat_reconcile_hourly`, minute 52 (:22 IST), POSTing
--   to the Edge Function with the CRON_SECRET bearer (OI-519, plan docs/plans/2026-11-23-revenuecat-play-billing-51.md
--   section 4, entry point 3).
-- Destructive?: no   -- adds one cron.job row; no schema change, no row rewrite
-- Rollback strategy: inline   -- one commented cron.unschedule at the end of the file
-- Linked diagnose-doc: none (feature; OI-519)
--
-- What the job does: the stall alert for the referral-defer queue (even with ENABLE_PLAY_BILLING_MIRROR off), the
-- crashed-claim sweep, the defer drain, then a bounded re-read of Play rows near expiry or stale; one 60 s budget per run
-- (logic.ts RUN_BUDGET_MS). Telemetry: `cron_call_log` under `revenuecat-reconcile` (logCronStart / logCronEnd).
--
-- Auth: the function is deployed verify_jwt=false and gated by `_shared/cron_auth.ts` `isAuthorizedCronCall` (the
-- CRON_SECRET bearer). `private.cron_get_secret()` (migration 107) reads the same value from Vault: the shape of
-- migration 131. Never a hardcoded JWT.
--
-- URL: a literal, as in 131 (a `private.<fn>_function_url()` helper would be SECURITY DEFINER content and make this file
-- catastrophic tier for a one-line URL).
--
-- Slot: minute 52. `referral_conversions_hourly` runs at :41 (its job queues the defers this run drains, so a reward
-- credited at :41 is sent 11 minutes later); nothing else scheduled at :52 (CRON_REGISTRY.md).
--
-- Timeout: 120 s (pg_net's default is 5 s; one run can use its 60 s budget plus a 10 s RevenueCat call), so the
-- request is not abandoned while the run works and `net._http_response` records the real answer (hermes seat 2).
--
-- Idempotency: `cron.schedule(jobname, ...)` upserts by job name (pg_cron 1.6.4), so a re-apply rewrites the same job.

SELECT cron.schedule(
  'revenuecat_reconcile_hourly',
  '52 * * * *',
  $job$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/revenuecat-reconcile',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.cron_get_secret()
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $job$
);

-- Verify (manual):
--   SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'revenuecat_reconcile_hourly';
--   -- after the first tick:
--   SELECT function_name, status, http_status, error_summary, started_at
--     FROM public.cron_call_log WHERE function_name = 'revenuecat-reconcile'
--     ORDER BY started_at DESC LIMIT 3;

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- SELECT cron.unschedule(<the job name scheduled above>);
-- Unquoted on purpose (Gate 31 raw-scans migration files; OI-193, the 131 note).
