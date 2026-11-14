-- test/sql/cleanup_cron_call_log_per_function_verify.sql
--
-- Behavioural pin for migration 172 (OI-199 + OI-471, diagnose b3e7d2): public.cleanup_cron_call_log() keeps, for EVERY
-- function_name, its newest success row and its newest row of any status, prunes everything else older than 10 days, and
-- public.cron_call_log_cleanup_7d() is gone.
--
-- WHERE TO RUN IT. ONLY in the LOCAL scratch Postgres that test/sql/cleanup_cron_call_log_per_function_local.sh builds
-- (docker image public.ecr.aws/supabase/postgres:17.6.1.084, minimal cron_call_log + alerts tables, the REAL migration files
-- applied). It EMPTIES public.cron_call_log, so it must never be sent to the live project (CLAUDE.md section 4.3; a first
-- production rehearsal of OI-473 hung for over an hour). The harness also provides public._alert_cmd(t text) holding the
-- command of alert_cron_function_dead taken from migration 170 between its two $$ tags (case J runs it).
--
-- BEGIN ... ROLLBACK, results in a temp table. now() is frozen inside the transaction, so every seed is back-dated from v_now.
-- Case labels start with the case letter; the harness reads the red labels per letter.
--   A  retention boundary, ONE function name for every row (strict cut at exactly 10 days)
--   B  one dead function beside a healthy one (with ONE function the 169 keep-set equals the new one)
--   C  two silent functions
--   D  a function with no success at all beside a healthy one
--   E  recent rows untouched      F  empty table      F2  tie on started_at      G  a second run deletes nothing
--   H  every row the 169 keep-set kept survives (the fixture has no global tie, so the ids agree) + exactness against an
--      independent row_number() oracle, with ties and pinned statuses
--   H2 a dead fleet: the rows the 169 keep-set kept are OLD here (in H they are inside the retention window, so that half of H
--      is satisfiable by any keep-set); plus exactness against the oracle
--   I  the orphan pruner is gone
--   K  the function's security envelope: SECURITY DEFINER, search_path pinned to public, no PUBLIC / anon / authenticated EXECUTE
--   J  alert_cron_function_dead over 9 simulated nights: a dead function pages twice (never three times), nothing past 14 days
--
-- closes-diagnose: b3e7d2

BEGIN;

-- Local-only guard: public._alert_cmd exists only in the harness scaffold. On any other database this file would empty
-- cron_call_log (case A) and delete alerts (case J), so it refuses to continue there.
DO $g$
BEGIN
  IF to_regclass('public._alert_cmd') IS NULL THEN
    RAISE EXCEPTION 'local harness only: public._alert_cmd is missing; never run this file on the live project';
  END IF;
END
$g$;

