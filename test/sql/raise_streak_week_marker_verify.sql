-- test/sql/raise_streak_week_marker_verify.sql
--
-- Slice C2 (diagnose a3c8f1) — live-Postgres verification of the week-marker
-- function raise_streak_week_marker(uuid, integer) and its column
-- user_progress.last_counted_week_key. Same method as
-- cross_device_progress_optimistic_lock_verify.sql: one transaction that
-- applies the migration's own SQL (so it is verified BEFORE it is applied for
-- real) and ROLLBACKs. Run via:
--
--   dart run scripts/check_onconflict_live_arbiter.dart \
--       --sql test/sql/raise_streak_week_marker_verify.sql
--
-- The function text between the markers below is kept byte-identical to the
-- migration's by test/contracts/streak_week_marker_migration_text_test.dart.
--
-- closes-diagnose: a3c8f1

BEGIN;

CREATE TEMP TABLE _v_results (
  label    text PRIMARY KEY,
  status   text NOT NULL,        -- 'ok' | 'fail'
  sqlstate text,
  msg      text
) ON COMMIT DROP;

ALTER TABLE public.user_progress ADD COLUMN IF NOT EXISTS last_counted_week_key integer;

-- BEGIN-FUNCTION
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
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id must not be null';
  END IF;
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'cross-account progress write blocked (caller % != target %)',
      auth.uid(), p_user_id;
  END IF;

  IF v_key IS NOT NULL AND v_key < 0 THEN
    v_key := NULL;
  END IF;
  IF v_key IS NULL THEN
    SELECT last_counted_week_key INTO v_out
      FROM public.user_progress
      WHERE user_id = p_user_id;
    RETURN v_out;
  END IF;

  v_today := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_monday := (v_today - (EXTRACT(ISODOW FROM v_today)::int - 1)) - DATE '1970-01-01';
  v_key := LEAST(v_key, v_monday);

  UPDATE public.user_progress
     SET last_counted_week_key = v_key
   WHERE user_id = p_user_id
     AND (last_counted_week_key IS NULL OR last_counted_week_key < v_key)
  RETURNING last_counted_week_key INTO v_out;

  IF NOT FOUND THEN
    SELECT last_counted_week_key INTO v_out
      FROM public.user_progress
      WHERE user_id = p_user_id;
  END IF;
  RETURN v_out;
END;
$function$;
-- END-FUNCTION

