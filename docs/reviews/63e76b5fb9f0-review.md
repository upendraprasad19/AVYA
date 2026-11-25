---
reviewed_at: 2026-11-26T00:17:00+05:30
staged_against: 63e76b5fb9f0843305b1fad78af2e7cafabbc52d
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
verdict_note: one fresh context-blind seat on the CI-green head (three-dot diff origin/main...63e76b5f); 0 P0/P1, 1 P2, 4 P3; all five fixed or answered in the same branch; 1 partly false (finding 5's "no test for a null body")
---

# Code Review — 63e76b5f (target-history-cloud, Nutrition History Landing B)

The SQL reviewed here is the DRAFT `test/sql/target_history_merge_draft.sql`. It is not applied
anywhere; it becomes `supabase/migrations/190_*.sql` byte for byte after the founder's go.

## Finding 1 — P2 — missing_input
- **file:line:** test/sql/target_history_merge_draft.sql (`pg_input_is_valid(e->>'from', 'date')`)
- **claim:** the function exists only on PostgreSQL 16+; the rehearsal image is 17.6 but nothing proved production is. On 15 the migration would apply and every call would fail at run time.
- **verification:** `select version(), pg_input_is_valid('2026-02-31','date'), pg_input_is_valid('2026-02-28','date')` on project dedsavbjuwgarrhphgnl (read-only, 2026-11-25)
- **status:** verified clean. Production answers `PostgreSQL 17.6`, `false`, `true`: the same major version as the rehearsal image. The same query confirmed the column and the function do not exist yet.

## Finding 2 — P3 — function_exception_swallow
- **file:line:** lib/core/services/sync/sync_profile.dart `pushTargetHistory` (the `.rpc(` call)
- **claim:** no timeout on a request the profile sync, the queue drain and the sweep await; a hung socket would hold them. Also: a missing function is reported on every profile sync until the migration is applied.
- **verification:** `TZ=Asia/Kolkata flutter test test/sync/target_history_cloud_sync_test.dart --plain-name "abandoned after pushTimeout"`
- **status:** accepted. The request is bounded by `TargetHistoryService.pushTimeout` (15 s); a timeout is reported like any failure and a late reply writes no memory. New test; mutant P16 (timeout removed) reddened 1. The missing-function window is closed by the order (apply before merge), a recorded decision.

## Finding 3 — P3 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml, two `_restoreUserProfile` cites (`754-908`)
- **claim:** the range was already off on main and was shifted, not re-derived; it did not reach the new strip call.
- **verification:** `grep -n "line_range: 834-1005" docs/sot_registry.yaml` against `grep -n "_restoreUserProfile(String userId" lib/core/services/sync/sync_profile.dart`
- **status:** accepted. Both cites re-derived from the method's doc comment to its closing brace.

## Finding 4 — P3 — writer_reader_drift
- **file:line:** the draft SQL's `strategy COLLATE "C"` and `left(.., 32)` against Dart `compareRank`
- **claim:** byte order and a 32-character cut differ from Dart's code-unit order only for non-ASCII or over-long strategy strings; unreachable with the real storage keys, and it cannot loop.
- **verification:** `grep -n "ASCII storage key" test/sql/target_history_merge_draft.sql`
- **status:** accepted as a comment in the SQL header (the draft is still editable). No behaviour change.

## Finding 5 — P3 — asserted_fixture_value
- **file:line:** test/sync/target_history_cloud_sync_test.dart
- **claim:** no test for a non-bool / null reply; no test for a missing function; the stale references the draft's file name will leave when it becomes migration 190.
- **verification:** `grep -n "rpcReturns(null)" test/sync/target_history_cloud_sync_test.dart`
- **status:** partly false, rest accepted. A null reply IS tested ("false from the function ... keeps no memory", second half: retried, no memory). A missing function is a 404 PostgrestException and takes the same catch as the tested 503 apart from not arming the sweep; not given its own test. The draft's references (plan, record, ledger, the rehearsal script's default) are repointed in the apply commit, as plan section 9 R1 already says.

## Founder triage notes
Run autonomously on the founder's "go. run autonomously" (2026-11-25); no finding needed a founder decision. The production apply of migration 190 still needs the founder's explicit go.

## Tuning entry
- **2026-11-26** - blast-radius platform - 5 findings; 1 false_alarm; tuning: none. Note for lens 7 (missing_input): when a draft SQL uses a built-in that is version-bound, the brief should hand the reviewer the production server version, because the seat cannot run a live query; here the author ran it after the finding.
