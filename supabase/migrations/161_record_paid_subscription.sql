-- Intent: Add public.record_paid_subscription(), the serialised writer of a paid subscriptions row (lock, idempotency, stacked end, insert in one call) for the OI-341 stacking ON path; inert until ENABLE_SUBSCRIPTION_STACKING is set
-- Destructive?: no   -- creates one function and narrows its ACL; no table, column, constraint, row or existing function is touched
-- Rollback strategy: inline   -- a commented block at the end of the file drops the function; while the switch is unset no caller exists, so the drop is safe at any time
-- Linked diagnose-doc: n/a   -- a planned feature (OI-341 Piece B1, plan docs/plans/oi341-piece-b-door.md), not a bug fix

-- 161_record_paid_subscription.sql
--
-- WHY. OI-341 Piece A (docs/plans/oi341-purchase-in-trial.md) made verify-payment and razorpay-webhook compute a paid row's end_date
-- by STACKING it after the user's latest active end, behind the default-OFF secret ENABLE_SUBSCRIPTION_STACKING. Its ON path is a
-- READ (latest active end) followed by an INSERT, two PostgREST requests with nothing serialising them per user (ledger row G10):
--   * two different payments for one user that interleave both read the same end, so the second paid period overlaps the first;
--   * private.grant_referral_days (migration 159: the referee's 7 days at redeem, the referrer's credit from the hourly job) extends
--     the user's LATEST active row under the advisory key below; a payment that read before that extension and inserted after it
--     silently absorbs those days.
-- This function does the lock, the idempotency check, the read and the insert in ONE transaction. The writers call it on the ON path
-- only (Piece B1, plan docs/plans/oi341-piece-b-door.md); the OFF path is unchanged, so this function is INERT until the switch is set:
-- only service_role may execute it and no code path calls it while the switch is unset.
--
-- 1. LOCK. The SAME advisory key that redeem_referral_atomic (blocking, migrations 159:139 / 160:73) and process_referral_conversions
--    (try-lock per referrer, 159:284 / 160:241) take, so a payment, a referee grant and a referrer credit for one user run one at a
--    time. Each path takes ONE advisory lock, so no lock-order deadlock exists. With the lock held either order adds up:
--    grant first -> the payment stacks on (trial end + 7); payment first -> the grant extends the paid row (its end + 7).
-- 2. TIME. clock_timestamp() AFTER the lock, so a call that waited does not stamp a stale instant. start_date and created_at are that
--    instant: migration 159's job reads start_date as the payment time and compares it with created_at windows that are DB-clock
--    values too.
-- 3. IDEMPOTENCY. Under the lock: a row with this payment id for this user returns it (out_inserted = false); the same id owned by
--    ANOTHER user raises P0001 payment_owned_by_other_user (defense in depth: verify-payment's own pre-SELECT is user-scoped).
-- 4. BASE. max(end_date) over the user's ACTIVE rows that end after now, excluding this payment's own row, with IS DISTINCT FROM so a
--    NULL-payment-id row (a referral trial or an admin grant) counts. A non-finite or out-of-range base raises 22008 BEFORE the
--    insert: infinity + interval is infinity, a row the calling Edge Function could not parse after it had committed.
-- 5. INSERT ... ON CONFLICT (razorpay_payment_id) DO NOTHING. The arbiter is the plain unique_razorpay_payment_id constraint
--    (migration 010:9; nulls distinct, 094). A conflict means a writer that did not take the lock (an OFF-path isolate) won the race:
--    re-select, raise if the row is another user's, else return it with out_inserted = false.
-- 6. ATTRIBUTES. SET TimeZone = 'UTC': timestamptz + interval adds calendar days in the SESSION zone, which moves an hour across a
--    daylight-saving change. SET lock_timeout = '5s' bounds every wait in the call (the advisory lock; an ON CONFLICT wait on an
--    uncommitted insert of the same id; the KEY SHARE wait on the users row behind an uncommitted account deletion, see
--    supabase/migrations/CLAUDE.md); a timeout raises 55P03 and the writer answers its existing retryable 500 with an alert.
--    Accepted risk: process_referral_conversions holds a referrer's key for the rest of its transaction, so that referrer paying
--    during the hourly run can hit the timeout; the webhook's retry then succeeds. VOLATILE (the default, stated): a STABLE function
--    would take its snapshot before the lock and miss rows committed while it waited.
-- 7. GRANTS. Supabase's default privileges grant EXECUTE on a new public function DIRECTLY to anon and authenticated, so REVOKE FROM
--    PUBLIC alone is a no-op for them (migration 103 / diagnose a9d3f1, recurred in 123). Both are revoked by name; the DO block
--    verifies the resulting state and RAISES (aborting a transaction-wrapped apply) if a client role can still execute it.

CREATE OR REPLACE FUNCTION public.record_paid_subscription(
  p_user_id    uuid,
  p_plan       text,
  p_payment_id text,
  p_order_id   text,
  p_signature  text
)
RETURNS TABLE (out_end_date timestamptz, out_start_date timestamptz, out_inserted boolean)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public, pg_temp
SET "TimeZone" = 'UTC'
SET lock_timeout = '5s'
AS $$
DECLARE
  v_days       integer;
  v_now        timestamptz;
  v_base       timestamptz;
  v_owner      uuid;
  v_end        timestamptz;
  v_start      timestamptz;
BEGIN
  -- 1. Arguments. Days are derived here so a caller cannot pass a count that disagrees with the plan.
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'invalid_user_id' USING ERRCODE = '22023';
  END IF;
  IF p_plan = 'monthly' THEN
    v_days := 30;
  ELSIF p_plan = 'yearly' THEN
    v_days := 365;
  ELSE
    RAISE EXCEPTION 'invalid_plan' USING ERRCODE = '22023';
  END IF;
  IF p_payment_id IS NULL OR p_payment_id !~ '^pay_[A-Za-z0-9]{1,64}$' THEN
    RAISE EXCEPTION 'invalid_payment_id' USING ERRCODE = '22023';
  END IF;

  -- 2. One lock per user, shared with the referral redeem and the referral job.
  PERFORM pg_advisory_xact_lock(hashtextextended('redeem_referral_atomic:' || p_user_id::text, 0));

  -- 3. The payment instant, taken after any wait for the lock.
  v_now := clock_timestamp();

  -- 4. Idempotency fast path, under the lock. The step-6 conflict re-select gives the same answers (so dropping this block
  --    changes no result, only skips the base read); it is kept so a replay does no insert attempt. A replay returns the
  --    STORED row whatever its status, plan, order id or signature: the payment is already recorded, never re-inserted.
  SELECT s.user_id, s.end_date, s.start_date
    INTO v_owner, v_end, v_start
    FROM subscriptions s
   WHERE s.razorpay_payment_id = p_payment_id;
  IF FOUND THEN
    IF v_owner IS DISTINCT FROM p_user_id THEN
      RAISE EXCEPTION 'payment_owned_by_other_user' USING ERRCODE = 'P0001';
    END IF;
    RETURN QUERY SELECT v_end, v_start, false;
    RETURN;
  END IF;

  -- 5. The base: the latest active end of any OTHER row, or now.
  SELECT greatest(v_now, coalesce(max(s.end_date), v_now))
    INTO v_base
    FROM subscriptions s
   WHERE s.user_id = p_user_id
     AND s.status = 'active'
     AND s.end_date > v_now
     AND s.razorpay_payment_id IS DISTINCT FROM p_payment_id;
  -- The end is base + up to 365 days and must keep a 4-digit year: JS Date.parse cannot read Postgres's '10000-...' form.
  IF NOT isfinite(v_base) OR v_base > timestamptz '9999-12-31 00:00:00+00' - interval '366 days' THEN
    RAISE EXCEPTION 'invalid_base_end_date' USING ERRCODE = '22008';
  END IF;

  -- 6. The insert. A conflict means an unlocked writer inserted this payment first.
  INSERT INTO subscriptions AS ins (
    user_id, plan, status, start_date, end_date,
    razorpay_payment_id, razorpay_order_id, razorpay_signature, created_at
  ) VALUES (
    p_user_id, p_plan, 'active', v_now, v_base + make_interval(days => v_days),
    p_payment_id, p_order_id, p_signature, v_now
  )
  ON CONFLICT (razorpay_payment_id) DO NOTHING
  RETURNING ins.end_date, ins.start_date INTO v_end, v_start;

  IF FOUND THEN
    RETURN QUERY SELECT v_end, v_start, true;
    RETURN;
  END IF;

  SELECT s.user_id, s.end_date, s.start_date
    INTO v_owner, v_end, v_start
    FROM subscriptions s
   WHERE s.razorpay_payment_id = p_payment_id;
  IF NOT FOUND THEN
    -- The conflicting row was removed (or is invisible) between the insert and this read: retryable, not an ownership refusal.
    RAISE EXCEPTION 'payment_row_vanished' USING ERRCODE = '40001';
  END IF;
  IF v_owner IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'payment_owned_by_other_user' USING ERRCODE = 'P0001';
  END IF;
  RETURN QUERY SELECT v_end, v_start, false;
END;
$$;

COMMENT ON FUNCTION public.record_paid_subscription(uuid, text, text, text, text) IS
  'OI-341 Piece B1 (migration 161): the serialised writer of a paid subscriptions row on the stacking ON path. '
  'Lock (key shared with the referral redeem and job), idempotency by payment id (other-user raises P0001), '
  'end = max(now, latest active end of any other row) + 30/365 days, insert. service_role only. Inert while '
  'ENABLE_SUBSCRIPTION_STACKING is unset. Plan docs/plans/oi341-piece-b-door.md.';

REVOKE ALL ON FUNCTION public.record_paid_subscription(uuid, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_paid_subscription(uuid, text, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.record_paid_subscription(uuid, text, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.record_paid_subscription(uuid, text, text, text, text) TO service_role;

-- Self-check: a REVOKE removes only privileges the revoking role granted, so verify the resulting state, not the statements.
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.record_paid_subscription(uuid, text, text, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'migration 161 self-check: anon can still execute record_paid_subscription';
  END IF;
  IF has_function_privilege('authenticated', 'public.record_paid_subscription(uuid, text, text, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'migration 161 self-check: authenticated can still execute record_paid_subscription';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.record_paid_subscription(uuid, text, text, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'migration 161 self-check: service_role cannot execute record_paid_subscription';
  END IF;
END
$$;

-- ROLLBACK (inline; run only with the founder's go, and only while ENABLE_SUBSCRIPTION_STACKING is unset or the writers are back on
-- verify-payment v25 / razorpay-webhook v29, since the ON path calls this function):
--
-- DROP FUNCTION IF EXISTS public.record_paid_subscription(uuid, text, text, text, text);
