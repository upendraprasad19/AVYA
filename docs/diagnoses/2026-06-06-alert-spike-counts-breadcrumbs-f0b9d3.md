---
bug_id: f0b9d3
date: 2026-06-06
batch: alert-tuning-2026-06-06
status: fixed
blast_radius: platform
symptom: >
  The alert_client_errors_spike cron paged critical for benign volume. Alert #24
  fired "client_errors spike: 354 rows in last hour" (critical) for what was the
  founder's own reinstall/restore burst on the old +28 APK — a single device.
  The cron counted ALL client_errors rows with no filter, but ~81.5% of rows
  over 10 days were error_code 'event'/'info' telemetry breadcrumbs (restore /
  sync progress logs), not failures. Combined with placeholder-low thresholds
  (20/50/100 from migration 076), every reinstall or sim run tripped a false
  critical.
concept: alert_threshold_tuning
sot_registry_entry: n/a (observability cron consuming a client_errors aggregate — adds no new writer/reader field contract)
writers: >
  The pg_cron job alert_client_errors_spike — was defined in
  supabase/migrations/076_alert_detection_crons.sql, now re-scheduled by
  supabase/migrations/086_alert_client_errors_spike_tune.sql. It runs every 15
  minutes and INSERTs a row into public.alerts when the hourly client_errors
  count crosses a threshold. The documented thresholds live in
  alerts/_thresholds.yaml but are NOT the runtime source of truth; the runtime
  values are embedded in the cron SQL and must be hand-mirrored via a paired
  migration (cron.unschedule + cron.schedule).
readers: >
  The SessionStart hook (scripts/check_alerts.dart, wired in .claude/settings.json)
  reads unacknowledged alerts and surfaces them to the founder at session start;
  the founder triages them in natural language. No client app code reads the
  alerts table — it is RLS service-role only (migration 076).
hive_key_prefix: not_applicable (server-side pg_cron alert; nothing written to Hive)
hive_key_formula: not_applicable (alert rows live in the Postgres alerts table)
sync_methods: not_applicable (no client sync path; cron writes alerts directly)
restore_methods: not_applicable (no restore path involved)
cloud_table: alerts (written by the cron) / client_errors (the aggregate read source)
cloud_columns: alerts.severity, alerts.summary, alerts.context_json.count, alerts.context_json.excludes
contract_test_path: test/contracts/alert_thresholds_sync_test.dart
ist_handling: not_applicable (the cron window is a rolling now()-1 hour interval; no IST date-keying or counter reset)
provider_invalidations: not_applicable (no Riverpod providers; server-side cron)
telemetry_op_types: alert_client_errors_spike (alerts.source); excluded breadcrumb codes = event, info
cross_account_guard: not_applicable (alerts is service-role-only RLS per migration 076; the count is an intentional all-user aggregate)
forbidden_patterns_checked:
  - "the bare unfiltered COUNT(*) over client_errors that counted telemetry breadcrumbs as errors — removed; 086 filters error_code IS DISTINCT FROM 'event' and 'info', and the contract test asserts the exclusion is present."
  - "alerts/_thresholds.yaml silently drifting from the cron SQL — now pinned by alert_thresholds_sync_test.dart (the yaml numbers must equal the migration CASE/floor numbers, and the yaml names its defining migration)."
proposed_fix: >
  (1) Migration 086 re-schedules alert_client_errors_spike to exclude
  error_code 'event'/'info' breadcrumbs from the hourly count. (2) Thresholds
  raised 20/50/100 to 100/250/500 (founder-chosen Tolerant tier; real-error
  baseline p95=127/hr, max=161 — a ~150-row reinstall burst lands at info, not
  critical). (3) alerts/_thresholds.yaml updated in the same commit (phase 2 +
  the new numbers + excludes_error_codes + a defined_in_migration pointer),
  keeping the doc-is-not-source-of-truth contract. (4) New contract test pins
  the yaml-to-migration agreement AND the breadcrumb exclusion. (5) The missing
  Phase-2 baseline doc docs/audit/2026-06-03-alert-baseline.md was written with
  the data, the decision, and the rejected transient-denylist (evidence: the
  same logical error appears under multiple error_codes, so a code/string
  denylist in SQL would be leaky).
