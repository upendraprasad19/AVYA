-- 046_morning_alert_personalized_delivery_cron.sql
-- Theme E · APK Test #8 — personalize morning push delivery to user wake_up_time.
--
-- (1) Defines morning_alert_pick_quarter RPC: returns users whose
--     wake_up_time floored to 15 min equals the current IST quarter, with
--     NULL fallback to the 07:00 quarter so legacy/restored profiles
--     missing wake_up_time still get the push at 7 AM IST.
-- (2) Drops the existing single-shot 07:00 IST morning_alert_deliver cron.
-- (3) Replaces it with morning_alert_deliver_late + morning_alert_deliver_early
--     running every 15 min, spanning UTC midnight to cover IST 04:00–11:59.

-- ─────────────────────────────────────────────────────────────────────
-- 1. RPC for the wake-time-aware paginated select.
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.morning_alert_pick_quarter(
  p_today    DATE,
  p_quarter  TEXT,        -- 'HH:MM:SS' from floorToQuarterIst()
  p_fallback BOOLEAN,     -- true when p_quarter = '07:00:00'
  p_offset   INTEGER,
  p_limit    INTEGER
)
RETURNS TABLE (user_id UUID, snapshot_json JSONB)
LANGUAGE sql
STABLE
AS $$
  SELECT s.user_id, s.snapshot_json
  FROM   public.user_daily_snapshots s
  JOIN   public.user_profile p ON p.user_id = s.user_id
  WHERE  s.snapshot_date = p_today
    AND  s.snapshot_json -> 'morning_alert' IS NOT NULL
    AND  (
            -- Normal: wake_up_time floored to 15 min equals current quarter.
            (
              p.wake_up_time IS NOT NULL
              AND make_time(
                    EXTRACT(HOUR   FROM p.wake_up_time)::INTEGER,
                    (FLOOR(EXTRACT(MINUTE FROM p.wake_up_time) / 15) * 15)::INTEGER,
                    0
                  )::TEXT = p_quarter
            )
            -- Fallback: NULL wake_up_time gets the 07:00 IST quarter only.
            OR (p.wake_up_time IS NULL AND p_fallback)
         )
  ORDER BY s.user_id
  LIMIT  p_limit
  OFFSET p_offset;
$$;

GRANT EXECUTE ON FUNCTION public.morning_alert_pick_quarter
  TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Drop the single 07:00 IST delivery cron.
-- ─────────────────────────────────────────────────────────────────────

SELECT cron.unschedule('morning_alert_deliver');

-- ─────────────────────────────────────────────────────────────────────
-- 3. Two cron rows running every 15 min, spanning UTC midnight to
--    cover IST 04:00–11:59.
-- ─────────────────────────────────────────────────────────────────────

-- IST 03:30 → 05:59 = UTC 22:00 → 23:59 (previous calendar day)
SELECT cron.schedule(
  'morning_alert_deliver_late',
  '*/15 22-23 * * *',
  $$
    SELECT net.http_post(
      url     := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/morning-alert',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object('mode','deliver')
    );
  $$
);

-- IST 05:30 → 12:14 = UTC 00:00 → 06:59 (same day)
SELECT cron.schedule(
  'morning_alert_deliver_early',
  '*/15 0-6 * * *',
  $$
    SELECT net.http_post(
      url     := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/morning-alert',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object('mode','deliver')
    );
  $$
);
