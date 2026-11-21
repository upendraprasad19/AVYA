-- Intent: Reward a REFERRER with PRO days only when the friend they referred actually pays (7 days for a monthly payment, 30 for yearly), instead of at the moment the friend applies the code (founder decision 2026-10-12, replacing the 7-per-90-days cap of migration 158). The friend still gets 7 days at once.
-- Destructive?: no   -- three nullable columns and two CHECKs added, two private functions created, one function body replaced (same signature, return type and ACL), one cron job created; no row rewritten, no column dropped
-- Rollback strategy: inline   -- a commented block at the end of the file: unschedule the job, restore the 158 body verbatim, then drop the private functions, the CHECKs and the columns
-- Linked diagnose-doc: n/a   -- a product rule, not a bug fix: docs/plans/referral-pay-on-conversion.md

-- 159_referral_reward_on_conversion.sql
--
-- WHY. Migration 158 paid the referrer at redemption and capped it at 7 credited referrals per rolling 90 days (49 PRO days
-- per 90, about 54 percent). The founder judged that loss-making and asked for the reward to come out of revenue: the friend
-- gets 7 days when they apply a code; the referrer gets 7 days (monthly) or 30 days (yearly) once that friend has PAID, with
-- no cap on invites. Plan, three review rounds and the measured lock behaviour: docs/plans/referral-pay-on-conversion.md.
--
-- HOW (no payment function is edited, no trigger is placed on public.subscriptions). The two writers of a paid row
-- (razorpay-webhook and verify-payment) INSERT one `monthly` / `yearly` row per captured payment, with razorpay_payment_id
-- set, and nothing else in the tree updates that table but 038/158 and the cancelled_at trigger. An hourly pg_cron job
-- reads those rows:
--   1. RECONCILE  every unrewarded redemption that is still inside the 97-day detection scan, or already pending, is set to
--                 the referee's EARLIEST qualifying payment (a paid row, status active, not cancelled, made on or after the
--                 redemption and no later than 90 days after it): converted_at = its start_date, referrer_reward_days =
--                 30 for yearly and 7 for monthly; NULL when there is none. A payment cancelled before the vest therefore
--                 voids the row, a later one re-arms it, and a deleted referee (referee_id NULL) matches nothing.
--   2. CREDIT     a pending row whose payment is at least 7 days old is credited ONCE: the referrer's PRO is extended and
--                 referrer_rewarded flips to true, in one sub-block, so a failure undoes both and the row is retried.
-- The three legacy rows (June 2026, 108 to 117 days old) are outside the scan and are never touched.
--
-- referrer_rewarded CHANGES MEANING: under 158 it meant "credited at redemption"; from here it means "the reward has been
-- credited". A row written under live 158 with the flag already true is excluded by the job and stays as it was.
--
-- NEVER WAITS. The job never waits for a ROW or ADVISORY lock: pg_try_advisory_xact_lock, FOR UPDATE SKIP LOCKED, NOWAIT on the grant
-- helper's row and a FOR KEY SHARE NOWAIT on the referrer's public.users row before any INSERT into subscriptions. The last
-- one is not decoration: the foreign key of that INSERT takes a key-share lock on the users row, which queues behind an
-- uncommitted account deletion, whose cascade in turn waits for the redemption row the job holds. MEASURED on PostgreSQL
-- 17.6: without it `deadlock detected`, with it a clean skip. redeem_referral_atomic CAN wait (one blocking advisory lock on
-- the REFEREE's key, behind a running job that credits that user; its INSERTs behind a deletion of the referee). The job does
-- still take ordinary table-level locks, which queue behind a pending ACCESS EXCLUSIVE of some later migration; no function-level
-- lock_timeout is set on purpose (it would fire in the reconcile statement, outside every sub-block, and fail the whole run on
-- benign DDL contention).
--
-- BATCH. At most 50 rewards are credited per run: each sub-block takes a subtransaction id (a backend caches 64 before other
-- sessions' snapshots are marked overflowed) and every lock a processed row took lives until the end of the run. A backlog after
-- an outage clears 50 an hour; the stall alert below covers one that does not.
--
-- STALL WATCH. The job's own result ({"skipped":"locked"}, skipped_locked) is discarded by pg_cron, and migration 146 sees only
-- a job that stopped launching or ran and FAILED: a run that returns `skipped` still writes a `succeeded` row. So a reward
-- stall (a forgotten session holding the job's lock, a referrer key or subscription row held for days) would be invisible.
-- The FIRST thing every run does, before it tries the job lock, is count the rewards that have stood pending more than 10 days
-- (a 7-day vest plus 3 days; a healthy row is credited within the hour after its vest) and raise the warn alert
-- `referral_conversions_stalled`, deduplicated like the others. Because it runs before the lock, it still fires while another
-- run holds the lock. It cannot fire when the job is switched off (cron.job.active = false): that is 146's weekly re-surfacing.
--
-- PRIVACY. There is deliberately no payment-id column: the existing SELECT policy shows a redemption row to its referrer
-- AND its referee, and one friend's Razorpay payment id must not become readable by the other. converted_at,
-- referrer_reward_days and referrer_credited_at ARE readable by both parties: that a friend subscribed, roughly when, and
-- which plan (7 vs 30) is what the product shows the referrer.
--
-- KNOWN LIMITS, stated so nobody reads this as stronger than it is: (1) a refund or dispute that does not touch the
-- subscriptions row is invisible (neither payment function handles refund events); a cancel after the vest has no
-- clawback; (2) the friend cannot buy while on the 7-day referral trial (create-razorpay-order answers 409 for any active
-- row), so the reward lands about 14 days after the friend joins; (3) a payment inserted between the grant helper's read
-- and its update can leave the extended row below the new maximum (days wasted for that grant; the same window as 038 and
-- 158); (4) the first qualifying payment decides the reward: a monthly payer who upgrades to yearly does not top the referrer up.
--
-- IDEMPOTENT: ADD COLUMN IF NOT EXISTS, each CHECK is dropped if present and added in ONE ALTER TABLE, CREATE OR REPLACE,
-- the cron job is unscheduled BY JOBID (Gate 31 treats a quoted-name unschedule as "the job is gone", OI-193) and
-- scheduled again, so a half-applied file converges on a re-run. The DDL is bounded by a 3-second lock_timeout.

SET lock_timeout = '3s';

ALTER TABLE public.referral_redemptions
  ADD COLUMN IF NOT EXISTS converted_at          timestamptz,
  ADD COLUMN IF NOT EXISTS referrer_reward_days  integer,
  ADD COLUMN IF NOT EXISTS referrer_credited_at  timestamptz;

ALTER TABLE public.referral_redemptions
  DROP CONSTRAINT IF EXISTS referral_redemptions_reward_days_check,
  DROP CONSTRAINT IF EXISTS referral_redemptions_converted_coherent_check,
  ADD  CONSTRAINT referral_redemptions_reward_days_check
       CHECK (referrer_reward_days IS NULL OR referrer_reward_days IN (7, 30)),
  ADD  CONSTRAINT referral_redemptions_converted_coherent_check
       CHECK ((converted_at IS NULL) = (referrer_reward_days IS NULL));

RESET lock_timeout;

-- ---------------------------------------------------------------------------------------------------------------------
-- private.grant_referral_days: the ONE implementation of "extend a user's PRO by N days" (158 wrote it twice).
-- Reads the user's latest active row with FOR UPDATE NOWAIT (a row held by someone else raises 55P03 at once); no active
-- row, or one already past, INSERTs a referral_trial row; otherwise the latest row's end_date is moved by id.
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.grant_referral_days(p_user_id uuid, p_days integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id  uuid;
  v_end timestamptz;
BEGIN
  IF p_user_id IS NULL OR p_days IS NULL OR p_days < 1 OR p_days > 30 THEN
    RAISE EXCEPTION 'grant_referral_days: a user and 1..30 days are required (got %, %)', p_user_id, p_days
      USING ERRCODE = '22023';
  END IF;

  SELECT s.id, s.end_date INTO v_id, v_end
    FROM subscriptions s
   WHERE s.user_id = p_user_id AND s.status = 'active'
   ORDER BY s.end_date DESC, s.id
   LIMIT 1
   FOR UPDATE NOWAIT;

  IF v_id IS NULL OR v_end < now() THEN
    INSERT INTO subscriptions (user_id, plan, status, start_date, end_date)
    VALUES (p_user_id, 'referral_trial', 'active', now(), now() + (p_days || ' days')::interval);
  ELSE
    UPDATE subscriptions
       SET end_date = end_date + (p_days || ' days')::interval
     WHERE id = v_id;
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- public.redeem_referral_atomic: same signature, return type, security mode and ACL as 158. The REFEREE is credited; the
-- REFERRER is not (the job above does that when the friend pays). One advisory lock, the referee's. A referee who has ever
-- paid is refused (an existing subscriber would otherwise be handed free days); the Edge Function maps the message to a 400.
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.redeem_referral_atomic(
  p_code text,
  p_referrer_id uuid,
  p_referee_id uuid,
  p_days integer
)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_key_referee bigint := hashtextextended('redeem_referral_atomic:' || p_referee_id::text, 0);
BEGIN
  IF p_referrer_id IS NULL OR p_referee_id IS NULL THEN
    RAISE EXCEPTION 'redeem_referral_atomic: referrer and referee are required' USING ERRCODE = '23502';
  END IF;

  -- Serialise per REFEREE: a second redemption for the same referee, and the job crediting that user as a referrer, queue here.
  PERFORM pg_advisory_xact_lock(v_key_referee);

  IF EXISTS (
    SELECT 1 FROM subscriptions
     WHERE user_id = p_referee_id
       AND plan IN ('monthly', 'yearly')
       AND razorpay_payment_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'referee_has_paid_plan' USING ERRCODE = 'P0001';
  END IF;

  -- Audit row (UNIQUE constraint on referee_id catches duplicates). The referrer is rewarded later, by the job.
  INSERT INTO referral_redemptions (
    code, referrer_id, referee_id, days_granted_each, referrer_rewarded, referee_rewarded
  ) VALUES (
    p_code, p_referrer_id, p_referee_id, p_days, false, true
  );

  PERFORM private.grant_referral_days(p_referee_id, p_days);
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- private.process_referral_conversions: the only writer of the referrer reward. Hourly, one transaction.
-- Returns {reconciled, voided, credited, failed, skipped_locked} (pg_cron does not keep the value; the alerts are the
-- observable), or {"skipped":"locked"} when an earlier run still holds the job lock.
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.process_referral_conversions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c_window             CONSTANT interval := interval '90 days';  -- a payment counts if it is made within this long after the code was applied
  c_vest               CONSTANT interval := interval '7 days';   -- the reward is credited once the payment has stood this long
  c_scan               CONSTANT interval := interval '97 days';  -- window plus a 7-day outage grace: older, never-converted rows are not looked at
  c_batch              CONSTANT integer  := 50;                  -- rewards credited per run at most
  c_stall              CONSTANT interval := interval '10 days';  -- a reward still pending this long after its payment (vest 7 days + 3) is stalled
  c_volume_credits     CONSTANT integer  := 10;                  -- Phase-1 placeholders (alerts/_thresholds.yaml)
  c_volume_redemptions CONSTANT integer  := 20;
  r             record;
  v_reconciled  integer := 0;
  v_voided      integer := 0;
  v_credited    integer := 0;
  v_failed      integer := 0;
  v_skipped     integer := 0;
  v_n           integer;
  v_stalled     integer;
  v_failed_ids  text[]  := ARRAY[]::text[];
BEGIN
  -- 0. STALL WATCH (see the header): before the job lock, so it still fires while another run holds that lock.
  BEGIN
    SELECT count(*) INTO v_stalled
      FROM referral_redemptions rr
     WHERE rr.converted_at IS NOT NULL
       AND rr.converted_at <= now() - c_stall
       AND rr.referrer_id IS NOT NULL
       AND rr.referrer_rewarded IS NOT TRUE;
    IF v_stalled > 0 THEN
      INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
      SELECT 'referral_conversions_stalled', 'warn',
             format('%s referral reward(s) have been pending more than 3 days past their vest: the hourly job is not crediting them', v_stalled),
             jsonb_build_object('stalled', v_stalled),
             'Check that cron.job referral_conversions_hourly is active, look for a long-open session holding the job''s advisory lock or a referrer''s, and read the failed and skipped_locked counts of the runs.'
       WHERE NOT EXISTS (
         SELECT 1 FROM public.alerts x
          WHERE x.source = 'referral_conversions_stalled'
            AND x.acknowledged = false
            AND x.severity = 'warn'
            AND x.detected_at > now() - interval '23 hours'
       );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- An overlapping run (a slow earlier one) must not double up: return at once.
  IF NOT pg_try_advisory_xact_lock(hashtextextended('process_referral_conversions', 0)) THEN
    RETURN jsonb_build_object('skipped', 'locked');
  END IF;

  -- 1. RECONCILE. Candidates are locked in their own MATERIALIZED CTE (SKIP LOCKED: a row held by a deletion cascade is
  --    left for the next run, never waited for); the earliest qualifying payment is read in a second CTE (payment rows are
  --    read, not locked); ONE UPDATE writes only what differs, so a steady state changes no column.
  WITH cand AS MATERIALIZED (
    SELECT rr.id, rr.referee_id, rr.created_at
      FROM referral_redemptions rr
     WHERE rr.referrer_id IS NOT NULL
       AND rr.referrer_rewarded IS NOT TRUE
       AND (rr.created_at > now() - c_scan OR rr.converted_at IS NOT NULL)
     FOR UPDATE OF rr SKIP LOCKED
  ), calc AS (
    SELECT c.id, q.start_date, q.plan
      FROM cand c
      LEFT JOIN LATERAL (
        SELECT s.start_date, s.plan
          FROM subscriptions s
         WHERE s.user_id = c.referee_id
           AND s.plan IN ('monthly', 'yearly')
           AND s.razorpay_payment_id IS NOT NULL
           AND s.status = 'active'
           AND s.cancelled_at IS NULL
           AND s.start_date >= c.created_at
           AND s.start_date <= c.created_at + c_window
         ORDER BY s.start_date, s.id
         LIMIT 1
      ) q ON true
  ), upd AS (
    UPDATE referral_redemptions rr
       SET converted_at         = calc.start_date,
           referrer_reward_days = CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END
      FROM calc
     WHERE rr.id = calc.id
       AND (rr.converted_at IS DISTINCT FROM calc.start_date
            OR rr.referrer_reward_days IS DISTINCT FROM (CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END))
    RETURNING rr.converted_at
  )
  SELECT count(*) FILTER (WHERE converted_at IS NOT NULL),
         count(*) FILTER (WHERE converted_at IS NULL)
    INTO v_reconciled, v_voided
    FROM upd;

  -- 2. CREDIT. Each row in its own sub-block: a failure rolls back that row's grant and flag together and the row stays
  --    pending for the next run. Order inside the block: the referrer's advisory lock (try), the users-row key share
  --    (NOWAIT: the foreign key of a later INSERT would otherwise queue behind an account deletion), the grant, the flag.
  FOR r IN
    SELECT rr.id, rr.referrer_id, rr.referrer_reward_days AS reward_days
      FROM referral_redemptions rr
     WHERE rr.converted_at IS NOT NULL
       AND rr.converted_at <= now() - c_vest
       AND rr.referrer_id IS NOT NULL
       AND rr.referrer_rewarded IS NOT TRUE
     ORDER BY rr.converted_at, rr.id
     LIMIT c_batch
     FOR UPDATE OF rr SKIP LOCKED
  LOOP
    BEGIN
      IF NOT pg_try_advisory_xact_lock(hashtextextended('redeem_referral_atomic:' || r.referrer_id::text, 0)) THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;

      PERFORM 1 FROM public.users u WHERE u.id = r.referrer_id FOR KEY SHARE NOWAIT;
      IF NOT FOUND THEN
        CONTINUE;  -- the referrer's account is gone; the row loses its referrer_id by the foreign key and drops out
      END IF;

      PERFORM private.grant_referral_days(r.referrer_id, r.reward_days);

      UPDATE referral_redemptions
         SET referrer_rewarded = true, referrer_credited_at = now()
       WHERE id = r.id AND referrer_rewarded IS NOT TRUE;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n <> 1 THEN
        RAISE EXCEPTION 'referral reward flag matched % rows for redemption %', v_n, r.id;
      END IF;

      v_credited := v_credited + 1;
    EXCEPTION
      WHEN lock_not_available THEN
        v_skipped := v_skipped + 1;
      WHEN OTHERS THEN
        v_failed := v_failed + 1;
        v_failed_ids := v_failed_ids || r.id::text;
    END;
  END LOOP;

  -- 3. ALERTS (warn: the founder digest reads every severity, the Telegram trigger fires on critical only). Each INSERT is
  --    its own sub-block (an alert that cannot be written must never roll back the credits above), has its own source, and
  --    is deduplicated the way migration 145 does: an open alert of the same source from the last 23 hours suppresses it.
  IF v_failed > 0 THEN
    BEGIN
      INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
      SELECT 'referral_conversions_failed', 'warn',
             format('%s referral reward credit(s) failed in the last run; the referrer(s) were not rewarded yet', v_failed),
             jsonb_build_object('failed', v_failed, 'redemption_ids', to_jsonb(v_failed_ids)),
             'Read cron.job_run_details for referral_conversions_hourly and the named referral_redemptions rows; the rewards stay pending and are retried every hour.'
       WHERE NOT EXISTS (
         SELECT 1 FROM public.alerts x
          WHERE x.source = 'referral_conversions_failed'
            AND x.acknowledged = false
            AND x.severity = 'warn'
            AND x.detected_at > now() - interval '23 hours'
       );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  BEGIN
    IF v_credited > c_volume_credits
       OR (SELECT count(*) FROM referral_redemptions WHERE created_at > now() - interval '24 hours') > c_volume_redemptions THEN
      INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
      SELECT 'referral_conversions_volume', 'warn',
             'Unusual referral volume: many rewards credited in one run or many redemptions in 24 hours',
             jsonb_build_object(
               'credited_this_run', v_credited,
               'redemptions_24h', (SELECT count(*) FROM referral_redemptions WHERE created_at > now() - interval '24 hours'),
               'max_redemptions_24h_one_referrer', (SELECT coalesce(max(c), 0) FROM (SELECT count(*) AS c FROM referral_redemptions WHERE created_at > now() - interval '24 hours' AND referrer_id IS NOT NULL GROUP BY referrer_id) t)),
             'Look for one referrer with many redemptions and look at the friends'' payments before more rewards vest.'
       WHERE NOT EXISTS (
         SELECT 1 FROM public.alerts x
          WHERE x.source = 'referral_conversions_volume'
            AND x.acknowledged = false
            AND x.severity = 'warn'
            AND x.detected_at > now() - interval '23 hours'
       );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'reconciled', v_reconciled,
    'voided', v_voided,
    'credited', v_credited,
    'failed', v_failed,
    'skipped_locked', v_skipped
  );
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- ACL. The two private functions are for the cron job (which runs as the owner) and for redeem_referral_atomic (security
-- definer): nobody else. The redeem RPC keeps 158's ACL: service_role only (CREATE OR REPLACE preserves it; restated).
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION private.grant_referral_days(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.grant_referral_days(uuid, integer) FROM anon, authenticated;
REVOKE ALL ON FUNCTION private.process_referral_conversions() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.process_referral_conversions() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- The hourly job, minute 41 (0, 7, 17, 23, 33 are taken). Unscheduled BY JOBID, not by quoted name: Gate 31 reads raw text
-- and treats a quoted-name unschedule call as "this job is gone" (OI-193; migration 145 does the same).
-- ---------------------------------------------------------------------------------------------------------------------
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'referral_conversions_hourly';
SELECT cron.schedule('referral_conversions_hourly', '41 * * * *', $$SELECT private.process_referral_conversions()$$);

-- Post-apply verification (read-only):
--   SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname = 'referral_conversions_hourly';   -- expect '41 * * * *', active
--   SELECT p.proname, n.nspname, p.prosecdef, p.proconfig, p.proacl::text
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE p.proname IN ('grant_referral_days', 'process_referral_conversions', 'redeem_referral_atomic');
--   -- anon / authenticated must NOT execute any of the three; service_role must execute redeem_referral_atomic:
--   SELECT has_function_privilege('anon', 'public.redeem_referral_atomic(text,uuid,uuid,integer)', 'execute');   -- expect false
--   SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'referral_redemptions'
--      AND column_name IN ('converted_at', 'referrer_reward_days', 'referrer_credited_at');                      -- expect 3 rows
--   -- after the next :41 a run row reads 'succeeded' (compare migration 145):
--   SELECT status, start_time, return_message FROM cron.job_run_details
--    WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'referral_conversions_hourly')
--    ORDER BY start_time DESC LIMIT 3;
-- The live verify is test/sql/referral_pay_on_conversion_live_verify.sql (ONE DO block that always aborts with a
-- VERIFY_RESULTS error, so nothing it writes survives); run it inside the hour of the apply.

-- Rollback (inline; commented; the order matters: the redeem body must be restored BEFORE the helper it calls is dropped):
--   SELECT cron.unschedule(<the referral_conversions_hourly job>);        -- unquoted on purpose (Gate 31 scans raw text)
--   DROP FUNCTION IF EXISTS private.process_referral_conversions();
--   -- 1. restore the migration 158 body of public.redeem_referral_atomic VERBATIM:
--   CREATE OR REPLACE FUNCTION public.redeem_referral_atomic(
--     p_code text,
--     p_referrer_id uuid,
--     p_referee_id uuid,
--     p_days integer
--   )
--    RETURNS void
--    LANGUAGE plpgsql
--    SECURITY DEFINER
--    SET search_path TO 'public'
--   AS $function$
--   DECLARE
--     -- OI-320: at most this many CREDITED referrals per referrer in any rolling window.
--     c_referrer_cap CONSTANT integer  := 7;
--     c_cap_window   CONSTANT interval := interval '90 days';
--     v_key_referrer bigint := hashtextextended('redeem_referral_atomic:' || p_referrer_id::text, 0);
--     v_key_referee  bigint := hashtextextended('redeem_referral_atomic:' || p_referee_id::text, 0);
--     v_referrer_expires TIMESTAMPTZ;
--     v_referee_expires TIMESTAMPTZ;
--     v_credited_in_window integer;
--     v_credit_referrer boolean;
--   BEGIN
--     IF p_referrer_id IS NULL OR p_referee_id IS NULL THEN
--       RAISE EXCEPTION 'redeem_referral_atomic: referrer and referee are required' USING ERRCODE = '23502';
--     END IF;
--
--     -- 0. Serialise per USER, lowest key first, so same-referrer redemptions queue, two single-redemption transactions
--     --    cannot wait on each other's advisory locks, and the count below cannot interleave with another insert.
--     PERFORM pg_advisory_xact_lock(least(v_key_referrer, v_key_referee));
--     PERFORM pg_advisory_xact_lock(greatest(v_key_referrer, v_key_referee));
--
--     -- 1. The cap decision: credited redemptions of this referrer inside the rolling window.
--     SELECT count(*) INTO v_credited_in_window
--     FROM referral_redemptions
--     WHERE referrer_id = p_referrer_id
--       AND referrer_rewarded
--       AND created_at > now() - c_cap_window;
--     v_credit_referrer := v_credited_in_window < c_referrer_cap;
--
--     -- 2. Audit row (UNIQUE constraint on referee_id catches duplicates). The referee is always credited;
--     --    the referrer only when under the cap.
--     INSERT INTO referral_redemptions (
--       code, referrer_id, referee_id, days_granted_each, referrer_rewarded, referee_rewarded
--     ) VALUES (
--       p_code, p_referrer_id, p_referee_id, p_days, v_credit_referrer, true
--     );
--
--     -- 3. Extend the referrer's subscription (skipped at the cap).
--     IF v_credit_referrer THEN
--       SELECT MAX(end_date) INTO v_referrer_expires
--       FROM subscriptions
--       WHERE user_id = p_referrer_id AND status = 'active';
--
--       IF v_referrer_expires IS NULL OR v_referrer_expires < now() THEN
--         INSERT INTO subscriptions (
--           user_id, plan, status, start_date, end_date
--         ) VALUES (
--           p_referrer_id,
--           'referral_trial',
--           'active',
--           now(),
--           now() + (p_days || ' days')::interval
--         );
--       ELSE
--         UPDATE subscriptions
--         SET end_date = end_date + (p_days || ' days')::interval
--         WHERE user_id = p_referrer_id AND status = 'active'
--           AND end_date = v_referrer_expires;
--       END IF;
--     END IF;
--
--     -- 4. Same for referee (unchanged, never capped)
--     SELECT MAX(end_date) INTO v_referee_expires
--     FROM subscriptions
--     WHERE user_id = p_referee_id AND status = 'active';
--
--     IF v_referee_expires IS NULL OR v_referee_expires < now() THEN
--       INSERT INTO subscriptions (
--         user_id, plan, status, start_date, end_date
--       ) VALUES (
--         p_referee_id,
--         'referral_trial',
--         'active',
--         now(),
--         now() + (p_days || ' days')::interval
--       );
--     ELSE
--       UPDATE subscriptions
--       SET end_date = end_date + (p_days || ' days')::interval
--       WHERE user_id = p_referee_id AND status = 'active'
--         AND end_date = v_referee_expires;
--     END IF;
--   END;
--   $function$;

--   DROP FUNCTION IF EXISTS private.grant_referral_days(uuid, integer);
--   SET lock_timeout = '3s';   -- bound the ACCESS EXCLUSIVE lock of the ALTER below, as the apply does
--   ALTER TABLE public.referral_redemptions
--     DROP CONSTRAINT IF EXISTS referral_redemptions_reward_days_check,
--     DROP CONSTRAINT IF EXISTS referral_redemptions_converted_coherent_check,
--     DROP COLUMN IF EXISTS converted_at,
--     DROP COLUMN IF EXISTS referrer_reward_days,
--     DROP COLUMN IF EXISTS referrer_credited_at;
--   -- Rows credited by the job keep referrer_rewarded = true and their PRO days; the 158 cap would count them again from
--   -- their created_at. Nothing here re-credits or un-credits anything.
--   -- REWARDS STILL PENDING are LOST by dropping converted_at / referrer_reward_days: the referrer was owed days for a payment
--   -- the friend already made. BEFORE running this block list them, and credit them by hand or let the job run once more:
--   --   SELECT id, referrer_id, referrer_reward_days, converted_at FROM public.referral_redemptions
--   --    WHERE converted_at IS NOT NULL AND referrer_rewarded IS NOT TRUE;
