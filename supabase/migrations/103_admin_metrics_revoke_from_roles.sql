-- Intent: SECURITY FIX — revoke EXECUTE on the admin founder_metrics_* functions from anon + authenticated DIRECTLY (not just PUBLIC).
-- Destructive?: no   -- revokes an over-broad grant; no data change
-- Rollback strategy: inline   -- re-grant (commented at file end) — but DO NOT roll back, this closes a leak
-- Linked diagnose-doc: a9d3f1

-- 103_admin_metrics_revoke_from_roles.sql
--
-- WHY (caught by the migration-101 post-apply privilege check, 2026-07-13):
--   Migration 101 created public.founder_metrics_{for_admin_api,engagement,ops}()
--   with `REVOKE ALL FROM PUBLIC` + `GRANT service_role`, mirroring migration
--   093. But 093's function lives in the `private` schema, which PostgREST never
--   exposes — its protection was schema-invisibility, NOT the revoke. These
--   functions live in `public` (they HAVE to, to be `.rpc()`-callable), and
--   Supabase's platform-level default privileges GRANT EXECUTE on every new
--   public-schema function DIRECTLY to `anon` + `authenticated` (proacl showed
--   `anon=X/postgres, authenticated=X/postgres` — a direct grant, not via
--   PUBLIC). So `REVOKE ... FROM PUBLIC` was a NO-OP for those two roles, and
--   because the functions are SECURITY DEFINER (they bypass RLS to count across
--   all users), ANY anonymous caller could `.rpc('founder_metrics_ops')` and
--   read live aggregate business metrics. This is the "REVOKE from PUBLIC is not
--   REVOKE from the role" trap (feedback_revoke_from_public_not_role) in its
--   inverse form — here the grant is direct-to-role, so PUBLIC-revoke can't
--   remove it.
--
-- FIX: revoke EXECUTE from anon + authenticated explicitly. End state proacl =
--   {postgres=X, service_role=X} — only the owner + the service role the admin
--   Edge Functions authenticate as. The `admin_metrics_daily` TABLE is NOT
--   touched here: it keeps the anon/authenticated grant like every other table
--   in this DB, protected by RLS-enabled-no-policies (default-deny rows) — RLS
--   is the row gate for tables; the functions needed this because SECURITY
--   DEFINER bypasses RLS.

revoke execute on function public.founder_metrics_for_admin_api() from anon, authenticated;
revoke execute on function public.founder_metrics_engagement()     from anon, authenticated;
revoke execute on function public.founder_metrics_ops()            from anon, authenticated;

-- Post-apply verification (all three anon/authenticated checks must be false):
--   select has_function_privilege('anon','public.founder_metrics_ops()','execute');           -- expect false
--   select has_function_privilege('authenticated','public.founder_metrics_ops()','execute');  -- expect false
--   select has_function_privilege('service_role','public.founder_metrics_ops()','execute');   -- expect true

-- ── Rollback (inline) — DO NOT run; this re-opens the anon leak ──────────────
-- grant execute on function public.founder_metrics_for_admin_api() to anon, authenticated;
-- grant execute on function public.founder_metrics_engagement()     to anon, authenticated;
-- grant execute on function public.founder_metrics_ops()            to anon, authenticated;
