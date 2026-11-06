// APK Test #12 / Task A-1 — pins the IST contract on `formatDateKey`.
//
// Pre-Test-#12 the helper extracted year/month/day from the input
// DateTime directly (UTC for UTC inputs, local for local inputs).
// That disagreed with `WorkoutWriteService.istDateStr` around midnight
// IST and caused the "May 4 receipt shows May 5 exercises" bug observed
// in APK 11.1. The helper now delegates to `istDateStr`, so reads via
// `formatDateKey` and writes via `istDateStr` always agree.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/date_utils.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  group('formatDateKey is IST-aware (APK Test #12 / Task A-1)', () {
    test('UTC 20:00 May 4 → IST 01:30 May 5 → "2026-05-05"', () {
      final t = DateTime.utc(2026, 5, 4, 20, 0);
      expect(formatDateKey(t), '2026-05-05');
    });

    test('UTC 18:30 May 4 = IST midnight → IST date is May 5', () {
      final t = DateTime.utc(2026, 5, 4, 18, 30);
      expect(formatDateKey(t), '2026-05-05');
    });

    test('UTC 18:29 May 4 = IST 23:59 May 4 → "2026-05-04"', () {
      final t = DateTime.utc(2026, 5, 4, 18, 29);
      expect(formatDateKey(t), '2026-05-04');
    });

    test('agrees with istDateStr for arbitrary UTC inputs', () {
      final samples = [
        DateTime.utc(2026, 1, 1, 0, 0),
        DateTime.utc(2026, 5, 6, 18, 30),
        DateTime.utc(2026, 12, 31, 23, 59),
        DateTime.utc(2027, 3, 1, 12, 0),
      ];
      for (final t in samples) {
        expect(formatDateKey(t), istDateStr(t),
            reason: 'formatDateKey must match istDateStr for $t');
      }
    });

    test('agrees with istDateStr for local DateTime', () {
      // DateTime.now() is device-local. On any device, the helper must
      // return the IST date — not the local-time date.
      final t = DateTime.now();
      expect(formatDateKey(t), istDateStr(t));
    });
  });
}
