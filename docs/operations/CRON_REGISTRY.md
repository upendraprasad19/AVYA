# Cron Job Registry

> Single source of truth for every active `pg_cron` job. Tech-debt audit
> 2026-05-20 finding I5 — was previously scattered across 10 migration
> files with no central inventory. `morning_alert_deliver_early` (jobid 17)
> broke silently for days before founder noticed.
>
> **Gate:** `scripts/check_cron_registry.dart` — fails when a `cron.schedule(...)`
> call in any `supabase/migrations/*.sql` is not listed here.
>
> **Lens precedent:** L45 (cron-registry-parity).
>
> **Note on accuracy:** This file lists the cron names declared in
> migrations. Active state (jobid, last run, success/failure) lives in
> `cron.job` + `cron.job_run_details` in Postgres. To check actual state:
> ```sql
> SELECT jobname, schedule, last_run_at FROM cron.job ORDER BY jobid;
> SELECT * FROM cron.job_run_details WHERE return_message <> 'success' ORDER BY end_time DESC LIMIT 20;
> ```

## Active jobs (declared by migration)

| Migration | Job name (jobid) | Cadence UTC | Cadence IST | Function | Vault dep | Notes |
|---|---|---|---|---|---|---|
| 015 | `morning_alert_generate` (5) | `30 20 * * *` | 02:00 | `morning-alert` (generate) | `cron_secret` | Builds the personalised morning payload |
| 065 | `promote_community_item_daily` (7) | `30 20 * * *` | 02:00 | `promote-community-item` | `cron_secret` | **Never succeeded before 2026-07-26** — used `current_setting('app.settings.service_role_key')`, which is unset on this project, so `'Bearer ' \|\| NULL` sent a NULL header. Fixed by migration 107 |
| 028 | `compute_coach_signals` (8) | `0 21 * * *` | 02:30 | `compute-coach-signals` | `cron_secret` | Writes `dropout_risk_score` / `plateau_risk_score`. **Was the ONLY job surviving the 401 outage** — because it had no auth gate at all (added 2026-07-26, diagnose c3f8a1) |
| 065 / 141 | `proactive_pr_detection` (9) | `0 * * * *` | hourly, on the hour | `pr-detection` | `cron_secret` | **Cadence changed 15min→hourly by migration 141** (2026-09-22 disk-IO audit) — no product latency requirement for PR congratulation notifications. ⚠ Was the de-facto heartbeat `alert_cron_silence` implicitly keyed on; hourly still clears the 2h silence threshold with margin, but watch for false silence-positives for a week post-ship |
| 031 | `proactive_re_engagement` (10) | `30 06 * * *` | 12:00 | `re-engagement` | `cron_secret` | Win-back nudge for lapsed users |
| 031 | `proactive_plateau_alert` (11) | `30 13 * * *` | 19:00 | `plateau-alert` | `cron_secret` | PRO-only; flags weight/lift plateaus |
| 031 | `proactive_protein_gap_alert` (12) | `30 14 * * *` | 20:00 | `protein-gap-alert` | `cron_secret` | PRO-only protein-deficit nudge |
| 031 | `proactive_workout_window_closing` (13) | `30 15 * * *` | 21:00 | `workout-window-closing` | `cron_secret` | Evening pre-bed training nudge |
| 040 | `evaluate_rank_promotions` (14) | `30 18 * * *` | **00:00** (next day) | `evaluate-rank-promotions` | `cron_secret` | Monotonic — promotes only, never demotes |
| 043 | `i-see-you-daily` (15) | `0 14 * * *` | 19:30 | `i-see-you-callout` | `cron_secret` | Self-limiting to recently-active users |
| 046 | `morning_alert_deliver_late` (16) | `*/15 22-23 * * *` | every 15 min, 03:30–05:29 | `morning-alert` (deliver) | `cron_secret` | Per-user delivery-slot sweep |
| 046 | `morning_alert_deliver_early` (17) | `*/15 0-6 * * *` | every 15 min, 05:30–12:29 | `morning-alert` (deliver) | `cron_secret` | Per-user delivery-slot sweep |
| 047 | `clean_orphan_media_daily` (18) | `0 3 * * *` | 08:30 | `clean-orphan-media` | `cron_secret` | **DELETES Storage objects** — highest-consequence endpoint behind the shared secret |
| 061 | `rolling-context-nightly` (19) | `0 21 * * *` | 02:30 | `rolling-context` | `cron_secret` | Nightly AI context rebuild |
| 061 | `streak-guardian-daily` (20) | `30 14 * * *` | 20:00 | `streak-guardian` | `cron_secret` | Nudges streaks at risk |
| 061 | `weekly_recap_ready_sunday` (21) | `30 14 * * 0` | **Sun 20:00** | `weekly-recap-ready` | `cron_secret` | PRO-only. Sends the "Sunday Brief ready" PUSH — **calls no model at all** (`grep -cE 'geminiChat\|generateContent' → 0`). ⚠ Corrected 2026-08-10: this said "Gemini 2.5 Pro", which is `weekly-report` — a different function. `supabase/functions/CLAUDE.md` already flagged the confusion; the registry had not caught up. The PRO gate is server-side via `_shared/subscription.ts` `fetchProUserIds` (diagnose e3b9d7) — before that it had NO subscription check and every active free user got it. Slowest cadence in the fleet — the reason `alert_cron_function_dead` uses an 8-day window |
| 061 | `expiry_reminder_daily` (22) | `0 9 * * *` | 14:30 | `expiry-reminder` | `cron_secret` | Subscription expiry nudges |
| 076 | `alert_payment_flow_health` (26) | `7 * * * *` | hourly, :07 UTC | (intra-DB) | n/a | Needs ≥3 new subscriptions in 24h to fire — effectively dormant at current scale |
| 102 | `compute_admin_metrics_daily` (30) | `15 18 * * *` | 23:45 | `compute-admin-metrics-daily` | `cron_secret` | Late-in-day deliberately: `*_today` fields are cumulative since IST midnight |
| 109 | `alert_cron_silence` (31) | `17 * * * *` | hourly, :17 UTC | (intra-DB) | n/a | Fires when NO cron has succeeded in ≥2h. Catches a TOTAL outage fast; blind to single-function death — `alert_cron_function_dead` (110) is the complement |
| 110 | `alert_cron_function_dead` | `47 6 * * *` | 12:17 | (intra-DB) | n/a | Per-function complement: a function that succeeded within 14d but not in 8d is presumed dead. Catches the shape `alert_cron_silence` misses |
| 141 | `db_maintenance_nightly` | `30 3 * * *` | 09:00 | (intra-DB) | n/a | **Consolidates 6 jobs by migration 141** (2026-09-22 disk-IO audit): `cron_call_log_cleanup_daily`, `usage_counters_retention_daily`, `jrd_retention_daily`, `client_errors_retention_daily`, `jrd_vacuum_daily`, `client_errors_vacuum_daily` — see Deprecated section. Runs all 6 statements sequentially in one job (retention before vacuum, same ordering the original time-staggering already preserved). `clean_orphan_media_daily` deliberately NOT folded in — it's an HTTP call, not pure SQL |
| 141, re-scheduled 143 | `ops_alerts_30min` | `*/30 * * * *` | every 30 min | (intra-DB) | n/a | **Consolidates 3 jobs by migration 141** (2026-09-22 disk-IO audit): `alert_edge_function_health`, `alert_client_errors_spike`, `alert_cron_failures` — see Deprecated section. Cadence also changed 15min→30min (founder decision: balance incident-detection latency against CPU cost on Nano-tier compute). ⚠ `alert_edge_function_health`'s error-rate guard rides along unfixed — tracked separately as OI-234, never fires (401s write no `cron_call_log` row). ⚠ **141's fold-in silently reverted migration 140's `alert_cron_failures` stuck-job bound** — 141 was authored from a branch snapshot predating 140, so its copy of the sub-query carried the pre-140 unbounded `status = 'started' AND started_at < now() - interval '1 hour'` form with no upper bound, live from 2026-09-22 until caught by a merge-integration `/code-review` pass the same day. Migration 143 restores the `[1h, 6h)` bound to this job's `alert_cron_failures` sub-block only; the other two sub-blocks are untouched. See `test/contracts/alert_cron_failures_sync_test.dart`'s `defined_in_migration names the LATEST migration` test, added the same day to catch this class again if the job is ever re-scheduled without updating `alerts/_thresholds.yaml` |
| 131 | `founder_digest_daily` (38) | `30 2 * * *` | 08:00 | `founder-digest` | `cron_secret` | OI-153 Unit D (scheduled 2026-09-13). ONE Telegram message to the founder covering YESTERDAY's IST day: the usage ledger per key (`usage_counters`, windowed + lifetime), users at a ceiling, top-5 id prefixes, and the day's `alerts` rows (exact server count via `{ count: "exact" }`, first 10 rendered — v2 2026-09-13; v1 counted the capped page) — three states per section (data / none / `⚠ unreadable`), never a zero for a failed read. Read-only; the ledger census allowlists it as the only aggregate reader. Secrets `TELEGRAM_BOT_TOKEN` + `FOUNDER_TELEGRAM_CHAT_ID` (Edge secrets, `SECRET_INVENTORY.md`). Yesterday's windowed rows are always present at read time: `usage_counters_retention_daily` keeps 7 days, so the two jobs' order does not matter. ⚠ THREE records disagree about a fire, by construction: `cron.job_run_details` says `succeeded / 1 row` (pg_cron enqueued the `net.http_post`); `net._http_response` says `timed_out` whenever the function takes > 5000 ms (46 of the 50 responses in the 24 h around the first fire, every job — 4 completed inside it); `cron_call_log` is the function's OWN record — and it too is lossy: on the FIRST natural fire (02:30Z 2026-09-13) the function ran and delivered (edge log POST 200 at 02:30:20Z) while its `logCronStart` insert lost the 02:30Z burst to a PostgREST 504 (`start insert failed … Gateway Timeout`), so `cron_call_log` holds NO row for it (OI-194 — fleet-wide, 46 such losses in 24 h; the Hermes pass of 2026-09-13 measured it). The message's ARRIVAL is the liveness signal; `alert_cron_function_dead` is NOT a backstop (OI-179: it cannot fire). Its rollback comment is deliberately an UNQUOTED `cron.unschedule(<name>)` so Gate 31's raw scan does not read the rollback as a real unschedule (OI-193). Function versions: v1 (02:00Z first send), v2 (~06:47Z, the Hermes digest fixes: exact count, line-boundary truncation, `Promise.all` + `MAX_PAGES` 200, unlisted keys surfaced, `reached N/N yesterday`), v3 (~13:08Z, a B-pass follow-up: the alerts `.limit()` literal for Gate `check_unbounded_cron_reads.dart`, and `unlistedTotals` made mode-aware so a lifetime key reports movers rather than summing two users' cumulative counters) — FOUR digests shipped 2026-09-13: v1 automatic, v2 and v3 each a manual verification run. v3's own manual run recurred OI-194 a second time that day: delivered (edge log POST 200) with `cron_call_log` again holding no row for it (`logCronStart` 504, `logCronEnd` no-ops on the null id) — the mechanism is in the shared wrapper, unrelated to either function's own diff |

