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
| 065 | `proactive_pr_detection` (9) | `*/15 * * * *` | every 15 min | `pr-detection` | `cron_secret` | Highest-frequency job; the de-facto heartbeat `alert_cron_silence` keys on |
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
| 061 | `weekly_recap_ready_sunday` (21) | `30 14 * * 0` | **Sun 20:00** | `weekly-recap-ready` | `cron_secret` | Gemini 2.5 Pro, PRO-only. Slowest cadence in the fleet — the reason `alert_cron_function_dead` uses an 8-day window |
| 061 | `expiry_reminder_daily` (22) | `0 9 * * *` | 14:30 | `expiry-reminder` | `cron_secret` | Subscription expiry nudges |
| 068 / 109 | `cron_call_log_cleanup_daily` (23) | `30 3 * * *` | 09:00 | (intra-DB) | n/a | 7-day retention, **always sparing the newest success row AND the newest row of any status** (110). Its function did not exist until 109 — the job had errored 70× |
| 076 | `alert_payment_flow_health` (26) | `7 * * * *` | hourly, :07 UTC | (intra-DB) | n/a | Needs ≥3 new subscriptions in 24h to fire — effectively dormant at current scale |
| 076 | `alert_edge_function_health` (27) | `*/15 * * * *` | every 15 min | (intra-DB) | n/a | Computes an error RATE from `cron_call_log`. **Structurally blind to an auth outage** — a 401 writes no row, so its `total >= 5` guard never matches. Never fired once |
| 077 | `alert_client_errors_spike` (29) | `*/15 * * * *` | every 15 min | (intra-DB) | n/a | The only alert that has ever fired |
| 102 | `compute_admin_metrics_daily` (30) | `15 18 * * *` | 23:45 | `compute-admin-metrics-daily` | `cron_secret` | Late-in-day deliberately: `*_today` fields are cumulative since IST midnight |
| 109 | `alert_cron_silence` (31) | `17 * * * *` | hourly, :17 UTC | (intra-DB) | n/a | Fires when NO cron has succeeded in ≥2h. Catches a TOTAL outage fast; blind to single-function death — `alert_cron_function_dead` (110) is the complement |
| 110 | `alert_cron_function_dead` | `47 6 * * *` | 12:17 | (intra-DB) | n/a | Per-function complement: a function that succeeded within 14d but not in 8d is presumed dead. Catches the shape `alert_cron_silence` misses |

> **Cadence accuracy (corrected 2026-07-26, Hermes L31).** Every row above was regenerated from live
> `cron.job` rather than hand-maintained — 11 of the previous 20 rows had wrong IST conversions, two
> named jobs that do not exist, and five live jobs were missing entirely. pg_cron runs in **UTC**
> (`cron.timezone = GMT`); IST = UTC+5:30. Gate 31 checks **presence only** — it cannot see a wrong
> cadence, so this table's accuracy is unenforced and must be regenerated from live state, never
> edited by hand.

## Deprecated / unscheduled

| Migration | Job name | Why removed |
|---|---|---|
| (none yet) | — | — |

## How to add a new cron job

1. Write the migration as `supabase/migrations/NNN_<feature>_cron.sql`.
2. Use **`private.cron_get_secret()`** (NOT a hardcoded JWT, and NOT the old `private.morning_alert_get_service_key()`) in the `Authorization: Bearer ' ||` clause. The old accessor returns the service_role JWT, which the auth gate no longer accepts — migrations 107/108 moved the whole fleet onto the `CRON_SECRET` shared secret. `private.cron_get_secret()` RAISES if the Vault row is missing, so a future disappearance shows up as `cron.job_run_details.status='failed'` rather than as a silent 401. See `supabase/functions/_shared/cron_auth.ts` (HISTORY section) and diagnose `c3f8a1`.
   ⚠ Target function must be `verify_jwt=false`. With `verify_jwt=true` the Supabase gateway validates the bearer as a project-signed JWT *before the module loads*, so an opaque shared secret is rejected before your gate ever runs.
3. Add a row to this registry — name, cadence, function, owner, vault dep.
4. Apply migration via Supabase MCP `apply_migration`. Update `backups/applied_migrations.json` in the same commit (per `feedback_migration_apply_record_pair.md`).
5. Run `dart run scripts/check_cron_registry.dart` — must pass.

## Last audit

- 2026-05-20: initial population, audit closure I5. 11 active jobs.