REVOKE ALL ON FUNCTION public.raise_streak_week_marker(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.raise_streak_week_marker(uuid, integer) TO authenticated, service_role;

-- A row-write counter: lets "no write" be asserted (xmin cannot tell, the
-- seed rows are created in this same transaction).
CREATE TEMP TABLE _v_writes (n integer NOT NULL);
INSERT INTO _v_writes VALUES (0);
CREATE OR REPLACE FUNCTION public._v_count_progress_writes() RETURNS trigger
LANGUAGE plpgsql AS $t$
BEGIN
  UPDATE _v_writes SET n = n + 1;
  RETURN NEW;
END;
$t$;
CREATE TRIGGER _v_count_progress_writes BEFORE UPDATE ON public.user_progress
  FOR EACH ROW EXECUTE FUNCTION public._v_count_progress_writes();

DO $outer$
DECLARE
  v_user_a  uuid := '00000000-0000-0000-0000-0000003c0001'::uuid;
  v_user_b  uuid := '00000000-0000-0000-0000-0000003c0002'::uuid;
  v_user_c  uuid := '00000000-0000-0000-0000-0000003c0003'::uuid;  -- never gets a progress row
  v_now     timestamptz := now();
  v_out     integer;
  v_w0      integer;
  v_w1      integer;
  v_today   date := (now() AT TIME ZONE 'Asia/Kolkata')::date;
  v_monday  integer := ((now() AT TIME ZONE 'Asia/Kolkata')::date
                        - (EXTRACT(ISODOW FROM (now() AT TIME ZONE 'Asia/Kolkata')::date)::int - 1))
                        - DATE '1970-01-01';
  v_ver     bigint;
  v_ver2    bigint;
  v_upd     timestamptz;
  v_upd2    timestamptz;
  v_def     text;
BEGIN
  BEGIN
    INSERT INTO auth.users (id, email, created_at) VALUES
      (v_user_a, 'test+3c-a@avya.local', v_now),
      (v_user_b, 'test+3c-b@avya.local', v_now),
      (v_user_c, 'test+3c-c@avya.local', v_now)
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    INSERT INTO public.users (id, email, full_name) VALUES
      (v_user_a, 'test+3c-a@avya.local', 'c2 a'),
      (v_user_b, 'test+3c-b@avya.local', 'c2 b'),
      (v_user_c, 'test+3c-c@avya.local', 'c2 c')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  -- The seeding above swallows errors on purpose (a re-run finds the rows); assert the rows are really there, so a
  -- silently failed seed cannot turn every case below into a vacuous pass.
  IF (SELECT count(*) FROM public.users WHERE id IN (v_user_a, v_user_b, v_user_c)) <> 3 THEN
    RAISE EXCEPTION 'seed failed: public.users rows = %',
      (SELECT count(*) FROM public.users WHERE id IN (v_user_a, v_user_b, v_user_c));
  END IF;
  DELETE FROM public.user_progress WHERE user_id IN (v_user_a, v_user_b, v_user_c);
  PERFORM public.update_user_progress_snapshot(
    v_user_a, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
  PERFORM public.update_user_progress_snapshot(
    v_user_b, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

  -- Case 1 — a valid key against a NULL stored marker is stored.
  BEGIN
    v_out := public.raise_streak_week_marker(v_user_a, v_monday - 14);
    IF v_out = v_monday - 14 AND EXISTS (
      SELECT 1 FROM public.user_progress WHERE user_id = v_user_a AND last_counted_week_key = v_monday - 14) THEN
      INSERT INTO _v_results VALUES ('c2_higher_stored', 'ok', NULL, 'stored ' || v_out);
    ELSE
      INSERT INTO _v_results VALUES ('c2_higher_stored', 'fail', NULL, 'got ' || COALESCE(v_out::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_higher_stored', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 2 — a higher key replaces it.
  BEGIN
    v_out := public.raise_streak_week_marker(v_user_a, v_monday - 7);
    INSERT INTO _v_results VALUES ('c2_raise_again',
      CASE WHEN v_out = v_monday - 7 THEN 'ok' ELSE 'fail' END, NULL, 'got ' || COALESCE(v_out::text, 'NULL'));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_raise_again', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 3 — a LOWER key is ignored AND issues no row write.
  BEGIN
    SELECT n INTO v_w0 FROM _v_writes;
    v_out := public.raise_streak_week_marker(v_user_a, v_monday - 21);
    SELECT n INTO v_w1 FROM _v_writes;
    INSERT INTO _v_results VALUES ('c2_lower_ignored_no_write',
      CASE WHEN v_out = v_monday - 7 AND v_w1 = v_w0 THEN 'ok' ELSE 'fail' END, NULL,
      'out=' || COALESCE(v_out::text, 'NULL') || ' writes ' || v_w0 || '->' || v_w1);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_lower_ignored_no_write', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 4 — an EQUAL key is a no-op (no write).
  BEGIN
    SELECT n INTO v_w0 FROM _v_writes;
    v_out := public.raise_streak_week_marker(v_user_a, v_monday - 7);
    SELECT n INTO v_w1 FROM _v_writes;
    INSERT INTO _v_results VALUES ('c2_equal_no_write',
      CASE WHEN v_out = v_monday - 7 AND v_w1 = v_w0 THEN 'ok' ELSE 'fail' END, NULL,
      'writes ' || v_w0 || '->' || v_w1);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_equal_no_write', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 5 — a NULL key is a no-op that returns the stored value.
  BEGIN
    SELECT n INTO v_w0 FROM _v_writes;
    v_out := public.raise_streak_week_marker(v_user_a, NULL);
    SELECT n INTO v_w1 FROM _v_writes;
    INSERT INTO _v_results VALUES ('c2_null_key_noop',
      CASE WHEN v_out = v_monday - 7 AND v_w1 = v_w0 THEN 'ok' ELSE 'fail' END, NULL,
      'out=' || COALESCE(v_out::text, 'NULL'));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_null_key_noop', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 6 — a NEGATIVE key (the client sentinel -1) against a NULL stored
  -- marker stores NOTHING. This is the vacuity trap: LEAST(NULL, x) is x, so
  -- without the early RETURN the Monday would be stored. user_b has NULL.
  BEGIN
    v_out := public.raise_streak_week_marker(v_user_b, -1);
    IF v_out IS NULL AND EXISTS (
      SELECT 1 FROM public.user_progress WHERE user_id = v_user_b AND last_counted_week_key IS NULL) THEN
      INSERT INTO _v_results VALUES ('c2_negative_key_stores_nothing', 'ok', NULL, 'stored value stayed NULL');
    ELSE
      INSERT INTO _v_results VALUES ('c2_negative_key_stores_nothing', 'fail', NULL,
        'a negative key was stored: ' || COALESCE(v_out::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_negative_key_stores_nothing', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 7 — a NULL key against a NULL stored marker stores nothing either.
  BEGIN
    v_out := public.raise_streak_week_marker(v_user_b, NULL);
    IF v_out IS NULL AND EXISTS (
      SELECT 1 FROM public.user_progress WHERE user_id = v_user_b AND last_counted_week_key IS NULL) THEN
      INSERT INTO _v_results VALUES ('c2_null_key_null_stored', 'ok', NULL, 'stayed NULL');
    ELSE
      INSERT INTO _v_results VALUES ('c2_null_key_null_stored', 'fail', NULL, 'stored ' || COALESCE(v_out::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_null_key_null_stored', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 8 — a far-future key is clamped to THIS IST week's Monday.
  BEGIN
    v_out := public.raise_streak_week_marker(v_user_b, 2000000);
    INSERT INTO _v_results VALUES ('c2_future_clamped_to_this_monday',
      CASE WHEN v_out = v_monday THEN 'ok' ELSE 'fail' END, NULL,
      'out=' || COALESCE(v_out::text, 'NULL') || ' monday=' || v_monday);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_future_clamped_to_this_monday', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 9 — the Monday clamp arithmetic, on FIXED dates (a Monday, a
  -- Wednesday, a Sunday), including "today is a Monday and key = today + 7
  -- must not become NEXT Monday" (the v5 +7 clamp failed exactly this).
  -- 2026-10-05 is a Monday; its key is 20731.
  BEGIN
    IF (SELECT bool_and(k = 20731) FROM (
          SELECT ((d - (EXTRACT(ISODOW FROM d)::int - 1)) - DATE '1970-01-01') AS k
            FROM (VALUES (DATE '2026-10-05'), (DATE '2026-10-07'), (DATE '2026-10-11')) AS t(d)) s)
       AND LEAST(20731 + 7, 20731) = 20731 THEN
      INSERT INTO _v_results VALUES ('c2_clamp_arithmetic_fixed_dates', 'ok', NULL,
        'Mon/Wed/Sun of the week of 2026-10-05 all give 20731; today+7 clamps to this Monday');
    ELSE
      INSERT INTO _v_results VALUES ('c2_clamp_arithmetic_fixed_dates', 'fail', NULL, 'clamp arithmetic wrong');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_clamp_arithmetic_fixed_dates', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 10 — the deployed function body contains the pinned clamp expression
  -- and the RETURN textually precedes LEAST (the body cannot drift from the
  -- tested expression above).
  BEGIN
    -- pg_get_functiondef returns the body VERBATIM including comments, and the migration's comments mention LEAST(:
    -- strip `--` comments first so the position check is made on code only (B-pass P2-1).
    v_def := regexp_replace(
      pg_get_functiondef('public.raise_streak_week_marker(uuid, integer)'::regprocedure),
      E'--[^\n]*', '', 'g');
    IF position('(v_today - (EXTRACT(ISODOW FROM v_today)::int - 1)) - DATE ''1970-01-01''' IN v_def) > 0
       AND position('RETURN v_out' IN v_def) < position('LEAST(' IN v_def) THEN
      INSERT INTO _v_results VALUES ('c2_body_has_pinned_clamp_and_early_return', 'ok', NULL, 'pinned');
    ELSE
      INSERT INTO _v_results VALUES ('c2_body_has_pinned_clamp_and_early_return', 'fail', NULL, 'body drifted');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_body_has_pinned_clamp_and_early_return', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 11 — no progress row yet returns NULL and creates nothing.
  BEGIN
    v_out := public.raise_streak_week_marker(v_user_c, v_monday);
    IF v_out IS NULL AND NOT EXISTS (SELECT 1 FROM public.user_progress WHERE user_id = v_user_c) THEN
      INSERT INTO _v_results VALUES ('c2_no_row_returns_null_creates_nothing', 'ok', NULL, 'no row');
    ELSE
      INSERT INTO _v_results VALUES ('c2_no_row_returns_null_creates_nothing', 'fail', NULL,
        'out=' || COALESCE(v_out::text, 'NULL'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_no_row_returns_null_creates_nothing', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 12 — streak_progress_version and updated_at are untouched by a raise.
  BEGIN
    SELECT streak_progress_version, updated_at INTO v_ver, v_upd FROM public.user_progress WHERE user_id = v_user_a;
    PERFORM public.raise_streak_week_marker(v_user_a, v_monday);
    SELECT streak_progress_version, updated_at INTO v_ver2, v_upd2 FROM public.user_progress WHERE user_id = v_user_a;
    INSERT INTO _v_results VALUES ('c2_version_and_updated_at_untouched',
      CASE WHEN v_ver = v_ver2 AND v_upd = v_upd2 THEN 'ok' ELSE 'fail' END, NULL,
      'version ' || v_ver || '->' || v_ver2);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_version_and_updated_at_untouched', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 13 — grants: anon has no EXECUTE; authenticated and service_role do.
  BEGIN
    IF NOT has_function_privilege('anon', 'public.raise_streak_week_marker(uuid, integer)'::regprocedure, 'EXECUTE')
       AND has_function_privilege('authenticated', 'public.raise_streak_week_marker(uuid, integer)'::regprocedure, 'EXECUTE')
       AND has_function_privilege('service_role', 'public.raise_streak_week_marker(uuid, integer)'::regprocedure, 'EXECUTE') THEN
      INSERT INTO _v_results VALUES ('c2_acl_anon_revoked', 'ok', NULL, 'anon none; authenticated + service_role yes');
    ELSE
      INSERT INTO _v_results VALUES ('c2_acl_anon_revoked', 'fail', NULL, 'unexpected EXECUTE grants');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_acl_anon_revoked', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 13b — the EXACT grantee set the migration's closing assertion pins (aclexplode, not has_function_privilege),
  -- and the role this channel runs as (informational: the closing assertion assumes the owner role is postgres).
  BEGIN
    IF (SELECT array_agg(g::text ORDER BY g) FROM (
          SELECT DISTINCT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE r.rolname END AS g
            FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a LEFT JOIN pg_roles r ON r.oid = a.grantee
           WHERE p.oid = 'public.raise_streak_week_marker(uuid, integer)'::regprocedure AND a.privilege_type = 'EXECUTE') s)
       = ARRAY['authenticated', 'postgres', 'service_role']::text[] THEN
      INSERT INTO _v_results VALUES ('c2_exact_grantee_set', 'ok', NULL, 'run as ' || current_user);
    ELSE
      INSERT INTO _v_results VALUES ('c2_exact_grantee_set', 'fail', NULL, 'grantee set differs; run as ' || current_user);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO _v_results VALUES ('c2_exact_grantee_set', 'fail', SQLSTATE, SQLERRM);
  END;

  -- Case 14 — the cross-account guard raises. Last: it sets a JWT claim.
  BEGIN
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', v_user_b::text, 'role', 'authenticated')::text, true);
    BEGIN
      v_out := public.raise_streak_week_marker(v_user_a, v_monday);
      INSERT INTO _v_results VALUES ('c2_cross_account_blocked', 'fail', NULL, 'a cross-account write was NOT blocked');
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'cross-account progress write blocked%' THEN
        INSERT INTO _v_results VALUES ('c2_cross_account_blocked', 'ok', NULL, SQLERRM);
      ELSE
        INSERT INTO _v_results VALUES ('c2_cross_account_blocked', 'fail', SQLSTATE, SQLERRM);
      END IF;
    END;
    PERFORM set_config('request.jwt.claims', '', true);
  END;
END;
$outer$;

SELECT label, status, sqlstate, msg FROM _v_results ORDER BY label;

ROLLBACK;
