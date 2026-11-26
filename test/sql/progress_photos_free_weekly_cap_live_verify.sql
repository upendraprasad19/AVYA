-- test/sql/progress_photos_free_weekly_cap_live_verify.sql
--
-- Live-Postgres verification of the progress-photos free weekly cap (OI-348 Landing 3c; draft
-- test/sql/progress_photos_free_weekly_cap_draft.sql, plan docs/plans/oi348-landing3c.md section 2).
-- Supersedes test/sql/progress_photos_pro_insert_rule_live_verify.sql, which proves migration 154's
-- PRO-only rule.
--
-- SHAPE. ONE DO block that ALWAYS aborts with RAISE EXCEPTION 'VERIFY_RESULTS ...', so nothing it
-- writes survives (the technique of migration 152's prod dry run and of the 154 verify). Run it with
-- the founder's go through execute_sql; every line of VERIFY_RESULTS must read `ok`. As the REHEARSAL
-- before the apply it runs AFTER the draft inside one statement:
--   DO $rh$ BEGIN EXECUTE <the draft's DO statement>; EXECUTE <this DO statement>; END $rh$;
-- so the draft's DDL is rolled back with the verify's abort.
--
-- WHO IS N. A real user (auth.users joined to public.users) with no subscriptions row, no progress_photos
-- row and no object in the bucket, chosen as postgres before any role switch. No user id is written to
-- the repo. O is a synthetic folder uuid that belongs to nobody.
--
-- ROLE WINDOW (as in the 154 verify): `SET LOCAL ROLE <role>` plus the JWT settings, set inside the nested
-- BEGIN ... EXCEPTION block of each case, so an exception also restores the role. The claims carry `role`
-- as well as `sub`, because the storage trigger reads auth.role(). A case with no claims runs as postgres
-- (auth.role() and auth.uid() NULL), the shape of a service or Storage-internal insert. Every "succeeds"
-- case asserts ROW_COUNT = 1. Timestamps inside one transaction all equal now(), so the week cases
-- BACKDATE an object or row as postgres to put it in last week.
--
-- BEFORE the apply (rehearsal skipped, plain run): W2, W8, W12a, W12b and the catalog lines read `fail`
-- (no trigger yet; the 154 policy refuses a free user at W1 instead, so W1 fails too). AFTER: every line ok.

DO $v$
DECLARE
  v_n        uuid;
  v_o        uuid := '00000000-0000-0000-0000-0000000f3c9a'::uuid;
  v_r        text := '';
  v_rows     int;
  v_state    text;
  v_msg      text;
  v_ts       timestamptz;
  v_week     timestamptz := (date_trunc('week', now() AT TIME ZONE 'Asia/Kolkata')) AT TIME ZONE 'Asia/Kolkata';
  v_txt      text;
  v_cnt      int;
BEGIN
  SELECT u.id INTO v_n
    FROM public.users u
    JOIN auth.users a ON a.id = u.id
   WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM public.progress_photos p WHERE p.user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.name LIKE u.id::text || '/%')
   ORDER BY u.id
   LIMIT 1;
  IF v_n IS NULL THEN
    RAISE EXCEPTION 'VERIFY_ABORT no borrowable user';
  END IF;

  -- W1: free N, first object this week, own folder -> accepted.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/o1.jpg', v_n::text);
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    v_r := v_r || CASE WHEN v_rows = 1 THEN E'W1=ok\n' ELSE E'W1=fail (row count)\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W1=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- W2: free N, a second object this week -> refused by the trigger (42501 + the literal).
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/o2.jpg', v_n::text);
    RESET ROLE;
    v_r := v_r || E'W2=fail (a second object this week was accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = '42501' AND v_msg = 'progress_photo_pro_required' THEN E'W2=ok\n'
                       ELSE 'W2=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- o1 moves to last week (as postgres).
  UPDATE storage.objects SET created_at = v_week - interval '1 second'
   WHERE bucket_id = 'progress-photos' AND name = v_n::text || '/o1.jpg';

  -- W3: last week's object does not count -> o2 is accepted now.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/o2.jpg', v_n::text);
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    v_r := v_r || CASE WHEN v_rows = 1 THEN E'W3=ok\n' ELSE E'W3=fail (row count)\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W3=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- W4: the row for o1 is accepted and takes o1's created_at (last week), not now().
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (user_id, storage_path, taken_at, created_at)
      VALUES (v_n, v_n::text || '/o1.jpg', now(), now() + interval '1 day');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    SELECT created_at INTO v_ts FROM public.progress_photos WHERE user_id = v_n AND storage_path = v_n::text || '/o1.jpg';
    v_r := v_r || CASE WHEN v_rows = 1 AND v_ts = v_week - interval '1 second' THEN E'W4=ok\n'
                       ELSE 'W4=fail (created_at ' || coalesce(v_ts::text, 'null') || E')\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W4=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- O's object, last week (as postgres: no claims, capped by O, who has nothing).
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_o::text || '/x.jpg', v_o::text);
  UPDATE storage.objects SET created_at = v_week - interval '2 days'
   WHERE bucket_id = 'progress-photos' AND name = v_o::text || '/x.jpg';

  -- W5: N's row pointing at O's last-week object does NOT adopt its created_at: it takes now() and is
  -- accepted (N has no row this week). Adopting it would put it in last week, where W4 already sits: refused.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (user_id, storage_path, taken_at)
      VALUES (v_n, v_o::text || '/x.jpg', now());
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    SELECT created_at INTO v_ts FROM public.progress_photos WHERE user_id = v_n AND storage_path = v_o::text || '/x.jpg';
    v_r := v_r || CASE WHEN v_rows = 1 AND v_ts = now() THEN E'W5=ok\n'
                       ELSE 'W5=fail (created_at ' || coalesce(v_ts::text, 'null') || E')\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W5=fail (' || v_state || ' ' || v_msg || E')\n';
  END;
  DELETE FROM public.progress_photos WHERE user_id = v_n AND storage_path = v_o::text || '/x.jpg';

  -- W6: the row for o2 (this week) is accepted.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (user_id, storage_path, taken_at) VALUES (v_n, v_n::text || '/o2.jpg', now());
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    v_r := v_r || CASE WHEN v_rows = 1 THEN E'W6=ok\n' ELSE E'W6=fail (row count)\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W6=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- W7: a second row this week (no object at that path: created_at = now()) -> refused P0001.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (user_id, storage_path, taken_at) VALUES (v_n, v_n::text || '/none.jpg', now());
    RESET ROLE;
    v_r := v_r || E'W7=fail (a second row this week was accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = 'P0001' AND v_msg = 'progress_photo_pro_required' THEN E'W7=ok\n'
                       ELSE 'W7=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- W8: an UPDATE cannot move created_at (backdating o2's row would free the row door).
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    UPDATE public.progress_photos SET created_at = now() - interval '30 days', notes = 'w8'
     WHERE user_id = v_n AND storage_path = v_n::text || '/o2.jpg';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    SELECT created_at INTO v_ts FROM public.progress_photos WHERE user_id = v_n AND storage_path = v_n::text || '/o2.jpg';
    v_r := v_r || CASE WHEN v_rows = 1 AND v_ts = now() THEN E'W8=ok\n'
                       ELSE 'W8=fail (created_at ' || coalesce(v_ts::text, 'null') || E')\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W8=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- W8b (Hermes A2): an UPDATE cannot move storage_path either (repointing the last-week row at another
  -- path would leave this week's row door empty while the object is held).
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    UPDATE public.progress_photos SET storage_path = v_n::text || '/w8b.jpg'
     WHERE user_id = v_n AND storage_path = v_n::text || '/o1.jpg';
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    SELECT count(*) INTO v_cnt FROM public.progress_photos
     WHERE user_id = v_n AND storage_path = v_n::text || '/o1.jpg';
    v_r := v_r || CASE WHEN v_rows = 1 AND v_cnt = 1 THEN E'W8b=ok\n'
                       ELSE 'W8b=fail (rows ' || v_rows || ', o1 rows left ' || v_cnt || E')\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W8b=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- W9: anon writing into N's folder gets the RLS refusal, NOT the trigger's literal (no answer about N's week).
  BEGIN
    SET LOCAL ROLE anon;
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    INSERT INTO storage.objects (bucket_id, name) VALUES ('progress-photos', v_n::text || '/w9.jpg');
    RESET ROLE;
    v_r := v_r || E'W9=fail (anon insert accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = '42501' AND v_msg LIKE '%row-level security%' THEN E'W9=ok\n'
                       ELSE 'W9=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- W10: another signed-in user (O) writing into N's folder gets the RLS refusal, not the literal.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_o::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/w10.jpg', v_o::text);
    RESET ROLE;
    v_r := v_r || E'W10=fail (a foreign-folder insert accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = '42501' AND v_msg LIKE '%row-level security%' THEN E'W10=ok\n'
                       ELSE 'W10=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- W10b (Hermes A1): O inserting a progress_photos ROW for N (free, holding a row this week) gets the
  -- RLS refusal, never the cap literal: the row door must not tell O whether N is PRO or holds a photo.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_o::text, true);
    INSERT INTO public.progress_photos (user_id, storage_path, taken_at) VALUES (v_n, v_n::text || '/o2.jpg', now());
    RESET ROLE;
    v_r := v_r || E'W10b=fail (a row for another user was accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = '42501' AND v_msg LIKE '%row-level security%' THEN E'W10b=ok\n'
                       ELSE 'W10b=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- W11: a service_role JWT carrying O's sub, writing into N's folder, is capped by the OWNER (N, free, o2 held).
  BEGIN
    SET LOCAL ROLE service_role;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o, 'role', 'service_role')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_o::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/w11.jpg', v_o::text);
    RESET ROLE;
    v_r := v_r || E'W11=fail (service_role bypassed the owner cap)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = '42501' AND v_msg = 'progress_photo_pro_required' THEN E'W11=ok\n'
                       ELSE 'W11=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- W12a/b: a non-uuid folder and a root-level name are refused (fail closed), as postgres.
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  BEGIN
    INSERT INTO storage.objects (bucket_id, name) VALUES ('progress-photos', 'not-a-uuid/w12.jpg');
    v_r := v_r || E'W12a=fail (accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_msg = 'progress_photo_pro_required' THEN E'W12a=ok\n' ELSE 'W12a=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;
  BEGIN
    INSERT INTO storage.objects (bucket_id, name) VALUES ('progress-photos', 'w12.jpg');
    v_r := v_r || E'W12b=fail (accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_msg = 'progress_photo_pro_required' THEN E'W12b=ok\n' ELSE 'W12b=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- W13: another bucket is untouched: a chat-media object for capped N is accepted (the trigger's WHEN).
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('chat-media', v_n::text || '/w13.jpg', v_n::text);
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    v_r := v_r || CASE WHEN v_rows = 1 THEN E'W13=ok\n' ELSE E'W13=fail (row count)\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W13=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- PRO: an active, unexpired subscription row for N.
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)
    VALUES (v_n, 'monthly', 'active', now(), now() + interval '30 days');

  -- W14: PRO N, two more objects and rows this week -> all accepted.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/p1.jpg', v_n::text);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/p2.jpg', v_n::text);
    INSERT INTO public.progress_photos (user_id, storage_path, taken_at) VALUES (v_n, v_n::text || '/p1.jpg', now());
    INSERT INTO public.progress_photos (user_id, storage_path, taken_at) VALUES (v_n, v_n::text || '/p2.jpg', now());
    RESET ROLE;
    SELECT count(*) INTO v_cnt FROM public.progress_photos WHERE user_id = v_n AND created_at >= v_week;
    v_r := v_r || CASE WHEN v_cnt = 3 THEN E'W14=ok\n' ELSE 'W14=fail (rows this week ' || v_cnt || E')\n' END;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || 'W14=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- W14b (Hermes A1): the same foreign-row insert with N now PRO gets the SAME refusal as W10b.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_o, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_o::text, true);
    INSERT INTO public.progress_photos (user_id, storage_path, taken_at) VALUES (v_n, v_n::text || '/p1.jpg', now());
    RESET ROLE;
    v_r := v_r || E'W14b=fail (a row for another user was accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = '42501' AND v_msg LIKE '%row-level security%' THEN E'W14b=ok\n'
                       ELSE 'W14b=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- W15: lapsed (end_date in the past) = free -> refused again.
  UPDATE public.subscriptions SET end_date = now() - interval '1 day' WHERE user_id = v_n;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/l1.jpg', v_n::text);
    RESET ROLE;
    v_r := v_r || E'W15=fail (a lapsed user was not capped)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = '42501' AND v_msg = 'progress_photo_pro_required' THEN E'W15=ok\n'
                       ELSE 'W15=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- W16 (B-pass F5): a NESTED name in lapsed N's own folder is capped by the same owner (folder[1]),
  -- so a subfolder is no way round the week. The client never writes one (it uploads `<uid>/<file>` and
  -- its courtesy check lists direct children only), so such an object is counted by the server alone.
  -- NOT covered on purpose: an `upsert` (ON CONFLICT) re-upload of a held path. A BEFORE INSERT trigger
  -- fires before conflict resolution, so a free user would be refused; the client sends `upsert: false`.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id) VALUES ('progress-photos', v_n::text || '/sub/w16.jpg', v_n::text);
    RESET ROLE;
    v_r := v_r || E'W16=fail (a nested name escaped the cap)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_r := v_r || CASE WHEN v_state = '42501' AND v_msg = 'progress_photo_pro_required' THEN E'W16=ok\n'
                       ELSE 'W16=fail (' || v_state || ' ' || v_msg || E')\n' END;
  END;

  -- C1: the three trigger functions are SECURITY DEFINER with the pinned path; nobody but the owner and
  -- service_role / postgres may EXECUTE any of the four functions.
  SELECT count(*) INTO v_cnt FROM pg_proc
   WHERE proname IN ('enforce_progress_photo_object_cap', 'enforce_progress_photo_pro', 'keep_progress_photo_created_at')
     AND prosecdef AND proconfig = ARRAY['search_path=public, pg_temp'];
  v_r := v_r || CASE WHEN v_cnt = 3 THEN E'C1=ok\n' ELSE 'C1=fail (' || v_cnt || E' of 3)\n' END;
  SELECT count(*) INTO v_cnt FROM pg_proc p
   WHERE p.proname IN ('progress_photo_week_start', 'enforce_progress_photo_object_cap', 'enforce_progress_photo_pro', 'keep_progress_photo_created_at')
     AND (has_function_privilege('anon', p.oid, 'execute') OR has_function_privilege('authenticated', p.oid, 'execute'));
  v_r := v_r || CASE WHEN v_cnt = 0 THEN E'C2=ok\n' ELSE 'C2=fail (' || v_cnt || E' executable by anon/authenticated)\n' END;
  -- C3: the storage trigger exists with its WHEN; C4: the UPDATE guard exists; C5: the INSERT policy has no subscription read.
  SELECT pg_get_triggerdef(oid) INTO v_txt FROM pg_trigger WHERE tgname = 'trg_progress_photo_object_cap' AND tgrelid = 'storage.objects'::regclass;
  v_r := v_r || CASE WHEN v_txt LIKE '%BEFORE INSERT ON storage.objects FOR EACH ROW WHEN ((new.bucket_id = ''progress-photos''::text)) EXECUTE FUNCTION %enforce_progress_photo_object_cap()'
                     THEN E'C3=ok\n' ELSE 'C3=fail (' || coalesce(v_txt, 'absent') || E')\n' END;
  SELECT pg_get_triggerdef(oid) INTO v_txt FROM pg_trigger WHERE tgname = 'trg_progress_photo_created_at_keep' AND tgrelid = 'public.progress_photos'::regclass;
  v_r := v_r || CASE WHEN v_txt LIKE '%BEFORE UPDATE ON public.progress_photos FOR EACH ROW EXECUTE FUNCTION %keep_progress_photo_created_at()'
                     THEN E'C4=ok\n' ELSE 'C4=fail (' || coalesce(v_txt, 'absent') || E')\n' END;
  SELECT with_check INTO v_txt FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'progress_photos_insert_own';
  v_r := v_r || CASE WHEN v_txt IS NOT NULL AND v_txt NOT LIKE '%subscriptions%' AND v_txt LIKE '%foldername%' THEN E'C5=ok\n'
                     ELSE 'C5=fail (' || coalesce(v_txt, 'absent') || E')\n' END;

  RAISE EXCEPTION 'VERIFY_RESULTS%', E'\n' || v_r;
END
$v$;
