---
bug_id: b4c8e2
date: 2026-09-26
batch: ops-alerting-b2a (B2a-1 — OI-178)
status: fixed
blast_radius: platform
symptom: >
  A pure-SQL pg_cron job can fail on every run and nothing raises an alert.
  db_maintenance_nightly (jobid 41) failed 5 of 5 nights, 2026-09-22 → 09-26,
  and it was found by hand while planning batch B (diagnose d6b2f9), not by
  any alert. On 2026-09-21, 14 jobs failed in two clusters spanning
  01:46-16:30 UTC (the DB saturation in e8b4a1). That was also invisible to
  the alert pipeline.
concept: >
  The alerting stack reads public.cron_call_log (alert_cron_failures,
  alert_cron_silence, alert_cron_function_dead). Only Edge Functions write that
  table, through _shared/cron_telemetry.ts. A pg_cron job whose command is SQL
  never calls an EF, so its only run record is the one pg_cron writes itself,
  cron.job_run_details, and before this batch no alert read that table. The
  failure path had a writer and no reader.
sot_registry_entry: >
  None. Cron scheduling is registered in docs/operations/CRON_REGISTRY.md
  (Gate 31), and the alert in alerts/_thresholds.yaml. No Hive/cloud
  writer-reader field pair is involved.
writers:
  - { file: supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql, method: "SQL-only cron jobs (db_maintenance_nightly and the VACUUM jobs); on each run pg_cron itself writes the status='failed' row to cron.job_run_details", line: 40 }
  - { file: supabase/migrations/145_alert_sql_job_failures.sql, method: "new job alert_sql_job_failures — INSERTs ONE aggregated public.alerts row per run when any run failed in the last 65 min", line: 51 }
