-- Intent: Make public.issue_referral_code() (migration 186) the only writer of referral_codes: drop the client INSERT policy and every client write privilege, keep the own-row SELECT for authenticated
-- Destructive?: no   -- drops one RLS policy and REVOKEs privileges; no row, column or constraint is touched
-- Rollback strategy: inline   -- a commented block at the end of the file re-creates the policy and re-grants the platform-default privileges
-- Linked diagnose-doc: c2e8a4

-- 189_referral_codes_server_only_writes.sql
--
-- WHY. Migration 186 (B2, diagnose c2e8a4) moved code issue to the server: public.issue_referral_code() is SECURITY DEFINER, owned by
-- postgres, and is now the only code that writes referral_codes (client: SupabaseService._issueReferralCode, web build live since
-- main a0a7037c). The table still carries what the old client needed (migration 035): the policy "Users can insert own referral code"
-- and the platform-default table grants. Read live 2026-11-25: relacl {postgres, anon, authenticated, service_role = arwdDxtm/postgres},
-- no column ACLs, owner postgres, RLS on, not forced, policies: SELECT own row, INSERT own row. With them a signed-in client can still
-- INSERT a row with a code of its own choosing (any format, any expiry), which bypasses the server's format, expiry and lock.
--
-- WHAT. (1) DROP the INSERT policy. (2) REVOKE ALL from PUBLIC, anon and authenticated, then GRANT SELECT to authenticated: the client
-- still reads its own row on restore (sync_restore_completeness.dart, `.from('referral_codes')`), and the SELECT policy stays. anon gets
-- nothing (its SELECT policy matched no row: auth.uid() is NULL). (3) A self-check DO block.
--
-- WHO IS UNAFFECTED. service_role (redeem-referral, restore-user-snapshot: both read with a service-role client); postgres, which owns
-- the table and the function: a SECURITY DEFINER body runs as postgres, the owner bypasses RLS while relforcerowsecurity is false, and an
-- owner's privileges do not depend on the grants revoked here. The auth.users foreign key ON DELETE CASCADE runs as the table owner.
-- Read live 2026-11-25: no other function, view or cron job names referral_codes.
--
-- WHO BREAKS (accepted, CLAUDE.md §1: every account is a testing account). A client older than main a0a7037c (AAB +50 and older, and a
-- browser tab or service worker still on the old web build) cannot create a FIRST code: its INSERT gets 42501. Existing codes are read
-- as before. REGENERATE was already broken on those builds (the bug 186 fixed).
--
-- SELF-CHECK. A REVOKE removes only privileges granted by the revoking role; read live, every grantor is postgres. The DO block checks the
-- resulting state and RAISES if anything is off. Under a transaction-wrapped apply (apply_migration) that rolls the whole migration back.
-- MAINTAIN is a PostgreSQL 17 privilege (live 17.6): on an older server the check fails CLOSED with "unrecognized privilege type".
--
-- IDEMPOTENT: DROP POLICY IF EXISTS, REVOKE/GRANT converge. The DDL is bounded by a 3-second lock_timeout.

SET lock_timeout = '3s';

DROP POLICY IF EXISTS "Users can insert own referral code" ON public.referral_codes;

REVOKE ALL ON public.referral_codes FROM PUBLIC;
REVOKE ALL ON public.referral_codes FROM anon, authenticated;
GRANT SELECT ON public.referral_codes TO authenticated;

DO $selfcheck$
DECLARE
  v_priv text;
  v_bad  text := '';
