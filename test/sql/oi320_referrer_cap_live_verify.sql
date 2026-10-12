-- test/sql/oi320_referrer_cap_live_verify.sql
--
-- Behavioural verification of the per-referrer referral cap (migration 158, OI-320, founder decision
-- 2026-10-11: 7 CREDITED referrals per referrer in any rolling 90 days; the referee is always credited).
-- Plan: docs/plans/oi320-referrer-cap.md.
--
-- WHAT IT PROVES. The Dart contract test (test/contracts/referral_referrer_cap_migration_test.dart) proves the
-- migration TEXT. It cannot prove what the function DOES. This file calls the real redeem_referral_atomic and
-- reads the resulting rows:
--   A  seven redemptions credit the referrer seven times (referral_trial inserted once, then +7 days six times:
--      end_date = now() + 49 days) and every audit row records referrer_rewarded = true, referee_rewarded = true;
--   B  the 8th is capped: the referrer's end_date does NOT move, the audit row reads referrer_rewarded = false /
--      referee_rewarded = true, and the REFEREE still receives a 7-day referral_trial;
--   C  a 9th is capped too, and uncredited rows do not enter the count;
--   G  a DIFFERENT referrer is unaffected by the first one's cap;
--   H  a duplicate referee still raises unique_violation and moves nothing (the Edge Function's 23505 path);
--   D  a credited row 89 days 23 h 59 min old still counts (still capped);
--   E  a credited row exactly 90 days old no longer counts (strict >): the next redemption credits again, although the
--      referrer is also the REFEREE of a credited row (that row does not count against them as a referrer);
--   F  after every credited row ages out, the next redemption credits although SEVEN uncredited rows are still in
--      the window (the lock-out expires 90 days after the 7th CREDIT, it does not grow with further attempts);
--   M  credited rows whose referee_id is NULL (what account deletion leaves under ON DELETE SET NULL, simulated by an
--      UPDATE inside the aborting block: no user is deleted) still count: the next redemption is capped, also when it
--      comes through a DIFFERENT code of the same referrer (the cap is per referrer, not per code);
--   R  a capped redemption whose referee ALREADY holds an active subscription still extends it by 7 days (the referee
--      is credited in the EXTEND branch too, not only when a new trial row is inserted);
--   J  a capped referrer whose own subscription has EXPIRED is neither re-trialled nor extended, and the referee is
--      still credited (the cap guards the insert branch as well as the extend branch);
--   L  a NULL referee (L1) and a NULL referrer (L2) are each refused by the function's own guard (message 'required'),
--      before anything is written;
--   I  the catalog: SECURITY DEFINER, search_path=public, RETURNS void, EXECUTE for service_role only, I7 the table has
--      RLS on and NO write policy for anon / authenticated / PUBLIC (so a user cannot rewrite or delete their own audit
--      rows, which would reopen the cap), and
--      schema change of plan-review rounds 1 and 2: referrer_id and referee_id are nullable and EVERY foreign key of
--      the table to users is ON DELETE SET NULL (so deleting an account cannot reopen the cap or a referee's
--      one-code-ever guard; the deletions themselves are exercised by oi320_referrer_cap_deletion_replica.sql).
-- The concurrency half (two sessions, one referrer; two sessions redeeming each other) cannot run in one
-- transaction: see test/sql/oi320_referrer_cap_concurrency_local.sh. Account deletion deletes real users, so it
-- lives in a REPLICA-ONLY file: test/sql/oi320_referrer_cap_deletion_replica.sql.
--
-- SHAPE. ONE `DO` block that ALWAYS aborts with `RAISE EXCEPTION 'VERIFY_RESULTS ...'`, so the transaction never
-- commits and nothing is left open or locked; results are read from the error text (the technique of
-- test/sql/progress_photos_pro_insert_rule_live_verify.sql; no explicit BEGIN ... ROLLBACK, because on a
-- mid-message error through execute_sql the trailing ROLLBACK is skipped). Every line must read `ok`.
--
-- NO DDL. Writes only rows, all inside the aborting block: referral_redemptions, subscriptions.
-- now() is constant inside a transaction, so every end_date expectation is exact (no tolerance).
--
-- FIXTURES. 19 existing public.users rows that hold NO subscription and appear in NO redemption, picked by
-- `ORDER BY id`; no user id is written to this file. On a live run these are real users: their rows are
-- touched only inside the aborting block. Needs 19 (36 existed live on 2026-10-11); fewer aborts with a message that
-- is not VERIFY_RESULTS.
--
-- RUN. LIVE: only with the founder's go, through execute_sql (project dedsavbjuwgarrhphgnl), before AND after the
-- apply: BEFORE (the old body) reads `fail` on A1, A2, B1, B2, C1, D1, E1, F1, F2, G1, H2, J1, L1, L2, M1, R1, I5 and I6
-- and `ok` on A3, A4, B3, H1, J2 and I1-I4; AFTER reads `ok` on every line (28 lines; I7 reads ok before and after, it is a property of the table). LOCAL: against
-- the throwaway replica (test/sql/oi320_referrer_cap_replica_schema.sql), see the plan, section 3.

DO $v$
DECLARE
  v_ids   uuid[];
  r       uuid;   -- the referrer under test
  r2      uuid;   -- a second referrer
  v_e     uuid[]; -- referees e1..e17 = v_ids[3..19]
  v_res   text := '';
  v_end   timestamptz;
  v_end_b timestamptz;
  v_end_b2 timestamptz;
  v_n     int;
  v_c     int;
  v_f1    boolean;
  v_f2    boolean;
  v_oldest uuid;
  v_acl   text;
  v_cfg   text[];
  v_msg   text;
  v_code  text := 'AVYA-VERIFY01';
  v_code2 text := 'AVYA-VERIFY02'; -- a SECOND code of the same referrer (codes expire and regenerate): the cap is per referrer, not per code
  v_days  int  := 7;
  i       int;
BEGIN
  SELECT array_agg(id) INTO v_ids FROM (
    SELECT u.id
      FROM public.users u
     WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.user_id = u.id)
       AND NOT EXISTS (SELECT 1 FROM public.referral_redemptions x WHERE x.referrer_id = u.id OR x.referee_id = u.id)
     ORDER BY u.id
     LIMIT 19) t;
  IF coalesce(array_length(v_ids, 1), 0) < 19 THEN
    RAISE EXCEPTION 'NEED_FIXTURES need 19 users with no subscription and no redemption, found %', coalesce(array_length(v_ids, 1), 0);
  END IF;
  r := v_ids[1];
  r2 := v_ids[2];
  v_e := v_ids[3:19];

  -- A. seven redemptions credit the referrer seven times.
  FOR i IN 1..7 LOOP
    PERFORM public.redeem_referral_atomic(v_code, r, v_e[i], v_days);
  END LOOP;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r AND referrer_rewarded;
  v_res := v_res || format(E'\nA1 seven audit rows carry referrer_rewarded=true  %s', CASE WHEN v_n = 7 THEN 'ok' ELSE 'fail got=' || v_n END);
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r AND referee_rewarded;
  v_res := v_res || format(E'\nA2 seven audit rows carry referee_rewarded=true  %s', CASE WHEN v_n = 7 THEN 'ok' ELSE 'fail got=' || v_n END);
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  v_res := v_res || format(E'\nA3 referrer end_date is now()+49 days (1 insert + 6 extensions)  %s', CASE WHEN v_end = now() + interval '49 days' THEN 'ok' ELSE 'fail got=' || coalesce(v_end::text, 'null') END);
  SELECT count(*) INTO v_n FROM public.subscriptions WHERE user_id = ANY (v_e[1:7]) AND plan = 'referral_trial' AND status = 'active' AND end_date = now() + interval '7 days';
  v_res := v_res || format(E'\nA4 each of the 7 referees holds a 7-day referral_trial  %s', CASE WHEN v_n = 7 THEN 'ok' ELSE 'fail got=' || v_n END);
  v_end_b := v_end;

  -- B. the 8th is capped; the referee is still credited.
  PERFORM public.redeem_referral_atomic(v_code, r, v_e[8], v_days);
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  v_res := v_res || format(E'\nB1 capped: referrer end_date did not move  %s', CASE WHEN v_end = v_end_b THEN 'ok' ELSE 'fail got=' || coalesce(v_end::text, 'null') || ' want=' || v_end_b END);
  SELECT referrer_rewarded, referee_rewarded INTO v_f1, v_f2 FROM public.referral_redemptions WHERE referee_id = v_e[8];
  v_res := v_res || format(E'\nB2 capped: audit row is referrer_rewarded=false, referee_rewarded=true  %s', CASE WHEN v_f1 IS NOT DISTINCT FROM false AND v_f2 IS NOT DISTINCT FROM true THEN 'ok' ELSE 'fail got=' || coalesce(v_f1::text, 'null') || '/' || coalesce(v_f2::text, 'null') END);
  SELECT count(*) INTO v_n FROM public.subscriptions WHERE user_id = v_e[8] AND plan = 'referral_trial' AND status = 'active' AND end_date = now() + interval '7 days';
  v_res := v_res || format(E'\nB3 capped: the referee still holds a 7-day referral_trial  %s', CASE WHEN v_n = 1 THEN 'ok' ELSE 'fail got=' || v_n END);

  -- C. a 9th is capped too.
  PERFORM public.redeem_referral_atomic(v_code, r, v_e[9], v_days);
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r AND referrer_rewarded;
  SELECT count(*) INTO v_c FROM public.referral_redemptions WHERE referrer_id = r;
  v_res := v_res || format(E'\nC1 9 redemptions, still 7 credited, end_date unmoved  %s', CASE WHEN v_n = 7 AND v_c = 9 AND v_end = v_end_b THEN 'ok' ELSE 'fail credited=' || v_n || ' total=' || v_c END);

  -- G. a different referrer is unaffected by R's cap.
  PERFORM public.redeem_referral_atomic(v_code, r2, v_e[14], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = v_e[14];
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r2 AND status = 'active';
  v_res := v_res || format(E'\nG1 a second referrer is credited while the first is capped  %s', CASE WHEN v_f1 IS NOT DISTINCT FROM true AND v_end = now() + interval '7 days' THEN 'ok' ELSE 'fail got=' || coalesce(v_f1::text, 'null') || '/' || coalesce(v_end::text, 'null') END);

  -- H. a duplicate referee still raises unique_violation and moves nothing.
  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, r, v_e[3], v_days);
    v_res := v_res || E'\nH1 duplicate referee raises unique_violation  fail (no exception)';
  EXCEPTION WHEN unique_violation THEN
    v_res := v_res || E'\nH1 duplicate referee raises unique_violation  ok';
  END;
  SELECT count(*) INTO v_c FROM public.referral_redemptions WHERE referrer_id = r;
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  v_res := v_res || format(E'\nH2 the failed duplicate moved nothing  %s', CASE WHEN v_c = 9 AND v_end = v_end_b THEN 'ok' ELSE 'fail total=' || v_c END);

  -- M. credited rows whose referee_id is NULL still count. Account deletion leaves exactly this under ON DELETE SET NULL;
  --    it is simulated by an UPDATE so the case is safe to run against real users. On the previous schema (referee_id
  --    NOT NULL) the UPDATE raises, is caught, and the case reads `fail`.
  v_n := 0;
  BEGIN
    UPDATE public.referral_redemptions SET referee_id = NULL WHERE referee_id = ANY (v_e[5:7]);
    GET DIAGNOSTICS v_n = ROW_COUNT;
  EXCEPTION WHEN not_null_violation THEN
    v_n := -1;
  END;
  PERFORM public.redeem_referral_atomic(v_code2, r, v_e[16], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = v_e[16];
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  v_res := v_res || format(E'\nM1 three credited rows with referee_id NULL still count, and a redemption through a DIFFERENT code of the same referrer is capped too (flag false, end_date unmoved)  %s', CASE WHEN v_n = 3 AND v_f1 IS NOT DISTINCT FROM false AND v_end = v_end_b THEN 'ok' ELSE 'fail nulled=' || v_n || ' flag=' || coalesce(v_f1::text, 'null') || ' end=' || coalesce(v_end::text, 'null') END);

  -- R. a capped redemption still extends a referee who ALREADY holds an active subscription.
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date) VALUES (v_e[17], 'referral_trial', 'active', now(), now() + interval '30 days');
  PERFORM public.redeem_referral_atomic(v_code, r, v_e[17], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = v_e[17];
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  SELECT max(end_date) INTO v_end_b2 FROM public.subscriptions WHERE user_id = v_e[17] AND status = 'active';
  v_res := v_res || format(E'\nR1 capped: the referrer is not credited AND a referee who already holds PRO is extended by 7 days  %s', CASE WHEN v_f1 IS NOT DISTINCT FROM false AND v_end = v_end_b AND v_end_b2 = now() + interval '37 days' THEN 'ok' ELSE 'fail flag=' || coalesce(v_f1::text, 'null') || ' referrer_end=' || coalesce(v_end::text, 'null') || ' referee_end=' || coalesce(v_end_b2::text, 'null') END);

  -- J. a capped referrer whose own subscription has EXPIRED is neither re-trialled nor extended.
  SELECT count(*) INTO v_n FROM public.subscriptions WHERE user_id = r;
  UPDATE public.subscriptions SET end_date = now() - interval '1 day' WHERE user_id = r AND status = 'active';
  PERFORM public.redeem_referral_atomic(v_code, r, v_e[15], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = v_e[15];
  SELECT count(*), max(end_date) INTO v_c, v_end FROM public.subscriptions WHERE user_id = r;
  v_res := v_res || format(E'\nJ1 capped, referrer subscription EXPIRED: no new trial, no extension (flag false, same row count, still expired)  %s', CASE WHEN v_f1 IS NOT DISTINCT FROM false AND v_c = v_n AND v_end = now() - interval '1 day' THEN 'ok' ELSE 'fail flag=' || coalesce(v_f1::text, 'null') || ' rows=' || v_c || '/' || v_n || ' end=' || coalesce(v_end::text, 'null') END);
  SELECT count(*) INTO v_n FROM public.subscriptions WHERE user_id = v_e[15] AND plan = 'referral_trial' AND status = 'active' AND end_date = now() + interval '7 days';
  v_res := v_res || format(E'\nJ2 capped, referrer subscription EXPIRED: the referee still holds a 7-day referral_trial  %s', CASE WHEN v_n = 1 THEN 'ok' ELSE 'fail got=' || v_n END);
  -- Restore the referrer's real row for the steps below (the previous body, which has no cap, also inserted a fresh trial row).
  UPDATE public.subscriptions SET end_date = v_end_b WHERE user_id = r AND end_date = now() - interval '1 day';

  -- L. a NULL referee is refused by the function's own guard, before anything is written.
  SELECT count(*) INTO v_c FROM public.referral_redemptions WHERE referrer_id = r;
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, r, NULL, v_days);
    v_msg := 'no exception';
  EXCEPTION WHEN not_null_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r;
  v_res := v_res || format(E'\nL1 a NULL referee raises 23502 from the function guard and writes nothing  %s', CASE WHEN v_msg LIKE '%required%' AND v_n = v_c AND (SELECT max(end_date) FROM public.subscriptions WHERE user_id = r AND status = 'active') = v_end THEN 'ok' ELSE 'fail msg=' || coalesce(v_msg, 'null') END);

  -- L2. a NULL referrer is refused by the other arm of the same guard.
  SELECT count(*) INTO v_c FROM public.referral_redemptions;
  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, NULL, v_e[13], v_days);
    v_msg := 'no exception';
  EXCEPTION WHEN not_null_violation THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  SELECT count(*) INTO v_n FROM public.referral_redemptions;
  v_res := v_res || format(E'\nL2 a NULL referrer raises 23502 from the function guard and writes nothing  %s', CASE WHEN v_msg LIKE '%required%' AND v_n = v_c THEN 'ok' ELSE 'fail msg=' || coalesce(v_msg, 'null') || ' rows=' || v_n || '/' || v_c END);

  -- D. a credited row 89 days 23 h 59 min old still counts.
  SELECT id INTO v_oldest FROM public.referral_redemptions WHERE referrer_id = r AND referrer_rewarded ORDER BY id LIMIT 1;
  UPDATE public.referral_redemptions SET created_at = now() - interval '89 days 23 hours 59 minutes' WHERE id = v_oldest;
  PERFORM public.redeem_referral_atomic(v_code, r, v_e[10], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = v_e[10];
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  v_res := v_res || format(E'\nD1 a credited row 89d23h59m old still counts (capped: flag false AND end_date unmoved)  %s', CASE WHEN v_f1 IS NOT DISTINCT FROM false AND v_end = v_end_b THEN 'ok' ELSE 'fail got=' || coalesce(v_f1::text, 'null') || '/' || coalesce(v_end::text, 'null') END);

  -- E. a credited row exactly 90 days old no longer counts (strict >). R is ALSO the referee of a credited row (the other
  --    party's flag is true): that row must not count against R as a referrer (the count is per referrer_id only). It is
  --    inserted directly, so no subscription moves.
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, referrer_rewarded, referee_rewarded, days_granted_each)
    VALUES (v_code, v_e[1], r, true, true, v_days);
  UPDATE public.referral_redemptions SET created_at = now() - interval '90 days' WHERE id = v_oldest;
  PERFORM public.redeem_referral_atomic(v_code, r, v_e[11], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = v_e[11];
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  v_res := v_res || format(E'\nE1 a credited row exactly 90d old is out of the window (credited again, +7 days), although R is also the referee of a credited row  %s', CASE WHEN v_f1 IS NOT DISTINCT FROM true AND v_end = v_end_b + interval '7 days' THEN 'ok' ELSE 'fail got=' || coalesce(v_f1::text, 'null') || '/' || coalesce(v_end::text, 'null') END);

  -- F. at the cap again, then every credited row ages out: uncredited rows must not hold the lock.
  PERFORM public.redeem_referral_atomic(v_code, r, v_e[12], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = v_e[12];
  SELECT max(end_date) INTO v_end FROM public.subscriptions WHERE user_id = r AND status = 'active';
  v_res := v_res || format(E'\nF1 back at 7 credited in the window, the next is capped (flag false AND end_date unmoved)  %s', CASE WHEN v_f1 IS NOT DISTINCT FROM false AND v_end = v_end_b + interval '7 days' THEN 'ok' ELSE 'fail got=' || coalesce(v_f1::text, 'null') || '/' || coalesce(v_end::text, 'null') END);
  -- Two of the old credited rows become uncredited rows INSIDE the window, so seven uncredited rows (the cap) sit in
  -- the window when the last credited row ages out: a count that included them would read 7 and cap the next one.
  UPDATE public.referral_redemptions SET referrer_rewarded = false, created_at = now() WHERE referee_id = ANY (v_e[1:2]);
  UPDATE public.referral_redemptions SET created_at = now() - interval '91 days' WHERE referrer_id = r AND referrer_rewarded;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r AND NOT referrer_rewarded AND created_at > now() - interval '90 days';
  PERFORM public.redeem_referral_atomic(v_code, r, v_e[13], v_days);
  SELECT referrer_rewarded INTO v_f1 FROM public.referral_redemptions WHERE referee_id = v_e[13];
  v_res := v_res || format(E'\nF2 uncredited rows in the window (%s) do not hold the lock: credited again  %s', v_n, CASE WHEN v_n >= 7 AND v_f1 IS NOT DISTINCT FROM true THEN 'ok' ELSE 'fail uncredited_in_window=' || v_n || ' flag=' || coalesce(v_f1::text, 'null') END);

  -- I. the catalog.
  SELECT p.proconfig, p.proacl::text INTO v_cfg, v_acl FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'redeem_referral_atomic';
  v_res := v_res || format(E'\nI1 SECURITY DEFINER  %s', CASE WHEN (SELECT prosecdef FROM pg_proc WHERE oid = 'public.redeem_referral_atomic(text,uuid,uuid,integer)'::regprocedure) THEN 'ok' ELSE 'fail' END);
  v_res := v_res || format(E'\nI2 search_path=public kept (migration 053)  %s', CASE WHEN v_cfg @> ARRAY['search_path=public'] THEN 'ok' ELSE 'fail got=' || coalesce(v_cfg::text, 'null') END);
  v_res := v_res || format(E'\nI3 RETURNS void  %s', CASE WHEN pg_get_function_result('public.redeem_referral_atomic(text,uuid,uuid,integer)'::regprocedure) = 'void' THEN 'ok' ELSE 'fail' END);
  v_res := v_res || format(E'\nI4 EXECUTE: service_role yes, anon/authenticated/PUBLIC no  %s',
    CASE WHEN has_function_privilege('service_role', 'public.redeem_referral_atomic(text,uuid,uuid,integer)', 'execute')
          AND NOT has_function_privilege('anon', 'public.redeem_referral_atomic(text,uuid,uuid,integer)', 'execute')
          AND NOT has_function_privilege('authenticated', 'public.redeem_referral_atomic(text,uuid,uuid,integer)', 'execute')
          AND v_acl !~ '(^|,|\{)=X'
         THEN 'ok' ELSE 'fail acl=' || coalesce(v_acl, 'null') END);

  v_res := v_res || format(E'\nI5 every foreign key of referral_redemptions to users is ON DELETE SET NULL, and there are exactly two (referrer_id, referee_id)  %s',
    CASE WHEN NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.referral_redemptions'::regclass AND contype = 'f' AND confdeltype <> 'n')
          AND (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.referral_redemptions'::regclass AND contype = 'f' AND confdeltype = 'n' AND confrelid = 'public.users'::regclass) = 2
         THEN 'ok'
         ELSE 'fail got=' || coalesce((SELECT string_agg(conname || ':' || confdeltype::text, ',') FROM pg_constraint WHERE conrelid = 'public.referral_redemptions'::regclass AND contype = 'f'), 'none') END);
  v_res := v_res || format(E'\nI6 referral_redemptions.referrer_id and referee_id are nullable  %s',
    CASE WHEN NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.referral_redemptions'::regclass AND attname IN ('referrer_id', 'referee_id') AND attnotnull) THEN 'ok' ELSE 'fail (NOT NULL)' END);
  v_res := v_res || format(E'\nI7 referral_redemptions: RLS is enabled and no INSERT/UPDATE/DELETE policy exists for anon, authenticated or PUBLIC (the cap holds only while a user cannot rewrite their own audit rows)  %s',
    CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.referral_redemptions'::regclass)
          AND NOT EXISTS (SELECT 1 FROM pg_policy pp WHERE pp.polrelid = 'public.referral_redemptions'::regclass AND pp.polcmd <> 'r'
                           AND (pp.polroles = '{0}'::oid[] OR EXISTS (SELECT 1 FROM pg_roles rl WHERE rl.oid = ANY (pp.polroles) AND rl.rolname IN ('anon', 'authenticated'))))
         THEN 'ok'
         ELSE 'fail rls=' || coalesce((SELECT relrowsecurity::text FROM pg_class WHERE oid = 'public.referral_redemptions'::regclass), 'null') || ' policies=' || coalesce((SELECT string_agg(polname || ':' || polcmd::text, ',') FROM pg_policy WHERE polrelid = 'public.referral_redemptions'::regclass), 'none') END);

  RAISE EXCEPTION 'VERIFY_RESULTS%', v_res;
END
$v$;
