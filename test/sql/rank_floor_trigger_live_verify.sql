-- Live verify for migration 184 (diagnose 8b1f3d): the floor rung never
-- dispatches a coach congratulation; every higher rung still does.
--
-- Run as ONE execute_sql request against project dedsavbjuwgarrhphgnl. The
-- whole block is BEGIN ... ROLLBACK: the fixture changes, the pg_net queue
-- rows and any telemetry the dispatch function writes are all rolled back, so
-- no HTTP request is ever sent (pg_net sends only committed queue rows).
--
-- Fixture: rank_promotions.user_id has a FK to users, so the block borrows a
-- (testing) account that holds ONLY the floor rung, deletes that row and
-- re-inserts it (inside the rolled-back transaction), then inserts SD1.
--
-- Expected BEFORE migration 184 (the bug): floor_queued = 1, sd1_queued = 1.
-- Expected AFTER  migration 184:           floor_queued = 0, sd1_queued = 1.

BEGIN;

DO $$
DECLARE
  v_uid uuid;
  q0 bigint;
  q1 bigint;
  q2 bigint;
BEGIN
  SELECT user_id INTO v_uid
    FROM public.rank_promotions
   GROUP BY user_id
  HAVING count(*) = 1 AND bool_and(rank_code = 'SD2')
   LIMIT 1;
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'no floor-only account to borrow';
  END IF;

  DELETE FROM public.rank_promotions WHERE user_id = v_uid AND rank_code = 'SD2';

  SELECT count(*) INTO q0 FROM net.http_request_queue;

  INSERT INTO public.rank_promotions (user_id, rank_code, trigger_type)
  VALUES (v_uid, 'SD2', 'signup');
  SELECT count(*) INTO q1 FROM net.http_request_queue;

  INSERT INTO public.rank_promotions (user_id, rank_code, trigger_type)
  VALUES (v_uid, 'SD1', 'combined');
  SELECT count(*) INTO q2 FROM net.http_request_queue;

  PERFORM set_config('rank_floor_verify.floor', (q1 - q0)::text, true);
  PERFORM set_config('rank_floor_verify.sd1', (q2 - q1)::text, true);
END $$;

SELECT current_setting('rank_floor_verify.floor') AS floor_queued,
       current_setting('rank_floor_verify.sd1')   AS sd1_queued,
       (SELECT pg_get_triggerdef(oid) FROM pg_trigger
         WHERE tgname = 'trg_dispatch_proactive_coach_promotion') AS trigger_def;

ROLLBACK;
