---
bug_id: d9a3b5
date: 2026-11-13
batch: coach-late-link-timeout-retry (OI-505 c)
status: fixed
blast_radius: platform
symptom: >-
  After the 12:11 IST outage the founder tapped Retry at 12:35 on a turn whose first request had in fact reached
  ai-proxy and finished. ai-proxy reserved a SECOND row under the same client_key (two rows, one key, both complete) and
  spent a second unit of the daily chat cap. The 30-second text dedup does not reach a Retry tapped minutes later and the
  cap trigger runs BEFORE INSERT only.
concept: coach_interactions
sot_registry_entry: coach_interactions (writer ai-proxy reservation insert and resolution UPDATE; reader the keyed replay)
writers:
  - file: supabase/functions/ai-proxy/index.ts
    method: chat reservation insert (client_key) and resolution UPDATE (tool_calls, legacy_log_actions marker)
    line: 960
readers:
  - file: supabase/functions/_shared/chat_dedup.ts
    method_or_widget: resolveKeyedReplay / keyedReplayVerdict (the keyed lookup before the text dedup)
    line: 130
  - file: supabase/functions/ai-proxy/index.ts
    method_or_widget: the replay_reply branch (one reply body)
    line: 920
hive_key_prefix: coach_
hive_key_formula: "not applicable (server-side fix; the app only sends client_retry on its Retry button)"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [id, user_message, ai_response, model_used, tokens_used, tool_calls, created_at, client_key]
contract_test_path: supabase/functions/_shared/chat_dedup_keyed_test.ts
ist_handling:
  - none needed: instants compared as epoch ms
provider_invalidations:
  - none
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: the lookup filters on user_id from the verified token and on channel app
forbidden_patterns_checked:
  - { pattern: "client_retry === true", absent: true }
proposed_fix: >-
  Only a Retry carries the marker: the app sends client_retry true (both chat transports, the 401 re-send included) only
  when existingCoachKey != null. With the marker and a valid client_key, ai-proxy (kill switch env
  DISABLE_CLIENT_KEY_REPLAY = 1) reads up to 5 rows of that key BEFORE the text dedup and the reservation:
  the newest complete text-only row of the same message not older than 6 h is replayed (one reply body, no reservation,
  no unit); a young (under 150 s) pending row answers 503 in_progress (the cold-start retry asks again); anything else
  falls through to the old path. A reply that carried an APPLY card, a completion tile or legacy [LOG...] tags is never
  replayed: the resolution UPDATE appends a legacy_log_actions record for the tags the stored clean reply no longer holds.
regression_test_planned:
  - supabase/functions/_shared/chat_dedup_keyed_test.ts
  - test/contracts/coach_keyed_replay_ef_test.dart
  - test/ai_coach/coach_client_key_request_test.dart
related_bugs:
  - a17bc3  # 2026-05-16 chat dedup: the 30 s text dedup this sits in front of
  - a5c8e2  # hard-failure apology replay: stays intact
recurrence: |
  Recurrence class: the 30-second dedup window (a17bc3, 2026-05-16, and a5c8e2) only covers a quick repeat; a slow Retry
  walked past it. Known-good pattern applied: key the reuse on an explicit identity (client_key) and gate it on an explicit
  marker, because the client reuses the Hive key of a COMPLETED row for the same text within 60 s
  (_findRecentDuplicateMessageKey), so a replay keyed on the key alone would serve a stale answer to a deliberate repeat.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "ai_service.dart sends client_retry on a Retry in both chat bodies (the notifier passes isRetry); ai_coach_provider.dart threads the flag through _chatBounded and the re-send." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive shape change." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No migration; client_key (migration 178) and its partial index already exist and are read as they are." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live read-only 2026-11-13: the 07:00 turn has a server row (b5f81db2) and a keyed in_app_orphan uploaded at 12:31; the 12:11 turn has two keyed rows under one key (the Retry at 12:35). The two surplus rows are a data repair with its own founder go (plan section 6)." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "ai-proxy and _shared/chat_dedup.ts changed; deno check --node-modules-dir=none clean; 21 Deno tests green. Deploy pending the founder's go (host-shell deploy, then a real-token smoke)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes the touched paths." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change; the new ai-proxy lookup runs with the service role and filters on user_id from the verified token." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage change." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret; DISABLE_CLIENT_KEY_REPLAY is an optional env kill switch, absent by default." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "client_retry is a new request-body field: absent on a new ask and on the automatic cold-start retry; end-to-end proof is the live smoke after the deploy (one finished turn re-sent with the same key and client_retry true: deduplicated true, no new row, no unit; without the marker it runs normally)." }
