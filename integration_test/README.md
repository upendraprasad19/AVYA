# integration_test/

Data-layer integration tests. Run on the host (no device required) or on
a connected Android device.

## Why a separate folder

`test/` runs pure-Dart units (no Hive plugin, no Riverpod root). Tests
under `integration_test/` exercise the WriteService → Hive → reader chain
end-to-end against a real Hive box on disk. They use the same
`wws_test_setup.dart` helper as `test/workout_write_service/` to mock
`path_provider` and open a temp Hive directory per test.

## Run

```bash
# Data-layer flows (host, no device) — runs via test/ mirror so the
# `flutter test` command doesn't try to spawn an integration runner.
flutter test test/critical_flows/critical_flows_test.dart

# Device flows (full app boot, --flavor dev required)
flutter test --dart-define-from-file=.env integration_test/app_test.dart --flavor dev
flutter test --dart-define-from-file=.env integration_test/flows/ --flavor dev
```

### Why two locations for `critical_flows_test.dart`?

`integration_test/critical_flows_test.dart` is the canonical scaffold
checked into the repo for future device-based extensions (auth,
onboarding, full UI flows). Today it is purely data-layer
(WriteService → Hive → reader) and does NOT need a device. To keep it
runnable from a CI host without an emulator, an identical mirror lives
at `test/critical_flows/critical_flows_test.dart`. `flutter test`
auto-routes anything under `integration_test/` through the integration
runner (which requires a desktop or device target); the `test/` mirror
sidesteps that.

When extending: edit BOTH files in the same PR until we wire a device
runner. The `test/` mirror is picked up automatically by the full
`flutter test` suite — which runs at **pre-push** (≥account blast-radius)
and in CI, not at pre-commit. (This line previously said pre-commit ran the
full suite; that was already wrong — it ran only the `test/contracts/`
subset — and since 2026-08-11 / ADR-0018 pre-commit runs no tests at all.)

## Critical flows covered (data-layer, host-runnable)

| # | Flow                                  | Surface                              |
| - | ------------------------------------- | ------------------------------------ |
| 1 | log meal round trip                   | NutritionWriteService.logMeal        |
| 2 | log workout round trip                | WorkoutRepository.getExerciseLogsForDate |
| 3 | receipt renders per-set chip data     | WorkoutReceiptData.fromExerciseLogs  |

## Extending

1. **Add data-layer flow** — append a `test(...)` block in
   `critical_flows_test.dart` if your flow round-trips through a
   WriteService and a canonical reader. Use `setUp(wwsTestSetup)` so
   each test has a fresh Hive temp dir.
2. **Add device-only flow** — drop a new file under
   `integration_test/flows/<flow>_test.dart` and gate the run with
   `--flavor dev`. Document the entry in this README's table.
3. **Anchor on the SoT registry** — `docs/sot_registry.yaml` lists every
   single-source-of-truth concept. If your flow exercises a registered
   concept, reference its `regression_test` field in the test header
   comment. Drift between writer and reader is the most common cause
   of APK regressions (Tests #6 → #12).

## Troubleshooting

- `MissingPluginException(plugins.flutter.io/path_provider)` — your
  test isn't calling `wwsTestSetup` in `setUp`. Without it, `Hive.init`
  fails to resolve the temp dir. Always pair it with `wwsTestTeardown`.
- `HiveError: Box not found` — `HiveUserSession.openForUser` hasn't run.
  `wwsTestSetup` does this with a fixed test UUID; a custom setup must
  call it before any box access.
- Test passes locally but fails in CI — check that
  `flutter test integration_test/critical_flows_test.dart` is in the
  CI matrix; some configs only run `test/`.
