-- 043_i_see_you_cron.sql
-- Registers the daily i-see-you-callout cron at 19:30 IST (14:00 UTC).
-- Source: APK Test #4 Plan C / C3.

SELECT cron.schedule(
  'i-see-you-daily',
  '0 14 * * *',  -- 14:00 UTC = 19:30 IST
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/i-see-you-callout',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
      ),
      body := '{}'::jsonb
    );
  $$
);
