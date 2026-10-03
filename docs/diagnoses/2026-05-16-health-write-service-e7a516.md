---
bug_id: e7a516
date: 2026-05-16
batch: audit-2026-05-16 (task E.7)
status: in_progress
symptom: |
  Two related health-domain defects rolled into one architectural fix:
  (1) F2-R2 — `BiometricNotifier.logSleep` wrote `sleep_log_<dateStr>`
  using device-local `now.year-now.month-now.day`. At IST 00:00-05:30 the
  device-local string was the prior UTC date, so the entry landed at the
  wrong Hive key and IST-anchored readers silently missed it until next
  sync. (2) F-A — Health domain (sleep / weight / measurements /
  water / urine / hydration) had no canonical write service, leaving 9
  UI-layer direct `healthBox.put` callsites scattered across 5 files.
  This was the same architectural asymmetry that produced every
  writer/reader drift bug in the Workout and Nutrition domains pre-Test
  #6 (7 instances tracked in `feedback_writer_reader_field_drift_recurring.md`).
concept: health_write_service
sot_registry_entry: hive_field_name_health_box
writers:
  - { file: lib/core/services/health_write_service.dart, method_or_widget: HealthWriteService.logSleep, line: 66 }
  - { file: lib/core/services/health_write_service.dart, method_or_widget: HealthWriteService.logWeight, line: 1 }
  - { file: lib/core/services/health_write_service.dart, method_or_widget: HealthWriteService.logMeasurement, line: 1 }
  - { file: lib/core/services/health_write_service.dart, method_or_widget: HealthWriteService.setWaterMl, line: 1 }
  - { file: lib/core/services/health_write_service.dart, method_or_widget: HealthWriteService.logUrine, line: 1 }
  - { file: lib/core/services/health_write_service.dart, method_or_widget: HealthWriteService.logHydration, line: 1 }
readers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: BiometricNotifier.logSleep, line: 502 }
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: ConversationalLogHandler._logMeasurement, line: 132 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: WaterIntakeNotifier.addWater, line: 395 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: UrineColorNotifier.select, line: 461 }
  - { file: lib/features/nutrition/providers/nutrition_provider.dart, method_or_widget: HydrationSaveNotifier.save, line: 490 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: WeightLogNotifier.logWeight, line: 772 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: OnboardingNotifier.completeOnboarding, line: 390 }
hive_key_prefix: "sleep_log_ / weight_ / measurement_ / water_ml_ / urine_color_ / hydration_"
hive_key_formula: "istDateStr(date) appended to canonical prefix"
sync_methods: [syncSleepNow, syncWeightNow, syncMeasurementsNow, syncNutritionData, pushSnapshot]
restore_methods: [_restoreWeightLogs, _restoreSleepLogs, _restoreMeasurements, _restoreWaterLogs]
cloud_table: sleep_logs, weight_logs, body_measurements, water_logs
cloud_columns: [date, duration_hrs, weight_kg, water_ml, urine_color]
contract_test_path: "test/contracts/health_write_service_writer_to_reader_test.dart"
ist_handling:
  - { file: lib/core/services/health_write_service.dart, line: 1, source: "istDateStr(date) called inside every public method before key construction" }
provider_invalidations: [biometricProvider, waterIntakeProvider, urineColorProvider, hydrationSaveProvider]
telemetry_op_types:
  success: []
  failure: [health_write_service_log_sleep, health_write_service_log_weight, health_write_service_log_measurement, health_write_service_set_water_ml, health_write_service_log_urine, health_write_service_log_hydration]
