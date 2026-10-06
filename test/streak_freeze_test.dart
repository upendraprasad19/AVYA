import 'package:flutter_test/flutter_test.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Streak Freeze — Pure Logic Tests (No Hive, No Device Required)
/// Run with: flutter test test/streak_freeze_test.dart
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Tests the streak freeze calculation logic extracted from train_provider.dart.
/// The actual Hive integration is covered in integration tests.
///
/// SF-1  — Consecutive day: streak increments, no freeze used
/// SF-2  — Gap with freeze available: freeze consumed, streak continues
/// SF-3  — Gap without freeze: streak resets to 1
/// SF-4  — Same day double-log: no change to streak or freezes
/// SF-5  — Multiple freezes (PRO): can survive multiple missed days
/// SF-6  — Zero freezes remaining: gap resets streak
/// SF-7  — Weekly refill: Monday detection logic
/// SF-8  — Freeze used dates list tracks which days were frozen

/// Extracted streak logic for testing without Hive dependencies.
/// Mirrors the logic in train_provider.dart lines ~1270-1315.
class StreakFreezeCalculator {
  /// Calculates updated streak state after a workout is logged.
  ///
  /// Returns a map with: current_streak_days, streak_freezes_available,
  /// streak_freeze_used_dates, streak_freeze_just_used, last_workout_date.
  static Map<String, dynamic> calculateStreak({
    required String todayStr,
    required String yesterdayStr,
    required String lastWorkoutDate,
    required int currentStreakDays,
    required int freezesAvailable,
    required List<String> freezeUsedDates,
  }) {
    int streakDays = currentStreakDays;
    int freezes = freezesAvailable;
    final usedDates = List<String>.from(freezeUsedDates);
    bool freezeJustUsed = false;

    if (lastWorkoutDate == todayStr) {
      // Same day double-log — do nothing
    } else if (lastWorkoutDate == yesterdayStr) {
      // Consecutive day
      streakDays += 1;
    } else if (streakDays > 0 && freezes > 0 && lastWorkoutDate.isNotEmpty) {
      // Gap detected but user has a streak freeze
      freezes -= 1;
      usedDates.add(yesterdayStr);
      streakDays += 1;
      freezeJustUsed = true;
    } else {
      // Gap or first workout — start at 1
      streakDays = 1;
    }

    return {
      'current_streak_days': streakDays,
      'streak_freezes_available': freezes,
      'streak_freeze_used_dates': usedDates,
      'streak_freeze_just_used': freezeJustUsed,
      'last_workout_date': todayStr,
    };
  }

  /// Determines if weekly freeze refill should happen.
  /// Returns the new freeze count, or null if no refill needed.
  static int? shouldRefill({
    required DateTime now,
    required String? lastRefillStr,
    required bool isPro,
  }) {
    final daysSinceMonday = (now.weekday - DateTime.monday) % 7;
    final thisMonday = DateTime(now.year, now.month, now.day - daysSinceMonday);
    final thisMondayStr = thisMonday.toIso8601String().substring(0, 10);

    if (lastRefillStr != null && lastRefillStr.compareTo(thisMondayStr) >= 0) {
      return null; // Already refilled this week
    }

    return isPro ? 3 : 1;
  }
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Streak logic
  // ─────────────────────────────────────────────────────────────────────────

  group('Streak Freeze — streak calculation', () {
    test('SF-1: Consecutive day increments streak, no freeze used', () {
      final result = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-07',
        yesterdayStr: '2026-04-06',
        lastWorkoutDate: '2026-04-06', // worked out yesterday
        currentStreakDays: 5,
        freezesAvailable: 1,
        freezeUsedDates: [],
      );

      expect(result['current_streak_days'], equals(6),
          reason: 'Consecutive day should increment streak');
      expect(result['streak_freezes_available'], equals(1),
          reason: 'No freeze should be consumed on consecutive day');
      expect(result['streak_freeze_just_used'], isFalse);
    });

    test('SF-2: Gap with freeze available → freeze consumed, streak continues', () {
      final result = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-07',
        yesterdayStr: '2026-04-06',
        lastWorkoutDate: '2026-04-05', // missed yesterday
        currentStreakDays: 5,
        freezesAvailable: 1,
        freezeUsedDates: [],
      );

      expect(result['current_streak_days'], equals(6),
          reason: 'Streak should continue through freeze');
      expect(result['streak_freezes_available'], equals(0),
          reason: 'One freeze should be consumed');
      expect(result['streak_freeze_just_used'], isTrue);
      expect(result['streak_freeze_used_dates'], contains('2026-04-06'),
          reason: 'Yesterday should be added to freeze used dates');
    });

