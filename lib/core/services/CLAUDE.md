---
scope: core_services
parent: ../../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Core Services — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/core/services/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## What lives here

`lib/core/services/` is the **service layer between widgets and storage**. Every
write to Hive that participates in cloud sync goes through a *WriteService*
class (`WorkoutWriteService`, `NutritionWriteService`, `HealthWriteService`,
`ProfileWriteService`, `WaterTargetService`, etc.). Every read with a public
domain contract goes through a *ReadService* (`WorkoutReadService`,
`NutritionReadService`, `HealthReadService`). Widgets and Riverpod providers
**must never call `Hive.box(...)` directly** — the WriteService wires
provider invalidation + sync fan-out + telemetry as one atomic unit.

Also in this directory:

- `sync_service.dart` + `sync/sync_*.dart` — orchestrator + per-domain sync extensions.
- `hive_service.dart` — boot, lifecycle compaction, user-session swap.
- `hive_user_session.dart` — cross-account ownership lock (`auth_hive_owner_agreement`).
- `auth_session_bootstrapper.dart` — post-auth decision tree owner.
- `subscription_service.dart` — `isPro()` + `gate()` + server verify with cache.
- `error_telemetry.dart` — `recordNonFatal` (the helper every catch block must use).
- `usage_counter_service.dart` — increment-at-API-call counters (post Test #11).
- Migrators: `exlog_key_migrator.dart`, `nlog_key_migrator.dart`, `hive_field_rename_migrator.dart`, `user_config_migrator.dart`, etc.

## Single-source-of-truth contracts

Every WriteService here is the canonical writer for at least one SoT-registry
concept. Selected mappings (full list in `docs/sot_registry.yaml`):

| Concept | Writer (this dir) | Reader entry point |
|---|---|---|
| `exercise_logs_read_path` / `workout_receipt_rendering` | `workout_write_service.dart` `logExercise` | `workout_read_service.dart` `exerciseLogsForIstDate` |
| `nutrition_total_calories` / `food_log_delete_with_undo` | `nutrition_write_service.dart` `logMeal` / `deleteWithUndo` | `nutrition_read_service.dart` |
| `health_write_service` | `health_write_service.dart` (6 methods — water / weight / sleep / steps / mood / energy) | `health_read_service.dart` |
| `subscription_state` / `subscription_payment_grace_window` | `subscription_service.dart` `setPro` + Razorpay webhook handlers | `subscriptionInfoProvider`, `gate()` |
| `water_target` | `water_target_service.dart` | `waterTargetProvider` |
| `error_telemetry_helper` | `error_telemetry.dart` `recordNonFatal` | every catch block app-wide |
| `sync_fanout_workout_domain` / `sync_fanout_nutrition_domain` | `sync/sync_workout.dart` / `sync/sync_nutrition.dart` | callers fire `unawaited(syncWorkoutData())` after a mutation |
| `restore_completeness` | `sync_service.dart` `restoreFromCloud` | `restoring_screen.dart` |
| `user_scoped_hive_keys` / `hive_deletion_and_session_helpers` | `hive_user_session.dart` + `hive_service.dart` | `wrapUserScopedBox` (helper used everywhere) |
| `auth_hive_owner_agreement` | `hive_user_session.dart` + `wrapUserScopedBox` | every WriteService + every Hive-touching Riverpod provider |
| `day_rollover_provider_invalidation` | `day_rollover_service.dart` | `splash_screen` + `home_screen` mount |
| `singleton_lifecycle_registry` | `singleton_lifecycle_registry.dart` | hot-restart cleanup |

The WriteService pattern enforces three steps every write:

1. **Write to Hive first** (via `wrapUserScopedBox`).
2. **Invalidate the registered provider set** (see `provider_invalidation_set` in `docs/sot_registry.yaml`).
3. **Fire-and-forget `unawaited(syncDomain())`** — never block the UI on cloud.

Failures from step 3 are captured by `ErrorTelemetry.recordNonFatal` with an
`op_type` from `op_types_canonical.dart`; the catch block never bubbles up to
the user. Every WriteService method returns a `WriteResult` so the caller can
distinguish "Hive succeeded" from "cloud succeeded".

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Hive box not open | Open ALL boxes in main.dart before runApp(). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Adapter not registered | Register ALL Hive adapters before openBox(). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Hive file bloat over time | `HiveService` implements `WidgetsBindingObserver` and runs `box.compact()` on **8** mutation-heavy boxes (user / workout / nutrition / health / custom / coach / sync / notifications) every 7 days on `AppLifecycleState.paused`. Gated via `configBox['last_compact_at']`. Per-box + global telemetry via `ErrorTelemetry.recordNonFatal` (reasons `hive_service_maybe_compact_box` / `hive_service_maybe_compact`). User-scoped box switch is race-safe via `HiveUserSession._sessionLock` + `Hive.isBoxOpen()` guard. Verified GREEN by audit 2026-05-17 / OI-17. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Force-unwrap `!` on map keys or `.first` on possibly-empty lists | Null-safe the map read (`(m['k'] as num?)?.toDouble() ?? 0.0`) and always guard `.first` with `isNotEmpty`. Closed 2026-04-24 (PR-FIX-2) in macros maps (home_provider + nutrition_provider), `exercise_type.first` (3 files), `sentences.last`, `options.keys.first`, `diet_plan_screen` shuffle result, `todayDay!` in train_screen. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Hive `path_provider` MissingPluginException in unit tests | `HiveService.init()` calls `Hive.initFlutter()` which uses `getApplicationDocumentsDirectory` from path_provider — fails in pure unit tests with `MissingPluginException(No implementation found for method getApplicationDocumentsDirectory on channel plugins.flutter.io/path_provider)`. Fix in tests that need Hive boxes (e.g., `test/ai_coach/meals_today_snapshot_test.dart`): add `TestWidgetsFlutterBinding.ensureInitialized()` + mock the channel via `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('plugins.flutter.io/path_provider'), (call) async => tempDir.path)` BEFORE calling `Hive.init(tempDir.path)` and `HiveService.instance.init()`. Required pattern for any Hive-touching unit test. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Increment a usage counter at save time | Counters MUST increment at the API-call site, not at the save site. Pre-Test-#11 free-tier users saw "50 remaining" while the Postgres trigger had counted every Edge Function call. Counter callsites: `food_logger_section._analyse`, `ScanMealNotifier.scanImage`, `cart_auditor_section.analyseCart`, `tool_dispatcher._executeLogMealByText`. | (relocated 2026-05-18 — see `lib/features/nutrition/CLAUDE.md`) |
| Restore writer keyed differently from production writer | Test #12.8 root cause — 6 of 16 `_restoreXxx` methods used legacy keys. Always test restore→read round-trip in `test/contracts/restore_completeness_test.dart`. | `feedback_writer_reader_field_drift_recurring.md` |

## Tests pinning the rules here

- `test/contracts/auth_hive_owner_agreement_behavioral_test.dart` — Layer A+B cross-account guard.
- `test/contracts/restore_completeness_test.dart` — every `_restoreXxx` round-trips.
- `test/contracts/sync_fanout_workout_domain_writer_to_reader_test.dart` (+ nutrition).
- `test/contracts/error_telemetry_helper_writer_to_reader_test.dart`.
- `test/contracts/health_write_service_writer_to_reader_test.dart`.
- `test/contracts/workout_write_service_*_test.dart` (multiple — exercise log, schedule, templates).
- `test/contracts/nutrition_write_service_*_test.dart`.
- `test/contracts/subscription_state_*_test.dart`.

## See also

- `lib/CLAUDE.md` — cross-feature rules.
- `docs/architecture/sync.md` — sync schedule + restore-completeness + Hive field-name contracts.
- `docs/sot_registry.yaml` — full SoT registry.
