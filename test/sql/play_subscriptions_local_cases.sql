-- test/sql/play_subscriptions_local_cases.sql
--
-- Behavioural proof of migration 182 (OI-519, plan docs/plans/2026-11-23-revenuecat-play-billing-51.md, tests T-SQL1..3 and the
-- SQL half of T-DEFER). LOCAL ONLY: run by test/sql/play_subscriptions_local.sh against a disposable replica
-- (test/sql/referral_pay_on_conversion_replica_schema.sql + 159 + 160 [+ 182]). Every case runs in its own BEGIN ... ROLLBACK and
-- RAISEs on a wrong outcome, so a failing case stops the run (ON_ERROR_STOP) and nothing persists.
--
-- Part N (psql -v part=N) holds the cases that involve NO Play row. The runner executes them on BOTH databases: passing on the
-- pre-182 database proves each assertion encodes the old behaviour; passing on the 182 database proves 182 leaves it unchanged
-- (T-SQL1, the pitfall "run it against the code it REPLACES"). Part P (psql -v part=P) holds the Play cases, 182 only.

\set ON_ERROR_STOP 1
SET client_min_messages = warning;

SELECT :'part' = 'N' AS run_n, :'part' = 'P' AS run_p \gset

\if :run_n
-- =====================================================================================================================
-- N1 grant, user with no row: one referral_trial row ending now + 7 days.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000a1');
SELECT private.grant_referral_days('00000000-0000-4000-8000-0000000000a1', 7);
DO $$ BEGIN
  IF (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000a1') <> 1
     OR NOT EXISTS (SELECT 1 FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000a1'
                     AND plan = 'referral_trial' AND status = 'active'
                     AND end_date BETWEEN now() + interval '7 days' - interval '1 minute' AND now() + interval '7 days' + interval '1 minute')
  THEN RAISE EXCEPTION 'N1 failed: expected one 7-day referral_trial row'; END IF;
END $$;
ROLLBACK;

-- N2 grant, user with an active paid web row: that row moves by 7 days, no new row.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000a2');
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
VALUES ('00000000-0000-4000-8000-0000000000a2', 'monthly', 'active', now() - interval '5 days', now() + interval '25 days', 'pay_n2');
SELECT private.grant_referral_days('00000000-0000-4000-8000-0000000000a2', 7);
DO $$ BEGIN
  IF (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000a2') <> 1
     OR (SELECT end_date FROM subscriptions WHERE razorpay_payment_id = 'pay_n2')
        NOT BETWEEN now() + interval '32 days' - interval '1 minute' AND now() + interval '32 days' + interval '1 minute'
  THEN RAISE EXCEPTION 'N2 failed: expected the web row extended by 7 days'; END IF;
END $$;
ROLLBACK;

-- N3 grant, latest active row already past its end: a new trial row.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000a3');
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
VALUES ('00000000-0000-4000-8000-0000000000a3', 'monthly', 'active', now() - interval '40 days', now() - interval '10 days', 'pay_n3');
SELECT private.grant_referral_days('00000000-0000-4000-8000-0000000000a3', 7);
DO $$ BEGIN
  IF (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000a3' AND plan = 'referral_trial') <> 1
  THEN RAISE EXCEPTION 'N3 failed: expected a new trial row'; END IF;
END $$;
ROLLBACK;

-- N4 grant with 0 days: 22023.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000a4');
DO $$ BEGIN
  BEGIN
    PERFORM private.grant_referral_days('00000000-0000-4000-8000-0000000000a4', 0);
    RAISE EXCEPTION 'N4 failed: no error';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
END $$;
ROLLBACK;

-- N5 redeem: a referee with a paid web row is refused (P0001).
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000b1'), ('00000000-0000-4000-8000-0000000000b2');
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
VALUES ('00000000-0000-4000-8000-0000000000b2', 'monthly', 'active', now(), now() + interval '30 days', 'pay_n5');
DO $$ BEGIN
  BEGIN
    PERFORM redeem_referral_atomic('CODE', '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b2', 7);
    RAISE EXCEPTION 'N5 failed: paid referee accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referee_has_paid_plan' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK;

-- N6 redeem: an unpaid referee gets the audit row and 7 trial days.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000b3'), ('00000000-0000-4000-8000-0000000000b4');
SELECT redeem_referral_atomic('CODE', '00000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-0000000000b4', 7);
DO $$ BEGIN
  IF (SELECT count(*) FROM referral_redemptions WHERE referee_id = '00000000-0000-4000-8000-0000000000b4') <> 1
     OR (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000b4' AND plan = 'referral_trial') <> 1
  THEN RAISE EXCEPTION 'N6 failed'; END IF;
END $$;
ROLLBACK;

-- N7 job: a friend's web payment inside the window, vested: converted and the referrer credited 7 days (new trial row).
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000c1'), ('00000000-0000-4000-8000-0000000000c2');
INSERT INTO referral_redemptions (code, referrer_id, referee_id, days_granted_each, referrer_rewarded, referee_rewarded, created_at)
VALUES ('CODE', '00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000c2', 7, false, true, now() - interval '20 days');
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
VALUES ('00000000-0000-4000-8000-0000000000c2', 'monthly', 'active', now() - interval '10 days', now() + interval '20 days', 'pay_n7');
SELECT private.process_referral_conversions();
DO $$ BEGIN
  IF NOT (SELECT referrer_rewarded FROM referral_redemptions WHERE referee_id = '00000000-0000-4000-8000-0000000000c2')
     OR (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000c1' AND plan = 'referral_trial') <> 1
  THEN RAISE EXCEPTION 'N7 failed: referrer not credited'; END IF;
END $$;
ROLLBACK;
\endif

\if :run_p
-- =====================================================================================================================
-- Fixture helper (182 database only): a Play row through the real writer.
-- P1 upsert: insert 'written'; an OLDER read is 'stale_read' and changes nothing; a newer read updates.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000d1');
DO $$
DECLARE r text;
BEGIN
  r := upsert_play_subscription('00000000-0000-4000-8000-0000000000d1', 'avya_pro', 'monthly', 'active',
         now() - interval '1 day', now() + interval '29 days', true, 'PRODUCTION', 'GPA.1', now() + interval '29 days', now());
  IF r <> 'written' THEN RAISE EXCEPTION 'P1 failed: first write returned %', r; END IF;
  r := upsert_play_subscription('00000000-0000-4000-8000-0000000000d1', 'avya_pro', 'monthly', 'cancelled',
         now() - interval '1 day', now(), false, 'PRODUCTION', 'GPA.1', now(), now() - interval '1 minute');
  IF r <> 'stale_read' THEN RAISE EXCEPTION 'P1 failed: older read returned %', r; END IF;
  IF (SELECT status FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000d1') <> 'active' THEN
    RAISE EXCEPTION 'P1 failed: stale read changed the row'; END IF;
  r := upsert_play_subscription('00000000-0000-4000-8000-0000000000d1', 'avya_pro', 'yearly', 'active',
         now() - interval '1 day', now() + interval '364 days', true, 'PRODUCTION', 'GPA.2', now() + interval '364 days', now() + interval '1 minute');
  IF r <> 'written' OR (SELECT plan FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000d1') <> 'yearly'
     OR (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000d1') <> 1 THEN
    RAISE EXCEPTION 'P1 failed: monthly -> yearly must update the one row'; END IF;
END $$;
ROLLBACK;

-- P2 upsert start_date chain: an active row keeps its start across a renewal; after expiry a resubscribe starts fresh.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000d2');
DO $$
DECLARE t0 timestamptz := now() - interval '40 days';
BEGIN
  PERFORM upsert_play_subscription('00000000-0000-4000-8000-0000000000d2', 'avya_pro', 'monthly', 'active',
            t0, t0 + interval '30 days', true, 'PRODUCTION', 'GPA.a', t0 + interval '30 days', now() - interval '3 minutes');
  PERFORM upsert_play_subscription('00000000-0000-4000-8000-0000000000d2', 'avya_pro', 'monthly', 'active',
            t0 + interval '30 days', t0 + interval '60 days', true, 'PRODUCTION', 'GPA.b', t0 + interval '60 days', now() - interval '2 minutes');
  IF (SELECT start_date FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000d2') <> t0 THEN
    RAISE EXCEPTION 'P2 failed: renewal moved start_date'; END IF;
  PERFORM upsert_play_subscription('00000000-0000-4000-8000-0000000000d2', 'avya_pro', 'monthly', 'expired',
            t0 + interval '30 days', t0 + interval '60 days', false, 'PRODUCTION', 'GPA.b', t0 + interval '60 days', now() - interval '1 minute');
  PERFORM upsert_play_subscription('00000000-0000-4000-8000-0000000000d2', 'avya_pro', 'monthly', 'active',
            now(), now() + interval '30 days', true, 'PRODUCTION', 'GPA.c', now() + interval '30 days', now());
  IF (SELECT start_date FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000d2') < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'P2 failed: a resubscribe after expiry kept the old start'; END IF;
END $$;
ROLLBACK;

-- P3 upsert rejects bad arguments (22023) and the CHECK rejects a Play row without store_read_at (23514).
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000d3');
DO $$ BEGIN
  BEGIN
    PERFORM upsert_play_subscription('00000000-0000-4000-8000-0000000000d3', 'avya_pro', 'weekly', 'active',
              now(), now() + interval '7 days', true, 'PRODUCTION', NULL, now(), now());
    RAISE EXCEPTION 'P3 failed: plan weekly accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
  BEGIN
    INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, store, store_product_id, store_environment)
    VALUES ('00000000-0000-4000-8000-0000000000d3', 'monthly', 'active', now(), now() + interval '30 days', 'play', 'avya_pro', 'SANDBOX');
    RAISE EXCEPTION 'P3 failed: Play row without store_read_at accepted';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL; END;
END $$;
ROLLBACK;

-- P4 grant with an ACTIVE Play row: one pending deferral; the subscriptions rows are byte-identical before and after.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000e1');
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000e1', 'avya_pro', 'monthly', 'active',
         now() - interval '1 day', now() + interval '29 days', true, 'PRODUCTION', 'GPA.e1', now() + interval '29 days', now());
CREATE TEMP TABLE before_p4 AS SELECT * FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e1';
SELECT private.grant_referral_days('00000000-0000-4000-8000-0000000000e1', 7);
DO $$ BEGIN
  IF (SELECT count(*) FROM store_reward_deferrals WHERE user_id = '00000000-0000-4000-8000-0000000000e1' AND status = 'pending' AND days = 7 AND store = 'play') <> 1
  THEN RAISE EXCEPTION 'P4 failed: no pending deferral'; END IF;
  IF EXISTS (SELECT * FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e1' EXCEPT SELECT * FROM before_p4)
     OR EXISTS (SELECT * FROM before_p4 EXCEPT SELECT * FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e1')
  THEN RAISE EXCEPTION 'P4 failed: subscriptions changed'; END IF;
END $$;
ROLLBACK;

-- P5 grant with a Play row past its end (still status active) and an active web row: the web row is extended, the Play row is
-- never picked for the in-place extension, nothing is queued.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000e2');
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000e2', 'avya_pro', 'monthly', 'active',
         now() - interval '40 days', now() + interval '60 days', true, 'PRODUCTION', 'GPA.e2', now() + interval '60 days', now());
UPDATE subscriptions SET end_date = now() - interval '1 hour' WHERE user_id = '00000000-0000-4000-8000-0000000000e2' AND store = 'play';
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date, razorpay_payment_id)
VALUES ('00000000-0000-4000-8000-0000000000e2', 'monthly', 'active', now() - interval '2 days', now() + interval '28 days', 'pay_p5');
SELECT private.grant_referral_days('00000000-0000-4000-8000-0000000000e2', 7);
DO $$ BEGIN
  IF (SELECT end_date FROM subscriptions WHERE razorpay_payment_id = 'pay_p5') < now() + interval '35 days' - interval '1 minute'
     OR (SELECT end_date FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e2' AND store = 'play') > now()
     OR EXISTS (SELECT 1 FROM store_reward_deferrals WHERE user_id = '00000000-0000-4000-8000-0000000000e2')
  THEN RAISE EXCEPTION 'P5 failed'; END IF;
END $$;
ROLLBACK;

-- P6 grant when the ONLY active row is a Play row already past its end: a new trial row, the Play row untouched.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000e3');
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000e3', 'avya_pro', 'monthly', 'active',
         now() - interval '40 days', now() + interval '1 day', true, 'PRODUCTION', 'GPA.e3', now(), now());
UPDATE subscriptions SET end_date = now() - interval '1 hour' WHERE user_id = '00000000-0000-4000-8000-0000000000e3';
SELECT private.grant_referral_days('00000000-0000-4000-8000-0000000000e3', 7);
DO $$ BEGIN
  IF (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e3' AND plan = 'referral_trial') <> 1
     OR (SELECT end_date FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e3' AND store = 'play') > now()
  THEN RAISE EXCEPTION 'P6 failed'; END IF;
END $$;
ROLLBACK;

-- P7 grant argument check comes first: a Play user with 0 days raises 22023, not a deferral CHECK violation (23514).
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000e4');
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000e4', 'avya_pro', 'monthly', 'active',
         now(), now() + interval '30 days', true, 'PRODUCTION', 'GPA.e4', now() + interval '30 days', now());
DO $$ BEGIN
  BEGIN
    PERFORM private.grant_referral_days('00000000-0000-4000-8000-0000000000e4', 0);
    RAISE EXCEPTION 'P7 failed: no error';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
END $$;
ROLLBACK;

-- P8 redeem: a PRODUCTION Play referee is refused; a SANDBOX Play referee is accepted and the days are queued as a deferral.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000f1'), ('00000000-0000-4000-8000-0000000000f2'), ('00000000-0000-4000-8000-0000000000f3');
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000f2', 'avya_pro', 'monthly', 'active',
         now(), now() + interval '30 days', true, 'PRODUCTION', 'GPA.f2', now() + interval '30 days', now());
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000f3', 'avya_pro', 'monthly', 'active',
         now(), now() + interval '30 days', true, 'SANDBOX', 'GPA.f3', now() + interval '30 days', now());
DO $$ BEGIN
  BEGIN
    PERFORM redeem_referral_atomic('CODE', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f2', 7);
    RAISE EXCEPTION 'P8 failed: PRODUCTION Play referee accepted';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'referee_has_paid_plan' THEN RAISE; END IF;
  END;
  PERFORM redeem_referral_atomic('CODE', '00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000f3', 7);
  IF (SELECT count(*) FROM store_reward_deferrals WHERE user_id = '00000000-0000-4000-8000-0000000000f3' AND status = 'pending') <> 1
  THEN RAISE EXCEPTION 'P8 failed: SANDBOX referee not queued'; END IF;
END $$;
ROLLBACK;

-- P9 job: a friend's PRODUCTION Play row converts and credits; a SANDBOX one does not convert.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000f4'), ('00000000-0000-4000-8000-0000000000f5'),
                         ('00000000-0000-4000-8000-0000000000f6'), ('00000000-0000-4000-8000-0000000000f7');
INSERT INTO referral_redemptions (code, referrer_id, referee_id, days_granted_each, referrer_rewarded, referee_rewarded, created_at)
VALUES ('CODE', '00000000-0000-4000-8000-0000000000f4', '00000000-0000-4000-8000-0000000000f5', 7, false, true, now() - interval '20 days'),
       ('CODE', '00000000-0000-4000-8000-0000000000f6', '00000000-0000-4000-8000-0000000000f7', 7, false, true, now() - interval '20 days');
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000f5', 'avya_pro', 'monthly', 'active',
         now() - interval '10 days', now() + interval '20 days', true, 'PRODUCTION', 'GPA.f5', now() + interval '20 days', now());
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000f7', 'avya_pro', 'monthly', 'active',
         now() - interval '10 days', now() + interval '20 days', true, 'SANDBOX', 'GPA.f7', now() + interval '20 days', now());
SELECT private.process_referral_conversions();
DO $$ BEGIN
  IF NOT (SELECT referrer_rewarded FROM referral_redemptions WHERE referee_id = '00000000-0000-4000-8000-0000000000f5')
  THEN RAISE EXCEPTION 'P9 failed: PRODUCTION Play payment not credited'; END IF;
  IF (SELECT converted_at FROM referral_redemptions WHERE referee_id = '00000000-0000-4000-8000-0000000000f7') IS NOT NULL
  THEN RAISE EXCEPTION 'P9 failed: SANDBOX Play row counted as paid'; END IF;
END $$;
ROLLBACK;

-- P10 fall-back compare-and-set and stacking.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000a9');
INSERT INTO store_reward_deferrals (id, user_id, store, days, status)
VALUES ('11111111-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a9', 'play', 7, 'pending'),
       ('11111111-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000a9', 'play', 5, 'pending'),
       ('11111111-0000-4000-8000-000000000003', '00000000-0000-4000-8000-0000000000a9', 'play', 3, 'applied');
DO $$
DECLARE r text;
BEGIN
  r := store_reward_fall_back('11111111-0000-4000-8000-000000000001', NULL);
  IF r <> 'fell_back' THEN RAISE EXCEPTION 'P10 failed: pending + NULL returned %', r; END IF;
  r := store_reward_fall_back('11111111-0000-4000-8000-000000000001', NULL);
  IF r <> 'noop' THEN RAISE EXCEPTION 'P10 failed: second call returned %', r; END IF;
  r := store_reward_fall_back('11111111-0000-4000-8000-000000000002', NULL);
  IF (SELECT end_date FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000a9' AND plan = 'referral_trial')
     NOT BETWEEN now() + interval '12 days' - interval '1 minute' AND now() + interval '12 days' + interval '1 minute'
     OR (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000a9') <> 1
  THEN RAISE EXCEPTION 'P10 failed: two fall-backs did not stack to 12 days'; END IF;
  r := store_reward_fall_back('11111111-0000-4000-8000-000000000003', NULL);
  IF r <> 'noop' OR (SELECT status FROM store_reward_deferrals WHERE id = '11111111-0000-4000-8000-000000000003') <> 'applied'
  THEN RAISE EXCEPTION 'P10 failed: an applied row was touched'; END IF;
END $$;
ROLLBACK;

-- P11 fall-back of a claimed row needs ITS token; one in flight per user.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000aa');
INSERT INTO store_reward_deferrals (id, user_id, store, days, status, claim_token, claimed_at)
VALUES ('22222222-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000aa', 'play', 7, 'in_flight',
        '33333333-0000-4000-8000-000000000001', now()),
       ('22222222-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000000aa', 'play', 7, 'needs_check',
        '33333333-0000-4000-8000-000000000002', now() - interval '2 hours'),
       ('22222222-0000-4000-8000-000000000003', '00000000-0000-4000-8000-0000000000aa', 'play', 7, 'pending', NULL, NULL);
DO $$
DECLARE r text;
BEGIN
  r := store_reward_fall_back('22222222-0000-4000-8000-000000000001', NULL);
  IF r <> 'noop' THEN RAISE EXCEPTION 'P11 failed: in_flight fell back without a token'; END IF;
  r := store_reward_fall_back('22222222-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000002');
  IF r <> 'noop' THEN RAISE EXCEPTION 'P11 failed: in_flight fell back with another token'; END IF;
  r := store_reward_fall_back('22222222-0000-4000-8000-000000000002', '33333333-0000-4000-8000-000000000002');
  IF r <> 'fell_back' THEN RAISE EXCEPTION 'P11 failed: needs_check with its token returned %', r; END IF;
  BEGIN
    UPDATE store_reward_deferrals SET status = 'in_flight', claim_token = gen_random_uuid(), claimed_at = now()
     WHERE id = '22222222-0000-4000-8000-000000000003' AND status = 'pending';
    RAISE EXCEPTION 'P11 failed: a second in_flight row for one user was accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
ROLLBACK;

-- P13 fall-back while the user's Play row is still active (the drain falls back e.g. after a refused defer): the days land as a
-- separate trial row; the Play row's end_date is never extended in place (the mirror would overwrite it).
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000ab');
SELECT upsert_play_subscription('00000000-0000-4000-8000-0000000000ab', 'avya_pro', 'monthly', 'active',
         now() - interval '1 day', now() + interval '29 days', true, 'PRODUCTION', 'GPA.ab', now() + interval '29 days', now());
INSERT INTO store_reward_deferrals (id, user_id, store, days, status)
VALUES ('44444444-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000ab', 'play', 7, 'pending');
DO $$ BEGIN
  IF store_reward_fall_back('44444444-0000-4000-8000-000000000001', NULL) <> 'fell_back' THEN RAISE EXCEPTION 'P13 failed: no fall-back'; END IF;
  IF (SELECT end_date FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000ab' AND store = 'play')
       > now() + interval '29 days' + interval '1 minute'
     OR (SELECT count(*) FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000ab' AND plan = 'referral_trial') <> 1
  THEN RAISE EXCEPTION 'P13 failed: the Play row was extended in place'; END IF;
END $$;
ROLLBACK;

-- P14 upsert tie and environment (B-pass of the draft, F1): an EQUAL read_at is 'stale_read' and changes nothing; a newer
-- SANDBOX read never replaces a running PRODUCTION row ('sandbox_refused', row unchanged); once that PRODUCTION row has ended,
-- a newer SANDBOX read is written.
BEGIN;
INSERT INTO users VALUES ('00000000-0000-4000-8000-0000000000e1');
DO $$
DECLARE r text; t0 timestamptz := now();
BEGIN
  r := upsert_play_subscription('00000000-0000-4000-8000-0000000000e1', 'avya_pro', 'monthly', 'active',
         t0 - interval '1 day', t0 + interval '29 days', true, 'PRODUCTION', 'GPA.e1', t0 + interval '29 days', t0);
  IF r <> 'written' THEN RAISE EXCEPTION 'P14 failed: first write returned %', r; END IF;
  r := upsert_play_subscription('00000000-0000-4000-8000-0000000000e1', 'avya_pro', 'yearly', 'cancelled',
         t0 - interval '1 day', t0, false, 'PRODUCTION', 'GPA.e1', t0, t0);
  IF r <> 'stale_read' THEN RAISE EXCEPTION 'P14 failed: tied read returned %', r; END IF;
  IF (SELECT plan || '|' || status FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e1') <> 'monthly|active' THEN
    RAISE EXCEPTION 'P14 failed: tied read changed the row'; END IF;
  r := upsert_play_subscription('00000000-0000-4000-8000-0000000000e1', 'avya_pro', 'yearly', 'active',
         t0, t0 + interval '365 days', true, 'SANDBOX', 'GPA.e1s', t0 + interval '365 days', t0 + interval '1 minute');
  IF r <> 'sandbox_refused' THEN RAISE EXCEPTION 'P14 failed: SANDBOX over running PRODUCTION returned %', r; END IF;
  IF (SELECT store_environment || '|' || plan FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e1')
       <> 'PRODUCTION|monthly' THEN
    RAISE EXCEPTION 'P14 failed: SANDBOX read replaced a running PRODUCTION row'; END IF;
  -- the PRODUCTION row ends (a newer PRODUCTION read), then a newer SANDBOX read may land
  r := upsert_play_subscription('00000000-0000-4000-8000-0000000000e1', 'avya_pro', 'monthly', 'expired',
         t0 - interval '31 days', t0 - interval '1 day', false, 'PRODUCTION', 'GPA.e1', t0 - interval '1 day', t0 + interval '2 minutes');
  IF r <> 'written' THEN RAISE EXCEPTION 'P14 failed: PRODUCTION expiry returned %', r; END IF;
  r := upsert_play_subscription('00000000-0000-4000-8000-0000000000e1', 'avya_pro', 'yearly', 'active',
         t0, t0 + interval '365 days', true, 'SANDBOX', 'GPA.e1s', t0 + interval '365 days', t0 + interval '3 minutes');
  IF r <> 'written' OR (SELECT store_environment FROM subscriptions WHERE user_id = '00000000-0000-4000-8000-0000000000e1') <> 'SANDBOX'
  THEN RAISE EXCEPTION 'P14 failed: SANDBOX after an ended PRODUCTION row returned %', r; END IF;
END $$;
ROLLBACK;

-- P12 no client role reaches the new writers or tables; the replaced functions are still SECURITY DEFINER.
DO $$ BEGIN
  IF has_function_privilege('authenticated', 'public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.store_reward_fall_back(uuid, uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.store_reward_deferrals', 'SELECT')
     OR has_table_privilege('anon', 'public.subscription_events', 'INSERT')
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'private.grant_referral_days(uuid, integer)'::regprocedure)
  THEN RAISE EXCEPTION 'P12 failed: ACL or security mode'; END IF;
END $$;
\endif

SELECT 'cases ' || :'part' || ' passed' AS result;