regression_test_planned: >
  test/contracts/alert_thresholds_sync_test.dart — asserts (a) the yaml
  client_errors_spike info/warn/critical equal the migration cnt gates
  (100/250/500); (b) the migration count query contains the event + info
  exclusion. RED against the old unfiltered 076 body (20/50/100, no exclusion),
  GREEN against 086.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: not_applicable, evidence: "server-side pg_cron + config only; no Flutter code path changed" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "read-only live count over the last 24h — old bare count 645 vs breadcrumb-excluded 264 (59 percent were event/info); the 10-day window is 4258 rows / 3472 (81.5 percent) breadcrumbs across 2 distinct users" }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "086 applied live via MCP apply_migration (user-authorized 2026-06-06); recorded in backups/applied_migrations.json with hash f4f5e88b" }
  - { tier: 7, layer: cron_jobs, status: fixed_in_this_batch, evidence: "cron.job for alert_client_errors_spike verified post-apply: breadcrumb exclusion present, new thresholds 500/250/100 present, old 20/50 gates gone, schedule */15 unchanged" }
impact_analysis: >
  Platform / observability blast radius — no user-facing change. Before: every
  founder reinstall/restore or sim run tripped a false critical (alert #24 =
  354) because the cron counted ~81.5 percent breadcrumb telemetry as errors and
  used placeholder thresholds. After: the cron counts only real errors and pages
  at the Tolerant tier (info 100 / warn 250 / critical 500), so a ~150-row
  reinstall burst is silent while a genuine fleet-scale regression still fires.
  The yaml-to-migration drift risk (previously untested) is now pinned by a
  contract test. Follow-ups (flagged, not in this batch): revisit thresholds
  with per-user normalization once real DAU grows; a cheap client-side fix to
  stop logging RealtimeSubscribeException with WebSocket close code 1000 (a
  normal closure) as an error would cut the weight_logs reconnect churn at the
  source.
---

# client_errors spike alert counted telemetry breadcrumbs as errors

## What happened
Alert #24 paged **critical** — "client_errors spike: 354 rows in last hour" — at
07:15 UTC on 2026-06-06. Triage showed every row was `client_version 1.0.0+28`
(the old installed APK) and `user_id d7a67a37` (the founder), i.e. his own
reinstall→restore burst, not a fleet regression.

## Root cause
The `alert_client_errors_spike` cron (migration `076_alert_detection_crons.sql`)
ran a bare `COUNT(*) FROM client_errors WHERE created_at > now()-interval '1 hour'`
with **no filter**. But `client_errors` is a dual-purpose sink: over the last 10
days **3,472 of 4,258 rows (81.5%)** are `error_code='event'`/`'info'` telemetry
breadcrumbs (restore/sync progress logs), not failures. So the alert was mostly
counting telemetry, and the placeholder thresholds (20/50/100) made every
reinstall or sim run a false critical.

A secondary defect: `alerts/_thresholds.yaml` documents the thresholds but is
**not** the runtime source of truth (the values are embedded in the cron SQL),
and **no test pinned the two together** — a silent-drift vector.

## Fix
Migration **086** re-schedules the one cron to (1) exclude `error_code` `'event'`
and `'info'` from the count and (2) raise thresholds to the founder-chosen
**Tolerant** tier **100 / 250 / 500** (real-error baseline p95=127/hr). The yaml
is updated in the same commit (phase 2, new numbers, `excludes_error_codes`, a
`defined_in_migration` pointer). A new contract test
(`alert_thresholds_sync_test.dart`) pins the yaml↔migration agreement and the
breadcrumb exclusion. The missing Phase-2 baseline is captured at
`docs/audit/2026-06-03-alert-baseline.md`.

The other two crons (`alert_edge_function_health`, `alert_payment_flow_health`)
were left untouched.

## Verification
- Live read-only count: old bare 24h count **645** vs breadcrumb-excluded **264**.
- Post-apply `cron.job` body verified: exclusion present, thresholds 500/250/100,
  old 20/50 gates gone, schedule `*/15` unchanged.
- `alert_thresholds_sync_test.dart` green; full suite green.

## See also
- supabase/migrations/086_alert_client_errors_spike_tune.sql
- docs/audit/2026-06-03-alert-baseline.md (baseline data + rejected denylist)
- alerts/_thresholds.yaml (documented thresholds + the doc-is-not-SoT contract)
