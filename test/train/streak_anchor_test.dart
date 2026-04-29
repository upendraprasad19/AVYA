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

  String isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

  group('B2: streak anchor', () {
    test('user onboarded today, plan starts yesterday — no freeze consumed', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': today.toIso8601String(),
      });

      await HiveService.instance.workoutBox.put('schedule_${isoDate(yesterday)}', {
        'type': 'PUSH A',
        'workout_name': 'PUSH A',
        'status': 'pending',
      });

      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
      });

      final streak = WorkoutRepository.instance.calculateCurrentStreak();

      expect(streak, 0);

      final progress = HiveService.instance.userBox.get('progress') as Map;
      expect(progress['streak_freezes_available'], 1,
        reason: 'B2: pre-onboarding scheduled day must NOT consume freeze');
      expect((progress['streak_freeze_used_dates'] as List).isEmpty, true);
    });

    test('established user with completed days — anchor doesnt break legitimate streak', () async {
      final today = DateTime.now();

      await HiveService.instance.userBox.put('profile', {
        'id': 'A',
        'onboarding_completed_at': today.subtract(const Duration(days: 30)).toIso8601String(),
      });

      for (int i = 1; i <= 3; i++) {
        final d = today.subtract(Duration(days: i));
        await HiveService.instance.workoutBox.put('schedule_${isoDate(d)}', {
          'type': 'PUSH A',
          'status': 'completed',
        });
      }

      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
      });

      final streak = WorkoutRepository.instance.calculateCurrentStreak();

      expect(streak, 3);
      final progress = HiveService.instance.userBox.get('progress') as Map;
      expect(progress['streak_freezes_available'], 1);
    });
  });
}
