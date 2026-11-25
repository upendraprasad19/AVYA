import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/features/train/providers/preview_plan_provider.dart';

import '../helpers/dart_source_scan.dart';

/// OI-348 Landing 3a (P1): ONE phase-numeral converter. Before the fix three
/// private 1-12 maps (`hold_week_labels.dart`, `week_selector.dart`,
/// `hold_roadmap_strip.dart`) and one 1-12 parse (`preview_plan_provider.dart`)
/// stopped at XII, so phase 13 printed "13". Presence pins for the wiring; the
/// behaviour is `test/core/roman_numeral_test.dart`.
String _src(String path) => stripDartComments(File(path).readAsStringSync());

void main() {
  // B-pass Finding 5: the first version needed a quoted 'XII', so a map that
  // stops at 'X' passed. Rule now: 4+ DISTINCT quoted numerals in one file
  // outside roman_numeral.dart. Today's legitimate maximum is 3 (the I/II/III
  // rows of phase_roadmap_screen and plan_screen), measured 2026-11-25.
  final numeral = RegExp(
      r"""['"](X{0,3}(?:IX|IV|VI{0,3}|I{1,3})|X{1,3})['"]""");
  Set<String> distinctNumerals(String src) =>
      numeral.allMatches(src).map((m) => m.group(1)!).toSet();

  test('no other numeral table under lib/ (4+ distinct quoted numerals)', () {
    final offenders = <String>[];
    var scanned = 0;
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final norm = f.path.replaceAll('\\', '/');
      if (norm.endsWith('lib/core/utils/roman_numeral.dart')) continue;
      scanned++;
      final found = distinctNumerals(stripDartComments(f.readAsStringSync()));
      if (found.length >= 4) offenders.add('$norm $found');
    }
    expect(scanned, greaterThan(500), reason: 'the scan read lib/');
    expect(offenders, isEmpty,
        reason: 'a numeral map outside roman_numeral.dart stops somewhere');
  });

  test('the table rule catches a map that stops at X, and not I/II/III', () {
    expect(
        distinctNumerals("const _m = {1:'I',2:'II',3:'III',4:'IV',5:'V',"
                "6:'VI',7:'VII',8:'VIII',9:'IX',10:'X'};")
            .length,
        greaterThanOrEqualTo(4));
    expect(distinctNumerals("""("I"), ('II'), ('IV'), ('X')""").length, 4);
    expect(distinctNumerals("number: 'I', number: 'II', number: 'III'").length,
        3);
    expect(distinctNumerals("'H': 23, 'M': 35, 'I': 47, 'B': 40").length, 1);
  });

  test('phaseRoman delegates to toRoman', () {
    final s = _src('lib/core/utils/hold_week_labels.dart');
    expect(s, contains('String phaseRoman(int phase) => toRoman(phase);'));
  });

  test('week_selector and hold_roadmap_strip delegate to phaseRoman', () {
    expect(_src('lib/features/train/widgets/week_selector.dart'),
        contains('String _phaseRoman(int phase) => phaseRoman(phase);'));
    expect(_src('lib/features/train/widgets/hold_roadmap_strip.dart'),
        contains('static String _roman(int phase) => phaseRoman(phase);'));
  });

  test('the preview route parses with fromRoman, fallback Phase I', () {
    expect(_src('lib/features/train/providers/preview_plan_provider.dart'),
        contains('previewPhaseFromRoman(key.phaseNumber)'));
    // Behaviour (B-pass Finding 4): any canonical numeral up to XCIX.
    expect(previewPhaseFromRoman('II'), 2);
    expect(previewPhaseFromRoman('XIII'), 13);
    expect(previewPhaseFromRoman('XCIX'), kPreviewMaxPhase);
    expect(previewPhaseFromRoman('C'), 1);
    expect(previewPhaseFromRoman('MMMCMXCIX'), 1);
    expect(previewPhaseFromRoman('xiii'), 1);
    expect(previewPhaseFromRoman('IIII'), 1);
    expect(previewPhaseFromRoman(''), 1);
  });
}
