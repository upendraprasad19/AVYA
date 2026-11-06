-- Intent: Reset the daily AI caps (chat free 7 / PRO 20, vision free 4 / PRO 20), make the chat cap count ONLY reservation rows, and add refund_quota() so a transport-failed turn gives its unit back (3 refunds per IST day per user).
-- Destructive?: no   -- two CREATE OR REPLACE trigger functions + one new function; no schema change, no row rewrite; existing usage_counters rows are read as-is (a free user already at 7+ chat or 4+ vision units today is blocked immediately on apply)
-- Rollback strategy: inline   -- chat -> migration 129 body, vision -> migration 132 body, DROP FUNCTION refund_quota; commented at the end of the file
-- Linked diagnose-doc: c4e9b2, d7a1f5
--
-- 153_gemini3_limits_refund.sql
--
-- Plan: docs/plans/gemini3-limits-caching.md section 4 (B1). Applied to prod
-- via MCP apply_migration after the founder's explicit go (2026-10-02); this
-- file landed in the SAME commit as its backups/applied_migrations.json entry
-- (Gate 14 + check_migration_ledger_paired.dart).
--
-- Three changes, one file, because they share one apply window:
--
-- 1. CHAT cap: free 7/day, PRO 20/day (was free 10, PRO exempt).
--    - PRO now consumes a unit. Migration 129's "PRO early return" is gone.
--    - The trigger counts ONLY reservation rows (`model_used = 'pending'`).
--      ai-media-proxy writes PRO media rows with channel='app' and a real
--      model label; they have their own media caps and must not burn chat
--      units. ai-proxy's chat reservation insert is the only 'pending' writer
--      on channel 'app'.
--    - `daily_cap` stays a VARIABLE (not an inline CASE): the parity helpers
--      (readProFreeCap / readSingleCeiling) parse that shape.
--
-- 2. VISION cap: free 4/day, PRO 20/day, still ONE shared budget across
--    scan_meal + cart_auditor. Body is migration 132's verbatim except the
--    tier lookup and the cap. The `IS NULL OR` channel guard is kept.
--
-- 3. refund_quota(p_reservation_id, p_label): gives ONE unit back after a
--    TRANSPORT failure (5xx / 429 / 404 / timeout / non-deterministic empty
--    reply). It never runs for SAFETY-class blocks, rounds-exhausted, parse
--    failures or cap refusals; that decision lives in ai-proxy
--    (refundableFailure in _shared/gemini.ts), not here.
--    - LATCH: `UPDATE ... WHERE id = $1 AND model_used = 'pending'` flips the
--      reservation row to the failure label and RETURNs its user/channel/
--      created_at in ONE statement. Two concurrent calls (or a retry) cannot
--      both refund: the loser matches no row and returns -1.
--    - The window is the IST day of the ROW's created_at. For an ordinary turn
--      that is the day the trigger charged. Across IST midnight (a turn that
--      started at 23:59 and failed at 00:01) the trigger charged the day it
--      ran in, so the unit goes back to THAT day's counter, which is no longer
--      the cap in force: a harmless, documented under-refund, never an over-refund.
--    - BUDGET: after the latch, `refund_budget` (3 per IST day) is consumed
--      through consume_quota. An exhausted budget leaves the row stamped but
--      does NOT decrement: the unit stays spent, which is the intended cost of
--      a user who keeps triggering provider failures.
--    - Decrement is `used = used - 1 ... AND used > 0`: never negative.
--    - Returns the new `used`, or -1 when nothing was refunded.
--    - The ledger row is checked BEFORE the budget is spent, so a refund that has
--      nothing to decrement (absent row, or used already 0) does not burn one of
--      the user's 3 daily refunds.
--    - `p_label = 'pending'` is treated as 'failed' (a refund must never leave the
--      row refundable again); a NULL `created_at` falls back to now().
--
-- ACCEPTED RESIDUE (B-pass 2026-10-01, documented rather than hidden):
--    * `authenticated` holds INSERT on ai_coach_interactions (insert_own policy).
--      Before this file, a client insert with channel 'app' hit the chat trigger and
--      was refused 42501 (consume_quota is not executable by authenticated). Now a
--      client row with channel 'app' and a model_used other than 'pending' passes
--      the early return and is stored. It buys no AI call and no quota (it is the
--      user's own history/summaries), so it is a boundary softened, not a quota
--      hole; closing it needs a BEFORE UPDATE/INSERT guard on client-supplied
--      model_used, which is a separate surface. `model_used` is also client-
--      updatable (update_own), so the latch predicate is not a security boundary;
--      refund_quota is reachable only by service_role with ids ai-proxy minted.
--    - SECURITY INVOKER, service_role only (ACL below). The platform's default
--      privileges grant new public functions straight to anon + authenticated,
--      so REVOKE must name them explicitly (migration 130 / diagnose f2c8d5).
--
-- APPLY OFF-PEAK: free users already at 7+ chat units or 4+ vision units today
-- are over the new cap the moment this lands. That is the cap working, but it
-- is visible; apply in the quiet window and tell the founder.

-- ── 1. Chat: free 7 / PRO 20, reservation rows only ──────────────────────────

CREATE OR REPLACE FUNCTION public.enforce_chat_app_daily_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  is_pro    bool;
  daily_cap int;
  new_count int;
BEGIN
  -- Only the ai-proxy chat RESERVATION row spends a chat unit. Other channel
  -- 'app' writers (PRO media rows) carry a real model label, not 'pending'.
  IF NEW.channel IS DISTINCT FROM 'app'
     OR NEW.model_used IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE user_id = NEW.user_id
      AND status = 'active'
      AND end_date > now()
  ) INTO is_pro;

  daily_cap := CASE WHEN is_pro THEN 20 ELSE 7 END;

  new_count := public.consume_quota(
    NEW.user_id,
    'chat_app',
    (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
    daily_cap
  );

  IF new_count = -1 THEN
    RAISE EXCEPTION 'chat_app_daily_limit_reached (cap=%, pro=%)', daily_cap,
      CASE WHEN is_pro THEN 'true' ELSE 'false' END
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- ── 2. Vision: free 4 / PRO 20, one shared budget ────────────────────────────

CREATE OR REPLACE FUNCTION public.enforce_vision_analysis_daily_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  is_pro    bool;
  daily_cap int;
  new_count int;
BEGIN
  IF NEW.channel IS NULL OR NEW.channel NOT IN ('scan_meal', 'cart_auditor') THEN
    RETURN NEW;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM subscriptions
    WHERE user_id = NEW.user_id
      AND status = 'active'
      AND end_date > now()
  ) INTO is_pro;

  daily_cap := CASE WHEN is_pro THEN 20 ELSE 4 END;

  -- ONE shared budget across both channels, so both map to ONE quota_key.
  new_count := public.consume_quota(
    NEW.user_id,
    'vision_analysis',
    (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
    daily_cap
  );

  IF new_count = -1 THEN
    RAISE EXCEPTION 'vision_analysis_daily_limit_reached (cap=%, pro=%)', daily_cap,
      CASE WHEN is_pro THEN 'true' ELSE 'false' END
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

-- ── 3. refund_quota ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.refund_quota(
  p_reservation_id uuid,
  p_label          text DEFAULT 'failed'
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
AS $fn$
DECLARE
  v_user    uuid;
  v_channel text;
  v_created timestamptz;
  v_key     text;
  v_window  timestamptz;
  v_budget  integer;
  v_used    integer;
  v_label   text;
BEGIN
  IF p_reservation_id IS NULL THEN
    RAISE EXCEPTION 'refund_quota: null reservation id';
  END IF;

  -- LATCH. Flip the row out of 'pending' and read what we need in ONE
  -- statement; only the caller that flips it may refund.
  v_label := COALESCE(NULLIF(p_label, ''), 'failed');
  IF v_label = 'pending' THEN
    v_label := 'failed';   -- never re-arm the latch
  END IF;

  UPDATE public.ai_coach_interactions
     SET model_used = v_label
   WHERE id = p_reservation_id
     AND model_used = 'pending'
  RETURNING user_id, channel, created_at INTO v_user, v_channel, v_created;

  IF NOT FOUND THEN
    RETURN -1;
  END IF;

  v_key := CASE v_channel
    WHEN 'app'                THEN 'chat_app'
    WHEN 'scan_meal'          THEN 'vision_analysis'
    WHEN 'cart_auditor'       THEN 'vision_analysis'
    WHEN 'food_text_analysis' THEN 'food_text'
    ELSE NULL
  END;

  -- An unmapped channel is latched (terminal) but never refunded.
  IF v_key IS NULL THEN
    RETURN -1;
  END IF;

  v_window := date_trunc('day', COALESCE(v_created, now()) AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata';

  -- Nothing to give back (no ledger row, or already 0): stop BEFORE spending the budget.
  PERFORM 1 FROM public.usage_counters
   WHERE user_id = v_user AND quota_key = v_key AND window_start = v_window AND used > 0
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN -1;
  END IF;

  -- BUDGET: 3 refunds per user per IST day. Consumed only after the latch, so
  -- a replayed call cannot spend it.
  v_budget := public.consume_quota(v_user, 'refund_budget', v_window, 3);
  IF v_budget = -1 THEN
    RETURN -1;
  END IF;

  UPDATE public.usage_counters
     SET used = used - 1, updated_at = now()
   WHERE user_id = v_user
     AND quota_key = v_key
     AND window_start = v_window
     AND used > 0
  RETURNING used INTO v_used;

  IF NOT FOUND OR v_used IS NULL THEN
    RETURN -1;
  END IF;

  RETURN v_used;
END;
$fn$;

COMMENT ON FUNCTION public.refund_quota(uuid, text) IS
  'Gives one quota unit back after a transport failure (OI gemini3-limits-caching). '
  'Latches the reservation row out of pending, then spends refund_budget (3/IST day). '
  'service_role only. Returns the new used, or -1 when nothing was refunded.';

REVOKE ALL ON FUNCTION public.refund_quota(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refund_quota(uuid, text) TO service_role;

-- Verify (manual, AFTER apply; founder-run, read-only):
--   SELECT has_function_privilege('anon',          'public.refund_quota(uuid,text)', 'execute');  -- expect false
--   SELECT has_function_privilege('authenticated', 'public.refund_quota(uuid,text)', 'execute');  -- expect false
--   SELECT has_function_privilege('service_role',  'public.refund_quota(uuid,text)', 'execute');  -- expect true
--   SELECT pg_get_functiondef('public.enforce_chat_app_daily_limit()'::regprocedure);
--   SELECT pg_get_functiondef('public.enforce_vision_analysis_daily_limit()'::regprocedure);

-- ── Rollback (inline) ──────────────────────────────────────────────────────
-- Chat: re-run migration 129 section 2 verbatim (free 10, PRO early return,
--   no model_used predicate, message 'chat_app_daily_limit_reached (cap=10)').
-- Vision: re-run migration 132's function verbatim (flat cap 20, message
--   'vision_analysis_daily_limit_reached (cap=20)').
-- Refund: DROP FUNCTION public.refund_quota(uuid, text);
-- Deploy order on rollback: redeploy the pre-Part-B ai-proxy FIRST (it does not
-- call refund_quota), then run the SQL above; a Part-B ai-proxy against a
-- dropped refund_quota degrades to "no refund" (the RPC error is non-fatal).
