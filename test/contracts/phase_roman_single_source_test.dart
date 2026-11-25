import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source_scan.dart';

/// OI-348 Landing 3a (P1): ONE phase-numeral converter. Before the fix three
/// private 1-12 maps (`hold_week_labels.dart`, `week_selector.dart`,
/// `hold_roadmap_strip.dart`) and one 1-12 parse (`preview_plan_provider.dart`)
/// stopped at XII, so phase 13 printed "13". Presence pins for the wiring; the
/// behaviour is `test/core/roman_numeral_test.dart`.
String _src(String path) => stripDartComments(File(path).readAsStringSync());

void main() {
  test('no other numeral table under lib/ (no quoted XI / XII literal)', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final norm = f.path.replaceAll('\\', '/');
      if (norm.endsWith('lib/core/utils/roman_numeral.dart')) continue;
      final s = stripDartComments(f.readAsStringSync());
      if (RegExp(r"""['"]X{0,3}(?:IX|IV|V?I{0,3})['"]\s*[:,]""")
              .hasMatch(s) &&
          RegExp(r"""['"]XII['"]""").hasMatch(s)) {
        offenders.add(norm);
      }
    }
    expect(offenders, isEmpty,
        reason: 'a numeral map outside roman_numeral.dart stops somewhere');
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
        contains('int _romanToInt(String roman) => fromRoman(roman) ?? 1;'));
  });
}
