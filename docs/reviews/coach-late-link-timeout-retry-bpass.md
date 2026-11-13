---
reviewed_at: 2026-11-13T14:30:00+05:30
staged_against: 9e9b0c85
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh seats, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 8
verdict: accepted
verdict_note: no P0 or P1; 2 P2 and 6 P3, all fixed in this batch (the fix commit follows the reviewed head 9e9b0c85); each new test mutated
---

# B-pass: OI-505 (PR #262), reviewed head 9e9b0c85 (CI green: `land_pr.sh 262 --ci-only` result `ci-green`)

Seat A reviewed the Flutter client, seat B the server, the registry and the records. Both returned `VERDICT: no P0/P1`.
Each finding was re-checked in the code before it was taken.

## Seat A

### Finding A-F1 - P2 - guard_without_its_mirror
- **file:line:** `lib/core/services/sync/sync_coach.dart:359-367` (`stampedIds`), `:575-583` (`excludeIds`).
- **claim:** `stampedIds` counted restored copies (`source: cloud_restore`, id = the cloud id). After a restore wrote the unkeyed
  server row X as its own sibling, X was barred from the unlinked local turn K: step 1 missed, step 2 (`now - 5 min`) missed
  for an old turn, and K uploaded as a second keyed row, the bug fix 1 exists to prevent (restore-then-push order).
- **verification:** `grep -n "cloud_restore" lib/core/services/sync/sync_coach.dart` (the init loop had no source filter).
- **status:** accepted, FIXED: the init loop skips `source == 'cloud_restore'`. Test L13 (restore, then push: no write, K stamped).
  Mutant Q1 (the skip removed) RED L13.

### Finding A-F2 - P3 - missing_input
- **claim:** a key whose instant is beyond year 9999 parses, prints `+010000-...`, and a throw in step 1 skipped step 2 and the upload.
- **status:** accepted, FIXED: `coachTurnInstantFromKey` and `_coachCreatedAtFromKey` return null above year 9999; step 1 is wrapped so a
  failure falls through to step 2 (`coach_turn_window_lookup_failed`, local only). Tests L14, L15. Mutants Q2 RED L14, Q3 RED L15.

### Finding A-F3 - P3 - unawaited_no_error_sink
- **claim:** an abandoned call's own `TimeoutException` was logged as `ai_service_chat_failed` (one extra event per expired send).
- **status:** accepted, FIXED: `if (e is TimeoutException) rethrow;` before the log in `chat()`.

### Finding A-F4 - P3 - doc drift
- **claim:** the `_sendKeyed` doc comment sat above `refreshSessionOverride`.
- **status:** accepted, FIXED: moved back above `_sendKeyed`.

## Seat B

### Finding B-F1 - P2 - writer_reader_drift (inserted-lines sub-check)
- **claim:** five registry cites of `lib/core/services/supabase_service.dart` (204, 243, 248, 324, 352; concept `edge_function_token_freshness`) were not shifted
  by the import line this diff adds at line 10 (text at the old line differs at HEAD).
- **verification:** `git show origin/main:lib/core/services/supabase_service.dart | sed -n 204p` against `sed -n 205p` at HEAD (the same declaration).
- **status:** accepted, FIXED: 205, 244, 249, 325, 353. Every `sync_coach.dart` / `ai_coach_provider.dart` / `ai_service.dart` cite was
  then re-derived from the diff hunks AGAIN after the B-pass edits, and the text at each new start line was compared with the text at the old line.

### Finding B-F2 - P3 - function_exception_swallow
- **claim:** `resolveKeyedReplay` swallows a lookup failure with no log; a persistent failure would turn fix 4 into a silent no-op.
- **status:** accepted, FIXED: the handler's `fetchRows` logs a FIXED string (`console.warn`, never the error object) before it rethrows.

### Finding B-F3 - P3 - asserted_fixture_value
- **claim:** the pin test's order check anchored on `const isProUser = await checkPro(`, whose first occurrence is the food path, so `keyed > isPro` was trivially true.
- **status:** accepted, FIXED: anchored on `const ruleOn = !isWriteClaimRuleDisabled();` (one occurrence, chat path, line 843, before the lookup at 850).

### Finding B-F4 - P3 - writer_reader_drift (records)
- **claim:** the diagnose / plan / pin-test header said the registry entry was `presence_only: true`, but it carries the Deno resolver test as
  `behavioral_test_path`; the plan said the Deno tests assert the select list and filters (they cannot: `fetchRows` is injected); d9a3b5 cited `chat_dedup.ts:130`.
- **status:** accepted, FIXED: wording aligned in the diagnose, the plan and the pin-test header; line 186. The `legacy_log_actions` marker
  (`status: queued`) would appear in the unread view `coach_tool_invocations_v` as one queued tool name: answered, no reader found in the repo, documented in d9a3b5.

## Checked and clean (both seats)
Every exit of `_sendKeyed` / `_sendWithMediaKeyed` releases the in-flight counter and replaces the loading bubble; `Future.timeout(onTimeout)` leaves no unhandled
zone error and a late success of the abandoned call writes nothing; `throwIfExpired` precedes every chat send; `client_retry` is `true` only for the Retry
button (both transports, the 401 re-send; never media or predict); with `client_retry` absent ai-proxy is byte-identical to main (no extra query);
the replay branch's columns are all selected; the lookup is scoped by the verified `user_id`; verdict windows 150 s / 6 h strict with boundary tests;
secrets scan clean; Deno 21 tests and the pin test green; all other shifted registry cites matched main's text.

## Tuning entry
- **2026-11-13** - blast-radius platform - 8 findings; 0 false_alarm; tuning: none (the registry inserted-lines sub-check already caught B-F1; the miss was the author's scan covering only 2 of the 4 edited files, so the author-side check now runs the hunk mapper over EVERY file the diff edits).
