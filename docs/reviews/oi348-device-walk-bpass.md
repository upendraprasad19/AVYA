---
reviewed_at: 2026-11-23T01:30:00+05:30
branch: oi348-device-walk
review_type: b-pass
staged_against: 59582d52
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 3
verdict: accepted
verdict_note: all three findings fixed in the B-pass fix commit on the same branch; reviewer suggested accept
---

# B-pass — oi348-device-walk (OI-348 Landing 1a-i, PR 327)

Fresh context-blind Sonnet reviewer, self-initiated before the merge (§4.3), on the committed three-dot diff `origin/main...59582d52`. Allowed commands were exhaustive (reads, read-only git, `dart analyze` on diff files, seven named test files); lib/ mutations by backup/`cp` restore with sha256 checked; `git diff --stat 59582d52 -- lib/` empty at the end.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** `lib/core/services/sync/sync_nutrition.dart` `_cleanupNutritionPullCopies`, the Hive-owner check `HiveUserSession.currentOwnerFullId != userId`
- **claim:** no test reached the case "live account B, Hive boxes still A's", where the Hive-owner check is the only guard (`ownerChangedSince` compares with the live account). Dropping the check or the whole first guard left 15/15 green; the regression would set B's run-once flag after scanning a box that is not B's.
- **verification:** mutation "drop `currentOwnerFullId != userId ||`" → previously 15/15 green.
- **status:** accepted — fixed: test "Hive boxes owned by another account: nothing removed, no flag for the live account" (`test/sync/nutrition_pull_removed_behavioral_test.dart`); the same mutation now reddens 1 test.

## Finding 2 — P2 — writer_reader_drift (SoT line cites)
- **file:line:** `docs/sot_registry.yaml` cites of `sync_service.dart` `_fetchAllRows` (3118-3189), `_reportSyncFailure` (2947-3020, and a reader entry at 2600-2665 that already pointed at pull code on main) and `nutrition_write_service.dart` `kNlogKeyShape`…`firstFreeLogKey` (1066-1089), stale after the diff's +24 / +6 line shifts (the parity gate checks bounds only).
- **verification:** `grep -n "Future<void> _reportSyncFailure\|_fetchAllRows(" lib/core/services/sync_service.dart` → 2992, 3183.
- **status:** accepted — fixed: re-derived from doc comment to closing brace: `_fetchAllRows` 3154-3225, `_reportSyncFailure` 2983-3056 (both entries), `kNlogKeyShape`…`firstFreeLogKey` 1073-1095. A sweep of every registry cite into either file past its insertion point and of bare `file:NNNN` cites in `lib`, `test`, `docs/architecture` and the registry found no other stale one.

## Finding 3 — P3 — function_exception_swallow
- **file:line:** `_cleanupNutritionPullCopies`, `deleteAll` then `invalidateAfterSync()`
- **claim:** a delete that throws part-way left the flag unset (right: retried next launch) but skipped the provider invalidation, so screens kept stale totals until another write.
- **status:** accepted — fixed: the invalidation moved to `finally`, guarded by "a delete started" and the owner check; test "a delete that fails part-way: screens re-read, no flag, retried next launch" (seam `debugFailPullCopyDelete`). Mutation "never invalidate in finally" reddens 2 tests.

## Clean (reviewer's evidence, summarized)
No `nutritionBox` writer in `lib/` puts a meal-shaped, item-less, UUID-keyed row except the removed pull leg (every writer read); the run-once flag is per user and set only after the owner check; P4 renders the old pill byte-for-byte when the build sells or the account is PRO; no secrets; telemetry sinks only in `unawaited`; tier platform matches. 17 reviewer mutations: 12 red, 5 green (the 3 owner-guard mutations of Finding 1 and 2 masked mid-flow checks, covered by the top guard).

## Founder triage notes
Self-triaged under the standing max-autonomy rule (memory `feedback_max_autonomy_no_petty_approvals.md`): all three accepted and fixed in this batch, none false alarm.

## Tuning entry
- **2026-11-23** - blast-radius platform - 3 findings; 0 false_alarm; tuning: none (lens 6's "every owner guard is masked by another" shape and lens 1's inserted-lines sub-check both fired as written).
