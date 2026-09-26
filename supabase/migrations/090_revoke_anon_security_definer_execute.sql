-- 090_revoke_anon_security_definer_execute.sql
--
-- Security hardening (quarterly audit 2026-06-11, diagnose c9b3e2).
--
-- ⚠️ NOTE: the `REVOKE EXECUTE ... FROM anon, authenticated` statements below are
-- NO-OPS — EXECUTE is granted to PUBLIC by default and anon/authenticated inherit
-- it. The effective revoke lives in migration 091 (REVOKE ... FROM PUBLIC + GRANT
-- to the trusted roles). The `update_streak_progress` auth.uid() guard + the
-- search_path ALTERs in this migration DID apply correctly and remain authoritative.
--
-- The Supabase security advisor + pg_proc inspection found several SECURITY
-- DEFINER functions in `public` that were EXECUTE-able by the `anon` and/or
-- `authenticated` roles over PostgREST (/rest/v1/rpc/<fn>). Because SECURITY
-- DEFINER bypasses RLS, this was a real privilege-escalation surface:
--   * extend_subscription(uuid,int)  → anyone could grant any account free PRO
--   * redeem_referral_atomic(...)    → anyone could mint free referral days
--   * increment_promo_used_count     → promo-counter tampering
--   * update_streak_progress(...)    → cross-account streak writes
-- Verified callers (grep lib/ + supabase/functions/):
--   - increment_promo_used_count : verify-payment + razorpay-webhook EFs (service_role)
--   - redeem_referral_atomic     : redeem-referral EF (service_role)
--   - extend_subscription        : NO caller in repo (admin/manual via service key)
--   - update_streak_progress     : NOT invoked by literal RPC name anywhere (the
--                                  optimistic-lock client path references it only in
--                                  comments). Keep `authenticated` EXECUTE for any
--                                  future/self caller but block anon + cross-account.
-- Trigger functions (auto_approve_community_item, update_user_subscription_status,
-- handle_new_auth_user, rls_auto_enable) fire from triggers regardless of role
-- EXECUTE grants — revoking direct RPC EXECUTE does NOT affect trigger firing.
--
-- service_role retains EXECUTE on all (EFs/cron unaffected).

BEGIN;

-- ── 1. Service-only / dead / trigger functions: no direct client RPC. ──────────
REVOKE EXECUTE ON FUNCTION public.extend_subscription(uuid, integer)                       FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer)        FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.increment_promo_used_count(text)                         FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.auto_approve_community_item()                            FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_user_subscription_status()                        FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user()                                   FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()                                        FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cron_call_log_cleanup_7d()                               FROM anon, authenticated;

-- ── 2. update_streak_progress: revoke anon; keep authenticated but block ───────
--     cross-account writes via an auth.uid() guard (service_role: uid IS NULL → allowed).
REVOKE EXECUTE ON FUNCTION public.update_streak_progress(uuid, bigint, integer, text[], text) FROM anon;

CREATE OR REPLACE FUNCTION public.update_streak_progress(
  p_user_id uuid,
  p_expected_version bigint,
  p_freezes_available integer,
  p_freeze_used_dates text[],
  p_freezes_last_refill text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_current_version BIGINT;
  v_new_version BIGINT;
BEGIN
  -- Security (audit 2026-06-11 / c9b3e2): an authenticated caller may only write
  -- its OWN streak. service_role / cron (auth.uid() IS NULL) pass through.
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'cross-account streak write blocked (caller % != target %)',
      auth.uid(), p_user_id;
  END IF;

  SELECT streak_progress_version INTO v_current_version
    FROM public.user_progress
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF NOT FOUND THEN
    IF p_expected_version <> 0 THEN
      RETURN NULL;
    END IF;
    INSERT INTO public.user_progress (
      user_id,
      streak_freezes_available,
      streak_freeze_used_dates,
      streak_freezes_last_refill,
      streak_progress_version
    ) VALUES (
      p_user_id,
      p_freezes_available,
      p_freeze_used_dates,
      p_freezes_last_refill,
      1
    );
    RETURN 1;
  END IF;

  IF v_current_version <> p_expected_version THEN
    RETURN NULL;
  END IF;

  v_new_version := v_current_version + 1;
  UPDATE public.user_progress
    SET streak_freezes_available = p_freezes_available,
        streak_freeze_used_dates = p_freeze_used_dates,
        streak_freezes_last_refill = p_freezes_last_refill,
        streak_progress_version = v_new_version
    WHERE user_id = p_user_id
      AND streak_progress_version = p_expected_version;
  RETURN v_new_version;
END;
$function$;

-- ── 3. search_path hardening (advisor function_search_path_mutable, 10 fns). ────
--     Broad inclusive fixed path → clears the "mutable" finding without breaking
--     any unqualified reference (public tables, pgvector ops in extensions, vault).
ALTER FUNCTION private.compute_coach_signals_function_url()                  SET search_path = public, extensions, vault, private;
ALTER FUNCTION private.morning_alert_function_url()                          SET search_path = public, extensions, vault, private;
ALTER FUNCTION private.morning_alert_get_service_key()                       SET search_path = public, extensions, vault, private;
ALTER FUNCTION public.cron_call_log_cleanup_7d()                            SET search_path = public, extensions, vault, private;
ALTER FUNCTION public.enforce_food_text_daily_limit()                       SET search_path = public, extensions, vault, private;
ALTER FUNCTION public.find_orphan_chat_media(timestamp with time zone)      SET search_path = public, extensions, vault, private;
ALTER FUNCTION public.get_users_with_message_count(integer)                 SET search_path = public, extensions, vault, private;
ALTER FUNCTION public.match_memories(uuid, vector, integer, double precision) SET search_path = public, extensions, vault, private;
ALTER FUNCTION public.morning_alert_pick_quarter(date, text, boolean, integer, integer) SET search_path = public, extensions, vault, private;
ALTER FUNCTION public.touch_coach_memory_updated_at()                       SET search_path = public, extensions, vault, private;

COMMIT;

-- NOT fixed here (founder-console only, documented in diagnose c9b3e2):
--   * auth leaked-password protection (Auth settings toggle)
--   * public buckets avatars/banners broad SELECT listing policy (storage)
