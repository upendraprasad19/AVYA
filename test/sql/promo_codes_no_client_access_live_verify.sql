-- test/sql/promo_codes_no_client_access_live_verify.sql
--
-- Live-Postgres verification of migration 163 (promo_codes_server_only_access; OI-406, diagnose a6c2e9,
-- plan docs/plans/2026-10-24-payment-hardening.md section 3 U4).
--
-- WHAT IT PROVES. test/contracts/promo_codes_server_only_writer_to_reader_test.dart proves the migration TEXT. This
-- file proves, on the live catalog, that (a) the anon and authenticated roles are refused a read of
-- public.promo_codes with the TABLE's 42501 (not a refused role switch), (b) neither role holds any table
-- privilege, directly, through PUBLIC, through role membership or per column, (c) the table has no policy and
-- RLS is still enabled, (d) nothing else exposes the rows (a definer-rights function a client can call, a
-- publication, a view), and (e) service_role really reads every row under RLS (BYPASSRLS) and keeps SELECT and
-- UPDATE, as does postgres (the positive control: the payment Edge Functions read through the service role).
--
-- SHAPE. ONE `DO` block that ALWAYS aborts with `RAISE EXCEPTION 'VERIFY_RESULTS ...'` (the shape of
-- test/sql/progress_photos_pro_insert_rule_live_verify.sql), one statement with no explicit BEGIN, so on the
-- abort Postgres rolls the whole statement back and nothing is left open or locked. It is READ-ONLY: the only
-- statements executed are SELECTs and catalog reads; write privileges are read from the catalog, never tried.
-- Each role-switched read sits in its own nested BEGIN ... EXCEPTION block that always ends in an exception, so
-- the subtransaction always rolls back and the role is always restored (PL/pgSQL variables keep their values).
-- The rehearsal of the migration is test/sql/promo_codes_server_only_rehearsal.sql: this same block with the
-- two migration statements run first, inside it (pinned equal by the contract test).
--
-- HOW TO READ IT. Run through execute_sql; the error text carries one line per case, `<id>=ok` or
-- `<id>=fail (<details>)`, after a `SUMMARY ok=N fail=M` line. After the apply every case must read `ok`
-- (16 lines). BEFORE the apply (the CLAUDE.md 4.9 check that a new test is run against what it replaces)
-- P1, P2, P3, P4, P5 and P14 read `fail` (the policy and the grants are still there) and the other 10 read `ok`.

DO $v$
DECLARE
  v_results text := '';
  v_ok      int  := 0;
  v_fail    int  := 0;
  v_state   text;
  v_msg     text;
  v_n       bigint;
  v_n0      bigint;
  v_txt     text;
  v_rel     oid  := 'public.promo_codes'::regclass;
  v_role    text;
  v_case    text;
