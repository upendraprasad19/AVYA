-- Intent: Close the stale-credit window of the referral reward job, bound the redeem retry on a held subscription row, hide payment-status columns of referral_redemptions from every client, add the referrer_summary() aggregate the app reads, and cap percent-off promo codes at 90 percent
-- Destructive?: no   -- REVOKEs table privileges nothing uses (the only app readers name granted columns), replaces two function bodies (same signature, return type, security mode and ACL), creates one function, replaces a CHECK with a tighter one that the three live rows satisfy; no row rewritten, no column dropped
-- Rollback strategy: inline   -- a commented block at the end of the file: drop the new function, restore the 159 bodies verbatim, restore the table grants and the 1..100 promo CHECK
-- Linked diagnose-doc: c5e9a3 (stale credit), f2d6b8 (redeem lock wait)

-- 160_referral_hardening.sql
--
-- WHY. Migration 159 shipped the pay-on-conversion reward. Three review rounds and a hermes pass left a hardening list
-- (OI-344, ledger rows N1 N3 N4 N5 of docs/audit/referral-pay-on-conversion.closure.yaml); the founder then decided what the app may
-- show a referrer (aggregates only: friends joined, subscribed, PRO days earned, a pending count) and capped percent-off promo
-- codes at 90 percent (2026-10-16). Plan (v4 after two plan-review rounds), the B-pass, the hermes pass and the measured lock behaviour: docs/plans/referral-hardening-migration-160.md.
--
-- 1. THE JOB (N1, diagnose c5e9a3). The credit select of private.process_referral_conversions did not re-check referee_id. A friend's
--    account deleted BETWEEN the reconcile and the credit select of one run leaves referee_id NULL on a row whose converted_at is
--    stale (the payment was deleted with the user); the run credited the referrer for a payment that no longer exists. The select now
--    carries `AND rr.referee_id IS NOT NULL`; the next run's reconcile voids the row. This is the ONLY change to the job body.
-- 2. THE REDEEM (N3, diagnose f2d6b8). 159 made private.grant_referral_days read the subscription row FOR UPDATE NOWAIT, where 158 used
--    a plain UPDATE that waited. A redeem that meets a row held for a moment (the webhook inserting the friend's payment) therefore
--    raised 55P03 and the friend saw a generic 500. The call is now a BOUNDED retry: 3 attempts, 0.25 s apart, ONLY lock_not_available.
--    Worst case adds 0.5 s; after the third failure the caller still gets 55P03 (a bounded retry, not an elimination).
-- 3. THE GRANTS (N4). anon and authenticated hold INSERT, UPDATE, DELETE, TRUNCATE (and more) on referral_redemptions; row security with no
--    write policy blocks them today, but the table now decides PRO days. All client privileges are revoked and SELECT is re-granted on
--    SIX columns (id, code, referrer_id, referee_id, days_granted_each, created_at): the five payment-status columns (converted_at,
--    referrer_reward_days, referrer_credited_at, referrer_rewarded, referee_rewarded) become unreadable to every client, so a referrer
--    cannot read which named friend paid, when, or on which plan. service_role, postgres and the SECURITY DEFINER functions are unaffected;
--    the foreign keys' ON DELETE SET NULL actions run as the table owner. The two app readers (referral_repository.hasRedeemed and
--    sync_restore_completeness) name only granted columns.
--    RESIDUAL, stated plainly: a referrer's client can still read, per friend row, an opaque referee_id UUID and created_at (the join time),
--    and aggregates read twice step by +7/+30 on each credit, so for ONE friend the aggregate is the individual. A friend who pays and then
--    deletes their account before the vest makes `subscribed` and `pending` drop while `joined` stays (the reconcile voids the row; the
--    granted referee_id column already turns NULL on exactly that row). That is inherent to the founder-approved fields.
-- 4. THE AGGREGATE (U2 server half). public.referrer_summary() returns jsonb {joined, subscribed, pending, credited, days_earned} for
--    auth.uid() as referrer, SECURITY DEFINER, EXECUTE to authenticated (service_role keeps the platform default grant; none to anon or PUBLIC), 28000 when unauthenticated. No timestamps, no ids.
-- 5. THE PROMO CEILING (N5, founder decision 2026-10-16). promo_codes_discount_pct_check already exists as 1..100; it is REPLACED (one ALTER)
--    by 1..90. The three live codes are 30, 20 and 15 percent. Free-access codes (PRO with no payment) are a different feature (OI-347).
-- 6. SELF-CHECK. A REVOKE removes only privileges granted by the revoking role. The final DO block verifies the resulting privilege
--    state with has_table_privilege / has_column_privilege / has_function_privilege and RAISES if any client privilege survived. Under a
--    transaction-wrapped apply (psql --single-transaction, as the replica proof runs it) that aborts and rolls back the WHOLE migration; a runner
--    that executes statement by statement would leave the earlier statements applied (every one of them only NARROWS access, the promo CHECK is
--    last and would be skipped, and the file is idempotent: fix the cause and re-run). MAINTAIN is a PostgreSQL 17 privilege (live is 17.6): on an
--    older server the check fails CLOSED with "unrecognized privilege type". Read live 2026-10-16: owner postgres, every grantor postgres, so
--    one REVOKE removes everything.
--
-- NOT CHANGED: the credit ORDER of the job (OI-344 item 2 / N2: the founder accepted the residual 2026-10-16), the helper
-- private.grant_referral_days, the cron job, the alerts, every other line of the 159 bodies.
--
-- IDEMPOTENT: CREATE OR REPLACE, REVOKE/GRANT converge, the CHECK is dropped if present and added in ONE ALTER TABLE. The DDL is bounded by a
-- 3-second lock_timeout.

