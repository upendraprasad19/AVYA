---
reviewed_at: 2026-10-25T14:10:00+05:30
branch: sync-storm-first-sweep
review_type: b-pass
blast_radius: platform
reviewer: claude-sonnet-via-agent (four fresh context-blind seats)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value, unawaited_no_error_sink, L1, L8, L10, L11, L15, L17, L20]
findings_count: 36
verdict: accepted
---

# B-pass review - sync-storm-first-sweep (W1 migrator, W2 incremental flush, W3 first-sweep postponement)

Plan: `docs/plans/2026-10-25-sync-storm-first-sweep.md` (v4.1, converged after four plan-review rounds; as-built deltas in its section 12). Diagnose-doc: `docs/diagnoses/2026-10-25-restored-device-resends-history-b9e4d7.md`.

Four fresh Sonnet seats, each handed the staged diff of the whole batch and an exhaustive read-only command list (git/grep/sed on staged content, one named `flutter test`, no scripts, no network, no database, no writes): W1 (migrator), W2 (skip index), W3 (first-sweep decision), docs and governance. Result: **0 P0, 1 P1 (a wrong disclosure in three docs), 17 P2, 18 P3 = 36 findings; no data-loss path and no false-skip path in the code.** Every finding was checked against the code by the author before acting; none was a false alarm. (One seat wrote a scratch copy of a staged file into the scratchpad outside its command list; nothing inside the worktree was touched.)

After the fixes, the 84-mutant run in the diagnose-doc was executed on the final tree (all applied, all red except five declared equivalents measured at 0 red), the 78 tests pass, `flutter analyze --no-fatal-infos` over the whole project has 0 warnings and 0 errors, and the full suite (`TZ=Asia/Kolkata flutter test --exclude-tags golden`: 11,312 passed, 11 skipped, 0 failed) ran on the final tree. The only edit after it is the header comment of the Gate 9 contract test (Finding D10), which re-ran 3/3; the pre-commit loop runs on the staged state before the commit.

## Docs and governance seat (15 findings)

### Finding D1 - P1 - truthfulness of the W3 consequence
- **file:line:** diagnose-doc impact_analysis, `docs/architecture/sync.md` First-launch section, `docs/sot_registry.yaml` `first_launch_sweep_decision.class_constraints`.
- **claim:** the docs said sweep-only pushes wait "up to 24 h on a fresh device's first day"; the stamp is the marker time and `_fullSyncInterval` is one day, so they wait until the first launch at least 24 h after the first one (unbounded for an inactive user).
- **status:** accepted - fixed in all three docs (and the naming/CLAUDE.md rows carry no "24 h" bound); the plan already said it.

### Finding D2 - P2 - the three timed-out ops
- **claim:** `restore_sync_exercise_logs` is the `syncWorkoutDataNow` fan-out step, not a `weeklyFullSync` step, so BOTH pushers timed out.
- **status:** accepted - fixed in the diagnose-doc Measured section and plan section 2.1.

### Finding D3 - P2 - bug-class 2.123 overclaims causation
- **status:** accepted - fixed: the stub chain proved the mechanism (0 versus 2 upserts); 633 for 207 is the incident volume the migrator, the sweep and the retry explain together; "right after a clean restore" dropped.

### Finding D4 - P2 - plan and test headers stale against the as-built batch
- **status:** accepted - fixed: plan section 12 "As built" (base b0735bb1, 78 tests in four files, 84 mutants, five wiring pins, a table row not a pitfall row); migrator test header names the real RED set (1, 2, 3, 4b, 8, 9); W3 test header says five pins.

### Finding D5 - P2 - registry range of `_reportSyncFailure` left stale
- **status:** accepted - fixed (`2975-3048`, the declaration inside), verified by `check_sot_registry_parity`.

### Finding D6 - P2 - registry mutant count wrong
- **status:** accepted - fixed: "12 of 12 non-equivalent mutants red (M1 and W1f equivalent, measured 0 red; M4 needed test 5c)"; the contract-file comment says 7 of 7.

### Finding D7 - P2 - the `last_full_sync` reader list for CLAUDE.md 4.1.5 point 3 is incomplete
- **status:** accepted - fixed: `_markFreshDeviceIfEmpty` (relies on null meaning never swept) and the new tests added to the diagnose-doc; the new meaning "stamped by a postponement" is stated.

### Finding D8 - P2 - the mutation-proof statement was more precise than the log supports
- **status:** accepted - fixed: the section was regenerated from the machine log of the final run (84 mutants on the final tree, sha256 fingerprint at start and end), deletion mutants are said to be confirmed by anchor assertion, equivalents are "measured 0 red, equivalence argued".

### Finding D9 - P3 - mutation baseline older than a bulk rewrite of the tree
- **status:** accepted - fixed: the final run was executed on the integrated tree and the diagnose-doc records the fingerprint.

