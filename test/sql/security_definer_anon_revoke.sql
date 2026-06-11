-- test/sql/security_definer_anon_revoke.sql
--
-- Live verification for migration 090 (diagnose c9b3e2). Run via the Supabase
-- MCP execute_sql AFTER the migration is applied. Asserts the anon-executable
-- SECURITY DEFINER surface is closed. Read-only — uses has_function_privilege()
-- so no role-switch / no writes are needed.
--
-- Expected after apply: every row's `ok` = true.

SELECT 'extend_subscription anon revoked' AS check,
       has_function_privilege('anon', 'public.extend_subscription(uuid, integer)', 'EXECUTE') = false AS ok
UNION ALL
SELECT 'extend_subscription authenticated revoked',
       has_function_privilege('authenticated', 'public.extend_subscription(uuid, integer)', 'EXECUTE') = false
UNION ALL
SELECT 'redeem_referral_atomic anon revoked',
       has_function_privilege('anon', 'public.redeem_referral_atomic(text, uuid, uuid, integer)', 'EXECUTE') = false
UNION ALL
SELECT 'redeem_referral_atomic authenticated revoked',
       has_function_privilege('authenticated', 'public.redeem_referral_atomic(text, uuid, uuid, integer)', 'EXECUTE') = false
UNION ALL
SELECT 'increment_promo_used_count anon revoked',
       has_function_privilege('anon', 'public.increment_promo_used_count(text)', 'EXECUTE') = false
UNION ALL
SELECT 'increment_promo_used_count authenticated revoked',
       has_function_privilege('authenticated', 'public.increment_promo_used_count(text)', 'EXECUTE') = false
UNION ALL
SELECT 'update_streak_progress anon revoked',
       has_function_privilege('anon', 'public.update_streak_progress(uuid, bigint, integer, text[], text)', 'EXECUTE') = false
UNION ALL
-- update_streak_progress: authenticated RETAINS execute (self-write path)…
SELECT 'update_streak_progress authenticated retained',
       has_function_privilege('authenticated', 'public.update_streak_progress(uuid, bigint, integer, text[], text)', 'EXECUTE') = true
UNION ALL
-- …but the body now blocks cross-account writes.
SELECT 'update_streak_progress cross-account guard present',
       pg_get_functiondef('public.update_streak_progress(uuid, bigint, integer, text[], text)'::regprocedure)
         ILIKE '%cross-account streak write blocked%'
UNION ALL
-- service_role keeps execute on the revoked-from-client functions.
SELECT 'extend_subscription service_role retained',
       has_function_privilege('service_role', 'public.extend_subscription(uuid, integer)', 'EXECUTE') = true
UNION ALL
-- search_path no longer mutable on the 10 flagged functions (spot-check 3).
SELECT 'match_memories search_path set',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='match_memories'
                 AND p.proconfig IS NOT NULL
                 AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
UNION ALL
SELECT 'morning_alert_get_service_key search_path set',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='private' AND p.proname='morning_alert_get_service_key'
                 AND p.proconfig IS NOT NULL
                 AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'));
