---
bug_id: d6b2f9
date: 2026-09-26
batch: ops-alerting-batch-b (B1 — retention restore, deadline 2026-10-01)
status: fixed
blast_radius: platform
symptom: >
  pg_cron job 41 `db_maintenance_nightly` FAILED every run 2026-09-22 → 09-26
  (5/5, `ERROR: VACUUM cannot run inside a transaction block`, avg 0.93 s).
  Because pg_cron executes a multi-statement command as ONE transaction, the
  error also rolled back the four cleanups in the same command:
  cron_call_log, usage_counters, cron.job_run_details and client_errors had
  not been pruned since 2026-09-21. Knock-on: cron_call_log now reaches back
  to 09-14, which makes `alert_cron_function_dead` (`days_silent >= 8`,
  daily 06:47 UTC) reachable for the first time — `alert-critical-notify`
  (last success 2026-09-22 11:00) would raise a FALSE CRITICAL at
  2026-10-01 06:47 UTC. Nothing alerted on the job failure itself (OI-178:
  SQL-only cron jobs write no cron_call_log row).
concept: >
  Migration 141 (disk-IO audit, 2026-09-22) consolidated six single-statement
  maintenance jobs into one command: four `SELECT cleanup_*()` + two
  `VACUUM (ANALYZE)`. With `cron.use_background_workers=off` (live) pg_cron
  sends the command over libpq as one simple query, which Postgres runs as a
  single implicit transaction; VACUUM refuses to run in a transaction block. As separate
  single-statement jobs (pre-141 jobids 35/36) the same VACUUMs succeeded
  every night 09-06 → 09-20 — the consolidation, not the statements, is the
  defect. 141's registry row even described the new shape as an improvement
  ("sequenced explicitly AFTER retention in the same job").
sot_registry_entry: >
  None. Cron scheduling is registered in docs/operations/CRON_REGISTRY.md
  (Gate 31), updated in this commit; no Hive/cloud writer-reader pair changes.
writers:
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method: "cron.schedule('db_maintenance_nightly', …) — four cleanups + two VACUUMs in ONE command (immutable; repaired by 144)", line: 71 }
  - { file: supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql, method: "cron.alter_job(db_maintenance_nightly) → cleanups only; two single-statement VACUUM jobs; alert_cron_function_dead excludes alert-critical-notify", line: 37 }