impact_analysis: >-
  A Retry of a finished turn now returns its stored answer and spends no unit; a Retry of a failed turn runs as before.
  Explicit non-goals: (1) a Retry tapped while the first request is still stuck BEFORE ai-proxy's reservation insert
  finds no row and runs (a second unit; fix 2 makes it reachable by offering Retry at 75 s); (2) media turns: no client
  path re-sends a media key, so ai-media-proxy is not changed. A handler killed after its reservation leaves a pending row
  that blocks a Retry for at most 150 s. Order of rollout: the ai-proxy deploy must precede or accompany the client build;
  an old ai-proxy ignores client_retry, so a new client against it behaves as today.
---

# A Retry of a finished coach turn reserved a second row (d9a3b5)

## Root cause
- Writer: ai-proxy's chat reservation `insert` (`model_used: "pending"`) runs for every request that passes the 30 s text
  dedup; the cap trigger `trg_chat_app_rate_limit` is `BEFORE INSERT` only, so each new reservation spends a unit.
- Reader: the text dedup (`dedupDecision`) looks only 30 s back.
- A Retry minutes later therefore inserted a second row under the same `client_key`.

## Fix
See `proposed_fix`; plan section 4, fix 4 (rev 5).

## Tests
Deno `_shared/chat_dedup_keyed_test.ts`: the `keyedReplayVerdict` table (no row, other message, real reply, A real plus B
newer failed, newest wins in either order, sentinel, young and stale pending, complete beats pending, card / tile /
legacy-marker rows, object and null `tool_calls`, age cap, unparseable `created_at`, empty reply) and the
`resolveKeyedReplay` wiring with an injected lookup (no fetch without the strict boolean, without a key, under the kill
switch; the exact 503 body; a failed lookup never blocks chat).
`test/contracts/coach_keyed_replay_ef_test.dart`: presence pins for the handler wiring (ai-proxy starts `serve(` at module
scope), registered `presence_only`.

## Mutation evidence (rule 21)
Script `mut505c.py` (session scratchpad): exact-string replacement with a count check; the source restored in a `finally`
and its sha256 compared. 16 mutants of `chat_dedup.ts`, all red.

| id | mutation | result |
|---|---|---|
| K1 | no retry-marker check | RED (1) |
| K2 | marker truthy, not strict `true` | RED (1) |
| K3 | kill switch ignored | RED (1) |
| K4 | lookup without a key | RED (1) |
| K5 | lookup failure not caught | RED (1) |
| K6 | other message replayed | RED (1) |
| K7 | age cap removed | RED (1) |
| K8 | failure-sentinel row replayed | RED (3) |
| K9 | card / tile rows replayed | RED (1) |
| K10 | oldest row instead of newest | RED (1) |
| K11 | pending row never stale | RED (1) |
| K12 | pending row ignored | RED (2) |
| K13 | legacy marker by name dropped | RED (1) |
| K14 | object `tool_calls` blocks replay | RED (7) |
| K15 | in_progress status not 503 | RED (1) |
| K16 | empty reply replayed | RED (1) |

Handler wiring (script `mut505d.py`): 8 mutants of `ai-proxy/index.ts` and `ai_service.dart` against
`test/contracts/coach_keyed_replay_ef_test.dart`, all red: H1 `client_retry` not passed, H2 replay row not assigned to
`recentDup`, H3 lookup not scoped to the user, H4 kill-switch compare changed, H5 legacy marker dropped, H6
`client_retry` dropped from one chat body, H7 the 503 status not read from `keyed`, H8 the key not sanitized. These pins
prove PRESENCE of the wiring, not the order of execution at runtime; the order is proven by the live smoke after the
deploy.
