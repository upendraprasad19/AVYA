// test/home/week_number_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('home_screen WK indicator source (F9)', () {
    test('does NOT use calendar-year math for week number', () {
      final source =
          File('lib/features/home/screens/home_screen.dart').readAsStringSync();

      // Calendar-year math signature: difference from January 1 ÷ 7
      expect(
        source.contains('DateTime(now.year, 1, 1)'),
        false,
        reason:
            'home_screen WK indicator must not derive week number from '
            'difference between today and Jan 1. Use plan-relative '
            'WorkoutScheduleService.getCurrentWeekNumber() instead.',
      );
    });

    test('calls WorkoutScheduleService.getCurrentWeekNumber()', () {
      final source =
          File('lib/features/home/screens/home_screen.dart').readAsStringSync();

      expect(
        source.contains('getCurrentWeekNumber'),
        true,
        reason:
            'home_screen WK indicator must use the canonical plan-relative '
            'week number (WorkoutScheduleService.getCurrentWeekNumber).',
      );
    });
  });
}
