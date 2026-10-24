// L2b Landing C: the pure row builder of the Progress comparison card.
//
// Every expected string is a literal: a test that builds its expectation from
// MeasurementCopy would pass with the copy wrong. Dates are literals and
// `todayIst` is a parameter of the function under test, so no row reads the
// device clock and none goes red with the calendar (a 2031 "today" is used
// where the year rule is exercised, a year the real clock has not reached).
@Timeout(Duration(seconds: 60))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/measurement_copy.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/features/profile/services/measurement_card_rules.dart';

MeasurementEntry e(String date, Map<String, double> sites) =>
    MeasurementEntry(date: date, sites: sites);

List<MeasurementCardRow> rows(
  List<MeasurementEntry> entries, {
  bool inches = false,
  String today = '2026-10-12',
}) => measurementCardRows(entries: entries, inches: inches, todayIst: today);

MeasurementCardRow only(List<MeasurementCardRow> r, String site) =>
    r.singleWhere((x) => x.site == site);

void main() {
  group('which tiles exist and in what order', () {
    test('no history gives no tiles', () {
      expect(rows(const []), isEmpty);
    });

    test(
      "tiles follow the registry's order whatever the entries' order is",
      () {
        final r = rows([
          e('2026-10-09', {'arms': 33.0, 'chest': 95.0}),
          e('2026-10-01', {'hips': 97.0, 'waist': 80.0}),
        ]);
        expect(r.map((x) => x.site).toList(), [
          'chest',
          'waist',
          'hips',
          'arms',
        ]);
      },
    );

    test('a site never measured has no tile (no placeholder)', () {
      final r = rows([
        e('2026-10-09', {'waist': 81.0}),
      ]);
      expect(r.map((x) => x.site).toList(), ['waist']);
    });

    test('labels come from the spec table', () {
      final r = rows([
        e('2026-10-09', {
          'chest': 95.0,
          'waist': 81.0,
          'hips': 97.0,
          'arms': 33.0,
        }),
      ]);
      expect(r.map((x) => x.label).toList(), [
        'Chest',
        'Waist',
        'Hips',
        'Arms',
      ]);
    });
  });

  group('the change is measured from the FIRST entry holding the site', () {
    test(
      'three entries: first holder, not the previous one, not the newest',
      () {
        final r = rows([
          e('2026-10-09', {'waist': 77.0}),
          e('2026-10-03', {'waist': 79.0}),
          e('2026-09-12', {'waist': 81.0}),
        ]);
        final waist = only(r, 'waist');
        expect(waist.valueText, '77.0 cm');
        // From 81.0 (the first), not from 79.0 (the previous entry).
        expect(waist.deltaText, '-4.0 cm since 12 Sep');
        expect(waist.delta, -4.0);
        expect(waist.firstDate, '2026-09-12');
      },
    );

    test(
      'a site absent from the oldest entry is measured from its first holder',
      () {
        final r = rows([
          e('2026-10-09', {'waist': 77.0, 'arms': 34.0}),
          e('2026-10-03', {'waist': 79.0, 'arms': 33.0}),
          e('2026-09-12', {'waist': 81.0}),
        ]);
        expect(only(r, 'waist').deltaText, '-4.0 cm since 12 Sep');
        expect(only(r, 'arms').deltaText, '+1.0 cm since 3 Oct');
      },
    );

    test('a site held on one day only has no change line at all', () {
      final r = rows([
        e('2026-10-09', {'waist': 81.0}),
        e('2026-10-03', {'chest': 95.0}),
      ]);
      expect(only(r, 'waist').deltaText, isNull);
      expect(only(r, 'waist').delta, isNull);
      expect(only(r, 'waist').firstDate, isNull);
      expect(only(r, 'chest').deltaText, isNull);
    });

    test('a single entry has no change line on any tile', () {
      final r = rows([
        e('2026-10-09', {
          'chest': 95.0,
          'waist': 81.0,
          'hips': 97.0,
          'arms': 33.0,
        }),
      ]);
      expect(r.map((x) => x.deltaText), everyElement(isNull));
    });

    test('two entries on the SAME day count as one day: no change line', () {
      final r = rows([
        e('2026-10-09', {'waist': 81.0}),
        e('2026-10-09', {'waist': 80.0}),
      ]);
      expect(only(r, 'waist').deltaText, isNull);
    });
  });

  group('sign and "no change"', () {
    test('an increase has a plus, a decrease a minus', () {
      final up = rows([
        e('2026-10-09', {'waist': 82.5}),
        e('2026-09-12', {'waist': 81.0}),
      ]);
      expect(only(up, 'waist').deltaText, '+1.5 cm since 12 Sep');
      final down = rows([
        e('2026-10-09', {'waist': 79.5}),
        e('2026-09-12', {'waist': 81.0}),
      ]);
      expect(only(down, 'waist').deltaText, '-1.5 cm since 12 Sep');
    });

    test('equal values on different days read "no change", never 0.0', () {
      final r = rows([
        e('2026-10-09', {'waist': 81.0}),
        e('2026-09-12', {'waist': 81.0}),
      ]);
      expect(only(r, 'waist').deltaText, 'no change since 12 Sep');
      expect(only(r, 'waist').delta, 0.0);
    });

    test('negative zero reads "no change" (builder level)', () {
      expect(
        MeasurementCopy.cardDeltaLine(
          -0.0,
          inches: false,
          shortFirstDate: '12 Sep',
        ),
        'no change since 12 Sep',
      );
      expect(
        MeasurementCopy.cardDeltaLine(
          0.0,
          inches: true,
          shortFirstDate: '12 Sep',
        ),
        'no change since 12 Sep',
      );
    });
  });

  group('the unit: the change is the difference of the DISPLAYED numbers', () {
    // These pairs separate the two rules. 79.6 cm shows 31.3 in and 80.9 cm
    // shows 31.9 in; converting the 1.3 cm difference instead would give +0.5.
    test(
      '79.6 -> 80.9 cm is 31.3 -> 31.9 in, +0.6 (the wrong rule gives +0.5)',
      () {
        final cm = rows([
          e('2026-10-09', {'waist': 80.9}),
          e('2026-09-12', {'waist': 79.6}),
        ]);
        expect(only(cm, 'waist').valueText, '80.9 cm');
        expect(only(cm, 'waist').deltaText, '+1.3 cm since 12 Sep');
        expect(only(cm, 'waist').delta, 1.3);
        final inch = rows([
          e('2026-10-09', {'waist': 80.9}),
          e('2026-09-12', {'waist': 79.6}),
        ], inches: true);
        expect(only(inch, 'waist').valueText, '31.9 in');
        expect(only(inch, 'waist').deltaText, '+0.6 in since 12 Sep');
        // The numbers behind the text, exactly: a delta left unrounded is
        // 0.5999999999999979 and prints the same, so only the number tells.
        expect(only(inch, 'waist').delta, 0.6);
        expect(only(inch, 'waist').value, 31.9);
        expect(only(inch, 'waist').latestDate, '2026-10-09');
        expect(only(inch, 'waist').firstDate, '2026-09-12');
      },
    );

    test(
      '79.8 -> 79.9 cm is 31.4 -> 31.5 in, +0.1 (the wrong rule gives 0.0)',
      () {
        final inch = rows([
          e('2026-10-09', {'waist': 79.9}),
          e('2026-09-12', {'waist': 79.8}),
        ], inches: true);
        expect(only(inch, 'waist').valueText, '31.5 in');
        expect(only(inch, 'waist').deltaText, '+0.1 in since 12 Sep');
        expect(only(inch, 'waist').delta, 0.1);
        final cm = rows([
          e('2026-10-09', {'waist': 79.9}),
          e('2026-09-12', {'waist': 79.8}),
        ]);
        expect(only(cm, 'waist').deltaText, '+0.1 cm since 12 Sep');
      },
    );

    test(
      '79.4 -> 79.5 cm both show 31.3 in: inches say no change, cm +0.1',
      () {
        final inch = rows([
          e('2026-10-09', {'waist': 79.5}),
          e('2026-09-12', {'waist': 79.4}),
        ], inches: true);
        expect(only(inch, 'waist').valueText, '31.3 in');
        expect(only(inch, 'waist').deltaText, 'no change since 12 Sep');
        expect(only(inch, 'waist').delta, 0.0);
        final cm = rows([
          e('2026-10-09', {'waist': 79.5}),
          e('2026-09-12', {'waist': 79.4}),
        ]);
        expect(only(cm, 'waist').deltaText, '+0.1 cm since 12 Sep');
      },
    );

    test('a decrease in inches', () {
      final inch = rows([
        e('2026-10-09', {'waist': 79.5}),
        e('2026-09-12', {'waist': 81.0}),
      ], inches: true);
      expect(only(inch, 'waist').valueText, '31.3 in');
      expect(only(inch, 'waist').deltaText, '-0.6 in since 12 Sep');
      expect(only(inch, 'waist').delta, -0.6);
    });

    test('chest 60.0 cm prints 23.6 in and arms 70.0 cm prints 27.6 in (the '
        'stated residual: figures the sheet would refuse if typed)', () {
      final r = rows([
        e('2026-10-09', {'chest': 60.0, 'arms': 70.0}),
      ], inches: true);
      expect(only(r, 'chest').valueText, '23.6 in');
      expect(only(r, 'arms').valueText, '27.6 in');
    });

    test('the same entries in centimetres print centimetres', () {
      final r = rows([
        e('2026-10-09', {'chest': 60.0, 'arms': 70.0}),
      ]);
      expect(only(r, 'chest').valueText, '60.0 cm');
      expect(only(r, 'arms').valueText, '70.0 cm');
      expect(r.map((x) => x.inches), everyElement(isFalse));
    });
  });

  group('dates carry their year only when it is not the current IST year', () {
    // today = 2031-04-15 (a year the real clock has not reached): a mutant that
    // asks the device clock for "this year" would print the year on every
    // 2031 date and fail the first two expectations.
    const today = '2031-04-15';
    test('a 2031 date has no year, a 2030 date has one', () {
      final r = rows([
        e('2031-03-02', {'waist': 79.0}),
        e('2030-12-30', {'waist': 81.0}),
      ], today: today);
      final waist = only(r, 'waist');
      expect(waist.titleText, 'WAIST · 2 Mar');
      expect(waist.deltaText, '-2.0 cm since 30 Dec 2030');
    });

    // The FIRST entry's date has its own year decision (a separate call for the
    // short date and for the spoken one): both directions, under a "today" the
    // real clock has not reached, so a call that used a fixed or device year in
    // its place is caught on each side.
    test('the first entry\'s date: a date in the current year has no year, in '
        'another year it has one, in the line and in the sentence', () {
      final same = only(
        rows([
          e('2031-03-02', {'waist': 79.0}),
          e('2031-01-05', {'waist': 81.0}),
        ], today: today),
        'waist',
      );
      expect(same.deltaText, '-2.0 cm since 5 Jan');
      expect(same.semanticsLabel, endsWith('since 5 January.'));
      final other = only(
        rows([
          e('2031-03-02', {'waist': 79.0}),
          e('2026-12-30', {'waist': 81.0}),
        ], today: today),
        'waist',
      );
      expect(other.deltaText, '-2.0 cm since 30 Dec 2026');
      expect(other.semanticsLabel, endsWith('since 30 December 2026.'));
    });

    test(
      'the long date in the screen-reader sentence follows the same rule',
      () {
        final r = rows([
          e('2031-03-02', {'waist': 79.0}),
          e('2030-12-30', {'waist': 81.0}),
        ], today: today);
        expect(
          only(r, 'waist').semanticsLabel,
          'Waist, 79.0 centimetres, measured 2 March. '
          'Down 2.0 centimetres since 30 December 2030.',
        );
      },
    );
  });

  group('the strings of a tile (literals)', () {
    test('tile title, value and change line, in centimetres', () {
      final r = rows([
        e('2026-10-03', {'waist': 79.5}),
        e('2026-09-12', {'waist': 78.0}),
      ]);
      final waist = only(r, 'waist');
      expect(waist.titleText, 'WAIST · 3 Oct');
      expect(waist.valueText, '79.5 cm');
      expect(waist.deltaText, '+1.5 cm since 12 Sep');
    });

    test('semantics: one entry', () {
      final r = rows([
        e('2026-10-03', {'waist': 79.5}),
      ]);
      expect(
        only(r, 'waist').semanticsLabel,
        'Waist, 79.5 centimetres, measured 3 October.',
      );
    });

    test('semantics: increase, decrease and zero', () {
      final up = rows([
        e('2026-10-03', {'waist': 79.5}),
        e('2026-09-12', {'waist': 78.0}),
      ]);
      expect(
        only(up, 'waist').semanticsLabel,
        'Waist, 79.5 centimetres, measured 3 October. '
        'Up 1.5 centimetres since 12 September.',
      );
      final down = rows([
        e('2026-10-03', {'waist': 78.0}),
        e('2026-09-12', {'waist': 79.5}),
      ]);
      expect(
        only(down, 'waist').semanticsLabel,
        'Waist, 78.0 centimetres, measured 3 October. '
        'Down 1.5 centimetres since 12 September.',
      );
      final zero = rows([
        e('2026-10-03', {'waist': 79.5}),
        e('2026-09-12', {'waist': 79.5}),
      ]);
      expect(
        only(zero, 'waist').semanticsLabel,
        'Waist, 79.5 centimetres, measured 3 October. '
        'No change since 12 September.',
      );
    });

    test('semantics: inches', () {
      final r = rows([
        e('2026-10-03', {'waist': 80.9}),
        e('2026-09-12', {'waist': 79.6}),
      ], inches: true);
      expect(
        only(r, 'waist').semanticsLabel,
        'Waist, 31.9 inches, measured 3 October. '
        'Up 0.6 inches since 12 September.',
      );
    });

    test('the visible text and the spoken sentence never use the word '
        '"snapshot"', () {
      final r = rows([
        e('2026-10-03', {'waist': 79.5, 'chest': 95.0}),
        e('2026-09-12', {'waist': 78.0, 'chest': 96.0}),
      ]);
      for (final row in r) {
        for (final text in [
          row.titleText,
          row.valueText,
          row.deltaText ?? '',
          row.semanticsLabel,
        ]) {
          expect(text.toLowerCase(), isNot(contains('snapshot')));
        }
      }
    });
  });
}