> **The four `121` rows were invisible to Gate 31 for five days, by construction (OI-132).** Their
> migration ran on prod on 2026-08-15 as `log_table_retention` and left **no .sql file**. Gate 31
> enforces parity by SCANNING `supabase/migrations/*.sql` for `cron.schedule(...)`, so a fileless
> migration is not merely un-gated — it is *unseeable*, and the gate reported green throughout.
> Measured 2026-08-20: **28 live jobs, 24 registered, 4 missing**, and the 4 were exactly these.
> Gate 31's blind spot accounted for the entire gap; the registry was otherwise perfect.
>
> The gate now ALSO checks a committed snapshot of live `cron.job`
> (`backups/live_cron_jobs.json`), which a fileless migration cannot hide from. CI has no Supabase
> credentials (OI-105), so a live query there would silently skip — a gate that passes because it
> never ran. The snapshot is the CI-safe shape, and follows the precedent
> `backups/live_schema_columns.json` already sets. **Regenerate it in the same commit as any
> migration that schedules or unschedules a job** — the regeneration SQL is in the gate's header.

> **Cadence accuracy (corrected 2026-07-26, Hermes L31).** Every row above was regenerated from live
> `cron.job` rather than hand-maintained — 11 of the previous 20 rows had wrong IST conversions, two
> named jobs that do not exist, and five live jobs were missing entirely. pg_cron runs in **UTC**
> (`cron.timezone = GMT`); IST = UTC+5:30. Gate 31 checks **presence only** — it cannot see a wrong
> cadence, so this table's accuracy is unenforced and must be regenerated from live state, never
> edited by hand.

