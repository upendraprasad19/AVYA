-- test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql
--
-- REHEARSAL ONLY. FILE 2 of two (FILE 1 is test/sql/exercise_media_bucket_live_verify.sql). Batch M1, diagnose
-- b4e7a2, plan docs/plans/2026-10-27-library-batch-m1-media-data.md R15. Run it in Task 8.4, BEFORE the apply, and
-- NEVER after it: its first statement raises if the exercise-media bucket already exists.
--
-- LOCKS. The policy DDL of the baseline and of every variant takes the same table locks as the apply (see the LOCKS
-- note of the migration draft) and holds them until the block ends, so the whole rehearsal holds them for seconds, not
-- milliseconds. Run it off-peak, with no sign-in or test session active.
--
-- WHAT IT PROVES. That the role probe and the catalog check of FILE 1 can tell the right setup from wrong ones. A
-- probe that passes the right policy proves nothing until it is also shown to fail a wrong one. The block runs the
-- migration body (the prelude below: the text of the migration's DO block without its wrapper, pinned equal to the
-- migration by test/contracts/exercise_media_bucket_private_test.dart), runs the probe and the catalog check on the
-- right policy (the BASELINE), and then, for each variant, applies the wrong DDL inside its own nested
-- BEGIN ... EXCEPTION block that always raises after the readings, so the DDL rolls back to the right setup before
-- the next variant (the technique of test/sql/promo_codes_no_client_access_live_verify.sql). The probe block and the
-- catalog block are byte-equal (after normalisation) to FILE 1's, pinned by the same test.
--
-- THE VARIANTS and their exact expected readings. QUADRUPLE = anon / authenticated / anon_session / other_bucket;
-- WRITES = insert / update / delete / bucket (the bucket leg is an UPDATE of storage.buckets); CATALOG = policy_cmd |
-- policy_roles | has_bucket | has_is_anonymous | anon_public_select_policies | unscoped_write_grants:
--   baseline  the migration's policy                       0/1/0/0  refused/0/0/0  SELECT|{authenticated}|true|true|none|none
--   v1        TO public instead of TO authenticated         1/1/0/0  refused/0/0/0  SELECT|{public}|true|true|<policy>|none   flips anon
--   v2        no is_anonymous clause                        0/1/1/0  refused/0/0/0  SELECT|{authenticated}|true|false|none|none flips anon_session
--   v3        no bucket scope (is_anonymous clause only)    0/1/0/1  refused/0/0/0  SELECT|{authenticated}|false|true|none|none flips other_bucket
--   v4        FOR ALL with the right USING                  0/1/0/0  inserted/1/1/0 ALL|{authenticated}|true|true|none|objects.exercise_media_authenticated_read  flips the objects write legs
--   v5        the right policy PLUS a FOR UPDATE USING (true) policy on storage.buckets: quadruple 0/1/0/0,
--             writes refused/0/0/open (refused/0/0/0 when authenticated has no UPDATE privilege on storage.buckets: then
--             the leg cannot redden and the catalog string alone carries v5), catalog
--             SELECT|{authenticated}|true|true|none|buckets.exercise_media_buckets_wrong   flips the bucket leg
-- A variant is RED only when its quadruple, its writes AND its catalog string equal its row exactly; anything else is
-- a STOP (the probe or the variant is not what the plan says, or the DDL was refused: read the error text). The
-- baseline must equal its row and anon_select_priv must be true.
--
-- SHAPE. ONE `DO` block that ALWAYS aborts with `RAISE EXCEPTION 'VERIFY_RESULTS ...'`, so nothing persists: the
-- bucket the prelude creates, the policies and the fixtures all roll back with the statement. If a call ever RETURNS
-- SUCCESS, the trailing RAISE did not fire and the DDL may have committed: read pg_policies for storage.objects and
-- storage.buckets, drop anything naming exercise-media except the real policy, and stop. After a transport error
-- with no VERIFY_RESULTS, read the catalog to prove nothing persisted. If one call is refused as too large, send it
-- as one call per variant (drop the others from the FOR loop bounds).
--
-- OUTPUT. `VERIFY_RESULTS`, then `verdict=PASS|FAIL`, then one line per variant
-- `<name>=<quadruple>;<writes>;<catalog> expected=<quadruple>;<writes>;<catalog> <OK|RED|STOP>`, then
-- `anon_select_priv=...`, `authenticated_update_priv_on_buckets=...` and `mutated: <n> of 5 reddened`. PASS needs the
-- baseline OK and all five variants RED.

