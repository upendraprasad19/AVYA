-- test/sql/progress_photos_pro_insert_rule_live_verify.sql
--
-- Live-Postgres verification of the progress-photo PRO INSERT rule (migration 154, unit B1 of the
-- 2026-10-06 progress-photos batch; plan docs/plans/progress-photos-pro-server-rule.md, D8).
--
-- WHAT IT PROVES. Source-grep tests (test/contracts/progress_photos_pro_insert_rule_test.dart) prove
-- the migration text. They cannot prove that, on the live database, (a) a user with no active
-- subscription is refused at BOTH doors (the progress_photos row: P0001 progress_photo_pro_required;
-- the Storage object: 42501), (b) a PRO user is NOT falsely refused (the rule reads public.subscriptions
-- as the `authenticated` role through RLS), (c) every lapsed state is refused (expired, cancelled,
-- end_date in the past) and a restored state is accepted again (the negative control that shows the
-- refusals were caused by the predicate), (d) a lapsed user can still SELECT and DELETE what they have
-- (founder decision 6), and (e) the policy set is the one the plan expects.
--
-- SHAPE. ONE `DO` block that ALWAYS aborts with `RAISE EXCEPTION 'VERIFY_RESULTS ...'`, so the
-- transaction never commits and nothing is left open or locked; the results are read from the error
-- text. (This is the technique of migration 152's prod dry run, docs/diagnoses/2026-09-29-subscription-
-- mirror-columns-dropped-c7e3b9.md tier 3 and docs/plans/oi-182-202-subscription-state.md:90; an explicit
-- BEGIN ... ROLLBACK is NOT used because on a mid-message error through execute_sql the trailing ROLLBACK
-- is skipped and the aborted session keeps its locks.) Run it with the founder's go through
-- execute_sql; read the line `VERIFY_RESULTS` in the error text; every case must read `ok`.
--
-- NO DDL. Every PRO state is a synthetic public.subscriptions row seeded for the borrowed user N
-- inside the transaction, and states change by UPDATing that row. No DROP/ALTER/CREATE: DDL on
-- storage.objects takes an ACCESS EXCLUSIVE lock on the table that serves every bucket's traffic.
--
-- WHO IS N. A real user (auth.users joined to public.users) with no subscriptions row and no
-- progress_photos row, chosen as `postgres` BEFORE any role switch. No user id is written to the repo.
-- All writes are inside the aborting block, so N is untouched; the separate residue read that follows
-- the abort (run it as a second execute_sql call) confirms it.
--
-- ROLE WINDOW. `postgres` is a member of `authenticated` and bypasses RLS, so `SET LOCAL ROLE
-- authenticated` plus the two JWT settings runs the statement under test as N. BOTH settings are
-- written: `request.jwt.claims` (what the live auth.uid() reads, as test/sql/rls_initplan_ab_verify.sql
-- relies on) and `request.jwt.claim.sub` (what an older auth.uid(), such as the one in the local
-- supabase/postgres image, reads); a verify that set only one would see auth.uid() = NULL and read every
-- refusal as the rule working. The
-- window is opened and closed INSIDE the nested BEGIN ... EXCEPTION block of each case; an exception
-- rolls that subtransaction back, which also restores the role. Every "succeeds" case asserts
-- GET DIAGNOSTICS ... ROW_COUNT = 1 (a RETURN NULL trigger would otherwise pass "the INSERT did not
-- raise" by silently dropping the row).
--
-- DELETE of a storage.objects row is not available from SQL (protect_objects_delete, a BEFORE DELETE
-- statement trigger, refuses it), so the Storage DELETE policy is checked by catalog text in V8, not
-- exercised.
--
-- BEFORE the apply (the §4.9 check that a new behavioural test is run against the code it replaces),
-- V1, V2, V4c, V4d, V4f, V5a, V5b, V6a, V6b, V6c, V6d, V8a and V8e must read `fail` (the rule is not there yet), V4a
-- and V4e read `fail` as knock-ons (the inserts V1, V4c and V4f were ACCEPTED, so the user holds more than one photo
-- row), and V0, V3 (V3e and V3f too: they pass both before and after), V4b, V7, V8b-V8d, V8f and V9 read `ok`. AFTER the apply, every case reads `ok` (30 lines). Measured against a local
-- throwaway replica of the live objects (a supabase/postgres 17.6 container, evidence E1-E16), before and
-- after the draft migration, and against 16 deliberately wrong policies / trigger functions, each of which this
-- file flags (diagnose d8f2a6, section "local replica run", written in the final commit). A policy changed to `... OR EXISTS (active
-- subscription)` fails V3d (the avatars case). The file carries no real data and writes nothing that survives.
--
-- closes-diagnose: d8f2a6

DO $v$
DECLARE
  v_n           uuid;
  v_other       uuid := '00000000-0000-0000-0000-0000000d8f2a'::uuid;  -- a folder name that is not N's
  v_results     text := '';
  v_rows        int;
  v_state       text;
  v_msg         text;
  v_photo_id    uuid := gen_random_uuid();
  v_before_photos bigint;
  v_count       int;
  v_txt         text;
BEGIN
  -- N: a real user with no subscription and no photo, picked as postgres before any role switch.
  SELECT u.id INTO v_n
    FROM public.users u
    JOIN auth.users a ON a.id = u.id
   WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.user_id = u.id)
     AND NOT EXISTS (SELECT 1 FROM public.progress_photos p WHERE p.user_id = u.id)
   ORDER BY u.id
   LIMIT 1;
  IF v_n IS NULL THEN
    RAISE EXCEPTION 'VERIFY_ABORT no borrowable user (a public.users row with no subscription and no photo)';
  END IF;
  SELECT count(*) INTO v_before_photos FROM public.progress_photos;

  -- V0: N starts with no subscription row and no photo.
  IF EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = v_n)
     OR EXISTS (SELECT 1 FROM public.progress_photos WHERE user_id = v_n) THEN
    v_results := v_results || E'V0=fail (N is not clean)\n';
  ELSE
    v_results := v_results || E'V0=ok\n';
  END IF;

  -- V1: no subscription row -> the progress_photos INSERT raises P0001 progress_photo_pro_required.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_n, v_n::text || '/v1.jpg', now());
    RESET ROLE;
    v_results := v_results || E'V1=fail (the photo INSERT was not refused)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0001' AND v_msg = 'progress_photo_pro_required' THEN
      v_results := v_results || E'V1=ok\n';
    ELSE
      v_results := v_results || 'V1=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V2: no subscription row -> the Storage INSERT (own folder) raises 42501.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('progress-photos', v_n::text || '/v2.jpg', v_n::text);
    RESET ROLE;
    v_results := v_results || E'V2=fail (the Storage INSERT was not refused)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = '42501' THEN
      v_results := v_results || E'V2=ok\n';
    ELSE
      v_results := v_results || 'V2=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- Seed: active, expires in 30 days (a synthetic row for N; the only trigger on the table sets cancelled_at locally).
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)
    VALUES (v_n, 'monthly', 'active', now(), now() + interval '30 days');

  -- V3a: active -> the photo INSERT succeeds (ROW_COUNT 1): not a false refusal for a payer.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (v_photo_id, v_n, v_n::text || '/v3.jpg', now());
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    IF v_rows = 1 THEN
      v_results := v_results || E'V3a=ok\n';
    ELSE
      v_results := v_results || 'V3a=fail (row count ' || v_rows || E')\n';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'V3a=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- V3b: active -> the Storage INSERT under N's own folder succeeds (ROW_COUNT 1).
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('progress-photos', v_n::text || '/v3.jpg', v_n::text);
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    IF v_rows = 1 THEN
      v_results := v_results || E'V3b=ok\n';
    ELSE
      v_results := v_results || 'V3b=fail (row count ' || v_rows || E')\n';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'V3b=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- V3c: active -> a Storage INSERT under ANOTHER user's folder is still refused (42501): the pre-existing condition holds.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('progress-photos', v_other::text || '/v3c.jpg', v_n::text);
    RESET ROLE;
    v_results := v_results || E'V3c=fail (an INSERT under another user''s folder was not refused)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = '42501' THEN
      v_results := v_results || E'V3c=ok\n';
    ELSE
      v_results := v_results || 'V3c=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V3d: active -> a Storage INSERT into the AVATARS bucket under another user's folder is refused (42501):
  -- catches the AND -> OR widening (a PRO user could otherwise write into any bucket under any folder).
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('avatars', v_other::text || '/v3d.jpg', v_n::text);
    RESET ROLE;
    v_results := v_results || E'V3d=fail (a PRO user could write into another bucket under another folder)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = '42501' THEN
      v_results := v_results || E'V3d=ok\n';
    ELSE
      v_results := v_results || 'V3d=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V3e: active -> the INSERT as the SESSION role with NO JWT (auth.uid() is NULL, as for a service-role writer) succeeds
  -- for N: the trigger reads NEW.user_id, not auth.uid(). A function that read auth.uid() would refuse every payer
  -- written by a service-role client (V3a runs with the JWT set, so it cannot see this). The row is deleted again so
  -- the photo counts of V4 are unchanged.
  BEGIN
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_n, v_n::text || '/v3e.jpg', now());
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    DELETE FROM public.progress_photos WHERE user_id = v_n AND storage_path = v_n::text || '/v3e.jpg';
    IF v_rows = 1 THEN
      v_results := v_results || E'V3e=ok\n';
    ELSE
      v_results := v_results || 'V3e=fail (row count ' || v_rows || E')\n';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'V3e=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- V3f: active -> a ROW for ANOTHER user is refused although the caller is a payer (Hermes L22 F1). Either refusal is
  -- the rule holding: 42501 before migration 154 (the table's own-row policy), P0001 after it (the trigger reads the
  -- OTHER user's subscriptions row under the caller's RLS, sees none, and refuses first). The case is `ok` before and
  -- after; it pins that a forged user_id is never ACCEPTED, and the SQLSTATE is recorded for the debugger.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_other, v_other::text || '/v3f.jpg', now());
    RESET ROLE;
    v_results := v_results || E'V3f=fail (a payer inserted a row for ANOTHER user)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state IN ('42501', 'P0001') THEN
      v_results := v_results || E'V3f=ok\n';
    ELSE
      v_results := v_results || 'V3f=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V4: the subscription lapses (status expired, end_date a day ago) with the V3 photo and object already present:
  -- the lapsed user can still SELECT and DELETE the photo row and still SELECT the object (decision 6),
  -- and can no longer INSERT either.
  UPDATE public.subscriptions
     SET status = 'expired', end_date = now() - interval '1 day'
   WHERE user_id = v_n;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    SELECT count(*) INTO v_count FROM public.progress_photos WHERE user_id = v_n;
    RESET ROLE;
    IF v_count = 1 THEN
      v_results := v_results || E'V4a=ok\n';
    ELSE
      v_results := v_results || 'V4a=fail (a lapsed user sees ' || v_count || E' photo rows, expected 1)\n';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'V4a=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    SELECT count(*) INTO v_count FROM storage.objects
     WHERE bucket_id = 'progress-photos' AND name = v_n::text || '/v3.jpg';
    RESET ROLE;
    IF v_count = 1 THEN
      v_results := v_results || E'V4b=ok\n';
    ELSE
      v_results := v_results || 'V4b=fail (a lapsed user sees ' || v_count || E' objects, expected 1)\n';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'V4b=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_n, v_n::text || '/v4c.jpg', now());
    RESET ROLE;
    v_results := v_results || E'V4c=fail (a lapsed user could INSERT a photo)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0001' AND v_msg = 'progress_photo_pro_required' THEN
      v_results := v_results || E'V4c=ok\n';
    ELSE
      v_results := v_results || 'V4c=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('progress-photos', v_n::text || '/v4d.jpg', v_n::text);
    RESET ROLE;
    v_results := v_results || E'V4d=fail (a lapsed user could INSERT a Storage object)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = '42501' THEN
      v_results := v_results || E'V4d=ok\n';
    ELSE
      v_results := v_results || 'V4d=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    DELETE FROM public.progress_photos WHERE user_id = v_n;
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    IF v_rows = 1 THEN
      v_results := v_results || E'V4e=ok\n';
    ELSE
      v_results := v_results || 'V4e=fail (a lapsed user deleted ' || v_rows || E' photo rows, expected 1)\n';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'V4e=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- V4f: the trigger is not an RLS check: the INSERT as the SESSION role (`postgres`, which bypasses RLS, as does
  -- service_role) for a lapsed user is refused too. A function that read auth.uid() instead of NEW.user_id, or one
  -- that returned early for a non-`authenticated` role, would pass the cases above. (The first reads a NULL uid here
  -- and refuses, as it should, so it is caught by V3e, the payer written without a JWT; the second is caught here.)
  BEGIN
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_n, v_n::text || '/v4f.jpg', now());
    v_results := v_results || E'V4f=fail (an INSERT as the session role for a lapsed user was accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0001' AND v_msg = 'progress_photo_pro_required' THEN
      v_results := v_results || E'V4f=ok\n';
    ELSE
      v_results := v_results || 'V4f=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V5a: status cancelled with a FUTURE end_date -> the photo INSERT is refused (the status conjunct; matches verify-subscription).
  UPDATE public.subscriptions
     SET status = 'cancelled', end_date = now() + interval '30 days'
   WHERE user_id = v_n;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_n, v_n::text || '/v5.jpg', now());
    RESET ROLE;
    v_results := v_results || E'V5a=fail (a cancelled subscription was accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0001' AND v_msg = 'progress_photo_pro_required' THEN
      v_results := v_results || E'V5a=ok\n';
    ELSE
      v_results := v_results || 'V5a=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V5b: the same state -> the Storage INSERT is refused too (the Storage policy carries its OWN copy of the status conjunct).
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('progress-photos', v_n::text || '/v5b.jpg', v_n::text);
    RESET ROLE;
    v_results := v_results || E'V5b=fail (a cancelled subscription was accepted by the Storage door)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = '42501' THEN
      v_results := v_results || E'V5b=ok\n';
    ELSE
      v_results := v_results || 'V5b=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V6a: status active with an end_date a minute in the PAST -> the photo INSERT is refused (the end-date conjunct).
  UPDATE public.subscriptions
     SET status = 'active', end_date = now() - interval '1 minute'
   WHERE user_id = v_n;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_n, v_n::text || '/v6.jpg', now());
    RESET ROLE;
    v_results := v_results || E'V6a=fail (an expired end_date was accepted)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0001' AND v_msg = 'progress_photo_pro_required' THEN
      v_results := v_results || E'V6a=ok\n';
    ELSE
      v_results := v_results || 'V6a=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V6b: the same state -> the Storage INSERT is refused too (the Storage policy carries its OWN copy of the end-date conjunct).
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('progress-photos', v_n::text || '/v6b.jpg', v_n::text);
    RESET ROLE;
    v_results := v_results || E'V6b=fail (an expired end_date was accepted by the Storage door)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = '42501' THEN
      v_results := v_results || E'V6b=ok\n';
    ELSE
      v_results := v_results || 'V6b=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V6c: status active with end_date EXACTLY now() -> the photo INSERT is refused. now() is the transaction start, so
  -- inside this block end_date = now() and the predicate is `end_date > now()` = false; a `>=` would accept it.
  UPDATE public.subscriptions
     SET status = 'active', end_date = now()
   WHERE user_id = v_n;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_n, v_n::text || '/v6c.jpg', now());
    RESET ROLE;
    v_results := v_results || E'V6c=fail (end_date = now() was accepted by the row door)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = 'P0001' AND v_msg = 'progress_photo_pro_required' THEN
      v_results := v_results || E'V6c=ok\n';
    ELSE
      v_results := v_results || 'V6c=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V6d: the same state -> the Storage INSERT is refused too (the policy has its own `end_date > now()`).
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('progress-photos', v_n::text || '/v6d.jpg', v_n::text);
    RESET ROLE;
    v_results := v_results || E'V6d=fail (end_date = now() was accepted by the Storage door)\n';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    IF v_state = '42501' THEN
      v_results := v_results || E'V6d=ok\n';
    ELSE
      v_results := v_results || 'V6d=fail (' || v_state || ' ' || v_msg || E')\n';
    END IF;
  END;

  -- V7a (negative control, no DDL): back to active and future -> the photo INSERT succeeds again, ROW_COUNT 1.
  -- Proves V1 and V4-V6 were refused BECAUSE of the predicate and not for another reason.
  UPDATE public.subscriptions
     SET status = 'active', end_date = now() + interval '30 days'
   WHERE user_id = v_n;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO public.progress_photos (id, user_id, storage_path, taken_at)
      VALUES (gen_random_uuid(), v_n, v_n::text || '/v7.jpg', now());
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    IF v_rows = 1 THEN
      v_results := v_results || E'V7a=ok\n';
    ELSE
      v_results := v_results || 'V7a=fail (row count ' || v_rows || E')\n';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'V7a=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- V7b (negative control for the Storage door): the same state -> the Storage INSERT succeeds, ROW_COUNT 1.
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_n)::text, true);
    PERFORM set_config('request.jwt.claim.sub', v_n::text, true);
    INSERT INTO storage.objects (bucket_id, name, owner_id)
      VALUES ('progress-photos', v_n::text || '/v7b.jpg', v_n::text);
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RESET ROLE;
    IF v_rows = 1 THEN
      v_results := v_results || E'V7b=ok\n';
    ELSE
      v_results := v_results || 'V7b=fail (row count ' || v_rows || E')\n';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_results := v_results || 'V7b=fail (' || v_state || ' ' || v_msg || E')\n';
  END;

  -- V8 (catalog): the policy and trigger shapes the rule depends on.
  -- V8a: exactly one INSERT policy named progress_photos_insert_own on storage.objects, permissive, role
  -- authenticated, whose with_check names the subscriptions table and the progress-photos bucket; AND it is the
  -- ONLY INSERT/ALL policy on storage.objects that mentions the progress-photos bucket (a second, narrower
  -- permissive policy would OR past the PRO conjunct for whatever it admits).
  SELECT count(*) INTO v_count
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'progress_photos_insert_own'
     AND cmd = 'INSERT' AND permissive = 'PERMISSIVE' AND roles = '{authenticated}'
     AND with_check LIKE '%subscriptions%' AND with_check LIKE '%progress-photos%';
  SELECT count(*) INTO v_rows
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND cmd IN ('INSERT', 'ALL')
     AND coalesce(with_check, '') || ' ' || coalesce(qual, '') LIKE '%progress-photos%';
  v_results := v_results || CASE WHEN v_count = 1 AND v_rows = 1 THEN E'V8a=ok\n'
    ELSE 'V8a=fail (' || v_count || ' matching policies, ' || v_rows || E' INSERT/ALL policies reach the bucket)\n' END;

  -- V8b: EVERY INSERT or ALL policy on storage.objects names a bucket_id = '<one bucket>' conjunct.
  SELECT count(*) INTO v_count
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND cmd IN ('INSERT', 'ALL')
     AND coalesce(with_check, qual, '') !~ 'bucket_id = ''[^'']+''';
  v_results := v_results || CASE WHEN v_count = 0 THEN E'V8b=ok\n' ELSE 'V8b=fail (' || v_count || E' unscoped INSERT/ALL policies)\n' END;

  -- V8c: EVERY UPDATE or ALL policy names a bucket_id conjunct in its qual (the rows it can touch) AND in the
  -- check applied to the NEW row, which is with_check when present and qual otherwise (a cross-bucket move is
  -- an UPDATE: a bucket-scoped qual with `WITH CHECK (true)` would let an avatars object land in progress-photos).
  SELECT count(*) INTO v_count
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND cmd IN ('UPDATE', 'ALL')
     AND (coalesce(qual, '') !~ 'bucket_id = ''[^'']+'''
          OR coalesce(with_check, qual, '') !~ 'bucket_id = ''[^'']+''');
  v_results := v_results || CASE WHEN v_count = 0 THEN E'V8c=ok\n' ELSE 'V8c=fail (' || v_count || E' unscoped UPDATE/ALL policies)\n' END;

  -- V8d: the SELECT and DELETE policies for the bucket are unchanged (E1 text), so view and delete stay open.
  SELECT count(*) INTO v_count
    FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname IN ('progress_photos_select_own', 'progress_photos_delete_own')
     AND qual = '((bucket_id = ''progress-photos''::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))';
  v_results := v_results || CASE WHEN v_count = 2 THEN E'V8d=ok\n' ELSE 'V8d=fail (' || v_count || E' of 2 unchanged)\n' END;

  -- V8e: the trigger is enabled, BEFORE INSERT, row level; the function pins its search path and is not a definer.
  SELECT count(*) INTO v_count
    FROM pg_trigger t
    JOIN pg_proc p ON p.oid = t.tgfoid
   WHERE t.tgname = 'trg_progress_photo_pro' AND NOT t.tgisinternal
     AND t.tgrelid = 'public.progress_photos'::regclass
     AND t.tgenabled = 'O'
     AND (t.tgtype & 1) = 1      -- row level
     AND (t.tgtype & 2) = 2      -- BEFORE
     AND (t.tgtype & 4) = 4      -- INSERT
     AND (t.tgtype & 24) = 0     -- not DELETE (8) or UPDATE (16)
     AND NOT p.prosecdef
     AND p.proconfig::text = '{"search_path=public, pg_temp"}';  -- EXACTLY these two schemas
  v_results := v_results || CASE WHEN v_count = 1 THEN E'V8e=ok\n' ELSE 'V8e=fail (' || v_count || E' matching triggers)\n' END;

  -- V8f: the table's four own-row policies are exactly the ones recorded as live evidence E1: command, roles, USING
  -- and WITH CHECK text, and there is no FIFTH policy on the table, compared with ALL whitespace removed (Postgres versions deparse a subquery as
  -- `(( SELECT ...)` or `((SELECT ...)`). A policy narrowed (USING (false)) or widened (USING (true)) no longer matches.
  SELECT count(*) INTO v_count
    FROM pg_policies p
    JOIN (VALUES
      ('progress_photos_select_own', 'SELECT', '((SELECT auth.uid() AS uid) = user_id)', NULL::text),
      ('progress_photos_insert_own', 'INSERT', NULL::text, '((SELECT auth.uid() AS uid) = user_id)'),
      ('progress_photos_update_own', 'UPDATE', '((SELECT auth.uid() AS uid) = user_id)', '((SELECT auth.uid() AS uid) = user_id)'),
      ('progress_photos_delete_own', 'DELETE', '((SELECT auth.uid() AS uid) = user_id)', NULL::text)
    ) AS e(policyname, cmd, qual, with_check)
      ON e.policyname = p.policyname AND e.cmd = p.cmd
     AND regexp_replace(coalesce(e.qual, '<none>'), '\s', '', 'g') = regexp_replace(coalesce(p.qual, '<none>'), '\s', '', 'g')
     AND regexp_replace(coalesce(e.with_check, '<none>'), '\s', '', 'g') = regexp_replace(coalesce(p.with_check, '<none>'), '\s', '', 'g')
   WHERE p.schemaname = 'public' AND p.tablename = 'progress_photos'
     AND p.permissive = 'PERMISSIVE' AND p.roles = '{public}';
  SELECT count(*) INTO v_rows FROM pg_policies WHERE schemaname = 'public' AND tablename = 'progress_photos';
  v_results := v_results || CASE WHEN v_count = 4 AND v_rows = 4 THEN E'V8f=ok\n'
    ELSE 'V8f=fail (' || v_count || ' of 4 own-row policies match the recorded text, ' || v_rows || E' policies on the table)\n' END;

  -- V9: public.subscriptions has exactly one policy, subscriptions_select_own for SELECT: no client write path.
  SELECT count(*) INTO v_count
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'subscriptions';
  SELECT string_agg(policyname || ':' || cmd, ',' ORDER BY policyname) INTO v_txt
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'subscriptions';
  v_results := v_results || CASE WHEN v_count = 1 AND v_txt = 'subscriptions_select_own:SELECT' THEN E'V9=ok\n'
                                 ELSE 'V9=fail (' || coalesce(v_txt, 'none') || E')\n' END;

  -- Always abort: nothing above commits. The results are the error text.
  RAISE EXCEPTION 'VERIFY_RESULTS (photos before=%)%', v_before_photos, E'\n' || v_results;
END
$v$;

-- ── Residue read (run as a SECOND execute_sql call after the abort; read-only) ─────────────────────────
-- The block above aborted, so nothing it wrote can remain. The borrowed user's id is not printed (no real
-- id is written down), so the check is by the shapes the block writes:
--
--   SELECT
--     (SELECT count(*) FROM public.progress_photos) AS photos_now,                         -- >= the "photos before" figure in the error text (the live PRO user may upload meanwhile)
--     (SELECT count(*) FROM public.progress_photos
--        WHERE storage_path LIKE '%/v3.jpg' OR storage_path LIKE '%/v7.jpg') AS seed_photos_left,   -- 0
--     (SELECT count(*) FROM storage.objects
--        WHERE bucket_id = 'progress-photos' AND name LIKE '%/v3.jpg') AS seed_objects_left,        -- 0
--     (SELECT count(*) FROM public.subscriptions
--        WHERE plan = 'monthly' AND razorpay_payment_id IS NULL AND razorpay_order_id IS NULL
--          AND created_at > now() - interval '15 minutes') AS seed_subscriptions_left;             -- 0 unless a real grant landed in the window
