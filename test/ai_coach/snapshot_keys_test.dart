// test/ai_coach/snapshot_keys_test.dart
//
// TDD tests for APK Test #4 / Task A4: today_workout, yesterday_workout,
// and week_lookahead snapshot keys added to AiCoachRepository.buildAiContext().
//
// Keys under test:
//   today_workout     — Map {type, status, exercises} or null if no schedule
//   yesterday_workout — Map {type, status} or null if no schedule
//   week_lookahead    — List of 7 {day, date, type, status}; REST for missing days

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_a4_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.workoutBox.clear();
  });

  String todayIso() => DateTime.now().toIso8601String().substring(0, 10);
  String yesterdayIso() => DateTime.now()
      .subtract(const Duration(days: 1))
      .toIso8601String()
      .substring(0, 10);

  group('today_workout', () {
    test('returns null when no schedule for today', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['today_workout'], isNull);
    });

    test('reflects scheduled session with type, status, and exercises', () async {
      await HiveService.instance.workoutBox.put('schedule_${todayIso()}', {
        'type': 'PUSH A',
        'status': 'pending',
        'workout_name': 'PUSH A',
        'exercises': [
          {
            'name': 'Bench Press',
            'sets': 4,
            'reps': '8-10',
            'weight': 60,
            'logging_type': 'weight_reps',
          },
          {
            'name': 'OHP',
            'sets': 3,
            'reps': '6-8',
            'weight': 45,
            'logging_type': 'weight_reps',
          },
        ],
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['today_workout'], isNotNull);
      final tw = ctx['today_workout'] as Map;
      expect(tw['type'], 'PUSH A');
      expect(tw['status'], 'pending');
      expect(tw['exercises'], isList);
      expect((tw['exercises'] as List).length, 2);
    });

    test('falls back to workout_name if type missing', () async {
      await HiveService.instance.workoutBox.put('schedule_${todayIso()}', {
        'workout_name': 'LEGS B',
        'status': 'completed',
        'exercises': [],
      });
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect((ctx['today_workout'] as Map)['type'], 'LEGS B');
    });
  });

  group('yesterday_workout', () {
    test('returns null when no schedule for yesterday', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['yesterday_workout'], isNull);
    });

    test('reports type and status for yesterday', () async {
      await HiveService.instance.workoutBox.put('schedule_${yesterdayIso()}', {
        'type': 'PULL A',
        'status': 'completed',
        'workout_name': 'PULL A',
      });
      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['yesterday_workout'], isNotNull);
      expect((ctx['yesterday_workout'] as Map)['type'], 'PULL A');
      expect((ctx['yesterday_workout'] as Map)['status'], 'completed');
    });
  });

  group('week_lookahead', () {
    test('returns 7 entries (today + next 6 days)', () async {
      // Seed 2 entries, leave 5 as rest
      await HiveService.instance.workoutBox.put('schedule_${todayIso()}', {
        'type': 'PUSH A',
        'status': 'pending',
        'workout_name': 'PUSH A',
      });
      final tomorrow = DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      await HiveService.instance.workoutBox.put('schedule_$tomorrow', {
        'type': 'PULL A',
        'status': 'pending',
        'workout_name': 'PULL A',
      });

      final ctx = AiCoachRepository.instance.buildAiContext();
      expect(ctx['week_lookahead'], isList);
      final week = ctx['week_lookahead'] as List;
      expect(week.length, 7);

      final first = week.first as Map;
      expect(first['date'], todayIso());
      expect(first['type'], 'PUSH A');
      expect(first['status'], 'pending');

      // Days without schedule should be REST
      final third = week[2] as Map;
      expect(third['type'], 'REST');
      expect(third['status'], 'rest');
    });

    test('each entry has day, date, type, status fields', () {
      final ctx = AiCoachRepository.instance.buildAiContext();
      final week = ctx['week_lookahead'] as List;
      for (final entry in week) {
        final e = entry as Map;
        expect(e.keys, containsAll(['day', 'date', 'type', 'status']));
        expect(e['day'], isA<String>());
        expect(e['date'], isA<String>());
      }
    });
  });
}