cross_account_guard: n/a — health box reads/writes already covered by HiveUserSession + GuardedBox per c4055a (audit-2026-05-12 / Test #15.3 Bug 5).
forbidden_patterns_checked: [direct_healthbox_put_for_sleep_log_key, direct_healthbox_put_for_weight_key, direct_healthbox_put_for_measurement_key, direct_healthbox_put_for_water_ml_key, direct_healthbox_put_for_urine_color_key, direct_healthbox_put_for_hydration_key, device_local_year_month_day_date_construction]
proposed_fix: |
  1. Add `HealthWriteService` (lib/core/services/health_write_service.dart)
     with 6 methods (logSleep / logWeight / logMeasurement / setWaterMl /
     logUrine / logHydration). Each uses `istDateStr(date)` for the Hive
     key, a per-(kind, date) `_acquireLock` mutex, stamps `date` + `source`
     + `updated_at_ms` per the field-name contract, single `healthBox.put`,
     fire-and-forget `SyncService.syncXxxNow()` + `pushSnapshot()`, and
     records non-fatal telemetry on exception.
  2. Extend `WriteSource` enum (lib/core/services/write_result.dart) with
     `manual` and `onboarding` values + matching `code` strings.
  3. Migrate 9 UI-layer direct writes:
       - BiometricNotifier.logSleep → HealthWriteService.logSleep (F2-R2 fix).
       - _logMeasurement (conversational) → HealthWriteService.logMeasurement.
       - WaterIntakeNotifier.addWater / decrement → setWaterMl.
       - UrineColorNotifier.select → logUrine.
       - HydrationSaveNotifier.save → logHydration.
       - WeightLogNotifier.logWeight → logWeight.
       - OnboardingNotifier weight-seed path → logWeight (source: onboarding).
  4. Keep ONE intentional direct write: the `sleep_logs` LIST-key append
     in `conversational_log_handler._logSleep`. The list is consumed by
     `SyncService.syncSleepNow` list-item path; routing through the
     service would convert append→overwrite semantics. Comment the
     callsite as `INTENTIONAL DIRECT WRITE` per the audit reframe.
  5. Fix two readers (WaterIntakeNotifier.build / UrineColorNotifier.build)
     that still used device-local date — they would silently mismatch
     the now-canonical IST writer at IST 00:00-05:30.
  6. Add `test/contracts/health_write_service_writer_to_reader_test.dart`
     pinning: service exists, all 6 methods present, every method calls
     `istDateStr(`, mutex + sync fan-out + telemetry plumbing in place,
     no UI-layer direct `healthBox.put` for the 6 owned key prefixes,
     `INTENTIONAL DIRECT WRITE` marker present on the sleep_logs list path,
     WriteSource enum carries `manual` + `onboarding`.
regression_test_planned:
  - { file: test/contracts/health_write_service_writer_to_reader_test.dart, line: 1 }
---

# HealthWriteService — audit-2026-05-16 task E.7

## Symptom

Two health-domain defects rolled into one architectural fix.

**F2-R2 (sleep_log IST drift).** `BiometricNotifier.logSleep` in
`lib/features/profile/providers/profile_provider.dart:497` wrote the Hive
key `sleep_log_<dateStr>` where `dateStr = ${now.year}-${now.month}-${now.day}`
— **device-local**, not IST. At IST 00:00–05:30 the device-local string
was the prior UTC date, so the entry landed under the wrong key and
IST-anchored readers (`SyncService.syncSleepNow` reads
`sleep_log_<istDate>` per-day; biometricProvider re-reads via the same
path) silently missed it. Same class as Test #12 / Task A-1
`formatDateKey` IST fix (CLAUDE.md §19).

**F-A (Health domain has no WriteService).** Workout and Nutrition
domains have canonical write services
(`WorkoutWriteService` / `NutritionWriteService`) that own every Hive
mutation, route the sync fan-out, and stamp the field-name contract.
Health domain did not — 9 direct `healthBox.put` callsites lived across
`profile_provider.dart`, `conversational_log_handler.dart`,
`nutrition_provider.dart`, `home_provider.dart`, and
`onboarding_provider.dart`. This is the same architectural asymmetry
that produced every writer/reader drift bug in Workout/Nutrition pre-Test
#6 (see `feedback_writer_reader_field_drift_recurring.md` — 7 instances
tracked).

## Root cause

Architectural — health domain was never gated. Every direct writer was
free to invent its own date formula, sync method, and metadata shape.
F2-R2 is the visible symptom of that freedom (the only writer for
`sleep_log_*` happened to use device-local date); F-A is the structural
condition that allowed the symptom and N more like it to exist.

## Fix shape

New file `lib/core/services/health_write_service.dart` exposes
`HealthWriteService.instance` with 6 methods mirroring
`NutritionWriteService`:

- `logSleep({date, hours, quality, source})`
- `logWeight({date, weightKg, source})`
- `logMeasurement({date, partName, valueCm, source})`
- `setWaterMl({date, totalMl, source})`
- `logUrine({date, color, source, colorIndex?})`
- `logHydration({date, totalMl, hydrationScore, source, urineColorIndex?})`

Per-method behaviour matches the Workout/Nutrition pattern:

1. Input validation.
2. `istDateStr(date)` for the Hive key (the F2-R2 fix is folded in here).
3. Per-`<istDate>::<kind>` mutex via `_acquireLock` (mirrors
   `WorkoutWriteService` so concurrent same-day same-kind taps merge).
4. Single `healthBox.put` stamping `date`, `source` (via `WriteSource.code`),
   `updated_at_ms`.
5. Fire-and-forget `SyncService.syncXxxNow()` + `pushSnapshot()` per
   CLAUDE.md §15.
6. Non-fatal `ErrorTelemetry.recordNonFatal` on exception.
7. Returns `WriteResult.ok(key)` / `WriteResult.fail(...)`.

`WriteSource` enum extended with `manual` + `onboarding`.

9 UI-layer callsites migrated; 2 reader sites (`WaterIntakeNotifier.build`
and `UrineColorNotifier.build`) also IST-anchored so they don't drift
against the now-canonical writer at IST 00:00–05:30. The conversational
`sleep_logs` LIST-key path is the only retained direct write, marked
`INTENTIONAL DIRECT WRITE` in source.

## Verification

- `flutter analyze` on the 7 affected files: 0 issues.
- `flutter test test/contracts/health_write_service_writer_to_reader_test.dart`
  passes (service-exists, 6 methods present, every method calls
  `istDateStr(`, mutex + sync fan-out + telemetry plumbing in place,
  no UI-layer direct `healthBox.put` for owned key prefixes,
  WriteSource enum carries `manual` + `onboarding`).
- `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-05-16-health-write-service.md`
  passes.

## Class lesson

When a domain lacks a canonical WriteService, every drift bug in that
domain is latent. The health domain has now joined Workout and Nutrition
in the SoT-gated tier; future audits should check this triplet symmetry
before declaring any data-mutation surface "covered." See
`feedback_source_of_truth_audit.md` for the writer/reader audit rule;
this fix is the 8th application of that lesson, and the first to close
an entire domain rather than a single concept.
