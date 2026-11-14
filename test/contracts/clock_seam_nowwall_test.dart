// Pins the clock-seam contract that the dev-panel time-travel + the
// year-simulation harness depend on (added 2026-05-31, diagnose b7c2d9).
//
// `nowWall()` is the public, seam-aware replacement for `DateTime.now()`.
// Schedule phase-expiry, rank weeks-since-signup, and streak walk-back were
// routed through it so a `setTestClock` override actually moves "today" for
// those reads. This test fails if `nowWall()` stops honoring the override or
// stops matching `DateTime.now()` when reset.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  tearDown(resetTestClock);

  group('nowWall seam', () {
    test('matches DateTime.now() within tolerance when no override', () {
      final a = nowWall();
      final b = DateTime.now();
      expect((a.difference(b)).inSeconds.abs(), lessThanOrEqualTo(2));
      expect(isTestClockActive, isFalse);
    });

    test('honors a fixed test clock override', () {
      final fixed = DateTime(2027, 3, 14, 9, 30);
      setTestClockTo(fixed);
      expect(isTestClockActive, isTrue);
      expect(nowWall(), equals(fixed));
    });

    test('honors a forward-jumping override (year-sim fast-forward)', () {
      final base = DateTime.now();
      setTestClock(() => base.add(const Duration(days: 365)));
      final jumped = nowWall();
      // ~365 days ahead of real now (allow a couple seconds of drift).
      final aheadDays = jumped.difference(DateTime.now()).inDays;
      expect(aheadDays, inInclusiveRange(364, 365));
    });

    test('resetTestClock restores the real wall clock', () {
      setTestClockTo(DateTime(2030, 1, 1));
      resetTestClock();
      expect(isTestClockActive, isFalse);
      expect((nowWall().difference(DateTime.now())).inSeconds.abs(),
          lessThanOrEqualTo(2));
    });

    test('istTodayStr follows the override (IST conversion intact)', () {
      // UTC 2027-06-01 20:00 → IST 2027-06-02 01:30 → next IST day.
      setTestClockTo(DateTime.utc(2027, 6, 1, 20, 0));
      expect(istTodayStr(), '2027-06-02');
    });
  });
}
