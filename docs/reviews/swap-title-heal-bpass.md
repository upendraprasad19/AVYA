---
reviewed_at: 2026-10-05
branch: swap-title-and-launch-refresh
staged_against: swap-title-and-launch-refresh at cc1f0686 (OI-284 CompletedTitleHealer; 21 files)
blast_radius: platform
reviewer: two independent context-blind B-passes (Sonnet), dispatched per CLAUDE.md 4.3; pass 2 reviewed the staged diff after pass 1's fixes
lens_set: [writer_reader_drift, race_atomicity, cross_account, test_vacuity, gate_registry_consistency]
findings_count: 8
verdict: accepted
---

# B-pass - OI-284 completed-row title heal

Scope: `CompletedTitleHealer` (`lib/core/services/completed_title_healer.dart`), its hooks in
`sync_service.dart` (public wrapper + verbatim-moved `_restoreFromCloudForUserCore` + the
`restoreFromCloud` tail), `SyncFlags.completedTitleHealEnabled`, the shared placeholder-name constants,
`test/contracts/completed_title_follows_log_test.dart`, registry / gate-baseline / doc edits.

Why this record exists: the plan-review record was written at `account` (measured before main's PR #70
promoted `sync_service.dart` and `sync_flags.dart` to platform). The merge-to-main gate then required
`bpass: accepted` with a committed review file. Both reviews below really ran before commit `cc1f0686`;
this file records them, it does not create a new one.

## Pass 1 - verdict CHANGES REQUIRED (all items fixed before commit)

- P2 placeholder-name scan was vacuous (it scanned a window and could not go blind-red): rewritten to scan the
  enclosing function of every production `markCompleted` caller, with a caller census and a "has a recognised
  source" assertion.
- P2 placement-parity test only grepped for a substring: strengthened (see pass 2 for the residual).
- P2 healer missing from `check_writeservice_only` allowlist: added, then shown by pass 2 to be a no-op and
  REVERTED (the gate matches only a literal `workoutBox.put(`; the healer writes through a local alias).
- P3 `template_id` global `_alwaysOk` in the drift gate: replaced by a per-file baseline line.
- P3 registry range for `_restoreFromCloudForUserCore`, diagnose / plan cites, Home CLAUDE.md row: fixed.

## Pass 2 - verdict ACCEPTED (no P0/P1; one P2, three P3; all fixed before commit)

Verified by reading code, not asserted: the verbatim move of the restore body is byte-identical (additions only
in the staged diff); every success return of the core reaches the wrapper's heal and every non-success does not;
the unhooked entry points (`restoreLightweightAlways`, the flag-gated `*ForSyncDomain` paths) restore no logs;
the heal reads and writes only the current user's boxes with a fresh `workoutBox` per row and swallows an
account-switch error; `restoreCompletedTick` (which also gates streak decay) is never bumped; Hive 2.2.3 updates
its keystore synchronously before the first await so the get-then-put cannot interleave; the registry line
ranges match the code.

Findings and dispositions:
- P2 the wrapper's success-only condition survived negation (substring checks only) - FIXED: the test now
  matches the exact non-negated `if (shouldHealAfterRestore(result)) { await heal...(); }`; mutation M19 reddens it.
- P3 guard-removal mutations were masked by the pass-level `catch` - FIXED: three tests (earlier no-wlog row,
  non-Map schedule value, non-Map wlog) prove one bad row never starves a later one; M20/M21 redden them.
- P3 the entry census asserted callers of the public restore must be `restoring_screen` (wrong: they are hooked
  by construction) - FIXED: the census now pins the call sites of `_restoreWorkoutLogs` /
  `_restoreScheduledWorkouts` (6 + 3); M22 reddens it.
- P3 the allowlist entry was a no-op - FIXED by reverting it (above).

Evidence beyond the reviews: 26 tests, 22 mutations each reddened at least one test, full suite 7,730 passed /
9 skipped / 0 failed at the pre-push of the merged tree. Not independently re-reviewed after the pass-2 fixes:
the fix delta (a stronger regex, three tests, a census rewrite, a reverted allowlist line) was verified by the
mutations above and the full suite, not by a third reviewer.
