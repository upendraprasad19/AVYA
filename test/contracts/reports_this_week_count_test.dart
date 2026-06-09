// Regression contract for APK +34 / obs 2 (diagnose c2e8b4): the Weekly Report
// "This Week" summary tile must show the CURRENT-WEEK workout count, not the
// lifetime `user_progress.total_workouts_done`. The trusted data source is
// WorkoutRepository.getWeeklyWorkoutCounts() (index 0 = this week — the same
// source the frequency chart's "This Week" bar already uses). The day-streak
// value must be labeled 'd' (days), not 'w' (it is the live day walk-back, the
// same value Home renders as "N DAYS").
//
// Source-grep (presence-only) over the reader binding — the underlying weekly
// count is pinned behaviorally by the workout-repository tests; this guards the
// reader from regressing back to the lifetime field
// (feedback_source_grep_false_confidence).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  final src = _strip(
      File('lib/features/profile/screens/reports_screen.dart').readAsStringSync());

  group('reports "This Week" tile binds to the weekly count, not lifetime', () {
    test('Workouts value is the current-week count', () {
      expect(src.contains('getWeeklyWorkoutCounts'), isTrue);
      expect(src.contains('thisWeekWorkouts'), isTrue,
          reason: 'the summary tile must use the this-week count');
      expect(src.contains(r"'Workouts', '${stats.totalWorkouts}'"), isFalse,
          reason: 'lifetime total_workouts_done must not back the "This Week" tile');
    });

    test('streak is labeled days (d), not weeks (w)', () {
      expect(src.contains(r"'${stats.currentStreak}w'"), isFalse,
          reason: 'currentStreak is the live DAY walk-back; "w" mislabels it');
      expect(src.contains(r"'${stats.currentStreak}d'"), isTrue);
    });
  });
}
