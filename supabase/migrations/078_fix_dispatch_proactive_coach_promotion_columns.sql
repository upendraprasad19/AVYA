-- Intent: Fix private.dispatch_proactive_coach_promotion() — use NEW.achieved_at (not the non-existent NEW.created_at), correct client_errors columns (error_code/error_message/client_version/platform, not message/severity), and wrap the WHEN OTHERS handler's telemetry insert in a nested swallow so a telemetry failure can never abort the rank_promotions INSERT.
-- Destructive?: no   -- CREATE OR REPLACE FUNCTION replaces the function body only; no table, data, or constraint changes; no locks.
-- Rollback strategy: migration 079   -- author a follow-up CREATE OR REPLACE restoring the prior body (archived in diagnose f4b2c9); the trigger binding (trg_dispatch_proactive_coach_promotion) is untouched.
-- Linked diagnose-doc: f4b2c9
--
-- 078_fix_dispatch_proactive_coach_promotion_columns.sql
--
-- Diagnose: 2026-05-30-rank-promotion-dispatch-trigger-columns (f4b2c9)
-- Blast radius: catastrophic (SECURITY DEFINER trigger on the core rank ladder;
--   its failure aborted EVERY rank_promotions INSERT for EVERY user).
--
-- BUG (P0): the AFTER INSERT trigger function
-- private.dispatch_proactive_coach_promotion() referenced columns that do not
-- exist, so it raised inside the trigger and — because the trigger fires
-- AFTER INSERT FOR EACH ROW — aborted the originating rank_promotions INSERT.
-- Result: no rank promotion could ever persist; user_profile.current_rank_code
-- never advanced. Surfaced 2026-05-30 during live web E2E: amar@gmail.com
-- onboarded with ZERO rank_promotions rows (not even the SD2 floor).
--
-- Three defects in the prior function body:
--   1. body := jsonb_build_object('achieved_at', COALESCE(NEW.achieved_at,
--      NEW.created_at)...) — rank_promotions has NO `created_at` column
--      (columns: id, user_id, rank_code, achieved_at, trigger_type,
--      trigger_metadata). NEW.created_at resolution failed first → jumped to
--      the WHEN OTHERS handler.
--   2. Both the success-path and the WHEN OTHERS handler did
--      INSERT INTO public.client_errors(user_id, op_type, message, severity).
--      client_errors has NO `message` and NO `severity` columns (real:
--      error_message, error_code) → 42703. Same wrong-column class as the
--      Edge Function logTelemetry fixed in diagnose 9e1d4c (2026-05-29) — that
--      fix corrected the TypeScript side but MISSED this Postgres trigger.
--   3. The inserts omitted client_errors NOT NULL columns client_version +
--      platform — so even with correct names they would have failed NOT NULL.
--
-- Because the WHEN OTHERS handler ITSELF re-raised (same bad insert), the
-- exception escaped the trigger and rolled back the rank_promotions row.
--
-- FIX:
--   - Use NEW.achieved_at (NOT NULL) directly — drop the bogus NEW.created_at.
--   - All client_errors inserts use the real columns: user_id, op_type,
--     error_code, error_message, client_version ('server-trigger'), platform
--     ('server'). The old 'severity' value maps to error_code, 'message' to
--     error_message.
--   - The WHEN OTHERS handler's telemetry insert is wrapped in a nested
--     BEGIN/EXCEPTION ... NULL so a telemetry failure can NEVER again abort
--     the rank_promotions INSERT. Recording the promotion must always win over
--     dispatching its celebration.
--
-- Verified via live rollback-transaction test (2026-05-30): INSERT into
-- rank_promotions under the OLD function -> 42703; under the NEW function ->
-- succeeds + one 'proactive_coach_promotion_dispatched' client_errors row;
-- both rolled back (zero pollution).

CREATE OR REPLACE FUNCTION private.dispatch_proactive_coach_promotion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_service_key text;
  v_supabase_url text;
  v_request_id bigint;
BEGIN
  -- Resolve service-role key from Vault (canonical pattern post-Audit
  -- 2026-05-12 Vault fix — never hardcode keys in DDL).
  SELECT private.morning_alert_get_service_key() INTO v_service_key;

  IF v_service_key IS NULL OR v_service_key = '' THEN
    INSERT INTO public.client_errors(
      user_id, op_type, error_code, error_message, client_version, platform
    ) VALUES (
      NEW.user_id,
      'proactive_coach_promotion_dispatch_failed',
      'warn',
      'service_role_key not set in Vault',
      'server-trigger',
      'server'
    );
    RETURN NEW;
  END IF;

  v_supabase_url := 'https://dedsavbjuwgarrhphgnl.supabase.co';

  SELECT net.http_post(
    url := v_supabase_url || '/functions/v1/proactive-coach-promotion',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'rank_code', NEW.rank_code,
      'achieved_at', NEW.achieved_at::text,
      'trigger_source', 'rank_promotion_insert'
    )
  ) INTO v_request_id;

  INSERT INTO public.client_errors(
    user_id, op_type, error_code, error_message, client_version, platform
  ) VALUES (
    NEW.user_id,
    'proactive_coach_promotion_dispatched',
    'info',
    'request_id=' || v_request_id || ' rank_code=' || NEW.rank_code,
    'server-trigger',
    'server'
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Telemetry/dispatch failure must NEVER abort the rank_promotions INSERT
  -- (AFTER INSERT trigger exceptions roll back the row). Swallow defensively
  -- in a nested block so even a broken telemetry insert cannot propagate.
  BEGIN
    INSERT INTO public.client_errors(
      user_id, op_type, error_code, error_message, client_version, platform
    ) VALUES (
      NEW.user_id,
      'proactive_coach_promotion_dispatch_failed',
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
$function$;
