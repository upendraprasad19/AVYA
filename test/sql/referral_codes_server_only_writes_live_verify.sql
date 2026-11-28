-- test/sql/referral_codes_server_only_writes_live_verify.sql
--
-- Behavioural verification of migration 189 (referral_codes: the client may only read its own row;
-- public.issue_referral_code() from migration 186 is the only writer; OI-348 B2 PR C, diagnose c2e8a4).
--
-- WHAT IT PROVES. The client role, run the way PostgREST runs it (SET LOCAL ROLE + the JWT claims),
-- is REFUSED every write by the missing PRIVILEGE (42501 "permission denied for table"), not merely
-- filtered by RLS (an UPDATE or DELETE with no policy matches zero rows and raises nothing, which is
-- the pre-189 state: W2/W3 tell the two apart). anon cannot even read. The own-row read and the
-- function's two write paths (first row, expired row) still work for authenticated.
--
-- HOW IT STAYS HONEST.
--   * ONE DO block that ALWAYS aborts with a VERIFY_RESULTS error, so nothing it writes survives.
--     Fixtures are two real auth.users ids (the FK) that hold NO referral_codes row; fixture rows
--     are written as the table owner.
--   * Run it ALONE against the pre-189 state first: the W cases must FAIL there (that is the hole).
--
-- PRE-APPLY DRY RUN: send the text of supabase/migrations/189_referral_codes_server_only_writes.sql
-- followed by this file as ONE request: the abort rolls the migration back with everything else.
--
-- HOW TO READ THE RESULT. The statement fails with `ERROR: VERIFY_RESULTS` followed by
-- `SUMMARY ok=N fail=M` and one line per case: `<id> <what>  ok` or `<id> <what>  fail <details>`.

DO $v$
DECLARE
  a uuid;
  b uuid;
  v_code text;
  v_exp timestamptz;
  v_n int;
  v_state text;
  v_msg text;
  v_ok int;
  v_fail int;
  v_res text;
  v_acl text;
  v_pol text;
