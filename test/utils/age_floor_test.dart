// OI-305 (2026-10-16): one age floor, 13, for every date-of-birth picker.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/age_floor.dart';

void main() {
  test('the floor is 13, the published policy number', () {
    expect(kMinAgeYears, 13);
  });

  group('latestAllowedDob', () {
    test('is the same day and month 13 years earlier', () {
      expect(latestAllowedDob(DateTime(2026, 10, 16)), DateTime(2013, 10, 16));
      expect(latestAllowedDob(DateTime(2026, 1, 1)), DateTime(2013, 1, 1));
      expect(latestAllowedDob(DateTime(2026, 12, 31)), DateTime(2013, 12, 31));
    });

    test('a person turning 13 today is allowed, one turning 13 tomorrow is '
        'not (the picker rejects a later date)', () {
      final latest = latestAllowedDob(DateTime(2026, 10, 16));
      expect(DateTime(2013, 10, 16).isAfter(latest), isFalse);
      expect(DateTime(2013, 10, 17).isAfter(latest), isTrue);
      expect(DateTime(2013, 10, 15).isAfter(latest), isFalse);
    });

    test('29 February clamps to 28 February, not 1 March (1 March would admit '
        'someone who turns 13 the next day)', () {
      expect(latestAllowedDob(DateTime(2028, 2, 29)), DateTime(2015, 2, 28));
      expect(latestAllowedDob(DateTime(2032, 2, 29)), DateTime(2019, 2, 28));
      expect(
        DateTime(2015, 3, 1).isAfter(latestAllowedDob(DateTime(2028, 2, 29))),
        isTrue,
        reason: 'born 1 March 2015 is 12 on 29 February 2028',
      );
    });

    test('28 February and 1 March in a leap year are plain', () {
      expect(latestAllowedDob(DateTime(2028, 2, 28)), DateTime(2015, 2, 28));
      expect(latestAllowedDob(DateTime(2028, 3, 1)), DateTime(2015, 3, 1));
    });

    test('carries only the date (no clock time), whatever the time of day', () {
      final late = latestAllowedDob(DateTime(2026, 10, 16, 23, 59, 59));
      final early = latestAllowedDob(DateTime(2026, 10, 16, 0, 0, 1));
      expect(late, early);
      expect(late, DateTime(late.year, late.month, late.day));
    });
  });
}
