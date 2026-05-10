# Audit H-35 + H-36 + H-37: SECURITY DEFINER hardening

**Bug ID:** `audit-h35-secdef`
**Severity:** HIGH — search-path injection + anon RPC reach
**Date:** 2026-05-11
**Source:** Audit doc `docs/audit/2026-05-11/code-review-2026-05-11.md` H-35, H-36, H-37 (verified live on prod via MCP)

## Bug

Three related risks on SECURITY DEFINER artefacts in the `public` schema:

1. **H-35** — 5 SECURITY DEFINER functions had no `SET search_path` config, exposing them to search-path injection. A user who creates a `users` / `subscriptions` / `promo_codes` table in their own schema can poison name resolution inside the function and execute arbitrary SQL with elevated privs.
2. **H-36** — `coach_tool_invocations_v` view was created without `WITH (security_invoker=true)`, so it ran as the view owner (postgres / service_role), bypassing RLS on the underlying `ai_coach_interactions` table. Supabase advisor flagged it as `security_definer_view`.
3. **H-37** — 8 SECURITY DEFINER functions had `EXECUTE` granted to `anon` and `authenticated`. Combined with the leaked Supabase anon JWT (audit C-3), an attacker could call any of them via `POST /rest/v1/rpc/<fn>` from anywhere, bypassing the Edge Function business-rule check that's supposed to gate them. Most consequentially:
   - `extend_subscription(uuid, days)` — second PRO-grant path beyond C-1
   - `auto_approve_community_item()` — bypass the 10-vote threshold
   - `redeem_referral_atomic(...)` — burn referrer's credit without a real referee

## Cause

Migrations 010, 012, 020, 028, 037, 038, 039 all created SECURITY DEFINER functions and views over time without consistently applying:
- `SET search_path = <schema>` (search-path injection guard)
- `REVOKE EXECUTE ... FROM anon, authenticated` (RPC enumeration guard)

Default Postgres behavior grants EXECUTE to PUBLIC on new functions; Supabase grants apply both `anon` and `authenticated` to PUBLIC; without explicit REVOKE, the functions become RPC-callable via PostgREST.

The `coach_tool_invocations_v` view was added in migration 029 (or later — schema as code drift, see audit H-31). When created, Postgres 14 didn't have `security_invoker` views; Postgres 15+ added the option but the view was created the legacy way and never recreated.

## Past attempts

- Migrations 028, 037, 038, 039 set `SET search_path` on functions added IN those migrations (correct discipline). The 5 unprotected functions all predate that discipline.

## Fix

Migration 053 (`053_security_definer_hardening.sql`) — three parts:

### Part 1 — `SET search_path = public` on 5 functions

```sql
ALTER FUNCTION public.auto_approve_community_item()      SET search_path = public;
ALTER FUNCTION public.extend_subscription(uuid, integer) SET search_path = public;
ALTER FUNCTION public.increment_promo_used_count(text)   SET search_path = public;
ALTER FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer)
                                                         SET search_path = public;
ALTER FUNCTION public.update_user_subscription_status()  SET search_path = public;
```

### Part 2 — recreate `coach_tool_invocations_v` with `security_invoker=true`

Captured the existing view body via `pg_get_viewdef`, dropped, recreated identically with `WITH (security_invoker=true)`, granted SELECT to `authenticated`. RLS on `ai_coach_interactions` (which restricts to `auth.uid()=user_id`) now applies to view callers.

### Part 3 — REVOKE EXECUTE from anon + authenticated on 9 functions

```sql
REVOKE EXECUTE ON FUNCTION public.auto_approve_community_item()      FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.extend_subscription(...)            FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.increment_promo_used_count(...)     FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(...)         FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_user_subscription_status()   FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_auth_user()              FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()                   FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.compute_coach_signals_for_user(...) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.active_users_for_signals()          FROM anon, authenticated;
```

Pre-revoke audit (run 2026-05-11 via grep across `lib/`, `supabase/functions/`):
- `redeem_referral_atomic`, `increment_promo_used_count`, `active_users_for_signals` — only invoked from Edge Functions using service_role
- `compute_coach_signals_for_user` — only invoked from `compute-coach-signals`, `re-engagement`, `plateau-alert` Edge Functions
- `handle_new_auth_user`, `rls_auto_enable`, `update_user_subscription_status` — trigger functions; EXECUTE grant doesn't affect trigger firing
- `auto_approve_community_item` — only invoked by `promote-community-item` Edge Function
- `extend_subscription` — no callers found (was the most dangerous as RPC entry)

Zero client-side RPC calls to any of these. Safe to revoke from authenticated.

## Verification

Pre-migration prod state (run 2026-05-11):
```sql
-- 5 functions had config = '<none>' (no search_path):
--   auto_approve_community_item, extend_subscription,
--   increment_promo_used_count, redeem_referral_atomic,
--   update_user_subscription_status
-- 4 functions already had search_path set:
--   active_users_for_signals (public), compute_coach_signals_for_user (public),
--   handle_new_auth_user (public), rls_auto_enable (pg_catalog)
-- coach_tool_invocations_v: regular VIEW, not security_invoker
-- All 9 SECDEF functions had ACL: anon=X, authenticated=X, service_role=X
```

Post-migration prod state (verified):
```sql
-- All 9 functions now have search_path config
-- All 9 functions: only service_role retains EXECUTE
-- coach_tool_invocations_v: dropped + recreated WITH (security_invoker=true)
```

## Regression test

`regression-test-skipped: SQL-only migration; pre/post-state verified via MCP queries (captured above). Future re-grants of EXECUTE to anon would be caught by the Supabase advisor (`anon_security_definer_function_executable`) which we now treat as a CI gate.`

(Logging this skip per CLAUDE.md rule 22 process.)

## Related

- Audit C-1 (subscriptions RLS lockdown — migration 052) — same family of "PostgREST-callable bypass paths"
- Audit C-3 (anon JWT in git history) — the leaked anon JWT becomes much less dangerous post-053 because it can't invoke any of these functions anymore
- CLAUDE.md §11 (Edge Function auth model)
