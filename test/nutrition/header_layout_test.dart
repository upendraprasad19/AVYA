import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// F10 · Test #9 — Nutrition header layout invariants.
void main() {
  late String src;

  setUpAll(() {
    final f = File('lib/features/nutrition/screens/nutrition_screen.dart');
    expect(f.existsSync(), isTrue, reason: 'Run from project root');
    src = f.readAsStringSync();
  });

  test('eyebrow contains GALLEY + date', () {
    // Source uses literal U+00B7 middle-dot (not the \u escape).
    expect(src.contains("'GALLEY · \${weekdays[now.weekday - 1]}"), isTrue,
        reason: 'eyebrow must consolidate GALLEY + date');
  });

  test('DIET PLAN button moved out of WardLetterhead.trailing slot', () {
    expect(src.contains('WardLetterhead('), isFalse,
        reason: 'F10 replaced WardLetterhead with explicit 3-row Column');
    expect(src.contains('_buildDietPlanButton()'), isTrue,
        reason: 'DIET PLAN button is still rendered, just in row 1 right');
  });

  test('row 3 anchor renders KCAL meter', () {
    expect(src.contains('KCAL'), isTrue,
        reason: 'F10 row 3 anchor is the KCAL bar');
    expect(src.contains('WardBar('), isTrue);
  });
}
