-- Intent: Drop the stale users.subscription_status / users.subscription_expires_at mirror columns and the trigger + functions that maintain them; entitlement is derived from public.subscriptions only. private.founder_metrics() (the only remaining reader) is rewritten to derive from subscriptions first, in the same transaction.
-- Destructive?: yes   -- DROP COLUMN x2 (data is derivable from subscriptions except one orphan, backed up to backups/subscription_mirror_columns_snapshot_2026-09-29.json), DROP TRIGGER, DROP FUNCTION x2
-- Rollback strategy: inline   -- commented reverse block at end of file (columns + backfill + trigger + functions + founder_metrics 093 body)
-- Linked diagnose-doc: c7e3b9 (docs/diagnoses/2026-09-29-subscription-mirror-columns-dropped-c7e3b9.md)

-- (no explicit BEGIN/COMMIT. Whether apply_migration wraps the file in a transaction is
--  unverified, and SET LOCAL is a no-op with a WARNING outside one, which would leave the
--  ALTER TABLE users lock wait unbounded. Plain SET + a closing RESET bounds it either way.)
SET lock_timeout = '5s';

-- 1. Rewrite the only reader FIRST. DROP COLUMN would otherwise succeed silently
--    (plpgsql/sql function bodies are not dependency-tracked) and break every
--    founder_metrics() caller at runtime.
CREATE OR REPLACE FUNCTION private.founder_metrics()
 RETURNS TABLE(total_users bigint, signups_today_ist bigint, signups_7d bigint, signups_30d bigint, pro_active bigint, pro_expired bigint, free_users bigint, active_subscriptions bigint, active_last_7d bigint, generated_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'private'
AS $function$
  with u as (
    select * from public.users where is_deleted is not true
  )
  select
    (select count(*) from u)::bigint,
    (select count(*) from u
       where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata')
                            at time zone 'Asia/Kolkata'))::bigint,
    (select count(*) from u where created_at >= now() - interval '7 days')::bigint,
    (select count(*) from u where created_at >= now() - interval '30 days')::bigint,
    -- pro_active: an active, unexpired subscription (the single PRO predicate).
    (select count(*) from u
       where exists (select 1 from public.subscriptions s
                      where s.user_id = u.id and s.status = 'active' and s.end_date > now()))::bigint,
    -- pro_expired: has at least one subscriptions row of ANY status (cancelled /
    -- expired rows are the win-back population 093 names) but NO live active one.
    -- NOT EXISTS, never NOT IN (a NULL in the subquery would make NOT IN match nothing).
    (select count(*) from u
       where exists (select 1 from public.subscriptions s where s.user_id = u.id)
         and not exists (select 1 from public.subscriptions s
                      where s.user_id = u.id and s.status = 'active' and s.end_date > now()))::bigint,
    -- free_users: never subscribed (no row of any status), so
    -- total = pro_active + pro_expired + free_users.
    ((select count(*) from u)
     - (select count(*) from u
          where exists (select 1 from public.subscriptions s where s.user_id = u.id))
    )::bigint,
    (select count(distinct user_id) from public.subscriptions
       where status = 'active')::bigint,
    (select count(*) from u
       where last_active_at >= now() - interval '7 days')::bigint,
    now();
$function$;

REVOKE ALL ON FUNCTION private.founder_metrics() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.founder_metrics() TO service_role;

-- 2. Drop the writers, then the columns.
DROP TRIGGER IF EXISTS trg_subscription_update_user ON public.subscriptions;
DROP FUNCTION IF EXISTS public.update_user_subscription_status();
DROP FUNCTION IF EXISTS public.extend_subscription(uuid, integer);

ALTER TABLE public.users DROP COLUMN IF EXISTS subscription_status;
ALTER TABLE public.users DROP COLUMN IF EXISTS subscription_expires_at;

NOTIFY pgrst, 'reload schema';

RESET lock_timeout;

