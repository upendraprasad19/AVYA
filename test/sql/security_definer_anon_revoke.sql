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
-- Unit 3b (OI-45 cross-device half, e6b9c4, migration 115) — the new sibling
-- RPC needs the SAME anon-blocked / authenticated-retained shape as
-- update_streak_progress above.
SELECT 'update_user_progress_snapshot anon revoked',
       has_function_privilege('anon',
         'public.update_user_progress_snapshot(uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer, text, integer, integer, date, integer)',
         'EXECUTE') = false
UNION ALL
SELECT 'update_user_progress_snapshot authenticated retained',
       has_function_privilege('authenticated',
         'public.update_user_progress_snapshot(uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer, text, integer, integer, date, integer)',
         'EXECUTE') = true
UNION ALL
SELECT 'update_user_progress_snapshot service_role retained',
       has_function_privilege('service_role',
         'public.update_user_progress_snapshot(uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer, text, integer, integer, date, integer)',
         'EXECUTE') = true
UNION ALL
SELECT 'update_user_progress_snapshot cross-account guard present',
       pg_get_functiondef('public.update_user_progress_snapshot(uuid, bigint, integer, integer, timestamptz, timestamptz, integer, integer, text, integer, integer, date, integer)'::regprocedure)
         ILIKE '%cross-account progress write blocked%'
UNION ALL
-- Unit 5 (OI-48, 2026-07-31, diagnose a4e1c9, migration 117) — new RPC needs
-- the SAME service-role-only shape (no legitimate client caller exists;
-- re-engagement is cron-dispatched, always service_role).
SELECT 'find_reengagement_silent_candidates anon revoked',
       has_function_privilege('anon',
         'public.find_reengagement_silent_candidates(date, timestamptz, uuid[])', 'EXECUTE') = false
UNION ALL
SELECT 'find_reengagement_silent_candidates authenticated revoked',
       has_function_privilege('authenticated',
         'public.find_reengagement_silent_candidates(date, timestamptz, uuid[])', 'EXECUTE') = false
UNION ALL
SELECT 'find_reengagement_silent_candidates service_role retained',
       has_function_privilege('service_role',
         'public.find_reengagement_silent_candidates(date, timestamptz, uuid[])', 'EXECUTE') = true
UNION ALL
-- Unit 5's sibling fix (migration 117 Part 2) — find_orphan_chat_media
-- (migration 071) was anon+authenticated-executable live since its creation;
-- this migration narrows it to match its always-documented service-role-only
-- intent (clean-orphan-media is its one caller, always service_role).
SELECT 'find_orphan_chat_media anon revoked',
       has_function_privilege('anon', 'public.find_orphan_chat_media(timestamptz)', 'EXECUTE') = false
UNION ALL
SELECT 'find_orphan_chat_media authenticated revoked',
       has_function_privilege('authenticated', 'public.find_orphan_chat_media(timestamptz)', 'EXECUTE') = false
UNION ALL
SELECT 'find_orphan_chat_media service_role retained',
       has_function_privilege('service_role', 'public.find_orphan_chat_media(timestamptz)', 'EXECUTE') = true
UNION ALL
-- Unit 5 round-2 review (N2) — find_reengagement_silent_candidates must set
-- search_path like every other directly-callable public RPC (confirmed live:
-- find_orphan_chat_media's own proconfig is search_path=public,extensions,
-- vault,private; migration 115's RPC sets search_path TO 'public'). Omitting
-- it would have been the first directly-callable public RPC to regress the
-- function_search_path_mutable lint category the 2026-06-11 audit closed 9/9.
SELECT 'find_reengagement_silent_candidates search_path set',
       EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='find_reengagement_silent_candidates'
                 AND p.proconfig IS NOT NULL
                 AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
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
