-- Intent: Schedule the founder's daily Telegram digest — pg_cron job `founder_digest_daily`, 02:30 UTC = 08:00 IST, POSTing to the `founder-digest` Edge Function with the CRON_SECRET bearer (OI-153, Unit E).
-- Destructive?: no   -- adds one cron.job row; no schema change, no row rewrite
-- Rollback strategy: inline   -- one commented cron.unschedule at the end of the file
-- Linked diagnose-doc: a9d4e7
--
-- 131_founder_digest_cron.sql
--
-- What the job does: once a day, `founder-digest` reads yesterday's IST-day
-- `usage_counters` rows and the `alerts` rows raised that day and sends ONE
-- Telegram message to the founder. It runs on quiet days too — the message's
-- ARRIVAL is the liveness signal; its absence means the cron or the bot is
-- dead, which `alert_cron_function_dead` (8-day window, jobid 32) would
-- otherwise take a week to notice.
--
-- Auth: the function is verify_jwt=false and gated by
-- `_shared/cron_auth.ts` `isAuthorizedCronCall`, which compares the bearer
-- to the CRON_SECRET Edge Function secret. `private.cron_get_secret()`
-- (migration 107) reads the same value from Vault, so the job sends
-- `Authorization: Bearer <CRON_SECRET>` — the identical shape every cron job
-- repointed by migration 108 uses. Never hardcode a JWT here.
--
-- URL: a literal, deliberately, rather than a `private.<fn>_function_url()`
-- helper (migration 028/102 convention). Those helpers are SECURITY DEFINER
-- functions, and `docs/blast_radius.yaml`'s content rule classifies ANY
-- migration containing that phrase as catastrophic — a Hermes-tier review
-- for a one-line URL. The project ref is fixed (CLAUDE.md §2a); a literal is
-- the honest tier for what this file does.
--
-- Slot: 02:30 UTC. `morning_alert_deliver_early` (jobid 17, `*/15 0-6`) also
-- fires at that minute; pg_cron runs jobs concurrently, and the digest is a
-- read + one HTTP call, so no interaction. 08:00 IST is the founder's chosen
-- reading time.
--
-- Idempotency: `cron.schedule(jobname, …)` UPSERTS by job name in pg_cron
-- >= 1.4 (this project runs 1.6.4 — `select extversion from pg_extension where
-- extname = 'pg_cron'`, 2026-09-13), so re-applying this file rewrites the
-- same job rather than adding a duplicate.

SELECT cron.schedule(
  'founder_digest_daily',
  '30 2 * * *',
  $job$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/founder-digest',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.cron_get_secret()
    ),
    body := '{}'::jsonb
  );
  $job$
);

-- Verify (manual):
--   SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'founder_digest_daily';
--   -- after the first tick (or a manual net.http_post of the same command):
--   SELECT function_name, status, http_status, error_summary, started_at
--     FROM public.cron_call_log WHERE function_name = 'founder-digest'
--     ORDER BY started_at DESC LIMIT 3;

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- SELECT cron.unschedule(<the job name scheduled above>);
--
-- The name is deliberately NOT quoted in this comment: Gate 31
-- (scripts/check_cron_registry.dart) raw-scans migration files, and a
-- commented unschedule of a QUOTED job name REMOVES that name from the gate's
-- input set, so the registry row would stop being demanded. Nine earlier
-- migrations carry that exact shape in a comment, and eleven carry an
-- uncommented unschedule-then-reschedule the gate's unordered set arithmetic
-- drops the same way (OI-193).
