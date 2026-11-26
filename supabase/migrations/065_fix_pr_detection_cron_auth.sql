-- 065_fix_pr_detection_cron_auth.sql
-- Closes-diagnose: 5a65bd (docs/diagnoses/2026-05-15-pr-detection-cron-401-5a65bd.md)
-- Author: APK Test #16 audit A4 (2026-05-15)
--
-- Symptom
-- -------
-- pr-detection Edge Function cron returns 401 every 15 min. Same shape
-- affects every other proactive-trigger function with verify_jwt=false +
-- the C-4 cron-auth-gate (re-engagement, plateau-alert, protein-gap-alert,
-- workout-window-closing, streak-guardian, evaluate-rank-promotions,
-- i-see-you-callout, clean-orphan-media, expiry-reminder, weekly-recap-
-- ready). pr-detection is the most visible because */15 schedule.
--
-- Root cause
-- ----------
-- The cron.job entries dispatch:
--   Authorization: Bearer ' || private.morning_alert_get_service_key()
-- where the helper reads `vault.decrypted_secrets WHERE name='service_role_key'`.
-- The in-function gate then compares:
--   token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
-- Both used to agree (audit C-4 / migration 061 P1-D, 2026-05-11). Between
-- 2026-05-11 and 2026-05-15 the two values drifted — either the project's
-- service-role JWT was rotated platform-side, or the Vault row was
-- rewritten with a different copy. Equality check fails → 401.
--
-- Why this migration is a NO-OP / documentation-only
-- --------------------------------------------------
-- The cron.job entries are structurally correct (already using the Vault
-- path). Re-scheduling them won't change the body of
-- `private.morning_alert_get_service_key()`. The actual fix lives in the
-- Supabase Vault, not in cron.* tables.
--
-- Operational steps (main thread + founder, NOT SQL)
-- --------------------------------------------------
--   1. Dashboard → Settings → API → copy the current `service_role` JWT.
--   2. Dashboard → Settings → Vault → edit row named exactly
--      `service_role_key` → paste the JWT from step 1 → save.
--   3. Run the verification block below from MCP execute_sql / SQL editor.
--
-- Verification block (uncomment and run AFTER Vault refresh)
-- ----------------------------------------------------------
--   DO $$
--   DECLARE
--     v_req_id BIGINT;
--     v_status INT;
--     v_body TEXT;
--   BEGIN
--     v_req_id := net.http_post(
--       url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/pr-detection',
--       headers := jsonb_build_object(
--         'Content-Type', 'application/json',
--         'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
--       ),
--       body := '{}'::jsonb
--     );
--     PERFORM pg_sleep(2);
--     SELECT status_code, content::text INTO v_status, v_body
--       FROM net._http_response WHERE id = v_req_id;
--     RAISE NOTICE 'pr-detection verify: status=% body=%', v_status, v_body;
--     IF v_status <> 200 THEN
--       RAISE EXCEPTION 'pr-detection still failing after Vault refresh: status=% body=%', v_status, v_body;
--     END IF;
--   END $$;
--
-- Sanity check: list every cron job that uses the Vault Bearer pattern,
-- so we can confirm no entry was MISSED by audit P1-D.
DO $$
DECLARE
  r RECORD;
  vault_jobs INT := 0;
  hardcoded_jobs INT := 0;
BEGIN
  FOR r IN
    SELECT jobid, jobname, command
    FROM cron.job
    ORDER BY jobid
  LOOP
    IF r.command ILIKE '%private.morning_alert_get_service_key%' THEN
      vault_jobs := vault_jobs + 1;
    ELSIF r.command ~ 'Bearer\s+''\s*\|\|\s*''eyJ' OR r.command ~ 'Bearer\s+eyJ' THEN
      hardcoded_jobs := hardcoded_jobs + 1;
      RAISE WARNING '[065] cron job % (jobid=%) still uses hardcoded JWT — operational follow-up required', r.jobname, r.jobid;
    ELSIF r.command ILIKE '%app.settings.service_role_key%' THEN
      RAISE WARNING '[065] cron job % (jobid=%) uses current_setting(app.settings.service_role_key) which returns NULL on this project — separate fix needed', r.jobname, r.jobid;
    END IF;
  END LOOP;
  RAISE NOTICE '[065] cron-auth audit: %s vault-backed jobs, %s hardcoded jobs', vault_jobs, hardcoded_jobs;
END $$;

-- No DDL/data changes. Migration exists for traceability + the inline
-- verification harness. Main thread runs the operational Vault refresh
-- separately.
