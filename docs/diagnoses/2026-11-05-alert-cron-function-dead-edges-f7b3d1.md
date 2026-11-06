---
bug_id: f7b3d1
date: 2026-11-05
batch: oi473-cron-dead-alert-edges
status: fixed
blast_radius: platform
symptom: >
  Since migration 169 made alert_cron_function_dead satisfiable (retention 7 -> 10 days), its body (migration 144)
  has three edges that could not matter while it never fired. (1) No per-run cap: an 8-10 day fleet outage inserts up
  to 17 CRITICAL rows in one statement, and trigger 133 dispatches alert-critical-notify once per row. (2) The dedup
  is `acknowledged = false AND detected_at > now() - interval '24 hours'`, so an acknowledged alert re-fires the next
  day and pg_cron start jitter decides whether the 24 h window holds: up to 3 alerts per dead function. (3) The
  exclusion is one hard-coded name; weekly-recalc calls logCronStart but has no cron job (OI-472), so one manual run
  pages CRITICAL 8 days later, and nothing ties the list to function retirement or addition.
concept: >
  An alert's input set (functions that write cron_call_log) must be reconciled with its exclusion list and with the
  schedule that defines which silence is abnormal. The exclusion list had no reader-side check against the writers.
  Same class as feedback_green_check_input_set_width and diagnose c9e2a7 (the alert's input bounded by something it
  did not know about).
sot_registry_entry: >
  None. Cron schedules and bodies are registered in docs/operations/CRON_REGISTRY.md (row 45, updated in this
  batch); the contract is pinned by the tests below. No Hive/cloud writer-reader pair exists for this concept.
writers:
  - { file: supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql, method: "alert_cron_function_dead (alter_job) — the body this batch replaces; INSERT ... SELECT one critical row per dead function, 24 h ack-dependent dedup, single-name exclusion", line: 64 }
  - { file: supabase/migrations/170_oi473_cron_dead_alert_edges.sql, method: "alert_cron_function_dead (alter_job) — CTE body: cap 3 with one summary row, 72 h name dedup, NOT IN exclusion (this fix)", line: 38 }
  - { file: supabase/functions/weekly-recalc/index.ts, method: "logCronStart(\"weekly-recalc\") — writes cron_call_log rows with no cron job behind it", line: 210 }
