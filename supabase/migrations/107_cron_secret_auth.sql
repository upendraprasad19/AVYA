-- Intent: Repoint the 16 verify_jwt=false HTTP cron jobs and the proactive-coach-promotion trigger from the unreachable JWT-verify auth path onto the CRON_SECRET opaque-token path, and lock down both Vault accessor functions.
-- Destructive?: no   -- rewrites cron.job.command text + one function body; no schema change, no row rewrite, no data loss
-- Rollback strategy: inline   -- reverse block at end of file
-- Linked diagnose-doc: c3f8a1

-- ============================================================================
-- ROOT CAUSE (verified live 2026-07-26, not inferred)
-- ----------------------------------------------------------------------------
-- supabase/functions/_shared/cron_auth.ts:97-101 verifies the bearer token
-- against Deno.env.get("SUPABASE_JWT_SECRET") and returns false when unset.
-- That variable is (a) NOT among Supabase's auto-injected defaults, and
-- (b) IMPOSSIBLE to add — the platform reserves the `SUPABASE_` prefix for
-- secret names ("Names must NOT start with the prefix `SUPABASE_`"). The JWT
-- branch is therefore permanently unreachable and every gated cron function
-- has returned 401 since it deployed.
--
-- The Vault service_role JWT was NEVER the problem — both prior fixes chased
-- it. Decoded live: HS256 / role=service_role / ref=dedsavbjuwgarrhphgnl /
-- exp 2089829852 (2036). Valid.
--
-- Recurrence of diagnose 5a65bd (2026-05-15), whose OWN "class fix" (swap the
-- brittle env-equality check for JWT signature verification) introduced the
-- impossible dependency.
--
-- FIX: use the CRON_SECRET opaque-token branch (cron_auth.ts:91-94), already
-- live in every deployed function. Being a plain string comparison it is also
-- immune to the JWT-signing-key migration in progress on this project and to
-- the pending deprecation of SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY.
--
-- ----------------------------------------------------------------------------
-- ⚠ SCOPE — WHY 16 JOBS AND NOT 18  (review round 1, finding P0-1/P0-2)
-- ----------------------------------------------------------------------------
-- `verify_jwt` is NOT uniform across the fleet. When verify_jwt=true the
-- Supabase GATEWAY validates the bearer as a project-signed JWT *before the
-- module loads*. An opaque CRON_SECRET is not a JWT, so the gateway rejects it
-- and the module never runs. Exactly two cron-targeted functions are
-- verify_jwt=true (verified live via list_edge_functions):
--
--   jobid  8  compute-coach-signals        verify_jwt=true,  NO module gate
--             => WORKS TODAY. The service_role JWT passes the gateway and the
--                module has no further check. coach_memory.signals_computed_at
--                max = 2026-07-25 21:00:05, five seconds after its dispatch.
--                Repointing it to an opaque token would BREAK the only cron
--                job that currently functions.
--
--   jobid 30  compute-admin-metrics-daily  verify_jwt=true,  module gate at :120
--             => Broken today (gateway passes the JWT, module gate 401s) AND
--                would stay broken after a repoint (gateway would 401 first).
--                admin_metrics_daily has 0 rows despite 13 dispatches.
--
-- Both are handled in migration 108, which MUST be applied only after their
-- verify_jwt flags are flipped to false (and, for compute-coach-signals, after
-- an auth gate is deployed to it — it currently has none, so flipping the flag
-- first would leave it fully public). Same batch, hard ordering dependency.
--
-- PRE-CONDITIONS (founder-side, MUST hold before applying):
--   1. Edge Function secret CRON_SECRET is set.
--   2. Vault secret `cron_secret` holds the IDENTICAL value.
--   NEVER commit the value to this file.
--
-- ⚠ ACCEPTED RISK, RECORDED 2026-07-26 — SECRET STRENGTH
--   The recommended value is `openssl rand -hex 32`. The value in use at apply
--   time is 20 characters, letters only, no digits or symbols, and contains a
--   dictionary word (measured without decrypting: 14 distinct chars). Founder
--   was advised twice and chose to apply as-is and rotate later.
--
--   Why it matters here specifically: every function this migration repoints is
--   verify_jwt=false, so its URL accepts unauthenticated POSTs from anywhere and
--   this secret is the ONLY gate in front of privileged fan-out — push sends,
--   Gemini spend, and clean-orphan-media, which DELETES Storage objects.
--
--   Rotation is cheap and needs no migration: update the Vault row `cron_secret`
--   and the CRON_SECRET Edge Function secret to the same new value. Both are
--   read at call time, so the change takes effect on the next tick with no
--   redeploy and no re-apply.
--
-- POST-APPLY (required, not optional): run the positive smoke in the diagnose
-- doc — POST one verify_jwt=false cron function with the secret and expect 200.
-- Nothing in SQL can prove the Vault value equals the Edge Function value; a
-- mismatch reproduces the identical silent 401 storm.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. New Vault accessor, locked down from the start.
--
--    Lives in `private`, which is not PostgREST-reachable: anon/authenticated
--    hold no USAGE on the schema (verified has_schema_privilege = false), so
--    the default PUBLIC execute grant is not exploitable. The REVOKE below is
--    defense-in-depth making the grant explicit rather than inherited.
-- ----------------------------------------------------------------------------
--    search_path deliberately MATCHES private.morning_alert_get_service_key()
--    rather than the stricter TO '' — vault.decrypted_secrets decrypts via
--    pgsodium in `extensions`, and the existing accessor with this exact
--    search_path is proven to work in production. Review round 1 raised TO ''
--    as a P3 hardening nit and separately verified the path is not exploitable
--    (has_schema_privilege('anon'|'authenticated','public','create') = false),
--    so tightening it here would trade a real decryption risk for no gain.
--    RAISES rather than returning NULL when the Vault row is missing. A plain
--    SELECT would reproduce the exact failure shape this migration exists to
--    fix: `'Bearer ' || NULL` is NULL, the header goes out empty, the function
--    401s, and — because the auth gate precedes telemetry — nothing is logged.
--    That is jobid 7's bug (header §4) and the 2026-05-12 audit P0 both over
--    again. Raising instead surfaces a future Vault disappearance as
--    cron.job_run_details.status='failed', which IS visible.
CREATE OR REPLACE FUNCTION private.cron_get_secret()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'vault', 'private'
AS $fn$
DECLARE
  v text;