## Deprecated / unscheduled

| Migration | Job name | Why removed |
|---|---|---|
| 068/109, unscheduled 141 | `cron_call_log_cleanup_daily` | Folded into `db_maintenance_nightly` (141), still calling the same `cleanup_cron_call_log()` — 7-day retention, always sparing the newest success row and the newest row of any status, unchanged |
| 121, unscheduled 141 | `jrd_retention_daily` | Folded into `db_maintenance_nightly` (141), still calling the same `cleanup_cron_job_run_details()` — deletes `cron.job_run_details` older than 14d, always sparing the newest row per job, unchanged |
| 121, unscheduled 141 | `client_errors_retention_daily` | Folded into `db_maintenance_nightly` (141), still calling the same `cleanup_client_errors()` — deletes `public.client_errors` older than 30d, unchanged |
| 128, unscheduled 141 | `usage_counters_retention_daily` | Folded into `db_maintenance_nightly` (141), still calling the same `cleanup_usage_counters()` — deletes `public.usage_counters` windowed rows older than 7d only; the two-sided predicate (`window_start <> 'epoch' AND window_start < now() - 7d`) that protects LIFETIME rows from deletion is inside the function, unchanged by the consolidation |
| 121, unscheduled 141 | `jrd_vacuum_daily` | Folded into `db_maintenance_nightly` (141), still runs `VACUUM (ANALYZE) cron.job_run_details` — now sequenced explicitly AFTER retention in the same job, rather than relying on a 16-minute time gap between separate jobs to hope retention finished first |
| 121, unscheduled 141 | `client_errors_vacuum_daily` | Folded into `db_maintenance_nightly` (141), still runs `VACUUM (ANALYZE) public.client_errors` — same sequencing improvement as above |
| 076, unscheduled 141 | `alert_edge_function_health` | Folded into `ops_alerts_30min` (141), cadence also changed 15min→30min. ⚠ Carries forward unfixed: **structurally blind to an auth outage** — a 401 writes no `cron_call_log` row, so its `total >= 5` guard never matches; has never fired once. Tracked as **OI-234** |
| 077, unscheduled 141 | `alert_client_errors_spike` | Folded into `ops_alerts_30min` (141), cadence also changed 15min→30min. Was the only one of the three that has ever actually fired |
| 139, unscheduled 141 | `alert_cron_failures` | Folded into `ops_alerts_30min` (141), cadence also changed 15min→30min. Created live by migration 139 (separate in-flight branch, uncommitted as of 141's authoring) — see 141's header note. ⚠ The fold-in also reverted migration 140's `[1h, 6h)` stuck-job bound back to unbounded; restored by migration 143 (see the `ops_alerts_30min` row above) |

## Trigger-dispatched functions (deliberately NOT in the table above)

`alert-critical-notify` (telegram-admin-bot batch, 2026-09-14) is invoked
ONLY by the `private.dispatch_critical_alert_notify()` Postgres trigger
(migration 133, telemetry added by migration 134) via `pg_net.http_post` on
a critical `alerts` INSERT — it is never `cron.schedule`-dispatched, so it
has no `cron.job` row and intentionally carries NO row in the active-jobs
table above. This is a deliberate scope note (per the original plan's
Task 13), not a silently skipped registration: **Gate 31
(`scripts/check_cron_registry.dart`) scans `supabase/migrations/*.sql` for
`cron.schedule(...)` calls only, so it would not see this function even if a
row existed for it** — a trigger dispatch and a cron dispatch are different
mechanisms with different auth/telemetry wiring conventions but the same
`_shared/cron_auth.ts` / `_shared/cron_telemetry.ts` helpers, which is why
`alert-critical-notify` is still covered by the `cron_auth_adoption_test.dart`
/ `cron_telemetry_adoption_test.dart` rosters (their own
`_triggerDispatchedFunctions` list, alongside `proactive-coach-promotion`)
even though it is absent from this cron-specific registry.

## How to add a new cron job

1. Write the migration as `supabase/migrations/NNN_<feature>_cron.sql`.
2. Use **`private.cron_get_secret()`** (NOT a hardcoded JWT, and NOT the old `private.morning_alert_get_service_key()`) in the `Authorization: Bearer ' ||` clause. The old accessor returns the service_role JWT, which the auth gate no longer accepts — migrations 107/108 moved the whole fleet onto the `CRON_SECRET` shared secret. `private.cron_get_secret()` RAISES if the Vault row is missing, so a future disappearance shows up as `cron.job_run_details.status='failed'` rather than as a silent 401. See `supabase/functions/_shared/cron_auth.ts` (HISTORY section) and diagnose `c3f8a1`.
   ⚠ Target function must be `verify_jwt=false`. With `verify_jwt=true` the Supabase gateway validates the bearer as a project-signed JWT *before the module loads*, so an opaque shared secret is rejected before your gate ever runs.
3. Add a row to this registry — name, cadence, function, owner, vault dep.
4. Apply migration via Supabase MCP `apply_migration`. Update `backups/applied_migrations.json` in the same commit (per `feedback_migration_apply_record_pair.md`).
5. Run `dart run scripts/check_cron_registry.dart` — must pass.

## Last audit

- 2026-05-20: initial population, audit closure I5. 11 active jobs.
