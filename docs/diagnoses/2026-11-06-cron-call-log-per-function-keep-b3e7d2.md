---
bug_id: b3e7d2
date: 2026-11-06
batch: cron-log-retention-oi199-oi471
status: fixed
blast_radius: catastrophic
symptom: >
  cleanup_cron_call_log() (migration 169, nightly at 03:30 UTC through cron job 41) spares only TWO rows for the whole table:
  the newest success and the newest row of any status. A cron function that goes quiet therefore loses ALL its cron_call_log
  rows at the next sweep once its newest success is older than 10 days, and every reader of the table stops seeing it
  (OI-199). alert_cron_function_dead (daily 06:47 UTC, newest success per function, 14-day lookback, fires at 8 days) can
  see a dead function on days 8 to 10 only, and a function silent for longer than that is reported by nothing. Also (OI-471):
  the orphan public.cron_call_log_cleanup_7d() deletes at 7 days and keeps nothing; scheduling or calling it would undo
  the 10-day retention of 169.
concept: >
  A pruned table that an absence-alert reads must keep the evidence of absence: the newest success of EVERY function, not
  of the table. A keep-set defined over the whole table silently drops the signal of exactly the functions that went
  quiet. Same class as feedback_green_check_input_set_width and diagnose c9e2a7 (the alert's input bounded by a pruner it
  did not know about), one level down: c9e2a7 fixed the retention number, this fixes what the retention spares.
sot_registry_entry: >
  None. The retention and the keep-set are registered in docs/operations/CRON_REGISTRY.md (rows 45 and 80, updated in this
  batch) and pinned by the tests below. No Hive/cloud writer-reader pair exists for this concept.
writers:
  - { file: supabase/migrations/172_cron_call_log_per_function_keep.sql, method: "CREATE OR REPLACE cleanup_cron_call_log(): per-function keep-set (this fix)", line: 49 }
  - { file: supabase/migrations/172_cron_call_log_per_function_keep.sql, method: "DROP FUNCTION IF EXISTS cron_call_log_cleanup_7d() (OI-471, this fix)", line: 72 }
  - { file: supabase/migrations/169_cron_call_log_retention_10d.sql, method: "cleanup_cron_call_log(): the two-row global keep-set this fix replaces", line: 30 }
  - { file: supabase/functions/_shared/cron_telemetry.ts, method: "logCronStart: inserts the cron_call_log rows the pruner sweeps", line: 50 }
readers:
  - { file: supabase/migrations/170_oi473_cron_dead_alert_edges.sql, method: "alert_cron_function_dead: newest success per function, 14-day lookback, 8-day threshold, 72 h dedup", line: 46 }
  - { file: supabase/migrations/136_founder_metrics_ops_exclude_info_client_errors_7d.sql, method: "founder_metrics_ops(): 24 h window counting failed and stuck rows (cannot see the rows the keep-set adds, which are older than 10 days)", line: 49 }
  - { file: supabase/functions/telegram-admin-bot/index.ts, method: "cmdCron: 7-day gte on started_at (unchanged; OI-478)", line: 563 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: cron_call_log
cloud_columns: [function_name, status, started_at]
contract_test_path: test/contracts/cleanup_cron_call_log_per_function_keep_test.dart
recurrence: >
  Same CLASS as c9e2a7 (OI-179: alert threshold above the pruner's retention) and f7b3d1 (OI-473: edges of the alert that
  only matter once it can fire); this is the third change to the same table-and-alert pair in two days, each exposing the
  next limit the previous one stated. The previous batch's migration 170 header lists this exact limit ("silence beyond 10 days
  stays invisible until OI-199's per-function keep-set"). Prior diagnose-docs grepped: c9e2a7, f7b3d1, c3f8a1, d6b2f9,
  82b018 (the telegram-admin-bot review that found the "spares TWO rows" claim false). Superseded wording (records stay as
  history, this doc names them): "a dead function pages only while its last success is 8-10 days old (24 h dedup, up to three
  alerts) and silence past 10 days is invisible again" in c9e2a7 (lines 66-70) and, as "24 h dedup / up to three alerts / pages
  only during days 8-10", in f7b3d1 (lines 43-45), docs/audit/2026-11-05-hermes-oi179-cron-dead-alert.md:61,
  docs/plans/oi179-cron-dead-alert.md:38 and the 169 header ("the lookback is only a cap"; its LIMITS paragraph), plus
  "silence beyond 10 days stays invisible until OI-199" in the 170 header (169 and 170 are immutable); edited in this batch: CRON_REGISTRY
  rows 45, 52 ("still sees only 8-10 days") and 80, the founder-digest header ("cannot fire at all"), the cron_telemetry.ts
  retention line, and the comments of test/helpers/cron_call_log_windows.dart and alert_threshold_below_retention_test.dart. What is true since 172:
  a dead function stays visible from day 8 to the 14-day lookback and pages about twice (72 h dedup since 170), never three
  times. The "TWO rows globally" comments of telegram-admin-bot were edited in this batch.
