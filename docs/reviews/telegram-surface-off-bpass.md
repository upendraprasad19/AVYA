---
reviewed_at: 2026-11-06T12:30:00+05:30
staged_against: 6cb989307b84 (hash of the fix-commit staged diff on base d27bf032, excluding docs/reviews and docs/plan-reviews; origin/main is 5 library-batch commits ahead and overlaps only open_issues.md, closed_issues.md and sot_registry.yaml, none deleted or renamed upstream)
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh agents, no conversation context: A code and tests, B docs, registry, board)
lens_set: [writer_reader_drift, guard_without_its_mirror, missing_input, asserted_fixture_value, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 15
verdict: accepted
---

# Code Review: Telegram surface off (OI-466, closes the residue of OI-227)

Plan `docs/plans/2026-11-06-telegram-surface-off.md` (section 8 records what this review changed), diagnose `docs/diagnoses/2026-11-06-telegram-promise-removed-b9d3f1.md`, ledger `docs/audit/telegram-surface-off.closure.yaml`. The staged tree had the complete gate loop, the whole-project `flutter analyze --no-fatal-infos` (0 errors, 0 warnings, 398 infos = baseline) and the full `flutter test` behind it before dispatch (one red, `land_pr_e2e_test.dart` "a hung gh is killed", a 400 ms deadline against a multi-fork shell stub on a loaded VPS, reproduced on the untouched base commit; CI on main is green for that commit). Reviewer A ran its allowed test files and `dart analyze` per file; reviewer B read only. No P0 or P1 from either seat.

Process notes from the coordinator: reviewer B deviated from its allow-list twice, harmlessly (one read-only `git ls-remote`, one scratch copy of the registry written to the session scratchpad outside the repo). Reviewer A proposed 8 mutants as text and was forbidden to apply them; the coordinator ran them with the in-memory harness after both seats had finished (6 were real survivors and are rows N1 to N6 of the mutation table; 2 declined below).

## Finding 1 - P2 - guard_without_its_mirror (A)
- **file:line:** `lib/features/ai_coach/screens/ai_coach/compact_header.dart:177,193` (item values) vs `:128-137` (`onSelected` cases); pin `test/contracts/telegram_surface_removed_test.dart`
- **claim:** the extraction split the menu's values from their dispatch; only the values were pinned, so renaming either side left a menu entry that did nothing with every test green.
- **verification:** mutant N2/N2b (`case 'upgrade':` renamed) survived before the fix.
- **status:** fixed (new test "every overflow menu value has its case in the real header handler"; N2 and N2b now red).

## Finding 2 - P2 - guard_without_its_mirror (A)
- **file:line:** `test/contracts/telegram_surface_removed_test.dart` header; `lib/features/ai_coach/screens/ai_coach/screen.dart:452`
- **claim:** the "tester with a saved telegram channel lands in chat" guarantee has two legs, no reader of the key and the chat area being unconditional; the second was unpinned (`git grep _buildChatArea -- test` was empty).
- **verification:** mutant N1 (`isPro ? _buildChatArea(...) : SizedBox.shrink()`) survived before the fix.
- **status:** fixed (pinned by its neighbours, header before and quick prompts after, plus one call site; N1 now red). The guarantee stays PRESENCE-only and the test header says so.

## Finding 3 - P2 - source-grep guard, indirection (A)
- **file:line:** `test/contracts/telegram_surface_removed_test.dart` deny regex, allow-list, `coach_channel` exemption
- **claim:** four ways round the scan: a deep link spelled `host: 't.me'` (no slash), `tg://` and the Devanagari spelling were not denied; the allow-list pinned counts, so swapping the string inside an allowed line passed; the migrator was exempt from the `coach_channel` check by file; the symbol check was a bare substring.
- **verification:** mutants N3, N3b, N3c, N4, N5 survived before the fix.
- **status:** fixed (`t.me` denied as a word, `tg://` and the Devanagari spellings added, built from code units so the file stays ASCII; allow-list is the EXACT trimmed lines; `coach_channel` pinned to one use in the migrator; symbols matched as whole words, N7 is the green control). Left as a recorded residue: adjacent literals (M10) and `\u` escapes in source, which no substring scan can see.

## Finding 4 - P3 - asserted_fixture_value (A)
- **file:line:** `test/contracts/telegram_surface_removed_test.dart:77-96`; `lib/shared/widgets/paywall_sheet.dart:153-154`
- **claim:** the paywall was pumped for the generic upgrade only, so the subtitle branches (the `Weekly AI Report` one is closest to the removed perk) were seen only by the substring scan.
- **verification:** mutant N6 (`${'Tele'}${'gram'}` in that branch) survived before the fix.
- **status:** fixed (every `case` label of the subtitle switch, 15, plus the default branch, is pumped; N6 now red).

## Finding 5 - P3 - pre-existing no-op (A)
- **file:line:** `lib/features/ai_coach/screens/ai_coach/compact_header.dart:130-132`; `lib/features/ai_coach/providers/ai_coach_provider.dart:167-190`
- **claim:** `Clear conversation` only calls `ref.invalidate(chatHistoryProvider)`, whose build re-reads every row from `coachBox`, so nothing is cleared. After this batch it is the only menu entry a PRO account has.
- **verification:** the coordinator confirmed it: byte-identical at `d27bf032`; `git grep` for any clearing implementation finds only `user_repository.dart:1212` (account wipe).
- **status:** spawned: OI-479 and ledger row `TG-CLEAR-NOOP` (`blocked_on_user`: what "clear" means across Hive and the cloud is a founder decision). The new test pins that the entry exists and is wired, and says it does not claim it works.

## Finding 6 - P3 - citation (A)
- **file:line:** `test/contracts/telegram_surface_removed_test.dart:23`
- **claim:** a test citation without its directory.
- **status:** fixed (full paths; both resolve).

## Finding 7 - P2 - claim accuracy, OI-476 security text (B)
- **file:line:** `docs/audit/open_issues.md` OI-476 "What"; `telegram-bot/bot.py:295-330`; `supabase/migrations/006_create_monetisation_tables.sql:58`
- **claim:** the text said an attacker can replace the real owner's `chat_id`, dropping the "probably" of the OI-227 text it was copied from. The table has `UNIQUE (user_id)` and the upsert names no `on_conflict`, so replacing an existing owner's chat would by reading hit a unique violation. Understated: the unknown-email reply is an account-existence oracle, and the success reply discloses the name, email and plan; the morning alert carries more than the workout (`morning-alert/message.ts:17-26`).
- **verification:** the coordinator re-read `bot.py:290-332` and migration 006 lines 49-59.
- **status:** fixed (paragraph rewritten to what the code shows; replacement marked NOT established; nothing was run).

## Finding 8 - P2 - corrected claim (B)
- **file:line:** `docs/diagnoses/2026-11-06-telegram-promise-removed-b9d3f1.md` `recurrence`
- **claim:** it cited finding 6 of the OI-227 review for "asked for a pin"; that is finding 4 (finding 6 is a cosmetic dead parameter).
- **status:** fixed.

## Finding 9 - P2 - corrected-claim sweep incomplete (B)
- **file:line:** `docs/audit/open_issues.md` OI-60 (two places), OI-278, OI-338, OI-467; `docs/architecture/database.md`; `docs/architecture/subscription.md`
- **claim:** six live statements still called the bot "out-of-repo" / "a separate repo" (it is tracked dormant code in `telegram-bot/`), and OI-467 said "the `source` value is read by the UI" (no reader exists in `lib/`).
- **verification:** `git grep -n -i "out-of-repo Telegram\|not in this repo\|separate repo on the OpenClaw\|separate OpenClaw VPS project\|value is read by the UI"`.
- **status:** fixed (each reworded to the verified fact; `hooks.md:482,547` stay, they are the verbatim pre-shortening archive).

## Finding 10 - P3 - asserted number (B)
- **file:line:** diagnose `cross_account_guard`
- **claim:** "eight other watchers remain" was the base commit's count for the file; after the two deletions it is six in `ai_coach_provider.dart` (69 across `lib/`).
- **status:** fixed.

## Finding 11 - P3 - registry range (B)
- **file:line:** `docs/sot_registry.yaml` `ai_coach_provider.dart` `log_measurement` range
- **claim:** `1588-1619` was a -32 shift of a range that was already one line short; the block is `1589-1620` including its closing `);`. The parity gate checks bounds only for a prose `method:`, so it could not see this.
- **status:** fixed (`1589-1620`; both SoT gates pass; mutant M13 re-run on the final registry is red).

## Finding 12 - P3 - stale text on lines the batch touched (B)
- **file:line:** `docs/architecture/ai-coach-detail.md:9`, `CLAUDE.md` AI Coach row, `lib/features/ai_coach/CLAUDE.md:20`, `docs/architecture/business-rules.md:26`
- **claim:** a nonexistent file path, the 50-per-day and 10-per-day-video caps (real: 10 and 5, `ai_limits.ts:30-31`), the retired reasoning tab, and a "dropped" bullet inside the FREE feature list.
- **status:** fixed (path, caps and reasoning tab corrected; the bullet removed, OI-278 keeps its own record). `.claude/memory/feature_decisions.md` "Telegram focus" history left on purpose: it is dated decision history.

## Finding 13 - P3 - root CLAUDE.md row no longer thin (B)
- **file:line:** `CLAUDE.md` Telegram Bot row, `README.md` same row
- **claim:** three sentences in a file that calls itself a thin index, and "not deployed" rested on a founder statement while OI-278 says DISABLED and OI-476 says the token was never checked.
- **status:** fixed (one clause: dropped, dormant code in `telegram-bot/` (OI-476), `telegram-admin-bot` is a different founder-ops bot).

## Finding 14 - P3 - board cosmetics (B)
- **file:line:** `docs/audit/open_issues.md` two blank lines before OI-476 and a mis-quoted old cell; `docs/audit/closed_issues.md` OI-227 Verified line with no separator
- **status:** fixed.

## Finding 15 - P3 - bug history incomplete (B)
- **file:line:** diagnose `related_bugs` / `recurrence`
- **claim:** `c7e3b9` records the in-repo `telegram-bot/` and the `receive_email` flaw (filed on OI-227 as "no new OI") and belongs in the history.
- **status:** fixed (`related_bugs: [c1b9d4, c7e3b9]`).

## Declined (proposed mutants, not findings)
- A's mutant 6 (a second, unrelated popup menu in the header): not a Telegram promise; every Telegram shape is already denied by the scan and the symbol checks.
- A's mutant 7 (a second `_jumpToBottom()` call site making the "One call site" comment false): pinning the number of call sites would only constrain legitimate edits; the comment is descriptive.

## Verified clean (attacked, not broken)
- Deleted symbols: `git grep` over `lib/ test/ integration_test/ scripts/ supabase/` finds no reference outside the absence list, one retirement comment and history docs; no sign-out or account-switch invalidation roster named the two deleted providers; `url_launcher` stays a real dependency elsewhere.
- `screen.dart` build: every piece the old channel branches carried is reachable once, unconditionally; `_jumpToBottom` has one call site; the removed OI-232 listener only compensated for the Telegram view remounting the list, a path that no longer exists.
- `coach_channel` / `telegram_connected`: no reader and no writer in `lib/`; only the migrator key list; `users.telegram_connected` is never restored into Hive.
- The comment stripper is string-aware (`//` in strings, nested block comments, raw and triple strings, `${}`); the allow-list recount gives 3 and 1; `lib/` has 584 Dart files; no Telegram text in `assets/`, `web/`, `android/`, `pubspec.yaml`, server prompts.
- Repointed pins are not weaker: the sanitization terminator occurs once, the counts (2 and 2) are unchanged, the chip pin is as tight as the old one.
- Ledger vs `validate_audit_closure.dart`, diagnose doc vs the validator, plan-review record vs `check_plan_review_record_exists.dart`: consistent; the record's only open field is `bpass`, set after this file exists. Secrets regex over the 1908-line diff: 0 hits; no `/home/ubuntu`, `/tmp` or session ids in added lines. OI board: `closed_issues.md` append-only, `open_issues.md` loses exactly OI-227 and OI-466.

## Founder triage notes
Coordinator triage, all findings non-pending. Two items need the founder and are on the board, not in the code: OI-476 (keep or delete `telegram-bot/` and the morning-alert fallback) and OI-479 (what `Clear conversation` should do), plus device check A17 of OI-348 for the one guarantee that is presence-only.

## Tuning entry
- **2026-11-06** - blast-radius platform - 15 findings; 0 false_alarm; tuning: none to the lens set. Observed for next time: a reviewer seat forbidden to edit can still propose mutants as text and the coordinator runs them (6 of 8 were real survivors of the author's own table); splitting the dispatch into a code-and-tests seat and a docs-and-board seat produced disjoint finding sets with no overlap, and only the docs seat caught the claim-accuracy P2s (an overstated exploit paragraph, a wrong review-finding number, six stale statements of a corrected claim).
