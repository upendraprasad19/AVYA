---
reviewed_at: 2026-10-07T00:40:00+05:30
staged_against: working tree of claude/avya-streak-data-check-b506de on top of HEAD 449aca21 (Slice B2: sync_service.dart, sync_flags.dart, sync/sync_workout.dart, sync_health.dart, sync_nutrition.dart, sync_community.dart, the shared test helper sync_stub_server.dart, the new test restore_legacy_paging_behavioral_test.dart, and the docs that cite them)
blast_radius: platform
reviewer: fresh-context-blind-agents (Sonnet; round 1 two seats: A correctness / fidelity / kill-switch revert / source-grep ripples, B test adequacy; round 2 one seat: C re-review of what round 1 changed; read-only, no command beyond git diff/show/grep, Read, Grep, Glob)
lens_set: [L1, L8, L11, L17, writer_reader_drift, guard_without_its_mirror, asserted_fixture_value, function_exception_swallow, blast_radius_mismatch, missing_input]
findings_count: 20
verdict: accepted
---

# Code Review (B-pass) — the client's legacy restore reads page and order deterministically (diagnose c7e2a9)

Scope: `SyncService._fetchAllRows` and its eleven callers, the three formerly bare reads
(`workout_schedule_completions`, `user_custom_exercises`, `user_custom_foods`), the nutrition loop, the community
catalogue pull, `SyncFlags.restorePagingFixEnabled`, the new paged-table responder in the shared stub
`test/helpers/sync_stub_server.dart` and `test/sync/restore_legacy_paging_behavioral_test.dart`. Self-attested (rule 21):
the mutation drivers are scratch scripts, not in the repo. Reviewers were told to find defects and to say what they
checked; the coordinator re-read every cited file:line (and re-ran the arithmetic, and the live reads) before accepting a
finding, and treated a reviewer's suggested fix as a separate claim. No reviewer statement was wrong; one suggested fix was
weighed and not taken (stop on an EMPTY page, B2 below).

No reviewer found a P0 or P1 in any round. Round 1 confirmed all eleven `_fetchAllRows` callers carry a tie-break that is a
real, unique, last column; the kill-switch revert is byte-identical for every read; the paging loop builds a fresh query per
page; the source-grep tests that read the edited regions still mean what they meant (the 4000-character window of
`orphan_completion_synthesizes_wlog_test.dart` only shrank); and `readiness_daily` (no `id` column, primary key
`(user_id, date)`) is tied on `date`. Round 2 re-reviewed the changes made for round 1.

## Findings (20: 0 P0, 0 P1, 5 P2, 15 P3) and what happened to each

### Round 1, seat A (correctness: 1 P2, 5 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| A1 | P2 | `syncCommunityItems` offset-pages 500 rows at a time ordered by `created_at` alone and then stamps `last_community_sync`, so a tied row skipped at a page seam is never refetched (same defect class as the slice's own). | FIXED: an `id` tie term on both queries behind the same kill switch; 1,200-row tied-rows test; N06, N07, N08 red. 0 approved community items live today. |
| A2 | P3 | The nutrition loop's own 50,000-row ceiling breaks with no event, so the docs' "the ceiling now emits one event" was true only of `_fetchAllRows`. | FIXED: the loop emits the same event; 50,000-row test; N04, N05 red. |
| A3 | P3 | The registry and the nested CLAUDE.md row said "every `.order()` term states `ascending:`"; four older single-column terms remain (nutrition primary, the verbatim legacy chain, `scheduled_workouts`, coach). | FIXED: wording scoped to NEW terms; the others rely on the Dart default (descending), which the order-string tests pin. |
| A4 | P3 | The diagnose and registry said a duplicate lower-cased name would restore the NEWER row locally; migration 057 makes a duplicate unreachable (and completions are unique per date). | VERIFIED LIVE (unique indexes read 2026-10-06) and corrected: for those three tables the tie-break is belt and braces and the paging is the protection; ledger `B2-TIE-ORDER-UNREACHABLE-ON-THREE-TABLES`. |
| A5 | P3 | The diagnose carried an unfilled `@@REVIEW@@` placeholder. | FIXED. |
| A6 | P3 | The stub caught only `StateError`; a `FormatException` (numeric row value against a non-numeric operand) would hang the request until the harness timeout. | FIXED: the paged branch catches every failure, answers 400 / 42703 and records it; every test's tearDown asserts none happened. |

