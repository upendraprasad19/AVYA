// audit-2026-05-16 task E.7 — contract test for HealthWriteService.
//
// This is a source-grep test (CLAUDE.md rule 21 "Regression test required
// for every fix") that pins the writer/reader SoT contract for the
// health domain:
//
//   1. `lib/core/services/health_write_service.dart` exists with the 6
//      canonical methods (logSleep / logWeight / logMeasurement /
//      setWaterMl / logUrine / logHydration).
//   2. Every method computes its Hive date key via `istDateStr(` — closes
//      audit-2026-05-16 finding F2-R2 (sleep_log device-local date drift).
//   3. The service uses a per-(kind, date) mutex (`_acquireLock(`) and
//      fires fire-and-forget sync via `SyncService.instance.`.
//   4. The 8 UI-layer migration sites no longer contain direct
//      `healthBox.put('<key prefix>...')` for the keys the service owns.
//   5. The list-key `sleep_logs` path in `conversational_log_handler.dart`
//      is the ONLY allowed direct `healthBox.put('sleep_logs'` — kept
//      intentionally per the task spec (asymmetric list semantics).
//
// Run: flutter test test/contracts/health_write_service_writer_to_reader_test.dart

import 'dart:io';
import 'package:test/test.dart';

void main() {
  final root = Directory.current.path;
  final servicePath = '$root/lib/core/services/health_write_service.dart';
  final serviceFile = File(servicePath);

  group('HealthWriteService — file exists with canonical methods', () {
    test('service file exists', () {
      expect(serviceFile.existsSync(), isTrue,
          reason: 'lib/core/services/health_write_service.dart must exist');
    });

    test('all 6 canonical methods present', () {
      final src = serviceFile.readAsStringSync();
      for (final method in const [
        'Future<WriteResult> logSleep(',
        'Future<WriteResult> logWeight(',
        'Future<WriteResult> logMeasurement(',
        'Future<WriteResult> setWaterMl(',
        'Future<WriteResult> logUrine(',
        'Future<WriteResult> logHydration(',
      ]) {
        expect(src.contains(method), isTrue,
            reason: 'HealthWriteService must expose $method');
      }
    });

    test('singleton instance is exposed', () {
      final src = serviceFile.readAsStringSync();
      expect(src.contains('static final HealthWriteService instance ='), isTrue,
          reason: 'HealthWriteService must expose a static singleton');
    });
  });

  group('IST-throughout — every method uses istDateStr', () {
    test('istDateStr called at least 6 times (one per method)', () {
      final src = serviceFile.readAsStringSync();
      final matches = RegExp(r'istDateStr\(').allMatches(src).length;
      expect(matches, greaterThanOrEqualTo(6),
          reason:
              'audit-2026-05-16 F2-R2 — every method must compute its Hive '
              'date key via istDateStr to close the device-local drift.');
    });

    test('no raw `now.year-now.month-now.day` date construction', () {
      final src = serviceFile.readAsStringSync();
      // Reject the exact device-local pattern that produced F2-R2.
      expect(
        RegExp(r"\$\{[a-z]+\.year\}-\$\{[a-z]+\.month").hasMatch(src),
        isFalse,
        reason: 'HealthWriteService must never inline device-local date '
            'construction — go through istDateStr.',
      );
    });
  });

  group('Mutex + sync fan-out + telemetry plumbing', () {
    test('per-(kind, date) mutex via _acquireLock', () {
      final src = serviceFile.readAsStringSync();
      expect(src.contains('_acquireLock('), isTrue,
          reason: 'HealthWriteService must serialise concurrent same-key '
              'writes via a per-(date,kind) mutex.');
      expect(src.contains('_locks'), isTrue);
    });

    test('fire-and-forget SyncService fan-out', () {
      final src = serviceFile.readAsStringSync();
      expect(src.contains('unawaited(SyncService.instance.'), isTrue,
          reason: 'Every method must fire a sync method fire-and-forget '
              'per CLAUDE.md §15.');
      // Each method should also fire a pushSnapshot so the AI coach sees
      // the new health datapoint.
      final pushCount =
          RegExp(r'pushSnapshot\(\)').allMatches(src).length;
      expect(pushCount, greaterThanOrEqualTo(6),
          reason: 'Every method must call SyncService.instance.pushSnapshot()');
    });

    test('telemetry on failure via ErrorTelemetry.recordNonFatal', () {
      final src = serviceFile.readAsStringSync();
      final telemetryCalls =
          RegExp(r'ErrorTelemetry\.recordNonFatal').allMatches(src).length;
      expect(telemetryCalls, greaterThanOrEqualTo(6),
          reason: 'Every method must record telemetry on exception.');
    });
  });

  group('UI-layer migration — no forbidden direct healthBox.put', () {
    test('profile_provider.dart: no direct sleep_log_ write', () {
      final src = File(
              '$root/lib/features/profile/providers/profile_provider.dart')
          .readAsStringSync();
      expect(
        RegExp(r"healthBox\.put\(\s*'sleep_log_").hasMatch(src),
        isFalse,
        reason: 'F2-R2 — BiometricNotifier.logSleep must route through '
            'HealthWriteService.logSleep (not direct healthBox.put).',
      );
    });

    test('conversational_log_handler.dart: no direct measurement_ write', () {
      final src = File(
              '$root/lib/features/ai_coach/services/conversational_log_handler.dart')
          .readAsStringSync();
      expect(
        RegExp(r"healthBox\.put\(\s*key\s*,\s*record\s*\)").hasMatch(src) &&
            src.contains("'measurement_\$dateStr'"),
        isFalse,
        reason: '_logMeasurement must route through '
            'HealthWriteService.logMeasurement.',
      );
    });

    test(
        'conversational_log_handler.dart: _logSleep routes through '
        'HealthWriteService.logSleep (audit-2026-05-16 F2-R3)', () {
      // Post-F2-R3: the previously "intentional" direct write to the
      // legacy `sleep_logs` LIST key was the source of a dual-key reader
      // hazard — AI-logged sleeps were invisible to canonical readers
      // (profile.dailySleepProvider, AI snapshot sleep_7d series) that
      // key off `sleep_log_<istDate>` per-day. Fix routes through
      // HealthWriteService.logSleep — same pattern as _logMeasurement
      // for E.7 — so the canonical writer emits the per-day key + sync
      // fan-out.
      final src = File(
              '$root/lib/features/ai_coach/services/conversational_log_handler.dart')
          .readAsStringSync();
      expect(src.contains('HealthWriteService.instance.logSleep'), isTrue,
          reason:
              '_logSleep must route through HealthWriteService.logSleep '
              'so the canonical per-day key sleep_log_<istDate> is '
              'written and downstream readers see the AI-logged sleep.');
      // Anti-regression: the pre-fix direct write must not return.
      expect(
          RegExp(r"healthBox\.put\(\s*'sleep_logs'").hasMatch(src), isFalse,
          reason:
              'Pre-fix direct write to the legacy sleep_logs LIST key '
              'must not return — bypassed canonical readers.');
    });

    test('nutrition_provider.dart: no direct water_ml_ / urine_color_ / '
        'hydration_ writes', () {
      final src = File(
              '$root/lib/features/nutrition/providers/nutrition_provider.dart')
          .readAsStringSync();
      // The keys must no longer appear inside a healthBox.put call.
      for (final keyPrefix in const [
        "'water_ml_",
        "'urine_color_",
        "'hydration_",
      ]) {
        final hasDirectPut = RegExp(
                'healthBox\\.put\\([^)]*$keyPrefix',
                multiLine: true)
            .hasMatch(src);
        expect(hasDirectPut, isFalse,
            reason:
                'nutrition_provider.dart must route $keyPrefix writes through '
                'HealthWriteService (no direct healthBox.put).');
      }
    });

    test('home_provider.dart: no direct weight_ write', () {
      final src =
          File('$root/lib/features/home/providers/home_provider.dart')
              .readAsStringSync();
      expect(
        RegExp(r"healthBox\.put\(\s*'weight_").hasMatch(src),
        isFalse,
        reason: 'WeightLogNotifier.logWeight must route through '
            'HealthWriteService.logWeight.',
      );
    });

    test('onboarding_provider.dart: no direct weight_log wlog_ write', () {
      final src = File(
              '$root/lib/features/onboarding/providers/onboarding_provider.dart')
          .readAsStringSync();
      // Pre-fix wrote `_hive.healthBox.put(key, { 'type': 'weight_log', ... })`
      // where key was `wlog_$isoTs`. The replacement uses
      // HealthWriteService.logWeight which writes the canonical
      // `weight_<istDate>` key.
      expect(
        src.contains("_hive.healthBox.put(key, {"),
        isFalse,
        reason: 'OnboardingNotifier seed-weight path must route through '
            'HealthWriteService.logWeight, not a raw healthBox.put.',
      );
    });
  });

  group('WriteSource enum coverage', () {
    test('manual + onboarding values added', () {
      final src = File('$root/lib/core/services/write_result.dart')
          .readAsStringSync();
      expect(src.contains('manual,'), isTrue);
      expect(src.contains('onboarding,'), isTrue);
      // Codes
      expect(src.contains("return 'manual';"), isTrue);
      expect(src.contains("return 'onboarding';"), isTrue);
    });
  });
}
