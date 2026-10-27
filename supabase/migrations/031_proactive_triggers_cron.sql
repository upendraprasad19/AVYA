-- ============================================================================
-- 031_proactive_triggers_cron.sql
-- Register pg_cron schedules for the 5 new proactive trigger Edge Functions.
--
-- Schedules (cron expressions in pg_cron's UTC timezone):
--   proactive_pr_detection            */15 * * * *  → every 15 min
--   proactive_re_engagement           30 06 * * *   → daily 06:30
--   proactive_plateau_alert           30 13 * * *   → daily 13:30
--   proactive_protein_gap_alert       30 14 * * *   → daily 14:30
--   proactive_workout_window_closing  30 15 * * *   → daily 15:30
--
-- Each schedule:
--   1. Unschedule any prior version (idempotent — wrapped in DO/EXCEPTION).
--   2. Re-schedule via cron.schedule(name, cron_spec, sql) calling
--      net.http_post against the function URL with a Bearer token sourced
--      from private.morning_alert_get_service_key() (same helper used by
--      compute_coach_signals + morning_alert_* jobs).
--
-- Auth note: the new fns deploy with verify_jwt=false, so the gateway
-- does NOT validate the Bearer token. The Authorization header is sent
-- anyway for consistency with sibling jobs and so the function itself can
-- read it if it ever needs to.
-- ============================================================================

-- proactive_pr_detection — every 15 min
DO $$ BEGIN PERFORM cron.unschedule('proactive_pr_detection'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule(
  'proactive_pr_detection',
  '*/15 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/pr-detection',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $cron$
);

-- proactive_re_engagement — daily 06:30
DO $$ BEGIN PERFORM cron.unschedule('proactive_re_engagement'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule(
  'proactive_re_engagement',
  '30 06 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/re-engagement',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $cron$
);

-- proactive_plateau_alert — daily 13:30
DO $$ BEGIN PERFORM cron.unschedule('proactive_plateau_alert'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule(
  'proactive_plateau_alert',
  '30 13 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/plateau-alert',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $cron$
);

-- proactive_protein_gap_alert — daily 14:30
DO $$ BEGIN PERFORM cron.unschedule('proactive_protein_gap_alert'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule(
  'proactive_protein_gap_alert',
  '30 14 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/protein-gap-alert',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $cron$
);

-- proactive_workout_window_closing — daily 15:30
DO $$ BEGIN PERFORM cron.unschedule('proactive_workout_window_closing'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule(
  'proactive_workout_window_closing',
  '30 15 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/workout-window-closing',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $cron$
);