readers:
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method: "the job as pg_cron reads it (live jobid 41 matched byte-for-byte) — one command, executed as one transaction", line: 71 }
  - { file: supabase/migrations/110_cron_silence_per_function_and_cleanup_null_guard.sql, method: "alert_cron_function_dead — reads cron_call_log success rows within 14 d, fires at days_silent >= 8 (live jobid 32 matches)", line: 112 }
  - { file: docs/operations/CRON_REGISTRY.md, method: "db_maintenance_nightly row — described the broken shape as correct", line: 46 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: cron.job
cloud_columns: [command, schedule, jobname]
contract_test_path: test/contracts/cron_vacuum_single_statement_test.dart
recurrence: >
  Not a recurrence of a recorded diagnose-doc (INDEX grepped for VACUUM /
  transaction block / db_maintenance: no prior instance). Same FAMILY as
  migration 141's other fold-in regression, migration 143 (the ops_alerts_30min
  consolidation silently reverted 140's stuck-job bound): 141's consolidations
  changed execution semantics that no test or review exercised. And the
  failure was silent for 5 days because of OI-178 — a pure-SQL job that fails
  emits nothing any alert reads.
related_bugs: [e8b4a1]
ist_handling: not_applicable — cron schedules are UTC; no date key derived.
cross_account_guard: not_applicable — no per-user data path.
provider_invalidations: not_applicable
telemetry_op_types: none — B2 (OI-178) adds the missing alert for failed SQL jobs.
forbidden_patterns_checked: >
  No SECURITY DEFINER (tier platform, classified on the written file). No data
  written by the migration itself. No edit to the applied, immutable 141 —
  the correction lives here, in 144's header, and in CRON_REGISTRY.md.
  cron.alter_job preserves jobids 41/32 and their run history (141 §4c precedent).
impact_analysis: >
  Restores the four prunes and the two VACUUMs to their pre-141 working
  shape. The first run after apply deletes (measured live, plan-review R1)
  730 of 1,429 cron_call_log rows, 2,406 of 6,968 job_run_details, 85 of
  6,007 client_errors and 11 of 28 usage_counters (all windowed keys are
  daily; lifetime rows are spared by the function's two-sided predicate). No
  alert can trip from a prune: every reader only loses rows, and
  cleanup_cron_call_log spares the globally newest success row.
  alert_cron_function_dead loses exactly one function from scope.
proposed_fix: >
  Migration 144: (1) cron.alter_job(db_maintenance_nightly, command := the four
  cleanups); (2) re-schedule jrd_vacuum_daily 03:40 and client_errors_vacuum_daily
  03:43 UTC as single-statement jobs; (3) cron.alter_job(alert_cron_function_dead)
  adding `AND function_name <> 'alert-critical-notify'`. Rejected: wrapping the
  VACUUM in a function (VACUUM cannot run inside a function either);
  dropping VACUUM entirely (autovacuum exists, but the pre-141 explicit VACUUM
  was a deliberate disk-IO decision in 121 — reversing it is its own call).
regression_test_planned: >
  test/contracts/cron_vacuum_single_statement_test.dart (6 tests) — scans every
  migration's comment-stripped dollar-quoted bodies, `$$` AND tagged `$job$`/
  `$cron$` (plan-review R1 F1: the first draft read `$$` only and was blind to the
  repo's majority style), for a VACUUM beside another statement; proves non-vacuous
  on 141 and on a synthetic `$job$` body; admits 141 only while 144 repairs it; pins
  the exclusion INSIDE the alert's cron_call_log subquery; and requires every
  trigger-dispatched roster function (cron_auth_adoption_test.dart) that calls
  logCronStart to be excluded. MUTATIONS (applied, confirmed, restored with cmp):
  (a) VACUUM re-added to 144's cleanup command → 2 red; (b) exclusion deleted → 2 red;
  (c) regex reverted to untagged `$$` → 1 red (the synthetic tagged case);
  (d) predicate moved to the outer WHERE → 1 red (the subquery case); after R2
  hardening, (e) predicate changed to `OR function_name <> …` → 2 red and (f)
  `'weekly-recalc'` added to the roster ON THE SAME LINE as an existing entry → 1
  red. Residue:
  a SINGLE-quoted cron command is not scanned (0 exist today). Live proof after apply: the next
  03:30/03:40/03:43 UTC runs must read `succeeded` in cron.job_run_details.
touched_layers_checked:
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "144 drafted; applied only on explicit founder authorization; ledger + live_cron_jobs.json regenerated in the apply commit." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "LIVE cron.job_run_details: jobid 41 failed 5/5 09-22→09-26 (VACUUM in transaction block); pre-141 jobs 35/36 succeeded 15/15 09-06→09-20 as single statements. cron_call_log oldest row 09-14; alert-critical-notify last success 09-22 11:00 ⇒ days_silent 8.8 at 10-01 06:47." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Row counts before fix: cron_call_log 1,429 (oldest 09-14), job_run_details 6,967, client_errors 6,007 (oldest 08-21), usage_counters 27." }
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ change." }
---

# db_maintenance_nightly has failed every night since migration 141

## What happened

Migration 141 folded six maintenance jobs into one. pg_cron runs a
multi-statement command in a single transaction, and `VACUUM` cannot run in
one. So the job failed every night, and the failure rolled back the four
cleanups that ran before it.

## Why nobody saw it

The job is pure SQL. The alerting stack reads `cron_call_log`, which only Edge
Functions write (OI-178). A failing SQL job therefore looks the same as a
healthy one: silent.

## What it was about to cause

Unpruned `cron_call_log` let `alert_cron_function_dead` see 12 days of history
for the first time. `alert-critical-notify`, which only runs when a critical
alert is raised, would have crossed 8 silent days at 2026-10-01 06:47 UTC and
raised a false CRITICAL about itself. That CRITICAL would then trigger the
function and reset its own clock (the loop OI-179 R2-11 predicted).

## Fix

Migration 144: cleanups-only nightly job, the two VACUUMs back as
single-statement jobs, and the trigger-dispatched function excluded from the
dead-function alert. OI-178 (alert on failed SQL jobs) is batch B's next slice.
