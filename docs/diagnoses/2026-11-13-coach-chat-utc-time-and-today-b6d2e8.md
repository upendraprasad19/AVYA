---
bug_id: b6d2e8
date: 2026-11-13
batch: coach-chat-time-dup (OI-502, Fixes A, B and D)
status: fixed
blast_radius: platform
symptom: >-
  The founder sent a coach question at 07:00 IST on 2026-11-13; the chat bubble showed 01:30, the UTC hour. Every coach
  chat row's created_at has been stored in UTC with Z since 2026-09-27 (commit 80557539, diagnose a2b1c7), but the bubble
  formatted DateTime.parse(created_at).hour without .toLocal(). The same change silently broke two "today" checks that
  test created_at.startsWith(<IST date>): getTodayUserMessageCount and extractAndAppendCoachingNotes. A turn sent between
  00:00 and 05:30 IST carries the previous UTC date, so it was not counted as today's and its coaching notes were not
  extracted. A third reader, the Home "💡" coach tip, quoted the last coach reply; measured on live data it produced no
  useful tip in 60 days, and the founder removed it (2026-11-13) instead of fixing its date check.
concept: coach_interactions
sot_registry_entry: coach_interactions (readers chat bubble time, getTodayUserMessageCount, extractAndAppendCoachingNotes; the AiInsightNotifier._getLatestCoachTip reader entry is removed)
writers:
  - file: lib/features/ai_coach/repositories/coach_interaction_repository.dart
    method: saveInteraction / saveUserMessagePending (created_at DateTime.now().toUtc().toIso8601String(), unchanged)
    line: 53
  - file: lib/core/services/sync/sync_coach.dart
    method: _restoreCoachInteractions (writes the cloud created_at, +00:00 form, unchanged)
    line: 302
readers:
  - file: lib/features/ai_coach/screens/ai_coach/chat_area.dart
    method_or_widget: message bubble time label (now chatClockLabel(message.timestamp))
    line: 72
  - file: lib/features/ai_coach/repositories/coach_interaction_repository.dart
    method_or_widget: getTodayUserMessageCount (now isIsoOnIstDay)
    line: 289
  - file: lib/features/ai_coach/services/coach_memory_service.dart
    method_or_widget: extractAndAppendCoachingNotes (now isIsoOnIstDay)
    line: 90
  - file: lib/features/home/providers/home_provider.dart
    method_or_widget: AiInsightNotifier.build (the coach tip append is removed; the insight is the schedule sentence only)
    line: 695
hive_key_prefix: coach_
hive_key_formula: "coachBox['coach_<ms>'] = {user_message, ai_response, mode, created_at (UTC with Z; +00:00 after a restore), ...}"
sync_methods:
  - none changed (the push in _syncCoachInteractions reads created_at only for its 5-minute text lookup, which compares instants)
restore_methods:
  - none changed in this fix (the restore keeps writing the cloud created_at)
cloud_table: ai_coach_interactions
cloud_columns: [created_at]
contract_test_path: test/contracts/coach_chat_time_today_tip_test.dart
ist_handling:
  - isIsoOnIstDay parses the stored instant and compares istDateStr(instant) with the IST day, so 00:00-05:30 IST turns land on the right day
  - chatClockLabel shows the device's clock (toLocal), matching every other time the app shows; a zone-less legacy string parses as local and keeps its own clock
  - the test file passes under TZ=Asia/Kolkata, TZ=UTC and TZ=Asia/Tokyo, with a per-offset expectation map for the label
provider_invalidations:
  - none (aiInsightProvider already derives from todayWorkoutProvider; removing the tip removes its coachBox read)
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a (coachBox is user-scoped; no new reads or writes)
forbidden_patterns_checked:
  - { pattern: "created_at.*startsWith\\(todayStr\\)", absent: true }
  - { pattern: "message\\.timestamp\\.hour", absent: true }
  - { pattern: "_getLatestCoachTip", absent: true }
proposed_fix: >-
  Fix A: a chatClockLabel(DateTime) helper in date_utils.dart formats t.toLocal() as HH:mm; chat_area.dart uses it. Fix
  B: an isIsoOnIstDay(String?, String istDay) helper in ist_date.dart parses the stamp and compares its IST date; the
  daily count and the coaching-notes loop use it instead of startsWith. Fix D (founder decision): delete
  _getLatestCoachTip and the 💡 append; AiInsightNotifier.build returns the schedule insight alone.
regression_test_planned:
  - test/contracts/coach_chat_time_today_tip_test.dart
