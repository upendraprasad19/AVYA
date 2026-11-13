---
bug_id: c8f2a4
date: 2026-11-13
batch: coach-late-link-timeout-retry (OI-505 b)
status: fixed
blast_radius: platform
symptom: >-
  The founder asked the coach a question at 12:11 IST on 2026-11-13 and the chat spun for 19 minutes, then showed
  "Sorry, something went wrong". The request hung through a Supabase database outage (12:10:55 to 12:19:51 IST); the
  coach call has no time limit, so the app waited until the browser dropped the connection. No Retry was offered for
  those 19 minutes.
concept: coach_interactions
sot_registry_entry: coach_interactions (writer SendMessageNotifier._sendKeyed / _chatBounded; reader the chat bubble)
writers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method: SendMessageNotifier._chatBounded / _sendKeyed / _sendWithMediaKeyed
    line: 978
  - file: lib/core/services/coach_call_budget.dart
    method: CoachCallBudget (limits, expired flag)
    line: 16
readers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: ChatHistoryNotifier (the error bubble with its Retry button)
    line: 172
hive_key_prefix: coach_
hive_key_formula: "coachBox['coach_<phone ms>'] = {user_message, ai_response, failed, pending, ...}"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: []
contract_test_path: test/ai_coach/coach_chat_timeout_test.dart
ist_handling:
  - none needed: durations only
provider_invalidations:
  - chatHistoryProvider (refreshFromHive on every ending of the turn, as before)
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: unchanged
forbidden_patterns_checked:
  - { pattern: "errStr.contains\\('401'\\)", absent: false }
proposed_fix: >-
  SendMessageNotifier owns a time limit on every coach call: chat 75 s, photo 120 s, and a 90 s deadline for the whole
  chat turn including the one 401 re-send (the refresh has its own 15 s bound; an auth error later than 60 s is not
  re-sent). On timeout the call's CoachCallBudget is marked expired, so the abandoned call's retry loops (callFunction,
  retryColdStart, the direct-HTTP fallbacks, retryHttpColdStart) send nothing more (a Future.timeout abandons a future, it
  does not cancel it). The turn ends as a failed row with the timeout copy and the Retry button; the in-flight counter is
  released; a late answer is ignored. A TimeoutException is classified by TYPE, never by its text. New copy: timeout,
  photo timeout (may still be analysed), and the in_progress answer of fix 4 (before the generic 503 branch).
regression_test_planned:
  - test/ai_coach/coach_chat_timeout_test.dart
  - test/core/coach_call_budget_test.dart
  - test/ai_coach/coach_client_key_request_test.dart
  - test/contracts/coach_chat_refresh_during_send_test.dart
related_bugs:
  - 3e7b41  # the chat refresh during a send (loading bubble kept): the timeout path must release it the same way
  - e5c9d2  # the cold-start retry: stays intact, only gated on the budget
recurrence: |
  Not a recurrence of a coach-chat bug: no earlier diagnose covers a missing time limit on the coach call. Same family as
  the restore-path bounded reads (e5b2a9, a read with no bound hangs the screen); the known-good pattern is a bound owned
  by the caller plus a flag the abandoned call checks.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "ai_coach_provider.dart (_chatBounded, 401 re-send bounded, type-based classification, media timeout), coach_call_budget.dart (new), supabase_service.dart and ai_service.dart (budget checked before every send). 11 notifier tests, 11 budget tests." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "T1 reads the coachBox row after the timeout: failed true, counter released; T9 the normal path still stores the answer." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No migration; client_key (migration 178) and its partial index already exist and are read as they are." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live read-only 2026-11-13: the 07:00 turn has a server row (b5f81db2) and a keyed in_app_orphan uploaded at 12:31; the 12:11 turn has two keyed rows under one key (the Retry at 12:35). The two surplus rows are a data repair with its own founder go (plan section 6)." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Client-only fix." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes the touched paths." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change; the new ai-proxy lookup runs with the service role and filters on user_id from the verified token." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage change." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret; DISABLE_CLIENT_KEY_REPLAY is an optional env kill switch, absent by default." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "The budget travels in the call objects only; no request body changes for this fix (client_retry is fix 4). The re-send carries the same client_key and the Retry marker of its turn (T3, T3b)." }
impact_analysis: >-
  A hung call now ends at 75 s (photo 120 s) with a Retry button. A legitimately slow turn finishes on the server and a
  Retry replays its stored answer (fix 4). The 401 re-send keeps its single attempt but can no longer extend the turn past
  90 s. Known limit (written down, not closed): a Retry tapped while the FIRST request is still stuck before ai-proxy's
  reservation insert finds no row, runs, and spends a second unit; no client cancel of the wire request exists in the
  supabase functions client.
---

# The coach chat call had no time limit (c8f2a4)

## Root cause
- Writer: `SendMessageNotifier._sendKeyed` awaited `AiService.chat` with no bound. `SupabaseService.callFunction` retries
  cold starts and a direct-HTTP fallback re-sends, none with a deadline.
- Reader: the chat bubble stays in its loading state until the call returns or throws.

## Fix
See `proposed_fix`; plan section 4, fix 2.

## Tests
`test/ai_coach/coach_chat_timeout_test.dart` T1 to T9 (timeout copy and Retry, TimeoutException text with `401`, the 401
re-send and its bounds, the photo turn, in_progress copy in both exception shapes, the plain 503, the normal answer);
`test/core/coach_call_budget_test.dart` B1 to B11 (no attempt after expiry in `retryColdStart` and `retryHttpColdStart` at
entry, in the cold-start branch and in the storage-race branch).

## Mutation evidence (rule 21)
Script `mut505b.py` (session scratchpad): exact-string replacement with a count check, `TZ=Asia/Kolkata`, restored in a
`finally`.

11 mutants, all red. Confirmed APPLIED by the count check; the source was restored and the diff stat compared.

| id | mutation | result |
|---|---|---|
| N1 | `retryColdStart` loop-top budget guard removed | RED (B4, B5, B6) |
| N2 | `retryHttpColdStart` guard removed | RED (B8, B9, B10) |
| N3 | timeout classified by text (`!isTimeout &&` dropped) | RED (T2) |
| N4 | the timeout handler does not expire the budget | RED (T1, T4) |
| N5 | the chat call not bounded (`.timeout` removed) | RED (T1, T4) |
| N6 | the re-send drops the Retry marker | RED (T3b) |
| N7 | the latest-auth-resend limit ignored | RED (T5) |
| N8 | the photo call not bounded | RED (T6) |
| N9 | the session refresh unbounded | RED (T4b) |
| N10 | `resendTimeout` ignores the minimum | RED (B2) |
| N11 | `throwIfExpired` a no-op | RED (B1, B4, B5, B6, B8, B9, B10) |

Source-pin side (presence only, labelled): the `callFunction` budget forwarding and the existing pins
`retry_loop_guard_test`, `spends_quota_per_call_source_pins_test`, `edge_function_503_retry_test` were re-run green.
