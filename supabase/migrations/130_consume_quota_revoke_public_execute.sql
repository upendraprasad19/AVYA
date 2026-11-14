-- Intent: Remove PUBLIC/anon/authenticated EXECUTE on consume_quota() — it is
--   SECURITY INVOKER with no ownership check on p_user_id, and is
--   un-exploitable today only by the accident of usage_counters having RLS
--   enabled with ZERO policies. OI-162 slice 4 puts a DPDP-erasure lockout
--   (delete_account quota) and a payment throttle (verify_payment quota)
--   behind that accident, so it is hardened deliberately here rather than
--   left as a filed issue (CLAUDE.md §4.2 — this is the change that makes
--   the gap dangerous, so it is fixed in the same batch).
--
-- Destructive?: no — revokes a privilege nothing currently depends on.
--   Verified 2026-09-11: `grep -rn consume_quota lib/` is EMPTY (no client
--   caller exists); both Edge Functions that call it (delete-account,
--   verify-payment) use a service_role client, which is UNAFFECTED — this
--   revoke targets PUBLIC/anon/authenticated only; the three live cap
--   triggers that call it (enforce_chat_app_daily_limit,
--   enforce_food_text_daily_limit, enforce_vision_analysis_daily_limit) are
--   only ever invoked via ai-proxy's service_role client — the two channel
--   values a client CAN write directly ('app_event', 'in_app_orphan') early-
--   return in all three triggers before reaching consume_quota.
--
-- Rollback strategy: inline — see commented block at end of file. Re-granting
--   EXECUTE to PUBLIC restores the pre-migration ACL exactly (nothing else in
--   this migration is destructive or has a side effect to unwind).
--
-- Linked diagnose-doc: f2c8d5
--
-- ⚠ FROM PUBLIC ALONE IS NOT ENOUGH HERE — the opposite of the lesson
-- migrations 090/091 teach for most functions in this codebase, and the
-- reason is visible in the live ACL at authoring time:
--   {=X/postgres, postgres=X/postgres, anon=X/postgres,
--    authenticated=X/postgres, service_role=X/postgres}
-- `=X/postgres` is the PUBLIC entry; `anon=X/postgres` and
-- `authenticated=X/postgres` are SEPARATE DIRECT grants, not inherited
-- through PUBLIC. `091`'s functions predated the schema-wide
-- `ALTER DEFAULT PRIVILEGES` policy and had ONLY a PUBLIC-sourced grant, so
-- revoking PUBLIC alone genuinely fixed them. `consume_quota` was created
-- under that default-ACL regime (migration 128 also runs
-- `GRANT EXECUTE ... TO service_role, authenticated;` explicitly), so it
-- carries independent non-PUBLIC sources and a PUBLIC-only revoke would be a
-- no-op for anon/authenticated. Revoke ALL THREE explicitly.

REVOKE EXECUTE ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer)
  FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer)
  TO service_role;

-- Rollback (NOT executed; restores the pre-migration ACL if this must be undone):
-- GRANT EXECUTE ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer)
--   TO PUBLIC;
