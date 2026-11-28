// OI-518: the words of the Weekly Report weight card's Maintain lines.
//
// Pure strings plus two source pins (presence only): the copy file never prints a
// distance from a float (`toStringAsFixed`) and never imports `lib/features`, so the
// printed gap can only come from the integer tenths the caller hands in.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/weight_callout_copy.dart';
import 'package:icanbefitter/features/onboarding/target_weight_check.dart';

const _dot = '·';

String _src(String path) => File(path)
    .readAsLinesSync()
    .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
    .join('\n');

void main() {
  group('onTargetLine', () {
    test('the distance and the target, in the founder-approved words', () {
      expect(WeightCalloutCopy.onTargetLine(gapTenths: 12, target: 75),
          'Holding the line $_dot 1.2 kg from your 75 kg target');
      expect(WeightCalloutCopy.onTargetLine(gapTenths: -12, target: 75),
          'Holding the line $_dot 1.2 kg from your 75 kg target');
    });
    test('0.0 kg reads right on the target', () {
      expect(WeightCalloutCopy.onTargetLine(gapTenths: 0, target: 75),
          'Holding the line $_dot right on your 75 kg target');
    });
    test('the window edge prints 3.0 (inside), never 3.1', () {
      expect(WeightCalloutCopy.onTargetLine(gapTenths: 30, target: 75),
          'Holding the line $_dot 3.0 kg from your 75 kg target');
      expect(WeightCalloutCopy.onTargetLine(gapTenths: -30, target: 75),
          'Holding the line $_dot 3.0 kg from your 75 kg target');
    });
  });

  group('offTargetLine', () {
    test('above: the last weigh-in is over the target', () {
      expect(WeightCalloutCopy.offTargetLine(gapTenths: -34, target: 75),
          '3.4 kg above your 75 kg target $_dot adjust your nutrition to hold the line');
    });
    test('below: the last weigh-in is under the target', () {
      expect(WeightCalloutCopy.offTargetLine(gapTenths: 34, target: 75),
          '3.4 kg below your 75 kg target $_dot adjust your nutrition to hold the line');
    });
    test('the first tenth beyond the window prints 3.1, never 3.0', () {
      expect(WeightCalloutCopy.offTargetLine(gapTenths: 31, target: 75),
          startsWith('3.1 kg below'));
      expect(WeightCalloutCopy.offTargetLine(gapTenths: -31, target: 75),
          startsWith('3.1 kg above'));
    });
    test('tenths from weightGapTenths: the float edge 66.9 / 70.0 reads 3.1', () {
      // (70.0 - 66.9) * 10 = 30.999999999999943: round() 31 (a truncating gap
      // would read 30 and print 3.0 under an offTarget kind).
      final gap = weightGapTenths(66.9, 70.0);
      expect(WeightCalloutCopy.offTargetLine(gapTenths: gap, target: 70.0),
          startsWith('3.1 kg below your 70 kg target'));
    });
  });

  group('asOfSuffix', () {
    DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);
    test('same year: day and month, no leading zero, no year', () {
      expect(WeightCalloutCopy.asOfSuffix(lastDay: d(2026, 11, 3), today: d(2026, 11, 19)),
          ' $_dot as of 3 Nov');
      expect(WeightCalloutCopy.asOfSuffix(lastDay: d(2026, 11, 18), today: d(2026, 11, 30)),
          ' $_dot as of 18 Nov');
    });
    test('all twelve month names', () {
      const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      for (var m = 1; m <= 12; m++) {
        expect(WeightCalloutCopy.asOfSuffix(lastDay: d(2026, m, 9), today: d(2026, 12, 31)),
            ' $_dot as of 9 ${names[m - 1]}');
      }
    });
    test('a different year adds the last weigh-in\'s year', () {
      expect(WeightCalloutCopy.asOfSuffix(lastDay: d(2026, 12, 28), today: d(2027, 1, 10)),
          ' $_dot as of 28 Dec 2026');
      // the same month in another year still prints the year
      expect(WeightCalloutCopy.asOfSuffix(lastDay: d(2025, 11, 3), today: d(2026, 11, 19)),
          ' $_dot as of 3 Nov 2025');
    });
    test('today supplies only the year (far future today)', () {
      expect(WeightCalloutCopy.asOfSuffix(lastDay: d(2026, 11, 3), today: d(2031, 3, 5)),
          ' $_dot as of 3 Nov 2026');
    });
  });

  group('targetLabel', () {
    test('whole to the tenth prints whole, else one decimal', () {
      expect(WeightCalloutCopy.targetLabel(75), '75');
      expect(WeightCalloutCopy.targetLabel(75.0), '75');
      expect(WeightCalloutCopy.targetLabel(74.5), '74.5');
      expect(WeightCalloutCopy.targetLabel(74.84), '74.8');
      expect(WeightCalloutCopy.targetLabel(74.96), '75');
      expect(WeightCalloutCopy.targetLabel(99.95), '100');
    });
    test('a non-positive or non-finite target prints nothing', () {
      expect(WeightCalloutCopy.targetLabel(0), '');
      expect(WeightCalloutCopy.targetLabel(-5), '');
      expect(WeightCalloutCopy.targetLabel(double.nan), '');
      expect(WeightCalloutCopy.targetLabel(double.infinity), '');
    });
  });

  group('source pins (presence only)', () {
    final src = _src('lib/core/copy/weight_callout_copy.dart');
    test('the distance is never printed from a float', () {
      expect(src.contains('toStringAsFixed'), isFalse);
    });
    test('lib/core/copy imports nothing from lib/features', () {
      expect(src.contains('features/'), isFalse);
    });
  });
}
