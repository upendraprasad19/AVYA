---
bug_id: h1a2b3
date: 2026-09-21
batch: observation-batch-and-digest-redesign (self-triggered Hermes pass, catastrophic tier)
status: fixed
blast_radius: catastrophic
symptom: |
  Two independent live defects in migrations 138 and 139, both shipped
  earlier in this SAME batch, found by an 8-lens self-triggered Hermes pass
  run before merge (required because this batch's blast-radius classifies
  catastrophic — migration 138/139/140 all define a `SECURITY DEFINER`
  function). Neither had a founder-facing report; both were caught by
  direct live-database verification during the pass.

  (1) `alert_cron_failures` (migration 139) misfired IN PRODUCTION: its
  `status = 'started'` stuck-job branch had no upper time bound, so a job
  that crashed mid-run (leaving a `cron_call_log` row permanently
  'started' — `logCronEnd` never runs on a crash/timeout/OOM) kept paging
  the founder hourly on data with no live incident behind it. Confirmed
  live: two rows from a crashed tick on 2026-09-19 04:15 UTC were still
  'started' 2.5 days later, both functions had run successfully many times
  since, and `public.alerts` id=40 had already fired on this stale data
  (detected 2026-09-21 17:30 UTC).

  (2) `private.set_subscription_cancelled_at()` (migration 138) only
  cleared `cancelled_at` FORWARD (status -> 'cancelled'); a reactivation
  ('cancelled' -> anything else, e.g. a manual dashboard revert — confirmed
  live as the ONLY way `status='cancelled'` is ever set today, since no
  application code writes it) left a stale, permanent `cancelled_at` stamp.
  `founder_digest_content.ts`'s B3 "Cancelled (manual)" reader filtered on
  `cancelled_at` alone with no `status` check, so a reactivated, paying
  subscriber would have been misreported as a cancellation forever. Also:
  the trigger was `BEFORE UPDATE` only, so a row INSERTed directly with
  `status='cancelled'` fired no trigger at all and stored a NULL stamp.
concept: cron_alert_dedup_window / subscription_cancelled_at_lifecycle
sot_registry_entry: not_applicable
writers:
  - { file: supabase/migrations/140_hermes_pass_fixes_138_139.sql, method_or_widget: "cron.schedule('alert_cron_failures', ...) — 6h stuck-window bound", line: 77 }
  - { file: supabase/migrations/140_hermes_pass_fixes_138_139.sql, method_or_widget: "private.set_subscription_cancelled_at() — TG_OP branch + reactivation clear", line: 113 }
readers:
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: "alertsRead (renders public.alerts rows into the digest)", line: 694 }
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: cancelledYesterdayRead, line: 852 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: cron_call_log, alerts, subscriptions
cloud_columns: [cron_call_log.status, cron_call_log.started_at, subscriptions.status, subscriptions.cancelled_at]
contract_test_path: test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [public.alerts source=alert_cron_failures, severity=critical]
cross_account_guard: Not applicable — no cross-user data path; both fixes are DB-internal (cron scheduling + a single-row trigger).
forbidden_patterns_checked:
  - "editing migrations 138/139 directly — both are IMMUTABLE (already applied to prod); corrections MUST land as a new migration per supabase/migrations/CLAUDE.md"
  - "acknowledging the misfired alert id=40 before deploying the fix — acknowledging re-arms the SAME dedup window and would have paged again on the next 15-minute tick rather than waiting out the hour (a pre-existing dedup-convention property shared by all 6 alert_* jobs, filed separately, not fixed here — see the OI filed alongside this migration)"
proposed_fix: |
  New migration 140 (immutable-migration correction pattern): (1)
  cron.unschedule + cron.schedule 'alert_cron_failures' with its
  status='started' branch now bounded to
  `started_at >= now() - interval '6 hours'` in addition to the existing
  `< now() - interval '1 hour'` check — long enough that no legitimate
  Edge-Function runtime on this project is masked, short enough to stay
  well inside sibling alert_cron_function_dead's 8-day horizon, so a job
  still broken past 6h remains covered by that sibling at its own time
  horizon. (2) CREATE OR REPLACE the trigger function with a TG_OP branch:
  on INSERT, stamps cancelled_at if status='cancelled' at insert time; on
  UPDATE, keeps the existing forward-stamp AND adds the reverse clear
  (status leaves 'cancelled' -> cancelled_at := NULL). Trigger widened
  BEFORE INSERT OR UPDATE. Belt-and-suspenders: founder_digest_content.ts's
  cancelledYesterdayRead also gets an explicit `.eq('status','cancelled')`
  filter (Hermes L22 F2) so the count stays correct even for a row some
  future writer stamps out of band.
