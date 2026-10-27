-- Intent: AFTER INSERT trigger on public.alerts (severity='critical') dispatches to the alert-critical-notify Edge Function via pg_net, so a critical alert reaches the founder's Telegram immediately instead of waiting for the next daily digest.
-- Destructive?: no   -- only ADDs a SECURITY DEFINER function in the private schema + a new trigger. Existing alerts inserts proceed unchanged; the trigger swallows all exceptions.
-- Rollback strategy: inline   -- end-of-file commented-out reverse DDL drops the trigger + function.
-- Linked diagnose-doc: n/a   -- new feature, not a bug fix

-- 133_alert_critical_notify_trigger.sql
--
-- Same shape as 073_proactive_coach_promotion_trigger.sql (private schema,
-- SECURITY DEFINER, exception-swallowing, fire-and-forget pg_net dispatch) —
-- that precedent is deliberate: a public-schema SECURITY DEFINER function is
-- anon-executable by default on this project (see
-- supabase/migrations/CLAUDE.md's "public SECURITY DEFINER function is
-- anon-executable" pitfall); living in `private` makes it PostgREST-invisible
-- and dodges the class entirely, the same way 073 does.
--
-- pg_net is already enabled (used by every other cron-dispatch trigger on
-- this project).

CREATE OR REPLACE FUNCTION private.dispatch_critical_alert_notify()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cron_secret text;
  v_supabase_url text;
  v_request_id bigint;
BEGIN
  SELECT private.cron_get_secret() INTO v_cron_secret;

  IF v_cron_secret IS NULL OR v_cron_secret = '' THEN
    -- CRON_SECRET not seeded — never block the alert insert for a missing
    -- notification credential. The alert row itself is the source of truth;
    -- the push is best-effort.
    RETURN NEW;
  END IF;

  v_supabase_url := 'https://dedsavbjuwgarrhphgnl.supabase.co';

  -- Fire-and-forget. pg_net returns immediately; delivery happens async,
  -- out-of-transaction, and can never roll back this INSERT.
  SELECT net.http_post(
    url := v_supabase_url || '/functions/v1/alert-critical-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_cron_secret
    ),
    body := jsonb_build_object('alert_id', NEW.id)
  ) INTO v_request_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never propagate a trigger failure back to the alerts INSERT — the alert
  -- record is authoritative; the Telegram push is purely additive.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dispatch_critical_alert_notify ON public.alerts;

CREATE TRIGGER trg_dispatch_critical_alert_notify
AFTER INSERT ON public.alerts
FOR EACH ROW
WHEN (NEW.severity = 'critical')
EXECUTE FUNCTION private.dispatch_critical_alert_notify();

COMMENT ON FUNCTION private.dispatch_critical_alert_notify() IS
  '133 — fires alert-critical-notify Edge Function on every critical-severity '
  'alerts INSERT. Never propagates errors back to the parent transaction.';

COMMENT ON TRIGGER trg_dispatch_critical_alert_notify ON public.alerts IS
  '133 — immediate Telegram push for a critical alert, independent of the daily digest.';

-- ── Rollback DDL (commented; uncomment + run as a new migration to revert) ──
--
-- DROP TRIGGER IF EXISTS trg_dispatch_critical_alert_notify ON public.alerts;
-- DROP FUNCTION IF EXISTS private.dispatch_critical_alert_notify();