BEGIN
  SELECT decrypted_secret INTO v
  FROM vault.decrypted_secrets
  WHERE name = 'cron_secret'
  LIMIT 1;

  IF v IS NULL OR length(v) = 0 THEN
    RAISE EXCEPTION
      'Vault secret `cron_secret` is missing or empty — cron auth cannot '
      'proceed. Add it under Project Settings -> Vault, matching the '
      'CRON_SECRET Edge Function secret exactly.';
  END IF;

  RETURN v;
END;
$fn$;

REVOKE ALL ON FUNCTION private.cron_get_secret() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.cron_get_secret() TO postgres;

-- ----------------------------------------------------------------------------
-- 2. Bring the service-role accessor in line (#35).
--
--    private.morning_alert_get_service_key() is SECURITY DEFINER returning the
--    service_role key in PLAINTEXT, yet carried the DEFAULT ACL (PUBLIC may
--    execute). Not currently exploitable for the same schema-USAGE reason as
--    above — this is hardening, not a live hole. private.founder_metrics
--    already uses the correct pattern.
--
--    Safe: all 22 cron jobs run as username='postgres' (verified), and the sole
--    non-cron caller (dispatch_proactive_coach_promotion) is SECURITY DEFINER
--    owned by postgres. Zero views/matviews reference it.
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION private.morning_alert_get_service_key() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.morning_alert_get_service_key() TO postgres;

-- ----------------------------------------------------------------------------
-- 3. Fail CLOSED before touching anything if the Vault side isn't ready.
-- ----------------------------------------------------------------------------
-- The accessor itself raises on a missing/empty secret (section 1), so simply
-- calling it here aborts the whole migration before section 4 touches any job.
DO $$
BEGIN
  PERFORM private.cron_get_secret();
END $$;

-- ----------------------------------------------------------------------------
-- 4. Repoint the 16 verify_jwt=false HTTP cron jobs.
--
--    Live counts verified 2026-07-26 immediately before authoring:
--      17 jobs -> 'Bearer ' || private.morning_alert_get_service_key()
--                 (three whitespace variants; both replace() targets match
--                 character-for-character and are disjoint)
--       1 job  -> jobid 7 promote_community_item_daily, which uses
--                 current_setting('app.settings.service_role_key', true).
--                 No such setting exists on this project, so the expression is
--                 NULL and 'Bearer ' || NULL evaluates to NULL — the job has
--                 sent a NULL Authorization header since creation and has
--                 never once succeeded, independent of this outage.
--      = 18 HTTP jobs, minus the 2 verify_jwt=true ones (see SCOPE above) = 16.
--    Those 2 are excluded SEMANTICALLY below — by the URL-builder function their
--    command calls, not by hardcoded jobid — so this stays correct if they are
--    ever unscheduled and re-created with new ids.
--    The 4 pure-SQL jobs (23 cleanup, 26/27/29 alert_*) are untouched.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  r        record;
  new_cmd  text;
  n        int := 0;
  already  int := 0;
BEGIN
  -- Idempotency: count jobs already on the new accessor from a prior run.
  -- NB the two verify_jwt=true jobs are excluded SEMANTICALLY (by the URL-
  -- builder function their command calls) rather than by hardcoded jobid, so
  -- this stays correct if the jobs are ever unscheduled and re-created.
  SELECT count(*) INTO already
  FROM cron.job
  WHERE command LIKE '%private.cron_get_secret()%'
    AND command NOT LIKE '%compute_coach_signals_function_url%'
    AND command NOT LIKE '%compute_admin_metrics_function_url%';

  FOR r IN
    SELECT jobid, jobname, command
    FROM cron.job
    WHERE (command LIKE '%morning_alert_get_service_key%'
           OR command LIKE '%app.settings.service_role_key%')
      -- verify_jwt=true — an opaque token dies at the gateway. Migration 108.
      AND command NOT LIKE '%compute_coach_signals_function_url%'
      AND command NOT LIKE '%compute_admin_metrics_function_url%'
    ORDER BY jobid
  LOOP
    new_cmd := replace(
      r.command,
      'private.morning_alert_get_service_key()',
      'private.cron_get_secret()'
    );
    new_cmd := replace(
      new_cmd,
      'current_setting(''app.settings.service_role_key'', true)',
      'private.cron_get_secret()'
    );

    -- Guard against counting a no-op as a repoint (a future variant spelling
    -- would otherwise inflate n and pass the total check while unchanged).
    IF new_cmd = r.command THEN
      RAISE EXCEPTION
        'jobid % (%) matched the WHERE clause but neither replacement applied '
        '— unrecognised token expression, aborting.', r.jobid, r.jobname;
    END IF;

    PERFORM cron.alter_job(r.jobid, command := new_cmd);
    n := n + 1;
    RAISE NOTICE 'repointed jobid % (%)', r.jobid, r.jobname;
  END LOOP;

  -- Fail closed on drift, but tolerate a clean re-run (already + n = 16).
  IF n + already <> 16 THEN
    RAISE EXCEPTION
      'expected 16 verify_jwt=false HTTP cron jobs on the new accessor, got % '
      'repointed + % already migrated = %. Aborting so no partial state is '
      'left behind; re-measure cron.job before re-running.',
      n, already, n + already;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 5. Repoint the proactive-coach-promotion TRIGGER (review finding P1-3).
--
--    private.dispatch_proactive_coach_promotion() fires from
--    trg_dispatch_proactive_coach_promotion on public.rank_promotions and POSTs
--    to /functions/v1/proactive-coach-promotion (verify_jwt=false, gated by
--    isAuthorizedCronCall). It is NOT a cron.job row, so section 4 cannot see
--    it — it would have kept 401ing silently.
--
--    Rewritten via pg_get_functiondef so the body is preserved verbatim rather
--    than transcribed by hand.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  def      text;
  new_def  text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO def
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'private'
    AND p.proname = 'dispatch_proactive_coach_promotion';

  IF def IS NULL THEN
    RAISE EXCEPTION 'private.dispatch_proactive_coach_promotion() not found';
  END IF;

  new_def := replace(
    def,
    'private.morning_alert_get_service_key()',
    'private.cron_get_secret()'
  );

  IF new_def = def THEN
    -- Already migrated, or the accessor call is spelled differently. Only the
    -- former is acceptable.
    IF def LIKE '%private.cron_get_secret()%' THEN
      RAISE NOTICE 'trigger fn already on the new accessor — skipping';
    ELSE
      RAISE EXCEPTION
        'private.dispatch_proactive_coach_promotion() does not call the '
        'expected accessor — aborting rather than guessing.';
    END IF;
  ELSE
    EXECUTE new_def;
    RAISE NOTICE 'repointed trigger fn dispatch_proactive_coach_promotion';
  END IF;
END $$;

-- ============================================================================
-- ROLLBACK (inline) — restores the exact pre-migration command text.
-- Returns the fleet to the KNOWN-BROKEN 401 state; an escape hatch, not a fix.
-- The GRANT/REVOKE changes are intentionally NOT reversed — the default-PUBLIC
-- ACL they replaced was itself the defect (#35).
-- ----------------------------------------------------------------------------
-- DO $$
-- DECLARE r record; new_cmd text; def text;
-- BEGIN
--   FOR r IN SELECT jobid, command FROM cron.job
--            WHERE command LIKE '%private.cron_get_secret()%'
--   LOOP
--     new_cmd := replace(r.command, 'private.cron_get_secret()',
--                                   'private.morning_alert_get_service_key()');
--     PERFORM cron.alter_job(r.jobid, command := new_cmd);
--   END LOOP;
--
--   SELECT pg_get_functiondef(p.oid) INTO def FROM pg_proc p
--     JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='private' AND p.proname='dispatch_proactive_coach_promotion';
--   EXECUTE replace(def, 'private.cron_get_secret()',
--                        'private.morning_alert_get_service_key()');
-- END $$;
-- ============================================================================