DO $r$
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
  v_write_bucket   text;
  v_bucket_public  text;
  v_bucket_limit   text;
  v_bucket_mime    text;
  v_policy_cmd     text;
  v_policy_roles   text;
  v_qual_bucket    text;
  v_qual_anon      text;
  v_anon_public    text;
  v_unscoped_write text;
  v_anon_priv      boolean;
  v_bucket_upd_priv boolean;
  v_i              int;
  v_names          text[] := ARRAY['baseline', 'v1_to_public', 'v2_no_is_anonymous', 'v3_unscoped_bucket', 'v4_for_all', 'v5_buckets_update_policy'];
  v_expected       text[] := ARRAY['0/1/0/0', '1/1/0/0', '0/1/1/0', '0/1/0/1', '0/1/0/0', '0/1/0/0'];
  v_expected_w     text[] := ARRAY['refused/0/0/0', 'refused/0/0/0', 'refused/0/0/0', 'refused/0/0/0', 'inserted/1/1/0', 'refused/0/0/0'];
  v_expected_c     text[] := ARRAY[
    'SELECT|{authenticated}|true|true|none|none',
    'SELECT|{public}|true|true|exercise_media_authenticated_read|none',
    'SELECT|{authenticated}|true|false|none|none',
    'SELECT|{authenticated}|false|true|none|none',
    'ALL|{authenticated}|true|true|none|objects.exercise_media_authenticated_read',
    'SELECT|{authenticated}|true|true|none|buckets.exercise_media_buckets_wrong'];
  v_actual         text;
  v_actual_w       text;
  v_cat            text;
  v_err            text;
  v_flag           text;
  v_lines          text := '';
  v_red            int := 0;
  v_stop           int := 0;
