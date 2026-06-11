-- 091_security_definer_revoke_from_public.sql
--
-- Corrective to 090 (diagnose c9b3e2). The role-specific `REVOKE EXECUTE ... FROM
-- anon, authenticated` statements in 090 were NO-OPS: PostgreSQL grants EXECUTE to
-- PUBLIC by default, and anon/authenticated INHERIT it via PUBLIC. has_function_
-- privilege('anon', fn, 'EXECUTE') stayed true after 090. The correct pattern is
-- REVOKE FROM PUBLIC, then GRANT to the specific trusted roles. (Caught by the live
-- post-apply verification — apply_migration returning success ≠ the grant changed.)
--
-- REVOKE + GRANT run in one transaction (apply_migration wraps it) → no exposure
-- window for the legit service callers. service_role retains EXECUTE → the Edge
-- Functions (verify-payment, razorpay-webhook, redeem-referral) and cron are
-- unaffected. Trigger functions fire regardless of EXECUTE grant → revoke, no re-grant.

-- Service-callable (Edge Functions via service_role; admin via service key):
REVOKE EXECUTE ON FUNCTION public.extend_subscription(uuid, integer)                FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.extend_subscription(uuid, integer)                TO service_role;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) TO service_role;
REVOKE EXECUTE ON FUNCTION public.increment_promo_used_count(text)                  FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.increment_promo_used_count(text)                  TO service_role;
REVOKE EXECUTE ON FUNCTION public.cron_call_log_cleanup_7d()                        FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.cron_call_log_cleanup_7d()                        TO service_role;

-- Pure trigger functions: triggers fire regardless of EXECUTE grant → revoke only.
REVOKE EXECUTE ON FUNCTION public.auto_approve_community_item()      FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_user_subscription_status()  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user()             FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()                  FROM PUBLIC;

-- update_streak_progress: keep the authenticated self-write path (090's auth.uid()
-- body guard blocks cross-account writes); service_role for cron.
REVOKE EXECUTE ON FUNCTION public.update_streak_progress(uuid, bigint, integer, text[], text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.update_streak_progress(uuid, bigint, integer, text[], text) TO authenticated, service_role;