CREATE TEMP TABLE _v_results (
  label  text PRIMARY KEY,
  status text NOT NULL,        -- 'ok' | 'fail'
  msg    text
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.rec(p_label text, p_ok boolean, p_msg text) RETURNS void
LANGUAGE sql AS $r$
  INSERT INTO _v_results VALUES (p_label, CASE WHEN p_ok THEN 'ok' ELSE 'fail' END, p_msg);
$r$;

-- ---------------------------------------------------------------- A
DO $a$
DECLARE
  v_now timestamptz := now();
  n int;
BEGIN
  DELETE FROM public.cron_call_log;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_a', 'success', v_now - interval '1 hour'),
    ('v_a', 'success', v_now - interval '9 days'),
    ('v_a', 'success', v_now - interval '10 days'),
    ('v_a', 'success', v_now - interval '10 days 1 minute'),
    ('v_a', 'success', v_now - interval '11 days'),
    ('v_a', 'failed',  v_now - interval '12 days');
  PERFORM public.cleanup_cron_call_log();

  SELECT count(*) INTO n FROM public.cron_call_log WHERE started_at = v_now - interval '1 hour';
  PERFORM pg_temp.rec('A_1h_kept', n = 1, format('1 h row count = %s (expect 1)', n));
  SELECT count(*) INTO n FROM public.cron_call_log WHERE started_at = v_now - interval '9 days';
  PERFORM pg_temp.rec('A_9d_kept', n = 1, format('9 d row count = %s (expect 1; a 7-day cut gives 0)', n));
  SELECT count(*) INTO n FROM public.cron_call_log WHERE started_at = v_now - interval '10 days';
  PERFORM pg_temp.rec('A_10d_exact_kept', n = 1, format('exactly-10-d row count = %s (expect 1: the cut is a strict <)', n));
  SELECT count(*) INTO n FROM public.cron_call_log WHERE started_at = v_now - interval '10 days 1 minute';
  PERFORM pg_temp.rec('A_10d_1min_pruned', n = 0, format('10 d 1 min row count = %s (expect 0)', n));
  SELECT count(*) INTO n FROM public.cron_call_log WHERE started_at = v_now - interval '11 days';
  PERFORM pg_temp.rec('A_11d_pruned', n = 0, format('11 d row count = %s (expect 0)', n));
  SELECT count(*) INTO n FROM public.cron_call_log WHERE started_at = v_now - interval '12 days';
  PERFORM pg_temp.rec('A_12d_failed_pruned', n = 0, format('12 d failed row count = %s (expect 0)', n));
END
$a$;

-- ---------------------------------------------------------------- B
DO $b$
DECLARE
  v_now timestamptz := now();
  n int;
BEGIN
  DELETE FROM public.cron_call_log;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_b_dead',    'success', v_now - interval '41 days'),
    ('v_b_dead',    'success', v_now - interval '40 days'),
    ('v_b_dead',    'success', v_now - interval '30 days'),
    ('v_b_dead',    'failed',  v_now - interval '29 days'),
    ('v_b_healthy', 'success', v_now - interval '1 hour');
  PERFORM public.cleanup_cron_call_log();

  SELECT count(*) INTO n FROM public.cron_call_log WHERE function_name = 'v_b_dead';
  PERFORM pg_temp.rec('B_dead_keeps_exactly_two', n = 2, format('dead function rows after cleanup = %s (expect 2)', n));
  SELECT count(*) INTO n FROM public.cron_call_log
    WHERE function_name = 'v_b_dead' AND status = 'success' AND started_at = v_now - interval '30 days';
  PERFORM pg_temp.rec('B_dead_newest_success_kept', n = 1, format('newest success (30 d) count = %s (expect 1)', n));
  SELECT count(*) INTO n FROM public.cron_call_log
    WHERE function_name = 'v_b_dead' AND status = 'failed' AND started_at = v_now - interval '29 days';
  PERFORM pg_temp.rec('B_dead_newest_row_kept', n = 1, format('newest row (failed, 29 d) count = %s (expect 1)', n));
  SELECT count(*) INTO n FROM public.cron_call_log WHERE function_name = 'v_b_healthy';
  PERFORM pg_temp.rec('B_healthy_untouched', n = 1, format('healthy rows = %s (expect 1)', n));
END
$b$;

-- ---------------------------------------------------------------- C
DO $c$
DECLARE
  v_now timestamptz := now();
  n1 int; n2 int;
BEGIN
  DELETE FROM public.cron_call_log;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_c1', 'success', v_now - interval '35 days'),
    ('v_c1', 'success', v_now - interval '33 days'),
    ('v_c1', 'success', v_now - interval '30 days'),
    ('v_c2', 'success', v_now - interval '28 days'),
    ('v_c2', 'success', v_now - interval '26 days'),
    ('v_c2', 'success', v_now - interval '25 days');
  PERFORM public.cleanup_cron_call_log();

  SELECT count(*) INTO n1 FROM public.cron_call_log WHERE function_name = 'v_c1' AND started_at = v_now - interval '30 days';
  SELECT count(*) INTO n2 FROM public.cron_call_log WHERE function_name = 'v_c2' AND started_at = v_now - interval '25 days';
  PERFORM pg_temp.rec('C_each_silent_function_keeps_its_newest', n1 = 1 AND n2 = 1,
    format('c1 newest success count = %s, c2 newest success count = %s (expect 1 and 1; a global keep-set gives 0 and 1)', n1, n2));
  SELECT count(*) INTO n1 FROM public.cron_call_log;
  PERFORM pg_temp.rec('C_nothing_else_kept', n1 = 2, format('total rows = %s (expect 2)', n1));
END
$c$;

-- ---------------------------------------------------------------- D
DO $d$
DECLARE
  v_now timestamptz := now();
  n int;
BEGIN
  DELETE FROM public.cron_call_log;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_d_nosuccess', 'failed',  v_now - interval '20 days'),
    ('v_d_nosuccess', 'started', v_now - interval '19 days'),
    ('v_d_nosuccess', 'failed',  v_now - interval '18 days'),
    ('v_d_healthy',   'success', v_now - interval '1 hour');
  PERFORM public.cleanup_cron_call_log();

  SELECT count(*) INTO n FROM public.cron_call_log WHERE function_name = 'v_d_nosuccess' AND started_at = v_now - interval '18 days';
  PERFORM pg_temp.rec('D_no_success_function_keeps_newest_row', n = 1, format('newest row of a never-succeeded function count = %s (expect 1)', n));
  SELECT count(*) INTO n FROM public.cron_call_log WHERE function_name = 'v_d_nosuccess';
  PERFORM pg_temp.rec('D_no_success_function_keeps_only_it', n = 1, format('rows of that function = %s (expect 1)', n));
END
$d$;

-- ---------------------------------------------------------------- E, F, F2, G
DO $e$
DECLARE
  v_now timestamptz := now();
  n_before int; n_after int; v_survivor bigint; v_max bigint; v_ok boolean; v_msg text;
BEGIN
  -- E: recent rows, mixed status, all inside 10 days
  DELETE FROM public.cron_call_log;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_e', 'success', v_now - interval '1 hour'),
    ('v_e', 'failed',  v_now - interval '2 days'),
    ('v_e', 'started', v_now - interval '3 days'),
    ('v_e', 'success', v_now - interval '5 days'),
    ('v_e', 'failed',  v_now - interval '9 days');
  SELECT count(*) INTO n_before FROM public.cron_call_log;
  PERFORM public.cleanup_cron_call_log();
  SELECT count(*) INTO n_after FROM public.cron_call_log;
  PERFORM pg_temp.rec('E_recent_rows_untouched', n_before = 5 AND n_after = 5, format('rows before %s, after %s (expect 5 and 5)', n_before, n_after));

  -- G: a second run deletes nothing
  PERFORM public.cleanup_cron_call_log();
  SELECT count(*) INTO n_after FROM public.cron_call_log;
  PERFORM pg_temp.rec('G_second_run_deletes_nothing', n_after = 5, format('rows after the second run = %s (expect 5)', n_after));

  -- F: empty table, no error
  DELETE FROM public.cron_call_log;
  v_ok := true; v_msg := 'no error';
  BEGIN
    PERFORM public.cleanup_cron_call_log();
  EXCEPTION WHEN OTHERS THEN
    v_ok := false; v_msg := SQLERRM;
  END;
  SELECT count(*) INTO n_after FROM public.cron_call_log;
  PERFORM pg_temp.rec('F_empty_table_no_error', v_ok AND n_after = 0, format('%s; rows = %s', v_msg, n_after));

  -- F2: a tie on started_at that IS the function's newest success and newest row: exactly one survives, the higher id
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_t', 'success', v_now - interval '30 days'),
    ('v_t', 'success', v_now - interval '30 days'),
    ('v_t_healthy', 'success', v_now - interval '1 hour');
  SELECT max(id) INTO v_max FROM public.cron_call_log WHERE function_name = 'v_t';
  PERFORM public.cleanup_cron_call_log();
  SELECT count(*), min(id) INTO n_after, v_survivor FROM public.cron_call_log WHERE function_name = 'v_t';
  PERFORM pg_temp.rec('F2_tie_keeps_one_the_higher_id', n_after = 1 AND v_survivor = v_max,
    format('tied rows left = %s, survivor id %s, higher id %s (expect 1 and equal)', n_after, v_survivor, v_max));
END
$e$;

-- ---------------------------------------------------------------- H
DO $h$
DECLARE
  v_now timestamptz := now();
  n_missing int; n_extra int; n_oldkeep_lost int; n_fixture int;
BEGIN
  DELETE FROM public.cron_call_log;
  -- f1 healthy: a success every day for 21 days, plus failed rows between
  INSERT INTO public.cron_call_log (function_name, status, started_at)
    SELECT 'v_h1', 'success', v_now - (g || ' days')::interval FROM generate_series(0, 20) g;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_h1', 'failed', v_now - interval '3 days 12 hours'), ('v_h1', 'failed', v_now - interval '15 days 12 hours');
  -- f2 dead, newest row is FAILED and newer than its newest success
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_h2', 'success', v_now - interval '12 days'), ('v_h2', 'success', v_now - interval '14 days'),
    ('v_h2', 'success', v_now - interval '20 days'), ('v_h2', 'success', v_now - interval '30 days'),
    ('v_h2', 'success', v_now - interval '45 days'), ('v_h2', 'failed', v_now - interval '11 days'),
    ('v_h2', 'failed', v_now - interval '13 days');
  -- f3 never succeeded
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_h3', 'failed', v_now - interval '15 days'), ('v_h3', 'failed', v_now - interval '17 days'),
    ('v_h3', 'failed', v_now - interval '20 days'), ('v_h3', 'started', v_now - interval '16 days');
  -- f4 newest row is STARTED (younger than its newest success)
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_h4', 'started', v_now - interval '2 hours'), ('v_h4', 'success', v_now - interval '1 day'),
    ('v_h4', 'success', v_now - interval '2 days'), ('v_h4', 'success', v_now - interval '12 days'),
    ('v_h4', 'success', v_now - interval '15 days');
  -- f5 TIES on started_at (two successes and a success + failed at 40 days)
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_h5', 'success', v_now - interval '25 days'), ('v_h5', 'success', v_now - interval '25 days'),
    ('v_h5', 'success', v_now - interval '40 days'), ('v_h5', 'failed',  v_now - interval '40 days');
  -- f6 a single old row
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_h6', 'success', v_now - interval '60 days');
  -- f7 newest row is STARTED and OLDER than the cut: only the keep-set can save it (v_h4's started row is 2 h old, so
  -- retention keeps it whatever the keep-set does; the first harness run let a `status <> 'started'` mutant survive on that)
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_h7', 'success', v_now - interval '20 days'), ('v_h7', 'success', v_now - interval '22 days'),
    ('v_h7', 'started', v_now - interval '15 days');
  SELECT count(*) INTO n_fixture FROM public.cron_call_log;

  -- the 169 keep-set (global newest success + global newest row), captured BEFORE the run, written exactly as in 169
  -- (no id tie-break: this fixture has no global tie, so the pick is deterministic)
  CREATE TEMP TABLE _old_keep ON COMMIT DROP AS
    SELECT id FROM (
      (SELECT id FROM public.cron_call_log
        WHERE status = 'success' ORDER BY started_at DESC LIMIT 1)
      UNION
      (SELECT id FROM public.cron_call_log
        ORDER BY started_at DESC LIMIT 1)
    ) k;
  -- the expected survivors, from a different formulation (row_number), BEFORE the run
  CREATE TEMP TABLE _expected ON COMMIT DROP AS
    SELECT id FROM public.cron_call_log WHERE started_at >= v_now - interval '10 days'
    UNION
    SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY function_name ORDER BY started_at DESC, id DESC) rn
                    FROM public.cron_call_log) a WHERE rn = 1
    UNION
    SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY function_name ORDER BY started_at DESC, id DESC) rn
                    FROM public.cron_call_log WHERE status = 'success') b WHERE rn = 1;

  PERFORM public.cleanup_cron_call_log();

  SELECT count(*) INTO n_oldkeep_lost FROM _old_keep o WHERE o.id NOT IN (SELECT id FROM public.cron_call_log);
  PERFORM pg_temp.rec('H_old_keep_set_is_subset_of_survivors', n_oldkeep_lost = 0,
    format('169 keep-set rows lost = %s (expect 0)', n_oldkeep_lost));
  SELECT count(*) INTO n_missing FROM _expected e WHERE e.id NOT IN (SELECT id FROM public.cron_call_log);
  SELECT count(*) INTO n_extra FROM public.cron_call_log c WHERE c.id NOT IN (SELECT id FROM _expected);
  PERFORM pg_temp.rec('H_survivors_equal_oracle', n_missing = 0 AND n_extra = 0,
    format('fixture rows %s; expected-but-deleted %s, kept-but-not-expected %s (expect 0 and 0)', n_fixture, n_missing, n_extra));
  -- statuses are pinned: the fixture really holds a started-newest function and a failed-newest-over-older-success one
  PERFORM pg_temp.rec('H_fixture_pins_started_and_failed_newest',
    EXISTS (SELECT 1 FROM public.cron_call_log WHERE function_name = 'v_h4' AND status = 'started' AND started_at = v_now - interval '2 hours')
    AND EXISTS (SELECT 1 FROM public.cron_call_log WHERE function_name = 'v_h2' AND status = 'failed' AND started_at = v_now - interval '11 days')
    AND EXISTS (SELECT 1 FROM public.cron_call_log WHERE function_name = 'v_h2' AND status = 'success' AND started_at = v_now - interval '12 days')
    AND EXISTS (SELECT 1 FROM public.cron_call_log WHERE function_name = 'v_h7' AND status = 'started' AND started_at = v_now - interval '15 days')
    AND EXISTS (SELECT 1 FROM public.cron_call_log WHERE function_name = 'v_h7' AND status = 'success' AND started_at = v_now - interval '20 days'),
    'v_h7 newest row (started, 15 d, older than the cut) and its newest success (20 d), v_h2 newest row (failed, 11 d) over its newest success (12 d) all survived');
