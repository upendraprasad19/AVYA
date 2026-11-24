-- test/sql/referral_code_issue_live_verify.sql
--
-- Behavioural verification of migration 186 (public.issue_referral_code(), OI-348 B2, diagnose
-- c2e8a4). Plan: docs/plans/oi348-walk-fixes-landing2.md, Unit B2.
--
-- WHAT IT PROVES. The Dart pin (test/contracts/issue_referral_code_function_pin_test.dart) proves
-- the migration TEXT. This file calls the REAL function as the client role (SET LOCAL ROLE
-- authenticated + the JWT claims, the way PostgREST runs it) and reads the rows it wrote.
-- What it CANNOT show (one session): two calls racing, and an old-client INSERT landing between
-- the expiry check and the upsert (the DO UPDATE ... WHERE expires_at <= now() guard). Those need two
-- sessions; both are pinned by the Dart test, and the race runs live after the apply (diagnose
-- doc, concurrency_note).
--
-- HOW IT STAYS HONEST.
--   * ONE DO block that ALWAYS aborts with a VERIFY_RESULTS error, so nothing it writes survives.
--     Fixtures are two real auth.users ids (the FK) chosen because they hold NO referral_codes row.
--   * now() is frozen inside the transaction, so "expires exactly now" is exact.
--   * B0 runs the OLD client write (the upsert) first, against the pre-M2 table: it must fail with
--     42501. That is the bug; after M2 (PR C) the client role cannot write the table at all.
--
-- PRE-APPLY DRY RUN: send the text of supabase/migrations/186_issue_referral_code.sql followed by
-- this file as ONE request: the abort rolls the function back with everything else.
--
-- HOW TO READ THE RESULT. The statement fails with `ERROR: VERIFY_RESULTS` followed by
-- `SUMMARY ok=N fail=M` and one line per case: `<id> <what>  ok` or `<id> <what>  fail <details>`.