SET lock_timeout = '3s';

-- 3. grants
REVOKE ALL ON public.referral_redemptions FROM PUBLIC;
REVOKE ALL ON public.referral_redemptions FROM anon, authenticated;
GRANT SELECT (id, code, referrer_id, referee_id, days_granted_each, created_at)
  ON public.referral_redemptions TO authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. public.redeem_referral_atomic: the 159 body with the grant call wrapped in a bounded retry (see the header).
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

  -- 160: the helper reads the subscription row FOR UPDATE NOWAIT (a held row raises 55P03 at once). Where 158 waited, a redeem that
  -- meets a momentarily held row (a webhook inserting the friend's payment) now retries, up to 3 attempts 0.25 s apart; ONLY
  -- lock_not_available is retried, any other error propagates at once; the third failure re-raises and aborts the whole call
  -- (the audit row above is rolled back with it), so the caller sees the same 55P03 as before.
  FOR v_attempt IN 1..3 LOOP
    BEGIN
      PERFORM private.grant_referral_days(p_referee_id, p_days);
      EXIT;
    EXCEPTION WHEN lock_not_available THEN
      IF v_attempt = 3 THEN
        RAISE;
      END IF;
      PERFORM pg_sleep(0.25);
      -- the wait is long enough for a payment to land: re-validate the precondition checked above (a referee who has paid must not
      -- receive the trial days) before the next attempt; the raise rolls the whole call back, the audit row included.
      IF EXISTS (
        SELECT 1 FROM subscriptions
         WHERE user_id = p_referee_id
           AND plan IN ('monthly', 'yearly')
           AND razorpay_payment_id IS NOT NULL
      ) THEN
        RAISE EXCEPTION 'referee_has_paid_plan' USING ERRCODE = 'P0001';
      END IF;
    END;
  END LOOP;
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. private.process_referral_conversions: the 159 body with ONE added predicate in the credit select (see the header).
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
       AND rr.referee_id IS NOT NULL   -- 160: a deleted friend's stale converted_at is never credited (the reconcile voids the row next run)
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
-- 4. public.referrer_summary: the only door to the referrer's aggregates. SECURITY DEFINER because the client can no longer read the
-- payment-status columns; it filters by auth.uid() itself, so a caller sees only rows where they are the REFERRER.
--   joined      = all rows (a row whose friend later deleted their account still counts)
--   subscribed  = rows with converted_at
--   credited    = rows with referrer_rewarded (a row credited under 158, converted_at NULL, is credited and not subscribed)
--   pending     = converted and not yet credited (the 7-day vest)
--   days_earned = days actually credited (0, never NULL, for a referrer with no rows)
-- ---------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.referrer_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_joined     integer;
  v_subscribed integer;
  v_credited   integer;
  v_pending    integer;
  v_days       integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'referrer_summary: not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT count(*),
         count(*) FILTER (WHERE rr.converted_at IS NOT NULL),
         count(*) FILTER (WHERE rr.referrer_rewarded IS TRUE),
         count(*) FILTER (WHERE rr.converted_at IS NOT NULL AND rr.referrer_rewarded IS NOT TRUE),
         coalesce(sum(CASE WHEN rr.referrer_rewarded IS TRUE THEN coalesce(rr.referrer_reward_days, rr.days_granted_each) END), 0)
    INTO v_joined, v_subscribed, v_credited, v_pending, v_days
    FROM public.referral_redemptions rr
   WHERE rr.referrer_id = v_uid;

  RETURN jsonb_build_object(
    'joined', v_joined,
    'subscribed', v_subscribed,
    'pending', v_pending,
    'credited', v_credited,
    'days_earned', v_days
  );
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- ACL. referrer_summary: authenticated only (Supabase's default privileges grant EXECUTE on every new public function directly to
-- anon and authenticated, so REVOKE FROM PUBLIC alone is not enough, CLAUDE.md migrations pitfall). The two replaced functions
-- keep their 159 ACL (CREATE OR REPLACE preserves it; restated).
-- ---------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.referrer_summary() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.referrer_summary() FROM anon;
GRANT  EXECUTE ON FUNCTION public.referrer_summary() TO authenticated;
REVOKE ALL ON FUNCTION private.process_referral_conversions() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.process_referral_conversions() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. SELF-CHECK (see the header). Nothing here touches service_role or postgres, so a legitimate ACL cannot trip it.
-- ---------------------------------------------------------------------------------------------------------------------
DO $selfcheck$
DECLARE
  v_role text;
  v_priv text;
  v_col  text;
  v_fn   text;
  v_bad  text := '';
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    FOREACH v_priv IN ARRAY ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'] LOOP
      IF has_table_privilege(v_role, 'public.referral_redemptions', v_priv) THEN
        v_bad := v_bad || format(' %s holds table-level %s;', v_role, v_priv);
      END IF;
    END LOOP;
  END LOOP;
  IF has_any_column_privilege('anon', 'public.referral_redemptions', 'SELECT,INSERT,UPDATE,REFERENCES') THEN
    v_bad := v_bad || ' anon holds a column privilege;';
  END IF;
  IF has_any_column_privilege('authenticated', 'public.referral_redemptions', 'INSERT,UPDATE,REFERENCES') THEN
    v_bad := v_bad || ' authenticated holds a column write privilege;';
  END IF;
  FOREACH v_col IN ARRAY ARRAY['converted_at', 'referrer_reward_days', 'referrer_credited_at', 'referrer_rewarded', 'referee_rewarded'] LOOP
    IF has_column_privilege('authenticated', 'public.referral_redemptions', v_col, 'SELECT') THEN
      v_bad := v_bad || format(' authenticated can still read %s;', v_col);
    END IF;
  END LOOP;
  FOREACH v_col IN ARRAY ARRAY['id', 'code', 'referrer_id', 'referee_id', 'days_granted_each', 'created_at'] LOOP
    IF NOT has_column_privilege('authenticated', 'public.referral_redemptions', v_col, 'SELECT') THEN
      v_bad := v_bad || format(' authenticated cannot read %s;', v_col);
    END IF;
  END LOOP;
  IF has_function_privilege('anon', 'public.referrer_summary()', 'EXECUTE') THEN
    v_bad := v_bad || ' anon can execute referrer_summary;';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.referrer_summary()', 'EXECUTE') THEN
    v_bad := v_bad || ' authenticated cannot execute referrer_summary;';
  END IF;
  -- the two replaced functions keep their 159 ACL (restated above): nobody but service_role / the owner may execute them
  FOREACH v_fn IN ARRAY ARRAY['private.process_referral_conversions()', 'public.redeem_referral_atomic(text, uuid, uuid, integer)'] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      IF has_function_privilege(v_role, v_fn::regprocedure, 'EXECUTE') THEN
        v_bad := v_bad || format(' %s can execute %s;', v_role, v_fn);
      END IF;
    END LOOP;
  END LOOP;
  -- referrer_summary is SECURITY DEFINER with a pinned search_path and is STABLE (a CREATE OR REPLACE by another path could change any of the three)
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
     WHERE p.oid = 'public.referrer_summary()'::regprocedure
       AND p.prosecdef AND p.provolatile = 's'
       AND p.proconfig = ARRAY['search_path=public, pg_temp']
  ) THEN
    v_bad := v_bad || ' referrer_summary is not SECURITY DEFINER STABLE with search_path public, pg_temp;';
  END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'migration 160 self-check failed:%', v_bad;
  END IF;
