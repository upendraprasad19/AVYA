---
bug_id: b1f4e2
date: 2026-05-28
batch: six-industry-gap-closures (follow-up fix during cross-check)
status: fixed
blast_radius: platform
symptom: >
  alert_edge_function_health pg_cron job failed every 15 minutes since
  migration 076 shipped, with "ERROR: column status_code does not exist".
  No edge-function-health alerting was actually running; cron.job_run_details
  showed status=failed for every tick.
concept: alert_detection_edge_function_health
sot_registry_entry: not_applicable (monitoring infra; not a user-data SoT concept)
writers:
  - { file: supabase/migrations/076_alert_detection_crons.sql, line: 75, source: "original (broken) cron body assumed status_code + created_at" }
  - { file: supabase/migrations/077_fix_alert_edge_function_health_columns.sql, line: 1, source: "fix — unschedule + reschedule with http_status + started_at" }
readers:
  - { file: scripts/check_alerts.dart, line: 1, source: "SessionStart hook reads public.alerts (downstream of the cron INSERT)" }
hive_key_prefix: not_applicable (cloud-only cron; no Hive involvement)
hive_key_formula: not_applicable
sync_methods: not_applicable (server-side pg_cron INSERT into public.alerts; no client sync)
restore_methods: not_applicable (alerts are not restored to client)
cloud_table: cron_call_log (read by the cron) + alerts (written by the cron)
cloud_columns: >
  cron_call_log actual columns: id, function_name, started_at, status,
  http_status, request_id, error_summary. Migration 076 wrongly referenced
  status_code (actual: http_status) and created_at (actual: started_at).
contract_test_path: not_applicable (live cron behavior; verified via cron.job_run_details query — source-grep contract test would not catch a column-name mismatch that only fails at runtime against live schema)
ist_handling: not_applicable (cron uses now() - interval windows; no IST date-key bucketing)
provider_invalidations: not_applicable (no client provider involved)
telemetry_op_types: not_applicable (the cron IS the telemetry/alerting path; failures land in cron.job_run_details)
cross_account_guard: not_applicable (alerts table is service-role-only, RLS enforced; no per-user scoping)
forbidden_patterns_checked: >
  Confirmed the corrected query references only columns that exist in
  information_schema.columns for public.cron_call_log (http_status,
  started_at). Verified the other two crons (alert_client_errors_spike →
  client_errors.created_at; alert_payment_flow_health →
  subscriptions.created_at + subscriptions.status) reference real columns —
  both were already succeeding.
proposed_fix: >
  Migration 077 unschedules alert_edge_function_health and reschedules it
  with the corrected column names (http_status, started_at) plus a
  "http_status IS NOT NULL" guard so in-flight/unlogged calls don't inflate
  the error rate. Corrected query was run live against cloud before apply
  (returned total=0, err_rate=null — clean, no calls in the 30-min window).
regression_test_planned: >
  No source-grep test (would not catch a runtime column mismatch). The
  durable guard is process: future cron migrations MUST query
  information_schema.columns for every referenced table BEFORE writing the
  cron body. Codified by linking this diagnose to
  feedback_mistake_fiber_backfill.md (the "assume schema" recurrence class).
  Live verification: cron.job_run_details status for alert_edge_function_health
  flips from failed → succeeded on the next */15 tick post-077.
touched_layers_checked:
  - { tier: "Postgres schema", status: verified, evidence: "information_schema.columns confirmed cron_call_log has http_status + started_at, NOT status_code/created_at" }
  - { tier: "Cron jobs", status: fixed_in_this_batch, evidence: "migration 077 applied (success:true); unschedule + reschedule with corrected columns" }
  - { tier: "Postgres data", status: verified, evidence: "corrected query ran live: total=0, err_rate=null (no rows mis-written; broken cron never INSERTed bad data, it errored out)" }
  - { tier: "Migrations applied", status: fixed_in_this_batch, evidence: "backups/applied_migrations.json +077 entry paired in same commit" }
  - { tier: "Client code", status: not_applicable, evidence: "cloud-only cron; check_alerts.dart reads alerts table unchanged" }
impact_analysis: >
  Severity: low user impact (zero — this is monitoring infra, not a
  user-facing path). Operational impact: edge-function-health alerting was
  silently dead from 076 ship (2026-05-27 ~22:00 IST) until 077
  (2026-05-28). During that window a real Edge Function 5xx spike would NOT
  have raised an alert via this cron — but the app, payments, and AI all
  functioned normally; only the observability signal was missing. The other
  two alert crons (client_errors_spike, payment_flow_health) were
  unaffected. No bad data written (the cron errored before INSERT). Caught
  during post-commit cross-check of cron.job_run_details — validating the
  value of the new incident-playbook detection infra (it caught its own
  wiring bug).
---

# b1f4e2 — alert_edge_function_health cron used non-existent columns

## What happened

Migration 076 (incident playbook Phase 1) created three alert pg_cron
jobs. Two referenced columns that exist; the third,
`alert_edge_function_health`, queried `public.cron_call_log` using
`status_code` and `created_at`. The real schema is `http_status` and
`started_at`. Every 15-minute tick failed with
`ERROR: column "status_code" does not exist` and logged `status=failed`
in `cron.job_run_details`.

## Root cause

Column names were assumed from convention instead of being verified
against `information_schema.columns` before writing the cron body. This
is the recurrence class documented in `feedback_mistake_fiber_backfill.md`
("Query information_schema before cross-table backfills"). The two other
crons happened to use real column names (`created_at` exists on both
`client_errors` and `subscriptions`), which is why only this one broke.

## Why our gates didn't catch it

The migration's SQL is syntactically valid; the column error only
surfaces at runtime when pg_cron executes against the live schema.
Source-grep contract tests can't catch a column-name mismatch that
depends on live DB state. The migration apply (`success:true`) reports
on the DDL (cron.schedule succeeded — it stores the job), not on the
job's future execution. The failure was only visible in
`cron.job_run_details` — which is exactly what the post-commit
cross-check queried. The incident-detection infra caught its own wiring
bug.

## Resolution

Migration 077 unschedules + reschedules the cron with `http_status` +
`started_at` and a `http_status IS NOT NULL` guard. Corrected query
verified live before apply.

## Prevention

Process rule reinforced: any future cron/migration referencing an
existing table MUST verify column names via `information_schema.columns`
first. Linked to `feedback_mistake_fiber_backfill.md`. Phase 2 alert
threshold tuning (2026-06-03) will re-confirm all three crons are
`succeeded` in `cron.job_run_details` as part of the baseline read.

## Linked artifacts

- Migrations: 076 (introduced), 077 (fixed)
- Cron: `alert_edge_function_health`
- Feedback: `feedback_mistake_fiber_backfill.md` (recurrence class)
- Batch: `project_six_industry_gap_closures_2026_05_28.md`
