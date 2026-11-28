-- Intent: Correct two live defects in migrations 138/139, both found by a self-triggered Hermes pass (catastrophic-tier gate) on the SAME batch that shipped 138/139, before merge.
-- Destructive?: no   -- CREATE OR REPLACE + cron.unschedule/cron.schedule of the ONE existing job; no table/data touched.
-- Rollback strategy: inline   -- end-of-file commented-out reverse DDL restores 138's and 139's original (buggy) bodies verbatim.
-- Linked diagnose-doc: docs/diagnoses/2026-09-21-hermes-pass-migration-138-139-fixes-h1a2b3.md

-- 140_hermes_pass_fixes_138_139.sql
--
-- ============================================================================
-- FIX 1 (of 139): the `status = 'started'` stuck-job branch had NO upper time
-- bound, on the argument that a genuinely-still-stuck job should keep paging
-- for as long as it remains stuck. That argument assumed `cron_call_log` can
-- tell "still running" apart from "crashed and never updated" — it cannot.
-- `logCronEnd` (_shared/cron_telemetry.ts) only fires if the isolate reaches
-- it; a timeout/OOM/crash leaves the row 'started' PERMANENTLY. Live proof
-- (Hermes L31/L35, 2026-09-21): two rows from a single crashed tick on
-- 2026-09-19 04:15 UTC are still 'started' 2.5 days later, both functions
-- have run successfully many times since, and the job has ALREADY fired
-- (public.alerts id=40, detected 2026-09-21 17:30 UTC) on data with no live
-- incident behind it. Left alone it re-pages roughly hourly until the 7-day
-- `cleanup_cron_call_log()` sweep deletes the rows on 2026-09-27 — and
-- ACKNOWLEDGING the page makes it re-fire on the very next 15-minute tick
-- instead of waiting out the hour (a pre-existing dedup-convention property
-- shared by all 6 alert_* jobs, not unique to this one — tracked separately,
-- see the OI filed alongside this migration).
--
-- Fix: bound the stuck-branch lookback at 6 hours. Chosen deliberately
-- between this project's two SIBLING alerts that already cover the two ends
-- of this exact failure mode: `alert_cron_silence` (fleet-wide, no success in
-- 2h) and `alert_cron_function_dead` (one function, no success in 8 days) —
-- both keyed on genuine forward-progress absence, not on this one row's
-- (unreliable) status field. A 6h bound is longer than any legitimate
-- Edge-Function runtime on this project (these are short request/response or
-- 15-minute-cadence cron functions, not long batch jobs), so it does not
-- mask a real "just went stuck" incident, and it is comfortably inside
-- `alert_cron_function_dead`'s 8-day horizon, so a job that is STILL broken
-- past 6h remains covered by that sibling alert at its own time horizon —
-- exactly the "different time horizons, genuinely serving different
-- purposes" design the original 139 header already argued for the job as a
-- whole, now applied consistently to this one branch too.
--
-- FIX 2 (of 138): `private.set_subscription_cancelled_at()` only cleared
-- FORWARD (status -> 'cancelled'); it never cleared `cancelled_at` on a
-- reactivation ('cancelled' -> anything else). Hermes L1/L35 (2026-09-21):
-- the trigger's own header claims "self-maintaining regardless of HOW the
-- status changes" but a manual dashboard revert (the exact workflow the
-- migration's own investigation found is the ONLY way `status='cancelled'`
-- is ever set today) would leave a stale, permanent `cancelled_at` stamp on
-- a now-active subscriber — and `founder_digest_content.ts`'s
-- "Cancelled (manual)" reader (migration 138's own reason for existing)
-- filters on `cancelled_at` ALONE, with no `status='cancelled'` check, so it
-- would misreport a reactivated, paying subscriber as a cancellation
-- forever. Fix: add the reverse transition (clears `cancelled_at` back to
-- NULL). Also widened the trigger from `BEFORE UPDATE` to
-- `BEFORE INSERT OR UPDATE` (Hermes L22 F2): an INSERT carrying
-- `status='cancelled'` directly (not a later UPDATE) fired no trigger at all
-- and stored a NULL stamp — `OLD` does not exist on INSERT, handled below
-- via `TG_OP`.
--
-- No live rows are affected by fix 2: `with_cancelled_at` count was 0 across
-- all 13 subscriptions rows immediately before this migration (verified live
-- during the Hermes pass) — there is nothing to backfill, this is a
-- forward-looking correctness fix only.
--
-- Both migrations 138 and 139 are IMMUTABLE (already applied) per
-- supabase/migrations/CLAUDE.md — corrections land here via
-- CREATE OR REPLACE FUNCTION (preserves the existing ACL; no signature
-- change) and cron.unschedule+cron.schedule (the established precedent for
-- updating an existing job — see 086_alert_client_errors_spike_tune.sql).

-- ---------------------------------------------------------------------------
-- FIX 1: bound alert_cron_failures's stuck-job branch to 6 hours.
-- ---------------------------------------------------------------------------

SELECT cron.unschedule('alert_cron_failures')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alert_cron_failures');

SELECT cron.schedule(
  'alert_cron_failures',
  '*/15 * * * *',
  $$
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
  SELECT
    'alert_cron_failures',
    'critical',
    'cron_call_log shows ' || cnt || ' failed (last 1h) or currently-stuck (last 6h) job(s)',
    jsonb_build_object('count', cnt, 'failed_window_hours', 1, 'stuck_window_hours', 6),
    'Check cron_call_log for the failing function_name (status=''failed'' or '
    'stuck status=''started''). See docs/operations/CRON_REGISTRY.md and '
    '_shared/cron_auth.ts for the auth-gate failure class (diagnose c3f8a1 lineage).'
  FROM (
    SELECT COUNT(*) AS cnt
    FROM public.cron_call_log
    WHERE
      (status = 'failed' AND started_at >= now() - interval '1 hour')
      OR (status = 'started'
          AND started_at < now() - interval '1 hour'
          AND started_at >= now() - interval '6 hours')
  ) c
  WHERE c.cnt >= 1
    AND NOT EXISTS (
      SELECT 1 FROM public.alerts
      WHERE source = 'alert_cron_failures'
        AND acknowledged = false
        AND detected_at > now() - interval '1 hour'
    );
  $$
);

-- ---------------------------------------------------------------------------
-- FIX 2: clear cancelled_at on reactivation; stamp on INSERT too.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.set_subscription_cancelled_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'cancelled' THEN
      NEW.cancelled_at := now();
    END IF;
    RETURN NEW;
  END IF;

  -- TG_OP = 'UPDATE' from here.
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    NEW.cancelled_at := now();
  ELSIF NEW.status IS DISTINCT FROM 'cancelled' AND OLD.status = 'cancelled' THEN
    NEW.cancelled_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_subscription_cancelled_at ON public.subscriptions;

CREATE TRIGGER trg_set_subscription_cancelled_at
BEFORE INSERT OR UPDATE ON public.subscriptions
FOR EACH ROW
EXECUTE FUNCTION private.set_subscription_cancelled_at();

COMMENT ON FUNCTION private.set_subscription_cancelled_at() IS
  '140 — BEFORE INSERT OR UPDATE trigger fn: stamps subscriptions.cancelled_at '
  'on a transition INTO ''cancelled'' (INSERT or UPDATE), and CLEARS it back '
  'to NULL on a transition OUT of ''cancelled'' (reactivation). Corrects '
  '138''s UPDATE-only, forward-only version — see migration 140''s header.';

COMMENT ON TRIGGER trg_set_subscription_cancelled_at ON public.subscriptions IS
  '140 — see private.set_subscription_cancelled_at() comment.';

-- Post-apply verification (run in the SQL editor):
--   SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'alert_cron_failures';
--   -- expect one row, schedule = '*/15 * * * *', active = true (jobid will differ from 139's, unschedule+reschedule assigns a new one)
--
--   -- Fix 1 sanity: the two known 2026-09-19 04:15 stuck rows must NO LONGER match:
--   SELECT count(*) FROM public.cron_call_log
--     WHERE status = 'started' AND started_at < now() - interval '1 hour' AND started_at >= now() - interval '6 hours';
--   -- expect 0 (those rows are ~2.5 days old, well outside the new 6h window)
--
--   -- Fix 2 sanity, inside a rolled-back transaction against a real ACTIVE row:
--   BEGIN;
--   WITH t AS (SELECT id FROM public.subscriptions WHERE status = 'active' LIMIT 1)
--   UPDATE public.subscriptions SET status = 'cancelled' WHERE id IN (SELECT id FROM t) RETURNING id, status, cancelled_at;
--   -- expect cancelled_at ~ now()
--   WITH t AS (SELECT id FROM public.subscriptions WHERE status = 'cancelled' AND cancelled_at IS NOT NULL LIMIT 1)
--   UPDATE public.subscriptions SET status = 'active' WHERE id IN (SELECT id FROM t) RETURNING id, status, cancelled_at;
--   -- expect cancelled_at IS NULL
--   ROLLBACK;

-- =============================================================================
-- Rollback (inline):
--
-- SELECT cron.unschedule('alert_cron_failures')
--  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alert_cron_failures');
-- SELECT cron.schedule('alert_cron_failures', '*/15 * * * *', $$
--   INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--   SELECT 'alert_cron_failures', 'critical',
--     'cron_call_log shows ' || cnt || ' failed (last 1h) or currently-stuck job(s)',
--     jsonb_build_object('count', cnt, 'failed_window_hours', 1, 'stuck_after_hours', 1),
--     'Check cron_call_log for the failing function_name.'
--   FROM (SELECT COUNT(*) AS cnt FROM public.cron_call_log
--     WHERE (status = 'failed' AND started_at >= now() - interval '1 hour')
--       OR (status = 'started' AND started_at < now() - interval '1 hour')) c
--   WHERE c.cnt >= 1 AND NOT EXISTS (SELECT 1 FROM public.alerts
--     WHERE source = 'alert_cron_failures' AND acknowledged = false
--       AND detected_at > now() - interval '1 hour');
-- $$);
--
-- CREATE OR REPLACE FUNCTION private.set_subscription_cancelled_at()
-- RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
-- BEGIN
--   IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
--     NEW.cancelled_at := now();
--   END IF;
--   RETURN NEW;
-- END;
-- $$;
-- DROP TRIGGER IF EXISTS trg_set_subscription_cancelled_at ON public.subscriptions;
-- CREATE TRIGGER trg_set_subscription_cancelled_at
--   BEFORE UPDATE ON public.subscriptions FOR EACH ROW
--   EXECUTE FUNCTION private.set_subscription_cancelled_at();
-- =============================================================================
