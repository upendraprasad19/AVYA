---
reviewed_at: 2026-11-02T17:30:00+05:30
staged_against: 9aa6ae627462
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
verdict_note: reviewed on staged diff 9972c855ee34; all 4 P2 fixed in this batch, the P3 needs no action; the fixes are in the diff this file is named for
---

# Code Review — 9aa6ae627462

The fresh Sonnet reviewer found no P0 or P1. Triage by the author (the review ran on the pre-fix diff `9972c855ee34`).

## Finding 1 — P2 — writer_reader_drift (inserted-lines sub-check)
- **file:line:** docs/sot_registry.yaml (home_provider.dart and sync_restore_completeness.dart ranges)
- **claim:** the batch re-shifted only some registry ranges; StreakNotifier.build, StreakFreezeNotifier.build, the nonexistent `_refillIfNewWeek`, `_restoreFreezes` and ~14 other home_provider ranges (stale at HEAD already) did not match their symbols.
- **status:** accepted — fixed: 25 ranges re-anchored from symbol lines in this diff; the `_refillIfNewWeek` entry now cites `restoreCompletedTickProvider`; `check_sot_registry_parity.dart` PASS.

## Finding 2 — P2 — guard_without_its_mirror (kill-switch path not identical)
- **file:line:** lib/core/services/sync/sync_restore_completeness.dart (loop head, drop message)
- **claim:** the pre-fetch owner guard and the numeric drop text ran on the kill-switch path too, contradicting "restores the single retry".
- **status:** accepted — fixed: the owner guard now applies from round 2 only (round 1 is the pre-fix path) and the drop text is `one retry` when maxRounds == 1; the kill-switch test pins the text.

## Finding 3 — P2 — missing_input (unguarded SyncService.instance in a provider build)
- **file:line:** lib/features/home/providers/home_provider.dart (restoreCompletedTickProvider)
- **claim:** every reader of the chip providers instantiated the SyncService singleton with no guard, unlike hive_tab_scaffold.dart:158.
- **status:** accepted — fixed: the access is in try/catch and returns 0 (no listener) when unavailable; the 26 test files that touch these providers/functions pass (364 tests).

## Finding 4 — P2 — asserted_fixture_value (tests that pass without the fix)
- **file:line:** test/contracts/freeze_push_retry_attempts_behavioral_test.dart
- **claim:** four of six tests also pass on the single-retry code; nothing proves a later round re-reads Hive; ownership is a presence pin only.
- **status:** accepted — fixed in part: added a test where a consume lands between rounds 2 and 3 and the final RPC must carry it (mutant: merge from the captured local value, 2 tests red). The owner-flip-in-round-2 behavioral test was NOT added: flipping HiveUserSession.currentOwnerFullId needs an async openForUser/closeAll that races the stub's HTTP reply, and closing the box makes the fresh read throw, so a mutant would not differ. The presence pin stays and the test title and diagnose-doc say so.

## Finding 5 — P3 — note
- **file:line:** lib/core/services/sync_flags.dart:245-264
- **claim:** worst case N x 7 calls with N concurrent uncoalesced pushes; bounded, documented.
- **status:** false_alarm (note only, no action required)

## Founder triage notes
Author triage only; the founder authorized commit, push and merge for this batch.

## Tuning entry
- **2026-11-02** - blast-radius platform - 5 findings; 1 false_alarm; tuning: none (the inserted-lines sub-check found the stale-range class again, 25 ranges; the lens is working).
