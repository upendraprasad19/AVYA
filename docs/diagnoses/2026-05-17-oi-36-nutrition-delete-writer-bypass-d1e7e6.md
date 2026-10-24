---
bug_id: d1e7e6
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase B (P1 writer/reader)
status: shipped
symptom: |
  `DeleteNutritionLogNotifier.deleteFoodLog` wrote the `recent_deletes`
  audit log + called `box.delete(logId)` directly, bypassing
  `NutritionWriteService.deleteLog`. Same writer/reader drift class
  that's burned us in Tests #6 → #15.3 — 10th instance per
  `feedback_writer_reader_field_drift_recurring.md`.

  Sibling method `restoreFoodLog` already routed through the
  WriteService (closed in audit-2026-05-11 C-12). The asymmetry was
  the smoking gun.
concept: nutrition_delete_canonical_writer
sot_registry_entry: nutrition_read_service
writers:
  - { file: lib/core/services/nutrition_write_service.dart, method: deleteLog accepts writeAuditLog param, line: 274 }
  - { file: lib/core/services/nutrition_write_service.dart, method: recent_deletes audit moved inside service, line: 318 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method: deleteFoodLog delegates to service, line: 996 }
readers:
  - { file: test/contracts/nutrition_delete_routes_through_write_service_test.dart, method_or_widget: 3-case contract, line: 1 }
hive_key_prefix: "nlog_"
hive_key_formula: "computeLogKey(istDate, mealType, items)"
sync_methods: [_syncNutritionLogs]
restore_methods: [_restoreNutritionLogs]
cloud_table: nutrition_logs
cloud_columns:
  - id
  - user_id
  - date
  - meal_type
  - total_calories
  - total_protein
  - total_carbs
  - total_fat
  - total_fiber
contract_test_path: test/contracts/nutrition_delete_routes_through_write_service_test.dart
ist_handling:
  - { file: lib/core/utils/ist_date.dart, line: 1, fn: istDateStr }
provider_invalidations: [dailyNutritionProvider, weeklyNutritionProvider, nutritionSummaryProvider, recentFoodLogsProvider, macroTargetsProvider, aiInsightProvider, foodLogProvider]
telemetry_op_types:
  success: []
  failure: [nutrition_write_service_delete_log, nutrition_write_service_audit_log, nutrition_write_service_sync_skipped]
cross_account_guard: "nutritionBox is user-scoped via HiveUserSession"
forbidden_patterns_checked:
  - { pattern: "DeleteNutritionLogNotifier.deleteFoodLog calls box.delete directly", absent: true }
  - { pattern: "DeleteNutritionLogNotifier.deleteFoodLog writes recent_deletes directly", absent: true }
proposed_fix: |
  Extended `NutritionWriteService.deleteLog` signature to accept
  `writeAuditLog: bool = true` parameter. When true (default), the
  service writes the `recent_deletes` audit entry BEFORE the delete
  — moved verbatim from the provider's pre-fix code path. Only
  fires for food-meta-bearing rows (skipped for water logs, etc.)
  to keep the coach's correction history clean.

  `DeleteNutritionLogNotifier.deleteFoodLog` now delegates entirely:

  ```dart
  final result = await NutritionWriteService.instance.deleteLog(
    logKey: logId,
    allowUndo: false,
  );
  ```

  `allowUndo: false` because this entry point (food search sheet delete)
  doesn't surface an UNDO snackbar. The food-search-tile delete path
  that DOES want undo can pass `allowUndo: true` independently.

  Why missed by today's audit: writer/reader sweep in audit-2026-05-16
  E.7 covered Health domain (HealthWriteService 9 migrations) +
  F11-C11-2 covered Workout schedule mutations. Nutrition delete was
  visible but not scoped in.
regression_test_planned:
  - test/contracts/nutrition_delete_routes_through_write_service_test.dart
---

# Bug d1e7e6 — nutrition deleteFoodLog bypassed NutritionWriteService

closes-oi: OI-36

## Root cause

The canonical NutritionWriteService writer pattern (logMeal, editLog,
restoreFoodLog) had been established + audited for fan-out, mutex,
telemetry, provider invalidation. `deleteFoodLog` predated the pattern
and was never migrated. Its direct `box.delete` + `box.put('recent_deletes')`
worked but:

- Bypassed the mutex (concurrent edits could race).
- Wrote audit out-of-band from the canonical path (other delete entry
  points wouldn't get the audit).
- Manually fired sync + invalidation (drift risk if the WriteService
  later changed its fan-out).
- Wasn't covered by the writer/reader contract tests.

This is the 10th instance of writer/reader drift per
`feedback_writer_reader_field_drift_recurring.md`. Each instance
shipped after the AUDIT THAT SHOULD HAVE CAUGHT IT — the lens never
covered every domain comprehensively.

## Fix

Moved the `recent_deletes` audit write INTO `NutritionWriteService.deleteLog`,
guarded by a new `writeAuditLog: bool = true` parameter that defaults
to true. Only fires for rows with food metadata (food_name / name +
meal_type) so non-food nutritionBox keys (water logs, urine status,
hydration totals) don't pollute the coach's correction history.

The provider is now a thin wrapper:

```dart
Future<void> deleteFoodLog(String logId) async {
  final result = await NutritionWriteService.instance.deleteLog(
    logKey: logId,
    allowUndo: false,
  );
  if (!result.success) {
    debugPrint('[NutritionProvider] deleteFoodLog failed: ${result.errorMessage}');
  }
  ref.invalidate(weeklyNutritionProvider);
}
```

The `weeklyNutritionProvider` invalidation is the only thing the
WriteService doesn't own — mirrors the existing `restoreFoodLog`
wrapper pattern.

## Verification

```
$ flutter test test/contracts/nutrition_delete_routes_through_write_service_test.dart
All tests passed! (3 cases)
```

Tests pin: (1) deleteFoodLog calls NutritionWriteService.instance.deleteLog;
(2) deleteLog accepts writeAuditLog parameter; (3) recent_deletes
write lives inside the WriteService.

## Related

- audit-2026-05-11 C-12 — restoreFoodLog migration (sibling pattern)
- audit-2026-05-16 E.7 — Health domain writer/reader sweep
- `feedback_writer_reader_field_drift_recurring.md` — recurring class
- `docs/audit/LENS_REGISTRY.md` — L1 writer/reader drift
- `docs/sot_registry.yaml` — nutrition_read_service entry (paired writer side now complete)
