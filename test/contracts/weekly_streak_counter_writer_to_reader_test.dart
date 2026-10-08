// Slice D (diagnose b7d3e5, founder decision D5) - the weekly-streak counter
// and its marker.
//
// Defect: completeWorkout stamped `last_streak_week` on EVERY completion, and the
// counter only increments when the week differs from that marker. With 6
// planned workouts (threshold 5) the first session of a week stamped the marker,
// so the qualifying fifth session saw "already counted" and the week never
// counted. Fix: `weeklyStreakAfterCompletion` stamps the marker ONLY when the
// counter increments, and the marker is the CALENDAR week last counted
// (`calendarWeekKey`, the Monday as days since the epoch), because the plan's
// week id is clamped to 1..4 and repeats across phases (B-pass P1).
//
// Writer: lib/features/train/providers/train_provider.dart completeWorkout
//         (the only production writer of `last_counted_week_key`).
// Reader: the same function on the next completion; restore max-merges the
//         counter (UserRepository.mergeCloudProgress) and keeps the marker local.
//
// Run: flutter test test/contracts/weekly_streak_counter_writer_to_reader_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';

({int weeks, int marker}) _after({
  int weeks = 4,
  int marker = 20000,
  int week = 20007,
  int planned = 6,
  bool current = true,
  required int done,
}) =>
    weeklyStreakAfterCompletion(
      streakWeeks: weeks,
      lastCountedWeekKey: marker,
      weekKey: week,
      weekIsCurrent: current,
      planned: planned,
      completedCount: done,
    );

