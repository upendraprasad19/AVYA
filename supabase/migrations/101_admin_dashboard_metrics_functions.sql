-- Intent: Admin-dashboard read functions (engagement/ops metrics + a founder_metrics() wrapper), all in `public` schema.
-- Destructive?: no   -- creates functions + grants only, no data change
-- Rollback strategy: inline   -- reverse DDL (drop functions) commented at file end
-- Linked diagnose-doc: n/a   -- feature (admin dashboard), not a bug fix
--
-- 101_admin_dashboard_metrics_functions.sql
-- Admin business-metrics dashboard, phase 1 of 2 (see also migration 102).
--
-- WHY `public` SCHEMA, NOT `private` (independent-review catch during
-- planning, verified against live config before writing a line of SQL):
--   `supabase/config.toml` (`[api] schemas = ["public", "graphql_public"]`)
--   only exposes `public`/`graphql_public` to PostgREST. A `private`-schema
--   function is invisible to `.rpc()` regardless of role/grants — this has
--   nothing to do with permissions, it's schema exposure. Every existing
--   Edge Function `.rpc()` call in this repo already targets a `public`
--   function (`active_users_for_signals`, `community_votes_summary`,
--   `increment_promo_used_count`, etc.) — migration 028 is the closest
--   precedent: it creates a `private` schema but defines its actual
--   Edge-Function-callable functions in `public`. `private.founder_metrics()`
--   (migration 093) has almost certainly only ever been called via the SQL
--   editor's direct Postgres connection, never from an Edge Function.
--
-- Same lockdown as migration 093 (SECURITY DEFINER + REVOKE FROM PUBLIC +
-- GRANT to service_role only), just in the schema PostgREST actually serves.
-- `private.founder_metrics()` itself is left untouched — `founder_metrics_
-- for_admin_api()` below wraps it so the SQL-editor path keeps working
-- unchanged while the Edge Function gets a reachable entry point.
--
-- IST "today" boundary matches founder_metrics()'s own convention: date
-- columns compare against `(now() at time zone 'Asia/Kolkata')::date`;
-- timestamptz columns compare against IST midnight.

-- ─────────────────────────────────────────────────────────────────────
-- 1. Wrapper: expose the existing private.founder_metrics() via `public`.
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.founder_metrics_for_admin_api()
returns table (
  total_users          bigint,
  signups_today_ist    bigint,
  signups_7d           bigint,
  signups_30d          bigint,
  pro_active           bigint,
  pro_expired          bigint,
  free_users           bigint,
  active_subscriptions bigint,
  active_last_7d       bigint,
  generated_at         timestamptz
)
language sql
security definer
set search_path = public, private
as $$
  select * from private.founder_metrics();
$$;

revoke all on function public.founder_metrics_for_admin_api() from public;
grant execute on function public.founder_metrics_for_admin_api() to service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2. Engagement & Retention tab metrics.
--    Columns grounded against backups/live_schema_columns.json (2026-07-12):
--    workout_logs.date, nutrition_logs.date, ai_coach_interactions.created_at,
--    streaks.(user_id, week_start, is_streak_maintained).
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.founder_metrics_engagement()
returns table (
  workouts_logged_today          bigint,
  food_logs_today                bigint,
  ai_messages_today               bigint,
  streak_maintained_current_week bigint,
  generated_at                    timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    (select count(*) from public.workout_logs
       where date = (now() at time zone 'Asia/Kolkata')::date)::bigint,
    (select count(*) from public.nutrition_logs
       where date = (now() at time zone 'Asia/Kolkata')::date)::bigint,
    (select count(*) from public.ai_coach_interactions
       where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
                            at time zone 'Asia/Kolkata'))::bigint,
    -- "Currently on-streak" proxy: each user's MOST RECENT week_start row
    -- has is_streak_maintained = true. streaks is a weekly plan-adherence
    -- record (workouts_planned/completed per week), not a running daily
    -- counter — see live_schema_columns.json; do not confuse with a
    -- day-count streak.
    (select count(*) from (
       select distinct on (user_id) user_id, is_streak_maintained
       from public.streaks
       order by user_id, week_start desc
     ) latest
     where latest.is_streak_maintained is true)::bigint,
    now();
$$;

revoke all on function public.founder_metrics_engagement() from public;
grant execute on function public.founder_metrics_engagement() to service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3. Ops Health tab metrics.
--    cron_call_log.status values per _shared/cron_telemetry.ts:
--    'started' (logCronStart) -> 'success' | 'failed' (logCronEnd). A row
--    stuck at 'started' past a generous 1h window means the function died
--    before reporting a terminal status (crash, timeout, cold-start hang).
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.founder_metrics_ops()
returns table (
  client_errors_today  bigint,
  client_errors_7d     bigint,
  open_alerts_count    bigint,
  cron_failures_24h    bigint,
  generated_at         timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    (select count(*) from public.client_errors
       where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
                            at time zone 'Asia/Kolkata'))::bigint,
    (select count(*) from public.client_errors
       where created_at >= now() - interval '7 days')::bigint,
    (select count(*) from public.alerts
       where resolved_at is null)::bigint,
    (select count(*) from public.cron_call_log
       where started_at >= now() - interval '24 hours'
         and (status = 'failed'
              or (status = 'started' and started_at < now() - interval '1 hour')))::bigint,
    now();
$$;

revoke all on function public.founder_metrics_ops() from public;
grant execute on function public.founder_metrics_ops() to service_role;

-- ─────────────────────────────────────────────────────────────────────
-- Post-apply verification (run in the SQL editor; all three must match):
--   select has_function_privilege('anon',          'public.founder_metrics_engagement()', 'execute');  -- expect false
--   select has_function_privilege('authenticated', 'public.founder_metrics_engagement()', 'execute');  -- expect false
--   select has_function_privilege('service_role',  'public.founder_metrics_engagement()', 'execute');  -- expect true
--   -- repeat for founder_metrics_ops() and founder_metrics_for_admin_api()
--   select * from public.founder_metrics_for_admin_api();
--   select * from public.founder_metrics_engagement();
--   select * from public.founder_metrics_ops();
-- ─────────────────────────────────────────────────────────────────────

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- drop function if exists public.founder_metrics_for_admin_api();
-- drop function if exists public.founder_metrics_engagement();
-- drop function if exists public.founder_metrics_ops();
