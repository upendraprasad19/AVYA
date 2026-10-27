-- test/sql/exercise_media_bucket_live_verify.sql
--
-- Live-Postgres verification of the exercise-media bucket migration (Batch M1, diagnose b4e7a2, plan
-- docs/plans/2026-10-27-library-batch-m1-media-data.md R7 and R15). FILE 1 of two: the other is
-- test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql (rehearsal only).
--
-- WHAT IT PROVES, at the database-role level. test/contracts/exercise_media_bucket_private_test.dart proves the
-- migration TEXT. This file proves, on the live catalog and with the real roles, that
--   (a) the bucket row is private, 1,500,000 bytes, image/webp only;
--   (b) the one read policy is FOR SELECT TO authenticated and its deparsed predicate names the bucket and
--       is_anonymous (catalog FIELDS, not source text: pg_policies.qual is the deparsed expression);
--   (c) no other policy lets anon or PUBLIC read this bucket and no policy of storage.objects grants a write to
--       anon, authenticated or PUBLIC without a bucket predicate;
--   (d) the role probe: a fake object of this bucket is read by an authenticated non-anonymous session (1), not by
--       the anon role (0), not by an anonymous-sign-in session (0), and a fake object of ANOTHER private bucket
--       is not read by the same session (0); an INSERT by that session is refused, an UPDATE and a DELETE
--       affect 0 rows.
-- What it does NOT prove: that Storage maps an anon-key JWT to the role anon and an anonymous sign-in to
-- is_anonymous true (documented behaviour, UNVERIFIED here; Task 9.2 adds one real request with the anon key),
-- and that Auth emits the claim name is_anonymous.
--
-- SHAPE. ONE `DO` block that ALWAYS aborts with `RAISE EXCEPTION 'VERIFY_RESULTS ...'` (the shape of
-- test/sql/promo_codes_no_client_access_live_verify.sql): one statement with no explicit BEGIN, so on the abort
-- Postgres rolls the whole statement back and nothing persists. It has no DDL. Its only writes are the fixture
-- INSERTs of the probe, inserted as postgres (which bypasses RLS) and rolled back with everything else. Each
-- role-switched leg sits in its own nested BEGIN ... EXCEPTION block that always ends in an exception, so the
-- subtransaction rolls back and the role and the claims are restored (PL/pgSQL variables keep their values).
-- Counts are scoped to the fixture's own bucket and name, so a re-run after the upload still counts 1.
--
-- REHEARSAL (Task 8.4, before the apply). The bucket does not exist yet, so the rehearsal sends this block with
-- the migration's DO body (the text between its BEGIN and END, without the DO wrapper) inserted TWICE at the
-- insert-point marker comment below, comments stripped, as ONE call. The in-transaction state is then the post-apply
-- state, and the second body run proves the DO UPDATE and the policy re-creation are idempotent. A normal run
-- (after the apply, and again after the upload) leaves the marker alone.
--
-- HOW TO READ IT. The error text is `VERIFY_RESULTS` and then one key=value per line, in this fixed order:
--   verdict                      PASS only when every line below holds its expected value, else FAIL
--   anon                         expected 0   (SET LOCAL ROLE anon, empty claims)
--   authenticated                expected 1   (claims {"sub": <uuid>, "role": "authenticated", "is_anonymous": false})
--   anon_session                 expected 0   (the same claims with "is_anonymous": true)
--   other_bucket                 expected 0   (a fake row of coach-media under a folder no policy admits)
--   write_insert                 expected refused  (42501 "new row violates row-level security policy")
--   write_update                 expected 0   (rows affected)
--   write_delete                 expected 0   (rows affected)
--   anon_select_priv             expected true (has_table_privilege anon SELECT on storage.objects; false is a STOP,
--                                              because then the TO public variant could not redden)
--   bucket_public                expected false
--   bucket_limit                 expected 1500000
--   bucket_mime                  expected {image/webp}
--   policy_cmd                   expected SELECT
--   policy_roles                 expected {authenticated}
--   policy_qual_has_bucket       expected true
--   policy_qual_has_is_anonymous expected true
--   anon_public_select_policies  expected none (SELECT or ALL policies for anon/public with no bucket predicate or
--                                              one that names exercise-media)
--   unscoped_write_grants        expected none (INSERT/UPDATE/DELETE/ALL policies for anon/authenticated/public with
--                                              no bucket predicate)
--   select_policies              operator reading (truncated): every anon/public/authenticated SELECT or ALL policy
-- A value starting `error:` is a leg that raised something other than its expected refusal: a STOP, read the text.

