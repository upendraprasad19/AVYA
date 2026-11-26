-- Intent: Let the cloud remember the CALENDAR WEEK a user's weekly streak last counted (user_progress.last_counted_week_key,
--   the Monday as days since 1970-01-01, the same number the client's calendarWeekKey produces), so a reinstall or a second
--   device no longer counts the current week a second time. A calendar-week key only moves forward, so the server rule is
--   plain GREATEST, in its own tiny SECURITY DEFINER function raise_streak_week_marker(uuid, integer). The hot RPC
--   update_user_progress_snapshot is NOT touched (no new parameter, no DROP, no ACL reset).
-- Destructive?: no   -- ADD COLUMN IF NOT EXISTS (nullable, no default: metadata only) + a NEW function; nothing is dropped or rewritten.
-- Rollback strategy: inline   -- reverse block at end of file (DROP FUNCTION; the column drop is commented and flagged
--   destructive because it destroys the stored markers). An APPLIED migration file is immutable, so a rollback is a NEW
--   minted migration number.
-- Linked diagnose-doc: a3c8f1

-- The file is IDEMPOTENT (ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE FUNCTION, REVOKE/GRANT), so a partial apply
-- converges on a re-run. Whether apply_migration wraps the file in a transaction is unverified (migration 152 hit this):
-- plain SET, not SET LOCAL, and a closing RESET.
SET lock_timeout = '3s';

ALTER TABLE public.user_progress ADD COLUMN IF NOT EXISTS last_counted_week_key integer;

-- IF NOT EXISTS skips silently when a column of that name already exists with another type: assert the type.
DO $assert_col$
DECLARE
  v_type text;
BEGIN
  SELECT data_type INTO v_type
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'user_progress' AND column_name = 'last_counted_week_key';
  IF v_type IS DISTINCT FROM 'integer' THEN
    RAISE EXCEPTION 'user_progress.last_counted_week_key missing or not integer: %', v_type;
  END IF;
END
$assert_col$;

CREATE OR REPLACE FUNCTION public.raise_streak_week_marker(
  p_user_id uuid,
  p_week_key integer
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_key integer := p_week_key;
  v_today date;
  v_monday integer;
  v_out integer;
BEGIN
  -- Security (the C1 guard, verbatim): an authenticated caller may only write its OWN progress.
  -- service_role / cron (auth.uid() IS NULL) pass through.
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id must not be null';
  END IF;
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'cross-account progress write blocked (caller % != target %)',
      auth.uid(), p_user_id;
  END IF;

  -- A NULL or negative key (the client sentinel is -1) is a no-op that returns the stored value. The early RETURN is
  -- load-bearing: LEAST(NULL, x) is x (migration 156 documents the same trap), so without it a NULL or -1 would become the
  -- Monday below and be STORED. The clamp comes strictly AFTER this block.
  IF v_key IS NOT NULL AND v_key < 0 THEN
    v_key := NULL;
  END IF;
  IF v_key IS NULL THEN
    SELECT last_counted_week_key INTO v_out
      FROM public.user_progress
      WHERE user_id = p_user_id;
    RETURN v_out;
  END IF;

  -- Clamp to THIS IST week's Monday (days since 1970-01-01), the largest value a correct client can hold. A device with a
  -- clock ahead cannot store a future week (which would equal a real future key and block it from counting).
  v_today := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_monday := (v_today - (EXTRACT(ISODOW FROM v_today)::int - 1)) - DATE '1970-01-01';
  v_key := LEAST(v_key, v_monday);

  -- GREATEST, written as a conditional UPDATE so an unchanged marker issues NO row write. Deliberately does NOT touch
  -- updated_at and does NOT bump streak_progress_version: the write is idempotent and monotonic (no optimistic lock needed)
  -- and a bump would make another device's next snapshot push see a stale version and retry.
  UPDATE public.user_progress
     SET last_counted_week_key = v_key
   WHERE user_id = p_user_id
     AND (last_counted_week_key IS NULL OR last_counted_week_key < v_key)
  RETURNING last_counted_week_key INTO v_out;

  IF NOT FOUND THEN
    -- Equal / lower key (nothing written), or no row yet (returns NULL; the snapshot RPC creates the row).
    SELECT last_counted_week_key INTO v_out
      FROM public.user_progress
      WHERE user_id = p_user_id;
  END IF;
  RETURN v_out;
END;
$function$;

-- A brand-new public function inherits the project's default privileges to anon (bug class 2.32): name every role.
REVOKE ALL ON FUNCTION public.raise_streak_week_marker(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.raise_streak_week_marker(uuid, integer) TO authenticated, service_role;

COMMENT ON FUNCTION public.raise_streak_week_marker(uuid, integer) IS
  'Raises user_progress.last_counted_week_key to the given calendar-week key (GREATEST, clamped to this IST week''s Monday); NULL/negative is a no-op. Own-account only. Diagnose a3c8f1.';

-- Closing assertions: exactly ONE function of that name, 2 arguments, no defaults, integer result, SECURITY DEFINER,
-- search_path, the exact EXECUTE grantee SET (aclexplode, not text), and no anon EXECUTE.
DO $assert_fn$
DECLARE
  v_count integer;
  v_grantees text[];
  v_cfg text[];
  v_secdef boolean;
  v_nargs integer;
  v_ndefaults integer;
  v_rettype oid;
BEGIN
  SELECT count(*) INTO v_count
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'raise_streak_week_marker';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly one raise_streak_week_marker, found %', v_count;
  END IF;

  SELECT array_agg(g ORDER BY g) INTO v_grantees FROM (
    SELECT DISTINCT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE r.rolname END AS g
      FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(p.proacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE p.oid = 'public.raise_streak_week_marker(uuid, integer)'::regprocedure
       AND a.privilege_type = 'EXECUTE'
  ) s;
  IF v_grantees IS DISTINCT FROM ARRAY['authenticated', 'postgres', 'service_role']::text[] THEN
    RAISE EXCEPTION 'unexpected EXECUTE grantees: %', v_grantees;
  END IF;

  IF has_function_privilege('anon', 'public.raise_streak_week_marker(uuid, integer)'::regprocedure, 'EXECUTE') THEN
    RAISE EXCEPTION 'anon must not have EXECUTE on raise_streak_week_marker';
  END IF;

  SELECT p.proconfig, p.prosecdef, p.pronargs, p.pronargdefaults, p.prorettype
    INTO v_cfg, v_secdef, v_nargs, v_ndefaults, v_rettype
    FROM pg_proc p
   WHERE p.oid = 'public.raise_streak_week_marker(uuid, integer)'::regprocedure;
  IF v_secdef IS NOT TRUE
     OR v_cfg IS DISTINCT FROM ARRAY['search_path=public']::text[]
     OR v_nargs <> 2
     OR v_ndefaults <> 0
     OR v_rettype <> 'integer'::regtype THEN
    RAISE EXCEPTION 'SECURITY DEFINER / search_path / arity / defaults / return type not as designed: % / % / % / % / %',
      v_secdef, v_cfg, v_nargs, v_ndefaults, v_rettype;
  END IF;
END
$assert_fn$;

RESET lock_timeout;

-- ROLLBACK (inline, commented, LITERAL). A rollback is a NEW minted migration number. Run it inside your OWN transaction.
--
-- DROP FUNCTION public.raise_streak_week_marker(uuid, integer);
--
-- DESTRUCTIVE (destroys every stored marker; a client then re-counts one week per reinstall until it is re-added):
-- ALTER TABLE public.user_progress DROP COLUMN last_counted_week_key;
