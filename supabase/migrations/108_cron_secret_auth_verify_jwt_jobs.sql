-- Intent: Repoint the two verify_jwt=true cron jobs (compute-coach-signals, compute-admin-metrics-daily) onto CRON_SECRET, after their gateway flags have been flipped and compute-coach-signals has been given an auth gate.
-- Destructive?: no   -- rewrites cron.job.command text only; no schema change, no row rewrite
-- Rollback strategy: inline   -- reverse block at end of file
-- Linked diagnose-doc: c3f8a1

-- ============================================================================
-- WHY THIS IS SEPARATE FROM MIGRATION 107
-- ----------------------------------------------------------------------------
-- Same batch, hard ordering dependency — NOT a deferral.
--
-- When an Edge Function has verify_jwt=true, the Supabase GATEWAY validates the
-- bearer token as a project-signed JWT *before the module loads*. An opaque
-- CRON_SECRET is not a JWT, so the gateway rejects it and the module never
-- runs. Repointing these two jobs before their flags are flipped would make
-- things strictly worse:
--
--   jobid  8  compute-coach-signals
--             verify_jwt=true, and — verified live — NO module-level auth gate
--             whatsoever (its source imports neither isAuthorizedCronCall nor
--             any inline token check). The service_role JWT therefore clears
--             the gateway and the module simply runs.
--             ⇒ IT IS THE ONLY CRON JOB CURRENTLY WORKING.
--                coach_memory.signals_computed_at max = 2026-07-25 21:00:05,
--                five seconds after its 21:00:00 dispatch.
--             Repointing it first would BREAK it.
--
--   jobid 30  compute-admin-metrics-daily
--             verify_jwt=true WITH a module gate (index.ts:120). Gateway passes
--             the JWT, module gate 401s. Broken now, and would remain broken
--             after a repoint because the gateway would reject the opaque token
--             first. admin_metrics_daily has 0 rows despite 13 dispatches.
--
-- ----------------------------------------------------------------------------
-- REQUIRED ORDER — every step must be complete before this migration applies
-- ----------------------------------------------------------------------------
--   1. Migration 107 applied (creates private.cron_get_secret()).
--   2. compute-coach-signals/index.ts given an isAuthorizedCronCall gate, with
--      logCronStart placed AFTER that gate, and DEPLOYED.
--        ⚠ AFTER, not before. An earlier draft of this checklist said "moved
--          ABOVE it" — that is wrong and is exactly the design 109 rejects:
--          on a verify_jwt=false endpoint, logging before the gate hands every
--          anonymous caller an unauthenticated INSERT into cron_call_log.
--          See _shared/cron_auth.ts (the KEEP logCronStart AFTER note) and
--          migration 109's header. The shipped code has the correct order.
--        ⚠ Order matters for safety: deploy the gate FIRST, while verify_jwt is
--          still true. The function is then double-protected (gateway + module).
--          Flipping the flag first would leave it briefly PUBLIC — and with no
--          gate, any holder of the anon key (shipped in every APK) could drive
--          up to 5000 RPC round-trips through it. It is momentarily 401 between
--          steps 2 and 4; it is never unprotected.
--   3. verify_jwt flipped to false on BOTH compute-coach-signals and
--      compute-admin-metrics-daily.
--   4. This migration.
--   5. Positive smoke: confirm a 200 from each, and that coach_memory
--      .signals_computed_at advances on the next 21:00 UTC tick.
-- ============================================================================

-- Guard 1 — 107 must have run.
DO $$
BEGIN
  IF to_regprocedure('private.cron_get_secret()') IS NULL THEN
    RAISE EXCEPTION
      'private.cron_get_secret() does not exist — apply migration 107 first.';
  END IF;
  -- The accessor raises on a missing/empty secret, so calling it is the check.
  PERFORM private.cron_get_secret();
END $$;

-- Guard 2 — repoint exactly the two expected jobs, identified semantically by
-- the URL-builder function their command calls rather than by hardcoded jobid.
DO $$
DECLARE
  r        record;
  new_cmd  text;
  n        int := 0;
  already  int := 0;
BEGIN
  SELECT count(*) INTO already
  FROM cron.job
  WHERE command LIKE '%private.cron_get_secret()%'
    AND (command LIKE '%compute_coach_signals_function_url%'
      OR command LIKE '%compute_admin_metrics_function_url%');

  FOR r IN
    SELECT jobid, jobname, command
    FROM cron.job
    WHERE command LIKE '%morning_alert_get_service_key%'
      AND (command LIKE '%compute_coach_signals_function_url%'
        OR command LIKE '%compute_admin_metrics_function_url%')
    ORDER BY jobid
  LOOP
    new_cmd := replace(
      r.command,
      'private.morning_alert_get_service_key()',
      'private.cron_get_secret()'
    );

    IF new_cmd = r.command THEN
      RAISE EXCEPTION
        'jobid % (%) matched but no replacement applied — aborting.',
        r.jobid, r.jobname;
    END IF;

    PERFORM cron.alter_job(r.jobid, command := new_cmd);
    n := n + 1;
    RAISE NOTICE 'repointed jobid % (%)', r.jobid, r.jobname;
  END LOOP;

  IF n + already <> 2 THEN
    RAISE EXCEPTION
      'expected exactly 2 verify_jwt-tier cron jobs, got % repointed + % '
      'already migrated = %. Aborting.', n, already, n + already;
  END IF;
END $$;

-- ============================================================================
-- ROLLBACK (inline)
-- ----------------------------------------------------------------------------
-- DO $$
-- DECLARE r record; new_cmd text;
-- BEGIN
--   FOR r IN SELECT jobid, command FROM cron.job
--            WHERE command LIKE '%private.cron_get_secret()%'
--              AND (command LIKE '%compute_coach_signals_function_url%'
--                OR command LIKE '%compute_admin_metrics_function_url%')
--   LOOP
--     new_cmd := replace(r.command, 'private.cron_get_secret()',
--                                   'private.morning_alert_get_service_key()');
--     PERFORM cron.alter_job(r.jobid, command := new_cmd);
--   END LOOP;
-- END $$;
-- NOTE: rolling back the SQL is not sufficient on its own — verify_jwt must be
-- flipped back to true on both functions, or the gateway will accept anything.
-- ============================================================================
