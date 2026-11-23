-- Intent: OI-519 (+51) Android PRO through RevenueCat + Google Play: Play columns on subscriptions, the RevenueCat event ledger, the referral-reward defer queue, the service-role writers, and a PRODUCTION Play row counting as paid for referrals
-- Destructive?: no   -- additive columns (NULL on every existing row), two new tables, three new functions; three function bodies replaced with one added predicate or branch each; no row is rewritten
-- Rollback strategy: inline   -- a commented block at the end restores the three pre-182 bodies verbatim and drops the new functions; columns and tables stay (additive)
-- Linked diagnose-doc: n/a   -- a planned feature (OI-519, plan docs/plans/2026-11-23-revenuecat-play-billing-51.md, ADR-0022), not a bug fix

-- 182_play_subscriptions.sql
--
-- Plan sections 3 and 4. The pre-182 bodies are the repo bodies 159:89 (grant_referral_days), 160:61 (redeem_referral_atomic)
-- and 160:129 (process_referral_conversions); their md5(prosrc) equalled live on 2026-11-23 (457ffc0c, ee24b1f0, 7a166314).
-- They are reproduced VERBATIM in the ROLLBACK block at the end.
--
-- 1. subscriptions gets seven nullable store_* / auto_renew columns. NULL on every existing row, so no reader sees a change
--    until a Play row exists. One Play row per (user, Google subscription id): RevenueCat's REST keys subscriptions by the id
--    without the base-plan suffix (avya_pro) and keeps one entry per subscription (plan section 18).
--    subscriptions_play_product_uq is a PLAIN unique index: non-Play rows carry a NULL store_product_id and NULLs never
--    collide, and a plain index is a valid ON CONFLICT arbiter (the partial-index 42P10 trap, migrations CLAUDE.md).
-- 2. subscription_events: the webhook's idempotency ledger. No payload and no raw app_user_id column; user_id only for a known
--    user, SET NULL on account deletion. RLS on with NO policy: service role only.
-- 3. store_reward_deferrals: referral days for a Play subscriber, sent to Google as a defer by the reconcile drain. One defer in
--    flight per user (partial unique index). RLS on with NO policy.
-- 4. private.grant_referral_days keeps its signature, ACL, security mode and argument check; it queues a deferral for a user with
--    an active Play row and otherwise calls private.grant_referral_days_direct, which is the 159 body plus one predicate that never
--    picks a Play row for the in-place extension. With no Play row the outcome is identical to 159 (test T-SQL1).
-- 5. redeem_referral_atomic (both checks) and process_referral_conversions (the calc lateral): "paid" also covers a PRODUCTION
--    Play row. A SANDBOX Play row is not paid (license testers renew every few minutes). Every other line is verbatim.
-- 6. public.store_reward_fall_back and public.upsert_play_subscription: SECURITY DEFINER writers for the Edge Functions.
--    Supabase's default privileges grant EXECUTE on a new public function DIRECTLY to anon and authenticated, so both are revoked
--    by name and the DO block at the end verifies the resulting ACLs and table privileges (migration 161 pattern).
-- 7. lock_timeout 5s for the whole apply: every DDL statement here takes a lock on a small table; a held lock must fail the
--    apply fast instead of queueing every subscriptions reader behind it.

SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. subscriptions: Play columns, checks, arbiter index
-- ---------------------------------------------------------------------------------------------------------------------
ALTER TABLE public.subscriptions
  ADD COLUMN store text,
  ADD COLUMN store_product_id text,
  ADD COLUMN store_original_transaction_id text,
  ADD COLUMN auto_renew boolean,
  ADD COLUMN store_environment text,
  ADD COLUMN store_expires_at timestamptz,
  ADD COLUMN store_read_at timestamptz;

ALTER TABLE public.subscriptions
  ADD CONSTRAINT subscriptions_store_check CHECK (store IS NULL OR store = 'play'),
  ADD CONSTRAINT subscriptions_store_environment_check
    CHECK (store_environment IS NULL OR store_environment IN ('SANDBOX', 'PRODUCTION')),
  ADD CONSTRAINT subscriptions_store_product_only_play_check CHECK (store_product_id IS NULL OR store = 'play'),
  ADD CONSTRAINT subscriptions_play_fields_check
    CHECK (store IS DISTINCT FROM 'play'
           OR (store_product_id IS NOT NULL AND store_environment IS NOT NULL AND store_read_at IS NOT NULL));

