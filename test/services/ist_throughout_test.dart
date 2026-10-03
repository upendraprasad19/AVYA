import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  group('istDateStr', () {
    test('IST 00:30 reads as the IST date, not the UTC prev-day date', () {
      // UTC 19:00 on 2026-05-03 = IST 00:30 on 2026-05-04
      final utcLate = DateTime.utc(2026, 5, 3, 19, 0);
      // istDateStr accepts a DateTime; the IST shift is built into the helper.
      expect(istDateStr(utcLate), '2026-05-04');
    });

    test('IST 23:30 stays on the same IST date even if device clock has rolled over UTC', () {
      // UTC 18:00 on 2026-05-04 = IST 23:30 on 2026-05-04
      final utcEvening = DateTime.utc(2026, 5, 4, 18, 0);
      expect(istDateStr(utcEvening), '2026-05-04');
    });

    test('IST 12:00 noon → expected date', () {
      // UTC 06:30 on 2026-05-04 = IST 12:00 on 2026-05-04
      final utcNoonIST = DateTime.utc(2026, 5, 4, 6, 30);
      expect(istDateStr(utcNoonIST), '2026-05-04');
    });
  });

  group('istNow', () {
    test('returns a DateTime offset from UTC by exactly +5:30', () {
      final before = DateTime.now().toUtc();
      final ist = istNow();
      final after = DateTime.now().toUtc();

      // istNow() should be UTC + 5h30m.
      // Because we can't freeze time, check that the offset is within 1 second
      // of what we'd expect.
      final expectedOffset = const Duration(hours: 5, minutes: 30);
      final diffFromBefore = ist.difference(before);
      final diffFromAfter = ist.difference(after);

      expect(diffFromBefore >= expectedOffset - const Duration(seconds: 1), isTrue);
      expect(diffFromAfter <= expectedOffset + const Duration(seconds: 1), isTrue);
    });
  });

  group('istDateStr boundary conditions', () {
    test('UTC 18:29 (IST 23:59) stays on the current IST day', () {
      // UTC 18:29 = IST 23:59 → still the same IST day
      final utc = DateTime.utc(2026, 5, 4, 18, 29);
      expect(istDateStr(utc), '2026-05-04');
    });

    test('UTC 18:30 (IST 00:00 next day) flips to the next IST day', () {
      // UTC 18:30 = IST 00:00 of the next day
      final utc = DateTime.utc(2026, 5, 4, 18, 30);
      expect(istDateStr(utc), '2026-05-05');
    });

    test('month boundary: UTC 18:30 on 2026-04-30 = IST 00:00 on 2026-05-01', () {
      final utc = DateTime.utc(2026, 4, 30, 18, 30);
      expect(istDateStr(utc), '2026-05-01');
    });

    test('year boundary: UTC 18:30 on 2026-12-31 = IST 00:00 on 2027-01-01', () {
      final utc = DateTime.utc(2026, 12, 31, 18, 30);
      expect(istDateStr(utc), '2027-01-01');
    });
  });
}
