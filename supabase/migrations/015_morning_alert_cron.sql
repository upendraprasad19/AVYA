-- ─────────────────────────────────────────────────────────────────────
-- Bug #18 — Schedule morning-alert Edge Function via pg_cron
-- ─────────────────────────────────────────────────────────────────────
-- Two scheduled jobs:
--   1. morning_alert_generate — 02:00 IST (=20:30 UTC previous day)
--      Generates personalised alerts for active users and stores them
--      in user_daily_snapshots.snapshot_json.morning_alert.
--   2. morning_alert_deliver  — 07:00 IST (=01:30 UTC)
--      Reads stored alerts and delivers via OneSignal push + Telegram.
--
-- Both jobs invoke the same Edge Function with different `mode` payloads
-- via net.http_post() (pg_net extension).
--
-- Service role key is read from the Supabase Vault (recommended pattern
-- for any cron job that needs to call an authed Edge Function). The vault
-- secret `service_role_key` MUST be set via the Supabase Dashboard
-- (Project Settings → Vault) before this migration is applied. See the
-- comment block at the bottom of this file for the exact dashboard steps.
-- ─────────────────────────────────────────────────────────────────────

-- 1. Enable required extensions (idempotent)
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

-- 1a. Ensure private schema exists for helper functions (idempotent)
create schema if not exists private;

-- 2. Helper: read service role key from vault.
--    Falls back to NULL if vault entry is missing (cron will fail loudly
--    in net.http_post — better than silently sending unauthed requests).
create or replace function private.morning_alert_get_service_key()
returns text
language sql
security definer
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = 'service_role_key'
  limit 1;
$$;

-- 3. Helper: build the full Edge Function URL.
--    Uses the project's public URL pulled from vault if present, else
--    falls back to the hardcoded fitness-app project URL.
create or replace function private.morning_alert_function_url()
returns text
language sql
security definer
as $$
  select coalesce(
    (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' limit 1),
    'https://dedsavbjuwgarrhphgnl.supabase.co'
  ) || '/functions/v1/morning-alert';
$$;

-- 4. Unschedule any prior versions of these jobs (idempotent re-runs)
do $$
begin
  perform cron.unschedule('morning_alert_generate');
exception when others then null;
end $$;

do $$
begin
  perform cron.unschedule('morning_alert_deliver');
exception when others then null;
end $$;

-- 5. Schedule generation job: 02:00 IST = 20:30 UTC previous day
select cron.schedule(
  'morning_alert_generate',
  '30 20 * * *',
  $job$
  select net.http_post(
    url := private.morning_alert_function_url(),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := jsonb_build_object('mode', 'generate')
  );
  $job$
);

-- 6. Schedule delivery job: 07:00 IST = 01:30 UTC same day
select cron.schedule(
  'morning_alert_deliver',
  '30 01 * * *',
  $job$
  select net.http_post(
    url := private.morning_alert_function_url(),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := jsonb_build_object('mode', 'deliver')
  );
  $job$
);

-- ─────────────────────────────────────────────────────────────────────
-- Vault setup (REQUIRED before this migration takes effect)
-- ─────────────────────────────────────────────────────────────────────
-- 1. Open Supabase Dashboard → Project Settings → Vault → Secrets
-- 2. Add a new secret:
--      Name:  service_role_key
--      Value: <copy from Project Settings → API → service_role key>
-- 3. (Optional) Add a second secret if your project URL ever changes:
--      Name:  project_url
--      Value: https://dedsavbjuwgarrhphgnl.supabase.co
-- 4. Verify both jobs are scheduled:
--      select jobname, schedule, active from cron.job;
-- 5. Watch execution history (after first run):
--      select jobid, runid, job_pid, status, return_message, start_time, end_time
--      from cron.job_run_details
--      where jobid in (select jobid from cron.job where jobname like 'morning_alert%')
--      order by start_time desc
--      limit 20;
-- ─────────────────────────────────────────────────────────────────────