END
$h$;

-- ---------------------------------------------------------------- H2
-- H cannot prove "every row the 169 keep-set kept survives": its global newest rows belong to v_h1, a healthy function whose
-- rows are 0 to 1 days old, so retention keeps them whatever the keep-set does. H2 is a DEAD FLEET: nothing is younger than 11
-- days, so the two rows the 169 keep-set kept (the newest success, v_k2 at 20 d, and the newest row, v_k3 failed at 11 d) are OLD
-- rows that only a keep-set can save. v_k1 is the function 169 would have wiped entirely.
DO $h2$
DECLARE
  v_now timestamptz := now();
  n_fixture int; n_oldkeep int; n_oldkeep_old int; n_oldkeep_lost int; n_missing int; n_extra int; n_after int;
BEGIN
  DELETE FROM public.cron_call_log;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES
    ('v_k1', 'success', v_now - interval '40 days'), ('v_k1', 'failed',  v_now - interval '30 days'),
    ('v_k2', 'success', v_now - interval '20 days'), ('v_k2', 'started', v_now - interval '25 days'),
    ('v_k3', 'failed',  v_now - interval '11 days'), ('v_k3', 'failed',  v_now - interval '35 days');
  SELECT count(*) INTO n_fixture FROM public.cron_call_log;

  CREATE TEMP TABLE _old_keep2 ON COMMIT DROP AS
    SELECT id FROM (
      (SELECT id FROM public.cron_call_log
        WHERE status = 'success' ORDER BY started_at DESC LIMIT 1)
      UNION
      (SELECT id FROM public.cron_call_log
        ORDER BY started_at DESC LIMIT 1)
    ) k;
  CREATE TEMP TABLE _expected2 ON COMMIT DROP AS
    SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY function_name ORDER BY started_at DESC, id DESC) rn
                    FROM public.cron_call_log) a WHERE rn = 1
    UNION
    SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY function_name ORDER BY started_at DESC, id DESC) rn
                    FROM public.cron_call_log WHERE status = 'success') b WHERE rn = 1;
  SELECT count(*) INTO n_oldkeep FROM _old_keep2;
  SELECT count(*) INTO n_oldkeep_old FROM public.cron_call_log c
    WHERE c.id IN (SELECT id FROM _old_keep2) AND c.started_at < v_now - interval '10 days';
  PERFORM pg_temp.rec('H2_fixture_old_keep_set_is_two_old_rows', n_fixture = 6 AND n_oldkeep = 2 AND n_oldkeep_old = 2,
    format('fixture rows %s (expect 6); 169 keep-set rows %s, of which older than the cut %s (expect 2 and 2)', n_fixture, n_oldkeep, n_oldkeep_old));

  PERFORM public.cleanup_cron_call_log();

  SELECT count(*) INTO n_oldkeep_lost FROM _old_keep2 o WHERE o.id NOT IN (SELECT id FROM public.cron_call_log);
  PERFORM pg_temp.rec('H2_dead_fleet_old_keep_rows_survive', n_oldkeep_lost = 0,
    format('169 keep-set rows lost = %s (expect 0)', n_oldkeep_lost));
  SELECT count(*) INTO n_missing FROM _expected2 e WHERE e.id NOT IN (SELECT id FROM public.cron_call_log);
  SELECT count(*) INTO n_extra FROM public.cron_call_log c WHERE c.id NOT IN (SELECT id FROM _expected2);
  SELECT count(*) INTO n_after FROM public.cron_call_log;
  PERFORM pg_temp.rec('H2_dead_fleet_survivors_equal_oracle', n_missing = 0 AND n_extra = 0 AND n_after = 4,
    format('expected-but-deleted %s, kept-but-not-expected %s, rows left %s (expect 0, 0 and 4)', n_missing, n_extra, n_after));
