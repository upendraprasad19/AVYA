-- DRAFT (OI-519, hermes seat 1, 2026-11-24): NOT a migration yet. Applied at live step L2 together with the reconcile
-- cron draft, with its own founder go: the number is minted with `sh scripts/mint_migration.sh play_upsert_start_date`,
-- this file moves byte-identical (`git mv`) to `supabase/migrations/<n>_play_upsert_start_date.sql`, is applied with MCP
-- `apply_migration`, and `backups/applied_migrations.json` changes in the same commit (the 182 precedent, plan s23).
--
-- Intent: `upsert_play_subscription` (migration 182) keeps a Play chain's first start_date when the new period begins
--   at or before the stored row's end (a renewal, however late it is read), and starts fresh when it begins after it (a
--   resubscribe), instead of keying on the stored status.
-- Destructive?: no   -- CREATE OR REPLACE of one function, same signature, same result type; no row is touched
-- Rollback strategy: inline   -- re-run the 182 body (section 6b of 182) as CREATE OR REPLACE
-- Linked diagnose-doc: none (hermes finding H1-3, recorded in docs/audit/2026-11-24-hermes-oi519-play-billing.md)
--
-- Grants: CREATE OR REPLACE keeps the function's ACL (EXECUTE for service_role only, revoked from PUBLIC/anon/
-- authenticated by 182); the DO block below asserts it, and that the new rule is in the live body.
-- Local proof: test/sql/play_upsert_start_date_local.sh (C1-C6: 182 alone gets C1 and C5 wrong; 182 + this file gets all
-- six right).

CREATE OR REPLACE FUNCTION public.upsert_play_subscription(
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
         -- (hermes seat 1 + its B-pass, 2026-11-24): a chain restarts only when the NEW period begins AFTER the stored
         -- row's end (a period starting exactly at it continues the chain), never on when the last read happened. A renewal's period starts at the old expiry E, before
         -- end_date (E + 3 h, or the grace end), so it keeps the chain even when read late or after an 'expired' read; a
         -- resubscribe after the row ended starts fresh even if the row was never re-read and still says 'active'
         -- (process_referral_conversions keys on start_date). The 182 rule keyed on status alone, so both depended on
         -- read timing.
         start_date                    = CASE WHEN excluded.start_date <= s.end_date THEN s.start_date ELSE excluded.start_date END,
         end_date                      = excluded.end_date,
         store_original_transaction_id = excluded.store_original_transaction_id,
         auto_renew                    = excluded.auto_renew,
         store_environment             = excluded.store_environment,
         store_expires_at              = excluded.store_expires_at,
         store_read_at                 = excluded.store_read_at
   WHERE s.store_read_at < excluded.store_read_at   -- an older or EQUAL read never overwrites (a tie keeps the first write)
     -- a SANDBOX (license-tester) read never replaces a PRODUCTION row that is still running: "paid" for referrals keys on
     -- store_environment, so the flip would un-pay a paying user (B-pass of the draft, F1). Once the PRODUCTION row has ended
     -- (status not active, or end_date past) a newer SANDBOX read may replace it: only license testers can make SANDBOX
     -- purchases, so the user who could then redeem a referral trial is a tester (delta review P3, accepted).
     AND NOT (s.store_environment = 'PRODUCTION' AND excluded.store_environment = 'SANDBOX'
              AND s.status = 'active' AND s.end_date > now());

  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 1 THEN
    RETURN 'written';
  END IF;
  -- Nothing written: say why. A stale or tied read is routine; a refused SANDBOX-over-PRODUCTION read is not.
  RETURN CASE
    WHEN EXISTS (SELECT 1 FROM subscriptions x
                  WHERE x.user_id = p_user_id AND x.store_product_id = p_product_id
                    AND x.store_read_at >= p_read_at) THEN 'stale_read'
    ELSE 'sandbox_refused'
  END;
END;
$function$;

DO $check$
DECLARE
  v_sig text := 'public.upsert_play_subscription(uuid, text, text, text, timestamptz, timestamptz, boolean, text, text, timestamptz, timestamptz)';
BEGIN
  IF has_function_privilege('anon', v_sig, 'EXECUTE') OR has_function_privilege('authenticated', v_sig, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'upsert_play_subscription: EXECUTE grants changed';
  END IF;
  IF position('WHEN excluded.start_date <= s.end_date THEN s.start_date' IN
              (SELECT prosrc FROM pg_proc WHERE oid = v_sig::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'upsert_play_subscription: the new start_date rule is not in the body';
  END IF;
END
$check$;
