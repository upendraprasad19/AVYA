import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('WorkoutRepository.completionRateOverWindow', () {
    test('empty window returns 0.0', () {
      final repo = WorkoutRepository.instance;
      expect(repo.completionRateOverWindow(4), 0.0);
    });

    test('zero or negative windowWeeks short-circuits to 0.0', () {
      final repo = WorkoutRepository.instance;
      expect(repo.completionRateOverWindow(0), 0.0);
      expect(repo.completionRateOverWindow(-3), 0.0);
    });

    test('all scheduled days completed → 1.0', () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      // 7 scheduled, all completed
      for (int i = 0; i < 7; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': 'completed',
          'date': dateStr(d),
        });
      }
      final repo = WorkoutRepository.instance;
      expect(repo.completionRateOverWindow(2), 1.0);
    });

    test('half completed → 0.5 (rest days excluded)', () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      // 4 scheduled: 2 completed, 2 missed; plus 3 rest days that should be ignored
      for (int i = 0; i < 4; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': i.isEven ? 'completed' : 'scheduled',
          'date': dateStr(d),
        });
      }
      for (int i = 4; i < 7; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': 'rest',
          'date': dateStr(d),
        });
      }
      final repo = WorkoutRepository.instance;
      expect(repo.completionRateOverWindow(2), 0.5);
    });

    test('pre_onboarding days excluded from both numerator and denominator',
        () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now().toUtc()
          .add(const Duration(hours: 5, minutes: 30));
      final istToday = DateTime(today.year, today.month, today.day);
      // 2 completed scheduled days
      for (int i = 0; i < 2; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': 'completed',
          'date': dateStr(d),
        });
      }
      // 3 pre_onboarding rest placeholders — must be ignored
      for (int i = 2; i < 5; i++) {
        final d = istToday.subtract(Duration(days: i));
        await box.put('schedule_${dateStr(d)}', {
          'status': 'rest',
          'reason': 'pre_onboarding',
          'date': dateStr(d),
        });
      }
      final repo = WorkoutRepository.instance;
      // 2/2 because pre_onboarding excluded
      expect(repo.completionRateOverWindow(2), 1.0);
    });
  });
}