END
$h2$;

-- ---------------------------------------------------------------- I
SELECT pg_temp.rec('I_orphan_pruner_dropped',
  to_regprocedure('public.cron_call_log_cleanup_7d()') IS NULL,
  format('to_regprocedure(cron_call_log_cleanup_7d) = %s (expect NULL)', coalesce(to_regprocedure('public.cron_call_log_cleanup_7d()')::text, 'NULL')));

-- ---------------------------------------------------------------- K
-- The security envelope. CREATE OR REPLACE keeps an existing function's ACL but RESETS its security mode and proconfig, so a
-- dropped SECURITY DEFINER or search_path shows up here and nowhere else; the harness additionally compares proacl with the
-- 169 state. Platform default privileges grant EXECUTE on a new public function to anon and authenticated directly, so the
-- anon / authenticated checks use has_function_privilege (which also sees a PUBLIC grant), not a text match.
DO $k$
DECLARE
  v_oid    oid := to_regprocedure('public.cleanup_cron_call_log()');
  v_def    boolean;
  v_cfg    text[];
  v_acl    aclitem[];
  v_public boolean;
BEGIN
  SELECT prosecdef, proconfig, proacl INTO v_def, v_cfg, v_acl FROM pg_proc WHERE oid = v_oid;
  v_public := EXISTS (SELECT 1 FROM aclexplode(v_acl) a WHERE a.grantee = 0);
  PERFORM pg_temp.rec('K_security_definer', coalesce(v_def, false),
    format('prosecdef = %s (expect true)', coalesce(v_def::text, 'NULL')));
  PERFORM pg_temp.rec('K_search_path_pinned', coalesce(v_cfg, '{}') = ARRAY['search_path=public'],
    format('proconfig = %s (expect {search_path=public})', coalesce(v_cfg::text, 'NULL')));
  PERFORM pg_temp.rec('K_no_public_execute', v_acl IS NOT NULL AND NOT v_public,
    format('proacl = %s (expect a non-default ACL with no PUBLIC entry)', coalesce(v_acl::text, 'NULL (default: PUBLIC can execute)')));
  PERFORM pg_temp.rec('K_anon_cannot_execute', NOT has_function_privilege('anon', v_oid, 'execute'),
    'anon EXECUTE = ' || has_function_privilege('anon', v_oid, 'execute') || ' (expect false)');
  PERFORM pg_temp.rec('K_authenticated_cannot_execute', NOT has_function_privilege('authenticated', v_oid, 'execute'),
    'authenticated EXECUTE = ' || has_function_privilege('authenticated', v_oid, 'execute') || ' (expect false)');
  -- postgres is a superuser in this image, so has_function_privilege('postgres', ...) is true whatever the ACL says (a vacuous
  -- check). The cron owner's EXECUTE is read from the ACL itself: an explicit postgres entry must be there.
  PERFORM pg_temp.rec('K_postgres_has_acl_execute',
    EXISTS (SELECT 1 FROM aclexplode(v_acl) a JOIN pg_roles r ON r.oid = a.grantee
             WHERE r.rolname = 'postgres' AND a.privilege_type = 'EXECUTE'),
    format('proacl = %s (expect an explicit postgres EXECUTE entry: the cron owner)', coalesce(v_acl::text, 'NULL')));
