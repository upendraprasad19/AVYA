-- Intent: raise public.cleanup_cron_call_log() retention from 7 to 10 days so alert_cron_function_dead (days_silent >= 8) can actually fire (OI-179).
-- Destructive?: no   -- widens retention only; the next sweep prunes at 10 days instead of 7, nothing is deleted by this migration itself
-- Rollback strategy: inline   -- re-apply the 110 body (interval '7 days') as a NEW forward migration; see the commented block at the end
-- Linked diagnose-doc: c9e2a7

-- WHY. alert_cron_function_dead (migration 144, daily 06:47 UTC) groups
-- public.cron_call_log by function_name and fires when the newest success is
-- 8 or more days old. This function pruned the same table at 7 days (sparing
-- only the newest success and the newest row overall), so the table can never
-- hold evidence 8 days old: the predicate is unsatisfiable and the alert has
-- fired 0 times since it was created. Live 2026-11-05: 531 rows, oldest
-- 2026-10-29 03:30 UTC (about 7.5 days).
--
-- WHY 10. The slowest scheduled cadence is weekly (weekly-recap-ready, Sunday),
-- so normal silence is at most 7 days, below the 8-day threshold; a dead
-- function becomes visible from day 8. 10 > 8 leaves two days of margin for the
-- 06:47 UTC run. About 76 rows per day, so roughly 760 rows held (+230). The
-- alert command, its 8-day threshold and its 14-day lookback are NOT touched
-- (the lookback is only a cap; the table now holds at most 10 days).
--
-- LIMITS, stated plainly. A dead function pages only while its last success is
-- 8-10 days old (24 h dedup in the alert, so up to three alerts); after that its
-- rows leave the table and the silence is invisible again. Keeping the newest
-- success PER FUNCTION is OI-199's fix and is not part of this migration.
--
-- BODY. The 110 body (the LAST definition; 141 and 144 only call it) verbatim,
-- except for the interval. Grants are re-stated; CREATE OR REPLACE keeps them
-- but the repo convention (110:52-54) is to say so.

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
        (SELECT id FROM public.cron_call_log
          WHERE status = 'success' ORDER BY started_at DESC LIMIT 1)
        UNION
        (SELECT id FROM public.cron_call_log
          ORDER BY started_at DESC LIMIT 1)
      ) AS keep_rows
    );
$fn$;

REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_cron_call_log() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_cron_call_log() TO postgres;

-- Post-apply verification (read-only):
--   SELECT prosrc FROM pg_proc WHERE proname = 'cleanup_cron_call_log';  -- expect interval '10 days'
--   Then run test/sql/cleanup_cron_call_log_retention_live_verify.sql (BEGIN ... ROLLBACK).

-- Rollback (commented; apply as a NEW forward migration if ever needed):
-- CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log() ... same body with interval '7 days'.
-- That puts alert_cron_function_dead back into its unsatisfiable state, so prefer a forward fix.
