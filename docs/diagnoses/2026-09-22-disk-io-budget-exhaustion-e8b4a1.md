---
bug_id: e8b4a1
date: 2026-09-22
batch: disk-io-audit-cleanup
status: fixed
blast_radius: platform
symptom: Supabase dashboard showed "Your project is about to deplete its Disk IO Budget" and project health read "Unhealthy"; every direct-DB call including `select 1` timed out. Screenshots confirmed Compute 91%, CPU 91%, Memory 55%, Disk IO 87% simultaneously on a Nano ($0/mo, 0.5GB RAM, Free plan) compute tier.
concept: disk_io_budget_exhaustion
sot_registry_entry: null
writers:
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method_or_widget: "ivfflat index retune", line: 25 }
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method_or_widget: "readiness_daily RLS policy fix", line: 37 }
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method_or_widget: "drop 2 dead indexes", line: 52 }
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method_or_widget: "db_maintenance_nightly consolidation", line: 71 }
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method_or_widget: "ops_alerts_30min consolidation", line: 97 }
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method_or_widget: "proactive_pr_detection cadence change", line: 162 }
  - { file: supabase/migrations/142_restore_nutrition_log_items_food_id_index.sql, method_or_widget: "restore FK-support index dropped in error by 141", line: 20 }
readers:
  - { file: docs/operations/CRON_REGISTRY.md, method_or_widget: "cron job registry (Gate 31 parity)", line: 46 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/disk_io_audit_cleanup_batch_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — infra/config fix, no per-user data path touched
forbidden_patterns_checked: []
proposed_fix: Six items originally scoped — (A) disable pg_cron's internal job_run_details logging — BLOCKED, see Notes (cron.log_run is a postmaster-context GUC, not settable via SQL migration; requires a full server restart), (B) retune memory_embeddings ivfflat index for actual row count — APPLIED, (C) fix readiness_daily RLS auth-initplan — APPLIED, (D) drop 2 verified-dead indexes — APPLIED, THEN FOUND PARTIALLY WRONG AND CORRECTED, see Notes (a self-triggered B-pass found one of the two, idx_nutrition_log_items_food_id, was the sole index backing a foreign key; idx_scan=0 says nothing about FK-support use, only query-access use; fixed via migration 142, APPLIED, live get_advisors confirms the unindexed_foreign_keys finding is gone), (E) compute tier upgrade — blocked on founder decision, explicitly deferred by founder choice to revisit after A-F land, not part of this commit, (F) consolidate 9 cron jobs into 3 — APPLIED. B/C/D/F applied together as migration 141 to project dedsavbjuwgarrhphgnl, verified live post-apply; migration 142 is a same-day follow-up fixing D's regression, found before commit by this batch's own self-triggered B-pass review, founder-authorized separately in chat, applied and verified live.
regression_test_planned:
  - test/contracts/disk_io_audit_cleanup_batch_test.dart
touched_layers_checked:
  - { tier: 1, status: not_applicable, evidence: "No Dart/client code changes" }
  - { tier: 2, status: not_applicable, evidence: "No Hive changes" }
  - { tier: 3, status: fixed_in_this_batch, evidence: "migration 141 written, applied to project dedsavbjuwgarrhphgnl, and verified live (indexdef shows lists='10', pg_policy shows the wrapped auth.uid() subquery, both dead indexes confirmed absent). Migration 142 applied same day, verified live: pg_indexes confirms idx_nutrition_log_items_food_id restored, get_advisors(type=performance) re-run and the unindexed_foreign_keys finding is gone. test/contracts/disk_io_audit_cleanup_batch_test.dart 9/9 passing, mutation-proven end to end -- migration 141's ivfflat assertion AND migration 142's own new test (removed IF NOT EXISTS from a scratch-restored copy per supabase/migrations/CLAUDE.md's immutable-migration protocol, confirmed RED on the exact assertion, restored, sha256 verified to match the ledger exactly, confirmed GREEN again). This doc previously miscounted the pre-142 file as 9/9 when it held 8 -- caught by B-pass, corrected. Fix A (cron.log_run=off) NOT applied -- see Notes" }
  - { tier: 4, status: not_applicable, evidence: "No data rows read, written, or deleted by migration 141" }
  - { tier: 5, status: fixed_in_this_batch, evidence: "backups/applied_migrations.json updated with migration 141's entry (hash, cloud_version 20260922000835) and migration 142's entry (hash, cloud_version 20260922043010) in the same commit, per feedback_migration_apply_record_pair.md. Migration 140 deleted rather than left unapplied — see Notes" }
  - { tier: 6, status: not_applicable, evidence: "No Edge Function code or deploy changes" }
  - { tier: 7, status: fixed_in_this_batch, evidence: "9 cron jobs consolidated to 3, applied live and verified: cron.job shows db_maintenance_nightly (30 3 * * *), ops_alerts_30min (*/30 * * * *), proactive_pr_detection (0 * * * *), all 8 folded job names absent. docs/operations/CRON_REGISTRY.md updated for Gate 31 parity; backups/live_cron_jobs.json regenerated same-day (24 jobs, _generated_at 2026-09-22T06:15:00+05:30) -- corrects this row's earlier 'regen still outstanding' claim, stale against the Notes section's own later 'Arithmetic error caught late' entry. Quantified invocation/WAL impact added post-apply -- see 'Quantified impact of Fix F' section" }
  - { tier: 8, status: fixed_in_this_batch, evidence: "readiness_daily RLS policy rewritten to (select auth.uid()), applied live and verified: pg_policy using_expr = the wrapped auth.uid() subquery form" }
  - { tier: 9, status: not_applicable, evidence: "No storage bucket/object changes" }
  - { tier: 10, status: not_applicable, evidence: "No secret changes" }
  - { tier: 11, status: not_applicable, evidence: "No external service changes" }
  - { tier: 12, status: not_applicable, evidence: "No client-server contract changes; all changes are server-internal (config, index tuning, RLS, cron scheduling)" }
impact_analysis: |
  Positive impact (applied and live-verified): fixes a 25:1 index-to-data-size waste on
  memory_embeddings; fixes a documented Supabase RLS perf warning; removes write-time
  maintenance overhead on 2 verified-dead indexes on high-churn tables; reduces cron
  scheduler entries 31->24 with zero functional change (same checks, same cleanup, same
  notifications) except two explicit, founder-approved cadence changes (ops alerts
  15min->30min, PR detection 15min->hourly).
  Fix A (the single largest lever, ~451MB/11days = 44.7% of all WAL from pg_cron's own
  job_run_details bookkeeping) is NOT applied. Discovered mid-batch that cron.log_run is
  a postmaster-context GUC — ALTER DATABASE ... SET fails outright (Postgres error 55P02),
  and the only path is a full server restart via Supabase's dashboard/support, not a
  reversible SQL migration. This is a materially different, riskier action than what the
  founder authorized ("fully reversible... a GUC not a schema change"), so it was
  deliberately not forced through and is being taken back as a fresh decision rather than
  reinterpreting the original approval to cover it.
  Quantified post-apply (2026-09-22, see "Quantified impact of Fix F" section below): Fix F
  alone cuts total daily cron invocations ~65% (490.1/day pre-141 -> 173.1/day post-141,
  computed from live schedules) and is projected to cut this specific WAL source ~56%
  (~41.0MB/day measured -> ~18.0MB/day projected, extrapolated from the source-confirmed
  per-invocation-uniform bookkeeping cost) -- independent of Fix A, which remains blocked.
  Fix A pursued later would still eliminate the largest single remaining slice (~26% of
  post-141 total WAL, projected), but its absolute value has shrunk from ~41.0MB/day to
  ~18.0MB/day because Fix F already captured most of the same win through cadence alone.
  Known residual risk: proactive_pr_detection was flagged in CRON_REGISTRY.md as the
  de-facto heartbeat alert_cron_silence implicitly relies on. Hourly cadence still clears
  the 2-hour silence threshold with a full hour of margin, but recommend watching
  alert_cron_silence for false positives for one week after this ships.
  Explicitly NOT fixed by this batch (separate OIs filed): alert_edge_function_health's
  broken error-rate guard (OI-234, never fires — rides along unfixed inside the
  consolidated ops_alerts_30min job), two unusually slow daily jobs likely needing a
  code-level fix (OI-235), 12 of 14 advisor-flagged unused indexes left for separate
  review (OI-236), and a possible sync write-amplification pattern on scheduled_workouts/
  template_exercises (OI-237, needs docs/architecture/sync.md + WriteServices review, out
  of scope for this SQL-only batch).
  The compute tier upgrade (Nano -> Micro/Small, requires Pro plan, ~$10-15/mo) is
  EXCLUDED from this diagnose-doc's fixed scope entirely — it is a spend decision blocked
  on the founder, tracked separately, not a code/migration fix.
  Self-triggered B-pass (before first commit, per §4.3) found one real regression this
  batch itself introduced: dropping idx_nutrition_log_items_food_id (item D) removed the
  sole index backing a foreign key -- idx_scan=0 says nothing about FK-support use, only
  query-access use. Fixed via migration 142, founder-authorized separately in chat,
  applied and verified live (get_advisors' unindexed_foreign_keys finding is gone).
  Also corrected: this doc's own test count (8 tests mis-stated as 9,
  now genuinely 9 after 142's test was added), an off-by-one job-count label (20 -> 21,
  arithmetic was already right), and a wrong migration timestamp/gap citation for
  alert_cron_failures (~12h claimed, ~6h45m actual -- see Notes for full detail).
---

## Symptom

Supabase dashboard showed "Your project is about to deplete its Disk IO Budget ...
throughput will return to its baseline of 5 MB/s until the budget resets" and project
health read "Unhealthy". Every direct-DB call, including `select 1`, timed out.
Founder-supplied screenshots (2026-09-21) showed Compute 91%, CPU 91%, Memory 55%, and
Disk IO 87% simultaneously over the preceding 7 days, on a **Nano** compute tier ($0/hour,
0.5GB RAM, shared compute, Free plan — confirmed via Settings → Compute and Disk).

## Root cause

Multiple contributing factors, quantified via live SQL investigation against project
`dedsavbjuwgarrhphgnl` once the connection became responsive:

### Primary driver: pg_cron's own internal bookkeeping (44.7% of all WAL)

`cron.log_run` (default `on`) makes pg_cron write 1 INSERT + up to 4 UPDATEs into
`cron.job_run_details` per job execution. Verified at the source level (fetched pg_cron
1.6.4's actual `src/pg_cron.c`): every `InsertJobRunDetail`/`UpdateJobRunDetail` call site
is individually gated behind `if (CronLogRun)`, so disabling it skips the entire
per-run sequence, not just the insert.

Measured via `pg_stat_statements` (stats window: 2026-09-10 to 2026-09-21, 11 days):
- Total WAL across the database: 1008.6 MB
- WAL from `cron.job_run_details` INSERT/UPDATE statements alone: **451.0 MB (44.7%)**
- Confirmed nothing in the app reads this table: `alert_cron_silence` and
  `alert_cron_function_dead` (the two jobs that monitor "is cron alive") both read the
  app's own `public.cron_call_log` table instead, verified by reading their actual
  `cron.job` command text.

### Contributing factor: oversized IVFFlat index on memory_embeddings

`idx_memory_embeddings_ivfflat` was created with `lists=100`, sized for the ~1M rows the
original migration's header anticipated. Actual row count: **839**. Index size: 9040kB
against 360kB of actual table data — a 25:1 ratio, for zero recall benefit at this scale
(pgvector guidance: `lists ~= rows/1000` for corpora under 1M rows).

### Contributing factor: RLS auth-initplan on readiness_daily

Supabase's own performance advisor (`get_advisors`, type=performance) flagged
`users_own_readiness_daily`'s policy re-evaluating `auth.uid()` per row instead of once
per query.

### Contributing factor: 14 unused indexes, 2 verified as safe to drop

Cross-verified live against `pg_stat_user_indexes` (not just the advisor's claim):
14 indexes show `idx_scan=0`. Two sit on the highest-churn tables from this
investigation — `idx_ai_coach_interactions_tool_calls_failed` and
`idx_nutrition_log_items_food_id` — and are dropped in this batch. The other 12 are left
alone (tracked as OI-236); two are auth/payment-adjacent (`idx_users_email_lower`,
`idx_subscriptions_razorpay_payment_id`) and may be low-frequency rather than truly dead.

### Contributing factor: cron scheduler fragmentation

31 distinct `pg_cron` jobs, several of them near-identical in shape and cadence. Real
execution history (`cron.job_run_details`, not schedule theory) confirmed 6 nightly
housekeeping jobs and 3 same-cadence SQL-only alert jobs as safe, zero-risk merge
candidates — verified independent (no shared state, no interdependency) by reading each
job's actual command body before proposing the merge.

### Underlying structural factor: undersized compute tier

Founder-supplied dashboard screenshots showed CPU and Compute both at 91% utilization,
not just Disk IO — confirming this is not purely a disk-throughput problem but a
generally undersized instance (Nano, 0.5GB RAM) running a full production app (30+ cron
jobs, AI coach embeddings, Edge Function traffic) concurrently with live user reads/
writes. This diagnose-doc's fixes reduce waste; they do not add compute headroom. The
compute upgrade itself is tracked separately as a founder spend decision, not included
in this commit's scope.

## Fix

Two migrations applied, one attempted and withdrawn:

- **`supabase/migrations/141_disk_io_audit_cleanup_batch.sql`** — bundles four independent
  fixes: ivfflat retune, RLS policy fix, 2 dead-index drops, and cron consolidation
  (9 jobs → 3). Applied to project `dedsavbjuwgarrhphgnl` via `apply_migration` and
  verified live (see Touched layers checked). Each section is independently reversible;
  a combined rollback block is included at the file's end.
- **`supabase/migrations/142_restore_nutrition_log_items_food_id_index.sql`** — restores
  `idx_nutrition_log_items_food_id`, one of the two indexes migration 141 dropped, after
  a self-triggered B-pass review found it was the sole index backing
  `nutrition_log_items_food_id_fkey` — a regression on the exact axis (DB resource
  pressure) this whole batch exists to fix (see Notes for the full finding and live
  verification). Founder-authorized separately in chat, applied to project
  `dedsavbjuwgarrhphgnl` via `apply_migration` (cloud_version `20260922043010`) and
  verified live: `pg_indexes` confirms the index exists, and a fresh `get_advisors` run
  shows the `unindexed_foreign_keys` finding is gone.
- **`supabase/migrations/140_disable_pg_cron_internal_logging.sql`** — originally drafted
  as `ALTER DATABASE postgres SET cron.log_run = off`. **Attempted and failed**: Postgres
  returned error 55P02, "parameter cron.log_run cannot be changed without restarting the
  server". `pg_settings` confirms `context = postmaster` — the most restrictive GUC class,
  settable only via server config at boot. This is not achievable through any SQL
  migration; it requires a full database restart, orchestrated through Supabase's
  dashboard or support, which is a materially different (briefly-downtime-incurring)
  action than what was described when authorization was requested. The file was deleted
  rather than left in the repo as a permanently-unappliable migration — see Notes.

`docs/operations/CRON_REGISTRY.md` updated in the same commit for Gate 31 parity — the 8
consolidated job names moved to the Deprecated section with their prior behavior
documented, and 2 new consolidated jobs plus the cadence change added to Active jobs.

## Quantified impact of Fix F (added 2026-09-22, post-apply)

Founder asked, once Fix A turned out to be blocked: since the bookkeeping cost is fixed
per invocation regardless of `cron.log_run`, does reducing *how often* jobs run achieve a
similar effect through a totally different, always-available mechanism? Yes — and Fix F
(already live) already exercises this lever. Quantified against two distinct baselines,
kept deliberately separate rather than blended into one percentage.

### 1. Raw scheduler load (schedule-based, not WAL) — immediately-pre-141 vs. current live state

| Group | Pre-141 | Post-141 | Delta |
|---|---|---|---|
| `proactive_pr_detection` (15min→hourly) | 96/day | 24/day | -72/day |
| 3 alert jobs → `ops_alerts_30min` (15min→30min) | 288/day | 48/day | -240/day |
| 6 housekeeping jobs → `db_maintenance_nightly` (daily→daily, merged) | 6/day | 1/day | -5/day |
| 21 other jobs, unchanged | 100.1/day | 100.1/day | 0 |
| **Total** | **490.1/day** | **173.1/day** | **-317/day (-64.7%)** |

Pre-141 figure includes `alert_cron_failures` (created live by migration 139 on the
`strange-merkle-c2d0b9` branch at cloud version `20260921172347`, ~6h45m before 141 folded
it into `ops_alerts_30min` — corrected by B-pass; this doc originally cited `20260921172242`,
which `list_migrations` shows is actually migration 138 (`subscriptions_cancelled_at_trigger`),
a sibling migration applied 65 seconds earlier, and originally estimated the gap at "~12h").
The "21 other jobs" total (100.1/day) is verified two
independent ways: summed directly from `backups/live_cron_jobs.json`'s 21 untouched
entries (16 once-daily = 16/day + `alert_cron_silence` + `alert_payment_flow_health`
hourly = 48/day + `morning_alert_deliver_early` `*/15 0-6*` = 28/day +
`morning_alert_deliver_late` `*/15 22-23*` = 8/day + `weekly_recap_ready_sunday` 1/week ≈
0.14/day = 100.14/day), and cross-checked as post-141-total minus the three changed-group
post-141 figures (173.1 − 24 − 48 − 1 = 100.1). Both agree — the table's earlier "20" was a
caption error only (B-pass caught it); the underlying arithmetic already summed 21 items.

### 2. Projected WAL specifically from `cron.job_run_details` — a smaller, different baseline than #1

The measured 451.0MB / 41.0MB-per-day figure (Root cause) covers 2026-09-10 to
2026-09-21 — `alert_cron_failures` existed for under half a day of that window, so it
contributed negligibly to the measurement. The rate that actually produced 41.0MB/day was
therefore ~394/day (490.1/day minus `alert_cron_failures`'s ~96/day), not 490.1/day. Using
the correct baseline:

- Projected post-141 rate as a fraction of the measured-era rate: 173.1 / 394 ≈ 43.9%
  remains → **~56% reduction** in this specific WAL source.
- **41.0 MB/day (measured) → ~18.0 MB/day (projected)**
- Total database WAL (Root cause: 1008.6MB/11days = 91.7MB/day measured) →
  **~68.7 MB/day projected** (~25% cut in *total* WAL, not just the cron-bookkeeping slice)

This is a linear extrapolation, not a new measurement — pg_cron's bookkeeping is
source-confirmed to be gated uniformly per invocation regardless of which job runs (Root
cause), but per-job detail-column length (error/return-message strings) is not perfectly
uniform, so treat ~18.0MB/day as an estimate, not a guarantee. **Re-run the
`pg_stat_statements` query from Root cause after ~11 days live (~2026-10-03) to confirm
against this projection.**

### Bottom line for the still-open Fix A decision

Fix F already captured roughly 56% of Fix A's original headline value (~41.0MB/day),
through a mechanism that needed no Supabase permission and no server restart. Fix A
pursued now, on top of Fix F, would eliminate the projected remaining ~18.0MB/day (down to
near-zero for this specific source) — still the single largest remaining lever (~26% of
post-141 total WAL, projected), but a materially smaller absolute number than when first
measured, because Fix F already ate into the same pool. Whether that remaining ~26% is
worth a support ticket plus a brief restart is the open decision (see Notes) — this
section exists to make that decision informed, not to make it.

## Tests

**`test/contracts/disk_io_audit_cleanup_batch_test.dart`** — source-grep presence test
(9 assertions: 8 for migration 141, 1 for migration 142 — verified via `grep -c "  test("`
and an actual `flutter test` run, `+9`, after a B-pass caught this doc originally
miscounting an 8-test file as 9/9). Chosen over a live-Postgres behavioral test because
every change here is Postgres config/schedule/schema DDL with no Dart runtime path; a
behavioral assertion would require real Supabase credentials in the test environment,
which this test suite does not carry for Edge/DB-level changes of this shape (precedent:
`test/sql/*_live_verify.sql` files are hand-run against live Postgres, not part of
`flutter test`). Pins: migration 141's four fixes are all present in their active
(non-rollback-comment) DDL; both new consolidated cron job names and the 8 deprecated
names appear correctly in `CRON_REGISTRY.md`; migration 142 creates the restored index
with `IF NOT EXISTS`. (No test covers migration 140 — it was withdrawn before merge.)

## Touched layers checked

| Tier | Status | Evidence |
|---|---|---|
| 1. Client code | not_applicable | No Dart/client code changes |
| 2. Hive | not_applicable | No Hive changes |
| 3. Postgres schema | fixed_in_this_batch | Migrations 141 and 142 both applied to `dedsavbjuwgarrhphgnl`, verified live. `flutter test test/contracts/disk_io_audit_cleanup_batch_test.dart` 9/9 green, mutation-proven end to end (both migrations' own assertions). Fix A (migration 140) attempted, failed with Postgres error 55P02, withdrawn |
| 4. Postgres data | not_applicable | No rows read/written/deleted |
| 5. Migrations applied | fixed_in_this_batch | `backups/applied_migrations.json` updated with migration 141's AND migration 142's entries in this commit |
| 6. Edge Function code vs deploy | not_applicable | No Edge Function changes |
| 7. Cron jobs | fixed_in_this_batch | 9→3 consolidation applied live, verified via `cron.job`; CRON_REGISTRY.md updated in parallel |
| 8. RLS policies | fixed_in_this_batch | `readiness_daily` policy rewritten and verified live via `pg_policy` |
| 9. Storage buckets + objects | not_applicable | No storage changes |
| 10. Secrets / API keys | not_applicable | No secret changes |
| 11. External services | not_applicable | No external service changes |
| 12. Client → server contract | not_applicable | No client-facing contract change |

## Notes

- **This diagnose-doc closes fixes B, C, D and F. Fix A is OPEN, blocked on a founder
  decision with a revised risk profile** (see below). Fix E (compute tier upgrade,
  Nano → Micro/Small, requires Pro plan) is deliberately excluded from this doc's scope
  entirely — it is a founder spend decision the founder explicitly chose to revisit after
  A-F land (2026-09-22, via AskUserQuestion), not a code change, tracked separately.
- **Fix A discovery, mid-batch**: `cron.log_run` is `context=postmaster` in `pg_settings`
  — Postgres's most restrictive GUC class, changeable only via server config at boot,
  requiring a full restart. `ALTER DATABASE ... SET` fails outright with error 55P02; it
  is not a retryable syntax issue. The founder had authorized migration 140 believing it
  was "fully reversible... a GUC not a schema change" (my own description, based on an
  incomplete understanding of this specific GUC's context before attempting it) — since
  the real action is now known to require a database restart (brief downtime for all
  clients) and possibly a support ticket or plan-tier check on Supabase's Nano/Free tier,
  I did not proceed on the original authorization. This needs a fresh, informed decision:
  pursue via Supabase's dashboard (if it exposes this) and accept a brief restart, or drop
  Fix A and rely on B/C/D/F plus the eventual compute upgrade (E).
- **Quantified impact analysis added 2026-09-22, same day, post-apply**: founder asked
  whether cadence reduction is a usable substitute lever given Fix A is blocked. Added the
  "Quantified impact of Fix F" section above — computed from live schedules
  (490.1→173.1 invocations/day, -65%) and projected against Root cause's empirical WAL
  measurement (~41.0MB/day→~18.0MB/day projected for the `cron.job_run_details` source
  specifically, ~56% cut). Deliberately keeps two different baselines separate
  (schedule-count reduction vs. the smaller rate that actually produced the measured WAL,
  since `alert_cron_failures` was only live for the last ~6h45m of the 11-day measurement
  window — corrected from an original, wrong "~12h" estimate, see the B-pass note below)
  rather than blending them into one percentage.
- **Self-triggered B-pass review (2026-09-22, before commit)**: per CLAUDE.md §4.3
  ("≥account code-review is SELF-INITIATED... do NOT wait to be asked"), dispatched a
  fresh context-blind reviewer against the full staged diff before this batch's first
  commit. Findings, all independently re-verified live before acting (never taken on the
  reviewer's word alone), full record: `docs/reviews/571c997e56b5-review.md` (renamed
  from its original `e100478657c7-review.md` after this fix round moved the staging
  hash — caught as a dead cross-reference by an independent round-2 re-review).
  - **P1, real regression, fixed**: dropping `idx_nutrition_log_items_food_id` (item D)
    removed the SOLE index backing `nutrition_log_items_food_id_fkey`. `idx_scan=0`
    (this doc's original justification) measures query-access paths only — it says
    nothing about whether an index backs a foreign key, which Postgres also uses for
    referential-integrity checks on the referenced table's side. Live `get_advisors`
    confirmed a new `unindexed_foreign_keys` finding that did not exist before 141.
    Checked the sibling drop (`idx_ai_coach_interactions_tool_calls_failed`) for the same
    blind spot — verified clean: `ai_coach_interactions`'s two FKs (`snapshot_id`,
    `user_id`) both have their own separate, still-live indexes, so this is an isolated
    fix, not evidence the other drop needs revisiting. Fixed: migration 142 (below),
    founder-authorized separately in chat and applied same day. Post-apply live
    verification: `pg_indexes` confirms the index exists; a fresh `get_advisors` run
    shows the `unindexed_foreign_keys` finding is gone (only the pre-existing,
    expected `unused_index` findings remain — 14, correctly including this
    freshly-recreated index again, exactly as predicted, since `idx_scan=0` was never
    the axis that mattered for it).
  - **P2, doc-only, fixed**: this doc, `backups/applied_migrations.json`, and the Touched
    Layers table all claimed the contract test was "9/9" when the file actually held 8
    `test()` blocks (verified via `grep -c` and an actual `flutter test` run: `+8`).
    Corrected throughout. The count is genuinely 9/9 again now, but only because
    migration 142 added its own 9th test — a coincidence worth stating plainly rather
    than letting the same number silently paper over the original miscount.
  - **P2, doc-only, fixed**: this doc cited the wrong migration's `cloud_version` for
    `alert_cron_failures` (see the "21 other jobs" paragraph above) and overstated the
    resulting gap as "~12h" when it is really ~6h45m. This *strengthens* rather than
    undermines the "negligible contribution to the 11-day measurement" reasoning the
    number was being used for — an even shorter window means even less opportunity to
    have contributed — so no other conclusion in the Quantified-impact section changes.
  - **P3, doc-only, fixed**: the "20 other jobs, unchanged" table row undercounted by one
    (the underlying 100.1/day arithmetic already summed 21 items correctly — a caption
    error only, not a computation error).
  - **P3, real but latent risk, not fixed (cannot be — 141 is immutable)**: none of
    migration 141's 9 `cron.unschedule('<name>')` calls are guarded, and
    `cron.unschedule()` on a genuinely-missing job name **raises a hard Postgres error**
    (verified live: `select cron.unschedule('definitely_does_not_exist_xyz_probe')` →
    `XX000: could not find valid entry for job`), not a silent no-op. This did not bite
    this time — all 9 names existed at apply time, confirmed by 141's own successful
    live application — but it was a genuine gap, most pointed for the
    `alert_cron_failures` unschedule given this same file's own comment discloses a
    live cross-branch race (that job was created by an uncommitted migration on a
    different branch). Since 141 cannot be edited post-apply, this is recorded here as a
    lesson for future migrations rather than a fix to this one: migration 142 uses
    `CREATE INDEX IF NOT EXISTS` for exactly this reason.
  - **Considered and NOT applied**: whether this diagnose-doc's A–F structure triggers
    §4.2's closure-YAML requirement ("every multi-item batch (≥4 findings/units)... MUST
    produce a `docs/audit/<batch>.closure.yaml`"). Decided no: that mechanism's own
    schema requires a `commit:` sha for every `closed_in_commit` item, which does not
    exist yet for a batch still staged as one pending commit (unlike the
    `food-logging-observations` precedent, which had 8 prior commits to cite by the time
    its closure YAML was written); and the established pattern for a single diagnose-doc
    with a per-item `proposed_fix` status (as this one already has) is the
    `touched_layers_checked` + regression-test mechanism, not a separate closure YAML,
    which precedent reserves for audit-shaped batches. Stated explicitly rather than
    silently skipped.
  - Everything else the reviewer was asked to independently verify came back clean:
    ivfflat `lists=10`, the RLS policy's wrapped `auth.uid()`, both intended dropped
    indexes actually gone, `cron.job`'s 24-job consolidated state, all 4
    `db_maintenance_nightly` cleanup functions' live existence, `cron.log_run`'s
    `postmaster` context, OI-236/OI-237's numeric framing, and — on independent
    re-verification here, not just the reviewer's own say-so — OI-235's "~93s"/"~116s"
    averages (the reviewer had flagged these as "unverifiable"; a direct requery
    reproduced both figures exactly: 93.1s and 116.0s, with a genuinely bimodal
    per-job distribution — most runs ~0.1s, one outlier per job at 25-31 minutes —
    added to OI-235's description as a sharper clue for whoever picks it up, not a
    correction).
- **Blast radius classified as `platform`**: the cron consolidation and RLS/index changes
  touch shared infrastructure rather than a single feature. Per §4.12.3, a
  `docs/plan-reviews/<branch>.md` record with ≥2 context-blind review rounds and
  `bpass: accepted` is required before merge to `main` —
  `docs/plan-reviews/claude-next-aab-decision-d1227b.md` (`verdict: converged`).
- **Pre-existing unrelated bug fixed opportunistically**: `pubspec.yaml` had two
  conflicting top-level `version:` keys (`1.0.0+45` inserted without removing the stale
  `1.0.0+44`), breaking the entire Flutter toolchain (`flutter test` failed with a YAML
  "Duplicate mapping key" error before any of this batch's own tests could run). Traced
  via `git diff` to an incomplete prior edit — `lib/core/constants/app_constants.dart`'s
  matching bump to `1.0.0+45` was done correctly, confirming intent. Fixed by removing the
  stale duplicate line; not otherwise part of this batch's scope.
- **Arithmetic error caught late**: this doc and the conversation preceding it stated
  "31→22 jobs" repeatedly. Verified against the live `select jobid, jobname from cron.job`
  count post-apply: **24, not 22** (9 old jobs removed, 2 new ones added = net -7, not -9).
  Corrected here and in `backups/live_cron_jobs.json`. Migration 141's own comment
  ("9 jobs -> 3", line 56) carries the same imprecision (should read "9 jobs -> 2, plus
  proactive_pr_detection separately re-cadenced") but is NOT edited — the migration is
  already applied and its hash is recorded in `backups/applied_migrations.json`; editing
  an applied migration's file, including comments, falsifies that audit trail per
  `supabase/migrations/CLAUDE.md`'s immutability rule.
- **Coordination note, corrected**: `alert_cron_failures` (folded into `ops_alerts_30min`
  here) was created by migration 139 on a separate in-flight branch
  (`claude/strange-merkle-c2d0b9`). Checked via `list_migrations` at apply time: 139, its
  sibling 138 (`subscriptions_cancelled_at_trigger`), and a follow-up
  `hermes_pass_fixes_138_139` are all **already live** on `dedsavbjuwgarrhphgnl`
  (cloud versions 20260921172242/172347/181434) despite their `.sql` files remaining
  uncommitted in that other worktree as of this writing. Migration numbers 140 and 141
  were chosen to avoid colliding with those uncommitted files once they eventually commit.

## Mutation proof (rule §4.4.21)

**Mutation:** Changed `lists = 10` → `lists = 100` on migration 141's active DDL line
(line 30 only, not the rollback comment).

**Test output (RED):**
```
00:00 +0 -1: ... migration 141 retunes memory_embeddings ivfflat for actual row count [E]
  Expected: contains 'lists = 10)'
    Actual: '...WITH (lists = 100);...'
     Which: does not contain 'lists = 10)'
```

**First mutation attempt was a false pass, corrected before trusting the test:** the
initial assertion `contains('lists = 10')` did NOT redden against this same mutation,
because `'lists = 100'` also contains `'lists = 10'` as a substring — the digit sequence
"10" is a prefix of "100". A second, independent bug compounded it: the negative assertion
used quoted-string syntax (`lists = '100'`) that doesn't match this migration's actual
unquoted SQL (`lists = 100`), and was additionally scoped against the WHOLE file including
the rollback comment block (which legitimately contains the old `lists = 100` value as
restore DDL), so it would have false-failed against a correct file too. Both fixed by
scoping the check to `migration141Active` (file content before the `-- Rollback` marker)
and anchoring on the closing paren (`lists = 10)` vs `lists = 100)`) to disambiguate the
digit-prefix collision.

**After revert to `lists = 10` (GREEN):** all tests in the file passed (8/8 at the time
this mutation was run — migration 142's test was added later, after a B-pass found the
FK-index regression documented in Notes; the file is 9/9 as of this doc's current state).

This proves `test/contracts/disk_io_audit_cleanup_batch_test.dart` actually catches a
regression on the ivfflat tuning value, and documents why the first version of this
assertion would not have.

### Migration 142's own test (added by this batch's fix round)

Migration 142 was applied live before this doc's final edit, making it immutable per
`supabase/migrations/CLAUDE.md` — so this mutation used that file's documented
scratch-copy protocol (`cp` to a backup, mutate, test, `cp` back, verify sha256),
**not** `git checkout` (which silently converts line endings and would desync the
ledger's hash without `git status`/`git diff` showing anything — the exact trap that
section warns about).

**Pre-mutation sha256 check:** `53592ae280cc9f26de68c6c65c9d5aee37161a26005734dfea354a213708b6ee`
— matches `backups/applied_migrations.json`'s migration-142 entry exactly, confirmed
BEFORE mutating.

**Mutation:** Removed `IF NOT EXISTS ` from the `CREATE INDEX` line.

**Test output (RED):**
```
00:00 +8 -1: ... migration 142 restores the FK-support index migration 141 wrongly dropped [E]
     Which: does not contain 'CREATE INDEX IF NOT EXISTS'
00:00 +8 -1: Some tests failed.
```
(8 other tests unaffected, confirming the mutation was isolated to this one file/assertion.)

**Restored from the pre-mutation backup; sha256 re-verified as EXACTLY
`53592ae280cc9f26de68c6c65c9d5aee37161a26005734dfea354a213708b6ee`** — confirms exact
restoration, not just a visual match. **After restore (GREEN):** 9/9 tests pass.

This proves the new test genuinely discriminates on the `IF NOT EXISTS` guard (the
specific defensive practice adopted in direct response to this same batch's
unguarded-`cron.unschedule()` finding), rather than only checking table/column-name
presence, which would pass against almost any plausible version of this migration.