related_bugs: [c9e2a7, f7b3d1, c3f8a1, d6b2f9, 82b018]
ist_handling: not_applicable — interval arithmetic on now(); no date key derived.
cross_account_guard: not_applicable — no per-user data path.
provider_invalidations: not_applicable
telemetry_op_types: none — the cron_call_log rows themselves are the signal.
forbidden_patterns_checked: >
  The new body is SECURITY DEFINER with search_path public (restated, as 169), so the batch is catastrophic by content
  (scripts/blast_radius_content_rules_lib.dart) and carries a Hermes pass. Grants restated exactly as 169 (REVOKE PUBLIC, anon,
  authenticated; GRANT postgres); live ACL {postgres=X/postgres,service_role=X/postgres} must be identical before and after.
  The DROP has no CASCADE. No alert body, schedule or job is touched (cron job 32 and 41 unchanged). Migrations 169 and 170 are
  immutable and untouched. Telegram is deferred (founder 2026-11-04): the /cron window is not built here.
impact_analysis: >
  Nothing is dead today (live read 2026-11-06 04:40 UTC: 17 function names, 598 rows, all status success, the oldest newest-success
  4.59 days old), and every row older than 10 days is already pruned, so the keep-set is NOT observable live until a function goes
  quiet for more than 10 days. Rows kept past the 10-day cut: at most two per distinct function_name, forever (17 names seen live, 19 literal logCronStart
  names in the code, so 34 to 38 old rows), on top of every row younger than 10 days; a retired function
  leaves its two rows (manual purge: DELETE ... WHERE function_name = '<name>'). BEHAVIOUR CHANGE of the live alert, measured
  (case J below), the alert body untouched: a dead function pages TWICE instead of once (first at age 8 to 9 days, second at
  11 to 13 days depending on pg_cron start jitter), never three times, and not at all once its last success is older than the
  14-day lookback. ACCEPTED RESIDUALS, stated and tracked in OI-478: no reader looks beyond 14 days (alert) or 7 days (/cron);
  the alert's own message says "this is the one alert; it stops once its rows leave cron_call_log" and "newly detected, not
  already alerted", both inexact now (the SECOND page of a dead function carries that wrong text; the founder is told in the apply ask); OI-194 (a cron start insert lost in a same-minute burst reads as silence) gives a false
  critical at day 8 and, with the kept row, a second at day 11 to 13 (weekly-recap-ready fires at 14:30 UTC on Sundays beside
  streak-guardian and protein-gap-alert). A runtime error in the new body would roll back ALL FOUR cleanups of job 41 (one
  implicit transaction) and page through job 46 alert_sql_job_failures; check_function_bodies is on live, the body has no cast
  or division, and the live runs of job 41 take about 0.8 s (last 10 nights all succeeded).