    test('SF-3: Gap without freeze → streak resets to 1', () {
      final result = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-07',
        yesterdayStr: '2026-04-06',
        lastWorkoutDate: '2026-04-05', // missed yesterday
        currentStreakDays: 5,
        freezesAvailable: 0, // no freezes
        freezeUsedDates: [],
      );

      expect(result['current_streak_days'], equals(1),
          reason: 'Streak should reset to 1 when no freeze available');
      expect(result['streak_freezes_available'], equals(0));
      expect(result['streak_freeze_just_used'], isFalse);
    });

    test('SF-4: Same day double-log → no change', () {
      final result = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-07',
        yesterdayStr: '2026-04-06',
        lastWorkoutDate: '2026-04-07', // already logged today
        currentStreakDays: 5,
        freezesAvailable: 1,
        freezeUsedDates: [],
      );

      expect(result['current_streak_days'], equals(5),
          reason: 'Same-day double log should not change streak');
      expect(result['streak_freezes_available'], equals(1),
          reason: 'Same-day double log should not consume freeze');
    });

    test('SF-5: PRO user with multiple freezes can survive multiple gaps', () {
      // First gap
      final after1st = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-07',
        yesterdayStr: '2026-04-06',
        lastWorkoutDate: '2026-04-05',
        currentStreakDays: 10,
        freezesAvailable: 3,
        freezeUsedDates: [],
      );

      expect(after1st['current_streak_days'], equals(11));
      expect(after1st['streak_freezes_available'], equals(2));

      // Second gap (simulate next day)
      final after2nd = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-09',
        yesterdayStr: '2026-04-08',
        lastWorkoutDate: '2026-04-07',
        currentStreakDays: after1st['current_streak_days'] as int,
        freezesAvailable: after1st['streak_freezes_available'] as int,
        freezeUsedDates: List<String>.from(after1st['streak_freeze_used_dates'] as List),
      );

      // This is actually consecutive (worked out Apr 7, logging Apr 9, yesterday is Apr 8)
      // Wait - lastWorkoutDate is Apr 7, yesterday is Apr 8 — so gap exists
      // Actually: todayStr=Apr9, yesterdayStr=Apr8, lastWorkoutDate=Apr7
      // lastWorkoutDate != todayStr, lastWorkoutDate != yesterdayStr → gap
      expect(after2nd['streak_freezes_available'], equals(1),
          reason: 'Second freeze should be consumed');
      expect(after2nd['current_streak_days'], equals(12),
          reason: 'Streak should continue through second freeze');
    });

    test('SF-6: Zero freezes remaining, gap resets streak', () {
      final result = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-07',
        yesterdayStr: '2026-04-06',
        lastWorkoutDate: '2026-04-04', // 2-day gap
        currentStreakDays: 20,
        freezesAvailable: 0,
        freezeUsedDates: ['2026-04-03'],
      );

      expect(result['current_streak_days'], equals(1),
          reason: 'With 0 freezes, any gap should reset streak');
    });

    test('SF-8: Freeze used dates accumulates correctly', () {
      final result = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-07',
        yesterdayStr: '2026-04-06',
        lastWorkoutDate: '2026-04-05',
        currentStreakDays: 3,
        freezesAvailable: 2,
        freezeUsedDates: ['2026-04-03'], // already one freeze used earlier
      );

      final usedDates = result['streak_freeze_used_dates'] as List<String>;
      expect(usedDates.length, equals(2),
          reason: 'Used dates list should grow by one');
      expect(usedDates, containsAll(['2026-04-03', '2026-04-06']),
          reason: 'Both freeze dates should be tracked');
    });

    test('SF-first-workout: Empty last workout date starts streak at 1', () {
      final result = StreakFreezeCalculator.calculateStreak(
        todayStr: '2026-04-07',
        yesterdayStr: '2026-04-06',
        lastWorkoutDate: '', // first ever workout
        currentStreakDays: 0,
        freezesAvailable: 1,
        freezeUsedDates: [],
      );

      expect(result['current_streak_days'], equals(1),
          reason: 'First workout ever should start streak at 1');
      expect(result['streak_freezes_available'], equals(1),
          reason: 'No freeze should be consumed on first workout');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Weekly refill logic
  // ─────────────────────────────────────────────────────────────────────────

  group('Streak Freeze — weekly refill', () {
    test('SF-7a: Monday triggers refill when no prior refill', () {
      final result = StreakFreezeCalculator.shouldRefill(
        now: DateTime(2026, 4, 6), // Monday
        lastRefillStr: null,
        isPro: false,
      );

      expect(result, equals(1),
          reason: 'FREE user should get 1 freeze on refill');
    });

    test('SF-7b: PRO user gets 3 freezes on refill', () {
      final result = StreakFreezeCalculator.shouldRefill(
        now: DateTime(2026, 4, 6), // Monday
        lastRefillStr: null,
        isPro: true,
      );

      expect(result, equals(3),
          reason: 'PRO user should get 3 freezes on refill');
    });

    test('SF-7c: Already refilled this week → no refill', () {
      final result = StreakFreezeCalculator.shouldRefill(
        now: DateTime(2026, 4, 9), // Thursday
        lastRefillStr: '2026-04-06', // Refilled Monday
        isPro: false,
      );

      expect(result, isNull,
          reason: 'Should not refill if already done this week');
    });

    test('SF-7d: New week triggers refill even on non-Monday', () {
      // User opens app on Wednesday but last refill was last week
      final result = StreakFreezeCalculator.shouldRefill(
        now: DateTime(2026, 4, 8), // Wednesday
        lastRefillStr: '2026-03-30', // Last week Monday
        isPro: false,
      );

      expect(result, equals(1),
          reason: 'Refill should happen on any day if last refill was before this Monday');
    });

    test('SF-7e: Sunday before new Monday → no refill if already refilled', () {
      final result = StreakFreezeCalculator.shouldRefill(
        now: DateTime(2026, 4, 12), // Sunday
        lastRefillStr: '2026-04-06', // Refilled this past Monday
        isPro: false,
      );

      expect(result, isNull,
          reason: 'Sunday in same week should not trigger re-refill');
    });
  });
}
