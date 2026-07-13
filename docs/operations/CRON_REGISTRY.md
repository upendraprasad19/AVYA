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

| Migration | Job name | Cadence | Function | Owner | Vault dep | Notes |
|---|---|---|---|---|---|---|
| 015 | `morning-alert-daily` | 06:00 IST daily | `morning-alert` | founder | `service_role_key` | Pushes morning workout/streak nudge |
| 028 | `compute-coach-signals-nightly` | 02:00 IST daily | `compute-coach-signals` | founder | `service_role_key` | Aggregates 7-day signals for AI coach context |
| 031 | `proactive_re_engagement` (jobid 10) | 06:30 UTC = 12:00 IST | `re-engagement` | founder | `service_role_key` | Win-back nudge for lapsed users. **F47 (2026-06-07):** registry previously listed a single fictional `proactive-triggers` job → `proactive-triggers` (no such cron name, no such function dir). Migration 031 actually schedules these 5 granular jobs. |
| 031 | `proactive_plateau_alert` (jobid 11) | 13:30 UTC = 19:00 IST | `plateau-alert` | founder | `service_role_key` | Flags weight/lift plateaus |
| 031 | `proactive_protein_gap_alert` (jobid 12) | 14:30 UTC = 20:00 IST | `protein-gap-alert` | founder | `service_role_key` | Daily protein-deficit nudge |
| 031 | `proactive_workout_window_closing` (jobid 13) | 15:30 UTC = 21:00 IST | `workout-window-closing` | founder | `service_role_key` | Evening pre-bed training nudge. (031 also schedules `proactive_pr_detection` (jobid 9) → `pr-detection` — see the `065` row below, which re-registered it for auth.) |
| 040 | `evaluate-rank-promotions-daily` | 04:00 IST daily | `evaluate-rank-promotions` | founder | `service_role_key` | Promotes users up the Lt/Cdr ladder |
| 043 | `i-see-you-daily` | 19:30 IST daily (14:00 UTC) | `i-see-you-callout` | founder | `service_role_key` | Surfaces "I see you" callouts |
| 046 | `morning_alert_deliver_early` (jobid 17) | 04:30 IST daily | `morning-alert` (personalised delivery slot) | founder | `service_role_key` | Early-bird variant; broke silently in mid-May before being detected |
| 046 | `morning_alert_deliver_late` | 07:30 IST daily | `morning-alert` (personalised delivery slot) | founder | `service_role_key` | Late-riser variant |
| 047 | `clean-orphan-media-weekly` | Sunday 03:00 IST | `clean-orphan-media` | founder | `service_role_key` | Sweeps unreferenced Storage objects |
| 061 | `rolling-context-nightly` | 03:00 IST daily | `rolling-context` | founder | `service_role_key` | Retrofitted to `private.morning_alert_get_service_key()` in audit 2026-05-12 P1-D |
| 061 | `streak-guardian-daily` | 20:00 IST daily (14:30 UTC) | `streak-guardian` | founder | `service_role_key` | Same P1-D retrofit. **F46 (2026-06-07):** registry said 23:50 IST, but migration 061 + live jobid 20 are both `30 14 * * *` = 20:00 IST — corrected here + in the function docstring. |
| 061 | `weekly_recap_ready_sunday` | Sunday 09:00 IST | `weekly-report` | founder | `service_role_key` | Audit P1-D fix; sends weekly performance recap |
| 061 | `expiry_reminder_daily` | 10:00 IST daily | `expiry-reminder` | founder | `service_role_key` | Audit P1-D fix; subscription expiry nudges |
| 047 | `clean_orphan_media_daily` | 03:00 IST daily | `clean-orphan-media` | founder | `service_role_key` | Sweeps unreferenced Storage objects (entry rename: registry initially used weekly cadence — actual migration is daily) |
| 065 | `pr-detection` (jobid 9) | every 15 min | `pr-detection` | founder | `service_role_key` | Fixed env-vs-vault drift on 2026-05-15 (operational fix) |
| 068 | cron_call_log housekeeping | hourly | (intra-DB function) | founder | n/a | Cleans `cron_call_log` rows older than 7d |
| 102 | `compute_admin_metrics_daily` | 23:45 IST daily (18:15 UTC) | `compute-admin-metrics-daily` | founder | `service_role_key` | Populates `public.admin_metrics_daily` (one row/day) for the founder-only `/admin` dashboard's trend charts. Deliberately late in the day (not just-after-midnight) — the `*_today` fields are cumulative-since-midnight-IST, so an early-morning run would snapshot near-zero for every "today" metric. |

## Deprecated / unscheduled

| Migration | Job name | Why removed |
|---|---|---|
| (none yet) | — | — |

## How to add a new cron job

1. Write the migration as `supabase/migrations/NNN_<feature>_cron.sql`.
2. Use `private.morning_alert_get_service_key()` (NOT a hardcoded JWT) in the `Authorization: Bearer ' ||` clause. See `supabase/functions/CLAUDE.md` "Cron jobs send Authorization: Bearer null" entry for history.
3. Add a row to this registry — name, cadence, function, owner, vault dep.
4. Apply migration via Supabase MCP `apply_migration`. Update `backups/applied_migrations.json` in the same commit (per `feedback_migration_apply_record_pair.md`).
5. Run `dart run scripts/check_cron_registry.dart` — must pass.

## Last audit

- 2026-05-20: initial population, audit closure I5. 11 active jobs.
