---
bug_id: 2026-05-16-telemetry-hardening
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.14
status: fixed
symptom: Telemetry framework had five compounding observability gaps surfaced by audit Agent 7 — no success-path emission on 5 low-usage sync methods (cannot distinguish "feature unused" from "silently failing"), no cron-execution telemetry (F10.5), no `_shared/cron_auth.ts` (F9.1 — Test #16 P1-D drift class), generic numbered op_types defeating triage (F10.3), and undetected HIGH_PRIORITY_OP_TYPES client/server drift (F10.4).
concept: ErrorTelemetry + sync success/failure signal + cron auth
sot_registry_entry: ErrorTelemetry
writers:
  - { file: lib/core/services/error_telemetry.dart, method: logEvent, line: 237 }
  - { file: lib/core/services/error_telemetry.dart, method: recordNonFatal, line: 165 }
  - { file: lib/core/services/sync/sync_nutrition.dart, method: _syncSavedMeals, line: 232 }
  - { file: lib/core/services/sync/sync_health.dart, method: _syncSleepLogs, line: 171 }
  - { file: lib/core/services/sync/sync_health.dart, method: _syncMeasurements, line: 139 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method: syncSavedDietPlan, line: 96 }
  - { file: lib/core/services/sync/sync_community.dart, method: _syncCustomItems, line: 103 }
readers:
  - { file: supabase/functions/log-client-error/index.ts, method: handler, line: 193 }
  - { file: lib/core/services/error_telemetry.dart, method: isHighPriorityOpType, line: 111 }
hive_key_prefix: N/A (telemetry emits over network only)
hive_key_formula: N/A
sync_methods:
  - { file: lib/core/services/sync/sync_nutrition.dart, method: _syncSavedMeals, line: 232 }
  - { file: lib/core/services/sync/sync_health.dart, method: _syncSleepLogs, line: 171 }
  - { file: lib/core/services/sync/sync_health.dart, method: _syncMeasurements, line: 139 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method: syncSavedDietPlan, line: 96 }
  - { file: lib/core/services/sync/sync_community.dart, method: _syncCustomItems, line: 103 }
restore_methods: N/A (no restore counterpart — these are write-only telemetry events)
cloud_table: client_errors
cloud_columns: user_id / error_code / error_message / op_type / retry_count / client_version / platform / created_at
contract_test_path: test/contracts/high_priority_op_types_parity_test.dart
ist_handling: N/A (server stamps created_at in UTC; event scheduling is per-call, not date-keyed)
provider_invalidations: N/A (telemetry is fire-and-forget, no UI state derived from it)
telemetry_op_types:
  - upsert_user_saved_meals_success
  - upsert_sleep_logs_success
  - upsert_body_measurements_success
  - upsert_saved_diet_plans_success
  - upsert_custom_items_success
cross_account_guard: N/A (server-side auth verifies JWT before insert; user_id derived from token)
forbidden_patterns_checked:
  - "reason: 'sync_service_catch_\\d+'"
  - "reason: 'sync_service_for_\\d+'"
  - "reason: 'sync_service_if(_\\d+)?'"
  - "token === SUPABASE_SERVICE_ROLE_KEY (inline env-equality in cron functions — replaced via _shared/cron_auth.ts in 2/9 functions)"
proposed_fix: Five sub-tasks — (A) success-path logEvent calls in 5 sync methods; (B) migration 068_cron_call_log.sql staged on disk; (C) _shared/cron_auth.ts JWT helper retrofitted into pr-detection + streak-guardian; (D) extend Gate 15 with generic-op_type ban + 63-entry grandfather baseline; (E) source-grep parity test for HIGH_PRIORITY_OP_TYPES across error_telemetry.dart and log-client-error/index.ts.
regression_test_planned: test/contracts/high_priority_op_types_parity_test.dart asserts client.set == server.set with named drift in the failure message; ≥17 entries on each side.
regression_test: test/contracts/high_priority_op_types_parity_test.dart
---

## Symptom

Audit 2026-05-16 Agent 7 surfaced five compounding telemetry / observability gaps:

1. **F-B — success-path emission missing on low-usage syncs.** Five sync methods (`_syncSavedMeals`, `_syncSleepLogs`, `_syncMeasurements`, `syncSavedDietPlan`, `_syncCustomItems`) emit telemetry only on FAILURE. When the audit queried `client_errors` for these op_types and found zero rows, we could not distinguish "feature is unused" from "method silently throws every call". Test #11 / Theme A surfaced exactly this class for restore-completeness — we were blind to broken syncs of features paying users assumed worked.
2. **F10.5 — no cron-execution telemetry.** `cron.job_run_details.status='succeeded'` means "pg_net dispatched POST", NOT "Edge Function responded 2xx". Test #16 / P1-D (Vault drift → Bearer null → 401 storm) was invisible from the cron telemetry surface for unknown hours/days.
3. **F9.1 — `_shared/cron_auth.ts` does not exist.** Every cron Edge Function inlines `token === SUPABASE_SERVICE_ROLE_KEY`, the brittle env-equality shape flagged as Test #16 P1-D root cause. Vault rotation → silent 401 storm.
4. **F10.3 — generic numbered op_types (`sync_service_catch_5`, `sync_service_for_25`, ...) defeat triage.** 89 `42P10` rows in `client_errors` last 30d tagged with these labels; the line number drifts and the label tells you nothing about which write actually failed.
5. **F10.4 — `HIGH_PRIORITY_OP_TYPES` client/server drift, no contract test.** A HIGH op_type that disagrees between client + server is a silent observability bug: server inserts past the rate limit while client drops it (or vice versa).

## Root cause

Telemetry framework was built in three rushed passes (audit 2026-05-11 H-42 retrofit, Test #15.1 Bug D, Test #16.1 Theme D) and never had a dedicated quality bar. Each pass added emission at SOME but not ALL failure paths, and zero passes added emission on SUCCESS paths. The cron-auth pattern was duplicated by copy-paste into 9+ Edge Functions during the 2026-05-11 C-4 retrofit before the shared helper was ever extracted — leaving every function carrying the same env-equality drift hazard.

Generic numbered op_types are a sub-class of the writer/reader drift family: they encode "Nth catch block in this file" instead of "what failed". The labels were generated mechanically by the H-42 retrofit script and never reviewed for semantic value.

## Fix

### 14.A — Success-path emission

Added `unawaited(ErrorTelemetry.logEvent('upsert_<table>_success', ...))` inside the successful upsert path of:

- `lib/core/services/sync/sync_nutrition.dart::_syncSavedMeals` → `upsert_user_saved_meals_success` (per item)
- `lib/core/services/sync/sync_health.dart::_syncSleepLogs` → `upsert_sleep_logs_success` (per item)
- `lib/core/services/sync/sync_health.dart::_syncMeasurements` → `upsert_body_measurements_success` (per item)
- `lib/core/services/sync/sync_restore_completeness.dart::syncSavedDietPlan` → `upsert_saved_diet_plans_success` (per call — one row per user)
- `lib/core/services/sync/sync_community.dart::_syncCustomItems` → `upsert_custom_items_success` once per batch with exercise + food counts (per-item success spam would dominate the budget on first restore of a heavy library)

All emissions are fire-and-forget LOW-priority — they share the 2000/day budget. The HIGH-priority bypass stays reserved for crashes / auth failures / SQL state codes.

### 14.B — Migration 068 `cron_call_log`

Stages on disk only (per E.14 batch rule — DDL gated by founder approval). Table captures per-invocation cron-function status (started / success / failed + http_status + request_id + error_summary). 7-day retention via `cleanup_cron_call_log()` function (cron registration deferred — founder wires post-dashboard-review). `backups/applied_migrations.json` bumped to include `"068"`.

### 14.C — `_shared/cron_auth.ts`

JWT signature + role-claim decode via `jose@v5.6.3`. Verifies against `SUPABASE_JWT_SECRET` and requires `role === 'service_role'`. `CRON_SECRET` opaque-token escape hatch preserved for rollback. Retrofitted into `pr-detection` and `streak-guardian` (two of the known 401-storm offenders) — both now call `if (!await isAuthorizedCronCall(req))` instead of inline env-equality. NOT DEPLOYED (per batch rule — live Edge Function deploys are gated).

### 14.D — Generic op_type ban (extension to Gate 15)

`scripts/check_generic_error_telemetry.dart` extended with a second scan that flags `reason:` / `opType:` literal values matching `_catch_\d+$` / `_for$` / `_for_\d+$` / `_if$` / `_if_\d+$`. Conservative migration: pre-existing 63 violations grandfathered through `backups/generic_op_type_baseline.txt`. New code must use semantic op_types. Gate passes cleanly post-edit.

### 14.E — `high_priority_op_types_parity_test.dart`

Parses both `lib/core/services/error_telemetry.dart::highPriorityOpTypes` and `supabase/functions/log-client-error/index.ts::HIGH_PRIORITY_OP_TYPES` via regex string extraction (the two lists can't import each other across runtimes). Asserts set equality. Audit reported 17/18 drift on `unique_violation`; client has since been updated and both sides now have 18 entries. Test pins parity at ≥17 entries.

## Verification

- `dart run scripts/check_generic_error_telemetry.dart` → `[Gate 15] PASS — no NEW violations. Tracked debt: 63 grandfathered generic op_types (E.14.D).`
- `flutter test test/contracts/high_priority_op_types_parity_test.dart` → 2/2 pass.
- `flutter analyze lib/core/services/sync/sync_nutrition.dart lib/core/services/sync/sync_health.dart lib/core/services/sync/sync_restore_completeness.dart lib/core/services/sync/sync_community.dart` → 0 new issues (2 pre-existing `use_null_aware_elements` infos, both predate this batch).
- `dart analyze scripts/check_generic_error_telemetry.dart` → No issues.

## Files changed

- `lib/core/services/sync/sync_nutrition.dart` — `_syncSavedMeals` success-emit
- `lib/core/services/sync/sync_health.dart` — `_syncSleepLogs` + `_syncMeasurements` success-emit
- `lib/core/services/sync/sync_restore_completeness.dart` — `syncSavedDietPlan` success-emit
- `lib/core/services/sync/sync_community.dart` — `_syncCustomItems` batch-level success-emit + per-table counters
- `scripts/check_generic_error_telemetry.dart` — E.14.D extension + baseline loader
- `backups/generic_op_type_baseline.txt` — NEW (63 grandfathered entries)
- `supabase/migrations/068_cron_call_log.sql` — NEW (staged on disk; not applied)
- `backups/applied_migrations.json` — `"068"` appended
- `supabase/functions/_shared/cron_auth.ts` — NEW JWT-verify helper
- `supabase/functions/pr-detection/index.ts` — retrofit to `isAuthorizedCronCall` (NOT deployed)
- `supabase/functions/streak-guardian/index.ts` — retrofit to `isAuthorizedCronCall` (NOT deployed)
- `test/contracts/high_priority_op_types_parity_test.dart` — NEW

## Out of scope / deferred

- Remaining 7 cron Edge Functions still inline env-equality (`clean-orphan-media`, `i-see-you-callout`, `plateau-alert`, `promote-community-item`, `protein-gap-alert`, `re-engagement`, `workout-window-closing`). Same retrofit pattern; deferred until founder approves deploy of the first two.
- Live application of migration 068 + cron registration for `cleanup_cron_call_log()` — gated.
- Renaming the 63 grandfathered op_types to semantic names — reduce over time per `backups/generic_op_type_baseline.txt` comment.
- Cron-function instrumentation to actually INSERT into `cron_call_log` — separate task (E.14.B ships only the table).

## Related

- CLAUDE.md §19 entries: APK Test #16 P1-D (`pr-detection` cron Vault drift), Test #16.1 Theme D (`log-client-error` silent-drop), Test #11 Theme A (restore-completeness sync).
- Audit findings: `docs/audit/2026-05-16/findings-agent-7.md` F-B, F9.1, F10.3, F10.4, F10.5.
- Phase E plan: `docs/audit/2026-05-16/phase-e-continuation.md` § E.14.
