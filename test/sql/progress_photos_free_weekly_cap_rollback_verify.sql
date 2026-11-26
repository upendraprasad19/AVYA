-- test/sql/progress_photos_free_weekly_cap_rollback_verify.sql
--
-- Live-Postgres proof that the progress-photos free weekly cap's inline ROLLBACK runs and restores migration
-- 154's state (OI-348 Landing 3c; Hermes seat B, finding 1: the rollback had never run against an EXISTING
-- trigger on storage.objects, a table owned by supabase_storage_admin, so the emergency lever was unproven).
--
-- SHAPE. ONE DO block that ALWAYS aborts with RAISE EXCEPTION 'ROLLBACK_VERIFY_RESULTS ...'. It is run, with
-- the founder's go, as the SECOND rehearsal, inside one statement after the forward block and the rollback:
--   DO $rh2$ BEGIN
--     EXECUTE <the draft's forward DO statement>;
--     EXECUTE <the draft's commented rollback DO statement, with the leading "-- " removed>;
--     EXECUTE <this DO statement>;
--   END $rh2$;
-- so all three roll back with this block's abort and nothing persists. Every line must read `ok`.
-- (Run plainly on the live database BEFORE the apply, it also reads all `ok`: that is 154's state today.)

DO $rv$
DECLARE
  v_r   text := '';
  v_cnt int;
  v_txt text;
  v_def boolean;
BEGIN
  -- R1: neither new trigger exists.
  SELECT count(*) INTO v_cnt FROM pg_trigger
   WHERE (tgname = 'trg_progress_photo_object_cap' AND tgrelid = 'storage.objects'::regclass)
      OR (tgname = 'trg_progress_photo_created_at_keep' AND tgrelid = 'public.progress_photos'::regclass);
  v_r := v_r || CASE WHEN v_cnt = 0 THEN E'R1=ok\n' ELSE 'R1=fail (' || v_cnt || E' trigger(s) left)\n' END;

  -- R2: none of the three new functions exists.
  SELECT count(*) INTO v_cnt FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('progress_photo_week_start', 'enforce_progress_photo_object_cap', 'keep_progress_photo_created_at');
  v_r := v_r || CASE WHEN v_cnt = 0 THEN E'R2=ok\n' ELSE 'R2=fail (' || v_cnt || E' function(s) left)\n' END;

  -- R3: 154's row trigger is still attached to its function.
  SELECT count(*) INTO v_cnt FROM pg_trigger
   WHERE tgname = 'trg_progress_photo_pro' AND tgrelid = 'public.progress_photos'::regclass;
  v_r := v_r || CASE WHEN v_cnt = 1 THEN E'R3=ok\n' ELSE 'R3=fail (' || v_cnt || E')\n' END;

  -- R4: the row function is SECURITY INVOKER again, with 154's body (subscriptions read, no week logic).
  SELECT p.prosecdef, p.prosrc INTO v_def, v_txt FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'enforce_progress_photo_pro';
  v_r := v_r || CASE WHEN v_def = false AND v_txt LIKE '%public.subscriptions%'
                           AND v_txt NOT LIKE '%progress_photo_week_start%' AND v_txt NOT LIKE '%advisory%'
                     THEN E'R4=ok\n' ELSE 'R4=fail (definer ' || coalesce(v_def::text, 'absent') || E')\n' END;

  -- R5: its ACL is the live one before the migration: EXECUTE for PUBLIC (so anon and authenticated) and service_role.
  SELECT count(*) INTO v_cnt FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'enforce_progress_photo_pro'
     AND has_function_privilege('anon', p.oid, 'execute')
     AND has_function_privilege('authenticated', p.oid, 'execute')
     AND has_function_privilege('service_role', p.oid, 'execute');
  v_r := v_r || CASE WHEN v_cnt = 1 THEN E'R5=ok\n' ELSE E'R5=fail (EXECUTE not restored)\n' END;

  -- R6: the Storage INSERT policy carries 154's subscription conjunct and the own-folder test again.
  SELECT with_check INTO v_txt FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'progress_photos_insert_own';
  v_r := v_r || CASE WHEN v_txt LIKE '%subscriptions%' AND v_txt LIKE '%foldername%' AND v_txt LIKE '%end_date%'
                     THEN E'R6=ok\n' ELSE 'R6=fail (' || coalesce(v_txt, 'absent') || E')\n' END;

  RAISE EXCEPTION 'ROLLBACK_VERIFY_RESULTS%', E'\n' || v_r;
END
$rv$;