readers:
  - { file: supabase/migrations/133_alert_critical_notify_trigger.sql, method: "trg_dispatch_critical_alert_notify — AFTER INSERT FOR EACH ROW WHEN severity = 'critical', one net.http_post per row", line: 64 }
  - { file: supabase/functions/alert-critical-notify/index.ts, method: "reads source, summary, detected_at, suggested_action of ONE alerts row; context_json is not read", line: 91 }
  - { file: supabase/functions/_shared/founder_digest_content.ts, method: "renders the day's alerts rows: detected_at, source, severity, summary only", line: 880 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: alerts
cloud_columns: [source, severity, summary, context_json, suggested_action, detected_at, acknowledged]
contract_test_path: test/contracts/cron_call_log_writers_roster_test.dart
recurrence: >
  Same CLASS as c9e2a7 (OI-179: the alert's input set bounded by a pruner it did not know about) and d6b2f9 (the
  trigger-dispatched alert-critical-notify exclusion, which this fix generalises into a tested roster). The jitter
  hazard in edge 2 is the one OI-473 item 2 names, and the first 48 h window proposed here would have moved it, not
  removed it (plan review #1 R1-1). Prior diagnose-docs grepped: c3f8a1 (alert lineage), c9e2a7, d6b2f9, e8b4a1.
  Superseded wording (records stay as history, this doc names them): the "24 h dedup / up to three alerts / pages only
  during days 8-10" text in c9e2a7 (lines 68-69), docs/audit/2026-11-05-hermes-oi179-cron-dead-alert.md:61,
  docs/plans/oi179-cron-dead-alert.md:38 and the immutable header of migration 169.
related_bugs: [c9e2a7, d6b2f9, c3f8a1, e8b4a1]
ist_handling: not_applicable — interval arithmetic on now(); no date key derived.
cross_account_guard: not_applicable — no per-user data path.
provider_invalidations: not_applicable
telemetry_op_types: none — the alerts row is the signal.
forbidden_patterns_checked: >
  No schema change, no new SECURITY DEFINER surface, no schedule change (cron.alter_job by jobname subquery, never a
  numeric id). The summary row has no function_name key; the only reader of that key was the alert's own dedup
  (grep of lib/, supabase/functions/, test/, scripts/, docs/sot_registry.yaml). Migrations 133, 144, 169 are
  immutable and untouched. Telegram is deferred (founder 2026-11-04): the Telegram 429/no-retry half of OI-201 is
  closed as moot, not fixed here. Migration slug avoids rls/security_definer (blast_radius.yaml).
impact_analysis: >
  Nothing is dead today (live read 2026-11-05: every scheduled function succeeded within the last day except
  weekly-recap-ready on 2026-11-01), so the first real firing is not observable; expect 0 rows at the next 06:47 UTC
  run. Worst case after the fix: an 8-10 day fleet outage raises ONE critical summary row and ONE dispatch instead of
  up to 17. ACCEPTED RESIDUALS (stated, not solved): functions scheduled after 06:47 UTC look dead on the first
  morning after an outage (one summary or up to 3 singles); functions crossing the 8-day line on different days raise
  another summary or singles on the second day; a keep-set row (169:40-45) can keep one function visible past day 10
  so it re-fires about every 3 days up to the 14-day lookback; a function retired from the repo pages once before its
  rows leave the table; silence beyond 10 days stays invisible until OI-199's per-function keep-set.
proposed_fix: >
  Migration 170: cron.alter_job by jobname with a data-modifying-CTE body: dead -> fresh (8-day threshold, 72 h
  name dedup that also honours a summary row's function_names array) -> n (count AFTER dedup) -> singles (n <= 3) /
  summary (n > 3), exclusion `NOT IN ('alert-critical-notify', 'weekly-recalc')`. Rejected: suppressing while
  alert_cron_silence is open (couples two alerts' acknowledge states); deriving the exclusion from cron.job text
  (measured: compute-admin-metrics-daily and compute-coach-signals are reached through helper functions
  private.compute_*_function_url(), so a name join silently drops two live functions out of the alert); a 48 h
  window (re-fires on the third visible run about half the time: the alert sees a dead function on 2 or 3 consecutive
  daily runs, ages 8 d to 10 d 3 h 17 m, and run 3 lands at run 1 + 48 h + start jitter; 72 h exceeds the span).
regression_test_planned: >
  test/contracts/cron_call_log_writers_roster_test.dart (writers A, registry B, exclusions C: A subset of B+C, C subset
  of A, B and C disjoint, trigger-dispatched roster subset of C; non-vacuity pins; parsers fixture-tested).
  MUTATIONS, applied and confirmed, restored by cp from backup, 0 diff afterwards: M1 weekly-recalc dropped from
  the list = 2 red; M2 fake writer function = 1 red; M3 stale ghost-fn entry = 1 red; M4 scheduled function excluded
  = 1 red; M5 variable-name caller = 1 red; M6 single-quote support removed from the parser = 2 red; M7
  alert-critical-notify dropped = 3 red; M8 NOT IN replaced by <> (parse empties) = 3 red. A first M1/M7 run
  SURVIVED because the anchor hit the migration's header comment, which the helper strips; re-anchored on the body
  line, both red. test/contracts/alert_cron_function_dead_rehearsal_sync_test.dart pins the rehearsal's embedded body
  and its md5 to the migration byte for byte (2 mutants red: a drifted copy, a stale md5).
  Behavioural: test/sql/alert_cron_function_dead_edges_live_verify.sql (13 cases + md5), run in a LOCAL docker
  Postgres (supabase/postgres 17.6.1.084, container oi473-pgtest, minimal alerts + cron_call_log tables, no-op
  stand-in for trigger 133), never against production. OLD (144) body, re-run on the final 13-case rehearsal: 6 of 13 cases red (a, c, f, g, i, j1 = the
  storm, acknowledgement re-fire, weekly-recalc, summary dedup, 72 h window) and 7 pass as a control (b, d, e, h, j2, k1, k2);
  its embedded md5 equals the live cron.job md5 bb2108a12cf313fa5cb4ee8c7f8d9398. NEW body: 13 of 13 + md5 ok.
  SQL mutants on the new body: S1 cap 3 -> 4 = c red; S2 summary arm > 4 = c red; S3 window 48 h = j1 red; S4
  weekly-recalc dropped = g red; S5 function_names branch dropped = e, f, i red; S7 threshold 9 = k1 red (it SURVIVED
  until the 8.2 d / 7.9 d edge cases were added); S8 acknowledged = false re-added = f red; S10 alert-critical-notify
  dropped = g red. S6 (count before dedup) and S9 (summary arm unconditional) abort with a runtime NOT NULL violation
  on alerts.summary, which is a real failure of the mutated SQL, not a compile error, but they are caught by an
  abort rather than by a named case.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ change." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "alerts columns/constraints read from migration 076 (source, severity CHECK info|warn|critical, summary NOT NULL, context_json jsonb NOT NULL default '{}', acknowledged); cron_call_log from 068 (function_name, started_at, status). No column change." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live read-only 2026-11-05: SELECT DISTINCT function_name from cron_call_log = 17 names with last success per function; cron.job md5 of alert_cron_function_dead = bb2108a12cf313fa5cb4ee8c7f8d9398 = md5 of migration 144's body; 0 alert_cron_function_dead rows; cron_call_log 542 rows, oldest 2026-10-29." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "Live cron.job read: compute_admin_metrics_daily and compute_coach_signals call private.compute_*_function_url() (no function name in the command), so a cron.job text join would drop both; the schedule of alert_cron_function_dead (47 6 * * *) is not touched." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Readers of alerts rows for this source (founder-digest, alert-critical-notify, admin-dashboard-data, scripts/check_alerts.dart, telegram-admin-bot) select source/severity/summary/suggested_action, never context_json->>'function_name'; a summary row with no function_name key breaks none." }
---

# alert_cron_function_dead: storm, duplicate alerts and a hard-coded exclusion list

## What happened

Migration 169 raised `cron_call_log` retention to 10 days, so `alert_cron_function_dead` can fire for the first time.
Its body (migration 144) then had three edges that were harmless while it never fired: a CRITICAL row per dead
function with no cap, a dedup that depends on acknowledgement and on scheduling jitter, and an exclusion list that is
one hard-coded name.

## The fix

One `cron.alter_job` (migration 170): more than 3 new dead functions raise one summary row instead of one each; the
dedup is 72 hours on the function name, independent of acknowledgement, and honours a summary row's
`function_names`; the exclusion becomes `NOT IN ('alert-critical-notify', 'weekly-recalc')` and a roster test ties
the list to the writers of `cron_call_log` and to the schedule table in `CRON_REGISTRY.md`.

## Apply state

Applied to production 2026-11-06 through MCP `execute_sql` in `BEGIN` with `lock_timeout = '3s'` and `statement_timeout = '60s'`, after the founder's explicit go. Verified live afterwards: `md5(cron.job.command)` = `f890669f0389e0febd5976ee0185c9f1`, equal to the md5 of the migration body between the dollar tags (before: `bb2108a12cf313fa5cb4ee8c7f8d9398`, the 144 body); schedule `47 6 * * *` and `active` unchanged. The first real observation is the next 06:47 UTC run, which should insert 0 rows.

## Not done, on purpose

The Telegram 429 / no-retry half of OI-201 is closed as moot while Telegram is deferred. Silence beyond 10 days is
OI-199. The rehearsal ran locally, not on production: a first attempt on production hung without finishing (cause not
established; the script took a table lock with no timeout) and left no trace in the database.
