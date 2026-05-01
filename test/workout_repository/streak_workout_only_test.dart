import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';

import '../helpers/hive_test_setup.dart';

/// Streak rule pin (Q26 = a, spec §10.3):
///   - Rest days are invisible (don't increment, don't break).
///   - Only `status='completed'` increments.
///   - Missed scheduled workouts (status='scheduled' on a non-today date)
///     break the streak when no freeze is available.
///   - Pre-onboarding days end the walk-back (handled here via the user
///     anchor: `profile.onboarding_completed_at`).
///
/// Note: this codebase uses `type='rest'` (NOT `status='rest'`) to mark
/// rest days; tests reflect production schema. The spec rule is the same
/// regardless of which field carries the rest marker.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
    // Clear shared streak-freeze state between tests so a missed-day case
    // can't be salvaged by a leftover freeze.
    final userBox = HiveService.instance.userBox;
    final progress = (userBox.get('progress') as Map?) ?? {};
    final mp = Map<String, dynamic>.from(progress);
    mp['streak_freezes_available'] = 0;
    mp['streak_freeze_used_dates'] = <String>[];
    await userBox.put('progress', mp);
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  String dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  group('Streak counts workout-only days (Q26=a)', () {
    test('completed workouts with rest days interspersed → rests invisible',
        () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now();
      final istToday = DateTime(today.year, today.month, today.day);
      // Pattern (i=0..9): C C C R C C C R C C
      // 8 completed workouts with 2 rest days interspersed.
      // Rests are invisible → streak should be 8.
      final pattern = ['c', 'c', 'c', 'r', 'c', 'c', 'c', 'r', 'c', 'c'];
      for (int i = 0; i < pattern.length; i++) {
        final d = istToday.subtract(Duration(days: i));
        if (pattern[i] == 'c') {
          await box.put('schedule_${dateStr(d)}', {
            'type': 'workout',
            'status': 'completed',
            'date': dateStr(d),
          });
        } else {
          await box.put('schedule_${dateStr(d)}', {
            'type': 'rest',
            'status': 'rest',
            'date': dateStr(d),
          });
        }
      }
      expect(WorkoutRepository.instance.calculateCurrentStreak(), 8);
    });

    test('reset on missed scheduled workout (no freeze)', () async {
      final box = HiveService.instance.workoutBox;
      final today = DateTime.now();
      final istToday = DateTime(today.year, today.month, today.day);
      // today=completed, yesterday=scheduled-but-not-done → break
      await box.put('schedule_${dateStr(istToday)}', {
        'type': 'workout',
        'status': 'completed',
        'date': dateStr(istToday),
      });
      final yesterday = istToday.subtract(const Duration(days: 1));
      await box.put('schedule_${dateStr(yesterday)}', {
        'type': 'workout',
        'status': 'scheduled',
        'date': dateStr(yesterday),
      });
      expect(WorkoutRepository.instance.calculateCurrentStreak(), 1);
    });

    test('walk-back stops at user onboarding anchor', () async {
      final box = HiveService.instance.workoutBox;
      final userBox = HiveService.instance.userBox;
      final today = DateTime.now();
      final istToday = DateTime(today.year, today.month, today.day);
      // Anchor = today (no pre-anchor data should count).
      final progress = (userBox.get('profile') as Map?) ?? {};
      final mp = Map<String, dynamic>.from(progress);
      mp['onboarding_completed_at'] = istToday.toIso8601String();
      await userBox.put('profile', mp);

      // today = completed → streak +1.
      await box.put('schedule_${dateStr(istToday)}', {
        'type': 'workout',
        'status': 'completed',
        'date': dateStr(istToday),
      });
      // yesterday is BEFORE the anchor → walk-back must stop without
      // penalising or counting.
      final yesterday = istToday.subtract(const Duration(days: 1));
      await box.put('schedule_${dateStr(yesterday)}', {
        'type': 'workout',
        'status': 'scheduled',
        'date': dateStr(yesterday),
      });
      expect(WorkoutRepository.instance.calculateCurrentStreak(), 1);
    });
  });
}
