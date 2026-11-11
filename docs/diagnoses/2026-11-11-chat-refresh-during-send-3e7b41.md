---
bug_id: 3e7b41
date: 2026-11-11
batch: coach-workout-parity-tile (S3, commit C; found by the S3 B-pass, seat 2 F3)
status: fixed
blast_radius: account
symptom: >-
  While a coach chat reply was pending, any chat refresh from Hive turned the loading dots into a false "This message
  didn't finish - Tap Retry" error bubble. The tool dispatcher refreshes the chat after a log_set APPLY (and after the
  S3 completion tile), so tapping APPLY on an earlier card during the wait did it. When the reply then landed,
  replaceLastMessage replaced whatever bubble was LAST: if that APPLY had just written the "X of Y - Complete workout"
  tile, the reply erased the tile from the live chat (back only after the next full rebuild). The retry path had the
  same shape on its own: it refreshed before adding its loading bubble, so the "didn't finish" bubble stayed above a
  successful retry reply. A second shape was found by the fix's own review seat: the in-flight flag was set only AFTER
  the first await (the pending-row write), so two taps in one frame (a double Retry, Retry plus a chip) both passed the
  `if (state) return` guard and left an orphan loading bubble, which the new refresh rule would then keep. Found in
  review, not by a user report; reproduced by a failing test (2 of 3 red before the fix).
concept: coach_interactions
sot_registry_entry: coach_interactions (reader ChatHistoryNotifier.build notes, refreshFromHive in-flight rule; writer `send` range re-anchored)
writers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method: SendMessageNotifier.send (pending row, user bubble, in-memory loading bubble; replaceLastMessage on reply)
    line: 808
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method: SendMessageNotifier.sendWithMedia (same two-write pattern, media)
    line: 612
  - file: lib/features/ai_coach/repositories/coach_interaction_repository.dart
    method: saveUserMessagePending (the coach_<ms> row with pending true)
    line: 88
readers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: ChatHistoryNotifier.build (renders a pending row as the "didn't finish" error, line 264 onward)
    line: 170
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: ChatHistoryNotifier.refreshFromHive (state = build(); the bug) and replaceLastMessage (positional)
    line: 367
  - file: lib/features/ai_coach/services/tool_dispatcher.dart
    method_or_widget: execute post-steps (refreshFromHive after the tile, line 214, and after log_set, line 243)
    line: 243
hive_key_prefix: coach_
hive_key_formula: "coachBox['coach_<ms>'] = {user_message, ai_response, pending, failed, created_at (UTC with Z), ...}"
sync_methods:
  - none changed (the in-memory list is UI state; the Hive row and its sync are untouched)
restore_methods:
  - none changed
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/contracts/coach_chat_refresh_during_send_test.dart
ist_handling:
  - not applicable (no date key; the tile row in the test is written for istTodayStr() and the file also runs under TZ=Etc/GMT+12)
provider_invalidations:
  - none (refreshFromHive sets chatHistoryProvider state directly, as before)
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a (the rebuild reads the current owner's coachBox as before; loading bubbles are in-memory UI only)
forbidden_patterns_checked:
  - { pattern: "isLoading: true,\\n\\s*\\)", absent: true }
proposed_fix: >-
  refreshFromHive rebuilds with build() and, when the in-memory list holds loading bubbles (a send in flight: every
  exit of send and sendWithMedia replaces its loading bubble), drops from the rebuilt list the AI-side error bubble
  whose coachKey matches a loading bubble's coachKey and appends the loading bubbles LAST. The loading bubbles in send
  and sendWithMedia now carry the turn's coachKey (no consumer acts on a loading bubble's coachKey: Retry needs
  isError, the media chip needs isUser). The retry path adds its loading bubble BEFORE its refresh. send and
  sendWithMedia claim the in-flight flag synchronously, right after their guard and before the first await, in a thin
  public wrapper that releases it in `finally` on every exit; the bodies moved unchanged into _sendBody and
  _sendWithMediaBody (placed right after their wrappers, so the source slices other tests take still hold them).
regression_test_planned:
  - test/contracts/coach_chat_refresh_during_send_test.dart
related_bugs:
  - 280c4d  # Unit 1, the tap-card tile row and the dispatcher's refresh after a prompt write
  - f4a7c2  # coach media consent: replaceLastMessage only swaps the trailing AI bubble (documented there)
  - a1c6b9  # history poisoning: a refreshFromHive elsewhere in the session noted as untested
recurrence: |
  Not a recurrence of a diagnosed bug. No diagnose doc names a refresh during an in-flight send (searched
  docs/diagnoses for replaceLastMessage, refreshFromHive, "didn't finish", loading placeholder; the four hits above
  describe the same primitives, not this overlap). New bug class 2.150 in .claude/skills/debugging/bug-classes.md.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "ai_coach_provider.dart refreshFromHive, the two loading-bubble sites, the retry order and the synchronous in-flight claim; 12 tests in coach_chat_refresh_during_send_test.dart green under TZ=Asia/Kolkata and TZ=Etc/GMT+12; 473 tests across the 35 files that name the provider green; mutation table below." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Tests write real coach_<ms> pending rows and a completion_prompt row through the real repository and store, then read the chat through ChatHistoryNotifier.build and refreshFromHive. No Hive write was changed." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "UI list only." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "UI list only." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request or response shape changed." }
