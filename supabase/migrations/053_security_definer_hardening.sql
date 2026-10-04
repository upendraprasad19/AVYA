-- Migration 053: SECURITY DEFINER hardening
--
-- closes-finding: H-35, H-36, H-37 (audit 2026-05-11)
--
-- Three hardening passes on existing SECURITY DEFINER artefacts:
--
-- 1. SET search_path = public on 5 SECURITY DEFINER functions that
--    currently have no search_path config (verified live via pg_proc.proconfig).
--    Without it, a malicious user who creates a `users` / `subscriptions` /
--    `promo_codes` table in their own schema can poison resolution
--    inside the function and execute arbitrary SQL with elevated privs.
--
-- 2. Recreate `coach_tool_invocations_v` view with `WITH (security_invoker=true)`
--    so RLS on `ai_coach_interactions` actually applies to view callers.
--    Currently the view runs as the creator (postgres / service_role),
--    bypassing RLS — flagged as `security_definer_view` by Supabase advisor.
--
-- 3. Revoke EXECUTE on user-impacting SECURITY DEFINER functions from
--    `anon` and `authenticated`, leaving service_role only. These are
--    intended to be called by Edge Functions / triggers, not directly
--    via PostgREST RPC.
--
-- Pre-migration audit (run 2026-05-11 via MCP):
--   5 functions confirmed missing search_path:
--     auto_approve_community_item, extend_subscription,
--     increment_promo_used_count, redeem_referral_atomic,
--     update_user_subscription_status
--   4 functions ALREADY hardened (no-op for those):
--     active_users_for_signals, compute_coach_signals_for_user,
--     handle_new_auth_user, rls_auto_enable

BEGIN;

-- ──────────────────────────────────────────────────────────────────────
-- Part 1: SET search_path = public on the 5 unprotected functions
-- ──────────────────────────────────────────────────────────────────────

ALTER FUNCTION public.auto_approve_community_item()      SET search_path = public;
ALTER FUNCTION public.extend_subscription(uuid, integer) SET search_path = public;
ALTER FUNCTION public.increment_promo_used_count(text)   SET search_path = public;
ALTER FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer)
                                                          SET search_path = public;
ALTER FUNCTION public.update_user_subscription_status()  SET search_path = public;

-- ──────────────────────────────────────────────────────────────────────
-- Part 2: recreate coach_tool_invocations_v with security_invoker=true
-- ──────────────────────────────────────────────────────────────────────

-- Definition captured from prod via pg_get_viewdef:
DROP VIEW IF EXISTS public.coach_tool_invocations_v;

CREATE VIEW public.coach_tool_invocations_v
  WITH (security_invoker=true)
AS
SELECT i.id AS interaction_id,
       i.user_id,
       i.created_at,
       i.model_used,
       call.value ->> 'name'        AS tool_name,
       call.value ->> 'status'      AS status,
       (call.value ->> 'latency_ms')::integer AS latency_ms,
       call.value ->> 'error'       AS error,
       call.value -> 'args'         AS args
  FROM public.ai_coach_interactions i,
       LATERAL jsonb_array_elements(COALESCE(i.tool_calls, '[]'::jsonb)) call(value)
 WHERE i.tool_calls IS NOT NULL;

-- Grant SELECT to authenticated (so app code can read tool history) — RLS
-- on ai_coach_interactions then enforces user_id = auth.uid() at the
-- underlying table layer because we're in security_invoker mode.
GRANT SELECT ON public.coach_tool_invocations_v TO authenticated;
-- service_role keeps full access (default).

-- ──────────────────────────────────────────────────────────────────────
-- Part 3: revoke RPC EXECUTE from anon on user-impacting SECDEF functions
-- ──────────────────────────────────────────────────────────────────────
--
-- These functions are called BY service-role (from Edge Functions or
-- triggers), not directly via PostgREST. Allowing anon EXECUTE means a
-- malicious caller with the leaked anon JWT can invoke them via:
--   POST /rest/v1/rpc/<fn>
-- bypassing the Edge Function business-rule check.
--
-- For `handle_new_auth_user` and `rls_auto_enable` — both are trigger
-- functions; revoking EXECUTE doesn't affect trigger firing (triggers
-- run with their own search_path/perms, ignoring the EXECUTE grant).
-- The ACL grant only matters for direct calls.

REVOKE EXECUTE ON FUNCTION public.auto_approve_community_item()
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.extend_subscription(uuid, integer)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.increment_promo_used_count(text)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer)
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_user_subscription_status()
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user()
  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()
  FROM anon, authenticated;

-- compute_coach_signals_for_user: confirmed via grep — all callers are
-- Edge Functions using service_role (re-engagement, plateau-alert,
-- compute-coach-signals). Zero client-side invocations.
REVOKE EXECUTE ON FUNCTION public.compute_coach_signals_for_user(uuid)
  FROM anon, authenticated;

-- active_users_for_signals: cron-only. Confirmed via grep — only
-- compute-coach-signals Edge Function calls it.
REVOKE EXECUTE ON FUNCTION public.active_users_for_signals()
  FROM anon, authenticated;

COMMIT;
