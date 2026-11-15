-- Intent: Cap the PRO days a referrer earns at 7 credited referrals in any rolling 90 days (OI-320, founder decision 2026-10-11); the referee is ALWAYS credited. Redefines redeem_referral_atomic, and re-creates referral_redemptions.referrer_id / referee_id as nullable with ON DELETE SET NULL so deleting an account cannot reopen the cap or a referee's one-code-ever guard.
-- Destructive?: no   -- widening only: two NOT NULLs dropped, two FKs re-created with a different ON DELETE action, one CREATE OR REPLACE FUNCTION (same signature, return type and ACL); no column or table dropped, no row rewritten
-- Rollback strategy: inline   -- the previous function body (migration 038 + the 053 search_path) and the two CASCADE foreign keys, commented at file end
-- Linked diagnose-doc: n/a   -- a product rule, not a bug fix: OI-320 in docs/audit/open_issues.md, plan docs/plans/oi320-referrer-cap.md
--
-- 158_referral_referrer_cap.sql
--
-- WHY. redeem_referral_atomic (migration 038) credits the REFERRER 7 days for every new referee and
-- idempotency is per referee only (UNIQUE referee_id), so a referrer who brings throwaway accounts earns
-- PRO without limit: 12 referees x 7 days = 84 days of PRO per 84-day window, i.e. permanent free PRO, and the
-- progress-photo server rule (migration 154) then honours that row like a paid subscription.
--
-- THE RULE. Before crediting the referrer, count that referrer's redemptions in the last 90 days whose
-- referrer_rewarded is true. At 7 or more the referrer is NOT credited (no insert, no end_date extension);
-- the redemption itself still happens and the referee is credited exactly as before. 7 x 7 days = 49 PRO days
-- per 90 days at most, about 54%. The window is rolling: a credited redemption stops counting 90 days after its
-- created_at (strict `>`: a row exactly 90 days old no longer counts).
--
-- WHICH COLUMN RECORDS THE DECISION. referral_redemptions already has referrer_rewarded / referee_rewarded
-- (boolean, default false). Measured live 2026-10-11: no code anywhere reads or writes them (every row is
-- false, the function inserts without them). This migration makes them meaningful: referee_rewarded is always
-- true (audit only: nothing reads it), referrer_rewarded is true exactly when the cap decision credited the
-- referrer, and the cap counts the latter. The flag is written BEFORE the credit, so it records the decision, not
-- the effect: the existing `UPDATE ... WHERE end_date = v_referrer_expires` can still match zero rows if another
-- writer of that subscription row (a payment verification, a webhook) moved end_date first. That window exists
-- in the previous body too and is not widened here. Counting uncredited rows too would make a capped referrer's
-- lock-out grow with every further attempt instead of expiring 90 days after their 7th credit. The 3 legacy rows
-- (one referrer, 2026-06-17 to 2026-06-26, all credited) keep referrer_rewarded = false on purpose: they are older
-- than 90 days at the time of writing and can never enter a window, so no row is rewritten (hence Destructive? no).
-- The window column is created_at: the live table has NO `redeemed_at` column (migration 037 names an index
-- idx_referral_redemptions_redeemed_at, which is on created_at, and docs/architecture/database.md listed a column).
--
-- WHY THE FOREIGN KEYS CHANGE (plan-review rounds 1 and 2). Both foreign keys of referral_redemptions to public.users
-- were ON DELETE CASCADE, and delete-account ends in auth.admin.deleteUser, which cascades through public.users to
-- every foreign key. (1) referee_id: a throwaway referee that redeemed a code and then deleted its own account took its
-- credited audit row with it and freed one of the referrer's 7 slots: 3 deletions turned 7 credits into 10
-- (reproduced on a local replica). (2) referrer_id: a deleted REFERRER took every row of theirs with it, and with them
-- the UNIQUE(referee_id) guard of each of their referees, who could then redeem a second code inside their 7-day
-- window and be credited again (reproduced). With the referrer side capped, burner referrers that delete themselves
-- would be the cheap farm for the referee side, so it is closed here too. Both columns become nullable and both
-- foreign keys ON DELETE SET NULL (the same pseudonymisation pattern as migration 049): the row stays, the deleted
-- party's id reads NULL. UNIQUE(referee_id) tolerates many NULLs, no_self_referral (referrer_id <> referee_id) passes
-- when either side is NULL, the RLS policy reads the two columns only inside an OR, and the readers only select the
-- row (the restore path stores it raw; ReferralRepository filters on referee_id = the signed-in user). A cap is per
-- ACCOUNT: a referrer who deletes their account and signs up again starts with a fresh count; nothing in the schema
-- can tie two accounts together.
--
-- LOCKS TAKEN BY THE DDL. DROP CONSTRAINT on a foreign key takes ACCESS EXCLUSIVE on BOTH tables (measured in a
-- sandbox: public.users too), held to the end of the transaction, so one long reader of public.users would queue this
-- migration and every later query on users behind it. SET lock_timeout bounds the wait (the convention of migrations
-- 152 and 157; whether apply_migration wraps a file in a transaction is unverified, so plain SET and a closing RESET).
-- The file is IDEMPOTENT (DROP NOT NULL, DROP CONSTRAINT IF EXISTS, CREATE OR REPLACE), so a failed apply converges on
-- a re-run. The DROP and the ADD of the two constraints are ONE ALTER TABLE statement, so there is no moment without
-- a foreign key. A post-condition block raises if any foreign key over either column is still not ON DELETE SET NULL
-- (a second, differently named FK would otherwise survive silently) or either column is still NOT NULL.
--
-- RACE AND LOCK ORDER. Two concurrent redemptions for one referrer would both read 6 and both credit (8 credited).
-- The function therefore takes pg_advisory_xact_lock on BOTH users' keys, in ascending key order, before the count
-- and before the audit insert. (a) Same referrer: the second transaction waits for the first's commit, and its count
-- then sees the first's row (READ COMMITTED takes a new snapshot per statement). (b) Any two redemptions that touch
-- a common subscription row share a user and therefore a key, so they serialise BEFORE touching that row; with a
-- fixed lock order (lowest key first) and ONE redemption per transaction (what the Edge Function's RPC call is) no cycle
-- of advisory locks can form; two transactions that each call the function twice in opposite order still can. That
-- also removes the cross-order subscription-row locking of the previous body (mutual redemption, P redeems Q while Q
-- redeems P) from this function's own interleavings. Writers outside this function (a webhook, a payment verification) take no advisory
-- lock; their interleaving with a redemption is unchanged. A caller queued behind a stalled holder waits until the
-- holder ends or a statement/lock timeout (if one is configured) fires; the Edge Function returns any error other
-- than 23505 as a 500 "Internal server error" (the client may retry), and nothing is left half-written.
--
-- WHAT DOES NOT CHANGE. Signature (text, uuid, uuid, integer), RETURNS void, SECURITY DEFINER, EXECUTE for
-- service_role only. CREATE OR REPLACE keeps the ACL (only DROP + CREATE resets it, bug class 2.36), but the
-- SET search_path is part of the definition and WOULD be dropped by a body that omits it, undoing migration 053, so
-- it is restated; the REVOKE/GRANT lines at the end re-assert the ACL idempotently. A NULL referrer or referee
-- still raises 23502, now from an explicit guard (referee_id is nullable, so the refusal must not depend on a later
-- statement failing). The redeem-referral Edge Function is not touched: it never reads the cap (the RPC returns void).

SET lock_timeout = '3s';

ALTER TABLE public.referral_redemptions ALTER COLUMN referrer_id DROP NOT NULL;
ALTER TABLE public.referral_redemptions ALTER COLUMN referee_id DROP NOT NULL;
ALTER TABLE public.referral_redemptions
  DROP CONSTRAINT IF EXISTS referral_redemptions_referrer_id_fkey,
  DROP CONSTRAINT IF EXISTS referral_redemptions_referee_id_fkey,
  ADD CONSTRAINT referral_redemptions_referrer_id_fkey FOREIGN KEY (referrer_id) REFERENCES public.users(id) ON DELETE SET NULL,
  ADD CONSTRAINT referral_redemptions_referee_id_fkey FOREIGN KEY (referee_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- Post-condition: the live table was read on 2026-10-11 and carries exactly one FK per column, but a second FK under
-- another name would survive the DROP above and keep the cascade alive, so assert instead of assuming.
DO $assert_fk$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), '; ') INTO v_bad
    FROM pg_constraint c
   WHERE c.conrelid = 'public.referral_redemptions'::regclass
     AND c.contype = 'f'
     AND c.confdeltype <> 'n'
     AND c.conkey && ARRAY(SELECT a.attnum FROM pg_attribute a
                            WHERE a.attrelid = c.conrelid AND a.attname IN ('referrer_id', 'referee_id'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'referral_redemptions still has a foreign key over referrer_id/referee_id that is not ON DELETE SET NULL: %', v_bad;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute a
              WHERE a.attrelid = 'public.referral_redemptions'::regclass
                AND a.attname IN ('referrer_id', 'referee_id') AND a.attnotnull) THEN
    RAISE EXCEPTION 'referral_redemptions.referrer_id / referee_id is still NOT NULL';
  END IF;
END
$assert_fk$;

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

-- Idempotent re-assertion of the ACL (migrations 038, 090, 091): service_role only. anon / authenticated are
-- named explicitly because the platform's default privileges grant them directly, not through PUBLIC.
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.redeem_referral_atomic(text, uuid, uuid, integer) TO service_role;

RESET lock_timeout;

-- Post-apply verification: test/sql/oi320_referrer_cap_live_verify.sql is ONE DO block that always aborts with a
-- VERIFY_RESULTS error (no explicit BEGIN/ROLLBACK), so nothing it writes survives. Read-only catalog check:
--   select proconfig, proacl::text, pg_get_function_result(oid) from pg_proc
--    where proname = 'redeem_referral_atomic';   -- expect {search_path=public}, {postgres=X/postgres,service_role=X/postgres}, void
--   select conname, confdeltype::text from pg_constraint where conrelid = 'public.referral_redemptions'::regclass
--    and contype = 'f';   -- expect exactly the two *_referrer_id_fkey / *_referee_id_fkey rows, both n
--   select attname, attnotnull from pg_attribute where attrelid = 'public.referral_redemptions'::regclass
--    and attname in ('referrer_id', 'referee_id');   -- expect both false

-- Rollback (inline): the previous body VERBATIM (038 + 053 search_path; md5 of its definition 1066f4cb5b1c36058fd5c0b635e3209d) and the CASCADE FK.
-- CREATE OR REPLACE FUNCTION public.redeem_referral_atomic(p_code text, p_referrer_id uuid, p_referee_id uuid, p_days integer)
--  RETURNS void
--  LANGUAGE plpgsql
--  SECURITY DEFINER
--  SET search_path TO 'public'
-- AS $function$
-- DECLARE
--   v_referrer_expires TIMESTAMPTZ;
--   v_referee_expires TIMESTAMPTZ;
-- BEGIN
--   -- 1. Audit row (UNIQUE constraint on referee_id catches duplicates)
--   INSERT INTO referral_redemptions (
--     code, referrer_id, referee_id, days_granted_each
--   ) VALUES (
--     p_code, p_referrer_id, p_referee_id, p_days
--   );
--
--   -- 2. Extend referrer's subscription
--   SELECT MAX(end_date) INTO v_referrer_expires
--   FROM subscriptions
--   WHERE user_id = p_referrer_id AND status = 'active';
--
--   IF v_referrer_expires IS NULL OR v_referrer_expires < now() THEN
--     INSERT INTO subscriptions (
--       user_id, plan, status, start_date, end_date
--     ) VALUES (
--       p_referrer_id,
--       'referral_trial',
--       'active',
--       now(),
--       now() + (p_days || ' days')::interval
--     );
--   ELSE
--     UPDATE subscriptions
--     SET end_date = end_date + (p_days || ' days')::interval
--     WHERE user_id = p_referrer_id AND status = 'active'
--       AND end_date = v_referrer_expires;
--   END IF;
--
--   -- 3. Same for referee
--   SELECT MAX(end_date) INTO v_referee_expires
--   FROM subscriptions
--   WHERE user_id = p_referee_id AND status = 'active';
--
--   IF v_referee_expires IS NULL OR v_referee_expires < now() THEN
--     INSERT INTO subscriptions (
--       user_id, plan, status, start_date, end_date
--     ) VALUES (
--       p_referee_id,
--       'referral_trial',
--       'active',
--       now(),
--       now() + (p_days || ' days')::interval
--     );
--   ELSE
--     UPDATE subscriptions
--     SET end_date = end_date + (p_days || ' days')::interval
--     WHERE user_id = p_referee_id AND status = 'active'
--       AND end_date = v_referee_expires;
--   END IF;
-- END;
-- $function$;
-- SET lock_timeout = '3s';
-- ALTER TABLE public.referral_redemptions
--   DROP CONSTRAINT IF EXISTS referral_redemptions_referrer_id_fkey,
--   DROP CONSTRAINT IF EXISTS referral_redemptions_referee_id_fkey,
--   ADD CONSTRAINT referral_redemptions_referrer_id_fkey FOREIGN KEY (referrer_id) REFERENCES public.users(id) ON DELETE CASCADE,
--   ADD CONSTRAINT referral_redemptions_referee_id_fkey FOREIGN KEY (referee_id) REFERENCES public.users(id) ON DELETE CASCADE;
-- -- SET NOT NULL fails while any row has a NULL referrer_id or referee_id; those rows belong to deleted accounts (the old
-- -- CASCADE would have removed them), so delete them first:
-- DELETE FROM public.referral_redemptions WHERE referrer_id IS NULL OR referee_id IS NULL;
-- ALTER TABLE public.referral_redemptions ALTER COLUMN referrer_id SET NOT NULL;
-- ALTER TABLE public.referral_redemptions ALTER COLUMN referee_id SET NOT NULL;
-- RESET lock_timeout;
-- -- Rows written while the cap was live keep referrer_rewarded / referee_rewarded as written; nothing reads them after a rollback.