END
$selfcheck$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. PROMO CEILING. Placed LAST on purpose: ADD CONSTRAINT takes ACCESS EXCLUSIVE on promo_codes (read by create-razorpay-order,
-- validate-promo, verify-payment and razorpay-webhook) and holds it to commit, so it runs after everything that can abort the apply.
-- ---------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.promo_codes
  DROP CONSTRAINT IF EXISTS promo_codes_discount_pct_check,
  ADD  CONSTRAINT promo_codes_discount_pct_check
       CHECK (discount_pct BETWEEN 1 AND 90);

RESET lock_timeout;

-- Post-apply verification (read-only):
--   SELECT relacl::text FROM pg_class WHERE oid = 'public.referral_redemptions'::regclass;     -- postgres + service_role only (plus column grants)
--   SELECT column_name FROM information_schema.column_privileges
--    WHERE table_schema = 'public' AND table_name = 'referral_redemptions' AND grantee = 'authenticated';     -- the six granted columns
--   SELECT has_function_privilege('anon', 'public.referrer_summary()', 'execute');                       -- expect false
--   SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'promo_codes_discount_pct_check';   -- 1..90
-- The live verify is test/sql/referral_pay_on_conversion_live_verify.sql (ONE DO block that always aborts with VERIFY_RESULTS; group Q is this migration).

