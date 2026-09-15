-- 061_audit_2026_05_12_cron_and_bounds.sql
-- Audit 2026-05-12 follow-up batch:
--   P1-D — rolling-context-nightly + streak-guardian-daily crons send a
--          hardcoded anon JWT (pre-Vault pattern). Switch to Vault
--          service-role key resolver matching morning_alert pattern.
--   P1-E — register pg_cron jobs for weekly-recap-ready (Sunday) and
--          expiry-reminder (daily) — both deployed Edge Functions but
--          never auto-triggered because no cron was registered.
--   P1-G — workout_log_sets is missing the per-set realistic bounds that
--          migration 060 added to workout_log_exercises. Live bad rows
--          (7 reps + 15 set_number out of bounds; Jump Rope 540 reps,
--          Leg Press set_number 15). Add CHECK NOT VALID so legacy
--          corrupt rows stay readable but new inserts are bounded; a
--          one-shot data-cleanup is a separate concern.
--   P3-B — drop duplicate UNIQUE constraint on referral_redemptions.referee_id
--          (referee_id_key + unique_referee_redemption are identical).
--
-- closes-diagnose: 3f8a91 (P0 sync) — this migration is the same batch
-- closes-diagnose: 2026-05-12-audit-batch-cron-bounds (this file)

-- ─────────────────────────────────────────────────────────────────────
-- P1-D · re-register rolling-context-nightly with Vault service-role key
-- ─────────────────────────────────────────────────────────────────────
SELECT cron.unschedule('rolling-context-nightly');

SELECT cron.schedule(
  'rolling-context-nightly',
  '0 21 * * *',
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/rolling-context',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object()
    );
  $$
);

-- ─────────────────────────────────────────────────────────────────────
-- P1-D · re-register streak-guardian-daily with Vault service-role key
-- ─────────────────────────────────────────────────────────────────────
SELECT cron.unschedule('streak-guardian-daily');

SELECT cron.schedule(
  'streak-guardian-daily',
  '30 14 * * *',
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/streak-guardian',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object()
    );
  $$
);

-- ─────────────────────────────────────────────────────────────────────
-- P1-E · register weekly-recap-ready cron (Sunday 14:30 UTC = 20:00 IST)
-- ─────────────────────────────────────────────────────────────────────
SELECT cron.schedule(
  'weekly_recap_ready_sunday',
  '30 14 * * 0',  -- Sunday 14:30 UTC
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/weekly-recap-ready',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object()
    );
  $$
);

-- ─────────────────────────────────────────────────────────────────────
-- P1-E · register expiry-reminder cron (daily 09:00 UTC = 14:30 IST)
-- ─────────────────────────────────────────────────────────────────────
SELECT cron.schedule(
  'expiry_reminder_daily',
  '0 9 * * *',
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/expiry-reminder',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object()
    );
  $$
);

-- ─────────────────────────────────────────────────────────────────────
-- P1-G · workout_log_sets bounds (parity with migration 060)
-- ─────────────────────────────────────────────────────────────────────
-- Per-set bounds. NOT VALID so legacy corrupt rows (Jump Rope 540 reps,
-- Leg Press set_number 15) stay readable but new inserts are bounded.
-- A separate one-shot data cleanup is in scope for a follow-up
-- decision (cardio/timed semantics) — see audit report P1-G.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'wls_reps_realistic'
      AND conrelid = 'public.workout_log_sets'::regclass
  ) THEN
    ALTER TABLE public.workout_log_sets
      ADD CONSTRAINT wls_reps_realistic
      CHECK (reps IS NULL OR reps BETWEEN 0 AND 60) NOT VALID;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'wls_set_number_realistic'
      AND conrelid = 'public.workout_log_sets'::regclass
  ) THEN
    ALTER TABLE public.workout_log_sets
      ADD CONSTRAINT wls_set_number_realistic
      CHECK (set_number IS NULL OR set_number BETWEEN 0 AND 10) NOT VALID;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'wls_duration_secs_realistic'
      AND conrelid = 'public.workout_log_sets'::regclass
  ) THEN
    -- duration_secs accommodates legitimate timed exercises (Jump Rope
    -- 540s = 9 minutes is plausible) — set upper bound at 1 hour (3600s)
    -- which covers cardio sessions but blocks "type the duration into
    -- the reps box" corruption.
    ALTER TABLE public.workout_log_sets
      ADD CONSTRAINT wls_duration_secs_realistic
      CHECK (duration_secs IS NULL OR duration_secs BETWEEN 0 AND 3600) NOT VALID;
  END IF;
END
$$;

COMMENT ON CONSTRAINT wls_reps_realistic ON public.workout_log_sets IS
  'Audit 2026-05-12 P1-G — parity with workout_log_exercises (wle_reps_realistic). '
  'NOT VALID so legacy corrupt rows survive; new inserts bounded [0, 60]. '
  'Jump Rope-style high-rep cardio belongs in duration_secs, not reps.';
COMMENT ON CONSTRAINT wls_set_number_realistic ON public.workout_log_sets IS
  'Audit 2026-05-12 P1-G — parity with workout_log_exercises (wle_set_number_realistic). '
  'NOT VALID so legacy corrupt rows survive; new inserts bounded [0, 10].';
COMMENT ON CONSTRAINT wls_duration_secs_realistic ON public.workout_log_sets IS
  'Audit 2026-05-12 P1-G — new bound. Caps timed-exercise per-set duration '
  'at 1 hour (3600s). Catches typos like "reps in seconds field" by limiting '
  'to plausible single-set durations.';

-- ─────────────────────────────────────────────────────────────────────
-- P3-B · drop duplicate UNIQUE constraint on referral_redemptions.referee_id
-- ─────────────────────────────────────────────────────────────────────
-- pg_constraint shows TWO identical UNIQUEs:
--   referral_redemptions_referee_id_key (auto-created by UNIQUE inline def)
--   unique_referee_redemption (named, added in migration 037)
-- Drop the auto-created one; keep the named one (clearer intent).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'referral_redemptions_referee_id_key'
      AND conrelid = 'public.referral_redemptions'::regclass
  ) THEN
    ALTER TABLE public.referral_redemptions
      DROP CONSTRAINT referral_redemptions_referee_id_key;
  END IF;
END
$$;