DO $v$
DECLARE
  a uuid;
  b uuid;
  v_code text;
  v_code2 text;
  v_exp timestamptz;
  v_exp2 timestamptz;
  v_n int;
  v_state text;
  v_ok int;
  v_fail int;
  v_res text;
  v_cfg text[];
  v_def boolean;
  v_owner text;
  v_msg text;
  v_calls int;
  v_codeA text;
  v_expA timestamptz;
  v_uniq text;
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

  -- B0 (the bug, pre-M2): the old client upsert on an existing row is refused (no UPDATE policy).
  INSERT INTO public.referral_codes (user_id, code, expires_at)
    VALUES (a, 'AVYA-VERIFYB0', now() - interval '1 day');
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  v_state := NULL;
  v_msg := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO public.referral_codes (user_id, code, expires_at)
      VALUES (a, 'AVYA-VERIFYB1', now() + interval '7 days')
      ON CONFLICT (user_id) DO UPDATE SET code = EXCLUDED.code, expires_at = EXCLUDED.expires_at;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('B0', 'old client upsert on an existing row is refused by RLS (42501, the bug)',
    v_state = '42501' AND v_msg ILIKE '%row-level security%',
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none'));
  DELETE FROM public.referral_codes WHERE user_id = a;

  -- B0c control: the same role CAN insert a first row (so B0's refusal is the missing UPDATE path).
  v_state := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    INSERT INTO public.referral_codes (user_id, code, expires_at)
      VALUES (a, 'AVYA-VERIFYB2', now() + interval '7 days');
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('B0c', 'control: a first-row INSERT as authenticated succeeds (pre-M2)',
    v_state IS NULL AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = a AND code = 'AVYA-VERIFYB2'),
    'sqlstate=' || coalesce(v_state, 'none'));
  DELETE FROM public.referral_codes WHERE user_id = a;

  -- V1 none -> created, the right shape, +7 days, one row.
  SET LOCAL ROLE authenticated;
  SELECT out_code, out_expires_at INTO v_code, v_exp FROM public.issue_referral_code();
  RESET ROLE;
  SELECT count(*) INTO v_n FROM public.referral_codes WHERE user_id = a;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('V1', 'no row -> a new code, AVYA-[A-Z0-9]{8}, +7 days, one row',
    v_code ~ '^AVYA-[A-Z0-9]{8}$' AND v_exp = now() + interval '7 days' AND v_n = 1
      AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = a AND code = v_code AND expires_at = v_exp),
    'code=' || coalesce(v_code, 'null') || ' exp=' || coalesce(v_exp::text, 'null') || ' rows=' || v_n);

  -- V2 a live code is returned unchanged: one row from the call, and the table row is untouched
  -- (a missing RETURN after the early RETURN QUERY would add a second row and overwrite the table).
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_calls FROM public.issue_referral_code();
  SELECT out_code, out_expires_at INTO v_code2, v_exp2 FROM public.issue_referral_code();
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('V2', 'live code -> returned unchanged, one row, table untouched',
    v_calls = 1 AND v_code2 = v_code AND v_exp2 = v_exp
      AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = a AND code = v_code AND expires_at = v_exp),
    'calls=' || v_calls || ' second=' || coalesce(v_code2, 'null'));

  -- V3 an expired code -> a NEW code, +7 days, one row returned, still one table row.
  UPDATE public.referral_codes SET code = 'AVYA-VERIFYX3', expires_at = now() - interval '1 day' WHERE user_id = a;
  SET LOCAL ROLE authenticated;
  SELECT count(*), max(out_code) INTO v_calls, v_msg FROM public.issue_referral_code();
  RESET ROLE;
  SELECT rc.code, rc.expires_at INTO v_code2, v_exp2 FROM public.referral_codes rc WHERE rc.user_id = a;
  SELECT count(*) INTO v_n FROM public.referral_codes WHERE user_id = a;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('V3', 'expired -> a new code, +7 days, one row returned, one row stored',
    v_calls = 1 AND v_msg = v_code2 AND v_code2 <> 'AVYA-VERIFYX3' AND v_code2 ~ '^AVYA-[A-Z0-9]{8}$' AND v_exp2 = now() + interval '7 days' AND v_n = 1,
    'calls=' || v_calls || ' code=' || coalesce(v_code2, 'null') || ' rows=' || v_n);

  -- V4 expiry exactly now() counts as expired.
  UPDATE public.referral_codes SET code = 'AVYA-VERIFYX4', expires_at = now() WHERE user_id = a;
  SET LOCAL ROLE authenticated;
  SELECT count(*), max(out_code) INTO v_calls, v_msg FROM public.issue_referral_code();
  RESET ROLE;
  SELECT rc.code INTO v_code2 FROM public.referral_codes rc WHERE rc.user_id = a;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('V4', 'expires_at = now() -> treated as expired, one row returned',
    v_calls = 1 AND v_msg = v_code2 AND v_code2 <> 'AVYA-VERIFYX4', 'calls=' || v_calls || ' code=' || coalesce(v_code2, 'null'));

  -- V5 A's call on A's EXPIRED row (the write path) leaves B's expired row as it was.
  UPDATE public.referral_codes SET code = 'AVYA-VERIFYX5', expires_at = now() - interval '1 day' WHERE user_id = a;
  INSERT INTO public.referral_codes (user_id, code, expires_at) VALUES (b, 'AVYA-VERIFYB5', now() - interval '1 day');
  SET LOCAL ROLE authenticated;
  SELECT out_code INTO v_code2 FROM public.issue_referral_code();
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('V5', 'A''s write-path call renews A and leaves B''s (expired) row as it was',
    v_code2 <> 'AVYA-VERIFYX5'
      AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = a AND code = v_code2)
      AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = b AND code = 'AVYA-VERIFYB5' AND expires_at = now() - interval '1 day'),
    'a_code=' || coalesce(v_code2, 'null'));

  -- V6 B's own call replaces B's row (the claims decide whose row) and leaves A's row as it was.
  SELECT rc.code, rc.expires_at INTO v_codeA, v_expA FROM public.referral_codes rc WHERE rc.user_id = a;
  PERFORM set_config('request.jwt.claim.sub', b::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*), max(out_code) INTO v_calls, v_msg FROM public.issue_referral_code();
  RESET ROLE;
  SELECT rc.code INTO v_code2 FROM public.referral_codes rc WHERE rc.user_id = b;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('V6', 'B''s call replaces only B''s row; A''s row unchanged',
    v_calls = 1 AND v_msg = v_code2 AND v_code2 <> 'AVYA-VERIFYB5' AND v_code2 ~ '^AVYA-[A-Z0-9]{8}$'
      AND EXISTS (SELECT 1 FROM public.referral_codes WHERE user_id = a AND code = v_codeA AND expires_at = v_expA),
    'calls=' || v_calls || ' b_code=' || coalesce(v_code2, 'null'));

  -- V7 claims with no sub -> raises 42501, writes nothing.
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
  v_state := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM * FROM public.issue_referral_code();
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('V7', 'no sub in the claims -> 42501',
    v_state = '42501', 'sqlstate=' || coalesce(v_state, 'none'));

  -- V8 anon cannot execute it. The claims carry a real sub, so the function's own null-uid guard
  -- cannot be what refuses: only the missing EXECUTE privilege can.
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'anon')::text, true);
  v_state := NULL;
  v_msg := NULL;
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM * FROM public.issue_referral_code();
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN
    v_state := SQLSTATE;
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('V8', 'SET ROLE anon (claims with a sub) -> permission denied for function',
    v_state = '42501' AND v_msg ILIKE 'permission denied for function%',
    'sqlstate=' || coalesce(v_state, 'none') || ' msg=' || coalesce(v_msg, 'none'));

  -- C1 catalog: privileges, security mode, search_path, owner.
  INSERT INTO _vr (id, descr, ok, note) VALUES ('C1', 'EXECUTE: anon false, authenticated true, public false',
    NOT has_function_privilege('anon', 'public.issue_referral_code()', 'execute')
      AND has_function_privilege('authenticated', 'public.issue_referral_code()', 'execute')
      AND NOT EXISTS (
        SELECT 1 FROM pg_proc p, aclexplode(p.proacl) x
         WHERE p.oid = 'public.issue_referral_code()'::regprocedure AND x.grantee = 0),
    'grantees=' || coalesce((
      SELECT string_agg(CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE x.grantee::regrole::text END, ',' ORDER BY x.grantee::regrole::text)
        FROM pg_proc p, aclexplode(p.proacl) x
       WHERE p.oid = 'public.issue_referral_code()'::regprocedure), 'default'));
  SELECT p.prosecdef, p.proconfig, p.proowner::regrole::text INTO v_def, v_cfg, v_owner
    FROM pg_proc p WHERE p.oid = 'public.issue_referral_code()'::regprocedure;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('C2', 'SECURITY DEFINER, search_path="", owner postgres',
    v_def AND v_cfg = ARRAY['search_path=""'] AND v_owner = 'postgres',
    'def=' || v_def || ' cfg=' || coalesce(v_cfg::text, 'null') || ' owner=' || v_owner);

  -- C3 the unique indexes the retry relies on: a code clash must report referral_codes_code_key
  -- (any other unique index on code would make the retry re-raise instead of retrying).
  -- Compared by full index definition, so an expression index (lower(code)) or a partial one counts too.
  SELECT string_agg(pg_get_indexdef(i.indexrelid), ' | ' ORDER BY pg_get_indexdef(i.indexrelid))
    INTO v_uniq
    FROM pg_index i
   WHERE i.indrelid = 'public.referral_codes'::regclass AND i.indisunique;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('C3', 'unique indexes are exactly pkey(id), code_key(code), user_id_key(user_id)',
    v_uniq = 'CREATE UNIQUE INDEX referral_codes_code_key ON public.referral_codes USING btree (code)'
      || ' | CREATE UNIQUE INDEX referral_codes_pkey ON public.referral_codes USING btree (id)'
      || ' | CREATE UNIQUE INDEX referral_codes_user_id_key ON public.referral_codes USING btree (user_id)',
    'unique=' || coalesce(v_uniq, 'null'));

  -- C4 the random source the mint path calls exists where the function names it.
  INSERT INTO _vr (id, descr, ok, note) VALUES ('C4', 'extensions.gen_random_bytes(integer) exists',
    to_regprocedure('extensions.gen_random_bytes(integer)') IS NOT NULL, '');

  SELECT count(*) FILTER (WHERE ok), count(*) FILTER (WHERE ok IS NOT TRUE) INTO v_ok, v_fail FROM _vr;
  SELECT string_agg(id || ' ' || descr || '  ' || CASE WHEN ok IS TRUE THEN 'ok' ELSE 'fail ' || note END, E'\n' ORDER BY ord)
    INTO v_res FROM _vr;
  RAISE EXCEPTION 'VERIFY_RESULTS%', E'\nSUMMARY ok=' || v_ok || ' fail=' || v_fail || E'\n' || v_res;
END
$v$;
