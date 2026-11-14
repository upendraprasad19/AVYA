---
bug_id: f7a3d2
date: 2026-09-26
batch: ops-alerting-b2a (B2a-1b — OI-178, second half)
status: fixed
blast_radius: platform
symptom: >
  A pg_cron job that stops being launched, or is switched off with the
  documented kill switch (`cron.job.active = false`), writes no run row at all,
  and nothing raises an alert. On 2026-09-21 two hourly alert jobs,
  alert_payment_flow_health and alert_cron_silence, were not launched for 5
  hours (12:07/12:17 → 17:07/17:17 UTC, DB saturation e8b4a1). Nothing reported
  it: the jobs that would have alerted were the ones not running.
concept: >
  Migration 145 (b4c8e2) reads cron.job_run_details for runs that FAILED. A job
  that is never launched produces no row there, so 145 cannot see it. OI-178's
  class line names exactly this: "a failing job and a job that never ran are
  the same observation here: nothing". Nothing read cron.job's schedule or
  active flag against run history.
sot_registry_entry: >
  None. Cron scheduling is registered in docs/operations/CRON_REGISTRY.md
  (Gate 31), and the alert in alerts/_thresholds.yaml. No Hive/cloud
  writer-reader field pair is involved.
writers:
  - { file: supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql, method: "every pg_cron job — on each LAUNCH pg_cron itself writes one cron.job_run_details row; a non-launch writes nothing (the absence is the signal)", line: 40 }
  - { file: supabase/migrations/146_alert_cron_job_silent.sql, method: "new job alert_cron_job_silent — INSERTs ONE aggregated public.alerts row per run when any job is overdue or deactivated", line: 73 }