BEGIN
  -- P0 positive control: postgres (the caller) reads the table; the count is kept for P13, not printed.
  BEGIN
    SELECT count(*) INTO v_n0 FROM public.promo_codes;
    v_results := v_results || E'P0=ok\n'; v_ok := v_ok + 1;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'P0=fail (postgres cannot read: ' || v_state || ' ' || v_msg || E')\n'; v_fail := v_fail + 1;
  END;

  -- P1 anon, P2 authenticated: the read is refused by the TABLE's privilege check. A refused role switch is
  -- also 42501 ("permission denied to set role"), so the message is checked too.
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    v_case := CASE v_role WHEN 'anon' THEN 'P1' ELSE 'P2' END;
    BEGIN
      EXECUTE format('SET LOCAL ROLE %I', v_role);
      SELECT count(*) INTO v_n FROM public.promo_codes;
      RAISE EXCEPTION 'VERIFY_UNEXPECTED_OK %', v_n;
    EXCEPTION
      WHEN insufficient_privilege THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg LIKE 'permission denied for table promo_codes%' THEN
          v_results := v_results || v_case || E'=ok\n'; v_ok := v_ok + 1;
        ELSE
          v_results := v_results || v_case || '=fail (' || v_role || ' refused for another reason: ' || v_msg || E')\n'; v_fail := v_fail + 1;
        END IF;
      WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
        v_results := v_results || v_case || '=fail (' || v_role || ' read: ' || v_state || ' ' || v_msg || E')\n'; v_fail := v_fail + 1;
    END;
  END LOOP;

  -- P3 no table-level ACL entry for PUBLIC (grantee 0), anon or authenticated, any privilege, any grantor.
  SELECT string_agg(e, ',' ORDER BY e) INTO v_txt
    FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END
                 || ':' || a.privilege_type || '/' || a.grantor::regrole::text AS e
            FROM pg_class c, aclexplode(c.relacl) a
           WHERE c.oid = v_rel
             AND (a.grantee = 0 OR a.grantee IN ('anon'::regrole, 'authenticated'::regrole))) x;
  IF v_txt IS NULL THEN
    v_results := v_results || E'P3=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || 'P3=fail (table grants left: ' || v_txt || E')\n'; v_fail := v_fail + 1;
  END IF;

  -- P4 no column-level grant either, and has_any_column_privilege is false for both roles.
  SELECT string_agg(e, ',' ORDER BY e) INTO v_txt
    FROM (SELECT att.attname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END
                 || ':' || a.privilege_type AS e
            FROM pg_attribute att, aclexplode(att.attacl) a
           WHERE att.attrelid = v_rel AND att.attnum > 0 AND NOT att.attisdropped
             AND (a.grantee = 0 OR a.grantee IN ('anon'::regrole, 'authenticated'::regrole))) x;
  IF v_txt IS NULL
     AND NOT has_any_column_privilege('anon', v_rel, 'SELECT,INSERT,UPDATE,REFERENCES')
     AND NOT has_any_column_privilege('authenticated', v_rel, 'SELECT,INSERT,UPDATE,REFERENCES') THEN
    v_results := v_results || E'P4=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || 'P4=fail (column grants: ' || coalesce(v_txt, 'none listed') || '; anon any-column '
      || has_any_column_privilege('anon', v_rel, 'SELECT,INSERT,UPDATE,REFERENCES')::text || ', authenticated any-column '
      || has_any_column_privilege('authenticated', v_rel, 'SELECT,INSERT,UPDATE,REFERENCES')::text || E')\n';
    v_fail := v_fail + 1;
  END IF;

  -- P5 the table has no policy at all.
  SELECT string_agg(policyname, ',' ORDER BY policyname) INTO v_txt
    FROM pg_policies WHERE schemaname = 'public' AND tablename = 'promo_codes';
  IF v_txt IS NULL THEN
    v_results := v_results || E'P5=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || 'P5=fail (policies left: ' || v_txt || E')\n'; v_fail := v_fail + 1;
  END IF;

  -- P6 RLS is still enabled (the migration must not have turned it off).
  IF (SELECT relrowsecurity FROM pg_class WHERE oid = v_rel) THEN
    v_results := v_results || E'P6=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || E'P6=fail (row level security is disabled on promo_codes)\n'; v_fail := v_fail + 1;
  END IF;

  -- P7 the definer-rights counter cannot be called by the client roles (closed by migrations 090/091).
  IF NOT has_function_privilege('anon', 'public.increment_promo_used_count(text)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.increment_promo_used_count(text)', 'EXECUTE') THEN
    v_results := v_results || E'P7=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || E'P7=fail (anon or authenticated can EXECUTE increment_promo_used_count)\n'; v_fail := v_fail + 1;
  END IF;

  -- P8 no publication carries the table (Realtime would stream rows past the grants).
  SELECT string_agg(pubname, ',' ORDER BY pubname) INTO v_txt
    FROM pg_publication_tables WHERE schemaname = 'public' AND tablename = 'promo_codes';
  IF v_txt IS NULL THEN
    v_results := v_results || E'P8=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || 'P8=fail (publications: ' || v_txt || E')\n'; v_fail := v_fail + 1;
  END IF;

  -- P9 no view or materialized view is built on the table (a view runs with its owner's rights).
  SELECT string_agg(DISTINCT r.ev_class::regclass::text, ',') INTO v_txt
    FROM pg_depend d JOIN pg_rewrite r ON r.oid = d.objid
   WHERE d.classid = 'pg_rewrite'::regclass AND d.refclassid = 'pg_class'::regclass
     AND d.refobjid = v_rel AND r.ev_class <> v_rel;
  IF v_txt IS NULL THEN
    v_results := v_results || E'P9=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || 'P9=fail (views on promo_codes: ' || v_txt || E')\n'; v_fail := v_fail + 1;
  END IF;

  -- P10 service_role keeps SELECT and UPDATE (the payment Edge Functions read and count through it).
  IF has_table_privilege('service_role', v_rel, 'SELECT') AND has_table_privilege('service_role', v_rel, 'UPDATE') THEN
    v_results := v_results || E'P10=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || E'P10=fail (service_role lost SELECT or UPDATE)\n'; v_fail := v_fail + 1;
  END IF;

  -- P11 postgres keeps SELECT and UPDATE.
  IF has_table_privilege('postgres', v_rel, 'SELECT') AND has_table_privilege('postgres', v_rel, 'UPDATE') THEN
    v_results := v_results || E'P11=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || E'P11=fail (postgres lost SELECT or UPDATE)\n'; v_fail := v_fail + 1;
  END IF;

  -- P12 promo_code_uses is untouched by this migration: its own-rows SELECT policy is still there.
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'promo_code_uses'
                AND policyname = 'Users can see own promo uses') THEN
    v_results := v_results || E'P12=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || E'P12=fail (the promo_code_uses policy is gone)\n'; v_fail := v_fail + 1;
  END IF;

  -- P13 service_role really reads EVERY row with RLS on and no policy (it has BYPASSRLS); vacuous on an empty table.
  v_n := NULL;
  BEGIN
    SET LOCAL ROLE service_role;
    SELECT count(*) INTO v_n FROM public.promo_codes;
    RAISE EXCEPTION 'VERIFY_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_msg = 'VERIFY_ROLLBACK' AND v_n0 > 0 AND v_n = v_n0
     AND (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'service_role') THEN
    v_results := v_results || E'P13=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || 'P13=fail (service_role read ' || coalesce(v_n::text, 'nothing') || ' of ' || coalesce(v_n0::text, '?')
      || ' rows; ' || v_state || ' ' || v_msg || E')\n'; v_fail := v_fail + 1;
  END IF;

  -- P14 neither client role holds ANY table privilege, by any route (direct, PUBLIC or role membership).
  IF NOT has_table_privilege('anon', v_rel, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
     AND NOT has_table_privilege('authenticated', v_rel, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN') THEN
    v_results := v_results || E'P14=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || E'P14=fail (anon or authenticated still holds a privilege on promo_codes)\n'; v_fail := v_fail + 1;
  END IF;

  -- P15 no definer-rights function that names promo_codes can be called by a client role (it would read past the grants).
  SELECT string_agg(p.oid::regprocedure::text, ',' ORDER BY p.oid::regprocedure::text) INTO v_txt
    FROM pg_proc p
   WHERE p.prosecdef AND p.prosrc ILIKE '%promo_codes%'
     AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF v_txt IS NULL THEN
    v_results := v_results || E'P15=ok\n'; v_ok := v_ok + 1;
  ELSE
    v_results := v_results || 'P15=fail (client-callable definer functions: ' || v_txt || E')\n'; v_fail := v_fail + 1;
  END IF;

  RAISE EXCEPTION 'VERIFY_RESULTS%', E'\nSUMMARY ok=' || v_ok || ' fail=' || v_fail || E'\n' || v_results;
END
$v$;