-- Rollback (inline; commented). Order: the 160 function first, then the two 159 bodies VERBATIM, then the grants, then the CHECK.
-- COORDINATION: once the Unit C client (which calls referrer_summary()) is released, dropping the function makes its counts line fail: roll the client
-- back first or accept an error on that line until it is. The current client (before Unit C) never calls it and reads only the six granted columns.
--   DROP FUNCTION IF EXISTS public.referrer_summary();
--   -- 159 body of public.redeem_referral_atomic:
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
--     v_key_referee bigint := hashtextextended('redeem_referral_atomic:' || p_referee_id::text, 0);
--   BEGIN
--     IF p_referrer_id IS NULL OR p_referee_id IS NULL THEN
--       RAISE EXCEPTION 'redeem_referral_atomic: referrer and referee are required' USING ERRCODE = '23502';
--     END IF;
--
--     -- Serialise per REFEREE: a second redemption for the same referee, and the job crediting that user as a referrer, queue here.
--     PERFORM pg_advisory_xact_lock(v_key_referee);
--
--     IF EXISTS (
--       SELECT 1 FROM subscriptions
--        WHERE user_id = p_referee_id
--          AND plan IN ('monthly', 'yearly')
--          AND razorpay_payment_id IS NOT NULL
--     ) THEN
--       RAISE EXCEPTION 'referee_has_paid_plan' USING ERRCODE = 'P0001';
--     END IF;
--
--     -- Audit row (UNIQUE constraint on referee_id catches duplicates). The referrer is rewarded later, by the job.
--     INSERT INTO referral_redemptions (
--       code, referrer_id, referee_id, days_granted_each, referrer_rewarded, referee_rewarded
--     ) VALUES (
--       p_code, p_referrer_id, p_referee_id, p_days, false, true
--     );
--
--     PERFORM private.grant_referral_days(p_referee_id, p_days);
--   END;
--   $function$;
--   -- 159 body of private.process_referral_conversions:
--   CREATE OR REPLACE FUNCTION private.process_referral_conversions()
--    RETURNS jsonb
--    LANGUAGE plpgsql
--    SECURITY DEFINER
--    SET search_path TO 'public'
--   AS $function$
--   DECLARE
--     c_window             CONSTANT interval := interval '90 days';  -- a payment counts if it is made within this long after the code was applied
--     c_vest               CONSTANT interval := interval '7 days';   -- the reward is credited once the payment has stood this long
--     c_scan               CONSTANT interval := interval '97 days';  -- window plus a 7-day outage grace: older, never-converted rows are not looked at
--     c_batch              CONSTANT integer  := 50;                  -- rewards credited per run at most
--     c_stall              CONSTANT interval := interval '10 days';  -- a reward still pending this long after its payment (vest 7 days + 3) is stalled
--     c_volume_credits     CONSTANT integer  := 10;                  -- Phase-1 placeholders (alerts/_thresholds.yaml)
--     c_volume_redemptions CONSTANT integer  := 20;
--     r             record;
--     v_reconciled  integer := 0;
--     v_voided      integer := 0;
--     v_credited    integer := 0;
--     v_failed      integer := 0;
--     v_skipped     integer := 0;
--     v_n           integer;
--     v_stalled     integer;
--     v_failed_ids  text[]  := ARRAY[]::text[];
--   BEGIN
--     -- 0. STALL WATCH (see the header): before the job lock, so it still fires while another run holds that lock.
--     BEGIN
--       SELECT count(*) INTO v_stalled
--         FROM referral_redemptions rr
--        WHERE rr.converted_at IS NOT NULL
--          AND rr.converted_at <= now() - c_stall
--          AND rr.referrer_id IS NOT NULL
--          AND rr.referrer_rewarded IS NOT TRUE;
--       IF v_stalled > 0 THEN
--         INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--         SELECT 'referral_conversions_stalled', 'warn',
--                format('%s referral reward(s) have been pending more than 3 days past their vest: the hourly job is not crediting them', v_stalled),
--                jsonb_build_object('stalled', v_stalled),
--                'Check that cron.job referral_conversions_hourly is active, look for a long-open session holding the job''s advisory lock or a referrer''s, and read the failed and skipped_locked counts of the runs.'
--          WHERE NOT EXISTS (
--            SELECT 1 FROM public.alerts x
--             WHERE x.source = 'referral_conversions_stalled'
--               AND x.acknowledged = false
--               AND x.severity = 'warn'
--               AND x.detected_at > now() - interval '23 hours'
--          );
--       END IF;
--     EXCEPTION WHEN OTHERS THEN
--       NULL;
--     END;
--
--     -- An overlapping run (a slow earlier one) must not double up: return at once.
--     IF NOT pg_try_advisory_xact_lock(hashtextextended('process_referral_conversions', 0)) THEN
--       RETURN jsonb_build_object('skipped', 'locked');
--     END IF;
--
--     -- 1. RECONCILE. Candidates are locked in their own MATERIALIZED CTE (SKIP LOCKED: a row held by a deletion cascade is
--     --    left for the next run, never waited for); the earliest qualifying payment is read in a second CTE (payment rows are
--     --    read, not locked); ONE UPDATE writes only what differs, so a steady state changes no column.
--     WITH cand AS MATERIALIZED (
--       SELECT rr.id, rr.referee_id, rr.created_at
--         FROM referral_redemptions rr
--        WHERE rr.referrer_id IS NOT NULL
--          AND rr.referrer_rewarded IS NOT TRUE
--          AND (rr.created_at > now() - c_scan OR rr.converted_at IS NOT NULL)
--        FOR UPDATE OF rr SKIP LOCKED
--     ), calc AS (
--       SELECT c.id, q.start_date, q.plan
--         FROM cand c
--         LEFT JOIN LATERAL (
--           SELECT s.start_date, s.plan
--             FROM subscriptions s
--            WHERE s.user_id = c.referee_id
--              AND s.plan IN ('monthly', 'yearly')
--              AND s.razorpay_payment_id IS NOT NULL
--              AND s.status = 'active'
--              AND s.cancelled_at IS NULL
--              AND s.start_date >= c.created_at
--              AND s.start_date <= c.created_at + c_window
--            ORDER BY s.start_date, s.id
--            LIMIT 1
--         ) q ON true
--     ), upd AS (
--       UPDATE referral_redemptions rr
--          SET converted_at         = calc.start_date,
--              referrer_reward_days = CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END
--         FROM calc
--        WHERE rr.id = calc.id
--          AND (rr.converted_at IS DISTINCT FROM calc.start_date
--               OR rr.referrer_reward_days IS DISTINCT FROM (CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END))
--       RETURNING rr.converted_at
--     )
--     SELECT count(*) FILTER (WHERE converted_at IS NOT NULL),
--            count(*) FILTER (WHERE converted_at IS NULL)
--       INTO v_reconciled, v_voided
--       FROM upd;
--
--     -- 2. CREDIT. Each row in its own sub-block: a failure rolls back that row's grant and flag together and the row stays
--     --    pending for the next run. Order inside the block: the referrer's advisory lock (try), the users-row key share
--     --    (NOWAIT: the foreign key of a later INSERT would otherwise queue behind an account deletion), the grant, the flag.
--     FOR r IN
--       SELECT rr.id, rr.referrer_id, rr.referrer_reward_days AS reward_days
--         FROM referral_redemptions rr
--        WHERE rr.converted_at IS NOT NULL
--          AND rr.converted_at <= now() - c_vest
--          AND rr.referrer_id IS NOT NULL
--          AND rr.referrer_rewarded IS NOT TRUE
--        ORDER BY rr.converted_at, rr.id
--        LIMIT c_batch
--        FOR UPDATE OF rr SKIP LOCKED
--     LOOP
--       BEGIN
--         IF NOT pg_try_advisory_xact_lock(hashtextextended('redeem_referral_atomic:' || r.referrer_id::text, 0)) THEN
--           v_skipped := v_skipped + 1;
--           CONTINUE;
--         END IF;
--
--         PERFORM 1 FROM public.users u WHERE u.id = r.referrer_id FOR KEY SHARE NOWAIT;
--         IF NOT FOUND THEN
--           CONTINUE;  -- the referrer's account is gone; the row loses its referrer_id by the foreign key and drops out
--         END IF;
--
--         PERFORM private.grant_referral_days(r.referrer_id, r.reward_days);
--
--         UPDATE referral_redemptions
--            SET referrer_rewarded = true, referrer_credited_at = now()
--          WHERE id = r.id AND referrer_rewarded IS NOT TRUE;
--         GET DIAGNOSTICS v_n = ROW_COUNT;
--         IF v_n <> 1 THEN
--           RAISE EXCEPTION 'referral reward flag matched % rows for redemption %', v_n, r.id;
--         END IF;
--
--         v_credited := v_credited + 1;
--       EXCEPTION
--         WHEN lock_not_available THEN
--           v_skipped := v_skipped + 1;
--         WHEN OTHERS THEN
--           v_failed := v_failed + 1;
--           v_failed_ids := v_failed_ids || r.id::text;
--       END;
--     END LOOP;
--
--     -- 3. ALERTS (warn: the founder digest reads every severity, the Telegram trigger fires on critical only). Each INSERT is
--     --    its own sub-block (an alert that cannot be written must never roll back the credits above), has its own source, and
--     --    is deduplicated the way migration 145 does: an open alert of the same source from the last 23 hours suppresses it.
--     IF v_failed > 0 THEN
--       BEGIN
--         INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--         SELECT 'referral_conversions_failed', 'warn',
--                format('%s referral reward credit(s) failed in the last run; the referrer(s) were not rewarded yet', v_failed),
--                jsonb_build_object('failed', v_failed, 'redemption_ids', to_jsonb(v_failed_ids)),
--                'Read cron.job_run_details for referral_conversions_hourly and the named referral_redemptions rows; the rewards stay pending and are retried every hour.'
--          WHERE NOT EXISTS (
--            SELECT 1 FROM public.alerts x
--             WHERE x.source = 'referral_conversions_failed'
--               AND x.acknowledged = false
--               AND x.severity = 'warn'
--               AND x.detected_at > now() - interval '23 hours'
--          );
--       EXCEPTION WHEN OTHERS THEN
--         NULL;
--       END;
--     END IF;
--
--     BEGIN
--       IF v_credited > c_volume_credits
--          OR (SELECT count(*) FROM referral_redemptions WHERE created_at > now() - interval '24 hours') > c_volume_redemptions THEN
--         INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--         SELECT 'referral_conversions_volume', 'warn',
--                'Unusual referral volume: many rewards credited in one run or many redemptions in 24 hours',
--                jsonb_build_object(
--                  'credited_this_run', v_credited,
--                  'redemptions_24h', (SELECT count(*) FROM referral_redemptions WHERE created_at > now() - interval '24 hours'),
--                  'max_redemptions_24h_one_referrer', (SELECT coalesce(max(c), 0) FROM (SELECT count(*) AS c FROM referral_redemptions WHERE created_at > now() - interval '24 hours' AND referrer_id IS NOT NULL GROUP BY referrer_id) t)),
--                'Look for one referrer with many redemptions and look at the friends'' payments before more rewards vest.'
--          WHERE NOT EXISTS (
--            SELECT 1 FROM public.alerts x
--             WHERE x.source = 'referral_conversions_volume'
--               AND x.acknowledged = false
--               AND x.severity = 'warn'
--               AND x.detected_at > now() - interval '23 hours'
--          );
--       END IF;
--     EXCEPTION WHEN OTHERS THEN
--       NULL;
--     END;
--
--     RETURN jsonb_build_object(
--       'reconciled', v_reconciled,
--       'voided', v_voided,
--       'credited', v_credited,
--       'failed', v_failed,
--       'skipped_locked', v_skipped
--     );
--   END;
--   $function$;
--   -- the platform-default grants (read live 2026-10-16: relacl arwdDxtm for anon and authenticated, grantor postgres; m = MAINTAIN, PG17):
--   REVOKE ALL ON public.referral_redemptions FROM anon, authenticated;   -- also removes the six column-level SELECT entries 160 created (attacl)
--   GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.referral_redemptions TO anon, authenticated;
--   ALTER TABLE public.promo_codes
--     DROP CONSTRAINT IF EXISTS promo_codes_discount_pct_check,
--     ADD  CONSTRAINT promo_codes_discount_pct_check CHECK (discount_pct >= 1 AND discount_pct <= 100);