readers:
  - { file: supabase/migrations/145_alert_sql_job_failures.sql, method: "alert_sql_job_failures — reads only status='failed' rows, so it is structurally blind to a job with NO row", line: 93 }
  - { file: supabase/migrations/146_alert_cron_job_silent.sql, method: "the new reader: cron.job (schedule, active) + max(cron.job_run_details.start_time) per job", line: 111 }
  - { file: supabase/migrations/133_alert_critical_notify_trigger.sql, method: "trg_dispatch_critical_alert_notify — pages via Telegram on severity='critical' only", line: 62 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: cron.job
cloud_columns: [jobid, jobname, schedule, active]
contract_test_path: test/contracts/alert_cron_job_silent_test.dart
recurrence: >
  Not a recurrence of a recorded diagnose-doc (INDEX grepped for silent /
  not launched / active = false / OI-178: only b4c8e2, this batch's first
  half). It is the same "absence of a row reads as health" family as
  OI-179 (alert_cron_function_dead) and `feedback_bad_news_vs_no_news`.
related_bugs: [b4c8e2, d6b2f9, e8b4a1]
ist_handling: not_applicable — the comparison is a relative interval on timestamptz; no date key.
cross_account_guard: not_applicable — no per-user data path.
provider_invalidations: not_applicable
telemetry_op_types: none — writes public.alerts rows with source 'alert_cron_job_silent'.
forbidden_patterns_checked: >
  No SECURITY DEFINER (tier platform, classified on the written file). One
  statement per cron command (d6b2f9). No DDL on existing objects; the only
  data written is the alert row. The idempotency guard unschedules by jobid
  (OI-193 / 145 R2 P2-2), and the rollback comment's name is unquoted.
impact_analysis: >
  The expected gap is derived from the job's SCHEDULE. The fields are checked
  in this order, first match wins, so each branch gives a gap ≥ the real one
  for every schedule it catches (R1 P1: with day-of-week tested before month,
  a yearly or quarterly job would false-page at about 39 d):
  - month set → 366 d;
  - day-of-week set → 7 d;
  - day-of-month set → 62 d (29–31 only occur in some months);
  - hour set → 1 d;
  - `*/N` minutes → N min;
  - otherwise → 1 h;
  - @macros are mapped, and any other shape is not judged.
  It is not derived from run history, because cleanup_cron_job_run_details
  keeps 14 d and spares only each job's newest run. A weekly job's previous
  run is pruned before a history-based threshold could ever be reached, while
  the newest run always survives, so "last launched" is always known. (A
  history-based first draft was replayed and rejected for that reason; it also
  false-flagged the windowed morning_alert_deliver_* jobs in their first week.)
  Replayed over all retained run history (09-06 → 09-26, every gap between
  consecutive launches, all active jobs), the rule flags exactly 2 gaps. Both
  are real: the 5 h non-launch of alert_payment_flow_health and
  alert_cron_silence on 2026-09-21. The final SELECT evaluated read-only at
  2026-09-21 16:33 returns one critical naming both; at 18:33 and at now() it
  returns nothing. It would first have fired at 14:33 UTC that day (12:07 +
  2.25 h = 14:22, and 12:17 + 2.25 h = 14:32; the next :33 run is 14:33),
  with the 23 h dedup then holding it to that one page. No job is inactive
  today.
  Thresholds: daily 31 h, hourly 2.25 h, */30 1.6 h, weekly 8.75 d.
  Residuals, stated:
  (1) a job that has never been launched (no row at all) is not judged, since
      cron.job has no creation time. Today that is jrd_vacuum_daily and
      client_errors_vacuum_daily until their first run at 03:40/03:43 UTC.
  (2) If THIS job stops running, it cannot say so; 145's job sees it only if
      it fails. The two partly cover each other: this job sees 145's job go
      silent, and 145 sees this job fail. A whole-scheduler stop, or all jobs
      stopping together, is seen by neither. Both also depend on
      `cron.log_run = on`. All of this is filed as OI-250 (an out-of-band
      heartbeat).
  (3) Schedules are judged conservatively: the expected gap is longer, never
      shorter. A list or range in the minute field of an hourly schedule is
      judged as hourly, and a weekday-only schedule (`* * * * 1-5`) is judged
      at 7 d.
  (3b) A job whose run is still going past its threshold is reported as
      silent. Its last status is printed in the alert's `why`
      (`… UTC (running), schedule …`), so the reader can tell a hung run from
      one that was never launched.
  (4) OI-178's third aggravation, `return_message = "1 row"` hiding a
      retention job's real DELETE count, is not a failure and not a silence.
      With 145 and 146 in place, manual inspection of return_message is no
      longer the fallback it once was. The deletion volume itself stays
      unobserved; it is filed as OI-251.
proposed_fix: >
  Migration 146 schedules alert_cron_job_silent at `33 * * * *`, as a single
  INSERT…SELECT. SILENT jobs (active, launched before, overdue by
  expected × 1.25 + 1 h) → critical; INACTIVE jobs (active = false) → warn.
  It raises one aggregated row.
  Dedup:
  - critical: an unacknowledged critical in the last 23 h that already names
    every silent job;
  - warn: any warn in the last 7 d that names every inactive job, so a
    deliberately disabled job is re-surfaced weekly, not hourly.
regression_test_planned: >
  test/contracts/alert_cron_job_silent_test.dart (7 tests) reads the latest
  definition through the shared test/helpers/cron_job_body_reader.dart
  (schedule or alter_job, any dollar tag; it throws on an unparseable or
  retiring migration). It pins:
  - one statement;
  - aggregation;
  - the inactive arm and the severity CASE;
  - every schedule-field mapping and the not-judged NULL;
  - the overdue predicate, including that a failed launch still counts;
  - both dedup branches and the keys they read;
  - the field ORDER, as one ordered string;
  - the last status shown in `why`;
  - yaml↔SQL agreement (migration, cadence, factor, grace, both dedup windows).
  MUTATIONS were applied with an apply-check, and restored by cp with both
  sha256s re-checked. Each of the 18 reddened ≥1 test:
  - inactive arm → false: 1
  - weekly → 1 d: 1
  - hour field ignored: 1
  - unknown shape judged as 1 h: 1
  - no grace hour: 2
  - last launch = succeeded runs only: 2
  - never-launched judged: 1
  - critical dedup counting acknowledged alerts: 1
  - critical containment dropped: 1
  - warn dedup 7 d → 23 h: 1
  - always critical: 1
  - GROUP BY: 1
  - a second statement: 1
  - yaml factor drift: 1
  - yaml cadence drift: 1
  - old order (dow before month, dom|month → 31 d): 1
  - dom 62 d → 31 d: 1
  - last status dropped from `why`: 1
  Through the shared helper, a later migration that alters any job by numeric
  id reddens 2 (both alert tests), and a later `UPDATE cron.job` naming 146
  reddens 1.
  R2 (146 R2 P3-2) found 3 survivors, now pinned and re-proven, each 1 red:
  dead warn path (`NOT j.active AND false`), silent_jobs filtered on
  'inactive' (NULL key, hourly page storm), last status ASC. The new
  not-judged arms (day-field AND semantics, month + day 29–31) each redden 1
  when dropped, and the helper's `job_id => N` form reddens 2.
  R2 P2-1 residual: re-enabling a job or shortening its schedule pages ONE
  false critical (cron.job has no timestamps); stated in the header and in
  both suggested_actions.
  Also through the shared helper, a later tagged alter_job gutting 145 reddens 7,
  and a later retirement of 146 by jobid fails the run.
  R3 (independent reviewer) re-verified all 6 R2 fixes from scratch, including
  re-running the 3 P3-2 mutations itself with its own restore+sha256 cycle;
  0 new material findings.
  B-pass found 1 P1 (dedup, guard_without_its_mirror) + 2 P2 (citation drift;
  a factual error) + 1 P3 (registry formatting), all fixed same-batch:
  - P1: the top-level OR joining the critical/warn dedup branches was
    unpinned — each branch's substring assertion survives an OR→AND mutation
    (both blocks stay literally present), which makes `x.severity = a.severity
    AND (critical-branch AND warn-branch)` unsatisfiable for any row and
    disables dedup for BOTH severities (page-storm). New assertion pins the
    boundary text itself; dropping OR now reddens.
  - P2: this doc's own writers[1]/readers[1] line citations onto 146.sql had
    drifted (14 lines) across the R1-R3 header growth — fixed above.
  - P2: "14 jobs failed within 7 hours" was wrong (live: 14h44m, two clusters
    01:46-04:41 and 14:28-15:39 UTC) — fixed in 145.sql's header, b4c8e2, and
    the plan doc.
  - P3: CRON_REGISTRY.md's new 145/146 rows show genuine IST conversion with
    no qualifier, next to older hourly rows that show raw UTC mislabeled
    "UTC" in the IST column (076/109, pre-existing, out of scope) — clarified.
  Live proof after apply: the next :33 run reads 'succeeded'.
touched_layers_checked:
  - { tier: 7, name: cron_jobs, status: verified, evidence: "LIVE cron.job: 26 active (24 launched at least once + 2 never-run vacuum jobs from 144), 0 inactive. cron.job_run_details: 7,010 rows (bulk from 09-06; the newest run per job is spared, so the oldest is 04-11); cleanup_cron_job_run_details keeps 14 d + newest run per job. Gap replay over all history: 2 flags (09-21 12:07 alert_payment_flow_health 5.0 h, 09-21 12:17 alert_cron_silence 5.0 h). Final SELECT at 2026-09-21 16:33 → 1 critical naming both; at 18:33 and now() → 0 rows." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "146 drafted; it is applied only on explicit founder authorization, together with 145, and the ledger + live_cron_jobs.json are regenerated in the apply commit." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "public.alerts: summary NOT NULL, severity CHECK in (info,warn,critical), acknowledged NOT NULL default false; trigger 133 pages on critical only." }
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ change." }
---

# A cron job that stops running was invisible

## What happened

On 2026-09-21 two hourly alert jobs were not launched for five hours while the
database was saturated, and nothing said so. A job that is never launched, or
is switched off with `active = false`, leaves no run row, and every alert,
including migration 145's new one, reads run rows.

## Fix

Migration 146 adds one hourly job, `alert_cron_job_silent`. It compares each
active job's last launch with how often its schedule says it should run:

- **critical** (Telegram page) when a job is overdue, for example more than
  31 h for a daily job or about 2 h for an hourly one;
- **warn** when a job is switched off.

Over all the run history we keep, it would have fired exactly once: during
that five-hour outage on 09-21.
