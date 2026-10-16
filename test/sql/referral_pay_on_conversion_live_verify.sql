-- test/sql/referral_pay_on_conversion_live_verify.sql
--
-- Behavioural verification of migration 159 (the referrer is rewarded when the friend PAYS: 7 days for a monthly payment,
-- 30 for yearly, vested 7 days; the friend still gets 7 days at redemption). Plan: docs/plans/referral-pay-on-conversion.md.
--
-- WHAT IT PROVES. The Dart contract test (test/contracts/referral_pay_on_conversion_migration_test.dart) proves the migration
-- TEXT. This file calls the REAL redeem_referral_atomic, private.grant_referral_days and private.process_referral_conversions
-- and reads the resulting rows. Groups: R redeem; W window and plan; P the "paid" predicate, one fixture per clause; V vest and
-- credit; X voids and deletions; L the legacy shape; F failure isolation, alert dedup, helper bounds and the redeem -> pay ->
-- vest -> credit chain; K the CHECK constraints; A the catalog (ACL, security mode, columns, the cron job); H the hermes round-2 killers (X5 a NULL-referrer backlog cannot starve a real reward, H1 the helper's `<` boundary, H2 an in-place plan edit).
-- What it CANNOT show (one session): two sessions racing, a lock held by someone else, the account-deletion deadlock, the volume
-- alert, the ROW_COUNT guard: those are test/sql/referral_pay_on_conversion_concurrency_local.sh (replica only).
--
-- HOW IT STAYS HONEST.
--   * Every assertion is on FIXTURE rows (a borrowed pool of 10 real users with no subscription and no redemption, wiped
--     between groups), not on the job's returned totals: on the live project the job also looks at real rows. (The one
--     exception, W13, asserts reconciled = 0 and voided = 0 on a second run over unchanged state; it can only be disturbed by
--     a real row changing between the two calls.)
--   * Every "credits nothing / not counted" case sits in a run that also credits a positive control, and the job's return
--     value is checked for {"skipped":"locked"} after every run (a skipped run would pass every negative case vacuously): such a
--     run RAISES JOB_LOCKED instead. now() is frozen inside the transaction, so every interval below is exact.
--   * ONE DO block that ALWAYS aborts with a VERIFY_RESULTS error (no explicit BEGIN/ROLLBACK), so nothing it writes survives,
--     the temp table and the alerts it writes included. It runs the job over the WHOLE table, so on the live project it also takes,
--     until the abort, FOR UPDATE SKIP LOCKED on real vested redemptions, FOR KEY SHARE NOWAIT on real referrers' users rows,
--     FOR UPDATE NOWAIT on their subscription rows and the job's advisory lock; a :41 run that overlaps it returns {skipped} and one
--     hourly run is missed; alerts.id sequence values are consumed. Run it in a quiet moment and NEVER copy its inserts out of the block.
--
-- HOW TO READ THE RESULT. The statement fails with `ERROR: VERIFY_RESULTS` followed by one line per case: `<id> <what>  ok` or
-- `<id> <what>  fail <details>`. A first line `SUMMARY ok=N fail=M skipped=K` counts them (K cases passed vacuously because an open real alert, or a real stalled reward, already existed). Every line must read `ok`. Against the replica
-- BEFORE migration 159 (the 158 state) the block fails: R2 fails first (the old body credits the referrer), then the first call of
-- private.process_referral_conversions(), which does not exist, aborts the whole block with an error instead of a result.
-- LOCAL: against test/sql/referral_pay_on_conversion_replica_schema.sql + supabase/migrations/159_referral_reward_on_conversion.sql.

DO $v$
DECLARE
  v_pool uuid[];
  r1 uuid; r2 uuid; r3 uuid;
  f  uuid[];
  v_code text := 'AVYA-VERIFY01';
  v_ret  jsonb;
  v_i    int;
  v_n    int;
  v_n2   int;
  v_x    timestamptz;
  v_x2   timestamptz;
  v_d    int;
  v_b1   boolean;
  v_b2   boolean;
  v_st   text;
  v_rid  uuid;
  v_rid2 uuid;
  v_pre  boolean;
  v_pre_stall boolean;
  v_pre_vol   boolean;
  v_skip      int;
  v_a3        text;
  v_a1   text;
  v_a2   text;
  v_fail int;
  v_ok   int;
  v_res  text;
