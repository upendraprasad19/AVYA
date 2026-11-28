# OI-179 — `alert_cron_function_dead` can never fire

Tier: L (migration + live function change). Execution mode: INLINE. Branch `oi179-cron-dead-alert`.
Lenses: L1 (writer/reader), L31 (alert coverage), data-retention.
Plan revision: v4. v1-v3 went through two context-blind review rounds (R1-1..R1-7, R2-1..R2-9). Founder
decision 2026-11-05: option 1 (retention 7 -> 10 days) and a MINIMAL scope; v4 is a strict subset of v3
(the orphan-function drop and the `weekly-recalc` exclusion are removed and filed as their own OIs).

## Facts (verified 2026-11-05, live project `dedsavbjuwgarrhphgnl`)

- Reader: `alert_cron_function_dead`, body last set by migration 144 (`alter_job`, :64-96): reads
  `public.cron_call_log` over `started_at > now() - interval '14 days'`, fires on `days_silent >= 8`,
  daily 06:47 UTC. No later migration redefines it.
- Pruner: `public.cleanup_cron_call_log()`, LAST `CREATE OR REPLACE` = migration 110:30-47; called by
  `db_maintenance_nightly` (141/144). Live body confirmed with `pg_get_functiondef`:
  `started_at < now() - interval '7 days' AND id NOT IN (newest success UNION newest row)`,
  `SECURITY DEFINER`, `SET search_path TO 'public'`.
- Live table: 531 rows, min `started_at` 2026-10-29 -> the alert can see at most ~7.5 days silent;
  `8 > 7.5`, unsatisfiable, fired 0 times ever.
- Slowest scheduled cadence is weekly (`weekly-recap-ready`, Sunday): normal silence <= 7 days < 8.
- Other `cron_call_log` readers use windows <= 24 h, or none (alert_cron_silence), or a 7-day `.gte()`
  (telegram-admin-bot `/cron`); all below 10 days.
- Live inventory (read-only, 2026-11-05): every scheduled function succeeded within the last day,
  except `weekly-recap-ready` (2026-11-01); nothing sits in the 8-10-day band. No other pruner is
  scheduled (jobs touching `cron_call_log`: `db_maintenance_nightly`, `ops_alerts_30min`,
  `alert_cron_silence`).
- R2-11 precondition (exclude trigger-dispatched `alert-critical-notify`) is met by 144.

## Fix

1. Migration (number via `sh scripts/mint_migration.sh cron_call_log_retention_10d`; slug avoids
   `rls`/`security_definer`, which blast_radius.yaml would classify catastrophic): four-tag header,
   `CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()` = the 110 body verbatim except
   `interval '7 days'` -> `interval '10 days'`, grants re-stated (`REVOKE ALL ... FROM PUBLIC`,
   `FROM anon, authenticated`, `GRANT EXECUTE ... TO postgres`). 10 > 8: a weekly function (<= 7 days)
   keeps 2 days of margin, a dead one is visible from day 8. The alert command is NOT touched.
   Cost ~760 rows (+230). Stated limits: a dead function pages only during days 8-10 (then its rows
   leave the table; 24 h dedup => up to 3 alerts) and silence beyond 10 days is invisible again - the
   per-function keep-set is OI-199's fix, not this batch.
2. Guard test `test/contracts/alert_threshold_below_retention_test.dart`. Invariant (the class):
   **threshold < min(lookback, retention)** - a lookback larger than retention is benign (it is only a
   cap); a threshold at or above either bound makes the alert unsatisfiable. REUSE
   `test/helpers/cron_job_body_reader.dart` `latestCronJobBody(job)` (add an optional
   `migrationsDir` parameter for fixtures); retention via `latestMigrationDefining` +
   `stripSqlComments`. Pure functions `extractCronCallLogWindows(String jobSql)` and
   `violations(windows, retentionDays)`. Lookbacks: `interval 'N unit'` between
   `FROM public.cron_call_log` and the paren-balanced close of that subselect (minute/hour/day ->
   days); thresholds: whole body, `(days|hours)_silent >= N`, MAX when repeated. Real-shape fixtures
   + exact-value non-vacuity: function_dead (lookback 14, threshold 8), cron_silence (threshold 6 h),
   edge_function_health (30 min), cron_failures (1 h / 6 h).
3. Behavioural pin `test/sql/cleanup_cron_call_log_retention_live_verify.sql`, `BEGIN ... ROLLBACK`:
   `DELETE FROM public.cron_call_log` inside the transaction, seed a 9-day success (survives), an
   11-day success (gone), two 30-day rows - a success and a NEWER non-success - plus a recent row;
   assert the 30-day success survives only as the newest success. Run FIRST against the OLD 7-day body
   (9-day assertion reddens), then the new one. Pre-apply re-check (read-only): `pg_proc` names like
   `%cron_call_log%` and `cron.job` commands like `%cron_call_log%`.
4. Stale 7-day text: `docs/operations/CRON_REGISTRY.md` :45, :52 ("NOT a backstop"), :80 ("7-day
   retention"); telegram-admin-bot comments at `index.ts:545-568` and `index_test.ts:1175-1185`
   (the 7-day `.gte()` and its Deno assertion STAY 7; grep `test/` and `index_test.ts` for the text
   before editing; `deno check --node-modules-dir=none supabase/functions/telegram-admin-bot/index.ts`;
   comment-only, not redeployed); OI-199 text (retention now 10 days).
5. Artifacts: full-template diagnose-doc (recurrence `feedback_green_check_input_set_width`; related
   OI-199, c3f8a1, d6b2f9, e8b4a1); `docs/sot_registry.yaml` concept
   `cron_call_log_retention_vs_alert_window` with `behavioral_test_path:` = the SQL pin (Gate 42);
   plan-review record `docs/plan-reviews/oi179-cron-dead-alert.md` (`bpass: accepted`);
   `backups/applied_migrations.json` entry in the commit that APPLIES (hash via
   `scripts/migration_ledger_hash.dart`); OI-179 closed in the POST-apply commit (until then the OI text
   reads "fixed on main, live apply pending"; `closes-oi: OI-179`).
6. Two new OIs (own numbers via `scripts/mint_oi.sh`): (a) orphan `cron_call_log_cleanup_7d()` - an
   unconditional 7-day DELETE with no caller, would undo this fix if scheduled; (b) `weekly-recalc`
   calls `logCronStart` but has no cron job, so a manual run would page CRITICAL 8 days later via the
   alert; plus the accepted residual (`weekly-recap-ready` lost-insert, OI-194 class).

## Live apply

Separate explicit founder go (CLAUDE.md §4.3). Order: merge code half -> founder go -> pre-apply
re-check -> apply -> run the SQL pin -> ledger -> close OI. Rollback: forward migration back to 7 days.

## Mutations (rule 21) — each confirmed applied (`grep -c`); a compile error is not red

M1 retention 10 -> 7 in the new migration. M2 fixture threshold 30 vs retention 10. M3 threshold ==
retention (strict `<`). M4 fixture lookback 6 < threshold 8 (lookback bound). M5 fixture dir with a
newer smaller-interval redefinition ("highest-numbered" selection). M6 remove the comment strip,
fixture with a rollback comment `interval '7 days'`. M7 remove subselect scoping, fixture with a 24 h
dedup on `alerts`. M8 remove the `UNION` newest-row arm (SQL pin). M9 drop the `cron_call_log` scope
in the extractor (exact-value pins).
