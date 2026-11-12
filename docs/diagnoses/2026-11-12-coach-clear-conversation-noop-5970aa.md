---
bug_id: 5970aa
date: 2026-11-12
batch: oi479-clear-conversation
status: fixed
blast_radius: platform
symptom: >-
  The AI Coach overflow menu item "Clear conversation" did nothing: the chat thread was unchanged after choosing it
  (OI-479, found by the OI-466 B-pass). Its handler only invalidated chatHistoryProvider, whose build re-reads every
  coachBox row, and nothing in lib/ cleared, hid or deleted chat rows except the whole-account wipe.
concept: coach_chat_cleared_at
sot_registry_entry: coach_chat_cleared_at
writers:
  - file: lib/features/ai_coach/screens/ai_coach/compact_header.dart
    method: "onSelected case 'clear' (was ref.invalidate(chatHistoryProvider) only) -> confirmClearCoachConversation"
    line: 133
  - file: lib/core/services/coach_chat_clear.dart
    method: CoachChatClear.clear / raiseTo (the ONE writer of userBox['coach_chat_cleared_at']; monotonic)
    line: 99
  - file: lib/core/services/sync/sync_profile.dart
    method: _restoreUserPreferences (adoption of the cloud column, max-wins, capped at device now)
    line: 1161
  - file: supabase/migrations/177_coach_chat_cleared_at.sql
    method: raise_coach_chat_cleared_at (cloud writer; GREATEST, LEAST(p_at, now()), NULL refused)
    line: 33
