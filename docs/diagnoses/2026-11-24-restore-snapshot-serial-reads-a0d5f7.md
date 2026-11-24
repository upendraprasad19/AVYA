---
bug_id: a0d5f7
date: 2026-11-24
batch: oi348-walk-fixes Landing 2 (B10)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-348 walk A8 (AAB 1.0.0+50, 2026-11-22): a sign-in restore took a long time. Live 24 h (2026-11-22/23): restore-user-snapshot execution_time_ms 4.8 to 97.5 s, not tracking body size (3.7 KB took 34.5 s, 328 KB took 4.8 s). client_errors for the 97 s case: apply steps A 1 ms, B 333 ms, C 5 ms, sub 254 ms, so the time is spent waiting for the function. In the walk's case the client's standalone readiness read took 2.8 s on top. The function issued ~33 requests strictly one after another (e28cdab8 index.ts:153-268, no Promise.all), each 150 to 650 ms on a slow backend.
concept: restore_user_snapshot_paged_reads
sot_registry_entry: restore_user_snapshot_paged_reads
writers:
  - { file: supabase/functions/restore-user-snapshot/restore_reads.ts, method_or_widget: "READS: the 29 bundle reads in key order, each scoped to v_uid (moved verbatim from index.ts)", line: 48 }
  - { file: supabase/functions/restore-user-snapshot/restore_reads.ts, method_or_widget: "assembleTables: runLimited over READS (at most RESTORE_READ_CONCURRENCY in flight), tables built by INPUT index, timing line in a finally", line: 257 }
  - { file: supabase/functions/restore-user-snapshot/paged_reads.ts, method_or_widget: "readPaged: the page budget is charged per page inside the page factory (was per read)", line: 287 }
  - { file: supabase/functions/restore-user-snapshot/index.ts, method_or_widget: "serve handler: auth timed, ONE budget per request, parseReadConcurrency(env) per request, assembleTables", line: 137 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_attemptSingleCallRestore: the readiness read starts before the Edge Function call (RestoreReadinessPrefetch.start), consumed in step B", line: 2387 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: "_attemptSingleCallRestore -> validatedSnapshotTables (29 keys, schema_version 1; unchanged)", line: 2387 }
  - { file: lib/core/services/sync/sync_health.dart, method_or_widget: "_restoreReadiness: preFetched rows, or its own read through the shared _fetchReadinessRows", line: 132 }
  - { file: lib/core/services/sync/restore_readiness_prefetch.dart, method_or_widget: "RestoreReadinessPrefetch.consume: ok -> rows; failed -> report then own read; none -> own read", line: 63 }
hive_key_prefix: "healthBox readiness_<date> (unchanged); configBox disable_restore_overlap (new kill switch)"
hive_key_formula: "n/a (no key changes)"
sync_methods: []
restore_methods: [_attemptSingleCallRestore, _restoreReadiness]
cloud_table: "the 29 bundle reads (unchanged set) + readiness_daily"
cloud_columns: ["unchanged"]
contract_test_path: test/contracts/restore_user_snapshot_paged_reads_wiring_test.dart
ist_handling: ["none: no date logic changed"]
provider_invalidations: ["none: same restore writes in the same order"]
telemetry_op_types:
  success: ["restore_timings (Edge Function log line: request_id, auth_ms, reads_ms, limit, ok, <read>_ms)"]
  failure: [restore_readiness, sync_service_single_call_restore_fault]
cross_account_guard: "Unchanged: vUid is validated (UUID, from getUser) before any read is built, every READS tuple scopes to it (wiring pin), no client-supplied id. The prefetched readiness rows are read for the restoring userId and used only after the existing owner re-check before step A; on every other exit they are dropped."
forbidden_patterns_checked:
  - { pattern: "tables assigned in completion order (results[i] keyed by finish)", absent: true }
  - { pattern: "a READS tuple without vUid", absent: true }
  - { pattern: "a builder created before its slot (eager thunks)", absent: true }
  - { pattern: "parseInt for RESTORE_READ_CONCURRENCY", absent: true }
  - { pattern: "a failed readiness prefetch passed to _restoreReadiness as null / [] (silent empty restore)", absent: true }
  - { pattern: "the subscription refresh overlapped with the restore writes", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-walk-fixes-landing2.md (v4 CONVERGED, Unit B10).
  1. Edge Function: the reads move verbatim into restore_reads.ts (READS tuples [name, "paged"|"query", fn]); assembleTables runs them through runLimited (lazy thunks, at most `limit` in flight, results in INPUT order, first error rejects after the in-flight reads settle, nothing new starts). limit = parseReadConcurrency(env RESTORE_READ_CONCURRENCY), read per request: absent/blank -> 3, not an integer -> 1, clamp 1..8. 1 = the old serial order (rollback without a redeploy).
  2. The page budget is charged per page inside readPaged's page factory, so 13 concurrent paged reads still share one budget of TOTAL_PAGE_BUDGET pages.
  3. A `restore_timings` log line (names and numbers only) per request, written in a finally so a failed or slow restore logs it.
  4. Fail-closed unchanged: any rejection -> the same 500 restore_snapshot_failed -> the client's verbatim legacy restore.
  5. Client: the readiness read starts concurrently with the Edge Function call; step B consumes it. Failed -> reported (restore_readiness) then _restoreReadiness does its own read. Kill switch configBox disable_restore_overlap -> today's serial read. The subscription refresh is NOT overlapped (it read-modify-writes the progress map the restore steps merge).
regression_test_planned: |
  supabase/functions/restore-user-snapshot/restore_reads_test.ts (18): golden parity at limit 1 and 3 (bundle byte for byte, request chains per table) against testdata/restore_bundle.golden.json, recorded ONCE from the e28cdab8 serial body in a scratch harness against fake_restore_db.ts; READS order and kinds; runLimited (limit, input order, lazy, first error after in-flight settle, sync throw, empty); the fake DB's in-flight cap; no builder before its slot; one failed read rejects + timing line ok=false; page budget binds under concurrency at 1/3/8; no starvation under budget; the timing line; the clamp table.
  test/sync/restore_readiness_prefetch_test.dart (13): ok -> rows, no second read; empty ok stays empty; failed -> report then own read (never empty); sync throw; throwing report still reads; switch on -> no prefetch; switch values; the read starts at start(); an unconsumed failed prefetch raises no unhandled error (zone); wiring: start before callFunction through _fetchReadinessRows + configBox, step B consume under 'readiness_daily' with the own read taking NO argument, one shared read in sync_health.dart.
  Repointed (never loosened): restore_user_snapshot_paged_reads_wiring_test.dart (rewritten against the READS tuples), restore_user_snapshot_freezes_projection_parity_test.dart, user_preferences_coaching_notes_writer_to_reader_test.dart; SoT rows at the restore entry, the paged-reads entry, the user_preferences reader and the referral_redemptions reader.
mutation_proof: |
  Rule 21. 13 of 13 KILLED, each applied (grep -c >= 1, or a grep showing the swapped lines) and restored by cp + cmp. Detail below.
impact_analysis: |
  The function's wall time drops from the sum of ~33 serial requests to roughly the sum divided by the cap (3), plus auth and cold start; the restore_timings line says which part dominates. The bundle is byte-identical (golden). The client hides the readiness read behind the function call. Rollback levers: RESTORE_READ_CONCURRENCY=1 (no redeploy), the client switch disable_restore_overlap, the existing disable_single_call_restore, and the previous payload in backups/edge_function_payloads/.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "restore_readiness_prefetch.dart (new, pure), sync_service.dart _attemptSingleCallRestore, sync_health.dart _fetchReadinessRows; 13 tests green." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Same writes (readiness_<date> additive, local-wins); only the read's start time moved." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Live 2026-11-23: max_connections 60, 3 PostgREST connections at rest, statement_timeout 2 min; a cap of 3 concurrent reads per request is within that." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "restore_reads.ts + index.ts + paged_reads.ts; deno check clean; 122 Deno tests green. Deploy (emit_payload --auto follows imports only, so fake_restore_db.ts and the golden are not shipped) pending a founder go; the version is recorded in this doc then." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "service_role reads, scoped in code (unchanged, pinned)." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "New optional env RESTORE_READ_CONCURRENCY; absent = 3 (no secret needed)." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Bundle shape byte-identical to the serial code (golden at limit 1 and 3); client validation unchanged. Live before/after execution_time_ms + restore_timings after the deploy." }
recurrence: "Not a recurrence. e4c1d7 fixed the paging correctness of the same function (every row returned); this is its latency. The open_issues text (OI-348) asked for this re-measure."
related_bugs: [e4c1d7]
---

# a0d5f7 - restore-snapshot-serial-reads

## What happened
`restore-user-snapshot` awaited about 33 reads one after another. On a slow backend each took 150 to 650 ms, so the function alone ran 5 to 21 s before cold start and queueing; the worst live call took 97.5 s while the phone applied the result in under 1 s.

## The fix
The reads run at most 3 at a time (env `RESTORE_READ_CONCURRENCY`, 1..8), in a pool that keeps the bundle's key order and the fail-closed 500. The page budget is charged per page so concurrent paged reads still share it. A per-request `restore_timings` line names where the time goes. On the phone, the readiness read starts with the function call instead of after it. See the frontmatter.

## What the golden proves, and what it cannot
`testdata/restore_bundle.golden.json` was recorded once from the e28cdab8 serial body against `fake_restore_db.ts`. The new code matches it byte for byte at limit 1 and 3, and issues the same request chains (a per-table, order-independent multiset; the plan said keyed by read name: per table is equivalent here because the three `user_progress` reads differ by their select). The fake resolves no embeds and has no RLS, so the golden says nothing about embed nesting or row-level security; those are unchanged code, pinned by the wiring test.

## Mutation results
13 of 13 KILLED.
Server (Deno suite, 122 tests): D1 per-page charge removed (5 red); D2 results by completion order (4); D3 `user_profile` and `users` tuples swapped (4); D5 the `streaks` query marked paged (3); D6 eager thunks (2); D7 limit ignored (5); D8 clamp removed (1); D9 empty-check removed (1); D4 `vUid` dropped from the `user_preferences` tuple (Deno 2 red, Dart wiring test 1 red).
Client (`restore_readiness_prefetch_test.dart`): M1 a failed prefetch handed to the restore as an empty list (3 red); M2 switch inverted (7); M3 the onError wrap removed (4); M4 the own read handed `preFetched: null` (1).

## Residual, stated
- The cap is a guess sized to the small compute tier; the timing line decides whether to raise it (env only).
- A prefetch that is started and then dropped (legacy fallback, cancel) still costs one network read.
- The subscription refresh (0.3 to 8.6 s) stays serial by design (see the plan, item 8).
