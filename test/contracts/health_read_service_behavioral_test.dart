// BEHAVIORAL contract for health_read_service:
// HealthReadService.waterMlForDate(date) reads `water_ml_<istDateStr(date)>`.
// HealthWriteService.setWaterMl(date, totalMl, ...) writes `water_ml_<istDateStr(date)>`.
//
// Assertions:
//   1. waterMlForDate(same IST date) returns the value written by setWaterMl.
//   2. waterMlForDate(different IST date) returns 0 (key not found).
//   3. The key formula `water_ml_<istDateStr(date)>` is shared between
//      write and read — a change to either side breaks this test.
//
// Run: flutter test test/contracts/health_read_service_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
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
    tempDir = Directory.systemTemp.createTempSync('health_read_svc_');
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

  const testUser = 'test-health-read-svc-0022-aabbccdd';

  group('health_read_service — waterMlForDate key-formula agreement', () {
    test(
        'waterMlForDate returns value written by setWaterMl for the SAME IST date',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();

      // Use a fixed UTC datetime that maps to a known IST date.
      // 2026-06-18 10:00 UTC → 2026-06-18 15:30 IST (same day).
      final writeDate = DateTime.utc(2026, 6, 18, 10, 0, 0);
      const totalMl = 1750;

      final result = await HealthWriteService.instance.setWaterMl(
        date: writeDate,
        totalMl: totalMl,
        source: WriteSource.manual,
      );
      expect(result.success, isTrue,
          reason: 'setWaterMl must succeed for valid totalMl');

      // Read back with the SAME date object — IST key must match.
      final readDate = DateTime.utc(2026, 6, 18, 10, 0, 0);
      final readMl = HealthReadService.instance.waterMlForDate(readDate);

      expect(readMl, totalMl,
          reason:
              'waterMlForDate must return the exact value written by setWaterMl '
              'for the same IST date key water_ml_${istDateStr(writeDate)}');
    });

    test(
        'waterMlForDate returns 0 for a DIFFERENT IST date (key-formula isolation)',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();

      // Write for 2026-06-18 (IST).
      final writeDate = DateTime.utc(2026, 6, 18, 10, 0, 0);
      await HealthWriteService.instance.setWaterMl(
        date: writeDate,
        totalMl: 2000,
        source: WriteSource.manual,
      );

      // Read for 2026-06-19 (IST) — different key — must return 0.
      final differentDate = DateTime.utc(2026, 6, 19, 10, 0, 0);
      final readMl = HealthReadService.instance.waterMlForDate(differentDate);

      expect(readMl, 0,
          reason:
              'waterMlForDate must return 0 for a date with no written entry; '
              'a non-zero return means key drift between writer and reader');
    });

    test(
        'waterMlForDate returns 0 when no water logged at all (absent key returns 0)',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();

      final anyDate = DateTime.utc(2026, 6, 18, 8, 0, 0);
      final readMl = HealthReadService.instance.waterMlForDate(anyDate);

      expect(readMl, 0,
          reason:
              'absent key must return 0 — waterMlForDate is zero-default per contract');
    });

    test(
        '23:30 UTC write key matches next-IST-day read key (midnight-crossing IST formula)',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();

      // 23:30 UTC on 2026-06-17 → 05:00 IST on 2026-06-18 (next day).
      final writeDate = DateTime.utc(2026, 6, 17, 23, 30, 0);
      final expectedIstDate = istDateStr(writeDate);
      expect(expectedIstDate, '2026-06-18',
          reason: 'confirm IST helper converts 23:30 UTC → next IST day');

      await HealthWriteService.instance.setWaterMl(
        date: writeDate,
        totalMl: 500,
        source: WriteSource.manual,
      );

      // A read using the SAME DateTime should find the value.
      final readMl = HealthReadService.instance.waterMlForDate(writeDate);
      expect(readMl, 500,
          reason: 'write and read must use the same istDateStr formula');

      // A read using the UTC-equivalent day (2026-06-17) must return 0.
      final utcDayDate = DateTime.utc(2026, 6, 17, 12, 0, 0); // IST = 2026-06-17
      final readMlWrongDay = HealthReadService.instance.waterMlForDate(utcDayDate);
      expect(readMlWrongDay, 0,
          reason:
              'reading with 2026-06-17 IST key must return 0; '
              'the water was written under 2026-06-18 IST key');
    });

    test(
        'sleepHoursForDate returns hours written by logSleep for the same IST date',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();

      final writeDate = DateTime.utc(2026, 6, 18, 10, 0, 0);
      const expectedHours = 6.5;

      await HealthWriteService.instance.logSleep(
        date: writeDate,
        hours: expectedHours,
        quality: 'good',
        source: WriteSource.manual,
      );

      final readHours =
          HealthReadService.instance.sleepHoursForDate(writeDate);

      expect(readHours, expectedHours,
          reason:
              'sleepHoursForDate must return the exact hours written by logSleep '
              'via the sleep_log_<istDateStr(date)> key');
    });

    test(
        'sleepHoursForDate returns null for a date with no written sleep entry',
        () async {
      await HiveUserSession.openForUser(testUser);
      await HiveService.instance.healthBox.clear();

      // Write for 2026-06-18.
      await HealthWriteService.instance.logSleep(
        date: DateTime.utc(2026, 6, 18, 10, 0, 0),
        hours: 7.0,
        quality: 'good',
        source: WriteSource.manual,
      );

      // Read for a different day — must return null.
      final readHours = HealthReadService.instance
          .sleepHoursForDate(DateTime.utc(2026, 6, 19, 10, 0, 0));
      expect(readHours, isNull,
          reason: 'sleepHoursForDate must return null for a day with no entry');
    });
  });
}
