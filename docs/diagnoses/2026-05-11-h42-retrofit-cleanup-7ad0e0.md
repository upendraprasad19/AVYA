---
bug_id: 7ad0e0
date: 2026-05-11
batch: audit-2026-05-11-cleanup
status: shipped
symptom: Phase 8 cleanup deferred the remaining 21 grandfathered `catch (e) { debugPrint(...) }` patterns in `lib/core/services/` + `lib/shared/repositories/` to a follow-up batch. Per audit doc §4 H-42 finding + the audit's "no deferrals" discipline rule, this batch retrofits ALL remaining grandfathered files — 20 services + 4 repositories. Each catch now pairs the existing `debugPrint(...)` with `unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: '<op_type>'))` so production silent failures surface in Crashlytics + the `client_errors` table.
concept: error_telemetry_funnel_completion
sot_registry_entry: error_telemetry_funnel
writers:
  - { file: lib/core/services/ai_service.dart, method_or_widget: 8 catches retrofitted, line: 1 }
  - { file: lib/core/services/app_events_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/barcode_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/exlog_key_migrator.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/guarded_box.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/hive_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/logging_type_repair_migrator.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/migrated_key.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/nlog_key_migrator.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/nutrition_write_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/prediction_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/scheduled_workouts_resync_migrator.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/seed_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/supabase_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/sync_queue.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/sync_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/user_config_migrator.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/workout_schedule_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/core/services/workout_write_service.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/shared/repositories/exercise_repository.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/shared/repositories/food_repository.dart, method_or_widget: catches retrofitted, line: 1 }
  - { file: lib/shared/repositories/submissions_repository.dart, method_or_widget: catches retrofitted, line: 1 }
readers: []
hive_key_prefix: "n/a"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: client_errors
cloud_columns: [error_code, error_message, op_type, retry_count, client_version, platform]
contract_test_path: test/contracts/no_silent_debugprint_in_services_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: ["<service>_<method>" format — each retrofit site gets a unique op_type derived from the file + method name so the Crashlytics non-fatal dashboard groups failures by exact call site]
cross_account_guard: n/a
forbidden_patterns_checked: ["silent_debugPrint_catch_in_services"]
proposed_fix: For every grandfathered file, add `import 'dart:async';` + `import '<path>/error_telemetry.dart';` if absent. For each catch block where `debugPrint(...)` appears without `ErrorTelemetry.recordNonFatal`/`logEvent`/`rethrow`, convert `catch (e)` to `catch (e, st)` if needed and append `unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: '<service>_<method>'));` after the debugPrint. Each site's `reason` is unique + descriptive. Update `test/contracts/no_silent_debugprint_in_services_test.dart` to remove all 24 retrofitted files from `_grandfathered`.
regression_test_planned:
  - test/contracts/no_silent_debugprint_in_services_test.dart (grandfathered set shrunk from 21 → 0; all `lib/core/services/*` + `lib/shared/repositories/*` now scan clean)
---
# H-42 retrofit — closing the grandfathered allowlist

## Context

Phase 8 cleanup (7ad0da) retrofitted 4 hot-path services
(`health_sync_service`, `razorpay_service`, `stat_snapshot_service`,
`subscription_service`) and shrunk the allowlist from 28 → 21 files.
The remaining 21 entries were explicitly deferred per Phase 8 §"What's
deferred to a future batch", with the discipline directive that
deferred items MUST ship in the next named batch (not "someday").

This is that batch. **Allowlist shrinks from 21 → 0.**

## Why each catch matters

Every `catch (e) { debugPrint(...) }` without telemetry is a hole in
the error funnel. The user hits a bug, the device prints to logcat,
the dev never sees the failure. Past audits (Test #12.6, APK Test #11)
each found ≥2 prod bugs that had been silently swallowed for weeks at
sites flagged by this pattern.

## Retrofit pattern (mechanical)

```dart
// BEFORE
} catch (e) {
  debugPrint('[SomeService.someOp] $e');
}

// AFTER
} catch (e, st) {
  debugPrint('[SomeService.someOp] $e');
  unawaited(ErrorTelemetry.recordNonFatal(e, st,
      reason: 'some_service_some_op'));
}
```

Imports added if absent:
```dart
import 'dart:async';                  // for unawaited()
import 'error_telemetry.dart';        // relative or package: path
```

The `reason` string format is `<file_basename_without_dart>_<method>`
in lower_snake_case. Examples:
- `ai_service.dart::sendMessage` → `ai_service_send_message`
- `sync_service.dart::syncWorkoutData` → `sync_service_sync_workout_data`
- `user_repository.dart::updateProfile` → `user_repository_update_profile`

This convention lets the Crashlytics non-fatal dashboard group by exact
call site. Each `reason` is unique within the codebase.

## Cohort breakdown (commit cadence)

Retrofitted in 6 cohorts (1 commit each) to keep diffs reviewable.
Each cohort cites this diagnose via `closes-diagnose: 7ad0e0`.

| Cohort | Files | Rationale |
|--------|-------|-----------|
| 1. Migrators | exlog_key_migrator, logging_type_repair_migrator, migrated_key, nlog_key_migrator, scheduled_workouts_resync_migrator, user_config_migrator | All fire once at session-bootstrap; silent failures = drifting Hive state on cold launch |
| 2. Write services + queue | nutrition_write_service, workout_write_service, sync_queue | Mutation hot path |
| 3. Hive infrastructure | guarded_box, hive_service, hive_user_session, seed_service | Cold-start critical path |
| 4. AI / ML | ai_service, prediction_service, barcode_service | Gemini + Edge Function callers |
| 5. Sync + Supabase + schedule | sync_service, supabase_service, workout_schedule_service, app_events_service | Cross-domain syncers |
| 6. Repositories | user_repository, exercise_repository, food_repository, submissions_repository | Data access layer |

## Verification

After each cohort:
1. `flutter analyze` — clean
2. `flutter test test/contracts/no_silent_debugprint_in_services_test.dart` — passes (cohort's files no longer in `_grandfathered`)
3. Full suite at end-of-batch: 1598 pass / 0 fail / 2 skip target

## Related

- 7ad0da (Phase 8 cleanup — first 4 retrofits)
- 7ad0c1..7ad0d9 (Phases 1-7 of audit-2026-05-11)
- CLAUDE.md rule 23 (no stopping mid-batch) — codified after Phase 8
