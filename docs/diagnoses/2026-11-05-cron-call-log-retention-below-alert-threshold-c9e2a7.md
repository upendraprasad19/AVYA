---
bug_id: c9e2a7
date: 2026-11-05
batch: oi179-cron-dead-alert
status: fixed
blast_radius: platform
symptom: >
  alert_cron_function_dead (daily 06:47 UTC; fires when a function's newest
  success in cron_call_log is 8 or more days old) has fired 0 times since it was
  created. The pruner cleanup_cron_call_log() deletes rows older than 7 days
  (sparing only the newest success and the newest row), so the table cannot
  hold evidence 8 days old and the predicate is unsatisfiable by construction.
  Live 2026-11-05: 531 rows, oldest 2026-10-29 03:30 UTC, about 7.5 days. A dead
  function therefore never paged, while the alert occupied the "coverage" slot
  and was cited as a backstop in migration 131 and in founder-digest's header.
concept: >
  A threshold on a pruned table must be smaller than that table's retention (and
  than the alert's own lookback). The alert's input set was bounded by a pruner
  it did not know about (feedback_green_check_input_set_width).
sot_registry_entry: >
  None. Cron schedules and retention are registered in docs/operations/CRON_REGISTRY.md
  (Gate 31), updated in this commit; the contract is pinned by the guard test below.
  No Hive/cloud writer-reader pair exists for this concept.
writers:
  - { file: supabase/migrations/110_cron_silence_per_function_and_cleanup_null_guard.sql, method: "cleanup_cron_call_log() — the LAST CREATE OR REPLACE; deletes started_at < now() - interval '7 days' except the newest success and the newest row", line: 30 }
  - { file: supabase/migrations/169_cron_call_log_retention_10d.sql, method: "cleanup_cron_call_log() — same body, interval '10 days' (this fix)", line: 36 }
  - { file: supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql, method: "db_maintenance_nightly — the only caller of the pruner", line: 43 }