BEGIN
  CREATE TEMP TABLE _vr (ord serial, id text, descr text, ok boolean, note text) ON COMMIT DROP;

  SELECT array_agg(id) INTO v_pool FROM (
    SELECT u.id
      FROM public.users u
     WHERE NOT EXISTS (SELECT 1 FROM public.subscriptions s WHERE s.user_id = u.id)
       AND NOT EXISTS (SELECT 1 FROM public.referral_redemptions x WHERE x.referrer_id = u.id OR x.referee_id = u.id)
     ORDER BY u.id
     LIMIT 10) t;
  IF coalesce(array_length(v_pool, 1), 0) < 10 THEN
    RAISE EXCEPTION 'NEED_FIXTURES need 10 users with no subscription and no redemption, found %', coalesce(array_length(v_pool, 1), 0);
  END IF;
  r1 := v_pool[1]; r2 := v_pool[2]; r3 := v_pool[3];
  f  := v_pool[4:10];   -- f[1] .. f[7]

  -- An open failed alert from the last 23 h would suppress ours (the F cases): they say so instead of passing vacuously.
  -- Read HERE, before any job run in this transaction can write one (a run that fails earlier would otherwise flip it).
  SELECT count(*) > 0 INTO v_pre FROM public.alerts WHERE source = 'referral_conversions_failed' AND acknowledged = false AND detected_at > now() - interval '23 hours';
  -- The same for the stall and volume alerts, and for REAL rewards already stalled on the live table (the stall cases count them too).
  SELECT count(*) > 0 INTO v_pre_stall FROM public.alerts WHERE source = 'referral_conversions_stalled' AND acknowledged = false AND detected_at > now() - interval '23 hours';
  v_pre_stall := v_pre_stall OR EXISTS (SELECT 1 FROM public.referral_redemptions WHERE converted_at IS NOT NULL AND converted_at <= now() - interval '10 days' AND referrer_id IS NOT NULL AND referrer_rewarded IS NOT TRUE);
  SELECT count(*) > 0 INTO v_pre_vol FROM public.alerts WHERE source = 'referral_conversions_volume' AND acknowledged = false AND detected_at > now() - interval '23 hours';

  -- ============================================================ R. redeem_referral_atomic
  PERFORM public.redeem_referral_atomic(v_code, r1, f[1], 7);
  SELECT count(*) INTO v_n  FROM public.subscriptions WHERE user_id = f[1] AND plan = 'referral_trial' AND status = 'active' AND end_date = now() + interval '7 days';
  SELECT count(*) INTO v_n2 FROM public.subscriptions WHERE user_id = r1;
  SELECT referrer_rewarded, referee_rewarded INTO v_b1, v_b2 FROM public.referral_redemptions WHERE referee_id = f[1];
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('R1', 'redeem credits the referee a 7-day referral_trial', v_n = 1, format('rows=%s', v_n)),
    ('R2', 'redeem does NOT touch the referrer (no subscription row)', v_n2 = 0, format('referrer rows=%s', v_n2)),
    ('R3', 'audit row: referrer_rewarded=false, referee_rewarded=true', coalesce(v_b1 IS NOT DISTINCT FROM false AND v_b2 IS NOT DISTINCT FROM true, false), format('%s/%s', v_b1, v_b2));

  FOR v_i IN 1..3 LOOP
    INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
    VALUES (f[v_i + 1], (ARRAY['monthly', 'yearly', 'monthly'])[v_i], (ARRAY['active', 'active', 'cancelled'])[v_i],
            now() - interval '40 days', now() - interval '10 days', 'pay_vfy_' || gen_random_uuid());
    BEGIN
      PERFORM public.redeem_referral_atomic(v_code, r1, f[v_i + 1], 7);
      v_st := 'no error';
    EXCEPTION WHEN OTHERS THEN
      v_st := SQLSTATE || ':' || SQLERRM;
    END;
    SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referee_id = f[v_i + 1];
    INSERT INTO _vr (id, descr, ok, note) VALUES
      ('R' || (3 + v_i),
       (ARRAY['a referee with a monthly paid row', 'a referee with a yearly paid row', 'a referee whose only paid row is cancelled'])[v_i]
         || ' is refused (P0001 referee_has_paid_plan) and no audit row is written',
       v_st = 'P0001:referee_has_paid_plan' AND v_n = 0, format('got=%s rows=%s', v_st, v_n));
  END LOOP;

  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)
  VALUES (f[5], 'referral_trial', 'active', now() - interval '4 days', now() + interval '3 days');
  PERFORM public.redeem_referral_atomic(v_code, r1, f[5], 7);
  SELECT count(*), max(end_date) INTO v_n, v_x FROM public.subscriptions WHERE user_id = f[5];
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('R7', 'a referee holding only a referral_trial row is allowed and that row is EXTENDED (3+7 days, still one row)',
     v_n = 1 AND v_x = now() + interval '10 days', format('rows=%s end=%s', v_n, v_x));

  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[6], 'monthly', 'active', now() - interval '40 days', now() - interval '10 days', NULL);
  PERFORM public.redeem_referral_atomic(v_code, r1, f[6], 7);
  SELECT count(*) INTO v_n FROM public.referral_redemptions WHERE referee_id = f[6];
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('R8', 'a monthly row with a NULL payment id (a hand grant) is not a paid row: the referee is allowed', v_n = 1, format('rows=%s', v_n));

  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, r2, f[1], 7);
    v_st := 'no error';
  EXCEPTION WHEN OTHERS THEN
    v_st := SQLSTATE;
  END;
  SELECT count(*) INTO v_n FROM public.subscriptions WHERE user_id = f[1];
  SELECT count(*) INTO v_n2 FROM public.referral_redemptions WHERE referee_id = f[1];
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('R9', 'a duplicate referee raises unique_violation 23505 and moves nothing (the Edge Function 23505 path)',
     v_st = '23505' AND v_n = 1 AND v_n2 = 1, format('sqlstate=%s subs=%s audit=%s', v_st, v_n, v_n2));

  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, NULL, f[7], 7);
    v_st := 'no error';
  EXCEPTION WHEN OTHERS THEN
    v_st := SQLSTATE;
  END;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('R10', 'a NULL referrer is refused with 23502', v_st = '23502', 'got=' || v_st);
  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, r3, NULL, 7);
    v_st := 'no error';
  EXCEPTION WHEN OTHERS THEN
    v_st := SQLSTATE;
  END;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('R10b', 'a NULL referee is refused with 23502 (not the helper''s 22023 after the audit row)', v_st = '23502', 'got=' || v_st);

  -- R11: only a PAID plan blocks a redemption. A referral_trial row that happens to carry a payment id (a hand grant) is not a paid plan.
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[7], 'referral_trial', 'active', now() - interval '2 days', now() + interval '5 days', 'pay_vfy_' || gen_random_uuid());
  BEGIN
    PERFORM public.redeem_referral_atomic(v_code, r3, f[7], 3);
    v_st := 'no error';
  EXCEPTION WHEN OTHERS THEN
    v_st := SQLSTATE || ':' || SQLERRM;
  END;
  SELECT count(*), max(end_date) INTO v_n, v_x FROM public.subscriptions WHERE user_id = f[7];
  SELECT days_granted_each INTO v_d FROM public.referral_redemptions WHERE referee_id = f[7];
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('R11', 'a referral_trial row WITH a payment id is not a paid plan: the redemption is accepted (kills dropping the plan clause from the refusal)',
      v_st = 'no error' AND v_d IS NOT NULL, 'got=' || v_st),
    ('R12', 'the days argument is honoured: p_days = 3 records days_granted_each 3 and EXTENDS the existing active row by 3 days (5 + 3), still one row',
      v_d = 3 AND v_n = 1 AND v_x = now() + interval '8 days', format('days=%s rows=%s end=%s', v_d, v_n, v_x));

  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- ============================================================ W. window and plan (referrer r1, redemptions 20 days old unless stated)
  -- W-a: seven friends, one run.
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded) VALUES
    (v_code, r1, f[1], now() - interval '20 days', false, true),
    (v_code, r1, f[2], now() - interval '20 days', false, true),
    (v_code, r1, f[3], now() - interval '20 days', false, true),
    (v_code, r1, f[4], now() - interval '20 days', false, true),
    (v_code, r1, f[5], now() - interval '95 days', false, true),
    (v_code, r1, f[6], now() - interval '95 days', false, true),
    (v_code, r1, f[7], now() - interval '97 days', false, true);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[1], 'monthly', 'active', (now() - interval '20 days') + interval '8 days',  now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[2], 'yearly',  'active', (now() - interval '20 days') + interval '8 days',  now() + interval '300 days', 'pay_vfy_' || gen_random_uuid()),
    (f[3], 'monthly', 'active', (now() - interval '20 days') - interval '1 day',   now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[4], 'monthly', 'active',  now() - interval '20 days',                       now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[5], 'monthly', 'active', (now() - interval '95 days') + interval '90 days', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[6], 'monthly', 'active', (now() - interval '95 days') + interval '90 days' + interval '1 second', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[7], 'monthly', 'active', (now() - interval '97 days') + interval '5 days',  now() + interval '30 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  -- W14: the returned counters are lower bounds here (a real row can only add to them): four fixture rows were reconciled
  -- (W1, W2, W4, W5). Kills swapping the two counters of the return value.
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('W14', 'the first run reports at least 4 reconciled (the four converted fixtures), so reconciled and voided are not swapped', (v_ret->>'reconciled')::int >= 4, v_ret::text);
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('W1', 'monthly payment 8 days after the code: converted_at = its start_date, 7 days',
      (SELECT converted_at = (now() - interval '20 days') + interval '8 days' AND referrer_reward_days = 7 FROM public.referral_redemptions WHERE referee_id = f[1]), NULL),
    ('W2', 'yearly payment: 30 days',
      (SELECT referrer_reward_days = 30 FROM public.referral_redemptions WHERE referee_id = f[2]), NULL),
    ('W3', 'a payment BEFORE the redemption is not counted',
      (SELECT converted_at IS NULL AND referrer_reward_days IS NULL FROM public.referral_redemptions WHERE referee_id = f[3]), NULL),
    ('W4', 'a payment exactly AT the redemption counts',
      (SELECT converted_at IS NOT NULL AND referrer_reward_days = 7 FROM public.referral_redemptions WHERE referee_id = f[4]), NULL),
    ('W5', 'a payment exactly 90 days after the redemption counts (and, 5 days old, is not yet credited)',
      (SELECT converted_at IS NOT NULL AND referrer_reward_days = 7 AND referrer_rewarded IS NOT TRUE FROM public.referral_redemptions WHERE referee_id = f[5]), NULL),
    ('W6', 'a payment 90 days + 1 second after the redemption does not count',
      (SELECT converted_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[6]), NULL),
    ('W7', 'a redemption exactly 97 days old is outside the detection scan (strict >), even with an in-window payment',
      (SELECT converted_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[7]), NULL);
  -- W13: a second run over the SAME state is a steady state: it writes no row, so it reports nothing reconciled and nothing
  -- voided (f[1]..f[6] are all scan candidates; f[3] and f[6] have no qualifying payment and must not be counted as voided).
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('W13', 'a second run over unchanged state reconciles nothing and voids nothing (kills dropping the IS DISTINCT FROM guard of the reconcile UPDATE)',
      (v_ret->>'reconciled')::int = 0 AND (v_ret->>'voided')::int = 0, v_ret::text);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- W-b: the scan edge control, the earliest payment, and the pending arm past the scan.
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days) VALUES
    (v_code, r1, f[1], (now() - interval '97 days') + interval '1 second', false, true, NULL, NULL),
    (v_code, r1, f[2], now() - interval '60 days', false, true, NULL, NULL),
    (v_code, r1, f[3], now() - interval '60 days', false, true, NULL, NULL),
    (v_code, r1, f[4], now() - interval '100 days', false, true, (now() - interval '100 days') + interval '5 days', 7),
    (v_code, r2, f[5], now() - interval '100 days', false, true, (now() - interval '100 days') + interval '5 days', 7),
    (v_code, r3, f[6], now() - interval '60 days', false, true, NULL, NULL);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[1], 'monthly', 'active', ((now() - interval '97 days') + interval '1 second') + interval '5 days', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[2], 'monthly', 'active', (now() - interval '60 days') + interval '8 days',  now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[2], 'yearly',  'active', (now() - interval '60 days') + interval '40 days', now() + interval '300 days', 'pay_vfy_' || gen_random_uuid()),
    (f[3], 'yearly',  'active', (now() - interval '60 days') + interval '8 days',  now() + interval '300 days', 'pay_vfy_' || gen_random_uuid()),
    (f[3], 'monthly', 'active', (now() - interval '60 days') + interval '40 days', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[4], 'monthly', 'cancelled', (now() - interval '100 days') + interval '5 days', now() - interval '70 days', 'pay_vfy_' || gen_random_uuid()),
    (f[5], 'monthly', 'active', (now() - interval '100 days') + interval '5 days', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[6], 'monthly', 'active', (now() - interval '60 days') - interval '1 second', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('W15', 'the run that voids the cancelled-payment pending row reports at least 1 voided AND at least 3 reconciled (the three converted fixtures of this run; a swap of the two counters fails the reconciled bound)', (v_ret->>'voided')::int >= 1 AND (v_ret->>'reconciled')::int >= 3, v_ret::text),
    ('W16', 'a payment ONE SECOND before the code was applied is not counted (kills loosening the lower bound of the window)',
      (SELECT converted_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[6]), NULL);
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('W8', 'control for W7: a redemption 1 second inside the 97-day scan IS converted',
      (SELECT converted_at IS NOT NULL AND referrer_reward_days = 7 FROM public.referral_redemptions WHERE referee_id = f[1]), NULL),
    ('W9', 'two payments, monthly then yearly: the EARLIEST decides (7), converted_at = the monthly start',
      (SELECT referrer_reward_days = 7 AND converted_at = (now() - interval '60 days') + interval '8 days' FROM public.referral_redemptions WHERE referee_id = f[2]), NULL),
    ('W10', 'two payments, yearly then monthly: the EARLIEST decides (30)',
      (SELECT referrer_reward_days = 30 AND converted_at = (now() - interval '60 days') + interval '8 days' FROM public.referral_redemptions WHERE referee_id = f[3]), NULL),
    ('W11', 'the pending arm: a pending row 100 days old whose payment was cancelled is VOIDED (converted_at, days NULL) and not credited',
      (SELECT converted_at IS NULL AND referrer_reward_days IS NULL AND referrer_rewarded IS NOT TRUE FROM public.referral_redemptions WHERE referee_id = f[4]), NULL),
    ('W12', 'control for W11: the same pending row with an active payment is kept and credited (past the scan)',
      (SELECT referrer_rewarded IS TRUE AND converted_at = (now() - interval '100 days') + interval '5 days' FROM public.referral_redemptions WHERE referee_id = f[5]), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- ============================================================ P. the "paid" predicate, one fixture per clause (control = P1)
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  SELECT v_code, r1, f[i], now() - interval '20 days', false, true FROM generate_series(1, 6) i;
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id, cancelled_at) VALUES
    (f[1], 'monthly',        'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid(), NULL),
    (f[2], 'monthly',        'active', now() - interval '12 days', now() + interval '18 days', NULL,                            NULL),
    (f[3], 'referral_trial', 'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid(), NULL),
    (f[4], 'monthly',        'cancelled', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid(), NULL),
    (f[5], 'monthly',        'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid(), now()),
    (f[6], 'monthly',        'expired', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid(), NULL);
  -- INSERT stamped cancelled_at for the cancelled row (trigger 140); the legacy hand-cancelled shape is status cancelled with cancelled_at NULL.
  UPDATE public.subscriptions SET cancelled_at = NULL WHERE user_id = f[4];
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('P1', 'control: a monthly row with a payment id, active, not cancelled IS counted',
      (SELECT converted_at IS NOT NULL FROM public.referral_redemptions WHERE referee_id = f[1]), NULL),
    ('P2', 'a monthly row with a NULL razorpay_payment_id is not counted (kills dropping that clause)',
      (SELECT converted_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[2]), NULL),
    ('P3', 'a referral_trial row WITH a payment id is not counted (kills dropping the plan clause)',
      (SELECT converted_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[3]), NULL),
    ('P4', 'status cancelled with cancelled_at NULL (the hand-cancelled legacy shape) is not counted (kills dropping the status clause)',
      (SELECT converted_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[4]) AND (SELECT cancelled_at IS NULL FROM public.subscriptions WHERE user_id = f[4]), NULL),
    ('P5', 'status active with cancelled_at set is not counted (kills dropping the cancelled_at clause)',
      (SELECT converted_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[5]), NULL),
    ('P6', 'status expired (neither active nor cancelled) is not counted (kills loosening `status = active` to `status <> cancelled`)',
      (SELECT converted_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[6]), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- ============================================================ V. vest and credit
  -- V-a: r1 gets one friend 6 d 23 h 59 m old (not vested) and one exactly 7 d old (vested); r2 gets a friend whose payment is 20 days old at first sight.
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded) VALUES
    (v_code, r1, f[1], now() - interval '30 days', false, true),
    (v_code, r1, f[2], now() - interval '30 days', false, true),
    (v_code, r2, f[3], now() - interval '30 days', false, true);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[1], 'monthly', 'active', now() - interval '6 days 23 hours 59 minutes', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[2], 'monthly', 'active', now() - interval '7 days', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[3], 'monthly', 'active', now() - interval '20 days', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n  FROM public.subscriptions WHERE user_id = r1;
  SELECT max(end_date) INTO v_x FROM public.subscriptions WHERE user_id = r1;
  SELECT count(*) INTO v_n2 FROM public.subscriptions WHERE user_id = r2;
  SELECT max(end_date) INTO v_x2 FROM public.subscriptions WHERE user_id = r2;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('V1', 'a payment 6 d 23 h 59 m old is converted but NOT credited',
      (SELECT converted_at IS NOT NULL AND referrer_rewarded IS NOT TRUE AND referrer_credited_at IS NULL FROM public.referral_redemptions WHERE referee_id = f[1]), NULL),
    ('V2', 'a payment exactly 7 d old IS credited: referrer_rewarded, referrer_credited_at = now()',
      (SELECT referrer_rewarded IS TRUE AND referrer_credited_at = now() FROM public.referral_redemptions WHERE referee_id = f[2]), NULL),
    ('V2b', 'the referrer r1 got ONE referral_trial row ending now()+7 days (only the vested friend counted)',
      v_n = 1 AND v_x = now() + interval '7 days' AND (SELECT plan = 'referral_trial' FROM public.subscriptions WHERE user_id = r1), format('rows=%s end=%s', v_n, v_x)),
    ('V3', 'a payment 20 days old at first detection: converted_at = its start_date (not now()), credited in the same run',
      (SELECT referrer_rewarded IS TRUE AND converted_at = now() - interval '20 days' FROM public.referral_redemptions WHERE referee_id = f[3]) AND v_n2 = 1 AND v_x2 = now() + interval '7 days', format('r2 rows=%s end=%s', v_n2, v_x2));
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('V4', 'a second run credits nothing more (rows and end_date unchanged for both referrers)',
      (SELECT count(*) FROM public.subscriptions WHERE user_id = r1) = v_n AND (SELECT max(end_date) FROM public.subscriptions WHERE user_id = r1) = v_x
      AND (SELECT count(*) FROM public.subscriptions WHERE user_id = r2) = v_n2 AND (SELECT max(end_date) FROM public.subscriptions WHERE user_id = r2) = v_x2, NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- V-b: what the credit does to the referrer's existing rows. r1 none (yearly friend), r2 an active paid row, r3 an old expired-but-active row plus a current one.
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (r2, 'monthly', 'active', now() - interval '20 days', now() + interval '10 days', 'pay_vfy_' || gen_random_uuid()),
    (r3, 'monthly', 'active', now() - interval '35 days', now() - interval '5 days',  'pay_vfy_' || gen_random_uuid()),
    (r3, 'monthly', 'active', now() - interval '27 days', now() + interval '3 days',  'pay_vfy_' || gen_random_uuid());
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded) VALUES
    (v_code, r1, f[1], now() - interval '20 days', false, true),
    (v_code, r2, f[2], now() - interval '20 days', false, true),
    (v_code, r3, f[3], now() - interval '20 days', false, true);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[1], 'yearly',  'active', now() - interval '10 days', now() + interval '355 days', 'pay_vfy_' || gen_random_uuid()),
    (f[2], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days',  'pay_vfy_' || gen_random_uuid()),
    (f[3], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days',  'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('V5', 'a yearly friend: a referrer with no row gets a referral_trial row ending now()+30 days',
      (SELECT count(*) = 1 AND max(end_date) = now() + interval '30 days' AND min(plan) = 'referral_trial' FROM public.subscriptions WHERE user_id = r1), NULL),
    ('V6', 'a referrer with an active PAID row has THAT row extended (+7), no new row',
      (SELECT count(*) = 1 AND max(end_date) = now() + interval '17 days' AND min(plan) = 'monthly' FROM public.subscriptions WHERE user_id = r2), NULL),
    ('V7', 'a referrer with an old expired-but-active row plus a current one: the CURRENT one is extended, the old one is untouched',
      (SELECT count(*) = 2 FROM public.subscriptions WHERE user_id = r3)
      AND (SELECT end_date = now() + interval '10 days' FROM public.subscriptions WHERE user_id = r3 AND start_date = now() - interval '27 days')
      AND (SELECT end_date = now() - interval '5 days'  FROM public.subscriptions WHERE user_id = r3 AND start_date = now() - interval '35 days'), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- V-c: only a CANCELLED row with a future end_date (kills dropping the helper's status filter); two friends vesting in one run (kills WHERE referrer_id in the flag UPDATE); a NULL flag.
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (r1, 'monthly', 'cancelled', now() - interval '10 days', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid()),
    (r3, 'monthly', 'active',    now() - interval '35 days', now() - interval '5 days',  'pay_vfy_' || gen_random_uuid());   -- r3: its ONLY active row has lapsed
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded) VALUES
    (v_code, r1, f[1], now() - interval '20 days', false, true),
    (v_code, r2, f[2], now() - interval '30 days', false, true),
    (v_code, r2, f[3], now() - interval '30 days', false, true),
    (v_code, r3, f[4], now() - interval '20 days', NULL,  true),
    (v_code, r3, f[5], now() - interval '20 days', false, true);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[1], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days',  'pay_vfy_' || gen_random_uuid()),
    (f[2], 'monthly', 'active', now() - interval '12 days', now() + interval '18 days',  'pay_vfy_' || gen_random_uuid()),
    (f[3], 'yearly',  'active', now() - interval '10 days', now() + interval '355 days', 'pay_vfy_' || gen_random_uuid()),
    (f[4], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days',  'pay_vfy_' || gen_random_uuid()),
    (f[5], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days',  'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('V8', 'a referrer whose ONLY row is cancelled (future end_date) gets a NEW referral_trial row; the cancelled row is untouched',
      (SELECT count(*) = 2 FROM public.subscriptions WHERE user_id = r1)
      AND (SELECT end_date = now() + interval '7 days' FROM public.subscriptions WHERE user_id = r1 AND plan = 'referral_trial' AND status = 'active')
      AND (SELECT end_date = now() + interval '20 days' FROM public.subscriptions WHERE user_id = r1 AND plan = 'monthly' AND status = 'cancelled'), NULL),
    ('V9', 'two friends of one referrer vest in one run (monthly then yearly): both credited, end_date = now()+37 days, both flags true',
      (SELECT max(end_date) = now() + interval '37 days' FROM public.subscriptions WHERE user_id = r2)
      AND (SELECT count(*) = 2 FROM public.referral_redemptions WHERE referrer_id = r2 AND referrer_rewarded IS TRUE), NULL),
    ('V10', 'a row whose referrer_rewarded is NULL is treated as not credited and is credited (flag becomes true)',
      (SELECT referrer_rewarded IS TRUE FROM public.referral_redemptions WHERE referee_id = f[4]), NULL),
    ('V11', 'a referrer whose only active row has LAPSED gets a NEW referral_trial row (the lapsed one untouched), and a second friend in the same run extends THAT row: 2 rows, trial ends now()+14 days',
      (SELECT count(*) = 2 FROM public.subscriptions WHERE user_id = r3)
      AND (SELECT end_date = now() - interval '5 days' FROM public.subscriptions WHERE user_id = r3 AND plan = 'monthly')
      AND (SELECT end_date = now() + interval '14 days' FROM public.subscriptions WHERE user_id = r3 AND plan = 'referral_trial'), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- ============================================================ X. voids and deletions
  -- X1: a payment cancelled before the vest voids the row; a later payment re-arms it with a fresh vest.
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  VALUES (v_code, r1, f[1], now() - interval '20 days', false, true);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[1], 'monthly', 'active', now() - interval '4 days', now() + interval '26 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT converted_at INTO v_x FROM public.referral_redemptions WHERE referee_id = f[1];
  UPDATE public.subscriptions SET status = 'cancelled' WHERE user_id = f[1];
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('X1a', 'control: the payment 4 days old converts the row', v_x = now() - interval '4 days', 'converted_at=' || coalesce(v_x::text, 'null')),
    ('X1b', 'the payment cancelled before the vest VOIDS the row (converted_at, days NULL) and the referrer is untouched',
      (SELECT converted_at IS NULL AND referrer_reward_days IS NULL AND referrer_rewarded IS NOT TRUE FROM public.referral_redemptions WHERE referee_id = f[1])
      AND NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = r1), NULL);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[1], 'yearly', 'active', now() - interval '1 day', now() + interval '364 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('X1c', 'a later payment RE-ARMS the row: converted_at = the second payment start, 30 days, no early credit',
      (SELECT converted_at = now() - interval '1 day' AND referrer_reward_days = 30 AND referrer_rewarded IS NOT TRUE FROM public.referral_redemptions WHERE referee_id = f[1])
      AND NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = r1), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- X2 / X3 / X4 in one run.
  INSERT INTO public.referral_redemptions (id, code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days) VALUES
    (gen_random_uuid(), v_code, r2,   NULL, now() - interval '30 days', false, true, now() - interval '12 days', 7),
    (gen_random_uuid(), v_code, NULL, f[2], now() - interval '30 days', false, true, now() - interval '12 days', 7),
    (gen_random_uuid(), v_code, r3,   f[3], now() - interval '20 days', false, true, NULL, NULL),
    (gen_random_uuid(), v_code, r1,   f[4], now() - interval '20 days', false, true, NULL, NULL);
  SELECT id INTO v_rid FROM public.referral_redemptions WHERE referee_id = f[2];   -- the NULL-referrer pending row
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[2], 'monthly', 'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid()),
    (f[3], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid()),
    (f[4], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT converted_at, referrer_reward_days, referrer_credited_at INTO v_x, v_d, v_x2 FROM public.referral_redemptions WHERE referee_id = f[4];
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('X2', 'a pending row whose referee was deleted (referee_id NULL) is VOIDED and its referrer gets nothing',
      (SELECT count(*) = 1 AND bool_and(converted_at IS NULL AND referrer_reward_days IS NULL AND referrer_rewarded IS NOT TRUE) FROM public.referral_redemptions WHERE referrer_id = r2 AND referee_id IS NULL)
      AND NOT EXISTS (SELECT 1 FROM public.subscriptions WHERE user_id = r2), NULL),
    ('X3', 'a vested pending row with a NULL referrer is not credited and no failed alert names it (positive control: the normal row for r3 IS credited)',
      (SELECT referrer_rewarded IS NOT TRUE FROM public.referral_redemptions WHERE id = v_rid)
      AND NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'referral_conversions_failed' AND context_json -> 'redemption_ids' ? v_rid::text)
      AND (SELECT referrer_rewarded IS TRUE FROM public.referral_redemptions WHERE referee_id = f[3]), NULL),
    ('X4a', 'control: the normal vested row is credited (r1 +7)',
      (SELECT referrer_rewarded IS TRUE FROM public.referral_redemptions WHERE referee_id = f[4]) AND (SELECT max(end_date) = now() + interval '7 days' FROM public.subscriptions WHERE user_id = r1), NULL);
  UPDATE public.subscriptions SET status = 'cancelled' WHERE user_id = f[4];
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('X4b', 'a CREDITED row whose payment is cancelled afterwards stays credited and keeps converted_at, days and credited_at (no clawback, not reset)',
      (SELECT referrer_rewarded IS TRUE AND converted_at = v_x AND referrer_reward_days = v_d AND referrer_credited_at = v_x2 FROM public.referral_redemptions WHERE referee_id = f[4]), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- ============================================================ H. hermes round 2 (2026-10-16): killers for mutants the first round called equivalent or Dart-only
  -- X5: 55 vested pending rows with a NULL referrer, all OLDER than the one real row, must not starve it out of the 50-row credit
  -- batch. Without `referrer_id IS NOT NULL` in the credit select they sort first, take every slot, credit nothing and raise no alert.
  INSERT INTO public.referral_redemptions (id, code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days)
  SELECT gen_random_uuid(), v_code, NULL, NULL, now() - interval '60 days', false, true, now() - interval '40 days' - (g || ' seconds')::interval, 7
    FROM generate_series(1, 55) g;
  INSERT INTO public.referral_redemptions (id, code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days)
  VALUES (gen_random_uuid(), v_code, r1, f[1], now() - interval '20 days', false, true, NULL, NULL);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[1], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('X5', 'FIFTY-FIVE older NULL-referrer vested rows do not starve the one real row out of the credit batch (r1 IS credited +7 in the FIRST run; none of the NULL-referrer rows is credited)',
      (SELECT referrer_rewarded IS TRUE FROM public.referral_redemptions WHERE referee_id = f[1])
      AND (SELECT max(end_date) = now() + interval '7 days' FROM public.subscriptions WHERE user_id = r1)
      AND NOT EXISTS (SELECT 1 FROM public.referral_redemptions WHERE referrer_id IS NULL AND code = v_code AND referrer_rewarded IS TRUE), v_ret::text);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool) OR (referrer_id IS NULL AND code = v_code);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- H1: an ACTIVE row whose end_date is exactly now() (now() is frozen, so this is exact) is EXTENDED by the helper, not shadowed by a
  -- second referral_trial row: the comparison is `v_end < now()`, so `<=` would insert a second row.
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date)
  VALUES (f[5], 'referral_trial', 'active', now() - interval '7 days', now());
  PERFORM private.grant_referral_days(f[5], 7);
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('H1', 'grant_referral_days extends an active row that ends exactly now() (one row, end_date = now() + 7 days) and does not insert a second row',
      (SELECT count(*) = 1 AND max(end_date) = now() + interval '7 days' FROM public.subscriptions WHERE user_id = f[5]), NULL);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- H2: a payment row edited IN PLACE from monthly to yearly at the same start_date changes only the reward days, so the second
  -- IS DISTINCT FROM arm of the reconcile is what rewrites 7 to 30 (the payment is 5 days old, so the row stays pending).
  INSERT INTO public.referral_redemptions (id, code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days)
  VALUES (gen_random_uuid(), v_code, r2, f[6], now() - interval '20 days', false, true, NULL, NULL);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[6], 'monthly', 'active', now() - interval '5 days', now() + interval '25 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  UPDATE public.subscriptions SET plan = 'yearly' WHERE user_id = f[6];
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('H2', 'a payment edited in place from monthly to yearly (same start_date) rewrites the pending reward from 7 to 30 days and leaves converted_at unchanged',
      (SELECT referrer_reward_days = 30 AND converted_at = now() - interval '5 days' AND referrer_rewarded IS NOT TRUE FROM public.referral_redemptions WHERE referee_id = f[6]), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- ============================================================ L. the legacy shape
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded) VALUES
    (v_code, r1, f[1], now() - interval '110 days', false, true),
    (v_code, r1, f[2], now() - interval '50 days',  false, true);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[1], 'monthly', 'active', (now() - interval '110 days') + interval '40 days', now() + interval '30 days', 'pay_vfy_' || gen_random_uuid()),
    (f[2], 'monthly', 'active', (now() - interval '50 days')  + interval '8 days',  now() + interval '30 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('L1', 'the legacy shape: a 110-day-old row, flag false, whose referee paid INSIDE the old window (day 40) is never detected or credited',
      (SELECT converted_at IS NULL AND referrer_rewarded IS NOT TRUE FROM public.referral_redemptions WHERE referee_id = f[1]), NULL),
    ('L2', 'control for L1: a 50-day-old twin with a day-8 payment is converted and credited',
      (SELECT converted_at IS NOT NULL AND referrer_rewarded IS TRUE FROM public.referral_redemptions WHERE referee_id = f[2]), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- Z: every run so far (groups R to L) was healthy, so none wrote a failed alert. Without this a credit select that re-picked
  -- already-credited rows (the flag UPDATE then matches 0 rows and the ROW_COUNT check raises) would stay green here and merely
  -- flip an F case to its skip branch. (Vacuous only when v_pre: an open real alert would have suppressed ours.)
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('Z', 'no run before group F wrote a failed alert (no credit failed in a healthy run)' || CASE WHEN v_pre THEN ' [SKIPPED: an open alert from the last 23 h already existed]' ELSE '' END,
      v_pre OR NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'referral_conversions_failed' AND detected_at = now()), NULL);

  -- ============================================================ S. the stall watch and the volume alert on the REAL alerts table
  -- The earlier groups legitimately left rewards pending for months (the W pending-arm fixtures), so the stall watch already wrote
  -- an alert in THIS transaction (detected_at = now(), which no real alert can carry). Remove those so S1 to S3 read their own runs.
  DELETE FROM public.alerts WHERE source = 'referral_conversions_stalled' AND detected_at = now();
  -- S1: none of these is a stalled reward: (a) pending 10 days MINUS one second (now() is frozen in this transaction, so the edge is
  -- exact); (b) a row old enough but whose referrer account is gone (referrer_id NULL: it drops out by the foreign key); (c) a row old
  -- enough that is already CREDITED.
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days, referrer_credited_at) VALUES
    (v_code, r1,   f[1], now() - interval '30 days', false, true, (now() - interval '10 days') + interval '1 second', 7, NULL),
    (v_code, NULL, f[2], now() - interval '30 days', false, true, now() - interval '12 days', 7, NULL),
    (v_code, r3,   f[3], now() - interval '30 days', true,  true, now() - interval '12 days', 7, now() - interval '5 days');
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[1], 'monthly', 'active', (now() - interval '10 days') + interval '1 second', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid()),
    (f[2], 'monthly', 'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid()),
    (f[3], 'monthly', 'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('S1', 'a reward pending 10 days minus one second, a row whose referrer is gone and an already-credited row raise no stalled alert' || CASE WHEN v_pre_stall THEN ' [SKIPPED: a stalled reward or an open stalled alert already existed on the live table]' ELSE '' END,
      v_pre_stall OR NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = 'referral_conversions_stalled' AND detected_at = now()), NULL);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- S2: a reward pending exactly 10 days IS stalled: one warn alert, counting it; the SAME call still credits the row.
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days)
  VALUES (v_code, r1, f[1], now() - interval '30 days', false, true, now() - interval '10 days', 7);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[1], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.alerts WHERE source = 'referral_conversions_stalled' AND detected_at = now();
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('S2', 'a reward pending exactly 10 days raises ONE warn stalled alert (counting it), and the same run credits the row' || CASE WHEN v_pre_stall THEN ' [SKIPPED: a stalled reward or an open stalled alert already existed on the live table]' ELSE '' END,
      v_pre_stall OR (v_n = 1
        AND EXISTS (SELECT 1 FROM public.alerts WHERE source = 'referral_conversions_stalled' AND severity = 'warn' AND detected_at = now() AND (context_json ->> 'stalled')::int = 1)
        AND (SELECT referrer_rewarded IS TRUE FROM public.referral_redemptions WHERE referee_id = f[1])), format('stalled alerts this txn=%s', v_n));
  -- S3: a second stalled row on the next run is suppressed by the open alert (dedup): still one alert in this transaction.
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days)
  VALUES (v_code, r2, f[2], now() - interval '30 days', false, true, now() - interval '12 days', 7);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[2], 'monthly', 'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.alerts WHERE source = 'referral_conversions_stalled' AND detected_at = now();
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('S3', 'a second stalled reward in the next run raises no second alert while the first is open (23-hour dedup)' || CASE WHEN v_pre_stall THEN ' [SKIPPED: a stalled reward or an open stalled alert already existed on the live table]' ELSE '' END,
      v_pre_stall OR v_n = 1, format('stalled alerts this txn=%s', v_n));
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- S5 / S6: the 23-hour dedup window edge, with an open alert planted at a chosen age. 22 h 59 min old suppresses a new one; 23 h 1 min
  -- old does not. (Kills moving the window to 1 hour or to 48 hours: every other dedup case lives inside one transaction.)
  DELETE FROM public.alerts WHERE source = 'referral_conversions_stalled' AND detected_at = now();
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action, detected_at)
  VALUES ('referral_conversions_stalled', 'warn', 'VERIFY-BOUNDARY', '{}'::jsonb, 'verify', now() - interval '22 hours 59 minutes');
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days)
  VALUES (v_code, r1, f[1], now() - interval '30 days', false, true, now() - interval '12 days', 7);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[1], 'monthly', 'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.alerts WHERE source = 'referral_conversions_stalled' AND detected_at = now();
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('S5', 'an open stalled alert 22 h 59 min old still suppresses a new one' || CASE WHEN v_pre_stall THEN ' [SKIPPED: a stalled reward or an open stalled alert already existed on the live table]' ELSE '' END,
      v_pre_stall OR v_n = 0, format('new alerts=%s', v_n));
  DELETE FROM public.alerts WHERE source = 'referral_conversions_stalled' AND summary = 'VERIFY-BOUNDARY';
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);
  INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action, detected_at)
  VALUES ('referral_conversions_stalled', 'warn', 'VERIFY-BOUNDARY', '{}'::jsonb, 'verify', now() - interval '23 hours 1 minute');
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded, converted_at, referrer_reward_days)
  VALUES (v_code, r2, f[2], now() - interval '30 days', false, true, now() - interval '12 days', 7);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[2], 'monthly', 'active', now() - interval '12 days', now() + interval '18 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.alerts WHERE source = 'referral_conversions_stalled' AND detected_at = now();
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('S6', 'an open stalled alert 23 h 1 min old no longer suppresses: a new one is written' || CASE WHEN v_pre_stall THEN ' [SKIPPED: a stalled reward or an open stalled alert already existed on the live table]' ELSE '' END,
      v_pre_stall OR v_n = 1, format('new alerts=%s', v_n));
  DELETE FROM public.alerts WHERE source = 'referral_conversions_stalled' AND summary = 'VERIFY-BOUNDARY';
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- S4: 21 redemptions inside 24 hours (NULL parties: the table allows them and nothing is credited) raise the volume alert on the
  -- REAL alerts table (the replica proves the thresholds; only the live table proves the INSERT is accepted there).
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded)
  SELECT v_code, NULL, NULL, now() - interval '1 hour', false, true FROM generate_series(1, 21);
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('S4', 'more than 20 redemptions in 24 hours raise a warn volume alert on the live alerts table' || CASE WHEN v_pre_vol THEN ' [SKIPPED: an open volume alert from the last 23 h already existed]' ELSE '' END,
      v_pre_vol OR EXISTS (SELECT 1 FROM public.alerts WHERE source = 'referral_conversions_volume' AND severity = 'warn' AND detected_at = now()
                              AND (context_json ->> 'redemptions_24h')::int >= 21 AND (context_json ->> 'max_redemptions_24h_one_referrer') IS NOT NULL), NULL);
  DELETE FROM public.referral_redemptions WHERE code = v_code AND referrer_id IS NULL AND referee_id IS NULL AND created_at = now() - interval '1 hour';

  -- ============================================================ F. failure isolation, alert dedup, helper bounds, the chain
  -- F-a: a referrer whose active row ends at the largest timestamp makes `+ 7 days` raise 22008 (measured): that row stays pending,
  --      the other row (r2) is still credited, the failed alert names the redemption id.
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (r1, 'monthly', 'active', now() - interval '10 days', '294276-12-31 00:00:00+00', 'pay_vfy_' || gen_random_uuid());
  INSERT INTO public.referral_redemptions (code, referrer_id, referee_id, created_at, referrer_rewarded, referee_rewarded) VALUES
    (v_code, r1, f[1], now() - interval '20 days', false, true),
    (v_code, r2, f[2], now() - interval '20 days', false, true);
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id) VALUES
    (f[1], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid()),
    (f[2], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid());
  SELECT id INTO v_rid FROM public.referral_redemptions WHERE referee_id = f[1];
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  v_ret := private.process_referral_conversions();   -- a second failing run: the open alert must suppress a second one (dedup)
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.alerts WHERE source = 'referral_conversions_failed' AND detected_at = now();
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('F1', 'a failing credit leaves its row PENDING (converted, not credited) and its referrer untouched',
      (SELECT converted_at IS NOT NULL AND referrer_rewarded IS NOT TRUE FROM public.referral_redemptions WHERE id = v_rid)
      AND (SELECT count(*) = 1 AND max(end_date) = '294276-12-31 00:00:00+00' FROM public.subscriptions WHERE user_id = r1), NULL),
    ('F2', 'the other row in the same run is still credited (per-row isolation)',
      (SELECT referrer_rewarded IS TRUE FROM public.referral_redemptions WHERE referee_id = f[2]), NULL),
    ('F3', 'a failed alert naming the redemption id was written (warn), once across two runs (dedup)' || CASE WHEN v_pre THEN ' [SKIPPED: an open alert from the last 23 h already existed]' ELSE '' END,
      v_pre OR (v_n = 1
        AND EXISTS (SELECT 1 FROM public.alerts WHERE source = 'referral_conversions_failed' AND severity = 'warn' AND detected_at = now() AND context_json -> 'redemption_ids' ? v_rid::text)), format('alerts this txn=%s', v_n));
  IF NOT v_pre THEN
    UPDATE public.alerts SET acknowledged = true, acknowledged_at = now() WHERE source = 'referral_conversions_failed' AND detected_at = now();
    v_ret := private.process_referral_conversions();
    IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
    SELECT count(*) INTO v_n  FROM public.alerts WHERE source = 'referral_conversions_failed' AND detected_at = now();
    SELECT count(*) INTO v_n2 FROM public.alerts WHERE source = 'referral_conversions_failed' AND detected_at = now() AND acknowledged = false;
    INSERT INTO _vr (id, descr, ok, note) VALUES
      ('F4', 'after the alert is acknowledged the next failing run writes a NEW one (2 in this transaction, 1 open)', v_n = 2 AND v_n2 = 1, format('total=%s open=%s', v_n, v_n2));
  END IF;
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- F-b: the helper's bounds.
  FOR v_i IN 1..4 LOOP
    BEGIN
      PERFORM private.grant_referral_days((ARRAY[f[1], f[1], NULL, f[1]])[v_i], (ARRAY[0, 31, 7, NULL])[v_i]);
      v_st := 'no error';
    EXCEPTION WHEN OTHERS THEN
      v_st := SQLSTATE;
    END;
    INSERT INTO _vr (id, descr, ok, note) VALUES
      ('F5.' || v_i, (ARRAY['0 days', '31 days', 'a NULL user', 'NULL days'])[v_i] || ' is refused by grant_referral_days (22023)', v_st = '22023', 'got=' || v_st);
  END LOOP;
  PERFORM private.grant_referral_days(f[1], 1);
  PERFORM private.grant_referral_days(f[1], 30);
  SELECT count(*), max(end_date) INTO v_n, v_x FROM public.subscriptions WHERE user_id = f[1];
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('F5.5', '1 day and 30 days are accepted: one referral_trial row, then extended to now()+31 days', v_n = 1 AND v_x = now() + interval '31 days', format('rows=%s end=%s', v_n, v_x));
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- F-c: the chain. A real redemption, then nothing for the referrer; then the friend pays; then the vest; then ONE credit.
  PERFORM public.redeem_referral_atomic(v_code, r1, f[1], 7);
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*) INTO v_n FROM public.subscriptions WHERE user_id = r1;
  INSERT INTO _vr (id, descr, ok, note) VALUES ('F6a', 'chain: after a real redemption and a job run the referrer has NOTHING', v_n = 0, format('rows=%s', v_n));
  UPDATE public.referral_redemptions SET created_at = now() - interval '20 days' WHERE referee_id = f[1];
  INSERT INTO public.subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
  VALUES (f[1], 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_vfy_' || gen_random_uuid());
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  v_ret := private.process_referral_conversions();
  IF v_ret ? 'skipped' THEN RAISE EXCEPTION 'JOB_LOCKED the job lock is held by another run; retry in a minute'; END IF;
  SELECT count(*), max(end_date) INTO v_n, v_x FROM public.subscriptions WHERE user_id = r1;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('F6b', 'chain: after the friend pays and the vest passes, the referrer is credited exactly ONCE across two runs (one row, now()+7 days)',
      v_n = 1 AND v_x = now() + interval '7 days' AND (SELECT referrer_rewarded IS TRUE FROM public.referral_redemptions WHERE referee_id = f[1]), format('rows=%s end=%s', v_n, v_x));
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);
  DELETE FROM public.subscriptions WHERE user_id = ANY (v_pool);

  -- ============================================================ K. the CHECK constraints
  INSERT INTO public.referral_redemptions (id, code, referrer_id, referee_id, created_at) VALUES (gen_random_uuid(), v_code, r1, f[1], now()) RETURNING id INTO v_rid;
  BEGIN UPDATE public.referral_redemptions SET converted_at = now() WHERE id = v_rid; v_a1 := 'no error';
  EXCEPTION WHEN OTHERS THEN v_a1 := SQLSTATE; END;
  BEGIN UPDATE public.referral_redemptions SET converted_at = now(), referrer_reward_days = 8 WHERE id = v_rid; v_a2 := 'no error';
  EXCEPTION WHEN OTHERS THEN v_a2 := SQLSTATE; END;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('K1', 'converted_at without referrer_reward_days violates the coherence CHECK (23514)', v_a1 = '23514', 'got=' || v_a1),
    ('K2', 'referrer_reward_days = 8 violates the 7/30 CHECK (23514)', v_a2 = '23514', 'got=' || v_a2);
  BEGIN UPDATE public.referral_redemptions SET referrer_reward_days = 7 WHERE id = v_rid; v_a3 := 'no error';
  EXCEPTION WHEN OTHERS THEN v_a3 := SQLSTATE; END;
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('K3', 'referrer_reward_days without converted_at violates the coherence CHECK too (23514): the equality holds in BOTH directions', v_a3 = '23514', 'got=' || v_a3);
  DELETE FROM public.referral_redemptions WHERE referrer_id = ANY (v_pool) OR referee_id = ANY (v_pool);

  -- ============================================================ A. the catalog
  INSERT INTO _vr (id, descr, ok, note) VALUES
    ('A1', 'all three functions are SECURITY DEFINER with search_path=public',
      (SELECT count(*) = 3 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.prosecdef AND p.proconfig @> ARRAY['search_path=public']
          AND ((n.nspname = 'private' AND p.proname IN ('grant_referral_days', 'process_referral_conversions'))
            OR (n.nspname = 'public' AND p.proname = 'redeem_referral_atomic'))), NULL),
    ('A2', 'anon, authenticated and PUBLIC cannot execute any of the three; service_role can execute the redeem RPC',
      NOT has_function_privilege('anon', 'public.redeem_referral_atomic(text,uuid,uuid,integer)', 'execute')
      AND NOT has_function_privilege('authenticated', 'public.redeem_referral_atomic(text,uuid,uuid,integer)', 'execute')
      AND has_function_privilege('service_role', 'public.redeem_referral_atomic(text,uuid,uuid,integer)', 'execute')
      AND NOT has_function_privilege('anon', 'private.grant_referral_days(uuid,integer)', 'execute')
      AND NOT has_function_privilege('authenticated', 'private.grant_referral_days(uuid,integer)', 'execute')
      AND NOT has_function_privilege('anon', 'private.process_referral_conversions()', 'execute')
      AND NOT has_function_privilege('authenticated', 'private.process_referral_conversions()', 'execute')
      AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.proname IN ('grant_referral_days', 'process_referral_conversions', 'redeem_referral_atomic')
                         AND p.proacl::text ~ '(^|,|\{)=X'), NULL),
    ('A3', 'redeem_referral_atomic keeps its signature and RETURNS void',
      pg_get_function_result('public.redeem_referral_atomic(text,uuid,uuid,integer)'::regprocedure) = 'void', NULL),
    ('A4', 'the three new columns exist with their types (timestamptz, integer, timestamptz) and the two CHECK constraints are present',
      (SELECT count(*) = 3 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'referral_redemptions'
          AND ((column_name = 'converted_at' AND data_type = 'timestamp with time zone')
            OR (column_name = 'referrer_reward_days' AND data_type = 'integer')
            OR (column_name = 'referrer_credited_at' AND data_type = 'timestamp with time zone')))
      AND (SELECT count(*) = 2 FROM pg_constraint WHERE conrelid = 'public.referral_redemptions'::regclass
          AND conname IN ('referral_redemptions_reward_days_check', 'referral_redemptions_converted_coherent_check')), NULL),
    ('A5', 'the cron job exists: referral_conversions_hourly, 41 * * * *, calling the private function',
      (SELECT count(*) = 1 AND bool_and(schedule = '41 * * * *') AND bool_and(active) AND bool_and(command ~ 'private\.process_referral_conversions\(\)') FROM cron.job WHERE jobname = 'referral_conversions_hourly'), NULL),
    ('A6', 'every foreign key of referral_redemptions to users is ON DELETE SET NULL, and there are exactly two (referrer_id, referee_id)',
      NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.referral_redemptions'::regclass AND contype = 'f' AND confdeltype <> 'n')
      AND (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.referral_redemptions'::regclass AND contype = 'f' AND confdeltype = 'n' AND confrelid = 'public.users'::regclass) = 2, NULL),
    ('A7', 'referral_redemptions.referrer_id and referee_id are nullable',
      NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.referral_redemptions'::regclass AND attname IN ('referrer_id', 'referee_id') AND attnotnull), NULL),
    ('A8', 'referral_redemptions: RLS is enabled and no INSERT/UPDATE/DELETE policy exists for anon, authenticated or PUBLIC (a user cannot rewrite the rows the reward is read from)',
      (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.referral_redemptions'::regclass)
      AND NOT EXISTS (SELECT 1 FROM pg_policy pp WHERE pp.polrelid = 'public.referral_redemptions'::regclass AND pp.polcmd <> 'r'
                       AND (pp.polroles = '{0}'::oid[] OR EXISTS (SELECT 1 FROM pg_roles rl WHERE rl.oid = ANY (pp.polroles) AND rl.rolname IN ('anon', 'authenticated')))), NULL),
    ('A9', 'subscriptions: RLS is enabled and no INSERT/UPDATE/DELETE policy exists for anon, authenticated or PUBLIC (a user cannot forge the paid row the reward is read from)',
      (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.subscriptions'::regclass)
      AND NOT EXISTS (SELECT 1 FROM pg_policy pp WHERE pp.polrelid = 'public.subscriptions'::regclass AND pp.polcmd <> 'r'
                       AND (pp.polroles = '{0}'::oid[] OR EXISTS (SELECT 1 FROM pg_roles rl WHERE rl.oid = ANY (pp.polroles) AND rl.rolname IN ('anon', 'authenticated')))), NULL);

  SELECT count(*) FILTER (WHERE ok), count(*) FILTER (WHERE NOT ok), count(*) FILTER (WHERE descr LIKE '%[SKIPPED%') INTO v_ok, v_fail, v_skip FROM _vr;
  SELECT string_agg(format('%s %s  %s', id, descr, CASE WHEN ok THEN 'ok' ELSE 'fail ' || coalesce(note, '') END), E'\n' ORDER BY ord) INTO v_res FROM _vr;
  RAISE EXCEPTION 'VERIFY_RESULTS%', E'\nSUMMARY ok=' || v_ok || ' fail=' || v_fail || ' skipped=' || v_skip || E'\n' || v_res;
END
$v$;
