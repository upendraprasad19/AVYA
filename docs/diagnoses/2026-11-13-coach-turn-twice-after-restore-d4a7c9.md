---
bug_id: d4a7c9
date: 2026-11-13
batch: coach-chat-time-dup (OI-503, Fix C)
status: fixed
blast_radius: platform
symptom: >-
  The founder asked the coach about the day's workout at 07:00 IST on 2026-11-13 (web app, iPhone Safari) and the
  question showed twice, each copy with the same reply. Live: ai_coach_interactions holds ONE row for it (b5f81db2,
  01:30:50 UTC), the edge logs show one ai-proxy request, and client_errors shows a full restore running 01:30:34 to
  01:31:17, the same minute. The phone wrote its row at coach_<phone ms> (mintCoachKey, before the AI call); the restore
  wrote the server's copy at coach_<server created_at ms>, 17 s later, so the thread held two rows for one turn. A second
  shape of the same cause: a restored copy (id = its own Hive key, not a uuid) was pushed back as an in_app_orphan once it
  was older than the push's 5-minute text window; 162 such rows exist live across 18 test accounts, 90 of them
  same-instant echoes of a server row.
concept: coach_interactions
sot_registry_entry: coach_interactions (writer _restoreCoachInteractions keyed path; writer _syncCoachInteractions key lookup + orphan client_key; cloud column client_key) and coach_client_key (new concept)
writers:
  - file: lib/core/services/sync/sync_coach.dart
    method: SyncServiceCoach._restoreCoachRowsKeyed (the cloud row back AT its client_key; unkeyed rows at coach_<server ms>)
    line: 538
  - file: lib/core/services/sync/sync_coach.dart
    method: SyncServiceCoach._syncCoachInteractions (key lookup first, keyed orphan, cloud_restore rows never pushed, fresh-read stamp)
    line: 289
  - file: supabase/functions/ai-proxy/index.ts
    method: chat reservation INSERT (client_key)
    line: 918
  - file: supabase/functions/ai-media-proxy/index.ts
    method: image paywall, video paywall and analysis INSERTs (client_key)
    line: 620
readers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: ChatHistoryNotifier.build (one bubble pair per coach_<ms> row)
    line: 172
  - file: lib/features/ai_coach/repositories/coach_interaction_repository.dart
    method_or_widget: getTodayUserMessageCount (one row per turn)
    line: 308
hive_key_prefix: coach_
hive_key_formula: "coachBox['coach_<phone ms>'] = {id (cloud uuid once known), user_message, ai_response, mode, created_at, pending, failed, ...}; a cloud row with client_key K restores to coachBox[K]"
sync_methods:
  - _syncCoachInteractions (push)
restore_methods:
  - _restoreCoachInteractions -> _restoreCoachRowsKeyed (kill switch configBox['disable_coach_client_key_restore'] keeps the old loop verbatim)
cloud_table: ai_coach_interactions
cloud_columns: [client_key, id, user_message, ai_response, model_used, created_at, channel]
contract_test_path: test/sync/coach_client_key_restore_test.dart
ist_handling:
  - none needed: keys are epoch ms and instants are compared as parsed DateTimes; no date key or day boundary is involved