### Round 1, seat B (test adequacy: 4 P2, 3 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| B1 | P2 | "Reverts VERBATIM" was pinned only for `order`, `offset`, `limit` and the Hive count: deleting `.eq('user_id', ...)` or `.gte('completed_at', ...)` from the legacy branch left every test green. | FIXED: the kill-switch tests assert the owner scope and the since filter (and a stale row); N01, N02, N03 red. |
| B2 | P2 | The short-page "pin" sets the STUB's cap to 500 and asserts the lossy outcome; a real cap drop makes no test go red, and hardening the loop would make it red (a false alarm). It documents, it does not detect. | REWORDED everywhere ("documents, does not detect"). The loop is NOT changed: an empty-page stop costs a request per read (about eleven) and would loop on any stub that ignores the offset; ledger `B2-SHORT-PAGE-STOP`, `upstream_blocked` with a reopen trigger and the cap-independent alternative (`Prefer: count=exact`) named. |
| B3 | P2 | The ten table-driven cases seed EMPTY tables, so the stub never evaluates the order columns; a typo (or an `id` on an id-less table) written the same way in code and test stays green. | FIXED, twice: first a live-schema check of the expected strings, then (round 2 F6) a check of every filter and order column the code actually SENT, in every test's tearDown; N11 and R05 (a consistent typo in code AND seed) red. |
| B4 | P2 | The nutrition loop had only an order-string case on an empty table: no paging, tie or ceiling test, and no ceiling event. | FIXED: 2,500-log paging test with reshuffled ties, 50,000-row ceiling test, the event; N04, N05, N10, M19, M20 red. |
| B5 | P3 | The seam-geometry comment was wrong (with 2,500 rows only the 2,000 seam straddles a tie group) and the 834-dates assertion cannot fail. | FIXED: 2,499 rows (833 x 3) straddle BOTH seams (derived in the test); the date count is labelled a sanity count; the negative control uses the same dataset. |
| B6 | P3 | Stub gaps: unhandled exception types hang the request; null / ISO-string comparison limits undocumented; no per-call timeout. | FIXED: catch-all with a recorded 400, limits documented in the helper, `_within` 2-minute per-call timeout. |
| B7 | P3 | The getter's box-not-open fallback and the exactly-2,000-row boundary were untested. | FIXED: both tested; N09 red. |

### Round 2, seat C (the changes made for round 1: 7 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| C1 | P3 | The empty-page-stop rationale cited `sync_nutrition_log_payload_hash_index_writer_to_reader_test.dart` as a stub that answers every GET with the same rows; that test is a PUSH test and never reaches a restore loop. | FIXED: the citation removed, the reason restated truthfully (no existing test does that to a `_fetchAllRows` table; an empty-page stop would loop on any future stub that does), and the count-exact alternative named. |
| C2 | P3 | The diagnose said 834 dates; the test asserts 833 (2,499 / 3). | FIXED. |
| C3 | P3 | Line citations drifted (`_fetchAllRows`, the getter, the registry range). | FIXED: re-derived by grep in the final pass. |
| C4 | P3 | The diagnose cited this review file and the ledger entry `B2-SHORT-PAGE-STOP`, neither of which existed. | FIXED: both created in this commit, with the code-review tuning-history entry the gate demands. |
| C5 | P3 | The naming row said the event is emitted only by `_fetchAllRows`; `disable_restore_paging_fix` was missing from the kill-switch list in `docs/architecture/sync.md`. | FIXED. |
| C6 | P3 | The live-schema check covered only the ten `cases` tables. | FIXED (see B3): the sent-column check covers every paged read the tests exercise. |
| C7 | P3 | The community pull stops at 10 x 500 rows and stamps `last_community_sync`; the new ceiling event does not cover it. | FIXED: a pull that fills its cap emits `restore_row_ceiling_hit` (`community_pull:<table>`); R01-R04 red. The cap itself is unchanged (keyset paging is a separate design; 0 approved items live); ledger `B2-COMMUNITY-PULL-PAGING`. |

## Could not verify (carried to the diagnose Limits)

Live `db-max-rows = 1000` is the coordinator's 2026-10-06 measurement, not re-read by any reviewer; the run time of the two
50,000-row stub tests on a loaded CI box (they sit well inside the 2-minute per-call cap locally, about 30 s for the whole
file); and a device restore that falls back to the legacy path, which owes the CLAUDE.md section 5 runtime check.