BEGIN
  CREATE TEMP TABLE _vr (ord serial, id text, descr text, ok boolean, note text) ON COMMIT DROP;

  SELECT u.id INTO a FROM auth.users u
   WHERE NOT EXISTS (SELECT 1 FROM public.referral_codes rc WHERE rc.user_id = u.id)
   ORDER BY u.created_at LIMIT 1;
  SELECT u.id INTO b FROM auth.users u
   WHERE NOT EXISTS (SELECT 1 FROM public.referral_codes rc WHERE rc.user_id = u.id)
     AND u.id <> a
   ORDER BY u.created_at LIMIT 1;
  IF a IS NULL OR b IS NULL THEN
    RAISE EXCEPTION 'VERIFY_SETUP: need two auth.users without a referral code';
  END IF;

  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);

  -- W1 the old client's FIRST-code INSERT (own user_id, a code of its own choosing) is refused.
  v_state := NULL; v_msg := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO public.referral_codes (user_id, code, expires_at)
      VALUES (a, 'AVYA-VERIFYW1', now() + interval '365 days');
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('W1', 'authenticated INSERT of its own first row -> permission denied for table',
    v_state = '42501' AND v_msg ILIKE 'permission denied for table%'
      AND NOT EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = a),
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none'));
  DELETE FROM public.referral_codes WHERE user_id = a;   -- pre-189 W1 succeeds; keep the fixtures below valid there too

  -- Fixture rows for A (expired) and B (live), written as the owner.
  INSERT INTO public.referral_codes (user_id, code, expires_at) VALUES (a, 'AVYA-VERIFYA0', now() - interval '1 day');
  INSERT INTO public.referral_codes (user_id, code, expires_at) VALUES (b, 'AVYA-VERIFYB0', now() + interval '3 days');

  -- W2 UPDATE of its own row is refused by privilege (pre-189: no error, zero rows).
  v_state := NULL; v_msg := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    UPDATE public.referral_codes SET expires_at = now() + interval '365 days' WHERE user_id = a;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('W2', 'authenticated UPDATE of its own row -> permission denied for table',
    v_state = '42501' AND v_msg ILIKE 'permission denied for table%',
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none'));

  -- W3 DELETE of its own row is refused by privilege (pre-189: no error, zero rows).
  v_state := NULL; v_msg := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    DELETE FROM public.referral_codes WHERE user_id = a;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('W3', 'authenticated DELETE of its own row -> permission denied for table',
    v_state = '42501' AND v_msg ILIKE 'permission denied for table%'
      AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = a AND code = 'AVYA-VERIFYA0'),
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none'));

  -- W4 the old client's upsert (the pre-186 REGENERATE) is refused by privilege.
  v_state := NULL; v_msg := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO public.referral_codes (user_id, code, expires_at)
      VALUES (a, 'AVYA-VERIFYW4', now() + interval '7 days')
      ON CONFLICT (user_id) DO UPDATE SET code = EXCLUDED.code, expires_at = EXCLUDED.expires_at;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('W4', 'authenticated upsert (old REGENERATE) -> permission denied for table',
    v_state = '42501' AND v_msg ILIKE 'permission denied for table%',
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none'));

  -- R1 authenticated still reads its OWN row and only that (restore path; RLS SELECT policy kept).
  v_state := NULL; v_msg := NULL; v_n := NULL; v_code := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    SELECT count(*), max(rc.code) INTO v_n, v_code FROM public.referral_codes rc;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('R1', 'authenticated SELECT sees exactly its own row',
    v_state IS NULL AND v_n = 1 AND v_code = 'AVYA-VERIFYA0',
    'sqlstate=' || coalesce(v_state, 'none') || ' rows=' || coalesce(v_n::text, 'null') || ' code=' || coalesce(v_code, 'null'));

  -- A1 anon cannot read (claims carry a real sub, so only the missing privilege can refuse).
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'anon')::text, true);
  v_state := NULL; v_msg := NULL;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM 1 FROM public.referral_codes;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('A1', 'anon SELECT -> permission denied for table',
    v_state = '42501' AND v_msg ILIKE 'permission denied for table%',
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none'));

  -- A2 anon cannot insert.
  v_state := NULL; v_msg := NULL;
  BEGIN
    SET LOCAL ROLE anon;
    INSERT INTO public.referral_codes (user_id, code, expires_at) VALUES (a, 'AVYA-VERIFYA2', now() + interval '7 days');
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('A2', 'anon INSERT -> permission denied for table',
    v_state = '42501' AND v_msg ILIKE 'permission denied for table%',
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none'));

  -- F1 the function still renews an EXPIRED row for authenticated (write path through the owner).
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_state := NULL; v_msg := NULL; v_code := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    SELECT out_code, out_expires_at INTO v_code, v_exp FROM public.issue_referral_code();
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('F1', 'issue_referral_code() as authenticated renews an expired row',
    v_state IS NULL AND v_code ~ '^AVYA-[A-Z0-9]{8}$' AND v_code <> 'AVYA-VERIFYA0' AND v_exp = now() + interval '7 days'
      AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = a AND code = v_code AND expires_at = v_exp),
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none') || ' code=' || coalesce(v_code, 'null'));

  -- F2 the function still creates a FIRST row (A's row deleted as owner) and leaves B's row alone.
  DELETE FROM public.referral_codes WHERE user_id = a;
  v_state := NULL; v_msg := NULL; v_code := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    SELECT out_code INTO v_code FROM public.issue_referral_code();
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE; v_msg := SQLERRM;
  END;
  RESET ROLE;
  SELECT count(*) INTO v_n FROM public.referral_codes WHERE user_id = a;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('F2', 'issue_referral_code() as authenticated creates a first row; B untouched',
    v_state IS NULL AND v_code ~ '^AVYA-[A-Z0-9]{8}$' AND v_n = 1
      AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = b AND code = 'AVYA-VERIFYB0'),
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none') || ' rows=' || v_n);

  -- C1 catalog: the exact table ACL, no column ACLs.
  SELECT c.relacl::text INTO v_acl FROM pg_class c WHERE c.oid = 'public.referral_codes'::regclass;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('C1', 'relacl = postgres/service_role arwdDxtm, authenticated r; no column ACL',
    v_acl = '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}'
      AND NOT EXISTS (SELECT 1 FROM pg_attribute at WHERE at.attrelid = 'public.referral_codes'::regclass AND at.attacl IS NOT NULL),
    'relacl=' || coalesce(v_acl, 'null'));

  -- C2 policies: exactly the own-row SELECT policy.
  SELECT string_agg(pp.policyname || ':' || pp.cmd, ' | ' ORDER BY pp.policyname) INTO v_pol
    FROM pg_policies pp WHERE pp.schemaname = 'public' AND pp.tablename = 'referral_codes';
  INSERT INTO _vr (id, descr, ok, note) VALUES ('C2', 'policies = only "Users can read own referral code" (SELECT)',
    v_pol = 'Users can read own referral code:SELECT', 'policies=' || coalesce(v_pol, 'none'));

  -- C3 the privileges a plain DML test cannot reach without side effects.
  INSERT INTO _vr (id, descr, ok, note) VALUES ('C3', 'TRUNCATE/REFERENCES/TRIGGER/MAINTAIN false for anon and authenticated',
    NOT has_table_privilege('anon', 'public.referral_codes', 'TRUNCATE')
      AND NOT has_table_privilege('authenticated', 'public.referral_codes', 'TRUNCATE')
      AND NOT has_table_privilege('anon', 'public.referral_codes', 'REFERENCES')
      AND NOT has_table_privilege('authenticated', 'public.referral_codes', 'REFERENCES')
      AND NOT has_table_privilege('anon', 'public.referral_codes', 'TRIGGER')
      AND NOT has_table_privilege('authenticated', 'public.referral_codes', 'TRIGGER')
      AND NOT has_table_privilege('anon', 'public.referral_codes', 'MAINTAIN')
      AND NOT has_table_privilege('authenticated', 'public.referral_codes', 'MAINTAIN'), '');

  SELECT count(*) FILTER (WHERE ok), count(*) FILTER (WHERE ok IS NOT TRUE) INTO v_ok, v_fail FROM _vr;
  SELECT string_agg(id || ' ' || descr || '  ' || CASE WHEN ok IS TRUE THEN 'ok' ELSE 'fail ' || note END, E'\n' ORDER BY ord)
    INTO v_res FROM _vr;
  RAISE EXCEPTION 'VERIFY_RESULTS%', E'\nSUMMARY ok=' || v_ok || ' fail=' || v_fail || E'\n' || v_res;
END
$v$;