CREATE UNIQUE INDEX subscriptions_play_product_uq ON public.subscriptions (user_id, store_product_id);

COMMENT ON COLUMN public.subscriptions.store IS 'NULL = our own rows (Razorpay, referral, admin); play = mirrored from RevenueCat (182).';
COMMENT ON COLUMN public.subscriptions.store_expires_at IS 'The store''s own expiry, for display; end_date may carry the 3-hour renewal window (plan section 4).';
COMMENT ON COLUMN public.subscriptions.store_read_at IS 'When the RevenueCat GET behind this row was ISSUED; the upsert ignores an older read.';

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. subscription_events: the webhook ledger
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE public.subscription_events (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  provider           text NOT NULL CHECK (provider = 'revenuecat'),
  provider_event_id  text NOT NULL UNIQUE,
  user_id            uuid REFERENCES public.users(id) ON DELETE SET NULL,
  event_type         text NOT NULL,
  product_id         text,
  environment        text CHECK (environment IS NULL OR environment IN ('SANDBOX', 'PRODUCTION')),
  event_timestamp_ms bigint,
  received_at        timestamptz NOT NULL DEFAULT now(),
  outcome            text
);
CREATE INDEX subscription_events_user_received_idx ON public.subscription_events (user_id, received_at);
ALTER TABLE public.subscription_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.subscription_events FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. store_reward_deferrals: referral days for a Play subscriber (Google defer queue)
-- ---------------------------------------------------------------------------------------------------------------------
CREATE TABLE public.store_reward_deferrals (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  store       text NOT NULL CHECK (store = 'play'),
  days        integer NOT NULL CHECK (days BETWEEN 1 AND 30),
  status      text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending', 'in_flight', 'applied', 'fell_back', 'needs_check')),
  claim_token uuid,
  claimed_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX store_reward_deferrals_status_created_idx ON public.store_reward_deferrals (status, created_at);
CREATE UNIQUE INDEX store_reward_deferrals_one_in_flight_uq ON public.store_reward_deferrals (user_id) WHERE status = 'in_flight';
ALTER TABLE public.store_reward_deferrals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.store_reward_deferrals FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. private.grant_referral_days_direct (159 body + one predicate) and the new private.grant_referral_days wrapper
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION private.grant_referral_days_direct(p_user_id uuid, p_days integer)
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
    RAISE EXCEPTION 'grant_referral_days_direct: a user and 1..30 days are required (got %, %)', p_user_id, p_days
      USING ERRCODE = '22023';
  END IF;

  SELECT s.id, s.end_date INTO v_id, v_end
    FROM subscriptions s
   WHERE s.user_id = p_user_id AND s.status = 'active'
     AND s.store IS DISTINCT FROM 'play'  -- 182: never extend a Play row in place (the mirror rewrites its end_date)
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

REVOKE ALL ON FUNCTION private.grant_referral_days_direct(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.grant_referral_days_direct(uuid, integer) FROM anon, authenticated;

CREATE OR REPLACE FUNCTION private.grant_referral_days(p_user_id uuid, p_days integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_user_id IS NULL OR p_days IS NULL OR p_days < 1 OR p_days > 30 THEN
    RAISE EXCEPTION 'grant_referral_days: a user and 1..30 days are required (got %, %)', p_user_id, p_days
      USING ERRCODE = '22023';
  END IF;

  -- 182: a user with an ACTIVE Play row gets the days as a Google defer of the next charge, queued here and sent by the
  -- revenuecat-reconcile drain. No subscriptions row is read FOR UPDATE or changed on this branch.
  IF EXISTS (
    SELECT 1 FROM subscriptions s
     WHERE s.user_id = p_user_id
       AND s.store = 'play'
       AND s.status = 'active'
       AND s.end_date > now()
  ) THEN
    INSERT INTO store_reward_deferrals (user_id, store, days) VALUES (p_user_id, 'play', p_days);
    RETURN;
  END IF;

  PERFORM private.grant_referral_days_direct(p_user_id, p_days);
END;
$function$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. "paid" includes a PRODUCTION Play row (160 bodies, one predicate each)
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
       AND (razorpay_payment_id IS NOT NULL
            OR (store = 'play' AND store_environment = 'PRODUCTION'))  -- 182: a PRODUCTION Play row is paid; SANDBOX is not
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
           AND (razorpay_payment_id IS NOT NULL
                OR (store = 'play' AND store_environment = 'PRODUCTION'))  -- 182: same predicate as above
      ) THEN
        RAISE EXCEPTION 'referee_has_paid_plan' USING ERRCODE = 'P0001';
      END IF;
    END;
  END LOOP;
END;
$function$;

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
           AND (s.razorpay_payment_id IS NOT NULL
                OR (s.store = 'play' AND s.store_environment = 'PRODUCTION'))  -- 182: a PRODUCTION Play row is a payment
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
-- 6a. public.store_reward_fall_back: a deferral that cannot be sent becomes ordinary stacked days, in one transaction
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.store_reward_fall_back(p_id uuid, p_token uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  v_user uuid;
  v_days integer;
BEGIN
  -- Compare-and-set first: only the caller's own state may be acted on (pending with no token, or its own claim).
  UPDATE store_reward_deferrals d
     SET status = 'fell_back', updated_at = now()
   WHERE d.id = p_id
     AND ((d.status = 'pending' AND p_token IS NULL)
          OR (d.status IN ('in_flight', 'needs_check') AND d.claim_token = p_token))
  RETURNING d.user_id, d.days INTO v_user, v_days;

  IF v_user IS NULL THEN
    RETURN 'noop';
  END IF;

  -- The direct grant INSERTs a child row of users: take the key share NOWAIT first (migrations CLAUDE.md, the account-deletion
  -- deadlock row). A held users row raises 55P03 and rolls the whole call back, the status flip included; the drain retries.
  PERFORM 1 FROM users u WHERE u.id = v_user FOR KEY SHARE NOWAIT;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'store_reward_fall_back: user gone' USING ERRCODE = 'P0002';
  END IF;

  PERFORM private.grant_referral_days_direct(v_user, v_days);
  RETURN 'fell_back';
EXCEPTION
  WHEN no_data_found THEN
    RETURN 'noop';  -- the block's changes (the status flip) are rolled back with the exception
END;
$function$;

REVOKE ALL ON FUNCTION public.store_reward_fall_back(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.store_reward_fall_back(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.store_reward_fall_back(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.store_reward_fall_back(uuid, uuid) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6b. public.upsert_play_subscription: the mirror's only writer of a Play row
-- ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.upsert_play_subscription(
  p_user_id uuid,
  p_product_id text,
  p_plan text,
  p_status text,
  p_start timestamptz,
  p_end timestamptz,
  p_auto_renew boolean,
  p_environment text,
  p_original_txn text,
  p_store_expires_at timestamptz,
  p_read_at timestamptz
)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  v_n integer;
BEGIN
  IF p_user_id IS NULL OR p_product_id IS NULL OR p_start IS NULL OR p_end IS NULL OR p_read_at IS NULL
     OR p_plan IS NULL OR p_plan NOT IN ('monthly', 'yearly')
     OR p_status IS NULL OR p_status NOT IN ('active', 'expired', 'cancelled')
     OR p_environment IS NULL OR p_environment NOT IN ('SANDBOX', 'PRODUCTION') THEN
    RAISE EXCEPTION 'upsert_play_subscription: invalid arguments' USING ERRCODE = '22023';
  END IF;

  INSERT INTO subscriptions AS s (
    user_id, plan, status, start_date, end_date,
    store, store_product_id, store_original_transaction_id, auto_renew, store_environment, store_expires_at, store_read_at
  ) VALUES (
    p_user_id, p_plan, p_status, p_start, p_end,
    'play', p_product_id, p_original_txn, p_auto_renew, p_environment, p_store_expires_at, p_read_at
  )
  ON CONFLICT (user_id, store_product_id) DO UPDATE
     SET plan                          = excluded.plan,
         status                        = excluded.status,
         -- a running chain keeps its first period's purchase date; a chain that had ended starts fresh (plan section 3)
         start_date                    = CASE WHEN s.status = 'active' THEN s.start_date ELSE excluded.start_date END,
         end_date                      = excluded.end_date,
         store_original_transaction_id = excluded.store_original_transaction_id,
         auto_renew                    = excluded.auto_renew,
         store_environment             = excluded.store_environment,
         store_expires_at              = excluded.store_expires_at,
         store_read_at                 = excluded.store_read_at
   WHERE s.store_read_at <= excluded.store_read_at;   -- an older read never overwrites a newer one

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN CASE WHEN v_n = 1 THEN 'written' ELSE 'stale_read' END;
END;
$function$;

REVOKE ALL ON FUNCTION public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz) TO service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Self-check: verify the resulting state, not the statements (a REVOKE removes only what the revoking role granted).
-- ---------------------------------------------------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT unnest(ARRAY[
    'public.store_reward_fall_back(uuid, uuid)',
    'public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz)',
    'private.grant_referral_days_direct(uuid, integer)',
    'private.grant_referral_days(uuid, integer)',
    'public.redeem_referral_atomic(text, uuid, uuid, integer)'
  ]) AS fn LOOP
    IF has_function_privilege('anon', r.fn, 'EXECUTE') OR has_function_privilege('authenticated', r.fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'migration 182 self-check: a client role can execute %', r.fn;
    END IF;
  END LOOP;
  IF NOT has_function_privilege('service_role', 'public.store_reward_fall_back(uuid, uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.redeem_referral_atomic(text, uuid, uuid, integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'migration 182 self-check: service_role lost EXECUTE on a writer';
  END IF;
  FOR r IN SELECT unnest(ARRAY['public.subscription_events', 'public.store_reward_deferrals']) AS t LOOP
    IF has_table_privilege('anon', r.t, 'SELECT') OR has_table_privilege('authenticated', r.t, 'SELECT')
       OR has_table_privilege('anon', r.t, 'INSERT') OR has_table_privilege('authenticated', r.t, 'INSERT') THEN
      RAISE EXCEPTION 'migration 182 self-check: a client role can read or write %', r.t;
    END IF;
  END LOOP;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'private.grant_referral_days(uuid, integer)'::regprocedure)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'private.grant_referral_days_direct(uuid, integer)'::regprocedure)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'private.process_referral_conversions()'::regprocedure)
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.redeem_referral_atomic(text, uuid, uuid, integer)'::regprocedure) THEN
    RAISE EXCEPTION 'migration 182 self-check: a replaced function lost SECURITY DEFINER';
  END IF;
END
$$;

-- ROLLBACK (inline; run only with the founder's go, and only after ENABLE_PLAY_BILLING_MIRROR is unset and every
-- store_reward_deferrals row is terminal (runbook, plan section 10)). Order: restore the three bodies (the wrapper
-- first, so nothing calls _direct), then drop the new functions. Columns and tables stay (additive).
--
-- CREATE OR REPLACE FUNCTION private.grant_referral_days(p_user_id uuid, p_days integer)
--  RETURNS void
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- DECLARE
--   v_id  uuid;
--   v_end timestamptz;
-- BEGIN
--   IF p_user_id IS NULL OR p_days IS NULL OR p_days < 1 OR p_days > 30 THEN
--     RAISE EXCEPTION 'grant_referral_days: a user and 1..30 days are required (got %, %)', p_user_id, p_days
--       USING ERRCODE = '22023';
--   END IF;
--
--   SELECT s.id, s.end_date INTO v_id, v_end
--     FROM subscriptions s
--    WHERE s.user_id = p_user_id AND s.status = 'active'
--    ORDER BY s.end_date DESC, s.id
--    LIMIT 1
--    FOR UPDATE NOWAIT;
--
--   IF v_id IS NULL OR v_end < now() THEN
--     INSERT INTO subscriptions (user_id, plan, status, start_date, end_date)
--     VALUES (p_user_id, 'referral_trial', 'active', now(), now() + (p_days || ' days')::interval);
--   ELSE
--     UPDATE subscriptions
--        SET end_date = end_date + (p_days || ' days')::interval
--      WHERE id = v_id;
--   END IF;
-- END;
-- $function$;
--
-- CREATE OR REPLACE FUNCTION public.redeem_referral_atomic(
--   p_code text,
--   p_referrer_id uuid,
--   p_referee_id uuid,
--   p_days integer
-- )
--  RETURNS void
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- DECLARE
--   v_key_referee bigint := hashtextextended('redeem_referral_atomic:' || p_referee_id::text, 0);
-- BEGIN
--   IF p_referrer_id IS NULL OR p_referee_id IS NULL THEN
--     RAISE EXCEPTION 'redeem_referral_atomic: referrer and referee are required' USING ERRCODE = '23502';
--   END IF;
--
--   -- Serialise per REFEREE: a second redemption for the same referee, and the job crediting that user as a referrer, queue here.
--   PERFORM pg_advisory_xact_lock(v_key_referee);
--
--   IF EXISTS (
--     SELECT 1 FROM subscriptions
--      WHERE user_id = p_referee_id
--        AND plan IN ('monthly', 'yearly')
--        AND razorpay_payment_id IS NOT NULL
--   ) THEN
--     RAISE EXCEPTION 'referee_has_paid_plan' USING ERRCODE = 'P0001';
--   END IF;
--
--   -- Audit row (UNIQUE constraint on referee_id catches duplicates). The referrer is rewarded later, by the job.
--   INSERT INTO referral_redemptions (
--     code, referrer_id, referee_id, days_granted_each, referrer_rewarded, referee_rewarded
--   ) VALUES (
--     p_code, p_referrer_id, p_referee_id, p_days, false, true
--   );
--
--   -- 160: the helper reads the subscription row FOR UPDATE NOWAIT (a held row raises 55P03 at once). Where 158 waited, a redeem that
--   -- meets a momentarily held row (a webhook inserting the friend's payment) now retries, up to 3 attempts 0.25 s apart; ONLY
--   -- lock_not_available is retried, any other error propagates at once; the third failure re-raises and aborts the whole call
--   -- (the audit row above is rolled back with it), so the caller sees the same 55P03 as before.
--   FOR v_attempt IN 1..3 LOOP
--     BEGIN
--       PERFORM private.grant_referral_days(p_referee_id, p_days);
--       EXIT;
--     EXCEPTION WHEN lock_not_available THEN
--       IF v_attempt = 3 THEN
--         RAISE;
--       END IF;
--       PERFORM pg_sleep(0.25);
--       -- the wait is long enough for a payment to land: re-validate the precondition checked above (a referee who has paid must not
--       -- receive the trial days) before the next attempt; the raise rolls the whole call back, the audit row included.
--       IF EXISTS (
--         SELECT 1 FROM subscriptions
--          WHERE user_id = p_referee_id
--            AND plan IN ('monthly', 'yearly')
--            AND razorpay_payment_id IS NOT NULL
--       ) THEN
--         RAISE EXCEPTION 'referee_has_paid_plan' USING ERRCODE = 'P0001';
--       END IF;
--     END;
--   END LOOP;
-- END;
-- $function$;
--
-- CREATE OR REPLACE FUNCTION private.process_referral_conversions()
--  RETURNS jsonb
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- DECLARE
--   c_window             CONSTANT interval := interval '90 days';  -- a payment counts if it is made within this long after the code was applied
--   c_vest               CONSTANT interval := interval '7 days';   -- the reward is credited once the payment has stood this long
--   c_scan               CONSTANT interval := interval '97 days';  -- window plus a 7-day outage grace: older, never-converted rows are not looked at
--   c_batch              CONSTANT integer  := 50;                  -- rewards credited per run at most
--   c_stall              CONSTANT interval := interval '10 days';  -- a reward still pending this long after its payment (vest 7 days + 3) is stalled
--   c_volume_credits     CONSTANT integer  := 10;                  -- Phase-1 placeholders (alerts/_thresholds.yaml)
--   c_volume_redemptions CONSTANT integer  := 20;
--   r             record;
--   v_reconciled  integer := 0;
--   v_voided      integer := 0;
--   v_credited    integer := 0;
--   v_failed      integer := 0;
--   v_skipped     integer := 0;
--   v_n           integer;
--   v_stalled     integer;
--   v_failed_ids  text[]  := ARRAY[]::text[];
-- BEGIN
--   -- 0. STALL WATCH (see the header): before the job lock, so it still fires while another run holds that lock.
--   BEGIN
--     SELECT count(*) INTO v_stalled
--       FROM referral_redemptions rr
--      WHERE rr.converted_at IS NOT NULL
--        AND rr.converted_at <= now() - c_stall
--        AND rr.referrer_id IS NOT NULL
--        AND rr.referrer_rewarded IS NOT TRUE;
--     IF v_stalled > 0 THEN
--       INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--       SELECT 'referral_conversions_stalled', 'warn',
--              format('%s referral reward(s) have been pending more than 3 days past their vest: the hourly job is not crediting them', v_stalled),
--              jsonb_build_object('stalled', v_stalled),
--              'Check that cron.job referral_conversions_hourly is active, look for a long-open session holding the job''s advisory lock or a referrer''s, and read the failed and skipped_locked counts of the runs.'
--        WHERE NOT EXISTS (
--          SELECT 1 FROM public.alerts x
--           WHERE x.source = 'referral_conversions_stalled'
--             AND x.acknowledged = false
--             AND x.severity = 'warn'
--             AND x.detected_at > now() - interval '23 hours'
--        );
--     END IF;
--   EXCEPTION WHEN OTHERS THEN
--     NULL;
--   END;
--
--   -- An overlapping run (a slow earlier one) must not double up: return at once.
--   IF NOT pg_try_advisory_xact_lock(hashtextextended('process_referral_conversions', 0)) THEN
--     RETURN jsonb_build_object('skipped', 'locked');
--   END IF;
--
--   -- 1. RECONCILE. Candidates are locked in their own MATERIALIZED CTE (SKIP LOCKED: a row held by a deletion cascade is
--   --    left for the next run, never waited for); the earliest qualifying payment is read in a second CTE (payment rows are
--   --    read, not locked); ONE UPDATE writes only what differs, so a steady state changes no column.
--   WITH cand AS MATERIALIZED (
--     SELECT rr.id, rr.referee_id, rr.created_at
--       FROM referral_redemptions rr
--      WHERE rr.referrer_id IS NOT NULL
--        AND rr.referrer_rewarded IS NOT TRUE
--        AND (rr.created_at > now() - c_scan OR rr.converted_at IS NOT NULL)
--      FOR UPDATE OF rr SKIP LOCKED
--   ), calc AS (
--     SELECT c.id, q.start_date, q.plan
--       FROM cand c
--       LEFT JOIN LATERAL (
--         SELECT s.start_date, s.plan
--           FROM subscriptions s
--          WHERE s.user_id = c.referee_id
--            AND s.plan IN ('monthly', 'yearly')
--            AND s.razorpay_payment_id IS NOT NULL
--            AND s.status = 'active'
--            AND s.cancelled_at IS NULL
--            AND s.start_date >= c.created_at
--            AND s.start_date <= c.created_at + c_window
--          ORDER BY s.start_date, s.id
--          LIMIT 1
--       ) q ON true
--   ), upd AS (
--     UPDATE referral_redemptions rr
--        SET converted_at         = calc.start_date,
--            referrer_reward_days = CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END
--       FROM calc
--      WHERE rr.id = calc.id
--        AND (rr.converted_at IS DISTINCT FROM calc.start_date
--             OR rr.referrer_reward_days IS DISTINCT FROM (CASE calc.plan WHEN 'yearly' THEN 30 WHEN 'monthly' THEN 7 END))
--     RETURNING rr.converted_at
--   )
--   SELECT count(*) FILTER (WHERE converted_at IS NOT NULL),
--          count(*) FILTER (WHERE converted_at IS NULL)
--     INTO v_reconciled, v_voided
--     FROM upd;
--
--   -- 2. CREDIT. Each row in its own sub-block: a failure rolls back that row's grant and flag together and the row stays
--   --    pending for the next run. Order inside the block: the referrer's advisory lock (try), the users-row key share
--   --    (NOWAIT: the foreign key of a later INSERT would otherwise queue behind an account deletion), the grant, the flag.
--   FOR r IN
--     SELECT rr.id, rr.referrer_id, rr.referrer_reward_days AS reward_days
--       FROM referral_redemptions rr
--      WHERE rr.converted_at IS NOT NULL
--        AND rr.converted_at <= now() - c_vest
--        AND rr.referrer_id IS NOT NULL
--        AND rr.referee_id IS NOT NULL   -- 160: a deleted friend's stale converted_at is never credited (the reconcile voids the row next run)
--        AND rr.referrer_rewarded IS NOT TRUE
--      ORDER BY rr.converted_at, rr.id
--      LIMIT c_batch
--      FOR UPDATE OF rr SKIP LOCKED
--   LOOP
--     BEGIN
--       IF NOT pg_try_advisory_xact_lock(hashtextextended('redeem_referral_atomic:' || r.referrer_id::text, 0)) THEN
--         v_skipped := v_skipped + 1;
--         CONTINUE;
--       END IF;
--
--       PERFORM 1 FROM public.users u WHERE u.id = r.referrer_id FOR KEY SHARE NOWAIT;
--       IF NOT FOUND THEN
--         CONTINUE;  -- the referrer's account is gone; the row loses its referrer_id by the foreign key and drops out
--       END IF;
--
--       PERFORM private.grant_referral_days(r.referrer_id, r.reward_days);
--
--       UPDATE referral_redemptions
--          SET referrer_rewarded = true, referrer_credited_at = now()
--        WHERE id = r.id AND referrer_rewarded IS NOT TRUE;
--       GET DIAGNOSTICS v_n = ROW_COUNT;
--       IF v_n <> 1 THEN
--         RAISE EXCEPTION 'referral reward flag matched % rows for redemption %', v_n, r.id;
--       END IF;
--
--       v_credited := v_credited + 1;
--     EXCEPTION
--       WHEN lock_not_available THEN
--         v_skipped := v_skipped + 1;
--       WHEN OTHERS THEN
--         v_failed := v_failed + 1;
--         v_failed_ids := v_failed_ids || r.id::text;
--     END;
--   END LOOP;
--
--   -- 3. ALERTS (warn: the founder digest reads every severity, the Telegram trigger fires on critical only). Each INSERT is
--   --    its own sub-block (an alert that cannot be written must never roll back the credits above), has its own source, and
--   --    is deduplicated the way migration 145 does: an open alert of the same source from the last 23 hours suppresses it.
--   IF v_failed > 0 THEN
--     BEGIN
--       INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--       SELECT 'referral_conversions_failed', 'warn',
--              format('%s referral reward credit(s) failed in the last run; the referrer(s) were not rewarded yet', v_failed),
--              jsonb_build_object('failed', v_failed, 'redemption_ids', to_jsonb(v_failed_ids)),
--              'Read cron.job_run_details for referral_conversions_hourly and the named referral_redemptions rows; the rewards stay pending and are retried every hour.'
--        WHERE NOT EXISTS (
--          SELECT 1 FROM public.alerts x
--           WHERE x.source = 'referral_conversions_failed'
--             AND x.acknowledged = false
--             AND x.severity = 'warn'
--             AND x.detected_at > now() - interval '23 hours'
--        );
--     EXCEPTION WHEN OTHERS THEN
--       NULL;
--     END;
--   END IF;
--
--   BEGIN
--     IF v_credited > c_volume_credits
--        OR (SELECT count(*) FROM referral_redemptions WHERE created_at > now() - interval '24 hours') > c_volume_redemptions THEN
--       INSERT INTO public.alerts (source, severity, summary, context_json, suggested_action)
--       SELECT 'referral_conversions_volume', 'warn',
--              'Unusual referral volume: many rewards credited in one run or many redemptions in 24 hours',
--              jsonb_build_object(
--                'credited_this_run', v_credited,
--                'redemptions_24h', (SELECT count(*) FROM referral_redemptions WHERE created_at > now() - interval '24 hours'),
--                'max_redemptions_24h_one_referrer', (SELECT coalesce(max(c), 0) FROM (SELECT count(*) AS c FROM referral_redemptions WHERE created_at > now() - interval '24 hours' AND referrer_id IS NOT NULL GROUP BY referrer_id) t)),
--              'Look for one referrer with many redemptions and look at the friends'' payments before more rewards vest.'
--        WHERE NOT EXISTS (
--          SELECT 1 FROM public.alerts x
--           WHERE x.source = 'referral_conversions_volume'
--             AND x.acknowledged = false
--             AND x.severity = 'warn'
--             AND x.detected_at > now() - interval '23 hours'
--        );
--     END IF;
--   EXCEPTION WHEN OTHERS THEN
--     NULL;
--   END;
--
--   RETURN jsonb_build_object(
--     'reconciled', v_reconciled,
--     'voided', v_voided,
--     'credited', v_credited,
--     'failed', v_failed,
--     'skipped_locked', v_skipped
--   );
-- END;
-- $function$;
--
-- DROP FUNCTION IF EXISTS public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz);
-- DROP FUNCTION IF EXISTS public.store_reward_fall_back(uuid, uuid);
-- DROP FUNCTION IF EXISTS private.grant_referral_days_direct(uuid, integer);
