// L2b Landing B (B4) - the pure unit helpers of the measurements sheet and the
// copy on the spec table. Probe values are LITERALS, never read from
// kBodyMeasurementSpecs or from the helper under test: a table that reads the
// code it checks follows a moved bound and its mutant stays green.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/body_measurement_sites.dart';
import 'package:icanbefitter/core/constants/body_measurement_specs.dart';
import 'package:icanbefitter/core/utils/measurement_units.dart';

void main() {
  group('inchBoundsFor', () {
    // (site, min, max) in inches - the accepted 0.1-inch range, derived by hand:
    // 23.7 in = 60.198 cm -> 60.2 (valid), 23.6 in = 59.944 cm -> 59.9 (below).
    const expected = <(String, double, double)>[
      ('chest', 23.7, 78.7),
      ('waist', 19.7, 78.7),
      ('hips', 23.7, 78.7),
      ('arms', 7.9, 27.5),
    ];
    for (final e in expected) {
      test('${e.$1}: ${e.$2}-${e.$3} in, each printed bound accepted and the '
          'next 0.1 in beyond it rejected', () {
        final b = inchBoundsFor(e.$1);
        expect(b.min, e.$2);
        expect(b.max, e.$3);
        expect(isValidBodyMeasurementCm(e.$1, cmFromInches(b.min)), isTrue);
        expect(isValidBodyMeasurementCm(e.$1, cmFromInches(b.max)), isTrue);
        expect(
          isValidBodyMeasurementCm(
            e.$1,
            cmFromInches(double.parse((b.min - 0.1).toStringAsFixed(1))),
          ),
          isFalse,
        );
        expect(
          isValidBodyMeasurementCm(
            e.$1,
            cmFromInches(double.parse((b.max + 0.1).toStringAsFixed(1))),
          ),
          isFalse,
        );
      });
    }

    test('an unknown site throws ArgumentError', () {
      expect(() => inchBoundsFor('thigh'), throwsArgumentError);
      expect(() => inchBoundsFor(''), throwsArgumentError);
    });
  });

  group('cmFromInches / inchesFromCm', () {
    const toCm = <(double, double)>[
      (26, 66.0),
      (49, 124.5),
      (78.7, 199.9),
      (78.8, 200.2),
      (31.5, 80.0),
      (23.6, 59.9),
      (23.7, 60.2),
      (27.6, 70.1),
      (75, 190.5),
    ];
    for (final r in toCm) {
      test('${r.$1} in -> ${r.$2} cm', () => expect(cmFromInches(r.$1), r.$2));
    }
    const toIn = <(double, double)>[
      (190.5, 75.0),
      (66.0, 26.0),
      (80.0, 31.5),
      (60.0, 23.6),
      (70.0, 27.6),
    ];
    for (final r in toIn) {
      test('${r.$1} cm -> ${r.$2} in', () => expect(inchesFromCm(r.$1), r.$2));
    }
  });

  group('parseMeasurementInput', () {
    test(
      'null for blank, a lone dot and the non-finite strings, in both units',
      () {
        for (final text in [
          '',
          ' ',
          '.',
          'NaN',
          'Infinity',
          '-Infinity',
          '1e999',
        ]) {
          expect(
            parseMeasurementInput(text, metric: true),
            isNull,
            reason: "'$text' cm",
          );
          expect(
            parseMeasurementInput(text, metric: false),
            isNull,
            reason: "'$text' in",
          );
        }
      },
    );

    // The two non-finite guards are NOT redundant: a FINITE text whose inch
    // conversion overflows (1e308 * 2.54) passes the first guard and is stopped
    // only by the second (B-pass reviewer B, finding 11).
    test('a finite text whose inch conversion overflows is null in inches', () {
      expect(double.parse('1e308').isFinite, isTrue, reason: 'premise');
      expect(
        (double.parse('1e308') * 2.54).isFinite,
        isFalse,
        reason: 'premise',
      );
      expect(parseMeasurementInput('1e308', metric: false), isNull);
    });

    test(
      'numeric rows carry their expected value, and the parse is bounds-free',
      () {
        expect(parseMeasurementInput('5.', metric: true), 5.0);
        expect(parseMeasurementInput('5.', metric: false), 12.7);
        expect(parseMeasurementInput('.5', metric: true), 0.5);
        expect(parseMeasurementInput('.5', metric: false), 1.3);
        expect(parseMeasurementInput('999.9', metric: true), 999.9);
        expect(parseMeasurementInput('999.9', metric: false), 2539.7);
        expect(parseMeasurementInput('75', metric: true), 75.0);
        expect(parseMeasurementInput('75', metric: false), 190.5);
        expect(parseMeasurementInput('82.34', metric: true), 82.3);
      },
    );
  });

  group('suggestOtherUnit at the real decision edges (+/-0.1)', () {
    // (site, text, metric, expected). Hand-derived from the bounds; see the plan.
    const rows = <(String, String, bool, bool)>[
      // waist: cm 50-200, inches 19.7-78.7
      ('waist', '19.6', true, false),
      ('waist', '19.7', true, true),
      ('waist', '49.9', true, true),
      ('waist', '50.0', true, false),
      ('waist', '78.7', true, false),
      ('waist', '78.8', true, false),
      ('waist', '200.0', true, false),
      ('waist', '200.1', true, false),
      ('waist', '19.6', false, false),
      ('waist', '19.7', false, false),
      ('waist', '49.9', false, false),
      ('waist', '50.0', false, false),
      ('waist', '78.7', false, false),
      ('waist', '78.8', false, true),
      ('waist', '200.0', false, true),
      ('waist', '200.1', false, false),
      // chest and hips: cm 60-200, inches 23.7-78.7
      ('chest', '23.6', true, false),
      ('chest', '23.7', true, true),
      ('chest', '59.9', true, true),
      ('chest', '60.0', true, false),
      ('chest', '78.7', true, false),
      ('chest', '78.8', true, false),
      ('chest', '200.0', true, false),
      ('chest', '200.1', true, false),
      ('hips', '23.6', false, false),
      ('hips', '23.7', false, false),
      ('hips', '59.9', false, false),
      ('hips', '60.0', false, false),
      ('hips', '78.7', false, false),
      ('hips', '78.8', false, true),
      ('hips', '200.0', false, true),
      ('hips', '200.1', false, false),
      // arms: cm 20-70, inches 7.9-27.5
      ('arms', '7.8', true, false),
      ('arms', '7.9', true, true),
      ('arms', '19.9', true, true),
      ('arms', '20.0', true, false),
      ('arms', '27.5', true, false),
      ('arms', '27.6', true, false),
      ('arms', '70.0', true, false),
      ('arms', '70.1', true, false),
      ('arms', '7.8', false, false),
      ('arms', '7.9', false, false),
      ('arms', '19.9', false, false),
      ('arms', '20.0', false, false),
      ('arms', '27.5', false, false),
      ('arms', '27.6', false, true),
      ('arms', '70.0', false, true),
      ('arms', '70.1', false, false),
    ];
    for (final r in rows) {
      test('${r.$1} "${r.$2}" ${r.$3 ? 'cm' : 'in'} -> ${r.$4}', () {
        expect(suggestOtherUnit(r.$1, r.$2, metric: r.$3), r.$4);
      });
    }

    test('false for a text that does not parse, in both units', () {
      for (final text in ['', '.', '0']) {
        expect(
          suggestOtherUnit('waist', text, metric: true),
          isFalse,
          reason: "'$text' cm",
        );
        expect(
          suggestOtherUnit('waist', text, metric: false),
          isFalse,
          reason: "'$text' in",
        );
      }
    });
  });

  group('formatShortIstDate', () {
    const today = '2026-10-12';
    test('the current year drops the year, other years keep it', () {
      expect(formatShortIstDate('2026-09-05', todayIst: today), '5 Sep');
      expect(formatShortIstDate('2026-10-12', todayIst: today), '12 Oct');
      expect(formatShortIstDate('2025-12-31', todayIst: today), '31 Dec 2025');
      expect(formatShortIstDate('2027-01-01', todayIst: today), '1 Jan 2027');
    });

    test('every month name', () {
      const names = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      for (var m = 1; m <= 12; m++) {
        final mm = m < 10 ? '0$m' : '$m';
        expect(
          formatShortIstDate('2026-$mm-15', todayIst: today),
          '15 ${names[m - 1]}',
        );
      }
    });

    test('malformed input gives the empty string, never a throw', () {
      for (final bad in [
        '2026-13-45',
        '2026-13-10',
        '2026-00-31',
        '2026-00-10',
        '2026-10-00',
        '2026-10-32',
        'abc',
        '',
        '20261012',
        '2026-10-12T00:00:00Z',
        '2026-10-12\n',
      ]) {
        expect(formatShortIstDate(bad, todayIst: today), '', reason: "'$bad'");
      }
    });

    test('an unparsable today treats every year as another year', () {
      expect(formatShortIstDate('2026-09-05', todayIst: 'abc'), '5 Sep 2026');
    });
  });

  group('formatLongIstDate (L2b Landing C)', () {
    // Literals: 2026-10-12 is the "today" of these rows; no consumer reads the
    // device clock, so no date makes them go red.
    const today = '2026-10-12';
    test('the current year drops the year, other years keep it', () {
      expect(formatLongIstDate('2026-09-05', todayIst: today), '5 September');
      expect(formatLongIstDate('2026-10-12', todayIst: today), '12 October');
      expect(
        formatLongIstDate('2025-12-31', todayIst: today),
        '31 December 2025',
      );
      expect(
        formatLongIstDate('2027-01-01', todayIst: today),
        '1 January 2027',
      );
    });

    test('every month name, in full', () {
      const names = [
        'January', 'February', 'March', 'April', 'May', 'June', //
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      for (var m = 1; m <= 12; m++) {
        final mm = m < 10 ? '0$m' : '$m';
        expect(
          formatLongIstDate('2026-$mm-15', todayIst: today),
          '15 ${names[m - 1]}',
        );
      }
    });

    test('malformed input gives the empty string, never a throw', () {
      for (final bad in [
        '2026-13-45',
        // A month past December with a valid day: the month table would be
        // indexed past its end, so these are the rows that prove "never a throw".
        '2026-13-10',
        '2026-00-31',
        '2026-00-10',
        '2026-10-00',
        '2026-10-32',
        'abc',
        '',
        '20261012',
        '2026-10-12T00:00:00Z',
        '2026-10-12\n',
      ]) {
        expect(formatLongIstDate(bad, todayIst: today), '', reason: "'$bad'");
      }
    });

    test('an unparsable today treats every year as another year', () {
      expect(
        formatLongIstDate('2026-09-05', todayIst: 'abc'),
        '5 September 2026',
      );
    });
  });

  group('copy on the spec table', () {
    test(
      'every site has a non-empty label and a guide of at most 90 characters',
      () {
        for (final site in kBodyMeasurementSites) {
          final spec = kBodyMeasurementSpecs[site]!;
          expect(spec.label.trim(), isNotEmpty, reason: site);
          expect(spec.guide.trim(), isNotEmpty, reason: site);
          expect(spec.guide.length, lessThanOrEqualTo(90), reason: site);
        }
      },
    );
  });
}
