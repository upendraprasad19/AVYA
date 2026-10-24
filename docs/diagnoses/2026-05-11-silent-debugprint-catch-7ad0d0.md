---
bug_id: 7ad0d0
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: `catch (e) { debugPrint(...); }` patterns across `lib/core/services/` + `lib/shared/repositories/` logged to the device console but emitted NO Crashlytics signal + NO `client_errors` row. Production users hit the bug, devs never saw it. Multiple instances over Test #12 series + this audit (Bug A, C-2, rank_service hot path) traced back to this silent-swallow class.
concept: silent_debugprint_catch
sot_registry_entry: error_telemetry_funnel
writers:
  - { file: lib/core/services/error_telemetry.dart, method_or_widget: recordNonFatal, line: 27 }
readers:
  - { file: lib/core/services/rank_service.dart, method_or_widget: evaluateAndPromote + getCurrentRank, line: 130 }
  - { file: lib/shared/repositories/plan_engine/progression_resolver.dart, method_or_widget: resolve, line: 76 }
hive_key_prefix: "n/a — telemetry guardrail"
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
  failure: [rank_service_evaluate_and_promote, rank_service_get_current_rank, progression_resolver_hive_read]
cross_account_guard: n/a
forbidden_patterns_checked: ["catch_e_debugPrint_only_no_telemetry"]
proposed_fix: Retrofit the 2 audit-prioritised hot paths (rank_service.evaluateAndPromote + getCurrentRank, fired from splash + every workout completion + cron evaluator; progression_resolver.resolve, fired from plan-generator). Add a contract test at test/contracts/no_silent_debugprint_in_services_test.dart that scans every file in scope for `catch (e) { ... debugPrint(...) ... }` without a sibling ErrorTelemetry.recordNonFatal / .logEvent / rethrow. The current 28 offenders in stable code paths are listed in `_grandfathered` as visible tech debt — new code can't add to that list (test fails immediately). Phase 8 cleanup retrofits the rest one file at a time.
regression_test_planned:
  - test/contracts/no_silent_debugprint_in_services_test.dart (2 cases — scoped scan with allowlist + rank_service no-regression)
---
# Audit H-42: silent debugPrint catch in services / repositories

## Bug

209 catch blocks across 25 files in `lib/core/services/` +
`lib/shared/repositories/`. Many follow the shape:

```dart
} catch (e) {
  debugPrint('[ServiceName.method] $e');
}
```

This logs to the device console but produces NO remote signal:

- **No Crashlytics non-fatal report.** Dashboard stays clean. Devs
  don't know the catch fired.
- **No `client_errors` row.** Server-side log audit can't correlate
  user reports with failures.
- **No retry / fallback.** Just swallow + move on.

Multiple known incidents trace back to this class:

- **Bug A (2026-04-26)** — orphan `public.users` row swallowed for
  48h because `_ensureLocalUser`'s catch only logged to debugPrint.
- **APK Test #12 / C-2** — `SubscriptionService.refreshFromSupabase`
  catches were silent; the founder reported "PRO pill stuck on GO
  PRO after payment" before we found the actual root cause.
- **rank_service.evaluateAndPromote** — splash + post-workout fire-
  and-forget; silent failure = rank promotions silently dropped in
  production.

## Cause

The pattern predates `ErrorTelemetry.recordNonFatal` being a routine
funnel. After that helper was introduced (APK Test #12.7), 2 services
(SyncService, NutritionWriteService) were partially retrofitted but
the broader codebase was left as-is.

## Fix

**Two retrofits** (the audit-prioritised hot paths):

1. `rank_service.dart` — both catches in `evaluateAndPromote` and
   `getCurrentRank` now call
   `ErrorTelemetry.recordNonFatal(e, st, reason: '...')` alongside
   the existing debugPrint. Reasons: `rank_service_evaluate_and_promote`,
   `rank_service_get_current_rank`.
2. `progression_resolver.dart` — silent failure here would mean the
   plan generator falls back to default starting weights silently.
   Retrofitted with `progression_resolver_hive_read`.

**Contract test** at
`test/contracts/no_silent_debugprint_in_services_test.dart` — 2 cases:

1. **Scoped scan.** Walks every file under `lib/core/services/` +
   `lib/shared/repositories/`. For each catch block, requires that
   if `debugPrint(...)` is present then `ErrorTelemetry.recordNonFatal`,
   `ErrorTelemetry.logEvent`, or `rethrow` must also be present in
   the same body. Files in the `_grandfathered` set (28 currently-
   tolerated offenders) are skipped.
2. **rank_service no-regression.** Specifically asserts
   `rank_service.dart` carries zero offenders — guards against the
   audit-prioritised hot path silently re-introducing the pattern.

`_grandfathered` is the visible tech-debt ledger. New code can't add
to it — the scoped-scan test fires the moment a file outside the list
adopts the pattern. Phase 8 cleanup retrofits one file at a time and
removes the entry.

This is NOT deferral — it's tracked technical debt with an active
guardrail. Compare with the WriteService bypass detector (T-12,
7ad0cc) for the same pattern.

Suite: 1562 pass / 0 fail / 2 skip.

## Related

- 7ad0cc (T-12 — WriteService bypass detector, same forcing-function pattern)
- APK Test #12.7 (introduced `ErrorTelemetry.recordNonFatal`)
- Bug A (2026-04-26 — 48-hour silent swallow of orphan `public.users`)
