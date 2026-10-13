-- test/sql/referral_pay_on_conversion_replica_schema.sql
--
-- A LOCAL, THROWAWAY replica of the live objects that migration 159 (referral reward on conversion) touches, in the state
-- AFTER migration 158 (the state live had on 2026-10-12), for proving 159 before it goes anywhere near the live project.
-- NEVER run this against project dedsavbjuwgarrhphgnl (it CREATEs tables): it is for a disposable supabase/postgres
-- container only (docs/plans/referral-pay-on-conversion.md, section 3). Successor of test/sql/oi320_referrer_cap_replica_schema.sql
-- (which built the PRE-158 state and applied 158 on top).
--
-- WHAT IS REPLICATED, and where each fact was read (live, read-only, 2026-10-12):
--   * public.referral_redemptions: the 8 live columns after 158 (referrer_id / referee_id NULLABLE with ON DELETE SET NULL,
--     no_self_referral, unique_referee_redemption, the two live indexes), RLS on with the ONE live SELECT policy and the
--     platform-default full table grants, so RLS is the only barrier. The three 159 columns are NOT here: 159 adds them.
--   * public.subscriptions: the 12 live columns, UNIQUE(razorpay_payment_id), FK to users ON DELETE CASCADE, and the live
--     BEFORE INSERT OR UPDATE trigger private.set_subscription_cancelled_at (migration 140's body, copied from the file).
--   * public.alerts: the live columns and the severity CHECK (info / warn / critical); NOT replicated: the critical-only
--     notify trigger (it calls out over the network).
--   * public.redeem_referral_atomic: the LIVE 158 body, copied from migration 158 by the script that wrote this file, with the
--     live ACL {postgres=X/postgres,service_role=X/postgres}.
--   * a STUB `cron` schema (cron.job, cron.schedule, cron.unschedule): pg_cron is not installed in the replica, and 159 only
--     calls those two functions. A `private` schema (PostgREST does not expose it live either).
--   * public.users: id only (the live table also has an FK to auth.users, dropped here so fixtures need no auth rows).
-- Fixtures: 30 users, none holding a subscription or a redemption.
--
-- BUILD (once, inside the container rpoc-pgtest, see the header of test/sql/referral_pay_on_conversion_concurrency_local.sh):
--   create database rpoc_a;   then   psql -d rpoc_a -v ON_ERROR_STOP=1 -f this file   then   -f supabase/migrations/159_referral_reward_on_conversion.sql
--
-- ONE TRANSACTION, REFUSING A NON-EMPTY TARGET (the OI-320 B-pass lesson): the whole file is BEGIN ... COMMIT, a guard
-- refuses a target that already holds any of these objects, and the marker is created LAST.
BEGIN;

DO $guard$
BEGIN
  IF to_regclass('public.users') IS NOT NULL
     OR to_regclass('public.referral_redemptions') IS NOT NULL
     OR to_regclass('public.subscriptions') IS NOT NULL
     OR to_regclass('public.alerts') IS NOT NULL
     OR to_regclass('public.rpoc_replica_marker') IS NOT NULL
     OR to_regnamespace('auth') IS NOT NULL
     OR to_regnamespace('cron') IS NOT NULL
     OR to_regnamespace('private') IS NOT NULL
     OR to_regprocedure('public.redeem_referral_atomic(text,uuid,uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'REFUSED this file builds the replica from scratch, and the target database already holds public.users / referral_redemptions / subscriptions / alerts / redeem_referral_atomic / the auth, cron or private schema / the replica marker; use a fresh database (create database rpoc_a)';
  END IF;
END
$guard$;

CREATE SCHEMA private;
CREATE TABLE public.users (id uuid PRIMARY KEY);

CREATE TABLE public.referral_redemptions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  referee_id        uuid REFERENCES public.users(id) ON DELETE SET NULL,
  referrer_rewarded boolean DEFAULT false,
  referee_rewarded  boolean DEFAULT false,
  created_at        timestamptz DEFAULT now(),
  code              text,
  days_granted_each integer NOT NULL DEFAULT 7,
  CONSTRAINT no_self_referral CHECK (referrer_id <> referee_id),
  CONSTRAINT unique_referee_redemption UNIQUE (referee_id)
);
CREATE INDEX idx_referral_redemptions_referrer ON public.referral_redemptions (referrer_id);
CREATE INDEX idx_referral_redemptions_redeemed_at ON public.referral_redemptions (created_at);

CREATE TABLE public.subscriptions (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  plan                     text NOT NULL,
  status                   text DEFAULT 'active',
  start_date               timestamptz NOT NULL,
  end_date                 timestamptz NOT NULL,
  razorpay_order_id        text,
  razorpay_payment_id      text,
  razorpay_signature       text,
  created_at               timestamptz DEFAULT now(),
  razorpay_subscription_id text,
  cancelled_at             timestamptz,
  CONSTRAINT unique_razorpay_payment_id UNIQUE (razorpay_payment_id)
);

-- Live trigger function, migration 140's body verbatim, and the live trigger.
CREATE OR REPLACE FUNCTION private.set_subscription_cancelled_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'cancelled' THEN
      NEW.cancelled_at := now();
    END IF;
    RETURN NEW;
  END IF;

  -- TG_OP = 'UPDATE' from here.
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    NEW.cancelled_at := now();
  ELSIF NEW.status IS DISTINCT FROM 'cancelled' AND OLD.status = 'cancelled' THEN
    NEW.cancelled_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_set_subscription_cancelled_at
BEFORE INSERT OR UPDATE ON public.subscriptions
FOR EACH ROW EXECUTE FUNCTION private.set_subscription_cancelled_at();

CREATE TABLE public.alerts (
  id               bigserial PRIMARY KEY,
  detected_at      timestamptz NOT NULL DEFAULT now(),
  source           text NOT NULL,
  severity         text NOT NULL,
  summary          text NOT NULL,
  context_json     jsonb NOT NULL DEFAULT '{}'::jsonb,
  suggested_action text,
  acknowledged     boolean NOT NULL DEFAULT false,
  acknowledged_at  timestamptz,
  resolved_at      timestamptz,
  CONSTRAINT alerts_severity_check CHECK (severity = ANY (ARRAY['info'::text, 'warn'::text, 'critical'::text]))
);

-- pg_cron stand-in: 159 calls cron.unschedule(jobid) and cron.schedule(name, schedule, command) and nothing else.
CREATE SCHEMA cron;
CREATE TABLE cron.job (jobid bigserial PRIMARY KEY, jobname text, schedule text, command text, active boolean NOT NULL DEFAULT true);
CREATE FUNCTION cron.schedule(p_jobname text, p_schedule text, p_command text) RETURNS bigint LANGUAGE sql
  AS $$ INSERT INTO cron.job (jobname, schedule, command) VALUES (p_jobname, p_schedule, p_command) RETURNING jobid $$;
CREATE FUNCTION cron.unschedule(p_jobid bigint) RETURNS boolean LANGUAGE sql
  AS $$ WITH d AS (DELETE FROM cron.job WHERE jobid = p_jobid RETURNING 1) SELECT EXISTS (SELECT 1 FROM d) $$;

-- Live definition after migration 158, copied from the file.
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
  -- OI-320: at most this many CREDITED referrals per referrer in any rolling window.
  c_referrer_cap CONSTANT integer  := 7;
  c_cap_window   CONSTANT interval := interval '90 days';
  v_key_referrer bigint := hashtextextended('redeem_referral_atomic:' || p_referrer_id::text, 0);
  v_key_referee  bigint := hashtextextended('redeem_referral_atomic:' || p_referee_id::text, 0);
  v_referrer_expires TIMESTAMPTZ;
  v_referee_expires TIMESTAMPTZ;
  v_credited_in_window integer;
  v_credit_referrer boolean;
BEGIN
  IF p_referrer_id IS NULL OR p_referee_id IS NULL THEN
    RAISE EXCEPTION 'redeem_referral_atomic: referrer and referee are required' USING ERRCODE = '23502';
  END IF;

  -- 0. Serialise per USER, lowest key first, so same-referrer redemptions queue, two single-redemption transactions
  --    cannot wait on each other's advisory locks, and the count below cannot interleave with another insert.
  PERFORM pg_advisory_xact_lock(least(v_key_referrer, v_key_referee));
  PERFORM pg_advisory_xact_lock(greatest(v_key_referrer, v_key_referee));

  -- 1. The cap decision: credited redemptions of this referrer inside the rolling window.
  SELECT count(*) INTO v_credited_in_window
  FROM referral_redemptions
  WHERE referrer_id = p_referrer_id
    AND referrer_rewarded
    AND created_at > now() - c_cap_window;
  v_credit_referrer := v_credited_in_window < c_referrer_cap;

  -- 2. Audit row (UNIQUE constraint on referee_id catches duplicates). The referee is always credited;
  --    the referrer only when under the cap.
  INSERT INTO referral_redemptions (
    code, referrer_id, referee_id, days_granted_each, referrer_rewarded, referee_rewarded
  ) VALUES (
    p_code, p_referrer_id, p_referee_id, p_days, v_credit_referrer, true
  );

  -- 3. Extend the referrer's subscription (skipped at the cap).
  IF v_credit_referrer THEN
    SELECT MAX(end_date) INTO v_referrer_expires
    FROM subscriptions
    WHERE user_id = p_referrer_id AND status = 'active';

    IF v_referrer_expires IS NULL OR v_referrer_expires < now() THEN
      INSERT INTO subscriptions (
        user_id, plan, status, start_date, end_date
      ) VALUES (
        p_referrer_id,
        'referral_trial',
        'active',
        now(),
        now() + (p_days || ' days')::interval
      );
    ELSE
      UPDATE subscriptions
      SET end_date = end_date + (p_days || ' days')::interval
      WHERE user_id = p_referrer_id AND status = 'active'
        AND end_date = v_referrer_expires;
    END IF;
  END IF;

  -- 4. Same for referee (unchanged, never capped)
  SELECT MAX(end_date) INTO v_referee_expires
  FROM subscriptions
  WHERE user_id = p_referee_id AND status = 'active';

  IF v_referee_expires IS NULL OR v_referee_expires < now() THEN
    INSERT INTO subscriptions (
      user_id, plan, status, start_date, end_date
    ) VALUES (
      p_referee_id,
      'referral_trial',
      'active',
      now(),
      now() + (p_days || ' days')::interval
    );
  ELSE
    UPDATE subscriptions
    SET end_date = end_date + (p_days || ' days')::interval
    WHERE user_id = p_referee_id AND status = 'active'
      AND end_date = v_referee_expires;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) TO service_role;

