-- Intent: Add client_errors telemetry (success + failure paths) to private.dispatch_critical_alert_notify(), and document the AFTER-INSERT-only trigger scope + the deliberate absence of a feature flag.
-- Destructive?: no   -- CREATE OR REPLACE FUNCTION replaces the function body only; no table, data, or constraint changes; the trigger binding (trg_dispatch_critical_alert_notify) is untouched.
-- Rollback strategy: migration 133's own body   -- author a follow-up CREATE OR REPLACE restoring 133's original (telemetry-free) body if ever needed; trivial since no schema changed.
-- Linked diagnose-doc: n/a
--
-- 134_alert_critical_notify_telemetry.sql
--
-- B-pass review (docs/reviews/28213f7956e2-review.md) on migration 133 found
-- its EXCEPTION WHEN OTHERS handler was a bare `RETURN NEW;` with zero
-- observability, despite 133's own header claiming "same shape as
-- 073_proactive_coach_promotion_trigger.sql (... exception-swallowing)". That
-- claim was only half true: 073 (before ITS OWN fix in migration 078) also
-- logged client_errors telemetry on both paths.
--
-- ⚠ The review's own suggested-fix cited `client_errors(user_id, op_type,
-- message, severity)` — independently re-verified against the LIVE table
-- (information_schema.columns) before writing this migration, and that is
-- NOT the real schema. Those are the exact WRONG columns that caused a real
-- P0 in migration 073's original body: `client_errors` has no `message` or
-- `severity` column at all (real: error_code, error_message, client_version,
-- platform — the last two NOT NULL). 078_fix_dispatch_proactive_coach_
-- promotion_columns.sql documents the incident: because a trigger function's
-- SQL is not validated until it actually runs, 073's bad INSERT shipped
-- silently and only failed live, aborting EVERY rank_promotions row — and
-- because 073's original WHEN OTHERS handler's OWN telemetry insert used the
-- same bad columns, the re-raised exception escaped the trigger entirely.
--
-- This migration uses 078's CORRECTED pattern from the start: real column
-- names, and the failure-path telemetry insert nested in its own
-- BEGIN/EXCEPTION WHEN OTHERS THEN NULL block so a broken telemetry write can
-- never itself abort the alerts INSERT (a telemetry failure must lose to the
-- alert record, never the other way round).
--
-- Also addresses two smaller review findings, both documentation-only:
--   - Finding 2 (feature_flag): docs/blast_radius.yaml requires a
--     feature_flag at catastrophic tier. This trigger deliberately has none —
--     it is a fire-and-forget, exception-swallowing NOTIFICATION side-effect
--     that never mutates `public.alerts` or any other table; its only failure
--     mode is "no Telegram message sent", which is the pre-migration status
--     quo. Disabling it requires a new migration (DROP TRIGGER), a heavier
--     off-switch than a flag flip, and that tradeoff is accepted here rather
--     than adding a dedicated kill-switch secret for a single trigger. This
--     rationale is recorded here pending the branch's plan-review record
--     (Finding 1 — owed before merge to main, per CLAUDE.md 4.12.3, tracked
--     in the SDD ledger for this batch's final whole-branch review).
--   - Finding 4 (AFTER INSERT only): documented via COMMENT ON TRIGGER below.
--     Verified live and in every migration/EF source that no writer currently
--     UPDATEs `public.alerts.severity` in place — this trigger's scope is
--     correct today; any FUTURE writer that escalates an alert's severity via
--     UPDATE instead of INSERT must add a mirror AFTER UPDATE OF severity
--     trigger.

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
    -- the push is best-effort. Telemetry insert nested defensively (see
    -- header) so a telemetry failure can never itself abort this INSERT.
    BEGIN
      INSERT INTO public.client_errors(
        user_id, op_type, error_code, error_message, client_version, platform
      ) VALUES (
        NULL,
        'critical_alert_dispatch_failed',
        'warn',
        'CRON_SECRET not set (private.cron_get_secret() returned null/empty)',
        'server-trigger',
        'server'
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
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

  BEGIN
    INSERT INTO public.client_errors(
      user_id, op_type, error_code, error_message, client_version, platform
    ) VALUES (
      NULL,
      'critical_alert_dispatched',
      'info',
      'request_id=' || v_request_id || ' alert_id=' || NEW.id,
      'server-trigger',
      'server'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never propagate a trigger failure back to the alerts INSERT — the alert
  -- record is authoritative; the Telegram push is purely additive. Nested
  -- swallow on the telemetry insert itself for the same reason as above.
  BEGIN
    INSERT INTO public.client_errors(
      user_id, op_type, error_code, error_message, client_version, platform
    ) VALUES (
      NULL,
      'critical_alert_dispatch_failed',
      'warn',
      LEFT(SQLERRM, 500),
      'server-trigger',
      'server'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION private.dispatch_critical_alert_notify() IS
  '134 — fires alert-critical-notify Edge Function on every critical-severity '
  'alerts INSERT, with client_errors telemetry on both paths. Never propagates '
  'errors (including telemetry-insert errors) back to the parent transaction.';

COMMENT ON TRIGGER trg_dispatch_critical_alert_notify ON public.alerts IS
  '134 — immediate Telegram push for a critical alert, independent of the '
  'daily digest. AFTER INSERT ONLY, deliberately: no writer currently UPDATEs '
  'alerts.severity in place (verified at review time). Any future writer that '
  'escalates severity via UPDATE instead of INSERT must add a mirror AFTER '
  'UPDATE OF severity trigger, or the escalation will not notify.';

-- ── Rollback DDL (commented; uncomment + run as a new migration to revert to 133's telemetry-free body) ──
--
-- (133's original body — see supabase/migrations/133_alert_critical_notify_trigger.sql for the
-- exact CREATE OR REPLACE FUNCTION text to restore verbatim.)
