---
bug_id: b7e1f3
date: 2026-11-13
batch: coach-late-link-timeout-retry (OI-505 a)
status: fixed
blast_radius: platform
symptom: >-
  The founder's 07:00 IST coach question of 2026-11-13 (test account, web app on an iPhone) showed a second time, hours
  later, as a keyed in_app_orphan row (uploaded 12:31 IST) next to the real server row (b5f81db2, 01:30:50 UTC). The
  second row carried client_key coach_<phone ms>, so the restore now writes it at the phone's key and it looks like a
  second turn. Cause: the push's text lookup for a row with no cloud id asked for rows created in the last 5 minutes
  (now - 5 min); the turn was linked 5.5 h after it was sent (the phone had been re-signed-in / stuck), the lookup found
  nothing and the row went up as a NEW keyed orphan.
concept: coach_interactions
sot_registry_entry: coach_interactions (writer _syncCoachInteractions text lookup, step 1 anchored to the key's instant)
writers:
  - file: lib/core/services/sync/sync_coach.dart
    method: SyncServiceCoach._syncCoachInteractions (text lookup, steps 1 and 2) and _lookupCoachTurnWindowRow
    line: 357
readers:
  - file: lib/features/ai_coach/providers/ai_coach_provider.dart
    method_or_widget: ChatHistoryNotifier.build (one bubble pair per coach_<ms> row)
    line: 172
  - file: lib/core/services/sync/sync_coach.dart
    method_or_widget: _restoreCoachInteractions -> _applyKeyedCoachRows (writes a keyed cloud row AT its key)
    line: 538
hive_key_prefix: coach_
hive_key_formula: "coachBox['coach_<phone ms>'] = {id (cloud uuid once known), user_message, ai_response, mode, created_at, ...}"
sync_methods:
  - _syncCoachInteractions (push)
restore_methods:
  - _restoreCoachInteractions
cloud_table: ai_coach_interactions
cloud_columns: [client_key, id, user_message, created_at, channel]
contract_test_path: test/sync/coach_late_link_test.dart
ist_handling:
  - none needed: the window is anchored to the instant the key encodes (epoch ms) and compared as parsed DateTimes
provider_invalidations:
  - none (a stamp writes the cloud id onto the local row, as before)
telemetry_op_types:
  success: []
  failure: [coach_client_key_lookup_failed]
cross_account_guard: unchanged; ownerChangedSince(userId) guards every write of the push iteration as before
forbidden_patterns_checked:
  - { pattern: "now.subtract\\(const Duration\\(minutes: 5\\)\\)", absent: false }
proposed_fix: >-
  Step 1 of the text lookup is anchored to the instant the row's key encodes (coachTurnInstantFromKey): created_at from 5
  minutes before to 10 minutes after it, only rows with no client_key, up to 10 read, the one nearest to the instant wins
  (nearestRowToInstant), and a cloud id already stamped in this pass is excluded. A hit is stamped onto the local row and
  nothing is uploaded. Step 2 is the OLD query (now - 5 min), kept for a phone clock that disagrees with the server by
  more than the step-1 margin. An unparseable key skips step 1. Kill switch configBox['disable_coach_turn_time_window']
  skips step 1 only.
regression_test_planned:
  - test/sync/coach_late_link_test.dart
  - test/sync/coach_client_key_push_test.dart
  - test/contracts/sync_coach_cross_channel_dedup_test.dart
related_bugs:
  - d4a7c9  # OI-503: the shared turn key; this bug is the push half it left open
  - 2026-05-16-sync-coach-cross-channel-dedup  # the text lookup this fix re-anchors
recurrence: |
  Recurrence of the 2026-05-16 cross-channel dedup class (docs/diagnoses/2026-05-16-sync-coach-cross-channel-dedup.md): the
  push's dedup lookup was too narrow in TIME, so a row that already had a server twin uploaded a second one. The 05-16 fix
  added a text lookup over the last 5 minutes relative to NOW; this one anchors the window to the turn instead.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "sync_coach.dart: coachTurnInstantFromKey, nearestRowToInstant, _lookupCoachTurnWindowRow, step 1 before the old query, kill switch. 16 new tests (coach_late_link_test.dart) and 3 existing push tests re-anchored." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "The push tests write real coachBox rows and read the stamped id back; the restore reader is unchanged (coach_client_key_restore_test.dart still green)." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No migration; client_key (migration 178) and its partial index already exist and are read as they are." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live read-only 2026-11-13: the 07:00 turn has a server row (b5f81db2) and a keyed in_app_orphan uploaded at 12:31; the 12:11 turn has two keyed rows under one key (the Retry at 12:35). The two surplus rows are a data repair with its own founder go (plan section 6)." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Client-only fix; no Edge Function changed for this bug." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes the touched paths." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change; the new ai-proxy lookup runs with the service role and filters on user_id from the verified token." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage change." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret; DISABLE_CLIENT_KEY_REPLAY is an optional env kill switch, absent by default." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "The stub server in test/helpers/sync_stub_server.dart now implements is.null and a repeated created_at, so the filter semantics (client_key is null, gte, lte, order, limit) are the PostgREST ones; L6 pins the raw request." }
impact_analysis: >-
  A turn linked late now finds its server row and the upload is skipped; the cloud id is stamped. Turns whose server row
  is not within -5/+10 minutes of the key's instant, or whose phone clock is off by more than the margin, take step 2
  exactly as before, so nothing that matched before stops matching. The documented bound: an unkeyed server row matched
  this way still restores at coach_<server ms> as a sibling of the phone row (pinned by L10 so a change is deliberate).
---

# A coach turn linked hours late uploaded a second row (b7e1f3)

## Root cause
- Writer of the extra row: `SyncServiceCoach._syncCoachInteractions` (`lib/core/services/sync/sync_coach.dart`), the orphan
  upsert after its text lookup found nothing.
- The lookup window was `created_at >= now - 5 min`. It is a window on the SYNC time, not on the TURN's time, so a turn
  that is linked later than 5 minutes after it was sent can never match its own server row.
- Reader: the restore (`_applyKeyedCoachRows`) writes the keyed orphan at the phone key, so the thread shows the turn
  twice.

## Fix
See `proposed_fix`. Plan: `docs/plans/2026-11-13-coach-late-link-timeout-retry.md` section 4, fix 1 (rev 5, converged
after four independent review rounds).

## Tests
`test/sync/coach_late_link_test.dart`: L1 the 07:00 case (row 5.5 h old, no key: no upsert, id stamped), L1b clock skew
(step 2 only), L3 cross-channel row, L4 unparseable key, L5 kill switch, L6 raw request shape, L8 another key in the window,
L9 the same words next morning, L10 the documented restore bound, L11 two candidates (nearest wins), pure-helper cases.

## Mutation evidence (rule 21)
Applied by exact-string replacement with a count check, run under `TZ=Asia/Kolkata`, source restored in a `finally`.
Script `mut505a.py` (session scratchpad). 12 mutants, all red.

| id | mutation | result |
|---|---|---|
| M1 | step 1 skipped | RED |
| M2 | window anchored to now instead of the key | RED |
| M3 | `client_key is null` filter dropped | RED |
| M4 | first row instead of the nearest | RED |
| M5 | already-stamped ids not excluded | RED |
| M6 | upper bound 30 min | RED |
| M7 | no intra-pass stamp map | RED |
| M8 | kill switch ignored | RED |
| M9 | filter kept after a failed key lookup | RED |
| M10 | limit 1 | RED |
| M11 | lower bound 1 min | RED |
| M12 | upper bound removed | RED |
