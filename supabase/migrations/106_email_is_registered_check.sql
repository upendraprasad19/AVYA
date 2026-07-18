-- Intent: Add public.email_is_registered(text) — pre-auth SECURITY DEFINER boolean check backing the email-first sign-in flow (type email → auto-branch to sign-in or sign-up) + a supporting lower(email) functional index.
-- Destructive?: no   -- new function + new index only; no existing rows or columns touched
-- Rollback strategy: inline   -- reverse DDL commented at end
-- Linked diagnose-doc: n/a   -- feature (email-first sign-in simplification), not a bug fix
--
-- SECURITY DEFINER required — public.users RLS is owner-only (auth.uid() =
-- id, see 001_create_users.sql) and there's no auth.uid() yet pre-signin, so
-- a SECURITY INVOKER read would always see zero rows regardless of whether
-- the email exists. Returns ONLY a boolean, nothing else.
--
-- INTENTIONAL anon grant: every prior SECURITY DEFINER hardening migration in
-- this project (053, 090, 091, 103) REVOKES anon execute; this is the
-- deliberate exception, because the caller isn't authenticated yet. Do not
-- "fix" this in a future audit without reading this comment first.
--
-- This codebase's own migration history disagrees with itself on WHY anon
-- can execute a public-schema function: 090/091 (2026-06-11) concluded
-- EXECUTE reaches anon via PUBLIC inheritance (revoke-from-PUBLIC was the
-- real fix); 103 (2026-07-13, diagnose a9d3f1) concluded Supabase grants
-- EXECUTE directly to anon on newly-created functions, making a
-- revoke-from-PUBLIC a no-op. Doing both revoke+grant below reaches the
-- correct end state either way — the has_function_privilege() check at the
-- bottom is what actually matters, not the theory. See
-- feedback_revoke_from_public_not_role.md.
--
-- Not a new enumeration oracle: AuthNotifier.signUpWithEmail already reveals
-- registration status after a failed sign-up attempt (identities-empty
-- branch, auth_provider.dart) — this just makes that existing information
-- cheaper to query. Ships without bespoke rate-limiting (no precedent for
-- limiting a pre-auth anon RPC in this codebase, and no stable pre-auth
-- identity to key a limiter on without moving this to an Edge Function).

create or replace function public.email_is_registered(p_email text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.users
    where lower(email) = lower(trim(p_email))
  );
$$;

revoke all on function public.email_is_registered(text) from public;
grant execute on function public.email_is_registered(text) to anon, authenticated;

-- No functional index exists on lower(email) today — the unique btree on raw
-- `email` (001_create_users.sql) can't serve this predicate. Add one so the
-- anon-callable query isn't an unindexed scan, especially since this
-- function intentionally ships without rate-limiting.
create index if not exists idx_users_email_lower on public.users (lower(email));

-- Post-apply verification (must be true):
--   select has_function_privilege('anon', 'public.email_is_registered(text)', 'execute');

-- Rollback (commented — reverse DDL):
--   drop index if exists idx_users_email_lower;
--   drop function if exists public.email_is_registered(text);
