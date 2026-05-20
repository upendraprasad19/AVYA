---
scope: core_services
parent: ../../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# Core Services — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/core/services/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

<!-- MIGRATION IN PROGRESS — content from CLAUDE.md will be moved here in Milestone 2 -->

## Single-source-of-truth contracts

(populated in Milestone 2)

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Hive box not open | Open ALL boxes in main.dart before runApp(). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Adapter not registered | Register ALL Hive adapters before openBox(). | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Hive file bloat over time | `HiveService` implements `WidgetsBindingObserver` and runs `box.compact()` on **8** mutation-heavy boxes (user / workout / nutrition / health / custom / coach / sync / notifications) every 7 days on `AppLifecycleState.paused`. Gated via `configBox['last_compact_at']`. Per-box + global telemetry via `ErrorTelemetry.recordNonFatal` (reasons `hive_service_maybe_compact_box` / `hive_service_maybe_compact`). User-scoped box switch is race-safe via `HiveUserSession._sessionLock` + `Hive.isBoxOpen()` guard. Verified GREEN by audit 2026-05-17 / OI-17. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Force-unwrap `!` on map keys or `.first` on possibly-empty lists | Null-safe the map read (`(m['k'] as num?)?.toDouble() ?? 0.0`) and always guard `.first` with `isNotEmpty`. Closed 2026-04-24 (PR-FIX-2) in macros maps (home_provider + nutrition_provider), `exercise_type.first` (3 files), `sentences.last`, `options.keys.first`, `diet_plan_screen` shuffle result, `todayDay!` in train_screen. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Hive `path_provider` MissingPluginException in unit tests | `HiveService.init()` calls `Hive.initFlutter()` which uses `getApplicationDocumentsDirectory` from path_provider — fails in pure unit tests with `MissingPluginException(No implementation found for method getApplicationDocumentsDirectory on channel plugins.flutter.io/path_provider)`. Fix in tests that need Hive boxes (e.g., `test/ai_coach/meals_today_snapshot_test.dart`): add `TestWidgetsFlutterBinding.ensureInitialized()` + mock the channel via `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('plugins.flutter.io/path_provider'), (call) async => tempDir.path)` BEFORE calling `Hive.init(tempDir.path)` and `HiveService.instance.init()`. Required pattern for any Hive-touching unit test. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

(populated in Milestone 6)