### Finding D10 - P3 - "only reader of the marker" / "deleted on every decision"
- **status:** accepted - fixed: "sole reader and deleter", "deleted on every decision it reaches (not at all with the kill switch engaged)" in the registry, naming row, services CLAUDE.md row; the contract-test header comment says consumer.

### Finding D11 - P3 - `sync.md` "keeps what was confirmed"
- **status:** accepted - fixed: "keeps every flushed batch of 25 (at most 24 unflushed events are lost)".

### Finding D12 - P3 - arithmetic
- **status:** accepted - fixed: exactly 1,375 entry copies at 262 rows, about 0.5M at 5,000.

### Finding D13 - P3 - naming conventions miss three terms
- **status:** accepted - fixed: one glossary row for `sync_skip_flush_<domain>`, `sync_exlog_migrator_compare` and `flushEnabledResolver`; `kSkipIndexFlushEvery` row says "durable events".

### Finding D14 - P3 - stale prose cites in the `sync_skip_index` concept
- **status:** accepted - fixed: cites refreshed to `pushIfChanged :227`, `_countFlushEvent :316`, `_flush :329`, `commit :355`, `readIndex :388`, `recordConfirmed :408`, `recordConfirmedAll :420`, `clearAll :453`.

### Finding D15 - P3 - nits (2.123 cross-reference to 2.100, tier-2 file count)
- **status:** accepted - fixed: 2.123 relates to 2.100 only through the summary-only `set_number = 1` push; tier 2 says all four test files.

## Skip-index (W2) seat (10 findings)

### Finding S1 - P2 - mutant S1 survives (constructor default `flushEvery`)
- **status:** accepted - fixed: a test builds the index without `flushEvery` (0 puts at 24 events, 1 at the 25th); mutants S1 and S1b red.

### Finding S2 - P2 - mutants S2 and S3 survive (a flush whose only effect is a new fingerprint on a key already in the box)
- **status:** accepted - fixed: tests seed old fingerprints and confirm new ones; S2 and S3 red.

### Finding S3 - P2 - mutant S11 survives (flush switch decided at construction)
- **status:** accepted - fixed: both directions pinned (true then false after construction, and the mirror); S11 red.

### Finding S4 - P2 - drops of stored fingerprints were not durable mid-pass, but the registry said they were
- **file:line:** `sync_skip_index.dart` `_forget`, `commit`; registry `sync_skip_index.class_constraints`.
- **status:** accepted - fixed by a design change, not a wording change: `_forget` now reports whether a fingerprint WAS stored and `_countFlushEvent` counts confirmations and drops of stored fingerprints, so a pass killed after a failed push of an edited row has already removed the old fingerprint (closing the edit-then-revert path within at most 24 unflushed events). Never-stored failures do not count. Tests: dropping stored fingerprints, unconfirmed, never-stored, shared window, edit-then-revert after a killed pass; mutants N1, N1b, N2, N3 red. Not a regression (main loses drops on a killed pass too).

### Finding S5 - P2 - mutant M16 application not proven
- **status:** accepted - fixed: the final run records the failing test names per mutant (M16 fails six named tests in the removals group); the diagnose-doc says pure deletions are confirmed by anchor assertion.

### Finding S6 - P3 - the `_flush` owner guard is redundant in production (M17)
- **status:** accepted - documented, guard kept: the second check is defence in depth (no await separates it from the post-push check; `ownerChangedSince` is stateless). The call-count pin in test 17 is kept on purpose because it is the only protection against the guard being removed; the diagnose-doc says M17 is production-equivalent.

### Finding S7 - P3 - registry cites stale, `_flush` not listed
- **status:** accepted - fixed with D14 (cites refreshed, `_flush` and `_countFlushEvent` named).

### Finding S8 - P3 - disk claim is native-only; custom-box listeners
- **status:** accepted - fixed in the diagnose-doc: arithmetic exact, the disk figure marked native-only and from memory of hive 2.2.3 (not verified here), the `customItem` listener cost noted.

### Finding S9 - P3 - a flush never prunes; a swallowed `readIndex` error could shrink the index
- **status:** accepted - documented, no code change: the shrink exposure is the same as `commit`'s (the file's own rule: failure costs an extra push, never a false skip), is unreachable for a closed box (the put throws too), and the missing prune is stated in the diagnose-doc.

### Finding S10 - P3 - plan lists a `readIndex` telemetry assertion the tests do not have
- **status:** accepted - fixed in the plan: section 12 records that the assertion was not added and why.

## W3 seat (7 findings)

### Finding W3-1 - P2 - wiring pins accepted conditional wrappers (mutants MA, MB, MC)
- **status:** accepted - fixed: five indent-anchored, comment-stripped, no-else pins; MA, MB, MC red. Disclosed residue: they are presence-only, other indirection is not covered, and the device check owes the runtime proof (`checkAndSync` cannot run under `SyncHarness`).

