-- test/sql/oi320_referrer_cap_replica_schema.sql
--
-- A LOCAL, THROWAWAY replica of the live objects that public.redeem_referral_atomic touches, for proving
-- migration 158 (OI-320, per-referrer referral cap) before it goes anywhere near the live project.
-- NEVER run this against project dedsavbjuwgarrhphgnl (it CREATEs tables): it is for a disposable
-- supabase/postgres container only (docs/plans/oi320-referrer-cap.md, section 3).
--
-- WHAT IS REPLICATED, and where each fact was read (live, read-only, 2026-10-11):
--   * public.referral_redemptions: the 8 live columns (there is NO `redeemed_at`; the window clock is
--     created_at), no_self_referral, unique_referee_redemption, both FKs ON DELETE CASCADE, and the two live
--     indexes (idx_referral_redemptions_redeemed_at is on created_at).
--   * public.subscriptions: the 12 live columns, UNIQUE(razorpay_payment_id), FK to users. NOT replicated: the
--     BEFORE INSERT/UPDATE trigger trg_set_subscription_cancelled_at (private.set_subscription_cancelled_at);
--     it writes cancelled_at only and nothing in the function reads it.
--   * public.users: id only. The live table also has an FK to auth.users(id); the replica drops that edge so
--     fixtures need no auth rows.
--   * public.redeem_referral_atomic: the LIVE definition, byte for byte as pg_get_functiondef returned it
--     (migration 038 body + the search_path of migration 053), with the live ACL
--     {postgres=X/postgres,service_role=X/postgres}.
-- Fixtures: 20 users, none holding a subscription or a redemption.
--
-- BUILD (once, inside the container oi320-pgtest, see the header of test/sql/oi320_referrer_cap_concurrency_local.sh):
--   create database oi320_a;   then   psql -d oi320_a -v ON_ERROR_STOP=1 -f this file   then   -f supabase/migrations/158_referral_referrer_cap.sql

-- ONE TRANSACTION, REFUSING A NON-EMPTY TARGET (B-pass of the OI-320 batch, a P2, reproduced). Run in psql's default mode
-- against a database that already held the replica, the failing CREATE TABLEs were skipped and the later statements still
-- ran: the capped function was REPLACED by the old uncapped body, 20 more users were inserted and a valid marker was left
-- behind, so the delete-capable replica-only files then ran against it. Now: the whole file is BEGIN ... COMMIT, a guard
-- refuses a target that already holds any of these objects, and the marker is created LAST (a file that did not run to
-- the end leaves no marker, and an error aborts the transaction so COMMIT rolls everything back).
BEGIN;

DO $guard$
BEGIN
  IF to_regclass('public.users') IS NOT NULL
     OR to_regclass('public.referral_redemptions') IS NOT NULL
     OR to_regclass('public.subscriptions') IS NOT NULL
     OR to_regclass('public.oi320_replica_marker') IS NOT NULL
     OR to_regnamespace('auth') IS NOT NULL
     OR to_regprocedure('public.redeem_referral_atomic(text,uuid,uuid,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'REFUSED this file builds the replica from scratch, and the target database already holds public.users / referral_redemptions / subscriptions / redeem_referral_atomic / the replica marker / an auth schema (a real project, or a replica that is already built)';
  END IF;
END
$guard$;

CREATE TABLE public.users (id uuid PRIMARY KEY);

CREATE TABLE public.referral_redemptions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id       uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  referee_id        uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
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

CREATE OR REPLACE FUNCTION public.redeem_referral_atomic(p_code text, p_referrer_id uuid, p_referee_id uuid, p_days integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_referrer_expires TIMESTAMPTZ;
  v_referee_expires TIMESTAMPTZ;
BEGIN
  -- 1. Audit row (UNIQUE constraint on referee_id catches duplicates)
  INSERT INTO referral_redemptions (
    code, referrer_id, referee_id, days_granted_each
  ) VALUES (
    p_code, p_referrer_id, p_referee_id, p_days
  );

  -- 2. Extend referrer's subscription
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

  -- 3. Same for referee
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

INSERT INTO public.users (id) SELECT gen_random_uuid() FROM generate_series(1, 20);

-- ROW-LEVEL SECURITY of the live table (read live, read-only, 2026-10-11; hermes pass of the OI-320 batch, a P2: without
-- this the replica ran with RLS off and nothing pinned who can read or WRITE the audit rows). Live: RLS enabled (not
-- forced), exactly ONE policy "Users can read own redemptions" (SELECT, role public; migrations 037 and 100), no
-- INSERT / UPDATE / DELETE policy, and the platform-default full table grants to anon, authenticated and service_role -
-- so RLS is the only thing between an authenticated user and their own audit rows. The cap relies on that.
-- auth.uid() is the minimal stand-in for Supabase's (a fresh container has the roles but no auth schema).
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
  AS $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
ALTER TABLE public.referral_redemptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own redemptions" ON public.referral_redemptions FOR SELECT
  USING (((select auth.uid()) = referrer_id) OR ((select auth.uid()) = referee_id));
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.referral_redemptions TO anon, authenticated, service_role;

-- Positive marker that identifies a disposable replica, created LAST. The live project does not have this table, and the
-- replica-only files (deletion scenario, race script) REFUSE to run without it: a user-count threshold cannot tell the
-- 20-user replica from the 43-user live project (round-2 review).
CREATE TABLE public.oi320_replica_marker (note text);
INSERT INTO public.oi320_replica_marker VALUES ('disposable replica of the OI-320 objects; never create this table on a real project');

COMMIT;
