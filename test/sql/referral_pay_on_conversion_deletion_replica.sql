-- test/sql/referral_pay_on_conversion_deletion_replica.sql
--
-- REPLICA ONLY. Account deletion DELETEs rows from public.users (cascading to subscriptions, and SET NULL on
-- referral_redemptions), so this file must never be pointed at the live project. It refuses to run unless the table
-- public.rpoc_replica_marker exists (created LAST by test/sql/referral_pay_on_conversion_replica_schema.sql; the live project
-- does not have it). Successor of test/sql/oi320_referrer_cap_deletion_replica.sql: its K1 and K2 were CAP cases (gone with
-- the cap); K3 to K6 carry over, re-pointed at the reward-on-conversion rule.
--
-- WHAT IT PROVES.
--   D1 a referee deleted BEFORE paying: the audit row stays with referee_id NULL, nothing is ever credited for it;
--   D2 a referee who PAID and is deleted before the vest: the payment row cascades away, the pending row is VOIDED by the
--      next run and the referrer is not credited (the deleted referee_id matches no payment);
--   D3 a CREDITED row whose referee is deleted afterwards stays credited and keeps its days (no clawback, nothing reset);
--   D4 a deleted REFERRER: the audit rows stay with referrer_id NULL, the referees keep their trials, the job never touches
--      them and writes no failed alert;
--   D5 a referee of a deleted referrer still cannot redeem a SECOND code (UNIQUE(referee_id) survives the SET NULL);
--   D6 row-level security on the orphaned rows, and on the NEW columns: the surviving party reads its row, an unrelated user
--      and anon read none, no authenticated user can UPDATE, DELETE or INSERT audit rows; no column of the table can carry a
--      payment id (the privacy rule of migration 159: one friend's Razorpay id must not become readable by the other);
--   D7 there is NO cap: nine redemptions for one referrer are all accepted and the referrer is rewarded for none of them
--      until a friend pays (the 158 cap, 7 per 90 days, is gone).
--
-- SHAPE. ONE `DO` block that ALWAYS aborts with `RAISE EXCEPTION 'VERIFY_RESULTS ...'` (same technique as
-- referral_pay_on_conversion_live_verify.sql), so nothing survives. Every line must read `ok`.
--
-- FIXTURES. 20 public.users rows holding no subscription and no redemption, picked by `ORDER BY id`. The job's own sweep
-- also looks at other rows in the replica; every assertion is on fixture rows.

DO $v$
DECLARE
  v_ids   uuid[];
  r       uuid;    -- the referrer of D1..D3, D6, D7
  e       uuid[];  -- referees e1..e9
  r3      uuid;    -- a second referrer, deleted in D4
  f       uuid[];  -- its two referees
  v_res   text := '';
  v_ret   jsonb;
  v_n     int;
  v_c     int;
  v_dup   text;
  v_k6a   int;
  v_k6a2  int;
  v_k6b   int;
  v_k6c   int;
  v_k6d   int;
  v_k6u   int;
  v_k6x   int;
  v_k6i   text;
  v_k6col int;
  v_k6new int;
  v_code  text := 'AVYA-DELETE01';
  i       int;
BEGIN
  IF to_regclass('public.rpoc_replica_marker') IS NULL THEN
    RAISE EXCEPTION 'REFUSED this file deletes users and runs only on the disposable replica (no public.rpoc_replica_marker)';
  END IF;
  SELECT array_agg(id) INTO v_ids FROM (
    SELECT u.id
      FROM public.users u
     WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.user_id = u.id)
       AND NOT EXISTS (SELECT 1 FROM public.referral_redemptions x WHERE x.referrer_id = u.id OR x.referee_id = u.id)
     ORDER BY u.id
     LIMIT 20) t;
  IF coalesce(array_length(v_ids, 1), 0) < 20 THEN
    RAISE EXCEPTION 'NEED_FIXTURES need 20 users with no subscription and no redemption, found %', coalesce(array_length(v_ids, 1), 0);
  END IF;
  r  := v_ids[1];
  e  := v_ids[2:10];
  r3 := v_ids[11];
  f  := v_ids[12:13];

  -- ---- D7 first (it uses e[1..9] as redeemers; they are deleted afterwards for D1..D3)
  FOR i IN 1..9 LOOP
    PERFORM public.redeem_referral_atomic(v_code, r, e[i], 7);
  END LOOP;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r;
  SELECT count(*) INTO v_c FROM public.subscriptions WHERE user_id = r;
  SELECT count(*) INTO v_k6u FROM public.subscriptions WHERE user_id = ANY (e) AND plan = 'referral_trial' AND status = 'active' AND end_date = now() + interval '7 days';
  v_res := v_res || format(E'\nD7 no cap: nine redemptions for one referrer are all accepted, all nine friends hold a 7-day trial, the referrer holds no subscription row and no flag reads true  %s',
    CASE WHEN v_n = 9 AND v_c = 0 AND v_k6u = 9
          AND NOT EXISTS (SELECT 1 FROM public.referral_redemptions WHERE referrer_id = r AND referrer_rewarded IS TRUE) THEN 'ok'
         ELSE 'fail audit=' || v_n || ' referrer_rows=' || v_c || ' trials=' || v_k6u END);

  -- ---- D1: e[1] deleted before paying.
  DELETE FROM public.users WHERE id = e[1];
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r AND referee_id IS NULL AND converted_at IS NULL AND referrer_rewarded IS NOT TRUE;
  v_res := v_res || format(E'\nD1 a referee deleted before paying: the audit row stays with referee_id NULL, never converted, never credited, the referrer holds no row  %s',
    CASE WHEN v_n = 1 AND NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = r) THEN 'ok' ELSE 'fail null_referee_rows=' || v_n END);

  -- ---- D2: e[2] pays 10 days ago (a pending row after the next run), then is deleted before the vest... the payment must be
  --          younger than 7 days for "before the vest": pay 4 days ago, run, delete, run.
  UPDATE public.referral_redemptions SET created_at = now() - interval '20 days' WHERE referee_id = e[2];
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (e[2], 'monthly', 'active', now() - interval '4 days', now() + interval '26 days', 'pay_del_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referee_id = e[2] AND converted_at IS NOT NULL AND referrer_rewarded IS NOT TRUE;
  v_c := v_n;   -- control: it WAS pending before the deletion
  DELETE FROM public.users WHERE id = e[2];
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referrer_id = r AND referee_id IS NULL AND converted_at IS NULL AND referrer_reward_days IS NULL AND referrer_rewarded IS NOT TRUE;
  v_res := v_res || format(E'\nD2 a referee that paid (pending) and is deleted before the vest: its payment cascades away, the pending row is VOIDED and the referrer is not credited (control: it was pending first)  %s',
    CASE WHEN v_c = 1 AND v_n = 2 AND NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = r) THEN 'ok' ELSE 'fail was_pending=' || v_c || ' voided_null_referee_rows=' || v_n END);

  -- ---- D3: e[3] pays 10 days ago, is credited, THEN is deleted.
  UPDATE public.referral_redemptions SET created_at = now() - interval '20 days' WHERE referee_id = e[3];
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (e[3], 'yearly', 'active', now() - interval '10 days', now() + interval '355 days', 'pay_del_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referee_id = e[3] AND referrer_rewarded IS TRUE AND referrer_reward_days = 30;
  v_c := v_n;
  DELETE FROM public.users WHERE id = e[3];
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.referral_redemptions
   WHERE referrer_id = r AND referee_id IS NULL AND referrer_rewarded IS TRUE AND referrer_reward_days = 30 AND referrer_credited_at = now() AND converted_at = now() - interval '10 days';
  v_res := v_res || format(E'\nD3 a CREDITED row whose referee is deleted afterwards stays credited with its days, converted_at and credited_at, and the referrer keeps the 30 days (control: credited before the deletion)  %s',
    CASE WHEN v_c = 1 AND v_n = 1 AND (SELECT max(end_date) = now() + interval '30 days' FROM public.subscriptions WHERE user_id = r) THEN 'ok' ELSE 'fail credited_before=' || v_c || ' kept=' || v_n END);

  -- ---- D4: a deleted REFERRER.
  PERFORM public.redeem_referral_atomic(v_code, r3, f[1], 7);
  PERFORM public.redeem_referral_atomic(v_code, r3, f[2], 7);
  UPDATE public.referral_redemptions SET created_at = now() - interval '20 days' WHERE referee_id = f[1];
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[1], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_del_' || gen_random_uuid());
  DELETE FROM public.users WHERE id = r3;
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referee_id = ANY (f) AND referrer_id IS NULL AND converted_at IS NULL AND referrer_rewarded IS NOT TRUE;
  SELECT count(*) INTO v_c FROM public.subscriptions WHERE user_id = ANY (f) AND plan = 'referral_trial' AND status = 'active';
  v_res := v_res || format(E'\nD4 a deleted referrer: the 2 audit rows stay with referrer_id NULL and unconverted (the paid friend included), the referees keep their trials, no failed alert names them  %s',
    CASE WHEN v_n = 2 AND v_c = 2
          AND NOT EXISTS (SELECT 1 FROM public.alerts a WHERE a.source = 'referral_conversions_failed' AND a.detected_at = now()) THEN 'ok'
         ELSE 'fail null_referrer_rows=' || v_n || ' trials=' || v_c END);

  -- ---- D5: ... and a referee of that deleted referrer cannot redeem a SECOND code.
  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, r, f[2], 7);
    v_dup := 'no exception';
  EXCEPTION WHEN unique_violation THEN
    v_dup := 'unique_violation';
  END;
  v_res := v_res || format(E'\nD5 a referee whose referrer was deleted cannot redeem a second code  %s', CASE WHEN v_dup = 'unique_violation' THEN 'ok' ELSE 'fail got=' || v_dup END);

  -- ---- D6: row-level security on the orphaned rows and on the new columns.
  PERFORM set_config('request.jwt.claim.sub', f[1]::text, true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_k6a FROM public.referral_redemptions;
  SELECT count(*) INTO v_k6a2 FROM public.referral_redemptions WHERE referee_id = f[1] AND referrer_id IS NULL;
  SELECT count(*) INTO v_k6new FROM (SELECT converted_at, referrer_reward_days, referrer_credited_at FROM public.referral_redemptions WHERE referee_id = f[1]) t;
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
  SELECT count(*) INTO v_k6col FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'referral_redemptions' AND (column_name ILIKE '%payment%' OR column_name ILIKE '%razorpay%');
  v_res := v_res || format(E'\nD6 RLS: a referee of a deleted referrer sees exactly its own row (new columns readable), the referrer sees the NULL-referee rows (D1, D2, D3), an unrelated user and anon see none, own-row UPDATE and DELETE touch 0 rows, an INSERT is refused, and the table has no payment-id column  %s',
    CASE WHEN v_k6a = 1 AND v_k6a2 = 1 AND v_k6new = 1 AND v_k6b = 3 AND v_k6c = 0 AND v_k6d = 0 AND v_k6u = 0 AND v_k6x = 0 AND v_k6i = 'denied' AND v_k6col = 0 THEN 'ok'
         ELSE 'fail own=' || v_k6a || '/' || v_k6a2 || '/' || v_k6new || ' nullref=' || v_k6b || ' unrelated=' || v_k6c || ' anon=' || v_k6d || ' upd=' || v_k6u || ' del=' || v_k6x || ' ins=' || v_k6i || ' payment_cols=' || v_k6col END);

  RAISE EXCEPTION 'VERIFY_RESULTS%', v_res;
END
$v$;