void main() {
  group('weeklyStreakAfterCompletion: the marker is the week LAST COUNTED', () {
    test('a session below the 80% threshold counts nothing and does NOT stamp',
        () {
      final r = _after(done: 1);
      expect(r.weeks, 4);
      expect(r.marker, 20000,
          reason: 'the old stamp-every-time bug wrote the current week here');
    });

    test('the qualifying session counts and stamps the week', () {
      // 6 planned -> ceil(4.8) = 5 sessions.
      final r = _after(done: 5);
      expect(r.weeks, 5);
      expect(r.marker, 20007);
    });

    test('the full sequence of one week counts it exactly once', () {
      var weeks = 4;
      var marker = 20000;
      for (var done = 1; done <= 6; done++) {
        final r = _after(weeks: weeks, marker: marker, done: done);
        weeks = r.weeks;
        marker = r.marker;
      }
      expect(weeks, 5, reason: 'sessions 5 and 6 must not recount the week');
      expect(marker, 20007);
    });

    test('a further session in an already-counted week does not recount', () {
      final r = _after(weeks: 5, marker: 20007, done: 6);
      expect(r.weeks, 5);
      expect(r.marker, 20007);
    });

    test('a restored marker for this week blocks a recount', () {
      final r = _after(weeks: 5, marker: 20007, done: 5);
      expect(r.weeks, 5);
      expect(r.marker, 20007);
    });

    test('the next calendar week counts again from its own qualifying session',
        () {
      final r = _after(weeks: 5, marker: 20007, week: 20014, done: 5);
      expect(r.weeks, 6);
      expect(r.marker, 20014);
    });

    test('B-pass P1: weeks that do not qualify never block a later week, '
        'whatever the plan week id is', () {
      // Counted a week (marker = its Monday). Three weeks pass without a
      // qualifying session. The next qualifying week has a DIFFERENT calendar
      // week, so it counts - the plan id (which could repeat) is not in play.
      var weeks = 4;
      var marker = 20000;
      for (final wk in [20007, 20014, 20021]) {
        final r = _after(weeks: weeks, marker: marker, week: wk, done: 2);
        weeks = r.weeks;
        marker = r.marker;
      }
      expect(weeks, 4);
      expect(marker, 20000);
      final r = _after(weeks: weeks, marker: marker, week: 20028, done: 5);
      expect(r.weeks, 5);
    });

    test('forward-only: the counter never decreases, the marker is one of the '
        'two inputs', () {
      for (var done = 0; done <= 8; done++) {
        final r = _after(weeks: 7, marker: 20000, week: 20007, done: done);
        expect(r.weeks, greaterThanOrEqualTo(7));
        expect(r.marker, anyOf(20000, 20007));
        expect(r.weeks == 8, r.marker == 20007,
            reason: 'the marker moves exactly when the counter does');
      }
    });

    test('a rolled-on plan window (weekIsCurrent false) counts nothing even '
        'when its stale rows read complete', () {
      final r = _after(current: false, done: 6);
      expect(r.weeks, 4);
      expect(r.marker, 20000);
    });

    test('nothing planned counts nothing', () {
      final r = _after(planned: 0, done: 3);
      expect(r.weeks, 4);
      expect(r.marker, 20000);
    });

    test('threshold is ceil(0.8 * planned): 5 of 6, 4 of 5, 1 of 1', () {
      expect(_after(planned: 6, done: 4).weeks, 4);
      expect(_after(planned: 6, done: 5).weeks, 5);
      expect(_after(planned: 5, done: 3).weeks, 4);
      expect(_after(planned: 5, done: 4).weeks, 5);
      expect(_after(planned: 1, done: 1).weeks, 5);
    });

    test('a fresh account (marker -1) counts its first qualifying week', () {
      final r = _after(weeks: 0, marker: -1, week: 20007, planned: 3, done: 3);
      expect(r.weeks, 1);
      expect(r.marker, 20007);
    });
  });

  group('calendarWeekKey: one key per Monday-to-Sunday week, never repeating',
      () {
    test('every day of one week shares a key', () {
      // Monday 2026-10-05 .. Sunday 2026-10-11.
      final keys = {
        for (var d = 5; d <= 11; d++) calendarWeekKey(DateTime(2026, 10, d)),
      };
      expect(keys, hasLength(1));
    });

    test('Sunday and the next Monday differ by exactly 7', () {
      final sunday = calendarWeekKey(DateTime(2026, 10, 11));
      final monday = calendarWeekKey(DateTime(2026, 10, 12));
      expect(monday - sunday, 7);
    });

    test('consecutive weeks differ by 7 across a month, a year and a leap day',
        () {
      for (final start in [
        DateTime(2026, 10, 26), // month rollover
        DateTime(2026, 12, 28), // year rollover
        DateTime(2028, 2, 28), // leap day inside the week
      ]) {
        final a = calendarWeekKey(start);
        final b = calendarWeekKey(start.add(const Duration(days: 7)));
        expect(b - a, 7, reason: '$start');
      }
    });

    test('the time of day does not move the key', () {
      expect(calendarWeekKey(DateTime(2026, 10, 7, 0, 5)),
          calendarWeekKey(DateTime(2026, 10, 7, 23, 55)));
    });

    test('the key is the Monday as days since the epoch', () {
      // 2026-10-05 is a Monday; Date.UTC(2026, 9, 5) / 86400000 = 20731.
      expect(calendarWeekKey(DateTime(2026, 10, 5)), 20731);
      expect(calendarWeekKey(DateTime(2026, 10, 9)), 20731);
    });
  });

  group('wiring (PRESENCE only - the behaviour is above)', () {
    test('completeWorkout uses the function and no longer stamps unconditionally',
        () {
      final src = File('lib/features/train/providers/train_provider.dart')
          .readAsStringSync();
      final stripped = src
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
          .join('\n');
      expect(stripped.contains('weeklyStreakAfterCompletion('), isTrue);
      expect(stripped.contains("'last_counted_week_key': weekly.marker"), isTrue);
      expect(stripped.contains("'current_streak_weeks': weekly.weeks"), isTrue);
      expect(stripped.contains('weekKey: streakWeek.weekKey'), isTrue);
      expect(
          stripped.contains('weekIsCurrent: streakWeek.weekIsCurrent'), isTrue);
      expect(stripped.contains("'last_streak_week':"), isFalse,
          reason: 'the old per-completion stamp is the bug');
    });
  });
}