readers:
  - { file: supabase/migrations/143_restore_alert_cron_failures_stuck_job_bound.sql, method: "alert_cron_failures — reads only public.cron_call_log (the EF-written table), so it is structurally blind to SQL jobs", line: 74 }
  - { file: supabase/migrations/145_alert_sql_job_failures.sql, method: "the new reader of cron.job_run_details (status='failed', coalesce(end_time, start_time) > now()-65 min, LEFT JOIN cron.job)", line: 90 }
  - { file: supabase/migrations/133_alert_critical_notify_trigger.sql, method: "trg_dispatch_critical_alert_notify — pages via Telegram on severity='critical' only, so the severity grading decides who gets paged", line: 62 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: cron.job_run_details
cloud_columns: [jobid, status, start_time, end_time, return_message]
contract_test_path: test/contracts/alert_sql_job_failures_test.dart
recurrence: >
  Not a recurrence of a recorded diagnose-doc. Grepping INDEX.md for
  job_run_details / SQL cron / OI-178 found no prior fix. It is the reason
  d6b2f9 stayed silent for 5 days, and it belongs to the same "a failure with
  no reader" family as the stuck-job branch of alert_cron_failures (140/143).
related_bugs: [d6b2f9, e8b4a1]
ist_handling: not_applicable — the window is a relative interval on timestamptz, not a date key.
cross_account_guard: not_applicable — no per-user data path.
provider_invalidations: not_applicable
telemetry_op_types: none — writes public.alerts rows with source 'alert_sql_job_failures'.
forbidden_patterns_checked: >
  No SECURITY DEFINER (tier platform, classified on the written file). One
  statement per cron command (d6b2f9's lesson, pinned). No DDL on existing
  objects. The only data it writes is the alert row. The rollback comment
  carries the name unquoted (OI-193 convention, since Gate 31 scans raw text).
impact_analysis: >
  Replayed at every hourly :23 check over the last 30 days (read-only,
  against live cron.job_run_details, dedup simulated with every alert left
  unacknowledged), the job raises 5 criticals, one per night for jobid 41's
  real VACUUM failures starting on night one, and 4 warns, one per DB
  saturation episode (capacity failures only). The per-job design from the
  first draft would have sent about 35 Telegram pages over the same period,
  14 of them on 2026-09-21 alone.
  The window keys on END time: a run's row reads 'failed' only once it ends.
  18 of 100 failed runs in 30 d ran longer than 5 min (max 1h09m), and a start_time
  window left 9 of 100 failed rows invisible to every check (plan-review R2
  P1-1).
  Dedup is per SEVERITY, 23 h, so an open warn cannot suppress a later
  critical. For critical it additionally requires that the open alert already
  names every job now failing with a REAL error (context key `sql_jobs`;
  capacity-only jobs excluded), so a NEW real failure pages even while an
  older critical is open (R2 P2-4), and a saturation storm's shifting mix of
  timed-out jobs cannot re-page a critical hourly (R3 P2-1: the first version
  compared the mixed `jobs` set, which could do both wrongs). 23 h rather than 24 h because a nightly failure
  is checked ~24 h apart, and a 24 h window pages on random nights (R2 P3-5).
  Acknowledging re-arms it (SQL in alerts/_thresholds.yaml `acknowledge_sql`).
  50 failed rows in that window belong to jobids that no longer exist in
  cron.job, so the query uses LEFT JOIN + coalesce: with an INNER JOIN those
  failures would be dropped, and with a NULL jobname the NOT NULL summary
  would make the INSERT itself fail every hour.
  The idempotency guard unschedules BY JOBID. A quoted-name unschedule is
  read by Gate 31's raw-text scan as "job removed" (OI-193) and would have
  hidden the job from the registry gate (R2 P2-2).
  Residuals, stated:
  (1) if this job itself fails on every run, it cannot report that
      (alert_cron_silence and ops_alerts are separate jobs and are unaffected);
  (2) the capacity class is a text match on pg_cron's own messages. A new
      capacity-type text would page as critical, and dedup caps that at once
      a night;
  (3) the window overlap is 5 min, so if this job starts > 5 min late or its
      own run fails, failures that ENDED in the gap are never scanned, and one
      ending inside the overlap is seen twice (absorbed by dedup unless
      acknowledged in between; R3 P3-3/P3-4);
  (4) a job that is DEACTIVATED or stops being launched writes no run row and
      is invisible to this alert. That is the other half of OI-178, which
      stays OPEN until the job-silence alert (B2a-1b, same session) lands.
proposed_fix: >
  Migration 145 schedules alert_sql_job_failures at `23 * * * *`, as a single
  INSERT…SELECT that reads cron.job_run_details (window on
  coalesce(end_time, start_time)) and aggregates every failed run into one
  row. Severity is 'critical' if any failure is outside the capacity class
  (job startup timeout / connection failed / remaining connection slots /
  server restarted / could not connect), otherwise 'warn'. Dedup is described
  above.
  Rejected:
  - one alert per failing job (plan-review R1 P1-2: page storm, NULL jobname,
    and dedup that breaks across reschedules);
  - teaching SQL jobs to write cron_call_log (that would touch every job, and a
    job that fails before its logging statement records nothing);
  - job-set dedup for warn too (replayed: 13 warns instead of 4, because a
    capacity burst's mix of timed-out jobs shifts every hour).
regression_test_planned: >
  test/contracts/alert_sql_job_failures_test.dart has 8 tests. It extracts
  the comment-stripped body of the LATEST migration that schedules OR
  alter_jobs the job, under any dollar-quote tag, and fails loudly if a
  migration mentions the job next to a cron call it cannot parse (R2 P3-7).
  It pins:
  - reads job_run_details status='failed';
  - the end-time window;
  - ONE statement (string literals are stripped before splitting on ';',
    because the suggested_action text contains one);
  - aggregated (HAVING, no GROUP BY);
  - the capacity regex and the warn/critical CASE;
  - LEFT JOIN plus both coalesces;
  - the full dedup: NOT EXISTS, source, acknowledged, severity, the critical
    `sql_jobs` containment and its FILTER, 23 h, and that the INSERT writes
    the `sql_jobs` key the dedup reads;
  - the yaml entry agrees with the SQL: migration file, cadence, window and
    dedup hours (R2 P2-3).
  MUTATIONS were applied with an apply-check, and restored by cp with both
  sha256s re-checked. 19 mutations; every one reddened at least one test, and
  the Dart file was never mutated, so none can be a compile error:
  - NOT EXISTS→EXISTS: 1
  - 65 min→65 days: 2
  - end_time→start_time window: 1
  - 23 h→24 h: 2
  - critical job-set containment → true: 1
  - containment on the mixed `jobs` set instead of `sql_jobs`: 1
  - the `sql_jobs` FILTER dropped: 1
  - `sql_jobs` not written to context_json: 1
  - severity dedup deleted: 1
  - LEFT JOIN→JOIN: 1
  - a second statement: 1
  - GROUP BY added: 1
  - CASE → always critical: 1
  - capacity class narrowed: 1
  - yaml cadence drift: 1
  - yaml dedup-hours drift: 1
  - a later migration alter_jobs the job with a gutted `$cmd$` body: 7
  - a later migration with an unparseable cron call, or one retiring the job
    by jobid: the setUpAll guard fails, which fails the run.
  A first run failed 1 of 7 on the naive `;` split. That was the TEST being
  wrong about the literal, not the migration.
  Live proof after apply: the next :23 run reads 'succeeded' in
  cron.job_run_details.
touched_layers_checked:
  - { tier: 7, name: cron_jobs, status: verified, evidence: "LIVE cron.job_run_details 30 d: jobid 41 failed 5/5 09-22→09-26; 14 jobs failed 09-21 (startup timeout); 50 failed rows whose jobid is absent from cron.job. The final SELECT was run read-only over a 30-day window (1 critical row; the aggregate + dedup parse and execute) and hourly over 30 d (5 critical + 4 warn after dedup). 100 failed runs in 30 d with 2 distinct return_message texts (job startup timeout 95; VACUUM in transaction block 5); 101 all-time (the 101st: jobid 25 `column "status_code" does not exist`, 2026-05-28); longest failed run 1h09m." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "145 drafted; it is applied only on explicit founder authorization, and the ledger + live_cron_jobs.json are regenerated in the apply commit." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "public.alerts: summary NOT NULL, severity CHECK in (info,warn,critical); trigger trg_dispatch_critical_alert_notify (133) fires on critical only." }
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ change." }
---

# SQL cron jobs could fail and nothing would alert

## What happened

`db_maintenance_nightly` failed five nights in a row, and no alert said so.
Every existing cron alert reads `cron_call_log`, which only Edge Functions
write. A pure-SQL job's run record exists only in `cron.job_run_details`, and
nothing read that table.

## Fix

Migration 145 adds one hourly job, `alert_sql_job_failures`, that reads
`cron.job_run_details` directly and raises at most one alert per run:

- **critical** (Telegram page) if any failure is a real error;
- **warn** if every failure is a pg_cron capacity failure (such as `job
  startup timeout`), which points at DB capacity rather than a SQL bug.

It looks at runs that *ended* in the last 65 minutes, because a run is only
marked failed once it ends. Over the last 30 days that would have paged 5
times, once each night for the real failure, starting on the first bad night,
plus 4 non-paging warnings. A new failing job always pages, even while an
older alert is still open.
