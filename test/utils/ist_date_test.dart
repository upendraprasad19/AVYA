import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  group('istDateOf', () {
    test('UTC midnight → IST 05:30 same day', () {
      final utcMidnight = DateTime.utc(2026, 5, 1, 0, 0, 0);
      final ist = istDateOf(utcMidnight);
      expect(ist.year, 2026);
      expect(ist.month, 5);
      expect(ist.day, 1);
      expect(ist.hour, 5);
      expect(ist.minute, 30);
    });

    test('UTC 18:30 → IST 00:00 next day (date rollover)', () {
      final utc = DateTime.utc(2026, 4, 30, 18, 30, 0);
      final ist = istDateOf(utc);
      expect(ist.year, 2026);
      expect(ist.month, 5);
      expect(ist.day, 1);
      expect(ist.hour, 0);
      expect(ist.minute, 0);
    });
  });

  group('istDateStr', () {
    test('formats as YYYY-MM-DD with zero-padding', () {
      final t = DateTime.utc(2026, 1, 5, 0, 0, 0);
      expect(istDateStr(t), '2026-01-05');
    });

    test('respects the IST date rollover at UTC 18:30', () {
      final justBefore = DateTime.utc(2026, 4, 30, 18, 29, 0);
      final justAfter = DateTime.utc(2026, 4, 30, 18, 31, 0);
      expect(istDateStr(justBefore), '2026-04-30');
      expect(istDateStr(justAfter), '2026-05-01');
    });
  });

  group('istMidnight', () {
    test('strips time of day and returns IST 00:00', () {
      final t = DateTime.utc(2026, 5, 1, 7, 23, 45);  // → IST 12:53:45 May 1
      final mid = istMidnight(t);
      expect(mid.year, 2026);
      expect(mid.month, 5);
      expect(mid.day, 1);
      expect(mid.hour, 0);
      expect(mid.minute, 0);
      expect(mid.second, 0);
    });
  });

  group('istMidnightUtc', () {
    test('IST midnight maps to UTC 18:30 previous day', () {
      // IST midnight of 2026-05-01 = UTC 2026-04-30 18:30
      final t = DateTime.utc(2026, 5, 1, 7, 0, 0); // mid-day on May 1 IST
      final utcMid = istMidnightUtc(t);
      expect(utcMid.isUtc, true);
      expect(utcMid.year, 2026);
      expect(utcMid.month, 4);
      expect(utcMid.day, 30);
      expect(utcMid.hour, 18);
      expect(utcMid.minute, 30);
    });
  });

  group('mondayOfIst / sundayOfIst', () {
    test('Wednesday 2026-04-29 → Monday 2026-04-27 / Sunday 2026-05-03', () {
      final wed = DateTime.utc(2026, 4, 29, 6, 0, 0);  // IST 11:30
      final mon = mondayOfIst(wed);
      final sun = sundayOfIst(wed);
      expect(mon.year, 2026);
      expect(mon.month, 4);
      expect(mon.day, 27);
      expect(sun.year, 2026);
      expect(sun.month, 5);
      expect(sun.day, 3);
    });

    test('Monday returns itself; Sunday returns +6 days', () {
      final mon = DateTime.utc(2026, 4, 27, 0, 0, 0);
      // 2026-04-27 UTC 00:00 → IST 05:30 same day (Monday)
      expect(mondayOfIst(mon).day, 27);
      expect(sundayOfIst(mon).day, 3);  // May 3
      expect(sundayOfIst(mon).month, 5);
    });

    test('Sunday wraps to Monday of SAME week (not next)', () {
      final sun = DateTime.utc(2026, 5, 3, 12, 0, 0);
      final mon = mondayOfIst(sun);
      expect(mon.day, 27);
      expect(mon.month, 4);
    });
  });

  group('isSameIstDate', () {
    test('two times in same IST day are equal', () {
      final a = DateTime.utc(2026, 5, 1, 1, 0, 0);   // IST 06:30 May 1
      final b = DateTime.utc(2026, 5, 1, 17, 0, 0);  // IST 22:30 May 1
      expect(isSameIstDate(a, b), true);
    });

    test('rollover boundary returns false', () {
      final a = DateTime.utc(2026, 4, 30, 18, 29, 0);  // IST 23:59 Apr 30
      final b = DateTime.utc(2026, 4, 30, 18, 31, 0);  // IST 00:01 May 1
      expect(isSameIstDate(a, b), false);
    });
  });
}
