---
reviewed_at: 2026-06-28T00:00:00+05:30
staged_against: 36495ba..HEAD (H1b — Part A edcb4f5 + Part B1 e46a1bc + review-fixes)
blast_radius: platform
reviewer: claude-sonnet-via-agent (context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 6
verdict: accepted
---

# Code Review (B-pass) — H1b sync-cost (Part A + Part B1)

Context-blind Sonnet pass over the H1b diff (`git diff 36495ba..HEAD`): the
scheduled_workouts dirty-filter (Part A) + the pushSnapshot debounce + cross-account
swap guard (Part B1). 1 P1, 0 P0, 5 false-alarms.

## Finding 1 — P1 — writer_reader_drift (test coverage) — RESOLVED
- **claim:** `sync_scheduled_payload_hash_index_writer_to_reader_test.dart` tested only the
  pure statics (`schedPayloadFingerprint` / `schedShouldSkipUpsert` / `schedPrunedHashIndex`);
  no Hive `put`→`get` round-trip of the actual key `sync_sched_payload_hash_index`
  exercised the runtime read-path (rule 21 / `feedback_source_grep_false_confidence`).
- **verification:** `grep -n 'sync_sched_payload_hash_index' test/contracts/sync_scheduled_payload_hash_index_writer_to_reader_test.dart` → 0 hits before fix.
- **resolution:** ACCEPTED — added a real in-memory Hive `Hive.init`/`openBox` round-trip
  test that writes `{date: fingerprint}` under the key, reads it back, reconstructs the
  dynamic-typed Map (mirroring the loop-head load), and asserts `schedShouldSkipUpsert`
  fires. Green.

## Findings 2-6 — FALSE_ALARM (all 5 lenses verified clean)
- **writer_reader_drift (index key collision):** `sync_sched_payload_hash_index` does NOT
  start with `schedule_` → auto-skipped by the row sweep's `!key.startsWith('schedule_')`
  guard. CLEAN.
- **function_exception_swallow:** `SyncCoalescer.trigger`'s `catch (_)` is a backstop; each
  task (`syncWorkoutDataNow` / `pushSnapshotNow`) self-reports via `ErrorTelemetry.recordNonFatal`
  + `_reportSyncFailure` before any error can reach the coalescer. CLEAN.
- **blast_radius_mismatch:** all 3 kill-switches (`disable_sched_hash_skip` /
  `disable_snapshot_debounce` / `disable_sync_debounce`) revert to verbatim pre-H1b behavior
  when set; defensive getters default to fix-active on a missing configBox. CLEAN.
- **secrets_in_tree:** no credential-shaped literals in the diff. CLEAN.
- **unawaited_no_error_sink:** every `unawaited(` routes through a self-reporting task or the
  coalescer backstop. CLEAN.
- **batch-specific (continue / store-on-200 / swap-mid-flight):** the `continue` skips no
  loop-end write-back; the fingerprint stores only at the 3 confirmed-200 points; the
  coalescer reset is present. (The B-pass rated swap-mid-flight a FALSE_ALARM by the
  compileDailySnapshot angle; the concurrency Hermes lens traced the RESPONSE-mirror leak
  deeper — see the Hermes report P1.)

## Triage
- P1 (test coverage): **accepted** → Hive round-trip test added. Green.
- 5 false-alarms: annotated, no action.

verdict: accepted
