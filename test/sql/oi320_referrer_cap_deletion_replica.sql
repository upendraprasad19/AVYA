-- test/sql/oi320_referrer_cap_deletion_replica.sql
--
-- REPLICA ONLY. Account deletion DELETEs rows from public.users (cascading to subscriptions and to
-- referral_redemptions), so this file must never be pointed at the live project. It refuses to run unless the table
-- public.oi320_replica_marker exists (created by test/sql/oi320_referrer_cap_replica_schema.sql; the live project does
-- not have it). A user-count threshold cannot tell the 20-user replica from the 43-user live project (round-2 review).
--
-- WHAT IT PROVES (round-1 review of docs/plans/oi320-referrer-cap.md, a P1). delete-account ends in
-- auth.admin.deleteUser, which cascades through public.users to every foreign key. Before migration 158
-- referral_redemptions.referee_id was ON DELETE CASCADE, so a throwaway referee that redeemed a referrer's code and
-- then deleted its own account took its credited audit row with it and freed one of that referrer's 7 slots: three
-- deletions turned 7 credits into 10. Migration 158 makes referee_id nullable with ON DELETE SET NULL, so the row
-- survives (referee_id reads NULL) and still counts.
--   K1 seven credited redemptions, then three referees are deleted: all seven audit rows remain, three of them
--      with referee_id NULL (UNIQUE(referee_id) tolerates the NULLs);
--   K2 the 8th redemption is STILL capped (flag false, referrer end_date unmoved) and its referee is credited;
--   K3 the deletion really cascaded elsewhere (the deleted referees' subscriptions are gone), so K1 is not
--      passing because nothing was deleted;
--   K4 deleting the REFERRER keeps the audit rows too (referrer_id reads NULL) and their referees keep their trials;
--   K5 and a referee whose referrer was deleted still cannot redeem a SECOND code: UNIQUE(referee_id) survives, so
--      burner referrers that delete themselves are not a farm for the referee side (round-2 review, reproduced:
--      with referrer_id ON DELETE CASCADE the referee's row vanished and a second redemption was credited);
--   K6 row-level security on those orphaned rows (hermes pass): the surviving party still reads its row, nobody else
--      does, and no authenticated user can UPDATE, DELETE or INSERT audit rows (the cap depends on it).
--
-- SHAPE. ONE `DO` block that ALWAYS aborts with `RAISE EXCEPTION 'VERIFY_RESULTS ...'` (same technique as
-- oi320_referrer_cap_live_verify.sql), so nothing survives. Every line must read `ok`. BEFORE migration 158 (the
-- live definition and the CASCADE foreign keys) K1, K2, K4 and K5 read `fail`; AFTER they read `ok`.
--
-- FIXTURES. 12 public.users rows holding no subscription and no redemption, picked by `ORDER BY id`.

DO $v$
DECLARE
  v_ids   uuid[];
  r       uuid;    -- the referrer under test
  e       uuid[];  -- referees e1..e8
  r3      uuid;    -- a second referrer, deleted at the end
  f       uuid[];  -- its two referees
  v_res   text := '';
  v_end   timestamptz;
  v_n     int;
  v_c     int;
  v_f1    boolean;
  v_dup   text;
  v_k6a   int;
  v_k6a2  int;
  v_k6b   int;
  v_k6c   int;
  v_k6d   int;
  v_k6u   int;
  v_k6x   int;
  v_k6i   text;
  v_code  text := 'AVYA-DELETE01';
  v_days  int  := 7;
  i       int;
BEGIN
  IF to_regclass('public.oi320_replica_marker') IS NULL THEN
    RAISE EXCEPTION 'REFUSED this file deletes users and runs only on the disposable replica (no public.oi320_replica_marker)';
  END IF;
  SELECT array_agg(id) INTO v_ids FROM (
    SELECT u.id
      FROM public.users u
     WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.user_id = u.id)
       AND NOT EXISTS (SELECT 1 FROM public.referral_redemptions x WHERE x.referrer_id = u.id OR x.referee_id = u.id)
     ORDER BY u.id
     LIMIT 12) t;
  IF coalesce(array_length(v_ids, 1), 0) < 12 THEN
    RAISE EXCEPTION 'NEED_FIXTURES need 12 users with no subscription and no redemption, found %', coalesce(array_length(v_ids, 1), 0);
  END IF;
  r := v_ids[1];
  e := v_ids[2:9];
  r3 := v_ids[10];
  f := v_ids[11:12];

  FOR i IN 1..7 LOOP
    PERFORM public.redeem_referral_atomic(v_code, r, e[i], v_days);
  END LOOP;
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';

  -- Three referees delete their accounts.
  DELETE FROM public.users WHERE id = ANY (e[1:3]);

  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r AND referrer_rewarded;
  SELECT count(*) INTO v_c FROM public.referral_redemptions WHERE referrer_id = r AND referee_id IS NULL;
  v_res := v_res || format(E'\nK1 three referees deleted: all 7 credited audit rows remain, 3 with referee_id NULL  %s', CASE WHEN v_n = 7 AND v_c = 3 THEN 'ok' ELSE 'fail credited=' || v_n || ' null_referee=' || v_c END);

  PERFORM public.redeem_referral_atomic(v_code, r, e[8], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = e[8];
  v_res := v_res || format(E'\nK2 the 8th redemption after the deletions is still capped (flag false, end_date unmoved), the referee credited  %s',
    CASE WHEN v_f1 IS NOT DISTINCT FROM false
          AND (SELECT max(end_date) FROM public.subscriptions WHERE user_id = r AND status = 'active') = v_end
          AND (SELECT count(*) FROM public.subscriptions WHERE user_id = e[8] AND plan = 'referral_trial' AND status = 'active' AND end_date = now() + interval '7 days') = 1
         THEN 'ok' ELSE 'fail flag=' || coalesce(v_f1::text, 'null') END);

  SELECT count(*) INTO v_n FROM public.subscriptions WHERE user_id = ANY (e[1:3]);
  v_res := v_res || format(E'\nK3 the deletion cascaded elsewhere: the deleted referees hold no subscription  %s', CASE WHEN v_n = 0 THEN 'ok' ELSE 'fail got=' || v_n END);

  -- A deleted REFERRER: the audit rows stay (referrer_id NULL) and the referees keep their trials.
  PERFORM public.redeem_referral_atomic(v_code, r3, f[1], v_days);
  PERFORM public.redeem_referral_atomic(v_code, r3, f[2], v_days);
  DELETE FROM public.users WHERE id = r3;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referee_id = ANY (f) AND referrer_id IS NULL;
  SELECT count(*) INTO v_c FROM public.subscriptions WHERE user_id = ANY (f) AND plan = 'referral_trial' AND status = 'active';
  v_res := v_res || format(E'\nK4 a deleted referrer: the 2 audit rows stay with referrer_id NULL, their referees keep their trials  %s', CASE WHEN v_n = 2 AND v_c = 2 THEN 'ok' ELSE 'fail null_referrer_rows=' || v_n || ' trials=' || v_c END);

  -- ... and a referee of that deleted referrer cannot redeem a SECOND code (UNIQUE(referee_id) still holds).
  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, r, f[1], v_days);
    v_dup := 'no exception';
  EXCEPTION WHEN unique_violation THEN
    v_dup := 'unique_violation';
  END;
  v_res := v_res || format(E'\nK5 a referee whose referrer was deleted cannot redeem a second code  %s', CASE WHEN v_dup = 'unique_violation' THEN 'ok' ELSE 'fail got=' || v_dup END);

  -- K6. Row-level security on the ORPHANED rows. The replica carries the live shape (RLS on, ONE select policy
  --     "Users can read own redemptions", full table grants to anon/authenticated). A row whose other party was deleted
  --     must stay visible to the surviving party and to nobody else, and no authenticated user may rewrite or delete
  --     their own audit rows (the cap holds only while that is true).
  PERFORM set_config('request.jwt.claim.sub', f[1]::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_k6a FROM public.referral_redemptions;
  SELECT count(*) INTO v_k6a2 FROM public.referral_redemptions WHERE referee_id = f[1] AND referrer_id IS NULL;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', r::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_k6b FROM public.referral_redemptions WHERE referee_id IS NULL;
  UPDATE public.referral_redemptions SET referrer_rewarded = false WHERE referrer_id = r;
  GET DIAGNOSTICS v_k6u = ROW_COUNT;
  DELETE FROM public.referral_redemptions WHERE referrer_id = r;
  GET DIAGNOSTICS v_k6x = ROW_COUNT;
  BEGIN
    INSERT INTO public.referral_redemptions (code, referrer_id, referee_id) VALUES ('AVYA-K6', r, NULL);
    v_k6i := 'inserted';
  EXCEPTION WHEN insufficient_privilege THEN
    v_k6i := 'denied';
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_k6c FROM public.referral_redemptions;
  RESET ROLE;
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_k6d FROM public.referral_redemptions;
  RESET ROLE;
  v_res := v_res || format(E'\nK6 RLS on the orphaned rows: a referee of a deleted referrer sees exactly its own row, a referrer sees the 3 NULL-referee rows, an unrelated user and anon see none, own-row UPDATE and DELETE touch 0 rows and an INSERT is refused  %s',
    CASE WHEN v_k6a = 1 AND v_k6a2 = 1 AND v_k6b = 3 AND v_k6c = 0 AND v_k6d = 0 AND v_k6u = 0 AND v_k6x = 0 AND v_k6i = 'denied' THEN 'ok'
         ELSE 'fail own=' || v_k6a || '/' || v_k6a2 || ' nullref=' || v_k6b || ' unrelated=' || v_k6c || ' anon=' || v_k6d || ' upd=' || v_k6u || ' del=' || v_k6x || ' ins=' || v_k6i END);

  RAISE EXCEPTION 'VERIFY_RESULTS%', v_res;
END
$v$;
