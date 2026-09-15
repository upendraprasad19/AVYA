-- test/sql/oi162_slice4_quota_boundary_and_acl_live_verify.sql
--
-- OI-162 slice 4 (diagnose f2c8d5). Two independent parts.
--
-- PART A — run any time, safe, rolled back. Drives consume_quota() through
-- synthetic quota_key values shaped like the two new callers
-- (delete_account limit=5, verify_payment limit=20) across the
-- limit-1/limit/limit+1 boundary, plus one bucket-isolation check. Uses a
-- real user_id (usage_counters.user_id has an ON DELETE CASCADE FK to
-- public.users — a random UUID would abort the transaction on insert) and a
-- synthetic 2099 window_start + a `oi162_slice4_test_` quota_key prefix, so
-- it cannot collide with any real row. Wrapped in BEGIN...ROLLBACK: nothing
-- persists. consume_quota's own behavior is UNCHANGED by this slice (it was
-- already proven for three other keys in e7c4b2) — this exercises the two
-- NEW keys specifically, which is what slice 4 adds.
--
-- PART B — has_function_privilege() ACL check. Read-only, safe to re-run any
-- time as a live regression check, per the same convention as
-- security_definer_anon_revoke.sql. Migration 130 WAS APPLIED 2026-09-11
-- 17:32 IST (founder-applied via the Management API after the agent's raw
-- curl attempt was correctly classifier-blocked as a live DDL write) — this
-- part is now a standing assertion, not a future one. Executed live
-- 2026-09-11 post-apply: all 3/3 rows `ok = true`.
--
-- Mutation-5 evidence for THIS diagnose-doc's ledger ("migration 130's
-- REVOKE narrowed back to FROM PUBLIC only ⇒ red") was gathered BEFORE
-- applying, live, read-only, with NO DDL run against prod at that time: the
-- PRE-apply raw ACL for consume_quota was
--   {=X/postgres, postgres=X/postgres, anon=X/postgres, authenticated=X/postgres, service_role=X/postgres}
-- — FOUR independent grant entries (the leading bare "=X" is the PUBLIC
-- grant; "anon=X" and "authenticated=X" were SEPARATE direct grants, not
-- inherited from PUBLIC). A `REVOKE ... FROM PUBLIC` would have removed only
-- the first entry, leaving `anon=X/postgres` and `authenticated=X/postgres`
-- untouched — exactly the ledger's predicted "red". This is why migration
-- 130's actual REVOKE lists PUBLIC, anon AND authenticated explicitly, and
-- POST-apply the raw ACL is now `{postgres=X/postgres, service_role=X/postgres}`
-- — both grants gone, confirming the reasoning was correct.

-- ============================================================================
-- PART A — boundary + bucket-isolation (safe to run now; rolled back)
-- ============================================================================
BEGIN;

DO $$
DECLARE
  v_user   uuid      := 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b'; -- any real users.id; FK requires one
  v_window timestamptz := '2099-01-01T00:00:00+00';             -- synthetic, can't collide with real data
  v_result integer;
  i        integer;
BEGIN
  CREATE TEMP TABLE oi162_slice4_probe (
    seq    serial,
    step   text,
    result integer
  );

  -- delete_account shape: limit = 5. Calls 1-4 succeed under the limit.
  FOR i IN 1..4 LOOP
    v_result := public.consume_quota(v_user, 'oi162_slice4_test_delete_account', v_window, 5);
    INSERT INTO oi162_slice4_probe (step, result) VALUES ('delete_account call ' || i, v_result);
  END LOOP;
  -- Call 5 (== limit) must still succeed and report exactly 5.
  v_result := public.consume_quota(v_user, 'oi162_slice4_test_delete_account', v_window, 5);
  INSERT INTO oi162_slice4_probe (step, result) VALUES ('delete_account call 5 (at limit)', v_result);
  -- Call 6 (limit+1) must refuse.
  v_result := public.consume_quota(v_user, 'oi162_slice4_test_delete_account', v_window, 5);
  INSERT INTO oi162_slice4_probe (step, result) VALUES ('delete_account call 6 (limit+1, must refuse)', v_result);

  -- verify_payment shape: limit = 20. Calls 1-19 succeed under the limit.
  FOR i IN 1..19 LOOP
    v_result := public.consume_quota(v_user, 'oi162_slice4_test_verify_payment', v_window, 20);
    INSERT INTO oi162_slice4_probe (step, result) VALUES ('verify_payment call ' || i, v_result);
  END LOOP;
  -- Call 20 (== limit) must still succeed and report exactly 20.
  v_result := public.consume_quota(v_user, 'oi162_slice4_test_verify_payment', v_window, 20);
  INSERT INTO oi162_slice4_probe (step, result) VALUES ('verify_payment call 20 (at limit)', v_result);
  -- Call 21 (limit+1) must refuse.
  v_result := public.consume_quota(v_user, 'oi162_slice4_test_verify_payment', v_window, 20);
  INSERT INTO oi162_slice4_probe (step, result) VALUES ('verify_payment call 21 (limit+1, must refuse)', v_result);

  -- Bucket isolation: the NEXT hour's bucket for the same key + user must be
  -- an independent counter (proves the PK really is the 3-column
  -- (user_id, quota_key, window_start), not just (user_id, quota_key) — the
  -- exact thing the FIXED-bucket-not-rolling fix in both Edge Functions
  -- depends on).
  v_result := public.consume_quota(v_user, 'oi162_slice4_test_delete_account', v_window + interval '1 hour', 5);
  INSERT INTO oi162_slice4_probe (step, result) VALUES ('delete_account, NEXT bucket (must be fresh, ==1)', v_result);
END $$;

SELECT
  step,
  result,
  CASE
    WHEN step LIKE '%at limit)%'       THEN result = (CASE WHEN step LIKE 'delete_account%' THEN 5 ELSE 20 END)
    WHEN step LIKE '%must refuse)%'    THEN result = -1
    WHEN step LIKE '%NEXT bucket%'     THEN result = 1
    ELSE result = substring(step FROM 'call (\d+)')::integer
  END AS ok
FROM oi162_slice4_probe
ORDER BY seq;

ROLLBACK;

-- ============================================================================
-- PART B — ACL check (migration 130 is live; safe to re-run any time)
-- ============================================================================
-- Executed live 2026-09-11 post-apply: all 3/3 rows `ok = true`.

SELECT 'consume_quota anon revoked' AS check,
       has_function_privilege('anon', 'public.consume_quota(uuid, text, timestamptz, integer)', 'EXECUTE') = false AS ok
UNION ALL
SELECT 'consume_quota authenticated revoked',
       has_function_privilege('authenticated', 'public.consume_quota(uuid, text, timestamptz, integer)', 'EXECUTE') = false
UNION ALL
SELECT 'consume_quota service_role retained',
       has_function_privilege('service_role', 'public.consume_quota(uuid, text, timestamptz, integer)', 'EXECUTE') = true;
