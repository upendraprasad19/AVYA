// BEHAVIORAL contract for health_write_service:
// HealthWriteService.logSleep uses istDateStr(date) for the Hive key.
// This test verifies:
//   1. The key is `sleep_log_<istDateStr(date)>` — NOT device-local YYYY-MM-DD.
//   2. For a timestamp at 23:30 UTC, the written key is the NEXT IST day.
//   3. BiometricNotifier reads the per-day `sleep_log_<todayStr>` key (not only
//      the legacy `sleep_logs` list) and returns the correct hours.
//
// Run: flutter test test/contracts/health_write_service_behavioral_test.dart

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
    tempDir = Directory.systemTemp.createTempSync('health_write_svc_');
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

  setUp(() async {
    await HiveUserSession.closeAll();
    await HiveService.instance.configBox.clear();
  });

  const testUser = 'test-health-write-0011-aabbccdd';

  group('health_write_service — IST date key formula', () {
    test(
        'logSleep at 23:30 UTC writes key for NEXT IST day (UTC+5:30 → +6h = 05:00)',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();

      // 23:30 UTC on 2026-06-17 → 05:00 IST on 2026-06-18 (next day).
      final utcTime = DateTime.utc(2026, 6, 17, 23, 30, 0);
      final expectedIstDate = istDateStr(utcTime); // Must be '2026-06-18'
      expect(expectedIstDate, '2026-06-18',
          reason: '23:30 UTC = 05:00 IST the next calendar day');

      final result = await HealthWriteService.instance.logSleep(
        date: utcTime,
        hours: 7.5,
        quality: 'good',
        source: WriteSource.manual,
      );
      expect(result.success, isTrue,
          reason: 'logSleep must succeed for valid hours');

      // The Hive key must be the IST date, not the UTC date.
      final box = HiveService.instance.healthBox;
      final expectedKey = 'sleep_log_$expectedIstDate'; // sleep_log_2026-06-18
      final wrongKey = 'sleep_log_2026-06-17'; // UTC day — must NOT be written

      expect(box.get(expectedKey), isNotNull,
          reason: 'sleep_log entry must use IST key sleep_log_2026-06-18');
      expect(box.get(wrongKey), isNull,
          reason: 'device-local UTC key must NOT be written (regression guard)');

      // Verify the stored hours match what was written.
      final stored = box.get(expectedKey);
      expect(stored is Map, isTrue);
      final map = Map<String, dynamic>.from(stored as Map);
      expect((map['sleep_hours'] as num?)?.toDouble(), 7.5,
          reason: 'sleep_hours field must round-trip exactly');
      expect((map['duration_hrs'] as num?)?.toDouble(), 7.5,
          reason: 'duration_hrs legacy alias must also be written');
      expect(map['date'], expectedIstDate,
          reason: 'date field must hold the IST date string');
    });

    test('logSleep result.logKey is the expected IST key', () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();

      final utcTime = DateTime.utc(2026, 6, 17, 23, 30, 0);
      final result = await HealthWriteService.instance.logSleep(
        date: utcTime,
        hours: 6.0,
        quality: 'fair',
        source: WriteSource.manual,
      );
      expect(result.logKey, 'sleep_log_2026-06-18',
          reason: 'WriteResult.logKey must equal the IST key written to Hive');
    });
  });

  group('health_write_service → BiometricNotifier per-day key read path', () {
    test(
        'BiometricNotifier reads sleep_log_<todayStr> key and returns correct hours',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();
      // Enable health sync so BiometricNotifier doesn't short-circuit.
      await HiveService.instance.configBox.put('health_sync_enabled', true);

      // BiometricNotifier uses `istDateStr(DateTime.now())` — so we must write
      // with DateTime.now() to produce a matching key.
      final now = DateTime.now();
      final todayStr = istDateStr(now);
      const expectedHours = 8.0;

      final result = await HealthWriteService.instance.logSleep(
        date: now,
        hours: expectedHours,
        quality: 'excellent',
        source: WriteSource.manual,
      );
      expect(result.success, isTrue);

      // Verify the key is present in Hive directly.
      final box = HiveService.instance.healthBox;
      expect(box.get('sleep_log_$todayStr'), isNotNull,
          reason: 'sleep_log_<todayStr> must be written to healthBox');

      // Now read via BiometricNotifier using a ProviderContainer.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final biometric = container.read(biometricProvider);
      expect(biometric.isSyncEnabled, isTrue,
          reason: 'health_sync_enabled must be true');
      expect(biometric.sleepHours, expectedHours,
          reason:
              'BiometricNotifier must read sleep hours from per-day key not only legacy list');
    });

    test(
        'BiometricNotifier returns null sleepHours when no sleep_log_ key exists for today',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();
      await HiveService.instance.configBox.put('health_sync_enabled', true);

      // Write a sleep log for YESTERDAY — should NOT be picked up by BiometricNotifier.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await HealthWriteService.instance.logSleep(
        date: yesterday,
        hours: 7.0,
        quality: 'good',
        source: WriteSource.manual,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final biometric = container.read(biometricProvider);
      expect(biometric.sleepHours, isNull,
          reason: 'Yesterday\'s sleep log must NOT appear as today\'s hours');
    });
  });
}
