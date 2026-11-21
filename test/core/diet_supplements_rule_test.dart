// test/core/diet_supplements_rule_test.dart
//
// Diet plan Unit 4a (docs/plans/diet-supplements.md section 2): the ONE rule
// for "Supplements are active", the age read it needs, and the push entry.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/diet_supplements_rule.dart';

void main() {
  final now = DateTime(2026, 11, 15);

  group('ageYearsOn', () {
    test('whole years, by month and day', () {
      expect(ageYearsOn('2008-11-15', now), 18); // 18th birthday today
      expect(ageYearsOn('2008-11-16', now), 17); // tomorrow
      expect(ageYearsOn('1998-01-01', now), 28);
    });

    test('a time part and surrounding spaces are tolerated', () {
      expect(ageYearsOn('2000-06-01T10:20:30.000', now), 26);
      expect(ageYearsOn(' 2000-06-01 ', now), 26);
    });

    test('a 29 February birthday counts as 1 March in a year without one', () {
      expect(ageYearsOn('2008-02-29', DateTime(2026, 2, 28)), 17);
      expect(ageYearsOn('2008-02-29', DateTime(2026, 3, 1)), 18);
    });

    test('unreadable values are null (never adult)', () {
      for (final v in <Object?>[
        null,
        '',
        '   ',
        'garbage',
        '2000-13-01',
        '2000-02-30',
        '2030-01-01', // the future
        '1800-01-01', // implausible
        20000101,
        DateTime(2000),
      ]) {
        expect(ageYearsOn(v, now), isNull, reason: '$v');
      }
    });
  });

  group('dietSupplementsEligible', () {
    test('needs the flag and an adult date of birth', () {
      expect(
          dietSupplementsEligible(
              profile: {'date_of_birth': '1998-01-01'},
              enabled: true,
              now: now),
          isTrue);
      expect(
          dietSupplementsEligible(
              profile: {'date_of_birth': '1998-01-01'},
              enabled: false,
              now: now),
          isFalse);
      expect(
          dietSupplementsEligible(
              profile: {'date_of_birth': '2010-01-01'},
              enabled: true,
              now: now),
          isFalse,
          reason: 'a minor');
      expect(dietSupplementsEligible(profile: {}, enabled: true, now: now),
          isFalse,
          reason: 'no date of birth');
      expect(dietSupplementsEligible(profile: null, enabled: true, now: now),
          isFalse);
    });
  });

  group('dietSupplementsActive: every clause is needed', () {
    const adult = '1998-01-01';
    bool active({
      Object? sw = true,
      Object? dob = adult,
      bool pro = true,
      bool enabled = true,
    }) =>
        dietSupplementsActive(
            profile: {'diet_supplements': sw, 'date_of_birth': dob},
            pro: pro,
            enabled: enabled,
            now: now);

    test('all clauses true', () => expect(active(), isTrue));
    test('not PRO', () => expect(active(pro: false), isFalse));
    test('flag off', () => expect(active(enabled: false), isFalse));
    test('switch off', () => expect(active(sw: false), isFalse));
    test('switch absent', () => expect(active(sw: null), isFalse));
    test('switch is not a bool', () {
      expect(active(sw: 'true'), isFalse);
      expect(active(sw: 1), isFalse);
    });
    test('a minor', () => expect(active(dob: '2010-01-01'), isFalse));
    test('the day before the 18th birthday is still a minor', () {
      // now is 2026-11-15: 2008-11-16 is 17 years 364 days, 2008-11-15 is 18.
      expect(active(dob: '2008-11-16'), isFalse);
      expect(active(dob: '2008-11-15'), isTrue);
    });
    test('no date of birth', () => expect(active(dob: null), isFalse));
    test('a null profile', () {
      expect(
          dietSupplementsActive(
              profile: null, pro: true, enabled: true, now: now),
          isFalse);
    });
  });

  group('dietSupplementsPushEntry', () {
    test('a stored bool is pushed, false included', () {
      expect(
          dietSupplementsPushEntry({'diet_supplements': true}, enabled: true),
          {'diet_supplements': true});
      expect(
          dietSupplementsPushEntry({'diet_supplements': false}, enabled: true),
          {'diet_supplements': false});
    });

    test('absent, non-bool or flag off: no entry', () {
      expect(dietSupplementsPushEntry({}, enabled: true), isEmpty);
      expect(dietSupplementsPushEntry({'diet_supplements': null}, enabled: true),
          isEmpty);
      expect(
          dietSupplementsPushEntry({'diet_supplements': 'true'}, enabled: true),
          isEmpty);
      expect(
          dietSupplementsPushEntry({'diet_supplements': true}, enabled: false),
          isEmpty);
    });
  });
}