INSERT INTO public.users (id) SELECT gen_random_uuid() FROM generate_series(1, 30);

-- ROW-LEVEL SECURITY of the live table (read live, read-only): RLS enabled (not forced), exactly ONE policy
-- "Users can read own redemptions" (SELECT, role public), no INSERT / UPDATE / DELETE policy, and the platform-default full
-- table grants to anon, authenticated and service_role, so RLS is the only barrier between an authenticated user and the audit
-- rows. auth.uid() is the minimal stand-in for Supabase's (a fresh container has the roles but no auth schema).
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
  AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
ALTER TABLE public.referral_redemptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own redemptions" ON public.referral_redemptions FOR SELECT
  USING (((select auth.uid()) = referrer_id) OR ((select auth.uid()) = referee_id));
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.referral_redemptions TO anon, authenticated, service_role;
-- The live subscriptions table (read 2026-10-13): RLS on, ONE policy, a SELECT of the caller's own rows. No write policy exists for anon,
-- authenticated or PUBLIC: that is what keeps a paid row unforgeable (migration 052 dropped the write policies).
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY subscriptions_select_own ON public.subscriptions FOR SELECT USING ((select auth.uid()) = user_id);

-- Positive marker that identifies a disposable replica, created LAST. The live project does not have this table, and the
-- replica-only files REFUSE to run without it.
CREATE TABLE public.rpoc_replica_marker (note text);
INSERT INTO public.rpoc_replica_marker VALUES ('disposable replica of the referral-pay-on-conversion objects; never create this table on a real project');

COMMIT;