-- ROLLBACK (inline, commented). Run it inside your OWN transaction (BEGIN ... COMMIT); the block
-- carries none, so it cannot commit early if replayed through a wrapped runner. It restores the
-- shape, the values derivable from subscriptions, and the one orphan row from the snapshot.
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS subscription_status text DEFAULT 'free';
-- ALTER TABLE public.users ADD COLUMN IF NOT EXISTS subscription_expires_at timestamptz;
-- UPDATE public.users u SET subscription_status = 'pro',
--        subscription_expires_at = s.max_end
--   FROM (SELECT user_id, max(end_date) AS max_end FROM public.subscriptions
--          WHERE status = 'active' GROUP BY user_id) s
--  WHERE u.id = s.user_id;
-- -- The one orphan (zero subscriptions rows), from backups/subscription_mirror_columns_snapshot_2026-09-29.json:
-- UPDATE public.users SET subscription_status = 'pro',
--        subscription_expires_at = '2026-06-22T03:14:41.46023+00:00'
--  WHERE id = '4d27a40b-ce2b-48e6-8485-f6f5a1b85863';
-- CREATE OR REPLACE FUNCTION public.update_user_subscription_status()
--  RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
-- BEGIN
--   IF NEW.status = 'active' THEN
--     UPDATE users SET subscription_status = 'pro',
--       subscription_expires_at = GREATEST(COALESCE(subscription_expires_at, NEW.end_date), NEW.end_date)
--     WHERE id = NEW.user_id;
--   END IF;
--   RETURN NEW;
-- END; $f$;
-- REVOKE ALL ON FUNCTION public.update_user_subscription_status() FROM PUBLIC, anon, authenticated;
-- GRANT EXECUTE ON FUNCTION public.update_user_subscription_status() TO service_role;
-- CREATE TRIGGER trg_subscription_update_user AFTER INSERT OR UPDATE ON public.subscriptions
--   FOR EACH ROW WHEN (new.status = 'active') EXECUTE FUNCTION public.update_user_subscription_status();
-- -- extend_subscription: exact live body, captured with pg_get_functiondef on 2026-09-29
-- -- (also stored in backups/subscription_mirror_columns_snapshot_2026-09-29.json).
-- CREATE OR REPLACE FUNCTION public.extend_subscription(p_user_id uuid, p_days integer)
--  RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
-- BEGIN
--   -- Atomically extend the most recent active subscription
--   UPDATE subscriptions
--   SET end_date = end_date + (p_days || ' days')::interval
--   WHERE id = (
--     SELECT id FROM subscriptions
--     WHERE user_id = p_user_id AND status = 'active'
--     ORDER BY end_date DESC
--     LIMIT 1
--   );
--   -- Update the users table to reflect the new expiry
--   UPDATE users
--   SET subscription_status = 'pro',
--       subscription_expires_at = (
--         SELECT end_date FROM subscriptions
--         WHERE user_id = p_user_id AND status = 'active'
--         ORDER BY end_date DESC
--         LIMIT 1
--       )
--   WHERE id = p_user_id;
-- END; $f$;
-- REVOKE ALL ON FUNCTION public.extend_subscription(uuid, integer) FROM PUBLIC, anon, authenticated;
-- GRANT EXECUTE ON FUNCTION public.extend_subscription(uuid, integer) TO service_role;
-- -- private.founder_metrics(): exact pre-152 live body (pg_get_functiondef, 2026-09-29).
-- -- Restore it AFTER the columns are re-added above, not before (with check_function_bodies on,
-- -- a body naming a missing column fails 42703).
-- CREATE OR REPLACE FUNCTION private.founder_metrics()
--  RETURNS TABLE(total_users bigint, signups_today_ist bigint, signups_7d bigint, signups_30d bigint, pro_active bigint, pro_expired bigint, free_users bigint, active_subscriptions bigint, active_last_7d bigint, generated_at timestamp with time zone)
--  LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'private'
-- AS $function$
--   with u as (select * from public.users where is_deleted is not true)
--   select
--     (select count(*) from u)::bigint,
--     (select count(*) from u where created_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'))::bigint,
--     (select count(*) from u where created_at >= now() - interval '7 days')::bigint,
--     (select count(*) from u where created_at >= now() - interval '30 days')::bigint,
--     (select count(*) from u where subscription_status = 'pro' and (subscription_expires_at is null or subscription_expires_at > now()))::bigint,
--     (select count(*) from u where subscription_status = 'pro' and subscription_expires_at is not null and subscription_expires_at <= now())::bigint,
--     (select count(*) from u where coalesce(subscription_status, 'free') = 'free')::bigint,
--     (select count(distinct user_id) from public.subscriptions where status = 'active')::bigint,
--     (select count(*) from u where last_active_at >= now() - interval '7 days')::bigint,
--     now();
-- $function$;
