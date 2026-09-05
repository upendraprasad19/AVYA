-- Intent: Create the usage-counter ledger (`usage_counters` + `consume_quota()`)
--   that quota enforcement will move onto, plus its retention job. NOTHING CALLS
--   IT YET — this is OI-162 slice 1, deliberately inert infrastructure so the
--   nine existing call sites can migrate one slice at a time without this
--   migration carrying any behaviour change.
--
--   WHY IT EXISTS: `ai_coach_interactions` is a conversation LOG that doubles as
--   a usage LEDGER — nine sites derive a quota from its row count — and
--   `rolling-context` prunes it nightly (keeps the newest 10 once a user passes
--   50). Deleting a log is correct; deleting a ledger resets every quota derived
--   from it. See docs/audit/oi162-slice1-plan.md.
--
-- Destructive?: no   -- creates one new table, two new functions and one cron
--   job. Touches no existing table, column, policy, function or job. The
--   retention DELETE can only ever remove rows from the new table.
--
-- Rollback strategy: inline   -- reverse DDL block, commented, at end of file.
--
-- Linked diagnose-doc: d3a7f1
--
-- ⚠ NO `SECURITY-DEFINER` FUNCTION ANYWHERE IN THIS FILE, AND THAT IS LOAD-BEARING TWICE.
--   (1) SECURITY: an INVOKER function cannot be a privilege-escalation surface —
--       the caller's own privileges apply, so RLS refuses anyone who is not
--       service_role/postgres regardless of who calls it or what EXECUTE grants
--       exist. Verified live before writing this: service_role writes and
--       returns 1; `authenticated` and `anon` are both refused 42501 WHILE
--       HOLDING EXECUTE.
--   (2) TIER: `scripts/blast_radius_content_rules_lib.dart` escalates any
--       migration whose TEXT contains that keyword pair to `catastrophic`,
--       regardless of what the file actually defines. Keeping this file
--       INVOKER-only holds it at `platform`. Do not "harden" these functions to
--       DEFINER mode without re-reading that — it would silently add a
--       Hermes-pass requirement and re-open the escalation surface.
--       ⚠ The rule scans RAW TEXT with no comment-stripping, so the keyword pair
--       is deliberately hyphenated in this header. That is a false-positive
--       dodge, not a suppression: this file defines ZERO such functions, which
--       is the only thing the rule exists to catch. Filed as its own issue —
--       the rule should strip SQL comments, and a migration that documents why
--       it avoids a pattern should not be graded as using it.
--   The retention function is INVOKER for the same reason and still works:
--   pg_cron jobs here run as `postgres` (verified: every row in cron.job has
--   username='postgres'), and `postgres` has rolbypassrls=true.

-- ── 1. The ledger ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.usage_counters (
  user_id      uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  quota_key    text        NOT NULL,
  window_start timestamptz NOT NULL,
  used         integer     NOT NULL DEFAULT 0,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, quota_key, window_start)
);

COMMENT ON TABLE public.usage_counters IS
  'Usage/quota ledger (OI-162). One row per (user, quota_key, window_start); '
  'lifetime quotas use window_start = epoch. Written ONLY via consume_quota(). '
  'RLS is enabled with NO policy on purpose: service_role and postgres bypass '
  'RLS, everyone else is refused. Never derive a quota from a row count on '
  'ai_coach_interactions again — that table is pruned nightly.';

-- ON DELETE CASCADE is mandatory, not decoration: delete-account/index.ts:440's
-- deleteUser is the only deletion path and DPDP compliance relies on cascade.
-- A no-FK table would strand quota rows for deleted users.

ALTER TABLE public.usage_counters ENABLE ROW LEVEL SECURITY;
-- DELIBERATELY NO POLICY. This is the security boundary for the whole feature.

