// Contract test for OI-02 (closes-diagnose: 2026-05-17-oi-02-read-services).
//
// Pins `HealthReadService` primitives: latestWeightKg, sleepHoursForDate,
// waterMlForDate. IST date key formula must agree with HealthWriteService.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDownAll(() async {
    await tearDownHiveForTests(tempDir);
  });

  tearDown(() async {
    await HiveService.instance.healthBox.clear();
  });

  group('HealthReadService.latestWeightKg', () {
    test('returns null when no weight rows exist', () {
      expect(HealthReadService.instance.latestWeightKg(), isNull);
    });

    test('returns latest by stamped date', () async {
      await HiveService.instance.healthBox.put('weight_2026-05-10', {
        'date': '2026-05-10',
        'weight_kg': 75.0,
        'type': 'weight_log',
      });
      await HiveService.instance.healthBox.put('weight_2026-05-15', {
        'date': '2026-05-15',
        'weight_kg': 73.5,
        'type': 'weight_log',
      });
      await HiveService.instance.healthBox.put('weight_2026-05-12', {
        'date': '2026-05-12',
        'weight_kg': 74.2,
        'type': 'weight_log',
      });

      expect(HealthReadService.instance.latestWeightKg(), 73.5);
    });

    test('ignores rows with non-positive weight or missing date', () async {
      await HiveService.instance.healthBox.put('weight_2026-05-10', {
        'date': '2026-05-10',
        'weight_kg': 0.0, // skipped
        'type': 'weight_log',
      });
      await HiveService.instance.healthBox.put('weight_2026-05-15', {
        'weight_kg': 80.0, // skipped — no date
        'type': 'weight_log',
      });
      await HiveService.instance.healthBox.put('weight_2026-05-12', {
        'date': '2026-05-12',
        'weight_kg': 74.2,
        'type': 'weight_log',
      });

      expect(HealthReadService.instance.latestWeightKg(), 74.2);
    });
  });

  group('HealthReadService.sleepHoursForDate', () {
    test('reads sleep_log_<istDate> sleep_hours field', () async {
      final date = DateTime(2026, 5, 15, 23, 0);
      final key = 'sleep_log_${istDateStr(date)}';
      await HiveService.instance.healthBox.put(key, {
        'date': istDateStr(date),
        'sleep_hours': 7.5,
        'quality': 'good',
      });
      expect(HealthReadService.instance.sleepHoursForDate(date), 7.5);
    });

    test('falls back to legacy duration_hrs alias', () async {
      final date = DateTime(2026, 5, 15);
      final key = 'sleep_log_${istDateStr(date)}';
      await HiveService.instance.healthBox.put(key, {
        'date': istDateStr(date),
        'duration_hrs': 6.0,
      });
      expect(HealthReadService.instance.sleepHoursForDate(date), 6.0);
    });

    test('returns null when no entry exists', () {
      expect(HealthReadService.instance.sleepHoursForDate(DateTime(2026, 5, 15)),
          isNull);
    });
  });

  group('HealthReadService.waterMlForDate', () {
    test('reads bare-int water_ml_<istDate>', () async {
      final date = DateTime(2026, 5, 15);
      final key = 'water_ml_${istDateStr(date)}';
      await HiveService.instance.healthBox.put(key, 1750);
      expect(HealthReadService.instance.waterMlForDate(date), 1750);
    });

    test('returns 0 when no entry exists (additive total)', () {
      expect(HealthReadService.instance.waterMlForDate(DateTime(2026, 5, 15)), 0);
    });

    test('coerces num to int when restored as double', () async {
      final date = DateTime(2026, 5, 15);
      final key = 'water_ml_${istDateStr(date)}';
      await HiveService.instance.healthBox.put(key, 1500.0);
      expect(HealthReadService.instance.waterMlForDate(date), 1500);
    });
  });
}
