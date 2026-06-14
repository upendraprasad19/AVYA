-- Intent: Admin-gated founder growth-metrics function (signups / users / PRO counts).
-- Destructive?: no   -- creates a private schema + function + grants; reads only, no data change
-- Rollback strategy: inline   -- reverse DDL (drop function) commented at file end
-- Linked diagnose-doc: n/a   -- feature (founder visibility), not a bug fix
--
-- 093_founder_metrics_admin_function.sql
-- Unit 5 (2026-06-14): an admin-gated growth-metrics snapshot for the founder
-- (signups / total users / PRO counts).
--
-- WHY A FUNCTION, NOT A VIEW (founder's explicit concern — anon-leak):
--   A view inherits the querying role's RLS. Owned by a privileged role it can
--   leak aggregate counts to anon via PostgREST; owned by a normal role it is
--   empty under RLS. This function instead:
--     * lives in the `private` schema  -> PostgREST only serves `public`, so it
--       is NOT reachable via the anon/authenticated REST API at all;
--     * is SECURITY DEFINER            -> reads across RLS to count every row;
--     * has EXECUTE REVOKED FROM PUBLIC (the no-op trap — REVOKE from anon/
--       authenticated alone is useless while PUBLIC holds the grant; debugging
--       skill section 2.32 + migrations 090/091) and GRANTED only to service_role;
--     * pins search_path (SECURITY DEFINER hardening) + fully-qualifies tables.
--
-- HOW THE FOUNDER CALLS IT: Supabase SQL editor (runs as the project owner):
--     select * from private.founder_metrics();
--   (or a service-role Edge Function / dashboard, never the app's anon key.)
--
-- Columns are grounded against the live schema (backups/live_schema_columns.json)
-- + a read-only distinct-value query (2026-06-14): users.subscription_status in
-- {free, pro}; subscriptions.status in {active, cancelled, expired}. The
-- canonical PRO gate is the denormalized users.subscription_status (what the app
-- reads); active_subscriptions is a paid cross-check from the subscriptions table.

create schema if not exists private;

create or replace function private.founder_metrics()
returns table (
  total_users          bigint,
  signups_today_ist    bigint,
  signups_7d           bigint,
  signups_30d          bigint,
  pro_active           bigint,  -- subscription_status='pro' AND not expired
  pro_expired          bigint,  -- was pro, expiry lapsed (win-back signal)
  free_users           bigint,
  active_subscriptions bigint,  -- subscriptions.status='active' (paid cross-check)
  active_last_7d       bigint,  -- engagement: last_active_at within 7d
  generated_at         timestamptz
)
language sql
security definer
set search_path = public, private
as $$
  with u as (
    select * from public.users where is_deleted is not true
  )
  select
    (select count(*) from u)::bigint,
    -- "Today" anchored to IST midnight (date keys + resets are IST app-wide).
    (select count(*) from u
       where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
                            at time zone 'Asia/Kolkata'))::bigint,
    (select count(*) from u where created_at >= now() - interval '7 days')::bigint,
    (select count(*) from u where created_at >= now() - interval '30 days')::bigint,
    (select count(*) from u
       where subscription_status = 'pro'
         and (subscription_expires_at is null
              or subscription_expires_at > now()))::bigint,
    (select count(*) from u
       where subscription_status = 'pro'
         and subscription_expires_at is not null
         and subscription_expires_at <= now())::bigint,
    (select count(*) from u
       where coalesce(subscription_status, 'free') = 'free')::bigint,
    (select count(distinct user_id) from public.subscriptions
       where status = 'active')::bigint,
    (select count(*) from u
       where last_active_at >= now() - interval '7 days')::bigint,
    now();
$$;

-- Admin gate (debugging skill section 2.32): REVOKE from PUBLIC, not the roles —
-- anon/authenticated inherit PUBLIC, so revoking from them alone is a no-op.
revoke all on function private.founder_metrics() from public;
grant execute on function private.founder_metrics() to service_role;

-- Post-apply verification (run in the SQL editor; both must be the stated value):
--   select has_function_privilege('anon',          'private.founder_metrics()', 'execute');  -- expect false
--   select has_function_privilege('authenticated', 'private.founder_metrics()', 'execute');  -- expect false
--   select has_function_privilege('service_role',  'private.founder_metrics()', 'execute');  -- expect true
--   select * from private.founder_metrics();

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- drop function if exists private.founder_metrics();
-- (schema `private` is shared with other functions — do NOT drop the schema.)
