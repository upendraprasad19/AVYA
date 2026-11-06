// test/contracts/ist_clock_override_test.dart
//
// Pins the injectable clock seam (Phase B1, audit-2026-05-29 batch).
//
// The dev panel + headless year-sim harness fast-forward "now" via
// setTestClock / setTestClockTo. This test guarantees:
//   1. Default (no override) istNow() tracks the real wall clock.
//   2. An override flows through istNow() AND istTodayStr() (the day-key
//      entry point) WITHOUT double-applying the +5:30 IST offset.
//   3. resetTestClock restores the real clock.
//   4. The override is observable via isTestClockActive.
//
// Pure unit test — no Hive / Flutter binding required.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  // Always restore the real clock after each test so a leaked override
  // can't contaminate other suites that share the process.
  tearDown(resetTestClock);

  group('IST clock override seam', () {
    test('default: no override active, istNow tracks real wall clock', () {
      expect(isTestClockActive, isFalse);
      final expectedIst = DateTime.now().toUtc().add(
            const Duration(hours: 5, minutes: 30),
          );
      final diff = istNow().difference(expectedIst).abs();
      expect(diff.inSeconds, lessThan(5),
          reason: 'istNow() must equal real now + 5:30 within tolerance');
    });

    test('setTestClockTo freezes istNow at fixed instant + IST offset', () {
      // A UTC instant plays the role of DateTime.now().
      final fixed = DateTime.utc(2027, 3, 15, 6, 0, 0);
      setTestClockTo(fixed);

      expect(isTestClockActive, isTrue);
      // istNow = fixed (as UTC) + 5:30 = 2027-03-15 11:30 IST wall clock.
      final ist = istNow();
      expect(ist.year, 2027);
      expect(ist.month, 3);
      expect(ist.day, 15);
      expect(ist.hour, 11);
      expect(ist.minute, 30);
    });

    test('istTodayStr honors override WITHOUT double-shifting the offset',
        () {
      // 2027-03-15 18:00 UTC -> +5:30 -> 2027-03-15 23:30 IST -> same date.
      setTestClockTo(DateTime.utc(2027, 3, 15, 18, 0, 0));
      expect(istTodayStr(), '2027-03-15');

      // 2027-03-15 20:00 UTC -> +5:30 -> 2027-03-16 01:30 IST -> next date.
      setTestClockTo(DateTime.utc(2027, 3, 15, 20, 0, 0));
      expect(istTodayStr(), '2027-03-16',
          reason: 'IST rollover past 18:30 UTC must advance the date once '
              '(no double offset).');
    });

    test('fast-forward by a year advances istTodayStr predictably', () {
      setTestClockTo(DateTime.utc(2027, 1, 1, 0, 0, 0));
      expect(istTodayStr(), '2027-01-01');
      setTestClockTo(DateTime.utc(2028, 1, 1, 0, 0, 0));
      expect(istTodayStr(), '2028-01-01');
    });

    test('resetTestClock restores the real clock', () {
      setTestClockTo(DateTime.utc(2027, 1, 1));
      expect(isTestClockActive, isTrue);
      resetTestClock();
      expect(isTestClockActive, isFalse);
      final diff = istNow()
          .difference(DateTime.now().toUtc().add(
                const Duration(hours: 5, minutes: 30),
              ))
          .abs();
      expect(diff.inSeconds, lessThan(5));
    });
  });
}
