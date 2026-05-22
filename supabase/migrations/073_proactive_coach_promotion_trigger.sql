-- 073_proactive_coach_promotion_trigger.sql
--
-- Theme C (closes-diagnose 2026-05-22 8b1f33).
--
-- Server-side proactive coach promotion congrats. Fires when a row
-- INSERTs into `rank_promotions` (existing RankService.evaluateAndPromote
-- writer) — Postgres trigger → pg_net.http_post → Edge Function
-- `proactive-coach-promotion` → AI message in coach_interactions +
-- OneSignal push.
--
-- Why server-side (vs client-side after-the-write):
--   - Client may be offline / paused when the promotion was evaluated.
--   - Multi-device: every signed-in device's coach surface needs the
--     congrats message (cloud-driven push, not client-stamped).
--   - The OneSignal push lands on the user's phone even if the app
--     isn't open — turning the moment into a real notification, not
--     just an in-app message they discover next time they open.
--
-- pg_net is already enabled (used by other cron-dispatch triggers).
-- service_role_key resolution uses private.morning_alert_get_service_key()
-- per Audit 2026-05-12 Vault fix.

-- Trigger function: fires after every INSERT into rank_promotions.
CREATE OR REPLACE FUNCTION private.dispatch_proactive_coach_promotion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_service_key text;
  v_supabase_url text;
  v_request_id bigint;
BEGIN
  -- Resolve service-role key from Vault (canonical pattern post-
  -- Audit 2026-05-12 Vault fix — never hardcode keys in DDL).
  SELECT private.morning_alert_get_service_key() INTO v_service_key;

  IF v_service_key IS NULL OR v_service_key = '' THEN
    -- Vault not seeded — fire telemetry but don't block the INSERT.
    -- The trigger is best-effort; missing the celebration push is
    -- non-fatal for the underlying rank record.
    INSERT INTO public.client_errors(
      user_id, op_type, message, severity
    ) VALUES (
      NEW.user_id,
      'proactive_coach_promotion_dispatch_failed',
      'service_role_key not set in Vault',
      'warn'
    );
    RETURN NEW;
  END IF;

  -- Resolve Supabase URL from a fixed env-level secret. The full
  -- functions endpoint shape is `${SUPABASE_URL}/functions/v1/<slug>`.
  v_supabase_url := 'https://dedsavbjuwgarrhphgnl.supabase.co';

  -- Fire-and-forget HTTP POST. pg_net returns immediately; the
  -- delivery happens async out-of-transaction.
  SELECT net.http_post(
    url := v_supabase_url || '/functions/v1/proactive-coach-promotion',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object(
      'user_id', NEW.user_id,
      'rank_code', NEW.rank_code,
      'achieved_at', COALESCE(NEW.achieved_at, NEW.created_at)::text,
      'trigger_source', 'rank_promotion_insert'
    )
  ) INTO v_request_id;

  -- Audit trail — observability into the trigger fan-out.
  INSERT INTO public.client_errors(
    user_id, op_type, message, severity
  ) VALUES (
    NEW.user_id,
    'proactive_coach_promotion_dispatched',
    'request_id=' || v_request_id || ' rank_code=' || NEW.rank_code,
    'info'
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never propagate trigger errors back to the INSERT — the rank
  -- record is the source of truth; the dispatch is purely additive.
  INSERT INTO public.client_errors(
    user_id, op_type, message, severity
  ) VALUES (
    NEW.user_id,
    'proactive_coach_promotion_dispatch_failed',
    LEFT(SQLERRM, 500),
    'warn'
  );
  RETURN NEW;
END;
$$;

-- Drop-and-recreate trigger to keep the migration idempotent.
DROP TRIGGER IF EXISTS trg_dispatch_proactive_coach_promotion
  ON public.rank_promotions;

CREATE TRIGGER trg_dispatch_proactive_coach_promotion
AFTER INSERT ON public.rank_promotions
FOR EACH ROW
EXECUTE FUNCTION private.dispatch_proactive_coach_promotion();

-- Grants. Only postgres / service_role can call the trigger function
-- (default for SECURITY DEFINER in private schema).

COMMENT ON FUNCTION private.dispatch_proactive_coach_promotion() IS
  'Theme C / 073 — fires proactive-coach-promotion Edge Function on '
  'every rank_promotions INSERT. Never propagates errors back to the '
  'parent transaction. Telemetry to client_errors.';

COMMENT ON TRIGGER trg_dispatch_proactive_coach_promotion ON public.rank_promotions IS
  'Theme C / 073 — async dispatch to AI coach + OneSignal push.';