readers:
  - { file: supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql, method: "alert_cron_function_dead (alter_job) — lookback 14 d, days_silent >= 8", line: 64 }
  - { file: supabase/migrations/109_cron_silence_alert_and_log_cleanup.sql, method: "alert_cron_silence — hours_silent >= 2 / >= 6, no lookback", line: 130 }
  - { file: supabase/migrations/147_alert_client_errors_spike_breadth.sql, method: "ops_alerts_30min cron_call_log sub-selects — 30 min / 1 h / 6 h", line: 79 }
  - { file: supabase/functions/telegram-admin-bot/index.ts, method: "cmdCron — 7-day gte window on cron_call_log", line: 566 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: cron_call_log
cloud_columns: [function_name, status, started_at, id]
contract_test_path: test/contracts/alert_threshold_below_retention_test.dart
recurrence: >
  Same CLASS as feedback_green_check_input_set_width and as OI-199 (the pruner's
  keep-set hides silence past 7 days). Related instance: diagnose d6b2f9 found
  that an UNPRUNED table (the nightly job failing) made this alert reachable for
  the first time and about to raise a false CRITICAL; this is the mirror image,
  a PRUNED table making it unreachable. Neither fix looked at the threshold
  against the retention. Prior diagnose-docs grepped: c3f8a1 (alert lineage),
  d6b2f9, e8b4a1 (disk-IO budget that set the 7-day retention).
related_bugs: [c3f8a1, d6b2f9, e8b4a1]
ist_handling: not_applicable — interval arithmetic on now(); no date key derived.
cross_account_guard: not_applicable — no per-user data path.
provider_invalidations: not_applicable
telemetry_op_types: none — the alert's own alerts row is the signal.
forbidden_patterns_checked: >
  No schema change, no new SECURITY DEFINER surface (the existing function is
  replaced with an identical body except the interval; grants re-stated, live ACL
  unchanged). The alert command, its 8-day threshold and its 14-day lookback are
  NOT touched. The applied migrations 110, 141 and 144 are immutable and untouched.
  Migration slug avoids rls/security_definer (blast_radius.yaml:92-93).
impact_analysis: >
  After apply the table holds 10 days instead of 7: about 760 rows instead of
  about 530 (76 rows a day measured), negligible against the e8b4a1 disk-IO
  budget. Every other reader uses a window of 24 hours or less, or none, or the
  7-day gte in telegram-admin-bot, so none changes. The first possible fire of
  alert_cron_function_dead is about one day after apply. Live inventory
  2026-11-05 (read-only): every scheduled function succeeded within the last
  day except weekly-recap-ready (2026-11-01, weekly cadence), so nothing sits in
  the 8-10 day band and no false CRITICAL is expected. LIMITS, stated plainly: a
  dead function pages only while its last success is 8-10 days old (24 h dedup,
  up to three alerts) and silence past 10 days is invisible again — the per-function
  keep-set is OI-199's fix. Accepted residual: one lost logCronStart insert on
  weekly-recap-ready (OI-194 class) makes the alert page at day 8. Filed instead
  of folded in: OI-471 (orphan cron_call_log_cleanup_7d(), an unconditional 7-day
  DELETE with no caller) and OI-472 (weekly-recalc logs cron runs but has no cron
  job, so a manual run would page CRITICAL 8 days later).
proposed_fix: >
  Migration 169: CREATE OR REPLACE cleanup_cron_call_log() with interval '10 days'
  (otherwise the 110 body verbatim, grants re-stated). Rejected, with the founder
  (2026-11-05): lowering the threshold to 3-5 days, because weekly-recap-ready is
  normally silent for up to 7 days and would page falsely every week; retention 21
  days, because 10 already clears the 8-day threshold with margin; a per-function
  keep-set (OI-199), because it is a larger rewrite of the pruner.
regression_test_planned: >
  test/contracts/alert_threshold_below_retention_test.dart (18 tests, after the B-pass): reads the
  retention from the LAST definition of cleanup_cron_call_log, extracts each alert's
  cron_call_log lookbacks and silence thresholds with pure functions, and asserts
  threshold < min(lookback, retention); pins the exact parsed values of
  alert_cron_function_dead (14 d / 8 d), alert_cron_silence (2 h, 6 h) and
  ops_alerts_30min (30 min, 1 h, 6 h); keeps a regression pin that the pre-fix 7-day
  retention IS a violation. Behavioural: test/sql/cleanup_cron_call_log_retention_live_verify.sql
  runs the function (BEGIN ... ROLLBACK; empties the table inside the transaction so
  fleet rows cannot mask the keep-set). MUTATIONS (applied, confirmed, restored):
  Dart — M1 retention 10 -> 7 in migration 169 = 2 red; M2 retention branch removed
  = 2 red; M3 strict < relaxed to <= = 1 red; M4 lookback bound removed = 1 red;
  M5 highest-numbered selection changed to first = red in setUpAll (1 failure, 0
  tests ran: the mutation is caught but not by the dedicated fixture); M6 comment
  strip removed = 1 red (after the first fixture proved vacuous — its comment sat
  after the function body — and was moved inside it); M7 sub-select bound removed =
  4 red; M9 cron_call_log scope removed = 3 red; B-pass additions: M10 lookback-equality `>=` changed to `>` = 1 red (it SURVIVED all 15 tests before the equality fixture was added), M11 string-literal skip in the sub-select scan removed = 1 red, M12 a new migration with an alert reading cron_call_log trips the tripwire = 1 red (probe file removed after). SQL — replica run in a disposable
  Docker Postgres (supabase/postgres 17.6.1.084, own container, not production): OLD
  7-day body = retention_9d_survives FAIL (1 of 5); NEW 10-day body = ALL OK (5);
  keep-set mutants: newest-row arm dropped = keep_set_newest_row_survives FAIL;
  newest-success arm dropped = keep_set_newest_success_survives FAIL; no keep-set =
  2 FAIL. Live proof after apply (done 2026-11-05): pg_proc prosrc reads interval '10 days' and not '7 days',
  SECURITY DEFINER, search_path public, anon and authenticated cannot execute. The SQL pin was NOT
  completed against production (the founder stopped the run for time; afterwards the row count and
  oldest row were unchanged and 0 test rows leaked); the replica run above is the behavioural proof.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ change; telegram-admin-bot comments only (deno check clean, not redeployed — comment-only)." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "pg_get_functiondef('public.cleanup_cron_call_log()') live 2026-11-05 = the migration 110 body with interval '7 days'; cron_call_log columns id, function_name, started_at, status, http_status, request_id, error_summary." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live 2026-11-05: cron_call_log 531 rows, min(started_at) 2026-10-29 03:30 UTC; last success per function read (16 daily functions within 1 day, weekly-recap-ready 2026-11-01); weekly-recalc has no cron.job and no history." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "169 minted (mint_migration.sh) and APPLIED 2026-11-05 through MCP apply_migration after the founder's per-action go (Supabase version 20261105065857); ledger entry in this commit with the hash from scripts/migration_ledger_hash.dart (sha256 of the file as applied). Rollback is a stub by design: the applied file is immutable, so a revert is a NEW forward migration restoring the 110 body (interval 7 days)." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "Live cron.job read: jobs touching cron_call_log are db_maintenance_nightly (calls cleanup_cron_call_log), ops_alerts_30min, alert_cron_silence, alert_cron_function_dead; no job calls cron_call_log_cleanup_7d (OI-471)." }
  - { tier: 12, name: client_server_contract, status: not_applicable, evidence: "No client-visible contract changes; /cron keeps its 7-day gte window." }
---

# alert_cron_function_dead could never fire: the table it reads is pruned sooner than it looks back

## What happened

`alert_cron_function_dead` asks `cron_call_log` which functions have had no
success for 8 or more days. `cleanup_cron_call_log()` deletes anything older
than 7 days. The table can therefore show at most about 7.5 days of silence,
and 8 is never reached. The alert has fired 0 times since it was created.

## Why it mattered

It looked like coverage. Migration 131 and the first `founder-digest` header
named it as the fallback that would notice a dead digest function. It would
have noticed nothing. A dead alert is worse than none, because it occupies the
slot.

## The fix

Retention 7 to 10 days (migration 169). 10 is above the 8-day threshold with two
days of margin and above the longest normal silence, the weekly Sunday push at 7
days. The alert is untouched. A threshold of 3-5 days was rejected because the
weekly job would page falsely every week.

## What is pinned

`alert_threshold_below_retention_test.dart` reads the retention from the last
definition of the pruner and each alert's thresholds from its live body, and
fails when `threshold >= min(lookback, retention)` for any alert reading
`cron_call_log`. The SQL pin runs the function and checks the 10-day boundary and
the keep-set.

## What it does not fix

Silence past 10 days is invisible again (OI-199, per-function keep-set). A
function that was never scheduled but logs runs would page after a manual run
(OI-472). An unconditional 7-day delete function still exists, uncalled (OI-471).