END
$k$;

-- ---------------------------------------------------------------- J
-- One simulated night per loop: shift every started_at and alerts.detected_at back one day (the alert's detected_at by
-- p_alert_shift), re-seed ONE fresh success for a healthy function (otherwise the dead function is the global newest success
-- and even the 169 body keeps it), run the pruner, then the real alert command. Pages are counted per function name.
CREATE FUNCTION pg_temp.sim(p_dead_age interval, p_alert_shift interval, OUT pages int[], OUT dead_rows_end int)
LANGUAGE plpgsql AS $s$
DECLARE
  v_cmd text := (SELECT t FROM public._alert_cmd);
  i int; n0 int; n1 int;
BEGIN
  DELETE FROM public.cron_call_log;
  DELETE FROM public.alerts;
  INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES ('v_dead', 'success', now() - p_dead_age);
  pages := '{}';
  FOR i IN 1..9 LOOP
    UPDATE public.cron_call_log SET started_at = started_at - interval '1 day';
    UPDATE public.alerts SET detected_at = detected_at - p_alert_shift;
    INSERT INTO public.cron_call_log (function_name, status, started_at) VALUES ('v_healthy', 'success', now() - interval '1 hour');
    PERFORM public.cleanup_cron_call_log();
    SELECT count(*) INTO n0 FROM public.alerts WHERE source = 'alert_cron_function_dead'
      AND (context_json ->> 'function_name' = 'v_dead' OR context_json -> 'function_names' @> to_jsonb('v_dead'::text));
    EXECUTE v_cmd;
    SELECT count(*) INTO n1 FROM public.alerts WHERE source = 'alert_cron_function_dead'
      AND (context_json ->> 'function_name' = 'v_dead' OR context_json -> 'function_names' @> to_jsonb('v_dead'::text));
    IF n1 > n0 THEN pages := pages || i; END IF;
  END LOOP;
  SELECT count(*) INTO dead_rows_end FROM public.cron_call_log WHERE function_name = 'v_dead';
