---
bug_id: 5beed5
date: 2026-05-16
batch: audit-2026-05-16 reader-side / F2-R3 (Phase B agent finding)
status: fixed
symptom: |
  AI coach reported "your sleep data isn't logged" despite the user
  having reported sleep through the same coach minutes earlier. The
  chat turn succeeded (assistant bubble responded with confirmation),
  but canonical readers (`profile_provider.dailySleepProvider`,
  `ai_coach_repository._countSleepLogsLast7Days`, AI snapshot's
  `sleep_logs_count_7d` field) never saw the entry.
concept: sleep_logs
sot_registry_entry: sleep_logs
writers:
  - { file: lib/core/services/health_write_service.dart, method: logSleep, line: 66 }
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method: _logSleep, line: 100 }
readers:
  - { file: lib/features/profile/providers/profile_provider.dart, method: dailySleepProvider, line: 440 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, method: _countSleepLogsLast7Days, line: 1388 }
  - { file: lib/core/services/sync/sync_health.dart, method: syncSleepNow, line: 46 }
hive_key_prefix: "sleep_log_"
hive_key_formula: "'sleep_log_${istDateStr(date)}'"
sync_methods: [syncSleepNow]
restore_methods: [_restoreSleepLogs]
cloud_table: sleep_logs
cloud_columns: [user_id, date, duration_hrs, quality, source]
contract_test_path: test/contracts/sleep_chat_routes_through_health_write_service_test.dart
ist_handling:
  - { file: lib/core/services/health_write_service.dart, line: 75, fn: istDateStr }
provider_invalidations: [dailySleepProvider]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "healthBox user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "healthBox.put('sleep_logs'", absent: true }
  - { pattern: "healthBox.put('sleep_log_", absent_outside_canonical: true }
proposed_fix: |
  `conversational_log_handler._logSleep` now routes through
  `HealthWriteService.instance.logSleep` — same canonical writer as
  the manual UI path. The canonical writer emits
  `sleep_log_<istDateStr>` (per-day overwrite semantics, matching
  user intent — one sleep value per night) and fires
  `syncSleepNow + pushSnapshot` from inside the WriteService per the
  audit-2026-05-16 E.7 health-domain pattern (mirroring
  `_logMeasurement` which was already routed through the service in
  that batch).
  The legacy `sleep_logs` LIST key is no longer written from any
  client path. `sync_health.syncSleepNow`'s list-read path stays
  for back-compat with pre-fix on-device data; it can be retired
  in a follow-up cleanup after devices upgrade past +28.
  Multiple chat mentions in one IST day collapse to the last value
  (per-day overwrite) — matches the natural sleep-tracking model.
regression_test_planned:
  - test/contracts/sleep_chat_routes_through_health_write_service_test.dart
---
# Body

## Symptom

User said in AI coach chat: "I slept 7 hours". Assistant responded:
"Logged. 7 hours noted." Two minutes later, user asked: "what was my
sleep last night?" Assistant responded: "your sleep data isn't logged".

The first turn succeeded — `ConversationalLogHandler._logSleep` was
called, returned `true`, the assistant bubble confirmed. But the data
went into a key that none of the canonical readers consult.

## Root cause

Dual-key writer asymmetry:

| Writer | Hive key written |
|---|---|
| Manual UI (Profile -> Sleep) -> `HealthWriteService.logSleep` | `sleep_log_<istDate>` (per-day overwrite) |
| AI chat (`ConversationalLogHandler._logSleep`) | `sleep_logs` LIST (append) |

All readers post-2026-05-16 audit (E.7 HealthWriteService canonicalisation)
key off the per-day key. The chat path bypassed `HealthWriteService`
entirely with a direct `healthBox.put('sleep_logs', logs)` call.

The pre-fix comment in `_logSleep` claimed the asymmetry was
"INTENTIONAL DIRECT WRITE" to preserve append semantics for chat
history. But the user-facing consequence was a silent reader miss —
all the readers that matter (dailySleepProvider, AI snapshot,
weekly report sleep series) saw nothing.

This was finding F2-R3 from Phase B agent inventory. I initially
flagged it as "lower severity than 6 user-visible bugs" and deferred.
Founder pushback ("why are these open?") reclassified it as
in-scope per `feedback_no_deferrals_recurrence.md` (5th instance of
the deferral pattern).

## Fix

See `proposed_fix` in frontmatter. Chat handler delegates to the
canonical writer — mirrors the `_logMeasurement` pattern established
in audit E.7. The legacy list path becomes effectively dead code
client-side; sync's list-read remains for on-device back-compat
with pre-fix data.

## Regression test

`test/contracts/sleep_chat_routes_through_health_write_service_test.dart`:
3 source-grep contract tests:
- `_logSleep` delegates to `HealthWriteService.instance.logSleep`
- No direct `healthBox.put('sleep_logs', ...)` in the chat path
- No direct `healthBox.put('sleep_log_<...>', ...)` either
