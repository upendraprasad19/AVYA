// BEHAVIORAL contract for sleep_logs dedup rule:
//
// When BOTH a per-day `sleep_log_<date>` key AND a legacy-list `sleep_logs`
// entry exist for the same date, BiometricNotifier MUST return only the
// per-day value — the legacy list is NOT consulted and NOT double-counted.
//
// Writers:
//   - per-day key:  HealthWriteService.logSleep  (profile_provider.dart consumer)
//   - legacy list:  AI chat path (healthBox key 'sleep_logs')
// Reader:
//   - BiometricNotifier.build() in profile_provider.dart
//
// Run: flutter test test/contracts/sleep_logs_behavioral_test.dart

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('sleep_logs_dedup_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  const testUser = 'test-sleep-dedup-0001-aabbccdd';

  setUp(() async {
    await HiveUserSession.openForUser(testUser);
    await HiveService.instance.healthBox.clear();
    await HiveService.instance.configBox.clear();
    await HiveService.instance.configBox.put('health_sync_enabled', true);
  });

  group('sleep_logs — dedup: per-day key wins over legacy list', () {
    test(
        'when per-day key exists, legacy list entry for same date is NOT consulted',
        () async {
      final now = DateTime.now();
      final todayStr = istDateStr(now);

      // Write the canonical per-day key via the service writer.
      final result = await HealthWriteService.instance.logSleep(
        date: now,
        hours: 7.0,
        quality: 'good',
        source: WriteSource.manual,
      );
      expect(result.success, isTrue,
          reason: 'logSleep must succeed so the per-day key is written');
      expect(HiveService.instance.healthBox.get('sleep_log_$todayStr'),
          isNotNull,
          reason: 'per-day key sleep_log_$todayStr must exist');

      // Also inject a legacy-list entry for the SAME date with a
      // DIFFERENT hours value — if BiometricNotifier reads both and sums
      // them, the assertion below will fail revealing the double-count bug.
      const legacyHours = 3.0; // deliberately different from 7.0
      await HiveService.instance.healthBox.put('sleep_logs', [
        {
          'date': todayStr,
          'sleep_hours': legacyHours,
        }
      ]);

      // Read via BiometricNotifier.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final biometric = container.read(biometricProvider);

      // Expect the per-day value (7.0), NOT the legacy value (3.0),
      // NOT the sum (10.0).
      expect(biometric.sleepHours, 7.0,
          reason:
              'per-day key (7.0h) must win; legacy list must NOT be read '
              'when per-day key exists for the same date');
    });

    test('legacy list IS consulted when per-day key is absent for today',
        () async {
      final now = DateTime.now();
      final todayStr = istDateStr(now);

      // No per-day key — only legacy list.
      await HiveService.instance.healthBox.put('sleep_logs', [
        {
          'date': todayStr,
          'sleep_hours': 6.5,
        }
      ]);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final biometric = container.read(biometricProvider);

      expect(biometric.sleepHours, 6.5,
          reason:
              'when per-day key is absent, legacy list must be the fallback');
    });

    test('legacy list entry for a different date does NOT appear for today',
        () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr = istDateStr(yesterday);

      // Legacy list has an entry for YESTERDAY only.
      await HiveService.instance.healthBox.put('sleep_logs', [
        {
          'date': yesterdayStr,
          'sleep_hours': 8.0,
        }
      ]);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final biometric = container.read(biometricProvider);

      expect(biometric.sleepHours, isNull,
          reason:
              'yesterday\'s legacy entry must NOT appear as today\'s sleep hours');
    });
  });
}