DO $v$
DECLARE
  v_msg            text;
  v_name           text;
  v_other_name     text;
  v_uid            text;
  v_n              bigint;
  v_anon           text;
  v_auth           text;
  v_anon_session   text;
  v_other          text;
  v_write_insert   text;
  v_write_update   text;
  v_write_delete   text;
  v_anon_priv      boolean;
  v_bucket_public  text;
  v_bucket_limit   text;
  v_bucket_mime    text;
  v_policy_cmd     text;
  v_policy_roles   text;
  v_qual_bucket    text;
  v_qual_anon      text;
  v_anon_public    text;
  v_unscoped_write text;
  v_listing        text;
  v_verdict        text;
BEGIN
  -- PRELUDE-INSERT-POINT (rehearsal only: the migration body goes here, twice; a normal run leaves this comment)

  -- the catalog half: bucket row, the one policy, and the policies that would open the bucket
  SELECT public::text, file_size_limit::text, allowed_mime_types::text
    INTO v_bucket_public, v_bucket_limit, v_bucket_mime
    FROM storage.buckets WHERE id = 'exercise-media';

  SELECT cmd, roles::text, (qual LIKE '%exercise-media%')::text, (qual LIKE '%is_anonymous%')::text
    INTO v_policy_cmd, v_policy_roles, v_qual_bucket, v_qual_anon
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'exercise_media_authenticated_read';

  SELECT coalesce(string_agg(policyname, ',' ORDER BY policyname), 'none') INTO v_anon_public
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND cmd IN ('SELECT', 'ALL')
     AND roles && ARRAY['anon', 'public']::name[]
     AND (qual IS NULL OR qual NOT LIKE '%bucket_id%' OR qual LIKE '%exercise-media%');

  SELECT coalesce(string_agg(policyname, ',' ORDER BY policyname), 'none') INTO v_unscoped_write
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
     AND roles && ARRAY['anon', 'authenticated', 'public']::name[]
     AND (coalesce(qual, '') || coalesce(with_check, '')) NOT LIKE '%bucket_id%';

  SELECT coalesce(left(string_agg(policyname || '|' || cmd || '|' || roles::text, '; ' ORDER BY policyname), 900), 'none')
    INTO v_listing
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND cmd IN ('SELECT', 'ALL')
     AND roles && ARRAY['anon', 'public', 'authenticated']::name[];

  v_anon_priv := has_table_privilege('anon', 'storage.objects', 'SELECT');

  -- PROBE-BEGIN
  v_name := 'probe-' || gen_random_uuid()::text || '.webp';
  v_other_name := '00000000-0000-0000-0000-000000000000/probe-' || gen_random_uuid()::text || '.webp';
  v_uid := gen_random_uuid()::text;

  -- fixtures: one fake object in exercise-media, one in another private bucket (coach-media), inserted as the
  -- caller (postgres bypasses RLS); if that insert is refused, as service_role (BYPASSRLS)
  BEGIN
    INSERT INTO storage.objects (bucket_id, name)
    VALUES ('exercise-media', v_name), ('coach-media', v_other_name);
  EXCEPTION WHEN OTHERS THEN
    SET LOCAL ROLE service_role;
    INSERT INTO storage.objects (bucket_id, name)
    VALUES ('exercise-media', v_name), ('coach-media', v_other_name);
    RESET ROLE;
  END;

  -- leg 1: the anon role, no claims
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM set_config('request.jwt.claims', '', true);
    SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'exercise-media' AND name = v_name;
    v_anon := v_n::text;
    RAISE EXCEPTION 'PROBE_ROLLBACK';
  EXCEPTION
    WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_anon := CASE WHEN v_msg LIKE 'permission denied for table%' THEN '0' ELSE 'error: ' || v_msg END;
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      IF v_msg <> 'PROBE_ROLLBACK' THEN v_anon := 'error: ' || v_msg; END IF;
  END;

  -- leg 2: an authenticated, non-anonymous session reads the exercise-media row
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated', 'is_anonymous', false)::text, true);
    SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'exercise-media' AND name = v_name;
    v_auth := v_n::text;
    RAISE EXCEPTION 'PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PROBE_ROLLBACK' THEN v_auth := 'error: ' || v_msg; END IF;
  END;

  -- leg 3: the same session as an anonymous sign-in
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated', 'is_anonymous', true)::text, true);
    SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'exercise-media' AND name = v_name;
    v_anon_session := v_n::text;
    RAISE EXCEPTION 'PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PROBE_ROLLBACK' THEN v_anon_session := 'error: ' || v_msg; END IF;
  END;

  -- leg 4: the normal session on the row of ANOTHER bucket
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated', 'is_anonymous', false)::text, true);
    SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'coach-media' AND name = v_other_name;
    v_other := v_n::text;
    RAISE EXCEPTION 'PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PROBE_ROLLBACK' THEN v_other := 'error: ' || v_msg; END IF;
  END;

  -- leg 5a: the normal session may not INSERT into the bucket
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated', 'is_anonymous', false)::text, true);
    INSERT INTO storage.objects (bucket_id, name)
    VALUES ('exercise-media', 'probe-write-' || gen_random_uuid()::text || '.webp');
    v_write_insert := 'inserted';
    RAISE EXCEPTION 'PROBE_ROLLBACK';
  EXCEPTION
    WHEN insufficient_privilege THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_write_insert := CASE WHEN v_msg LIKE 'new row violates row-level security policy%' THEN 'refused' ELSE 'error: ' || v_msg END;
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      IF v_msg <> 'PROBE_ROLLBACK' THEN v_write_insert := 'error: ' || v_msg; END IF;
  END;

  -- leg 5b: an UPDATE affects 0 rows
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated', 'is_anonymous', false)::text, true);
    UPDATE storage.objects SET name = name WHERE bucket_id = 'exercise-media' AND name = v_name;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_write_update := v_n::text;
    RAISE EXCEPTION 'PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PROBE_ROLLBACK' THEN v_write_update := 'error: ' || v_msg; END IF;
  END;

  -- leg 5c: a DELETE affects 0 rows (Storage's statement trigger refuses a direct delete unless this setting is
  -- on, which would hide the policy; the Storage API sets it for its own deletes)
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_uid, 'role', 'authenticated', 'is_anonymous', false)::text, true);
    PERFORM set_config('storage.allow_delete_query', 'true', true);
    DELETE FROM storage.objects WHERE bucket_id = 'exercise-media' AND name = v_name;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_write_delete := v_n::text;
    RAISE EXCEPTION 'PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'PROBE_ROLLBACK' THEN v_write_delete := 'error: ' || v_msg; END IF;
  END;
  -- PROBE-END

  v_verdict := CASE
    WHEN v_anon = '0' AND v_auth = '1' AND v_anon_session = '0' AND v_other = '0'
     AND v_write_insert = 'refused' AND v_write_update = '0' AND v_write_delete = '0'
     AND v_anon_priv
     AND v_bucket_public = 'false' AND v_bucket_limit = '1500000' AND v_bucket_mime = '{image/webp}'
     AND v_policy_cmd = 'SELECT' AND v_policy_roles = '{authenticated}'
     AND v_qual_bucket = 'true' AND v_qual_anon = 'true'
     AND v_anon_public = 'none' AND v_unscoped_write = 'none'
    THEN 'PASS' ELSE 'FAIL' END;

  RAISE EXCEPTION 'VERIFY_RESULTS%', E'\n'
    || 'verdict=' || v_verdict || E'\n'
    || 'anon=' || coalesce(v_anon, 'unset') || E'\n'
    || 'authenticated=' || coalesce(v_auth, 'unset') || E'\n'
    || 'anon_session=' || coalesce(v_anon_session, 'unset') || E'\n'
    || 'other_bucket=' || coalesce(v_other, 'unset') || E'\n'
    || 'write_insert=' || coalesce(v_write_insert, 'unset') || E'\n'
    || 'write_update=' || coalesce(v_write_update, 'unset') || E'\n'
    || 'write_delete=' || coalesce(v_write_delete, 'unset') || E'\n'
    || 'anon_select_priv=' || coalesce(v_anon_priv::text, 'unset') || E'\n'
    || 'bucket_public=' || coalesce(v_bucket_public, 'absent') || E'\n'
    || 'bucket_limit=' || coalesce(v_bucket_limit, 'absent') || E'\n'
    || 'bucket_mime=' || coalesce(v_bucket_mime, 'absent') || E'\n'
    || 'policy_cmd=' || coalesce(v_policy_cmd, 'absent') || E'\n'
    || 'policy_roles=' || coalesce(v_policy_roles, 'absent') || E'\n'
    || 'policy_qual_has_bucket=' || coalesce(v_qual_bucket, 'absent') || E'\n'
    || 'policy_qual_has_is_anonymous=' || coalesce(v_qual_anon, 'absent') || E'\n'
    || 'anon_public_select_policies=' || v_anon_public || E'\n'
    || 'unscoped_write_grants=' || v_unscoped_write || E'\n'
    || 'select_policies=' || v_listing;
END
$v$;
