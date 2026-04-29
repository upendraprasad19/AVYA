// test/ai_coach/anti_fabrication_grounding_test.dart
//
// Validates the anti-fabrication grounding keys added to buildAiContext()
// in APK Test #4 / Task A3. The Captain Manual §8 references these keys
// to refuse history-beyond-window claims (e.g. "no data from last year —
// 8 days on roster").
//
// Keys under test:
//   data_window_days       — int: days since first wlog_* row, 0 if none
//   first_workout_date     — String? ISO date of earliest workout, null if none
//   workout_logs_count     — int: total wlog_* key count
//   nutrition_logs_count_7d — int: nlog_* rows with date in last 7 days
//   sleep_logs_count_7d    — int: sleep_log_* rows with date in last 7 days

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('avya_test_a3_');
    // Mock path_provider per CLAUDE.md §19 — required for Hive in unit tests.
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tempDir.path);
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.nutritionBox.clear();
    await HiveService.instance.healthBox.clear();
  });

  group('anti-fabrication grounding keys', () {
    test('data_window_days computed from earliest workout log', () async {
      final eightDaysAgo = DateTime.now().subtract(const Duration(days: 8));
      final dateStr = eightDaysAgo.toIso8601String().substring(0, 10);
      await HiveService.instance.workoutBox.put(
        'wlog_${eightDaysAgo.millisecondsSinceEpoch}',
        {
          'date': dateStr,
          'workout_name': 'PUSH A',
          'duration_seconds': 1800,
        },
      );

      final ctx = AiCoachRepository.instance.buildAiContext();

      expect(ctx['data_window_days'], greaterThanOrEqualTo(7));
      expect(ctx['data_window_days'], lessThanOrEqualTo(9));
      expect(ctx['first_workout_date'], dateStr);
      expect(ctx['workout_logs_count'], 1);
    });

    test('zero workouts returns zero window + null first date', () async {
      final ctx = AiCoachRepository.instance.buildAiContext();

      expect(ctx['workout_logs_count'], 0);
      expect(ctx['data_window_days'], 0);
      expect(ctx['first_workout_date'], isNull);
    });

    test('workout_logs_count counts all wlog_* keys', () async {
      final base = DateTime.now().subtract(const Duration(days: 5));
      for (int i = 0; i < 3; i++) {
        final d = base.add(Duration(days: i));
        final dateStr = d.toIso8601String().substring(0, 10);
        await HiveService.instance.workoutBox.put(
          'wlog_${d.millisecondsSinceEpoch}',
          {
            'date': dateStr,
            'workout_name': 'PUSH A',
            'duration_seconds': 1800,
          },
        );
      }

      final ctx = AiCoachRepository.instance.buildAiContext();

      expect(ctx['workout_logs_count'], 3);
    });

    test('nutrition_logs_count_7d counts only logs in last 7 days', () async {
      // 3 logs in last 7 days
      for (int i = 0; i < 3; i++) {
        final d = DateTime.now().subtract(Duration(days: i));
        final dateStr = d.toIso8601String().substring(0, 10);
        await HiveService.instance.nutritionBox.put(
          'nlog_${d.millisecondsSinceEpoch}',
          {'date': dateStr, 'total_calories': 500},
        );
      }
      // 1 log 30 days ago (outside the 7-day window — must NOT be counted)
      final old = DateTime.now().subtract(const Duration(days: 30));
      await HiveService.instance.nutritionBox.put(
        'nlog_${old.millisecondsSinceEpoch}',
        {
          'date': old.toIso8601String().substring(0, 10),
          'total_calories': 500,
        },
      );

      final ctx = AiCoachRepository.instance.buildAiContext();

      expect(ctx['nutrition_logs_count_7d'], 3);
    });

    test('sleep_logs_count_7d counts only sleep logs in last 7 days',
        () async {
      for (int i = 0; i < 5; i++) {
        final d = DateTime.now().subtract(Duration(days: i));
        final dateStr = d.toIso8601String().substring(0, 10);
        await HiveService.instance.healthBox.put(
          'sleep_log_${d.millisecondsSinceEpoch}',
          {'date': dateStr, 'hours': 7.5},
        );
      }

      final ctx = AiCoachRepository.instance.buildAiContext();

      expect(ctx['sleep_logs_count_7d'], 5);
    });
  });
}
