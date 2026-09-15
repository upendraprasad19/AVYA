-- 047_clean_orphan_media_cron.sql
-- F16 · Test #9 — 30-day TTL for free-user coach media.
--
-- Daily cron at 03:00 UTC posts to the clean-orphan-media Edge Function
-- which scans storage for free-user objects > 30 days old and deletes them.
-- The Edge Function rechecks isPro on each candidate to handle race with
-- mid-window upgrades.

CREATE OR REPLACE FUNCTION public.find_orphan_coach_media(p_cutoff TIMESTAMPTZ)
RETURNS TABLE (user_id UUID, path TEXT)
LANGUAGE sql
STABLE
AS $$
  SELECT
    NULLIF((REGEXP_MATCH(o.name, '^([0-9a-f-]{36})/'))[1], '')::UUID AS user_id,
    o.name AS path
  FROM   storage.objects o
  WHERE  o.bucket_id = 'coach-media'
    AND  o.created_at < p_cutoff
    AND  EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = NULLIF((REGEXP_MATCH(o.name, '^([0-9a-f-]{36})/'))[1], '')::UUID
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = NULLIF((REGEXP_MATCH(o.name, '^([0-9a-f-]{36})/'))[1], '')::UUID
        AND s.status = 'active'
        AND s.end_date > NOW()
    );
$$;

GRANT EXECUTE ON FUNCTION public.find_orphan_coach_media TO service_role;

SELECT cron.schedule(
  'clean_orphan_media_daily',
  '0 3 * * *',
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/clean-orphan-media',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object()
    );
  $$
);
