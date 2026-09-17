// C1 (ai-coach-ux-tool-integrity spec 2026-09-18) — founder rule: PAUSED =
// INVISIBLE. A past paused day must neither break the streak nor burn a
// freeze (writer: pauseRange, workout_schedule_write_service.dart:140; the
// old reader fell through to the missed arm: workout_repository.dart:384).
// Same for the 'moved'/'dropped' terminal rows Task 2 introduces.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  Future<void> seedAnchor(int daysBack) async {
    await HiveService.instance.userBox.put('profile', {
      'id': 'A',
      'onboarding_completed_at':
          nowWall().subtract(Duration(days: daysBack)).toIso8601String(),
    });
  }

  group('C1 — paused days are invisible to the streak', () {
    test('a paused past day neither breaks the streak nor burns a freeze',
        () async {
      await seedAnchor(20);
      final today = nowWall();
      DateTime daysAgo(int n) => today.subtract(Duration(days: n));
      String key(DateTime d) => istDateStr(d);

      await HiveService.instance.workoutBox
          .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(1))}',
          {'type': 'PUSH', 'status': 'paused', 'paused_via': 'ai_coach'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(2))}', {'type': 'PUSH', 'status': 'completed'});
      // ZERO freezes available — pre-fix the paused day broke the walk here.
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
      });

      expect(WorkoutRepository.instance.currentStreak(), 2,
          reason: 'paused day-1 is invisible: today(+1) day-1(skip) day-2(+1) = 2');
    });

    test('a moved/dropped terminal row is equally invisible', () async {
      await seedAnchor(20);
      final today = nowWall();
      DateTime daysAgo(int n) => today.subtract(Duration(days: n));
      String key(DateTime d) => istDateStr(d);

      await HiveService.instance.workoutBox
          .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox.put('schedule_${key(daysAgo(1))}',
          {'type': 'PUSH', 'status': 'moved', 'moved_to': istDateStr(today)});
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(2))}',
          {'type': 'PUSH', 'status': 'dropped', 'moved_via': 'ai_coach'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(3))}', {'type': 'PUSH', 'status': 'completed'});

      expect(WorkoutRepository.instance.currentStreak(), 2,
          reason: 'moved+dropped invisible: today(+1) day-1(skip) day-2(skip) day-3(+1)');
    });

    test('a genuinely missed day with no freeze still breaks (no over-protection)',
        () async {
      await seedAnchor(20);
      final today = nowWall();
      DateTime daysAgo(int n) => today.subtract(Duration(days: n));
      String key(DateTime d) => istDateStr(d);

      await HiveService.instance.workoutBox
          .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(1))}', {'type': 'PUSH', 'status': 'pending'});
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(2))}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
      });

      expect(WorkoutRepository.instance.currentStreak(), 1,
          reason: 'missed day-1 still breaks — the rule protects pauses, not skips');
    });
  });

  group('C1 — completionRateOverWindow excludes paused/moved/dropped', () {
    test('paused day is out of BOTH numerator and denominator', () async {
      await seedAnchor(20);
      final today = nowWall();
      DateTime daysAgo(int n) => today.subtract(Duration(days: n));
      String key(DateTime d) => istDateStr(d);

      await HiveService.instance.workoutBox
          .put('schedule_${key(today)}', {'type': 'PUSH', 'status': 'completed'});
      await HiveService.instance.workoutBox.put(
          'schedule_${key(daysAgo(1))}',
          {'type': 'PUSH', 'status': 'paused', 'paused_via': 'ai_coach'});
      // PLAN-SEED CORRECTION (implementer, 2026-09-18): the plan seeded day-2
      // as 'completed' while its own comments require 1 completed / 2 counted
      // = 0.5 (and pre-fix 1/3 ≈ 0.33) — unreachable with two completed days
      // (pre-fix actual was 0.67, post-fix 1.0). Day-2 is 'pending'
      // (scheduled, not completed) so the assertion measures exactly what the
      // plan's comment describes: paused excluded from BOTH sides.
      await HiveService.instance.workoutBox
          .put('schedule_${key(daysAgo(2))}', {'type': 'PUSH', 'status': 'pending'});
      // Only today (completed) + day-2 (pending) count: 1/2 = 0.5.
      // Pre-fix: 1/3 ≈ 0.33 (paused counted as scheduled-not-completed).
      expect(WorkoutRepository.instance.completionRateOverWindow(1), 0.5);
    });
  });
}