readers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: ChatHistoryNotifier.build (hides rows at or before the marker; today's unresolved tile exempt)
    line: 172
  - file: lib/features/ai_coach/repositories/coach_interaction_repository.dart
    method_or_widget: recentHistoryExchanges (the coach's short-term history starts after the marker)
    line: 366
  - file: lib/features/ai_coach/repositories/coach_interaction_repository.dart
    method_or_widget: _findRecentDuplicateMessageKey (never reuses a hidden row)
    line: 167
hive_key_prefix: null
hive_key_formula: "userBox['coach_chat_cleared_at'] = UTC ISO-8601 instant; userBox['coach_chat_cleared_at_pushed'] = '<marker>|<istDateStr(nowWall())>'"
sync_methods:
  - CoachChatClear.clear -> SyncService.pushCoachChatClearedAt (fire-and-forget)
  - SyncService._syncUserPreferences -> pushCoachChatClearedAt (retry leg, outside its try)
  - AuthNotifier._teardown -> pushCoachChatClearedAt(fromSignOut: true), 2 s, before clearAllData
restore_methods:
  - SyncService._restoreUserPreferences (removes the column before the generic merge; adopts it max-wins)
cloud_table: user_preferences
cloud_columns:
  - coach_chat_cleared_at
contract_test_path: test/contracts/coach_chat_clear_behavioral_test.dart
ist_handling:
  - The marker is an instant, never an IST day key; every comparison parses both sides to UTC instants (created_at is written with Z locally and as the cloud's +00:00 microsecond form after a restore).
  - The pushed-memory is bounded by istDateStr(nowWall()), as _pushStreakWeekMarker.
  - D3's "today" uses the existing istTodayStr() filter in ChatHistoryNotifier.build.
provider_invalidations:
  - chatHistoryProvider (after a clear; the restore-complete tick already invalidates it, screen.dart:200-205)
telemetry_op_types:
  success: []
  failure:
    - upsert_coach_chat_cleared_at
    - coach_chat_cleared_at_push_failed
cross_account_guard: >-
  userBox is user-scoped (opened per owner, wrapUserScopedBox). clear() captures HiveUserSession.currentOwnerFullId and
  re-checks ownerChangedSince before the write; the restore adoption has its own fresh ownerChangedSince after the
  preferences write and adoptFromCloud awaits; the push re-checks before the RPC and before the memory write; the
  sign-out push never reports a sync failure or writes memory (it can outlive the wipe).
forbidden_patterns_checked:
  - { pattern: "coachBox.delete / coachBox.clear in the clear path", absent: true }
  - { pattern: "coach_chat_cleared_at in buildUserPreferencesPayload (the wholesale upsert)", absent: true }
  - { pattern: "string compare of created_at against the marker", absent: true }
proposed_fix: >-
  Hide, never delete (founder D1). One instant, userBox['coach_chat_cleared_at'], written by CoachChatClear (max-wins);
  the chat thread, the coach history replay and the client dedup scan skip rows created at or before it; today's
  unresolved completion tile is exempt (D3). The instant syncs to user_preferences.coach_chat_cleared_at only through
  the monotonic RPC raise_coach_chat_cleared_at (migration 177) and is adopted on restore max-wins, capped at the
  device's now. A confirmation dialog; the item is disabled while a reply is in flight and CLEAR re-checks it.
regression_test_planned:
  - test/contracts/coach_chat_clear_behavioral_test.dart
  - test/sync/coach_chat_cleared_at_sync_test.dart
  - test/ai_coach/clear_conversation_menu_test.dart
  - test/contracts/coach_chat_cleared_at_migration_text_test.dart
  - test/sql/coach_chat_cleared_at_local.sh
related_bugs:
  - e8a3b1  # restore pulling coach rows back into the thread on cold start: the reason a local delete cannot work
  - f3d704  # completion_prompt created_at stamped in two formats: the reason the marker compares instants
  - e4a1b7  # OI-98 user_preferences wholesale upsert vs per-key merge: the reason the marker has its own RPC
  - a3c8f1  # raise_streak_week_marker: the monotonic GREATEST RPC + IST-day pushed-memory precedent
recurrence: |
  Not a recurrence. Bug history searched (docs/diagnoses/INDEX.md for "clear conversation", "chat history",
  "coachBox", "completion prompt"; feedback memory for invalidate-only fixes): no prior diagnose of this menu item.
  The shape (a handler that only invalidates a provider whose build re-reads the same store) has no earlier entry.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "coach_chat_clear.dart (new), ai_coach_provider.dart, coach_interaction_repository.dart, compact_header.dart, sync_profile.dart, sync_coach.dart (test seam), auth_provider.dart (sign-out push); flutter analyze clean." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "Real-Hive tests: thread / replay / dedup hide by instant, D3 tile kept, restore re-put rows stay hidden, daily count unchanged (coach_chat_clear_behavioral_test.dart, 11 tests, Kolkata / UTC / Tokyo)." }
  - { tier: 3, name: postgres_schema, status: fixed_in_this_batch, evidence: "Migration 177 adds user_preferences.coach_chat_cleared_at timestamptz NULL; rehearsed in the local supabase/postgres 17.6 container (test/sql/coach_chat_cleared_at_local.sh, 18 cases)." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No row is rewritten; the column starts NULL for every user." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "Applied live only on the founder's explicit go; backups/applied_migrations.json updated in the same commit (see the Live apply section)." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: verified, evidence: "No EF change: restore-user-snapshot selects * from user_preferences (index.ts:165-167), so the column reaches _restoreUserPreferences unchanged; semantic retrieval kept (D5)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "user_preferences keeps own-row select / insert / update-with-check (001, 055, 100); the RPC is SECURITY INVOKER keyed on auth.uid(); docker: user A cannot touch B's row, anon has no EXECUTE (has_function_privilege f)." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "coach_chat_cleared_at_sync_test.dart drives the real supabase client against a stub PostgREST: the RPC name and p_at body, the restore GET with the +00:00 microsecond form, the failure op type; the docker harness proves the server half." }
impact_analysis: >-
  "Clear conversation" now asks first, then empties the thread on this device and, once synced, on every device at its
  next launch. The coach starts a fresh short-term conversation but keeps its long-term memory and semantic recall
  (D2, D5). Nothing is deleted locally or in the cloud; the daily message limit, the weekly report and every server
  job see the same rows as before. Today's unfinished-workout tile stays until the day is completed (D3).
---

# "Clear conversation" did nothing (5970aa, OI-479)

Plan: `docs/plans/2026-11-12-oi479-clear-conversation.md` (converged after three review rounds; record
`docs/plan-reviews/oi479-clear-conversation.md`).

## Root cause
`compact_header.dart` handled `case 'clear'` with `ref.invalidate(chatHistoryProvider)` only.
`ChatHistoryNotifier.build` rebuilds the list from every `coachBox` row, so the rebuild produced the same thread. No
code anywhere hid or removed chat rows (the only `coachBox.clear()` is the account wipe, `user_repository.dart:1212`).

## Fix
`proposed_fix` above; the founder's decisions D1-D5 and the coordinator calls C1 (Home tip unchanged) and C2 (pending
action cards survive) are in plan section 2. Deviation from the plan: `CoachChatClear` lives in `lib/core/services/`
(not `features/ai_coach/services/`), because the sync layer reads and writes the same marker and core does not import
feature code (the reason `CompletionPromptStore` lives there too); the dialog flow is the top-level
`confirmClearCoachConversation` so a widget test can drive it.

## Mutations (rule 21)
A scripted harness applied each mutant (exact-string replace, count asserted == 1 so it provably applied), ran the
named test file(s) under TZ=Asia/Kolkata, restored the file from a byte copy and asserted the bytes equal the
original; afterwards a sha256 manifest of all 18 changed files taken before the run verified clean. 22 of 22 red:

| Mutant | Reddened |
|---|---|
| M1 drop the thread filter | 8 tests (every T1 case and T5) |
| M2 `<=` becomes `<` | T1 "a row exactly AT the marker is hidden" |
| M3 string compare of `created_at` | T1 "compared as an INSTANT" |
| M4 drop the D3 tile exception | T1 D3 |
| M5 a row with no stamp shown | T1 "missing or unparseable created_at" |
| M6 drop the replay filter | T2 |
| M7 drop the dedup filter | T3 |
| M8 the daily count reads the marker | T4 presence pin |
| M9 local marker read at method entry | T6 "a clear made DURING the fetch" |
| M10 column not removed before the merge | T6 "never lands in userBox[preferences]" |
| M11 drop the device-now cap | T6 "capped at device now" |
| M12 drop the max (plain put) | 2 T6 cases |
| M13 drop the fresh owner check | T6 "an account swap after the preferences write" |
| M14 push inside the preferences try | T7 "_syncUserPreferences pushes ... even when its own upsert fails" |
| M15 drop the pushed-memory check | T7 "skips a repeat push the same IST day" |
| M16 sign-out push reports a sync failure | T7 "from sign-out a failure is only logged" |
| M17 teardown push after the wipe | T7 source-slice pin (the only harness for `_teardown`) |
| M18 CANCEL still clears | T8 "CANCEL changes nothing" (then the run timed out: the mutant writes Hive from the fake-async zone, the hang the test's runAsync pattern avoids) |
| M19 the item never disabled | T8 "the item is disabled while a reply is in flight" |
| M20 drop the CLEAR re-check | T8 "a send that starts while the dialog is open" (then timed out, same reason as M18) |
| M21 `clear()` never pushes | T7 "clear() stamps the marker and pushes it" + T8 "CLEAR stamps ... pushes it" (re-run by hand: both are assertion reds, not a compile error) |
| M22 migration NULL guard deleted | T9 "refuses a NULL p_at" |

## SQL rehearsal (T10)
`bash test/sql/coach_chat_cleared_at_local.sh` on `public.ecr.aws/supabase/postgres:17.6.1.084` (local, never prod):
18 cases green (insert and update branches, monotonic, future value clamped on both branches, NULL refused, user A
cannot touch B, anon denied and `has_function_privilege('anon', ...)` false, no `auth.uid()` refused, invoker with a
pinned `search_path`). Four migration mutants, each run through the same harness: NULL guard removed (C5 red),
GREATEST removed (C2 red), the INSERT-branch clamp removed (C4b red; it survived until C4b was added, because C4 ran
against a user who already had a row), the anon REVOKE removed (C8 red, both checks).

## Live apply
Pending the founder's explicit go (CLAUDE.md 4.3). Post-apply checks: `information_schema.columns` for the column,
`pg_proc` for `prosecdef = false` and the `proconfig`, and `has_function_privilege('anon',
'public.raise_coach_chat_cleared_at(timestamptz)', 'execute') = false` live (the migrations CLAUDE.md row: the
default-privilege grant lives in no migration file).

## Residuals (accepted)
- Clock skew between a device and the server shifts the hide boundary by that skew for server-stamped (restored) rows
  (plan 3.1).
- A clear made offline and followed by a sign-out before reconnecting is lost with the wiped `userBox`: the OI-253
  class (a userBox queue lost at sign-out); recorded on OI-253 as a second instance.
- Another device sees the clear at its next launch, not live.
