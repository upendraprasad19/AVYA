-- Intent: make cleanup_cron_call_log() keep every cron function's newest success and newest row instead of two rows for the whole table (OI-199), and drop the orphan cron_call_log_cleanup_7d() (OI-471).
-- Destructive?: yes   -- DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d() (no CASCADE); the pruner change keeps MORE rows than 169 and deletes nothing by itself
-- Rollback strategy: inline   -- two commented blocks at the end (re-create the orphan from its live body and ACL, which is NOT advised; restore the 169 two-row keep-set); apply either as a NEW forward migration
-- Linked diagnose-doc: b3e7d2

-- WHY (OI-199). cleanup_cron_call_log() (live definition: migration 169) prunes cron_call_log at 10 days and spares exactly TWO
-- rows for the whole table: the newest success and the newest row of any status. A cron function that goes quiet therefore loses
-- ALL its rows at the next 03:30 UTC sweep once its newest success is older than 10 days, and every reader of the table stops
-- seeing it. alert_cron_function_dead (daily 06:47 UTC) reads the newest success per function with a 14-day lookback, so with
-- 169 alone it can see a dead function on days 8 to 10 only.
--
-- WHAT CHANGES. The keep-set becomes, for EVERY function_name, its newest success row and its newest row of any status (ties go
-- to the higher id). For every row the 169 keep-set kept it keeps a row of the same function_name, started_at and status: the
-- global newest success is the newest success of its own function, and the global newest row is the newest row of its own
-- function. (Only on an exact started_at tie between two rows of ONE function can the kept id differ from the one 169 picked;
-- 169 broke such a tie arbitrarily.) So the property 110 added still holds (a table with no success row is never wiped; a
-- fully dead fleet keeps its newest row for alert_cron_silence). Untouched: the 10-day retention, the grants, the nightly
-- caller (cron job 41, db_maintenance_nightly), every alert body.
--
-- COST, STATED. Past the 10-day cut the table keeps at most two rows per distinct function_name, forever (17 names seen live, 19
-- literal logCronStart names in the code, so at most 34 to 38 old rows), on top of every row younger than 10 days. A retired or
-- renamed function leaves its rows; purge by hand: DELETE FROM public.cron_call_log WHERE function_name = '<name>'. There is no cap
-- on the keep-set on purpose: a cap would let a fully dead fleet empty the table again after the cap and reopen the wipe class that
-- 110 closed. The sibling pruner cleanup_cron_job_run_details() already keeps one row per job the same way (DISTINCT ON (jobid)).
-- PRECONDITION OF THE BOUND: only postgres and service_role can insert into cron_call_log (the writers pass literal names). Migration
-- 068 says RLS stays disabled; live, RLS is ENABLED with zero policies while anon and authenticated still hold raw table grants
-- (OI-184, open), so row-level default-deny is the only thing keeping a client from inserting arbitrary function_name values, each
-- of which would now keep two rows for good. Read relrowsecurity and the policy count before and after the apply.
--
-- CONSEQUENCE FOR alert_cron_function_dead (the alert is NOT edited). Its 14-day lookback now becomes real: a dead function stays
-- visible from day 8 to day 14 instead of days 8 to 10. With its 72 h dedup the SAME dead function pages a second time about
-- 3 to 4 days after the first (about day 11 to 13) and never a third time (a third run would be 14 days or older, outside the
-- lookback). Beyond day 14 the alert is silent by design; the rows stay in the table. Two things stay inexact until the alert
-- body is next changed (tracked on the board, not changed here): its message says "this is the one alert; it stops once its rows
-- leave cron_call_log", and its summary says "newly detected, not already alerted".
--
-- OI-471. public.cron_call_log_cleanup_7d() deletes at 7 days and keeps nothing, so scheduling or calling it would undo the
-- retention fix of 169. Read live 2026-11-06: no cron job, function body, trigger, view or dependency references it. No migration
-- in the repo creates it (it was made out of band; 090 and 091 only REVOKE, ALTER and GRANT it). The DROP has no CASCADE, so a
-- CATALOG dependent (trigger, view, policy, rule, default) that was not seen makes this migration fail closed instead of dropping
-- it. A cron.job command or a function body that merely names it as text creates no dependency and is not stopped by the DROP; the
-- pre-apply recheck searches both, and an external RPC caller (a service-role key outside this repo) cannot be ruled out here.
--
-- STATED LIMITS (not solved here). No reader LOOKS FOR a silent function beyond 14 days (the alert) or 7 days (telegram-admin-bot
-- /cron): a function silent for more than 14 days is kept in the table and still reported by nothing. alert_cron_silence (109) is
-- unwindowed but reads only the table-wide newest success, which is always kept. That, the /cron window and the alert message
-- text are carried by new OIs.

CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  DELETE FROM public.cron_call_log
  WHERE started_at < now() - interval '10 days'
    AND id NOT IN (
      SELECT id FROM (
        (SELECT DISTINCT ON (function_name) id FROM public.cron_call_log
          WHERE status = 'success' ORDER BY function_name, started_at DESC, id DESC)
        UNION
        (SELECT DISTINCT ON (function_name) id FROM public.cron_call_log
          ORDER BY function_name, started_at DESC, id DESC)
      ) AS keep_rows
    );
$fn$;

REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;

DROP FUNCTION IF EXISTS public.cron_call_log_cleanup_7d();

-- Post-apply verification (read-only):
--   SELECT md5(prosrc), length(prosrc) FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure;
--   -- must equal the md5 and byte length of the raw text between the two $fn$ tags above (leading and trailing newline
--   -- included): 6597e3e24f91126b6268b3d54aa7ea57 and 460. The harness and a test pin this value.
--   SELECT relrowsecurity, (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cron_call_log')
--     FROM pg_class WHERE oid = 'public.cron_call_log'::regclass;  -- true, 0 (the bound's precondition, see COST above)
--   SELECT to_regprocedure('public.cron_call_log_cleanup_7d()');  -- NULL
--   SELECT proacl::text FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure;
--   -- identical to the pre-apply value {postgres=X/postgres,service_role=X/postgres}.
--   SELECT has_function_privilege('anon', 'public.cleanup_cron_call_log()', 'execute'),
--          has_function_privilege('authenticated', 'public.cleanup_cron_call_log()', 'execute');  -- false, false
--   SELECT prosecdef, proconfig FROM pg_proc WHERE oid = 'public.cleanup_cron_call_log()'::regprocedure;  -- true, {search_path=public}
--   -- Then: the first 03:30 UTC run after the apply shows cron job 41 `succeeded`.

-- Rollback (commented; apply as a NEW forward migration). Prefer a forward fix. EMERGENCY PATH: if the first 03:30 UTC run after
-- the apply fails, job 41 rolls back all four cleanups every night until a fix lands; then send block 1 through execute_sql in
-- ONE request (with the founder's go) and record it afterwards with a forward migration. Block 1 returns to the 169 keep-set, so
-- the next 03:30 run prunes the old rows this migration retained.
-- 1. Restore the 169 two-row keep-set (the body between the two $fn$ tags is the 169 body byte for byte once the `-- ` prefix is
--    removed, so md5(prosrc) afterwards equals the 169 value 0d14570d905770a34f9845683ca4aed4; a test pins this):
-- CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
-- RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
-- AS $fn$
--   DELETE FROM public.cron_call_log
--   WHERE started_at < now() - interval '10 days'
--     AND id NOT IN (
--       SELECT id FROM (
--         (SELECT id FROM public.cron_call_log
--           WHERE status = 'success' ORDER BY started_at DESC LIMIT 1)
--         UNION
--         (SELECT id FROM public.cron_call_log
--           ORDER BY started_at DESC LIMIT 1)
--       ) AS keep_rows
--     );
-- $fn$;
-- 2. Re-create the orphan (NOT advised: it prunes at 7 days and keeps nothing, so scheduling it undoes 169). Live body and ACL
--    read 2026-11-06 (EXECUTE for postgres and service_role only). Its search_path (public, extensions, vault, private) is wider than
--    anything this migration needs: dropping it removes that too, which is one more reason not to bring it back:
-- CREATE OR REPLACE FUNCTION public.cron_call_log_cleanup_7d()
-- RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'extensions', 'vault', 'private'
-- AS $fn$
--   DELETE FROM public.cron_call_log
--   WHERE started_at < now() - interval '7 days';
-- $fn$;
-- REVOKE ALL ON FUNCTION public.cron_call_log_cleanup_7d() FROM PUBLIC;
-- REVOKE ALL ON FUNCTION public.cron_call_log_cleanup_7d() FROM anon, authenticated;
-- GRANT EXECUTE ON FUNCTION public.cron_call_log_cleanup_7d() TO postgres, service_role;