impact_analysis: >-
  A refresh with no send in flight is unchanged (state = build()). With a send in flight, the loading bubble stays last
  and the in-flight turn shows no false error; a tile or other row written meanwhile keeps its place and survives the
  reply. An older crash-leftover pending row still shows its "didn't finish" bubble. If a future path ever left a
  loading bubble behind, refreshes would now keep it (before, a refresh cleared it): every exit of both send methods
  replaces it today, and the nested CLAUDE.md pitfall row and the source pin make a new loading site follow the rule.
---

# A chat refresh during an in-flight send wiped the loading bubble (3e7b41)

## Root cause
The send path keeps its loading bubble in memory only (`ai_coach_provider.dart:654`, `:878`) and swaps the reply in by
position (`replaceLastMessage`, `:426`). `refreshFromHive` (`:367`) replaced the whole list with `build()` (`:170`),
which renders the in-flight turn's `pending: true` row (`:264`) as the crash-leftover "didn't finish" error. The
dispatcher calls `refreshFromHive` after a `log_set` APPLY (`tool_dispatcher.dart:243`) and after the S3 tile
(`:214`). An APPLY tapped during the network wait therefore replaced the dots with an error, and the reply replaced the
last bubble instead of the dots.

## Fix
- `refreshFromHive`: no loading bubble in state, `state = build()` as before. Otherwise the rebuilt list minus the
  AI-side error bubble whose `coachKey` matches a loading bubble, then the loading bubbles LAST.
- Both loading bubbles carry `coachKey: coachKey`.
- The retry path adds its loading bubble before its `refreshFromHive()`.
- `send` / `sendWithMedia` claim `state = true` before the first await and release it in `finally` (review seat F1:
  two overlapping sends would otherwise leave an orphan loading bubble that the refresh rule keeps).

## Tests
`test/contracts/coach_chat_refresh_during_send_test.dart` (12). Through the REAL `SendMessageNotifier` (a fake
`AiService` holds each model call open with a Completer; review seat F2):
- retry with a refresh while the reply is pending: the dots stay last, no error bubble, none left after the reply;
- two `send` calls in one frame: one model call, no orphan loading bubble, the flag released;
- the same for two `sendWithMedia` calls;
- the free daily limit (an early return inside the body) releases the flag;
- an empty message never claims it.

At the notifier level, the send's steps in order, then a refresh, then the reply's `replaceLastMessage`:
- the loading bubble stays last, no "didn't finish", the reply lands, the user bubble is kept once;
- a tile written during the send survives the reply;
- an unkeyed loading bubble is still kept last (the tile survives);
- an OLDER crash-leftover pending row keeps its "didn't finish" bubble (mirror);
- retry: no error bubble once the reply lands;
- a pin that every `isLoading: true` site carries `coachKey: coachKey` (2 sites) and the retry adds it before its refresh;
- no send in flight: a leftover pending row still renders as "didn't finish" (mirror).

Before the fix, the first two failed (the third case existed then as the mirror and passed). The file passes under
`TZ=Asia/Kolkata` and `TZ=Etc/GMT+12`.

## Mutation evidence (rule 21)
Exact-string replacement, anchor count asserted 1, file restored and checked by sha256 after each mutant
(`refresh_mutants.py` in the session scratchpad).

| id | edit | result |
|---|---|---|
| R1 | refresh ignores loading bubbles (`state = build()` always) | RED, 3 (in-flight, tile, unkeyed) |
| R2 | in-flight error bubble not dropped | RED, 3 (in-flight, older-leftover count, retry) |
| R3 | EVERY AI error bubble dropped (no key match) | RED, 1 (older-leftover mirror) |
| R4 | loading bubbles put FIRST | RED, 3 (in-flight, tile, unkeyed) |
| R5 | retry refreshes before adding its loading bubble | RED, 2 (the source pin and the real-send retry case) |
| R6 | text-send loading bubble without `coachKey` | RED, 2 (the source pin and the real-send retry case) |
| R7 | media-send loading bubble without `coachKey` | RED, 1 (the source pin) |
| Q1 | `send` wrapper does not claim the flag | RED, 1 (two sends in one frame) |
| Q2 | `sendWithMedia` wrapper does not claim the flag | RED, 1 (two media sends in one frame) |
| Q3 | `send` claims the flag after an await | RED, 1 (two sends in one frame) |
| Q4 | `send` wrapper's `finally` does not release | GREEN at first (the body's own `finally` releases on the normal path); the free-limit early-return case was added and turns it RED, 1 |

R7 reddens only the source pin: a media loading bubble's key matters only to a refresh during a media send, which the
notifier-level cases cover with keyed bubbles built the same way. Survivors: none.
