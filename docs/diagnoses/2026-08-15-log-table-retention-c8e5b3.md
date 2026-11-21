---
bug_id: c8e5b3
date: 2026-08-15
batch: oi132-cron-registry
blast_radius: platform
status: fixed
symptom: >
  Two log tables grew without bound: cron.job_run_details (~29,044 rows) and
  public.client_errors (~10,654 rows). A migration named `log_table_retention`
  was applied to prod on 2026-08-15 to bound them — 14-day retention on the
  former, 30-day on the latter, plus a daily VACUUM (ANALYZE) on each.
  THE MIGRATION IS NOT THE BUG. This doc exists because the migration left NO
  artifact of any kind: no .sql file, no backups/applied_migrations.json entry,
  no cron-registry entries for the four jobs it created, and no diagnose-doc —
  even though its own header cited `Linked diagnose-doc: c8e5b3`, this file,
  which did not exist until 2026-08-20. It also promised a "reverse block in the
  repo file" for rollback; there was no repo file to hold one.
  The compounding defect, and the reason this is platform-tier rather than a
  paperwork nit: Gate 31 (scripts/check_cron_registry.dart) enforced
  cron-registry parity by SCANNING supabase/migrations/*.sql for
  cron.schedule(...). A migration with no file is therefore not merely un-gated
  but UNSEEABLE — the gate reported green for five days while two
  row-destructive jobs ran daily against production. A missing file does not
  skip that gate; it defeats it by construction.
concept: cron_registry_parity
sot_registry_entry: cron_registry_parity
writers:
  - { file: supabase/migrations/121_log_table_retention.sql, line: 1, source: "RECONSTRUCTION of the applied statements, recovered verbatim from supabase_migrations.schema_migrations on 2026-08-20. Marked DO-NOT-APPLY: the statements already ran, and a replay would run the DELETEs immediately rather than on schedule" }
  - { file: backups/live_cron_jobs.json, line: 1, source: "NEW. Committed snapshot of live cron.job — the second, file-independent input Gate 31 now checks. 28 jobs at time of writing" }
  - { file: docs/operations/CRON_REGISTRY.md, line: 48, source: "the four missing jobs registered: jrd_retention_daily, client_errors_retention_daily, jrd_vacuum_daily, client_errors_vacuum_daily" }
readers:
  - { file: scripts/check_cron_registry.dart, line: 72, source: "Gate 31, RE-SCOPED. Input B (the snapshot) is read FIRST and hard-fails on a missing, malformed or EMPTY snapshot rather than silently degrading to input A alone. READ ORDER IS THE FIX: input B was first written BELOW input A's `migrations dir absent -> exit(0)` branch, so a tree without that directory passed having consulted neither input — the same never-ran-so-it-passed shape, reintroduced by the edit that closed it. Caught by this commit's B-pass; that branch is now a NOTE, not an exit" }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: cron.job
cloud_columns: [jobid, jobname, schedule, active]
contract_test_path: test/scripts/cron_registry_snapshot_gate_test.dart
ist_handling:
  - { file: docs/operations/CRON_REGISTRY.md, line: 48, fn: "pg_cron runs in UTC (cron.timezone = GMT); the registry's IST column is UTC+5:30. 22 4 * * * UTC = 09:52 IST" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "a live cron job absent from CRON_REGISTRY.md", absent: true }
  - { pattern: "Gate 31 passing when backups/live_cron_jobs.json is missing or empty", absent: true }
proposed_fix: >
  Reconstruct the migration file, manifest entry, diagnose-doc and registry rows
  from live state; then give Gate 31 a second input that a fileless migration
  cannot hide from — a committed snapshot of live cron.job. Snapshot rather than
  live query because CI holds no Supabase credentials (OI-105), so a live query
  would silently skip there: a gate passing because it never ran, which is the
  same failure one layer up.
regression_test_planned: [test/scripts/cron_registry_snapshot_gate_test.dart]
impact_analysis: >
  NO USER IMPACT, and no data was lost beyond what the migration was designed to
  delete. The two cleanup functions are correct: the jrd one always spares the
  newest run row per job, and the client_errors one is a plain 30-day age cut.
  Both are SECURITY DEFINER and — unlike migration 120 (a9d3f1) — both carry the
  full REVOKE ALL FROM PUBLIC + REVOKE ALL FROM anon, authenticated +
  GRANT EXECUTE TO postgres hygiene, verified against the recovered statements.
  So this is an OBSERVABILITY failure, not a correctness one: for five days
  nobody reading the repo could have known that four cron jobs existed, that two
  of them delete rows daily, or how to roll them back. The deleted rows are not
  recoverable, which is exactly why the absence of a rollback block mattered.
  The fix changes no production behaviour. It adds a file, a snapshot, four
  registry rows and a second gate input; the live jobs are untouched.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "no client code touched — this is migrations, ops docs and a gate script" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "no Hive access" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "the two cleanup functions read live from pg_proc; the reconstruction is byte-faithful to schema_migrations.statements, not rewritten from memory" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "no data written by this batch. The migration's own deletions continue on their existing schedule, unchanged" }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "121 added to backups/applied_migrations.json recording the ORIGINAL 2026-08-15 apply, not a new one. Gate 39 PASS" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "no Edge Function involved — all four jobs are intra-DB" }
  - { tier: 7, name: cron_jobs, status: fixed_in_this_batch, evidence: "all four registered. Live cron.job re-queried 2026-08-20: 28 jobs, all active; registry now covers 28 of 28 (was 24 of 28)" }
  - { tier: 8, name: rls_policies, status: verified, evidence: "unchanged. Both SECURITY DEFINER functions carry REVOKE ALL FROM PUBLIC + FROM anon, authenticated + GRANT EXECUTE TO postgres — confirmed in the recovered statements" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or written; these jobs use no cron_secret (intra-DB)" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "none" }
  - { tier: 12, name: client_server_contract, status: not_applicable, evidence: "no client-server contract involved" }
related_bugs:
  - { id: a9d3f1, relation: "the SECURITY DEFINER grant defect this migration did NOT have — cited so a future edit does not 'simplify' its correct revoke lines away" }
recurrence: >
  The generalisable lesson is about GATE INPUTS, not about cron. Gate 31 was
  well-built, actively useful, and had caught real drift before — and it was
  blind to this because its input was the migration FILES, and the failure mode
  was a migration with no file. Measured 2026-08-20: 28 live jobs, 24
  registered, 4 missing, and the 4 missing were exactly the fileless
  migration's. The gate's blind spot accounted for 100% of the gap; everything
  it could see, it had kept perfect.
  So: when a gate derives its worldview from artifacts in the repo, ask what
  happens when the artifact is simply absent. Tightening the scan never fixes
  that, because the scan's input is the thing that is missing. The fix is always
  a second input with a different provenance — here, live state.
  Same shape as OI-78's unbuilt allowlist gate and rule 24's "its own test never
  invoked main()". A gate that cannot fail, and a gate that cannot see, are the
  same defect wearing different clothes.
---

# A migration with no file defeats the gate built to catch it

## What was missing

| artifact | before | after |
|---|---|---|
| `supabase/migrations/*.sql` | absent | `121_log_table_retention.sql` (reconstruction, DO-NOT-APPLY) |
| `backups/applied_migrations.json` | no entry | entry recording the 2026-08-15 apply |
| diagnose-doc `c8e5b3` | cited, did not exist | this file |
| `CRON_REGISTRY.md` | 0 of 4 jobs | 4 of 4 |
| rollback block | promised "in the repo file" | inline, DDL-only, with the honest caveat |

## Why the count was wrong twice

OI-132 was first filed saying **two** cron jobs. That came from a reviewer that
had filtered on retention-shaped names, and it was propagated without
re-derivation. Recovering the statements and re-querying `cron.job` shows
**four**, all active — the two `VACUUM (ANALYZE)` jobs are not row-destructive
but were equally unregistered and equally invisible.

Worth stating plainly because it is the same error the whole class is about:
a claim was carried one layer up without being re-checked at the layer that
could falsify it.

## The gate fix, and what it deliberately does not claim

Gate 31 now reads two inputs: the migration scan (unchanged) and a committed
snapshot of live `cron.job`. The snapshot input hard-fails when the file is
missing, malformed, or **empty** — an empty snapshot would make every assertion
built on it vacuous, which is precisely the Gate-44 shape.

It does **not** prove the snapshot is fresh. Nothing in CI can, without Supabase
credentials the repo does not have (OI-105). This gate proves
registry-vs-snapshot parity and says so in its own header rather than implying
more. Regenerating the snapshot is a documented step on any migration that
schedules or unschedules a job.

## Mutation proof

| mutation | result |
|---|---|
| delete the 121 file, jobs still live in the snapshot (**the OI-132 scenario**) | **RED** — all four named, tagged `LIVE on the project` |
| delete the snapshot file | **RED** — refuses to downgrade to the migration scan alone |
| empty the snapshot to `[]` | **RED** — refuses a vacuous pass |
| malformed snapshot JSON | **RED** |
| a job in a migration file but not the registry, snapshot clean | **RED** — input A not masked by adding input B |
| everything registered | green |