### Finding W3-2 - P2 - no exlog-only history case (mutant MD)
- **status:** accepted - fixed: a case seeds only an `exlog_` row; MD red.

### Finding W3-3 - P2 - the postpone event was not asserted absent on the other paths (mutant ME)
- **status:** accepted - fixed: event absence asserted on the stale, future, owed, no-marker, owner-changed and kill-switch paths; ME red (8 tests).

### Finding W3-4 - P3 - malformed marker untested (mutant MF)
- **status:** accepted - fixed: a non-ISO marker is consumed without a report and the sweep runs; MF red.

### Finding W3-5 - P3 - the "UTC" claim was true by reading only (mutant MG)
- **status:** accepted - fixed: the written marker text ends with `Z`; MG and MG2 red.

### Finding W3-6 - P3 - a test title overclaimed ("Layer A empty stub")
- **status:** accepted - fixed: renamed to say what it sets (the session resolver disagrees with the open session); the guard it proves still reddens when removed.

### Finding W3-7 - P3 - doc claims ("deleted on every decision", "up to 24 h", registry cites that drift)
- **status:** accepted - fixed with D1 and D10; the registry cites are labelled "confirmed" and are a known drift class covered by the range-recompute rule.

## Migrator (W1) seat (4 findings)

### Finding M1 - P2 - test 4 holds for a different reason than stated
- **status:** accepted - fixed: test 4's fixture is `weight_reps` against a cloud duration of 600; its reason now says so; tests 4b (a real timed row is left alone, 0 upserts, red on main) and 4c (a timed row with NULL cloud metrics is recorded then pushed once, residual shape 1) pin the real shapes; the plan and diagnose wording was corrected (the MEASURED label is gone).

### Finding M2 - P2 - test 8 leaves mutants alive (report once, order dependence, `skipServerPost`, counters)
- **status:** accepted - fixed: two Infinity rows, a key-order precondition, `unchanged=2 rewritten=2` asserted from the log line, the once-only report asserted, test 8b pins the default server post; mutants W1a-W1e red.

### Finding M3 - P3 - header, registry and diagnose-doc disagree on the RED set and mutant counts
- **status:** accepted - fixed with D4 and D6.

### Finding M4 - P3 - the kill switch only matters before a device's first migrator run
- **status:** accepted - fixed: one sentence in the getter doc comment, `docs/architecture/sync.md` and the diagnose-doc.

## Checked and clean (from the seats' reports)
- **writer_reader_drift:** every reader of `updated_at_ms` on exercise-log rows was read (push `latestWriteIso`, `_resolveCompletedAtOrNull`, the migrator's own sort, the receipt session label); only the push sees the difference, which is the intended fix. The delete drain compares the cloud `completed_at` with the queue's `deleted_at_ms` and never reads the Hive stamp.
- **false skip (migrator):** the candidate differs from the stored row only by the stamp when the canonical JSON is equal; int-versus-double, key order, -0.0, NaN and Infinity all fall on the safe side (rewrite or fall back). `group.length == 1` is equivalent to drop (verified by argument).
- **wrong account (W3):** the marker writer returns unless the Hive owner is the user and `!ownerChangedSince`, with no await between the guard and the put; the decision re-checks `ownerChangedSince` before the stamp.
- **clock and zone (W3):** `last_full_sync` is read only through `_getTimestamp`; `DateTime.tryParse` takes both text forms and the arithmetic is on instants. A future marker is stale (the sweep runs).
- **order (W3):** the mark precedes health sync, `_restoreIfNeeded` and the decision in `checkAndSync`, and precedes the first restore op in the restore core; `restoreFromCloud(` is called only from `_restoreIfNeeded`.
- **consequences (W3):** an owed sweep always runs; an offline first launch arms the owed flag on any write; a lingering marker is stale after 1 h; sign-out clears `syncBox` and with it the marker.
- **exceptions and telemetry:** both new catches report through `recordNonFatal` with the default server post; the H-42 pair count is unchanged.

## Founder triage notes
Self-triaged by the author under the project rules (CLAUDE.md 4.3, B-pass before the merge): all 36 findings accepted and handled above; none is parked or deferred. Residual self-attested items are named in the diagnose-doc (five equivalent mutants argued, presence-only wiring pins, the device check). The commit go is the founder's.

## Tuning entry
- **2026-10-25** - blast-radius platform - 36 findings; 0 false_alarm; tuning: briefs that hand the reviewer the mutation log and the staged tests produce concrete surviving-mutant lists (S1-S4, S11, MA-MG) that were cheap to confirm and close; the docs seat's P1 was the same wording the plan had already fixed in one place only, so a disclosure change must be grepped across the diagnose-doc, the architecture doc, the registry and the nested CLAUDE.md in the same edit.