BEGIN
  -- guard: rehearsal only, the bucket must not exist yet (the prelude creates it inside this aborting statement)
  IF EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'exercise-media') THEN
    RAISE EXCEPTION 'REHEARSAL_ONLY: the exercise-media bucket already exists; this file must not run after the apply';
  END IF;

  -- PRELUDE-BEGIN
  -- a lock wait longer than 5 s aborts the whole block: nothing is applied, a re-run is idempotent
  PERFORM set_config('lock_timeout', '5s', true);

  -- (1) the private bucket
  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES ('exercise-media', 'exercise-media', false, 1500000, ARRAY['image/webp'])
  ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

  -- (2) the one read policy (re-runnable: dropped and re-created under the same name)
  DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
  CREATE POLICY exercise_media_authenticated_read ON storage.objects
    FOR SELECT TO authenticated
    USING (
      bucket_id = 'exercise-media'
      AND coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
    );

  -- (3) read-back self-check: any miss raises and rolls the block back
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id = 'exercise-media'
      AND public = false
      AND file_size_limit = 1500000
      AND allowed_mime_types = ARRAY['image/webp']
  ) THEN
    RAISE EXCEPTION 'exercise_media_bucket self-check: the bucket row is not private, 1500000 bytes, image/webp';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'exercise_media_authenticated_read'
      AND cmd = 'SELECT'
      AND roles = ARRAY['authenticated']::name[]
      AND qual LIKE '%exercise-media%'
      AND strpos(qual, 'is_anonymous') > 0
  ) THEN
    RAISE EXCEPTION 'exercise_media_bucket self-check: the read policy is missing or is not SELECT TO authenticated with the bucket and is_anonymous predicates';
  END IF;

  IF (
    SELECT count(*) FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND (coalesce(qual, '') LIKE '%exercise-media%' OR coalesce(with_check, '') LIKE '%exercise-media%')
  ) <> 1 THEN
    RAISE EXCEPTION 'exercise_media_bucket self-check: some other policy of storage.objects names exercise-media';
  END IF;
  -- PRELUDE-END

  v_anon_priv := has_table_privilege('anon', 'storage.objects', 'SELECT');
  v_bucket_upd_priv := has_table_privilege('authenticated', 'storage.buckets', 'UPDATE');
  IF v_bucket_upd_priv THEN v_expected_w[6] := 'refused/0/0/open'; END IF;

  FOR v_i IN 1..6 LOOP
    v_anon := NULL; v_auth := NULL; v_anon_session := NULL; v_other := NULL;
    v_write_insert := NULL; v_write_update := NULL; v_write_delete := NULL; v_write_bucket := NULL;
    v_err := NULL;
    BEGIN
      -- the variant's wrong DDL (variants 2 to 5 replace the policy under the same name as the real one)
      IF v_i = 2 THEN
        DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
        CREATE POLICY exercise_media_authenticated_read ON storage.objects
          FOR SELECT TO public
          USING (
            bucket_id = 'exercise-media'
            AND coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
          );
      ELSIF v_i = 3 THEN
        DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
        CREATE POLICY exercise_media_authenticated_read ON storage.objects
          FOR SELECT TO authenticated
          USING (bucket_id = 'exercise-media');
      ELSIF v_i = 4 THEN
        DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
        CREATE POLICY exercise_media_authenticated_read ON storage.objects
          FOR SELECT TO authenticated
          USING (coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false);
      ELSIF v_i = 5 THEN
        DROP POLICY IF EXISTS exercise_media_authenticated_read ON storage.objects;
        CREATE POLICY exercise_media_authenticated_read ON storage.objects
          FOR ALL TO authenticated
          USING (
            bucket_id = 'exercise-media'
            AND coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
          );
      ELSIF v_i = 6 THEN
        CREATE POLICY exercise_media_buckets_wrong ON storage.buckets
          FOR UPDATE TO authenticated
          USING (true);
      END IF;

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
          v_anon := CASE WHEN v_msg LIKE 'permission denied for table objects%' THEN '0' ELSE 'error: ' || v_msg END;
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
          v_write_insert := CASE WHEN v_msg LIKE 'new row violates row-level security policy for table "objects"%' THEN 'refused' ELSE 'error: ' || v_msg END;
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

      -- leg 5d: the normal session may not rewrite a bucket row (flip it public). The statement has NO WHERE clause and sets a
      -- constant, on purpose: a WHERE on id (or a column on the right of SET) also needs the row to pass a SELECT policy, so an
      -- UPDATE-only policy would hide from it; with neither, only the UPDATE policy decides. 0 rows (a privilege denial on that
      -- table is the same answer, 0) is right; any row means some policy lets a logged-in user rewrite a bucket row: 'open'.
      BEGIN
        SET LOCAL ROLE authenticated;
        PERFORM set_config('request.jwt.claims',
          json_build_object('sub', v_uid, 'role', 'authenticated', 'is_anonymous', false)::text, true);
        UPDATE storage.buckets SET public = true;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_write_bucket := CASE WHEN v_n = 0 THEN '0' ELSE 'open' END;
        RAISE EXCEPTION 'PROBE_ROLLBACK';
      EXCEPTION
        WHEN insufficient_privilege THEN
          GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
          v_write_bucket := CASE WHEN v_msg LIKE 'permission denied for table buckets%' THEN '0' ELSE 'error: ' || v_msg END;
        WHEN OTHERS THEN
          GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
          IF v_msg <> 'PROBE_ROLLBACK' THEN v_write_bucket := 'error: ' || v_msg; END IF;
      END;
      -- PROBE-END

      -- CATALOG-BEGIN
      SELECT public::text, file_size_limit::text, allowed_mime_types::text
        INTO v_bucket_public, v_bucket_limit, v_bucket_mime
        FROM storage.buckets WHERE id = 'exercise-media';

      SELECT cmd, roles::text, (strpos(qual, 'exercise-media') > 0)::text, (strpos(qual, 'is_anonymous') > 0)::text
        INTO v_policy_cmd, v_policy_roles, v_qual_bucket, v_qual_anon
        FROM pg_policies
       WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'exercise_media_authenticated_read';

      SELECT coalesce(string_agg(policyname, ',' ORDER BY policyname), 'none') INTO v_anon_public
        FROM pg_policies
       WHERE schemaname = 'storage' AND tablename = 'objects'
         AND cmd IN ('SELECT', 'ALL')
         AND roles && ARRAY['anon', 'public']::name[]
         AND (qual IS NULL OR strpos(qual, 'bucket_id') = 0 OR strpos(qual, 'exercise-media') > 0);

      SELECT coalesce(string_agg(tablename || '.' || policyname, ',' ORDER BY tablename, policyname), 'none') INTO v_unscoped_write
        FROM pg_policies
       WHERE schemaname = 'storage' AND tablename IN ('objects', 'buckets')
         AND cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
         AND roles && ARRAY['anon', 'authenticated', 'public']::name[]
         AND (tablename = 'buckets'
              OR strpos(coalesce(qual, '') || coalesce(with_check, ''), 'bucket_id') = 0
              OR strpos(coalesce(qual, '') || coalesce(with_check, ''), 'exercise-media') > 0
              OR (coalesce(qual, '') || coalesce(with_check, '')) ~ '(<>|!=|!~|NOT |IS DISTINCT|~~)');
      -- CATALOG-END

      v_actual := coalesce(v_anon, 'unset') || '/' || coalesce(v_auth, 'unset') || '/'
        || coalesce(v_anon_session, 'unset') || '/' || coalesce(v_other, 'unset');
      v_actual_w := coalesce(v_write_insert, 'unset') || '/' || coalesce(v_write_update, 'unset') || '/'
        || coalesce(v_write_delete, 'unset') || '/' || coalesce(v_write_bucket, 'unset');
      v_cat := coalesce(v_policy_cmd, 'absent') || '|' || coalesce(v_policy_roles, 'absent') || '|'
        || coalesce(v_qual_bucket, 'absent') || '|' || coalesce(v_qual_anon, 'absent') || '|'
        || v_anon_public || '|' || v_unscoped_write;
      RAISE EXCEPTION 'VARIANT_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      IF v_msg <> 'VARIANT_ROLLBACK' THEN v_err := v_msg; END IF;
    END;

    IF v_err IS NOT NULL THEN
      v_flag := 'STOP';
      v_lines := v_lines || v_names[v_i] || '=error: ' || v_err || ' ' || v_flag || E'\n';
      v_stop := v_stop + 1;
    ELSE
      IF v_i = 1 THEN
        v_flag := CASE WHEN v_actual = v_expected[v_i] AND v_actual_w = v_expected_w[v_i] AND v_cat = v_expected_c[v_i] AND v_anon_priv
                       THEN 'OK' ELSE 'STOP' END;
      ELSE
        v_flag := CASE WHEN v_actual = v_expected[v_i] AND v_actual_w = v_expected_w[v_i] AND v_cat = v_expected_c[v_i]
                       THEN 'RED' ELSE 'STOP' END;
      END IF;
      IF v_flag = 'RED' THEN v_red := v_red + 1; END IF;
      IF v_flag = 'STOP' THEN v_stop := v_stop + 1; END IF;
      v_lines := v_lines || v_names[v_i] || '=' || v_actual || ';' || v_actual_w || ';' || v_cat
        || ' expected=' || v_expected[v_i] || ';' || v_expected_w[v_i] || ';' || v_expected_c[v_i] || ' ' || v_flag || E'\n';
    END IF;
  END LOOP;

  RAISE EXCEPTION 'VERIFY_RESULTS%', E'\n'
    || 'verdict=' || CASE WHEN v_stop = 0 AND v_red = 5 AND v_anon_priv THEN 'PASS' ELSE 'FAIL' END || E'\n'
    || v_lines
    || 'anon_select_priv=' || coalesce(v_anon_priv::text, 'unset') || E'\n'
    || 'authenticated_update_priv_on_buckets=' || coalesce(v_bucket_upd_priv::text, 'unset') || E'\n'
    || 'mutated: ' || v_red || ' of 5 reddened';
END
$r$;
