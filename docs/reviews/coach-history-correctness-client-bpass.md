---
reviewed_at: 2026-10-09T20:00:00+05:30
staged_against: coach-history-correctness-client at commit 5c19161a (U2 restore, U3 push, U4 deletes) vs main 15aa7a7f
blast_radius: platform
reviewer: 2 fresh context-blind Sonnet reviewers on one commit (A: units U2 and U3; B: unit U4 and the test-stub change), read-only, exhaustive command allow-list (Read, git show, git diff, git log; no scripts, no tests, no database); the Grep and Glob tools were unavailable to both, so neither could search test/ repo-wide
lens_set: [writer_reader_drift, guard_without_its_mirror, missing_input, asserted_fixture_value, blast_radius_mismatch]
findings_count: 15
verdict: accepted
---

# Code Review (B-pass) — L1a-2 exercise-log restore, push day and deletes (`coach-history-correctness-client`)

Plan `docs/plans/coach-history-correctness-client.md` (v9); diagnose-docs `a4e7b1`, `b5f8c2`, `c6a9d3`, `d7bae4`. Production was not touched by any reviewer or by the fixes.

**Outcome:** no P0. Two findings were design-level and came from reviewer B tracing a scenario the diff's own tests could not see (the tests re-logged with the SAME set count). Every finding was fixed or recorded as a plan-accepted residual; 0 false alarms. Fixes were mutation-checked (8 of 8 new protections RED; the move-queue ordering is a source-position pin, presence-only).

## Reviewer A (U2 restore, U3 push)

| Id | Sev | Claim | Disposition |
|---|---|---|---|
| A-F1 | P2 | A row restored under the OLD rules sits under the write-day key; the next restore finds the workout-day key empty and writes a SECOND local row; the old row keeps pushing under the wrong `workout_log_id`. | Fixed: restore re-keys the old row (`WorkoutWriteService.rekeyRestoredExerciseLog`) when its `workout_log_id` equals the cloud id. Tests: heal + a locally logged row on the write day is left alone. |
| A-F2 | P2 | The push skips a row with no `date` and no key date although the readers date it from `created_at`. | Fixed: falls back to the IST day of `created_at`, then skips. |
| A-F3 | P3 | Comment says the kill-switch path iterates "oldest first". | Fixed (read order is newest-first; the first row seen wins). |
| A-F4 | P3 | A `workout_log_id` outside 2020-01-01..today+400 or the missing-date bucket restores onto the write day. | Recorded residual (plan-accepted horizon; 0 live rows in the bucket, read-only 2026-10-09). |
| A-F5 | P3 | `_beats` compares timestamps as text; `uniquePerSetNumbers` renumbers positionally. | `_beats` fixed (parsed instants, test with `+05:30` vs `Z`); renumbering is by design for the collision-merge shape (existing sets first), recorded. |
| A-F6 | P3 | `latestWriteIso` does not clamp a future `updated_at_ms`. | Recorded residual: clamping would break the same-device guarantee that a re-log is later than that device's own delete under the same skewed clock (plan §10 clock-skew residual). |
| A-F7 | P3 | PR list ties on the date-only sort key. | Fixed: stable tie-break by exercise name (test + mutation). |

## Reviewer B (U4 deletes, stub)

| Id | Sev | Claim | Disposition |
|---|---|---|---|
| B-F1 | P1 | `cancelFor` ran between the Hive put and the index append in `logExercise` and could throw (closed or foreign user box), leaving an indexless row (the e4a8b1 class). | Fixed: `cancelFor` never throws, runs after the index append; the move wraps its queue calls so a queue failure cannot stop the move of the remaining rows. |
| B-F2 | P1/P2 | A re-log cancelled the whole queued entry, so the OLDER cloud version at a different set count was never tombstoned and the highest-count restore brought the deleted version back over the re-log. | Fixed, REVERSING the plan's "cancel on re-create" for timed entries: the drain's `completed_at <= deleted_at_ms` filter already spares the newer version, so a timed entry stays; only a time-less entry (older build) is cancelled. Tests vary the count (3-set stale vs 2-set re-log) against a cloud model; mutation: cancelling timed entries again RED x4. |
| B-F3 | P2 | An UPDATE cannot create a tombstone the way the old upsert could, so a creating push already on the wire can land after an empty UPDATE and stay live (the plan's "same race exists today" was wrong for that case). | Fixed: an UPDATE that touched no row keeps the entry for ONE more pass (`empty_pass`); test with a push that lands between passes. Residual: a push still in flight two passes later. |
| B-F4 | P2 | A clock far in the future makes `deleted_at_ms` tombstone other devices' later re-logs; a skewed `completed_at` makes the own delete a no-op; local-ISO `created_at` suspected. | Future cutoff clamped to now (test + mutation). The skew cases are plan §10 residual (i). The local-ISO suspicion was checked: no exlog writer stamps `created_at` (the two `created_at` writers in `workout_repository.dart` are custom exercises and templates). |
| B-F5 | P2 | `deleted_at_ms` was cast `as int?` outside the try; one malformed value stopped every exercise-log push. | Fixed: `read()` drops a non-int time (reads as "no time"); test with a malformed entry beside a good one. |
| B-F6 | P2 | The move queued the source delete BEFORE its Hive work. | Fixed: queued after `box.delete(oldKey)`; source-position pin (presence-only). |
| B-F7 | P2 | Case-sensitive exercise-name match in `cancelFor` / `isQueued` / `remove`. | Recorded: the time filter protects the newer row, so a missed match costs a wasted queue entry, not data. |
| B-F8 | P3 | Stale class header and misplaced drain doc. | Fixed. |

Stub change: reviewer B could not search `test/` for tests that depended on the old 204/201 default (no Grep tool). Coordinator check: 16 test files use `SyncStubServer`; the full suite (8,449 tests) passed with the new default, and mutating the default back reddened 2 tests, so the new behaviour is exercised.

## Method note

The diff's own tests used one set count for the delete and the re-log; B-F2 only appears with two. Fixture width again (see the `asserted_fixture_value` lens).
