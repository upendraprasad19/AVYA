-- ============================================================================
-- 040_rank_promotions_cron.sql
--
-- Register a pg_cron schedule for the nightly evaluate-rank-promotions
-- Edge Function. Catches users whose client-side firings missed
-- (background install, app uninstalled while a milestone passed, etc.).
--
-- Schedule: 18:30 UTC nightly  =  00:00 IST
-- Function: evaluate-rank-promotions  (verify_jwt: false, cron-only)
--
-- Uses the same private.morning_alert_get_service_key() helper as
-- migrations 031 + compute_coach_signals — auth header consistency.
--
-- Idempotent — DO/EXCEPTION wrapper unschedules any prior version
-- before re-creating, so re-applying the migration is safe.
-- ============================================================================

DO $$
BEGIN
  PERFORM cron.unschedule('evaluate_rank_promotions');
EXCEPTION
  WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'evaluate_rank_promotions',
  '30 18 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/evaluate-rank-promotions',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $cron$
);