provider_invalidations:
  - none (the restore's callers keep their chatHistoryProvider refresh)
telemetry_op_types:
  success: []
  failure: [coach_client_key_lookup_failed]
cross_account_guard: ownerChangedSince(userId) at the top of every keyed and unkeyed restore iteration and before every stale-copy delete; the in-flight counter is cleared in SyncService._onUserChanged
forbidden_patterns_checked:
  - { pattern: "await coachBox.put\\(key, updated\\)", absent: true }
proposed_fix: >-
  One identity per turn, shared by the phone and the server (founder decision 2026-11-13, after plan-review round 2 found
  a P0 in a text-and-time matcher). Migration 178 adds ai_coach_interactions.client_key (nullable, CHECK
  ^coach_[0-9]{10,16}$, partial index on (user_id, client_key)). The phone sends its row key as client_key in all four
  request bodies; ai-proxy and ai-media-proxy store it (a malformed key is dropped, never fails the insert). The restore
  groups keyed cloud rows by key, picks one (complete over incomplete, then latest), and writes it AT the key: absent ->
  written with id = uuid; present with the same turn text -> id stamped, and the reply filled only when the local row is
  incomplete, not in flight, the cloud row is complete, and the user has not already re-sent the turn; present with a
  different text -> left alone, the cloud row goes down the unkeyed path. A stale pre-key copy of the same cloud row is
  deleted; an unkeyed same-text same-instant echo of a keyed row is skipped. The push looks the key up first, never pushes
  a cloud_restore row or a row whose send is in flight, sends client_key on the orphan only when it matches the CHECK, and
  stamps the cloud id onto a fresh read. An in-flight COUNTER (CoachInteractionRepository) spans each send from the moment
  its key is known to after its last Hive write.
regression_test_planned:
  - test/sync/coach_client_key_restore_test.dart
  - test/sync/coach_client_key_push_test.dart
  - test/ai_coach/coach_client_key_request_test.dart
  - test/contracts/coach_client_key_ef_insert_test.dart
  - supabase/functions/_shared/client_key_test.ts
  - test/sql/coach_client_key_local.sh
related_bugs:
  - c3f9a1  # coach_<ms> same-millisecond collision: mintCoachKey, the key this fix sends
  - 5970aa  # OI-479 clear conversation: a restored row keeps its created_at, so a hidden row stays hidden (k14)
  - b6d2e8  # OI-502, the same batch: the UTC created_at readers
recurrence: |
  Recurrence of the APK Test #12.8 / Bug #1 class (restore key != writer key; see lib/core/services/CLAUDE.md "Restore
  writer keyed differently from production writer"). The 12.8 fix moved the coach restore from coach_<id hash> to
  coach_<server created_at ms> on the belief that the server's created_at is "stable and globally unique per turn" and so
  "collapses cloud -> local". It is stable but it is NOT the phone's key: the phone mints its key from its own clock before
  the AI call, so the two never matched for any turn sent from the phone. The push's stamp comment ("so subsequent
  restores collapse") described a reader that did not exist: the restore never read the stamped id. Known-good fix of the
  class applied: make the restore write at the WRITER's key, here by carrying that key through the server.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "sync_coach.dart keyed restore + push; ai_service.dart four bodies; ai_coach_provider.dart in-flight span; coach_interaction_repository.dart counter; sync_service.dart clear on user change. 26 restore, 9 push, 9 request, 7 EF-pin tests." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "Restore and push tests write real coachBox rows and read them back (one row per turn, ids, fills, deletes), and through ChatHistoryNotifier.build and getTodayUserMessageCount (k1 readers)." }
  - { tier: 3, name: postgres_schema, status: fixed_in_this_batch, evidence: "Migration 178 rehearsed in a local supabase/postgres 17.6 container (test/sql/coach_client_key_local.sh, 14 cases, 4 mutants red). Applied live 2026-11-13 after the founder go (cloud version 20261113030538); post-apply live: client_key text nullable as the 13th column, CHECK and index equal the file, 0 keyed rows." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live read-only 2026-11-13: one cloud row (b5f81db2) for the doubled turn; 162 in_app_orphan rows across 18 test users, 90 same-instant echoes. No backfill; the optional echo DELETE needs its own go." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "178 minted by mint_migration.sh (mig/178); applied 2026-11-13, version 20261113030538; backups/applied_migrations.json entry with the file hash; live_schema_columns.json regenerated (13 columns)." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "ai-proxy and ai-media-proxy changed; deno check --node-modules-dir=none clean for both; Deno tests 4 + 25 green. Deploy pending the founder's go, before any client build (plan C7)." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes client_key." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "RLS on ai_coach_interactions is row-level own-row only; the local rehearsal (K4) inserts a keyed row as authenticated and is refused for another user's row." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage change." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "client_key added to the ai-proxy and ai-media-proxy request bodies (both transports) and to the client orphan upsert; the end-to-end check is the real-token smoke after the deploy (one chat turn, one photo turn, each row carrying client_key)." }
impact_analysis: >-
  A turn sent from a build with this fix restores to one row on the sending phone and to the same key on any other
  device. Turns sent before it carry no key and keep the old restore path; a device that already shows a doubled
  pre-batch turn heals on sign-out and sign-in (the fresh restore writes the cloud row and its same-instant echo at one
  key). Restored rows are no longer pushed back, so no new in_app_orphan echoes are created. Server readers of
  ai_coach_interactions are unchanged; the new column is nullable and unread by them. The kill switch restores the old
  loop; key emission and the push lookup stay on and are harmless.
---

# One coach turn showed twice after a restore (d4a7c9)

## Root cause
- Writer of the phone row: `CoachInteractionRepository.saveUserMessagePending` puts `coach_<phone ms>` (`mintCoachKey`)
  before the AI call.
- Writer of the server row: ai-proxy's chat reservation INSERT, `created_at` = the server's now (17 s later in the
  founder's case: the AI call and a cold start in between).
- The restore keyed the server row by its own `created_at` (`sync_coach.dart`, pre-fix lines 302-306), so the two rows
  never shared a key. The push stamped the cloud id onto the phone row "so subsequent restores collapse", but the restore
  never read that id.

## Fix
See `proposed_fix` above and the plan, section 4 (rev 3.3, converged after five review rounds).

## Tests
- `test/sync/coach_client_key_restore_test.dart`: k1 to k23 (plus k22b, the readers case, the kill-switch case, the pick
  tiers, `coachTurnText`).
- `test/sync/coach_client_key_push_test.dart`: p1 to p9 against a stub with real PostgREST filter semantics (p5 is a
  database without the column: a real 400 / 42703).
- `test/ai_coach/coach_client_key_request_test.dart`: the key in the request and the in-flight span through the real
  `SendMessageNotifier` (new send, failure, Retry, media), plus source pins for the four bodies and the try/finally.
- `test/contracts/coach_client_key_ef_insert_test.dart`, `_shared/client_key_test.ts`, the ai-media-proxy paywall test.
- `test/sql/coach_client_key_local.sh`: the migration in a throwaway container.

## Mutation evidence (rule 21)
Each mutant was applied by exact-string replacement with a count check (exactly one match, else NOT APPLIED), its test
files were run under `TZ=Asia/Kolkata`, and the file was restored and checked by sha256. Script `mut503.py` in the
session scratchpad. 40 mutants of the client, server and SQL, 39 red, 1 equivalent (C6).

| id | mutation | result |
|---|---|---|
| R1 | restore never groups by key | RED 14 |
| R2 | fill ignores the in-flight check | RED 2 (k3, k19) |
| R3 | fill ignores local completeness | RED 1 (k17) |
| R4 | fill ignores cloud completeness | RED 1 (k5) |
| R5 | no re-sent-turn guard | RED 1 (k20) |
| R6 | no media tag strip | RED 2 (k21) |
| R7 | no occupied-key check | RED 1 (k15) |
| R8 | no stale-copy delete | RED 1 (k9) |
| R9 | no echo skip | RED 1 (k16) |
| R10 | no owner check in the keyed loop | RED 1 (k11) |
| R11 | kill switch ignored | RED 1 (k12) |
| R12 | stale delete ignores the key shape | RED 1 (k22b) |
| R13 | an `await` inside the decision slice | RED 1 (k23) |
| R14 | the pick ignores completeness | RED 1 (pick tiers) |
| R15 | no id stamp | RED 7 |
| P1 | the push sends `cloud_restore` rows | RED 1 (p9) |
| P2 | the push sends in-flight rows | RED 1 (p6) |
| P3 | no key lookup | RED 5 |
| P4 | the orphan is unkeyed | RED 1 (p3) |
| P5 | the key is sent after a failed lookup | RED 1 (p5) |
| P6 | the key shape is loosened to `coach_` | RED 1 (p3) |
| P7 | a stale pre-await copy is written on a key hit | RED 2 (p7) |
| P8 | the stamp re-creates a deleted row | RED 1 (p8) |
| C1 | the primary chat body drops `client_key` | RED 1 (source pin) |
| C2 | the send does not pass the key | RED 3 |
| C3 | `beginInFlight` after the Retry's reset put | RED 3 |
| C4 | the send never releases the key | RED 4 |
| C5 | the media send never counts the key | RED 2 |
| C6 | the null check folded into `n <= 1` | EQUIVALENT: an absent key is removed, a no-op either way |
| C6b | `endInFlight` decrements below zero | RED 1 (k19) |
| C7 | the counter becomes a set | RED 1 (k19) |
| C8 | the account switch keeps the counter | RED 1 (source pin) |
| E1 | ai-proxy's reservation drops `client_key` | RED 2 (Dart pin) |
| E2 | ai-media-proxy's analysis insert drops it | RED 1 (Dart pin) |
| E3 | ai-media-proxy's image paywall insert drops it | RED 1 (Deno paywall test) |
| E4 | `sanitizeClientKey` unanchored | RED (Deno `client_key_test.ts`) |
| M1-M4 | migration 178: CHECK removed / unanchored / index removed / `RESET` removed | RED 6 / 2 / 2 / 1 (`test/sql/coach_client_key_local.sh`) |
