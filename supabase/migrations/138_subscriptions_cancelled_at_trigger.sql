-- Intent: Add subscriptions.cancelled_at (nullable timestamptz) + a self-maintaining BEFORE UPDATE trigger that stamps it the moment status transitions TO 'cancelled', so the founder-digest (B3) can report a genuinely-windowed "Cancelled (manual)" figure instead of an un-windowed status count.
-- Destructive?: no   -- ADD COLUMN nullable, no backfill; new trigger only fires on a status transition, existing UPDATE statements that don't touch status are unaffected.
-- Rollback strategy: inline   -- end-of-file commented-out reverse DDL drops the trigger, function, and column.
-- Linked diagnose-doc: n/a   -- new feature (Part B of the observation-batch-and-digest-redesign spec), not a bug fix

-- 138_subscriptions_cancelled_at_trigger.sql
--
-- Writer investigation (spec B3): grepped both supabase/functions/ and lib/
-- for any code path that writes subscriptions.status = 'cancelled' — there is
-- NONE. Every 'cancelled' reference in the repo is a READ-side filter. The 3
-- 'cancelled' rows live in the table today (verified live) were set by a
-- manual dashboard/SQL edit, not by any app code — so "patch the writer to
-- also set cancelled_at" has no call site to patch. A trigger is
-- self-maintaining regardless of HOW the status changes (today's manual
-- dashboard edit, a future automated cancellation flow, an admin script) —
-- no future writer can forget to set cancelled_at, because nothing needs to.
--
-- No backfill for the 3 existing 'cancelled' rows — cancelled_at stays NULL
-- for them (founder-accepted: "not tracked retroactively, only from this
-- migration date on"). The digest copy states this explicitly rather than
-- silently showing a bare 0 for all pre-migration history.
--
-- Same private-schema/SECURITY DEFINER shape as 133_alert_critical_notify_trigger.sql
-- for the reason documented there (public SECURITY DEFINER functions are
-- anon-executable by default on this project) — not strictly required here
-- since this trigger only mutates NEW within the same row and grants nothing
-- externally callable, but living in `private` keeps it PostgREST-invisible
-- and consistent with this project's trigger-function convention.

ALTER TABLE public.subscriptions ADD COLUMN IF NOT EXISTS cancelled_at timestamptz NULL;

CREATE OR REPLACE FUNCTION private.set_subscription_cancelled_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    NEW.cancelled_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_subscription_cancelled_at ON public.subscriptions;

CREATE TRIGGER trg_set_subscription_cancelled_at
BEFORE UPDATE ON public.subscriptions
FOR EACH ROW
EXECUTE FUNCTION private.set_subscription_cancelled_at();

COMMENT ON COLUMN public.subscriptions.cancelled_at IS
  '138 — stamped by trg_set_subscription_cancelled_at the moment status '
  'transitions to ''cancelled''. NULL for every row cancelled before this '
  'migration (no retroactive backfill, founder-accepted).';

COMMENT ON FUNCTION private.set_subscription_cancelled_at() IS
  '138 — BEFORE UPDATE trigger fn: stamps subscriptions.cancelled_at on a '
  'status transition INTO ''cancelled''. Self-maintaining regardless of which '
  'caller changes status (manual dashboard edit today, any future automated '
  'cancellation flow) — no writer needs to remember to set this column.';

COMMENT ON TRIGGER trg_set_subscription_cancelled_at ON public.subscriptions IS
  '138 — see private.set_subscription_cancelled_at() comment.';

-- Post-apply verification (run in the SQL editor):
--   select column_name, is_nullable from information_schema.columns
--     where table_schema='public' and table_name='subscriptions' and column_name='cancelled_at';
--   -- expect one row, is_nullable = 'YES'
--
--   -- Trigger fires only on a real transition, not a no-op re-save of the same status:
--   with t as (select id from public.subscriptions where status = 'active' limit 1)
--   update public.subscriptions set status = 'cancelled' where id in (select id from t)
--   returning id, status, cancelled_at;  -- expect cancelled_at ~ now(); then manually revert this test row.

-- =============================================================================
-- Rollback (inline):
--
-- DROP TRIGGER IF EXISTS trg_set_subscription_cancelled_at ON public.subscriptions;
-- DROP FUNCTION IF EXISTS private.set_subscription_cancelled_at();
-- ALTER TABLE public.subscriptions DROP COLUMN IF EXISTS cancelled_at;
-- =============================================================================
