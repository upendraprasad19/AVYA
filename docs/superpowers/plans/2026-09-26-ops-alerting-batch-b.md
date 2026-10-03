# Batch B — ops alerting: restore retention, then make SQL-job failure visible

Branch `ops-alerting-batch-b`. Execution mode: **inline** (single coordinator;
one migration file per slice; no parallel units — §4.12.7).

## Why split into B1 / B2 (decided at batch start)

B1 has a hard date and standalone value; B2 is alert *design*. §4.3's
consolidate-slices rule allows a split for a genuinely separable piece: B1 restores
four prunes that have been dead 5 nights and defuses a dated false CRITICAL, and
none of that depends on B2's design decisions.

- **B1 (this plan, ships first):** OI-247 + the OI-179 R2-11 exclusion. Migration 144.
- **B2 (own plan + ×2 review, next):** OI-178 (alert on failed pg_cron SQL jobs,
  reading `cron.job_run_details`), OI-248 (spike alert counts rows not users),
  OI-200 (`founder_metrics_ops` reinclusion filter), client-side offline error
  classification. OI-179's threshold-vs-retention defect is B2 scope too.

## B1 — facts (all verified live 2026-09-26, project dedsavbjuwgarrhphgnl)

1. `cron.job` jobid 41 `db_maintenance_nightly` (`30 3 * * *`) command = 4 ×
   `SELECT public.cleanup_*()` + `VACUUM (ANALYZE) cron.job_run_details;` +
   `VACUUM (ANALYZE) public.client_errors;` — byte-matches migration 141:71.
2. `cron.job_run_details` jobid 41: 5/5 `failed`, 09-22 → 09-26,
   `ERROR: VACUUM cannot run inside a transaction block`.
3. Pre-141 jobs 35 (`jrd_vacuum_daily`) / 36 (`client_errors_vacuum_daily`),
   single-statement VACUUM commands: 15/15 `succeeded` 09-06 → 09-20 (one
   `failed` each on 09-21 = the e8b4a1 DB-starvation incident).
4. Consequence: the four cleanups are rolled back with the VACUUM, so no prune
   since 09-21. `cron_call_log` oldest row 09-14 (1,429 rows);
   `client_errors` 6,007 rows (oldest 08-21); `job_run_details` 6,967.
5. `alert_cron_function_dead` (jobid 32, `47 6 * * *`): success rows within 14 d,
   fires at `days_silent >= 8`, dedup 24 h. `alert-critical-notify` last success
   2026-09-22 11:00 ⇒ 8.8 d at 2026-10-01 06:47 ⇒ false CRITICAL.
   `alert-critical-notify` is trigger-dispatched (CRON_REGISTRY "Trigger-dispatched
   functions" section; migration 133) — a critical about it would dispatch it and
   reset its own clock (OI-179 R2-11).

## B1 — change (`supabase/migrations/144_split_vacuum_out_of_db_maintenance_nightly.sql`)

1. `cron.alter_job(db_maintenance_nightly, command := four cleanups)` — keeps
   jobid 41 + history (141 §4c precedent).
2. `cron.schedule('jrd_vacuum_daily','40 3 * * *', VACUUM (ANALYZE) cron.job_run_details)`
   and `client_errors_vacuum_daily` at `43 3 * * *` — single statements, the
   shape proven by fact 3. Guarded unschedule first (idempotent re-apply).
3. `cron.alter_job(alert_cron_function_dead, command := live body + two lines —
   a comment and `AND function_name <> 'alert-critical-notify'` inside the
   cron_call_log subquery)`.

Tier: **platform** (classified on the written file; no SECURITY DEFINER) ⇒ ×2
review + B-pass; no Hermes.

## B1 — tests / docs

- `test/contracts/cron_vacuum_single_statement_test.dart` (6): scans every
  migration's comment-stripped dollar-quoted bodies (`$$` and tagged) for VACUUM
  beside another statement; proves non-vacuous on 141 and a synthetic `$job$` body;
  admits 141 only while 144 repairs it; pins the exclusion inside the alert's
  cron_call_log subquery; ties it to the trigger-dispatched roster. Mutation counts:
  see diagnose d6b2f9.
- `docs/operations/CRON_REGISTRY.md`: db_maintenance_nightly row corrected (it
  described the broken shape as an improvement); two VACUUM jobs active again;
  alert_cron_function_dead row notes the exclusion. Gate 31 PASS.
- `test/contracts/disk_io_audit_cleanup_batch_test.dart` unchanged and green (its
  141-content assertions stay true; the registry's Deprecated section still lists
  the two job names as history).
- Diagnose `d6b2f9`.

## B1 — apply + verify (needs explicit founder go, §4.3)

1. `apply_migration` 144. Target: **before 2026-09-29 03:30 UTC** (R2 F1): the
   09-29 03:30 prune is then the first to run, and it removes every row older than
   09-22 03:30 before the 09-29 06:47 alert. Why 09-29 and not 09-30:
   `weekly-recap-ready` (weekly, `30 14 * * 0`) has ONE success row, 09-20 14:30;
   if its 09-27 run leaves no success row (a real failure or an OI-194 lost insert)
   and nothing prunes, the alert fires falsely at 09-29 06:47 (8.68 d). The
   `alert-critical-notify` false critical (10-01 06:47) is defused by the exclusion
   the moment it commits (R1 F7), so the true last-safe apply for THAT case is
   10-01 06:47, but the weekly case makes 09-29 03:30 the operative target.
2. Same commit: `backups/applied_migrations.json` entry (sha256 of the file as
   applied) + `backups/live_cron_jobs.json` regenerated (Gate 31 input B).
3. Read-only verify, same session as the apply: the `cron.job` commands. Then a
   DATED action on the first night after apply (the morning after, UTC ≥ 03:45):
   `cron.job_run_details` must show `succeeded` for db_maintenance_nightly (41)
   and the two new VACUUM jobids; `cron_call_log` oldest row ≤ 7 d. Until B2's
   OI-178 alert exists this manual check is the ONLY detection (R1 F9), so
   OI-247 closes only on that observed `succeeded`, never on the apply.
4. Board: OI-247 CLOSED on the succeeded run; OI-179 UPDATE (exclusion shipped,
   threshold defect remains, B2).

## Known residue (named, owned)

- OI-178 (SQL-job failures invisible) is why this was silent for 5 nights — B2.
- OI-179 threshold `>= 8` vs 7-day prune: restoring the prune makes the alert
  inert again for all functions (the pre-09-22 state). B2.
- `weekly-recalc` calls `logCronStart` but has no cron job (0 rows live): a
  manual run would put it in the same silence-is-healthy class. Recorded on
  OI-179 in the apply commit; the roster test (R1 F3) covers the named
  trigger-dispatched functions.
