-- Migration 069 — OI-batch closures from audit 2026-05-17.
-- Bundles three small, non-destructive changes that don't deserve their own
-- migration file but each fix a discrete audit finding:
--
--   A. (OI-12, P1-A) Add SELECT policy for `client_errors` so users can read
--      their own telemetry rows. Pre-fix the table had only an INSERT policy
--      → any future "show my recent errors" UI would silently return zero.
--      Service role is unaffected (it bypasses RLS).
--
--   B. (OI-15) Register the `cleanup_cron_call_log` retention sweep with
--      pg_cron. Function exists (migration 068) but was never scheduled.
--      Without this, `cron_call_log` grows unbounded.
--
--   C. (OI-18, finding 3) Drop the `coach-media` Storage purge step from
--      `delete-account` is OUT OF SCOPE for SQL — handled in Edge Function
--      source — but verify here that no stale reference to a non-existent
--      bucket remains in the schema (none expected; this is a no-op verify).
--
-- Idempotent: all `CREATE POLICY IF NOT EXISTS` style guards. Cron job
-- registration uses `DELETE THEN INSERT` pattern (cron.unschedule first).

-- ── A. client_errors SELECT policy ──────────────────────────────────────
DO $$
BEGIN
  -- Drop and recreate to make this migration idempotent across re-runs.
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'client_errors'
      AND policyname = 'client_errors_select_own'
  ) THEN
    DROP POLICY "client_errors_select_own" ON public.client_errors;
  END IF;
END $$;

CREATE POLICY "client_errors_select_own"
  ON public.client_errors
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

COMMENT ON POLICY "client_errors_select_own" ON public.client_errors IS
  'OI-12 P1-A (2026-05-17): authenticated users can SELECT their own '
  'telemetry rows. Pre-fix only INSERT was allowed → any future telemetry-'
  'self-view UI returned zero. Service role bypasses RLS so admin tooling '
  'is unaffected.';

-- ── B. cron_call_log retention sweep — daily 03:30 UTC ──────────────────
-- Runs after clean_orphan_media_daily (03:00 UTC) to spread the cron load.
-- `cleanup_cron_call_log()` was created by migration 068.

DO $$
BEGIN
  -- Defensive unschedule in case this migration is re-applied. cron.unschedule
  -- raises on missing job name, so wrap in EXCEPTION handler.
  BEGIN
    PERFORM cron.unschedule('cron_call_log_cleanup_daily');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END $$;

SELECT cron.schedule(
  'cron_call_log_cleanup_daily',
  '30 3 * * *',
  $cmd$ SELECT public.cleanup_cron_call_log(); $cmd$
);

-- ── C. No-op verify: no orphan refs to coach-media bucket in schema ─────
-- (Storage buckets are managed in storage.buckets; docs/architecture/payment.md lists
--  `coach-media/<uid>/` in delete-account purge step, but the bucket does
--  not exist. Resolution is in the Edge Function — drop the purge step or
--  create the bucket. Tracked as OI-18 follow-up.)
-- This migration intentionally takes NO ACTION on this finding.