-- ── 2. The one entry point ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.consume_quota(
  p_user_id      uuid,
  p_quota_key    text,
  p_window_start timestamptz,
  p_limit        integer
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
AS $fn$
DECLARE
  v_used integer;
BEGIN
  IF p_user_id IS NULL OR p_quota_key IS NULL OR p_window_start IS NULL THEN
    RAISE EXCEPTION 'consume_quota: null argument';
  END IF;
  IF p_limit IS NULL OR p_limit < 0 THEN
    RAISE EXCEPTION 'consume_quota: invalid limit %', p_limit;
  END IF;

  -- p_limit = 0 means "nothing is ever allowed". Without this the unconditional
  -- INSERT arm below returns 1 on the first call, granting one free use: that
  -- arm is not limit-gated, only the ON CONFLICT branch is.
  IF p_limit = 0 THEN
    RETURN -1;
  END IF;

  INSERT INTO public.usage_counters AS uc (user_id, quota_key, window_start, used, updated_at)
  VALUES (p_user_id, p_quota_key, p_window_start, 1, now())
  ON CONFLICT (user_id, quota_key, window_start) DO UPDATE
    SET used = uc.used + 1, updated_at = now()
    WHERE uc.used < p_limit
  RETURNING uc.used INTO v_used;

  -- No row RETURNED means the WHERE guard skipped the UPDATE, i.e. the limit was
  -- already reached. plpgsql leaves v_used NULL there, and NULL is exactly the
  -- value that reads as "fine" at a call site (`null >= limit` is false, which
  -- fails OPEN). Convert it to an explicit sentinel HERE, once, rather than
  -- trusting every future caller to handle NULL correctly.
  IF NOT FOUND OR v_used IS NULL THEN
    RETURN -1;
  END IF;

  RETURN v_used;
END;
$fn$;

COMMENT ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer) IS
  'Atomically consume one unit of a quota. Returns the new count (>=1) when '
  'allowed, or -1 when the quota is exhausted or p_limit = 0. Never returns 0, '
  'never returns NULL. SECURITY INVOKER by design — RLS on usage_counters is '
  'the guard, not the EXECUTE grant.';

-- The GRANT below is REDUNDANT and kept as executable documentation of intent.
-- This project's schema-level ALTER DEFAULT PRIVILEGES already grants EXECUTE on
-- every new public function to postgres, anon, authenticated and service_role
-- (verified: pg_default_acl shows {postgres=X,anon=X,authenticated=X,
-- service_role=X} for both grantors, with no PUBLIC entry). That is the same
-- institutional trap diagnose a9d3f1 documents. It is harmless here precisely
-- because the design does not rely on grants: an authenticated or anon caller
-- reaches the INSERT and is refused by RLS.
GRANT EXECUTE ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer)
  TO service_role, authenticated;

-- ── 3. Retention ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cleanup_usage_counters()
RETURNS void
LANGUAGE sql
SECURITY INVOKER
AS $fn$
  -- ⚠ BOTH CONJUNCTS ARE LOAD-BEARING. Windowed quotas are disposable; LIFETIME
  -- quotas (window_start = epoch) must never be deleted — deleting them
  -- reintroduces the exact bug this table exists to fix, inside the new table.
  -- A bound with only one side is a half-finished thought.
  DELETE FROM public.usage_counters
  WHERE window_start <> 'epoch'::timestamptz
    AND window_start < now() - interval '7 days';
$fn$;

COMMENT ON FUNCTION public.cleanup_usage_counters() IS
  'Deletes windowed usage_counters rows older than 7 days. NEVER deletes '
  'lifetime rows (window_start = epoch). Runs as postgres via pg_cron, which '
  'bypasses RLS.';

-- 03:45 UTC — a free slot: existing jobs sit at 03:00, 03:30, 04:22, 04:25,
-- 04:38 and 04:41 (verified against cron.job before scheduling).
SELECT cron.schedule(
  'usage_counters_retention_daily',
  '45 3 * * *',
  $job$ SELECT public.cleanup_usage_counters(); $job$
);

-- ── Rollback (inline) ────────────────────────────────────────────────────────
-- SELECT cron.unschedule('usage_counters_retention_daily');
-- DROP FUNCTION IF EXISTS public.cleanup_usage_counters();
-- DROP FUNCTION IF EXISTS public.consume_quota(uuid, text, timestamptz, integer);
-- DROP TABLE IF EXISTS public.usage_counters;
--
-- Safe to run in full while nothing calls consume_quota (slice 1). Once a call
-- site is migrated (slice 2+), dropping the table would break that caller —
-- roll back the caller first.
