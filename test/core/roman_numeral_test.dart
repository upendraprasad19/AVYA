import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/hold_week_labels.dart';
import 'package:icanbefitter/core/utils/roman_numeral.dart';

/// OI-348 Landing 3a (P1): phases do not stop at XII, so the phase numeral
/// converter must too. Before the fix every map stopped at 12 and phase 13
/// printed as "13".
void main() {
  test('known values', () {
    const cases = {
      1: 'I', 2: 'II', 3: 'III', 4: 'IV', 5: 'V', 9: 'IX', 10: 'X',
      11: 'XI', 12: 'XII', 13: 'XIII', 14: 'XIV', 19: 'XIX', 24: 'XXIV',
      40: 'XL', 49: 'XLIX', 90: 'XC', 400: 'CD', 1994: 'MCMXCIV',
      3999: 'MMMCMXCIX',
    };
    cases.forEach((n, r) {
      expect(toRoman(n), r, reason: 'toRoman($n)');
      expect(fromRoman(r), n, reason: 'fromRoman($r)');
    });
  });

  test('round trip 1..200', () {
    for (var n = 1; n <= 200; n++) {
      expect(fromRoman(toRoman(n)), n);
    }
  });

  test('out of range renders digits, never throws', () {
    expect(toRoman(0), '0');
    expect(toRoman(-3), '-3');
    expect(toRoman(4000), '4000');
  });

  test('fromRoman is strict: only the canonical upper-case form', () {
    for (final bad in ['', 'IIII', 'VX', 'IC', 'xiii', 'XIII ', ' I', 'A',
      'IIV', 'VV', 'MMMM']) {
      expect(fromRoman(bad), isNull, reason: '"$bad" must not parse');
    }
  });

  test('phaseRoman delegates: XIII and beyond', () {
    expect(phaseRoman(12), 'XII');
    expect(phaseRoman(13), 'XIII');
    expect(phaseRoman(25), 'XXV');
    expect(phaseRoman(0), '0');
  });
}