END
$s$;

DO $j$
DECLARE
  r record;
BEGIN
  -- exact: detected_at shifts a full day per loop. Last success at age 7.6 d before loop 1, so loop 1 is age 8.6 d.
  SELECT * INTO r FROM pg_temp.sim(interval '7 days 14 hours 24 minutes', interval '1 day');
  PERFORM pg_temp.rec('J_exact_pages_loops_1_and_4', r.pages = ARRAY[1, 4],
    format('page loops = %s (expect {1,4}: ages 8.6 d and 11.6 d; the 169 body gives {1})', r.pages));
  -- jitter: detected_at shifts LESS than a day (1 day minus 1 minute), so the 72 h dedup holds one loop longer
  SELECT * INTO r FROM pg_temp.sim(interval '7 days 14 hours 24 minutes', interval '1 day' - interval '1 minute');
  PERFORM pg_temp.rec('J_jitter_pages_loops_1_and_5', r.pages = ARRAY[1, 5],
    format('page loops = %s (expect {1,5}: ages 8.6 d and 12.6 d)', r.pages));
  -- beyond the 14-day lookback: never pages, but the new body keeps the row
  SELECT * INTO r FROM pg_temp.sim(interval '14 days 14 hours 24 minutes', interval '1 day');
  PERFORM pg_temp.rec('J3_beyond_lookback_zero_pages', r.pages = '{}'::int[],
    format('page loops = %s (expect {}: the last success is already older than 14 d)', r.pages));
  PERFORM pg_temp.rec('J3_beyond_lookback_row_kept', r.dead_rows_end = 1,
    format('rows of the dead function after 9 nights = %s (expect 1 with the per-function keep-set; the 169 body gives 0)', r.dead_rows_end));
END
$j$;

SELECT label, status, msg FROM _v_results ORDER BY label;
SELECT CASE WHEN count(*) FILTER (WHERE status = 'fail') = 0
            THEN 'ALL OK (' || count(*) || ' checks)'
            ELSE 'FAILED: ' || count(*) FILTER (WHERE status = 'fail') || ' of ' || count(*) END AS summary
  FROM _v_results;

ROLLBACK;