proposed_fix: >
  Migration 172: CREATE OR REPLACE cleanup_cron_call_log() keeping, per function_name, the newest success row UNION the newest
  row of any status (DISTINCT ON (function_name), ties to the higher id), same 10-day retention, same grants; then DROP FUNCTION
  IF EXISTS public.cron_call_log_cleanup_7d() without CASCADE. Rejected: a cap on the keep-set ("newer than N days"): it lets a
  fully dead fleet empty the table again after N days (the F5 wipe class, docs/audit/2026-07-26-hermes-cron-secret-auth.md:81)
  and needs a second interval the retention reader cannot read; moving the alert's dedup to about 7 days so a dead function
  pages once: a new cron.alter_job migration and a larger blast radius, not needed to keep the evidence; splitting the DROP from the
  keep-set: both reviewers advised against it (the heavy SECURITY DEFINER half needs the Hermes pass either way).
regression_test_planned: >
  test/contracts/cleanup_cron_call_log_per_function_keep_test.dart (65 tests; a SOURCE-SHAPE pin, no database, and it says so:
  the keep-set shape of the LATEST definition read inside the balanced NOT IN list, so an extra arm, UNION ALL or a whole-table
  SELECT fails as well as a missing arm; the WHOLE function text equal to migration 172's, whitespace- and comment-insensitive
  (Hermes D-1: the list check was blind to `) OR started_at < ... '30 days'`, a second DELETE or another DELETE target); the
  SECURITY DEFINER envelope and the grants, reading every GRANT/REVOKE whatever the spelling of the name (Hermes D-2, D-8); the
  DROP form without CASCADE; no migration at or after the drop mentioning the orphan outside a comment; no migration newer than
  the resolved latest definition running DDL on the function (DDL only, so a later job 41 CALL does not flag, Hermes D-3); rollback
  block 1 equal to 169 in body (byte for byte) and header (Hermes D-4); the raw `$fn$` text of 172 has md5
  6597e3e24f91126b6268b3d54aa7ea57 and 460 bytes, the same literals as the harness, the plan and the migration; the harness orphan
  equals rollback block 2; the harness's step 2b and the plan quote the same apply-request wrapper and the same 880-byte statements block; 40 fixtures frozen on migration 172's text (37 must be rejected, 3 must be accepted: B4, P1, P2), each
  rejection asserting the SPECIFIC problem it must raise). Behavioural, in a LOCAL docker Postgres (supabase/postgres 17.6.1.084,
  never production): test/sql/cleanup_cron_call_log_per_function_local.sh (run with bash) applies the REAL migration 169 and 172
  files and runs test/sql/cleanup_cron_call_log_per_function_verify.sql (35 checks: A boundary incl. the exact-10-day row, B/C/D
  dead, silent and never-succeeded functions, E recent rows, F empty table, F2 tie, G idempotent, H every row 169 kept survives
  and exactness against an independent row_number() oracle, H2 the same on a DEAD FLEET where the rows 169 kept are old (in H they
  are 0 to 1 days old, so that label could never go red: Hermes D-5), I the drop, J nine simulated nights of the real alert, K the
  security envelope: SECURITY DEFINER, search_path pinned to public, no PUBLIC / anon / authenticated EXECUTE, an explicit postgres
  EXECUTE entry in the ACL; the file refuses to run outside the harness scaffold and the harness proves it does, rc=3). Run
  2026-11-06 (harness exit 0): OLD (169) body 15 of 35 red (B x3, C x2, D x2, F2, H x2, H2 oracle, I, J exact, J jitter, J3 row
  kept), A/E/F/G/K and the H2 fixture and 169-keep labels green. NEW (172) body 35 of 35; step 2b runs the exact LIVE APPLY REQUEST (BEGIN, SET LOCAL timeouts, the file's CREATE..DROP lines, an in-transaction md5/length assertion, COMMIT) on the 169 state: it commits; a wrong md5 aborts it and the CREATE and DROP roll back together; a catalog dependent of the orphan (a view) fails the DROP and rolls the CREATE back; proacl IDENTICAL to the 169 state
  ({postgres=X/postgres,service_role=X/postgres}), md5(prosrc)|length(prosrc) = 6597e3e24f91126b6268b3d54aa7ea57|460, a second
  apply of 172 raises no error, and the older pin test/sql/cleanup_cron_call_log_retention_live_verify.sql (updated: one function
  name per scenario) is ALL OK (5 checks) under both bodies. SQL MUTANTS on the 172 body (19), each on its own reset, applied and
  confirmed (changed-line counts), an apply error counted as a failure not a kill, all killed: M1 arm 1 loses the success filter =
  5 red; M2 arm 2 removed = 8; M3 DISTINCT ON removed = 9; M3b global LIMIT 1 (the 169 shape) = 14; M4 ASC = 11; M5 INTERSECT = 9;
  M6 7 days = 5; M7 IN for NOT IN = 17; M8 retention guard deleted = 5; M9 DROP deleted = 1; M10 arm 2 `status <> 'started'` = 2;
  M11 `<=` at the cut = 2; M12 tie-break dropped = 2 (F2 and H); M13 GRANT also to anon = 1 (K_anon only); M14 SECURITY INVOKER = 1
  (K_security_definer only); M15 search_path clause deleted = 1 (K_search_path_pinned only); M16 GRANT also to PUBLIC = 3
  (K_no_public_execute, K_anon, K_authenticated); M17 GRANT also to authenticated = 1; M18 REVOKE EXECUTE FROM postgres = 1
  (K_postgres_has_acl_execute). Before Hermes three of the six K labels had no mutant that reddened them (D-6); H2's
  H2_dead_fleet_old_keep_rows_survive goes red under M2, M4, M5 and M7, where the H label stayed green in every run. M12 CAVEAT:
  which of two tied rows DISTINCT ON picks without the id tie-break is planner-dependent, so M12 may survive on another plan or
  Postgres minor (it was killed through F2 in every run so far); the harness reports a survivor without counting it as coverage,
  and the tie-break TEXT is pinned independently by the Dart fixture M12. Deleting a REVOKE line is equivalent inside the harness
  (172 is applied on top of 169's ACL), so the REVOKE and GRANT text is pinned by the Dart fixtures A3, A5 and A7 to A10. M10
  SURVIVED the first harness run: the fixture's "newest row is started" function had that row 2 hours old, so retention kept it
  whatever the keep-set did; fixed with a function whose newest row is started and 15 days old (v_h7), then killed. NEUTER
  experiment on the rewritten Dart checkers (all six reduced to `return []` in a scratch copy, removed afterwards): 42 tests
  reddened, exactly the 37 rejection fixtures plus the 5 DDL fixtures that expect a flag; the accepted fixtures, the baseline and
  the two "a call is not DDL" fixtures stayed green, as they should. The two tests that read the migrations DIRECTORY (and so have no text
  fixture) were mutated by hand with scratch migration files, each removed by a trap: a scratch 173 and a scratch 172b naming the
  orphan outside a comment each reddened exactly "no other migration at or after the drop mentions the orphan pruner"; a scratch
  173 with `DROP FUNCTION IF EXISTS "public"."cleanup_cron_call_log"()` and another with `GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA
  public TO anon` each reddened exactly "no migration NEWER than the resolved latest definition runs DDL on the function", and a
  scratch 173 containing only `SELECT public."cleanup_cron_call_log"();` reddened nothing (the false red Hermes D-3 found is gone).
  Plan review ground truth (reviewer 1) ran the body on 3000 random fixtures (0 violations of superset and exactness, as that
  reviewer defined them) and measured the page counts independently of the harness. B-pass (two Sonnet reviewers, no P0 or P1): R1
  found that nothing pinned the security envelope or the grants (now case K, M13 to M15, the proacl equality), that rollback block
  1 was not byte-identical to 169 (fixed, pinned by rollbackProblems), that "strict superset" was not literally true for an exact
  started_at tie inside one function (reworded), and that the harness must be run with bash; R2 found that the Dart checker did not
  reject a keep-set that is too WIDE (a third arm, UNION ALL, a whole-table SELECT: fixed and fixtured as W1 to W5) and the
  case-insensitive 'success' literal. Hermes pass (four Sonnet seats, no P0 or P1, report docs/audit/2026-11-06-hermes-cron-log-
  retention-oi199-oi471.md): the runbook now sends ONE execute_sql request with SET LOCAL timeouts and an in-transaction md5
  assertion (A-1 to A-4), captures the orphan's attributes and row-count snapshots first (A-5 to A-7), names an emergency path (A-8)
  and separate gos (A-10); stale wording fixed in CRON_REGISTRY row 52 and two Edge Function header comments (B-1, B-3, B-5); the
  RLS precondition of the per-name bound is stated and read (C-1); "fail closed" now says catalog dependents only (C-2);
  error_summary sanitising is OI-481 (C-4); the Dart and SQL findings D-1 to D-10 are above.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ change." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "Live 2026-11-06: cleanup_cron_call_log prosrc md5 0d14570d905770a34f9845683ca4aed4 (length 372) equals the 169 body; cron_call_log_cleanup_7d md5 853d4dc0ce64bb76c5c2e8a12f8b2099 (length 84); both proacl {postgres=X/postgres,service_role=X/postgres}, owner postgres; id is bigint NOT NULL, function_name TEXT NOT NULL; live table has RLS enabled with no policies and a partial index WHERE status <> 'success' (neither touches the DELETE)." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live read-only 2026-11-06 04:40 UTC: 17 distinct function names, 598 rows, all status success, oldest newest-success 2026-11-01 14:30 (weekly-recap-ready, 4.59 d); no failed or started row exists." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "NO deploy and NO deployed-version read in this batch: telegram-admin-bot, founder-digest and _shared/cron_telemetry.ts are not redeployed, because only comments changed (precedent 0d16beb1; every changed line is a // or * comment, proven with git diff -U0), so the deployed code is behaviourally identical to the tree. Local checks only: deno check --node-modules-dir=none passes for telegram-admin-bot and founder-digest, the 51 telegram-admin-bot Deno tests pass, node_modules untouched; no redeploy (no behaviour change)." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "Live cron.job: only job 41 db_maintenance_nightly (30 3 * * *) calls cleanup_cron_call_log, with three other cleanups in one command; jobs 31, 32, 41, 43 read cron_call_log; job 41 last 10 runs all succeeded in 0.77 to 0.93 s; no cron job names cron_call_log_cleanup_7d." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "Live 2026-11-06 (plan Facts): cron_call_log has RLS ENABLED and zero policies; migration 068 says RLS stays disabled, so the live state differs from a replay of the migrations. The per-name row bound relies on it (anon and authenticated still hold raw table grants, OI-184 open): relrowsecurity and the policy count are read before and after the apply." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Readers of cron_call_log swept in the live catalog (pg_proc.prosrc, pg_views, pg_matviews, pg_rules, pg_policies, cron.job, table triggers) and in the repo (lib/, supabase/functions/, scripts/, test/): alert_cron_function_dead, alert_cron_silence, ops_alerts_30min, founder_metrics_ops, telegram-admin-bot cmdCron; none is hurt by one to two extra old rows per function. No outside reader can be ruled out: track_functions is none, service_role can execute the orphan; the pre-apply recheck reads pg_stat_statements and the API logs." }
---

# cleanup_cron_call_log: keep every function's newest evidence, and drop the orphan 7-day pruner

## What happened

Migration 169 raised the `cron_call_log` retention to 10 days so `alert_cron_function_dead` can fire, and 170 reworked that
alert's edges. Both left one limit in their headers: the pruner spares two rows for the whole table, so a function silent for
more than 10 days is erased from the table and nothing can see it (OI-199). The same review rounds found an orphan pruner,
`cron_call_log_cleanup_7d()`, that would undo 169 if anyone scheduled it (OI-471).

## The fix

Migration 172 makes the keep-set per function (newest success plus newest row of any status, ties to the higher id), keeps the
10-day retention and the grants, and drops the orphan without `CASCADE`. The alert is not edited. Scope call by the founder on
2026-11-06: the proposal "I'd do only the migration and leave out the Telegram `/cron` window change, since Telegram is
deferred" was answered "Ok", so the `/cron` window, the alert's own message text and a reader for silence beyond 14 days are
OI-478. The two stale `telegram-admin-bot` comments that repeated the "spares TWO rows globally" claim are corrected here, with the
`founder-digest` header ("cannot fire at all") and the `cron_telemetry.ts` retention line (comment text only, no redeploy).
THE BOUND'S PRECONDITION (Hermes C-1): "at most two rows per name" holds only while nobody but postgres and service_role can insert
into `cron_call_log`. Migration 068 says RLS stays disabled; live, RLS is enabled with zero policies while `anon` and
`authenticated` still hold raw table grants (OI-184, open), so default-deny RLS is the only barrier. The migration states this,
and the pre- and post-apply reads include `relrowsecurity` and the policy count.

## Apply state

**APPLIED to production 2026-11-06 about 20:47 IST (15:17 UTC), after the founder's explicit go** ("Yes, apply migration"),
project `dedsavbjuwgarrhphgnl`, through MCP `execute_sql` as ONE request (BEGIN, `SET LOCAL` timeouts 3 s and 60 s, the file's
CREATE..DROP lines, an in-transaction md5/length assertion, COMMIT; 1,328 bytes). The first attempt expired at the tool's own
confirmation prompt (no approval within 2 minutes) and ran nothing: the live state was re-read and was unchanged (169 body,
orphan present). The second attempt was confirmed and committed. Commit, push and merge are separate gos.

Pre-apply reads (read-only, 2026-11-06 09:55 and 11:01 UTC; the two function bodies and the ACL were read again at 15:16 UTC, immediately before the confirmed attempt): `cleanup_cron_call_log` md5 0d14570d905770a34f9845683ca4aed4,
length 372, SECURITY DEFINER, `search_path=public`, owner postgres; orphan md5 853d4dc0ce64bb76c5c2e8a12f8b2099, length 84,
`search_path=public, extensions, vault, private`, one overload, volatile, cost 100, no comment; both `proacl`
`{postgres=X/postgres,service_role=X/postgres}`; `cron_call_log` RLS enabled, 0 policies, `anon` and `authenticated` hold INSERT
table privilege (OI-184, open: default-deny RLS is the only barrier); 616 rows, 17 names, `min(started_at)`
2026-10-29T03:30:02Z, 97 rows older than 7 days (so the orphan has not run), 0 older than 10 days; the orphan has no `pg_depend`
dependent and no `cron.job` command or function body names it; job 41 command md5 1b4c39eb5ec1ef3d168dda19b15ba494.

Post-apply read (2026-11-06 15:17 UTC): `md5(prosrc)` 6597e3e24f91126b6268b3d54aa7ea57 and `length(prosrc)` 460, equal to the raw
text between the `$fn$` tags of the file; `to_regprocedure('public.cron_call_log_cleanup_7d()')` null; `proacl` IDENTICAL
`{postgres=X/postgres,service_role=X/postgres}`; `has_function_privilege` false for `anon` and `authenticated`; `prosecdef` true,
`proconfig` `{search_path=public}`, owner postgres; RLS enabled, 0 policies (unchanged); job 41 command md5 unchanged; rows 624
(the writers' own inserts since the pre-apply read of 616; nothing was deleted) and `min(started_at)` unchanged.

NOT YET OBSERVED LIVE: the keep-set itself (no function has been quiet for 10 days; every row older than 10 days was already pruned
and the oldest row is 8 days old). Follow-ups, written here as they happen: (1) the 03:30 UTC run of job 41 on 2026-11-07 shows
`succeeded` (a runtime error would roll back all four cleanups and page through job 46); (2) the first deletions of rows older than
10 days are about 2026-11-09 03:30 UTC: `min(started_at)` of each frequent function moves forward and each function's newest success
and newest row survive.

## Not done, on purpose

The `/cron` window, the alert message text and the reader for silence beyond 14 days (OI-478). Sanitising `error_summary` at the telemetry sink (OI-481, Hermes C-4): a habit of about 19 call sites, no leak found, not changed by this batch. The cost of the complete local gate loop (OI-480) rides on this PR's board diff but is not a unit of the batch. Moving the alert's dedup so a
dead function pages once. A cap on the keep-set. The keep-set is not observable live until a function goes quiet for more
than 10 days: the rehearsal ran in a local container, never on production (a first production rehearsal of OI-473 hung
without finishing).