BEGIN
  -- anon: nothing at all
  FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'] LOOP
    IF has_table_privilege('anon', 'public.referral_codes', v_priv) THEN
      v_bad := v_bad || format(' anon holds %s;', v_priv);
    END IF;
  END LOOP;
  IF has_any_column_privilege('anon', 'public.referral_codes', 'SELECT,INSERT,UPDATE,REFERENCES') THEN
    v_bad := v_bad || ' anon holds a column privilege;';
  END IF;
  -- authenticated: SELECT only
  FOREACH v_priv IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'] LOOP
    IF has_table_privilege('authenticated', 'public.referral_codes', v_priv) THEN
      v_bad := v_bad || format(' authenticated holds %s;', v_priv);
    END IF;
  END LOOP;
  IF has_any_column_privilege('authenticated', 'public.referral_codes', 'INSERT,UPDATE,REFERENCES') THEN
    v_bad := v_bad || ' authenticated holds a column write privilege;';
  END IF;
  IF NOT has_table_privilege('authenticated', 'public.referral_codes', 'SELECT') THEN
    v_bad := v_bad || ' authenticated lost SELECT (restore reads its own row);';
  END IF;
  -- the owner and service_role keep their rights (the function writes as postgres; redeem-referral and
  -- restore-user-snapshot read as service_role). Effective privileges: postgres inherits anon, authenticated
  -- and service_role (read live 2026-11-25), so its own ACL entry alone does not decide this.
  FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE'] LOOP
    IF NOT has_table_privilege('service_role', 'public.referral_codes', v_priv) THEN
      v_bad := v_bad || format(' service_role lost %s;', v_priv);
    END IF;
    IF NOT has_table_privilege('postgres', 'public.referral_codes', v_priv) THEN
      v_bad := v_bad || format(' postgres lost %s;', v_priv);
    END IF;
  END LOOP;
  -- policies: no write policy of any command, the own-row SELECT policy kept as it was (roles, condition)
  IF EXISTS (
    SELECT 1 FROM pg_policies pp
     WHERE pp.schemaname = 'public' AND pp.tablename = 'referral_codes'
       AND pp.cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
  ) THEN
    v_bad := v_bad || ' a write policy remains on referral_codes;';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies pp
     WHERE pp.schemaname = 'public' AND pp.tablename = 'referral_codes'
       AND pp.policyname = 'Users can read own referral code' AND pp.cmd = 'SELECT'
       AND pp.roles = '{public}'::name[]
       AND pp.qual = '(( SELECT auth.uid() AS uid) = user_id)'
  ) THEN
    v_bad := v_bad || ' the own-row SELECT policy is missing or changed;';
  END IF;
  -- the function must still be able to write: owner postgres, RLS on but not forced, table owned by postgres
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
     WHERE c.oid = 'public.referral_codes'::regclass
       AND c.relrowsecurity AND NOT c.relforcerowsecurity
       AND c.relowner = 'postgres'::regrole
  ) THEN
    v_bad := v_bad || ' referral_codes is not (RLS on, not forced, owner postgres);';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
     WHERE p.oid = 'public.issue_referral_code()'::regprocedure
       AND p.prosecdef AND p.proowner = 'postgres'::regrole
  ) THEN
    v_bad := v_bad || ' issue_referral_code is not SECURITY DEFINER owned by postgres;';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.issue_referral_code()', 'EXECUTE') THEN
    v_bad := v_bad || ' authenticated cannot execute issue_referral_code;';
  END IF;
  IF has_function_privilege('anon', 'public.issue_referral_code()', 'EXECUTE') THEN
    v_bad := v_bad || ' anon can execute issue_referral_code;';
  END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'migration 189 self-check failed:%', v_bad;
  END IF;
END
$selfcheck$;

RESET lock_timeout;

-- Post-apply verification (read-only):
--   SELECT relacl::text FROM pg_class WHERE oid = 'public.referral_codes'::regclass;   -- postgres, service_role = arwdDxtm; authenticated = r
--   SELECT policyname, cmd FROM pg_policies WHERE schemaname = 'public' AND tablename = 'referral_codes';   -- the SELECT policy only
-- The live verify is test/sql/referral_codes_server_only_writes_live_verify.sql (BEGIN ... ROLLBACK).

-- Rollback (inline; commented). Coordination: nothing in the current client writes the table, so a rollback only re-opens the old
-- client path; it is needed only if a pre-a0a7037c client must create a first code again.
--   CREATE POLICY "Users can insert own referral code"
--     ON public.referral_codes FOR INSERT
--     WITH CHECK (((select auth.uid()) = user_id));
--   -- the platform-default grants (read live 2026-11-25: arwdDxtm for anon and authenticated, grantor postgres; m = MAINTAIN, PG17):
--   GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.referral_codes TO anon, authenticated;
