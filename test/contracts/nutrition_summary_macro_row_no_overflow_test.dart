// test/contracts/nutrition_summary_macro_row_no_overflow_test.dart
//
// Diagnose 7e3c91 (2026-06-01) — found live (amar, Nutrition tab): the TODAY'S
// SUMMARY card's macro rows tripped a RenderFlex "RIGHT OVERFLOWED BY N PIXELS"
// — the label + the "$current / $target$suffix" value sat in a
// `Row(spaceBetween)` with NO Flexible/Expanded, so a wide value (a realistic
// 4-digit water row "2103 / 3125ml", or a power user's inflated macros) exceeded
// the narrow right column → the value clipped and the label squished into it
// ("PROTEIN451 / 535g").
//
// Fix: wrap the LABEL Text in `Flexible` with `maxLines: 1` +
// `TextOverflow.ellipsis` so it ellipsizes under pressure, while the numeric
// value keeps its full width + right alignment (the data stays visible). The
// Row can then never overflow.
//
// This is a SOURCE-GREP contract scoped to the `_macroRow` method body. Comments
// are stripped FIRST (per feedback_source_grep_strip_comments_first.md) because
// the fix's own comment quotes "RenderFlex" / "OVERFLOWED" / "Flexible" /
// "ellipsis" and would produce false matches otherwise. Behavioral proof is the
// live observation (overflow banner present pre-fix, gone post-fix).
//
// Run: flutter test test/contracts/nutrition_summary_macro_row_no_overflow_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _stripComments(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final idx = line.indexOf('//');
        return idx >= 0 ? line.substring(0, idx) : line;
      })
      .join('\n');
  return s;
}

void main() {
  final file =
      File('lib/features/nutrition/screens/nutrition_screen.dart');
  late String macroRowBody;

  setUpAll(() {
    expect(file.existsSync(), isTrue,
        reason: 'nutrition_screen.dart must exist');
    final code = _stripComments(file.readAsStringSync());

    // Isolate the `_macroRow` method body so the assertions match THIS row,
    // not some other Flexible elsewhere in the (large) screen file.
    final start = code.indexOf('Widget _macroRow(');
    expect(start, greaterThanOrEqualTo(0),
        reason: 'the _macroRow builder must exist');
    // The method ends at the next top-level `  Widget ` / `  Future` / `  void`
    // declaration; bound generously by the next `\n  Widget ` after start.
    final nextDecl = code.indexOf('\n  Widget ', start + 10);
    final end = nextDecl > start ? nextDecl : code.length;
    macroRowBody = code.substring(start, end);
  });

  group('Nutrition TODAY\'S SUMMARY macro row never overflows (Diagnose 7e3c91)',
      () {
    test('the macro-row label is wrapped in Flexible (absorbs overflow)', () {
      expect(macroRowBody.contains('Flexible('), isTrue,
          reason:
              'the macro-row label MUST be Flexible so it ellipsizes instead of '
              'overflowing the narrow right column — a wide value (e.g. '
              '"2103 / 3125ml") otherwise trips a RenderFlex RIGHT OVERFLOW.');
    });

    test('the flexible label ellipsizes on one line', () {
      expect(macroRowBody.contains('TextOverflow.ellipsis'), isTrue,
          reason: 'the flexible label must ellipsize (overflow: ellipsis).');
      expect(macroRowBody.contains('maxLines: 1'), isTrue,
          reason: 'the label must stay on one line.');
    });

    test('the row still renders the value as "current / target + suffix"', () {
      expect(macroRowBody.contains(r"'$current / $target$suffix'"), isTrue,
          reason:
              'the numeric value (the data) must still be rendered in full — '
              'only the LABEL ellipsizes, never the value.');
    });
  });
}
