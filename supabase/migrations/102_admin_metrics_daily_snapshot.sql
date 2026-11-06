-- Intent: Daily snapshot table for admin-dashboard trend charts, plus the cron job that populates it.
-- Destructive?: no
-- Rollback strategy: inline   -- reverse DDL (unschedule cron, drop function, drop table) commented at file end
-- Linked diagnose-doc: n/a   -- feature (admin dashboard), not a bug fix
--
-- 102_admin_metrics_daily_snapshot.sql
-- Admin business-metrics dashboard, phase 2 of 2 (see also migration 101).
--
-- Scheduled at 23:45 IST (18:15 UTC), NOT just after midnight. The
-- `*_today` fields from founder_metrics_engagement()/founder_metrics_ops()
-- are cumulative-since-midnight-IST counts — running the snapshot right
-- after midnight would capture only a few minutes of "today" and make
-- every daily trend point read as near-zero. 23:45 IST captures ~99.7%
-- of the calendar day before it rolls over.
--
-- pg_cron does not guarantee exactly-once execution (independent-review
-- catch during planning). `UNIQUE(snapshot_date)` + `ON CONFLICT DO UPDATE`
-- in the Edge Function's upsert (not here — this migration only creates
-- the constraint) means a retried run corrects the same day's row instead
-- of creating a duplicate that would corrupt every trend chart.

create table if not exists public.admin_metrics_daily (
  id                              bigint generated always as identity primary key,
  snapshot_date                   date not null unique,
  total_users                     bigint,
  signups_today_ist               bigint,
  signups_7d                      bigint,
  signups_30d                     bigint,
  pro_active                      bigint,
  pro_expired                     bigint,
  free_users                      bigint,
  active_subscriptions            bigint,
  active_last_7d                  bigint,
  workouts_logged_today           bigint,
  food_logs_today                 bigint,
  ai_messages_today               bigint,
  streak_maintained_current_week  bigint,
  client_errors_today             bigint,
  client_errors_7d                bigint,
  open_alerts_count               bigint,
  cron_failures_24h               bigint,
  computed_at                     timestamptz not null default now()
);

-- RLS enabled with NO policies -> default-deny for anon/authenticated,
-- matching the convention on every other table in this DB (see
-- backups/live_schema_columns.json / list_tables — every table but the
-- documented account_deletion_log exception has rls_enabled=true).
-- service_role bypasses RLS regardless — this is defense-in-depth, not
-- the real gate. The real gate is that only a service-role Edge Function
-- ever touches this table (CLAUDE.md rule #9).
alter table public.admin_metrics_daily enable row level security;

revoke all on public.admin_metrics_daily from public;
grant select, insert, update on public.admin_metrics_daily to service_role;

-- ─────────────────────────────────────────────────────────────────────
-- Supporting indexes for the admin dashboard's created_at-window counts.
-- founder_metrics_ops()/_engagement() (migration 101) count rows by a bare
-- `created_at >= <IST day/7d>` predicate. Every existing index on these two
-- tables is user_id-LEADING (idx_*_user_created etc.), so a filter on
-- created_at alone cannot range-seek and falls to a full seq scan — run both
-- nightly (cron) AND now per admin page-load (the current tiles read these
-- LIVE). Negligible at today's volume, but client_errors + ai_coach_
-- interactions are the two fastest-growing tables here (spike telemetry / PRO-
-- unlimited chat). A created_at-leading index keeps both paths O(window), not
-- O(table). (streaks already has uq_streaks_user_week(user_id, week_start)
-- which the DISTINCT ON scans backward — no new index needed there.)
-- Hermes L31. IF NOT EXISTS = idempotent; instant at current scale.
create index if not exists idx_client_errors_created
  on public.client_errors (created_at desc);
create index if not exists idx_ai_coach_interactions_created
  on public.ai_coach_interactions (created_at desc);

-- ─────────────────────────────────────────────────────────────────────
-- Cron: compute-admin-metrics-daily, once daily, 23:45 IST = 18:15 UTC.
-- Mirrors the private.morning_alert_get_service_key() auth pattern used
-- by every other cron job (supabase/functions/CLAUDE.md — never hardcode
-- a JWT) and the per-job _function_url() helper convention (migration 028).
-- ─────────────────────────────────────────────────────────────────────
create or replace function private.compute_admin_metrics_function_url()
returns text
language sql
security definer
as $$
  select coalesce(
    (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' limit 1),
    'https://dedsavbjuwgarrhphgnl.supabase.co'
  ) || '/functions/v1/compute-admin-metrics-daily';
$$;

do $$
begin
  perform cron.unschedule('compute_admin_metrics_daily');
exception when others then null;
end $$;

select cron.schedule(
  'compute_admin_metrics_daily',
  '15 18 * * *',
  $job$
  select net.http_post(
    url := private.compute_admin_metrics_function_url(),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $job$
);

-- Verify (manual):
--   select jobname, schedule, active from cron.job where jobname = 'compute_admin_metrics_daily';
--   select * from public.admin_metrics_daily order by snapshot_date desc limit 5;
--   select has_table_privilege('anon', 'public.admin_metrics_daily', 'select');           -- expect false
--   select has_table_privilege('authenticated', 'public.admin_metrics_daily', 'select');  -- expect false
--   select has_table_privilege('service_role', 'public.admin_metrics_daily', 'select');   -- expect true

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- select cron.unschedule('compute_admin_metrics_daily');
-- drop function if exists private.compute_admin_metrics_function_url();
-- drop table if exists public.admin_metrics_daily;
-- drop index if exists public.idx_client_errors_created;
-- drop index if exists public.idx_ai_coach_interactions_created;