regression_test_planned:
  - test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql (new — same live-Postgres, rolled-back-transaction pattern as test/sql/onconflict_live_arbiter.sql and test/sql/oi46_daily_cap_triggers_live_verify.sql; run live 2026-09-21, all 4 cases ok — see AMENDMENT below for the 4th — zero residue confirmed by a post-run leak check)
impact_analysis: |
  Fix 1 is schedule-only (unschedule+reschedule the SAME job under the SAME
  name, cron.schedule assigns a new jobid — expected, documented in the
  migration's own post-apply verification). No historical cron_call_log
  rows are modified; the two known-stale 2026-09-19 rows simply stop
  matching the (now-bounded) query on the next tick, and age out of
  cron_call_log entirely via the pre-existing 7-day cleanup_cron_call_log()
  sweep. Fix 2 is additive to the trigger function body (CREATE OR REPLACE,
  same signature — preserves the existing ACL per supabase/migrations
  /CLAUDE.md's "signature change loses ACL" pitfall) plus one new ELSIF
  branch; verified live (rolled back) that with_cancelled_at was 0 across
  all 13 subscriptions rows before this migration, so there is nothing to
  backfill — forward-looking correctness only.
touched_layers_checked:
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "information_schema check confirms no schema shape change from 138 (cancelled_at column, its type and nullability are unchanged by 140 — only the trigger function body and the cron job's SQL body changed)." }
  - { tier: 5, name: "Migrations applied", status: fixed_in_this_batch, evidence: "Migration 140 applied live via mcp apply_migration (name hermes_pass_fixes_138_139), explicit founder authorization obtained via AskUserQuestion before the live apply. backups/applied_migrations.json updated in the same commit." }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "SELECT jobid, jobname, schedule, active FROM cron.job WHERE jobname='alert_cron_failures' — one row, schedule='*/15 * * * *', active=true, jobid differs from 139's (expected: unschedule+reschedule always mints a new jobid). SELECT count(*) FROM cron_call_log WHERE status='started' AND started_at < now()-interval '1 hour' AND started_at >= now()-interval '6 hours' — returned 0, confirming the two known 2026-09-19 04:15 UTC stale rows (now ~2.5 days old) no longer match." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Single-query BEGIN; UPDATE ... SET status='cancelled' RETURNING; UPDATE ... SET status='active' RETURNING; ROLLBACK; against one real active subscription row confirmed cancelled_at stamps on cancel and clears back to NULL on reactivation, with the transaction rolled back (no live side effect, no real row mutated)." }
mutation_proven:
  mutated: "Not applicable in the mutate-and-rerun-a-Dart-test sense (rule 21) — this is a live-Postgres DDL change. Instead ran test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql (new, this batch) live against dedsavbjuwgarrhphgnl via execute_sql inside a BEGIN...ROLLBACK, exercising the exact predicate/trigger migration 140 installed with synthetic rows — same standard as supabase/migrations/CLAUDE.md's onconflict_live_arbiter precedent."
  result: "All 4 cases returned status='ok' (originally 3 — see AMENDMENT below for the 4th, added same day by a B-pass): stuck_window_bounds_2h_in_7h_out (a 2h-old synthetic row counts, a 7h-old one does not — the exact predicate migration 140 installed), cancelled_at_stamps_on_cancel, cancelled_at_clears_on_reactivation (a synthetic row cancelled then reactivated correctly ends with cancelled_at back to NULL — something the PRE-140 function body, re-read from migration 138's own text, has no branch that can ever do), and cancelled_at_stamps_on_direct_insert. Post-run leak check (separate query, after the ROLLBACK) confirmed 0 residual rows in cron_call_log/subscriptions/public.users for both synthetic user ids."
  confirmed_applied: "Live SQL query results (not memory, not migration-file prose) — see touched_layers_checked evidence above and the SQL file's own header."
---

## Summary

Migrations 138 and 139, both shipped earlier in this same batch, carried two
independent live defects — one of them (the stuck-alert misfire) already
actively producing a false-positive founder page in production. Both were
found by an 8-lens self-triggered Hermes pass, run because this batch's
blast-radius classifies catastrophic and the merge gate
(`scripts/check_plan_review_record_exists.dart`) hard-requires a
`hermes: accepted` plan-review record at that tier.

## Root cause

(1) `alert_cron_failures`'s stuck-job branch assumed `cron_call_log.status`
can reliably distinguish "genuinely still running" from "crashed and never
updated." It cannot — `logCronEnd` only runs if the isolate reaches it, so a
timeout/OOM/crash leaves a row `'started'` permanently, and the un-bounded
query kept re-matching (and re-alerting) on it indefinitely.

(2) `private.set_subscription_cancelled_at()` treated `cancelled_at` as a
write-once forward stamp, but the investigation baked into migration 138's
own header already established that the ONLY writer of `status='cancelled'`
in this codebase is a manual dashboard/SQL edit — which can just as easily
revert the status. A trigger claiming to be "self-maintaining regardless of
HOW the status changes" needs to handle both directions of that change, not
just one.

## Fix

New migration 140 (both 138 and 139 are immutable, already applied):
`cron.unschedule` + `cron.schedule` re-registers `alert_cron_failures` with
its stuck-branch bounded to a 6-hour lookback window; `CREATE OR REPLACE
FUNCTION private.set_subscription_cancelled_at()` adds the reactivation-clear
branch and widens the trigger to `BEFORE INSERT OR UPDATE`. A defensive
`.eq('status', 'cancelled')` filter was also added to
`founder_digest_content.ts`'s B3 reader as belt-and-suspenders.

## Verification

- New `test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql`
  run live against synthetic rows inside a rolled-back transaction: both the
  stuck-window bound and the reactivation clear behave correctly (3/3
  `status='ok'`), with a separate post-run query confirming zero residual
  rows.
- Live query against the real (pre-existing) stale rows proved the
  stuck-window bound excludes the two known-stale rows that had already
  triggered the false alert.
- `cron.job` confirmed the job re-registered active on the same schedule.
- Migration 140 applied live via MCP `apply_migration` with explicit,
  separate founder authorization (obtained after the broader batch-level
  "commit push merge" instruction — per this project's rule that a live
  prod apply always needs its own per-action approval regardless of
  broader batch approval).

## Files changed

- Created: `supabase/migrations/140_hermes_pass_fixes_138_139.sql`
- Created: `test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql`
- Modified: `supabase/functions/_shared/founder_digest_content.ts` (B3 defensive filter)
- Modified: `backups/applied_migrations.json` (migration 140 entry)
- Created: this diagnose-doc.

## Note on migration 138's own verification snippet (durable trap, not fixed here)

Migration 138's own "Post-apply verification" comment block contains a bare,
non-transactional `UPDATE ... SET status = 'cancelled' ... RETURNING` against
a real, randomly-selected active subscription row, with only a comment
("then manually revert this test row") relying on the operator to remember
to undo it by hand. Run literally as written, it permanently cancels a real
subscription. Migration 138 is immutable and cannot be edited to wrap this
in a transaction. Documented as a durable pitfall in root `CLAUDE.md` §4.9
(this same commit) rather than silently left for the next person to
discover by running it.

## AMENDMENT (2026-09-21) — B-pass round on the full batch, 2 findings

A self-triggered B-pass on the FULL 69-file staged batch (required before
the `--no-ff` merge per CLAUDE.md §4.3, catastrophic tier) ran two fresh
context-blind reviewers against everything above, plus every other file in
the batch. Two of its findings concern this diagnose-doc's own fixes:

**Finding (Reviewer A, P2, blast_radius_mismatch)** — `alerts/_thresholds.yaml`'s
`cron_failures` entry still described the stuck-job branch as having "no
upper bound," even though migration 140 (above) added the 6-hour bound
specifically because the unbounded version was already misfiring live. The
threshold registry — the documented single reference for tuning this
alert — was never updated for the fix this same doc describes, and neither
this doc nor the Hermes report mentioned `alerts/_thresholds.yaml` at all.
**Fixed**: `alerts/_thresholds.yaml`'s description now states the 6-hour
bound, adds a `stuck_window_upper_bound_hours: 6` field mirroring the
migration's own `jsonb_build_object`, and `defined_in_migration` now names
both 139 and 140.

**Finding (Reviewer B, P3, missing_input / test-coverage gap)** — migration
140 fixes TWO distinct defects in `private.set_subscription_cancelled_at()`:
the reactivation-clear (Case 2 above) AND widening the trigger to
`BEFORE INSERT OR UPDATE` so a row inserted directly with
`status='cancelled'` also gets stamped. The live-verify SQL's original 3
cases only exercised the UPDATE-driven reactivation-clear path — the
INSERT-driven stamp path (the migration's OTHER named reason for existing)
had zero live coverage. **Fixed**: added Case 3
(`cancelled_at_stamps_on_direct_insert`) to
`test/sql/migration_140_stuck_alert_and_cancelled_at_live_verify.sql`,
re-ran all 4 cases live against `dedsavbjuwgarrhphgnl` inside the same
rolled-back transaction — all 4 returned `status='ok'`, including the new
case. A follow-up query confirmed zero residual rows for both synthetic
user ids (`...140001` and the new `...140002`).

Neither finding indicated the underlying migration 140 fix itself was
wrong — both were documentation/coverage gaps in the diagnose-doc's own
artifacts, found by a review round that ran AFTER this doc was first
written. Recorded here rather than silently absorbed, per this repo's own
convention (see the "Note on migration 138" section above, which does the
same for a defect found but not fixed).