related_bugs:
  - a2b1c7  # 80557539 moved the coach row created_at to UTC (Z) and did not sweep the readers that format or date-test it
  - f3d704  # the completion tile: a local stamp sorted against UTC chat rows; the same representation-mismatch class
  - c2b7e4  # progress photos taken_at: local vs UTC compare
  - 5970aa  # OI-479 clear conversation: its behavioral test listed the Home tip as an unchanged reader (now removed)
recurrence: |
  Recurrence of the f3d704 / c2b7e4 class: a time value whose REPRESENTATION changed (local to UTC) while a reader kept
  treating the string as local wall-clock text. Here the writer changed (a2b1c7, 2026-09-27) and three readers were not
  swept. Known-good fix applied: compare and format INSTANTS (parse, then toLocal / istDateStr), never the string. Sweep
  done for this batch: grep of created_at reads in lib/features/ai_coach, lib/core/services/sync/sync_coach.dart and
  lib/features/home found these three plus the tip; ChatHistoryNotifier.build already compares parsed instants for the
  clear marker (5970aa) and sorts strings of one representation (UTC), which orders correctly.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "chat_area.dart via chatClockLabel; getTodayUserMessageCount and extractAndAppendCoachingNotes via isIsoOnIstDay; home_provider.dart tip removed. 12 tests in coach_chat_time_today_tip_test.dart green under Kolkata, UTC and Tokyo." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Tests write real coachBox rows at 00:30, 06:00 IST today and 23:30 IST yesterday and read the count back (2); a coachBox reply that fit the old tip rule no longer reaches the Home insight." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change for this fix (migration 178 belongs to OI-503's fix)." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live ai_coach_interactions.created_at is timestamptz; the founder's 07:00 IST row reads 2026-11-13 01:30:50+00, confirming the stored UTC instant." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration for this fix." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads these client fields." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy." }
  - { tier: 9, name: storage_buckets_and_objects, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_and_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "Display and local counting only; no request or response shape changes." }
impact_analysis: >-
  Bubbles show the device's clock. The daily coach count now includes 00:00-05:30 IST turns; it is a local display and
  first-message signal, while the server-side cap (consume_quota) is unchanged, so no user gains or loses messages. The
  coaching-notes extraction now sees early-morning turns. The Home insight loses the 💡 line it showed after a coach
  reply; the schedule sentence is unchanged byte for byte (ai_insight_follows_today_row_test.dart).
---

# Coach chat times shown in UTC; "today" checks miss 00:00-05:30 IST (b6d2e8)

## Root cause
Commit 80557539 (diagnose a2b1c7, 2026-09-27) made `saveInteraction` and `saveUserMessagePending` stamp
`DateTime.now().toUtc().toIso8601String()`. Three readers kept treating that string as local time:
- the bubble printed `message.timestamp.hour` / `.minute`, the UTC fields of a `Z` instant;
- `getTodayUserMessageCount` and `extractAndAppendCoachingNotes` tested `created_at.startsWith(todayStr)`, where
  `todayStr` is the IST date and the stamp's date is UTC.

## Fix
- `chatClockLabel` (date_utils.dart): `toLocal()`, then `HH:mm`.
- `isIsoOnIstDay` (ist_date.dart): parse, `istDateStr(instant) == istDay`; null, empty and unparseable are on no day.
- Home coach tip removed (founder decision 2026-11-13).

## Tests
`test/contracts/coach_chat_time_today_tip_test.dart` (12 tests): label per host offset, `Z` vs `+00:00`, a zone-less
legacy string, the chat_area wiring pin; `isIsoOnIstDay` boundaries (00:30 IST, 23:30 IST, the 18:30 UTC midnight edge,
null/empty/garbage, legacy local); the coaching-notes wiring pin; the Hive-backed daily count (2 of 3); the Home insight
carries no 💡 and no tip text. `coach_chat_clear_behavioral_test.dart` T4 no longer lists the removed tip.

## Mutation evidence (rule 21)
Each mutant applied by exact-string replacement with a count check, the file run, then restored and checked by sha256.

| id | edit | result |
|---|---|---|
| MA | `chatClockLabel` drops `.toLocal()` | RED (label per offset, off-UTC hosts) |
| MB1 | `isIsoOnIstDay` becomes `iso.startsWith(istDay)` | RED (00:30 IST, midnight edge) |
| MB2 | the daily count goes back to `startsWith(todayStr)` | RED (Hive count 1, expected 2) |
| MB3 | the coaching-notes loop goes back to `startsWith(todayStr)` | RED (wiring pin) |
| MD | the tip and its 💡 append restored | RED (Home insight test) |

Survivors: none.
