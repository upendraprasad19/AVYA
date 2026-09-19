// Regression contract for bug e8a2c1 (Obs#5, 2026-06-13 live web E2E): on the
// ~698px web mobile-frame the stock Material time/date picker's OK/Cancel action
// row fell BELOW the fold, so the user could not confirm a time → muster Q2 (and
// onboarding DOB) became an unpassable blocker. The shared responsivePickerBuilder
// scroll-wraps the dialog so the actions stay reachable; both pickers use it.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/responsive_picker_builder.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  testWidgets(
      'e8a2c1 — responsivePickerBuilder scroll-wraps a too-tall dialog (actions reachable)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => responsivePickerBuilder(
          context,
          // A child taller than the test viewport (800x600) — the wrap must let
          // it scroll rather than clip the (bottom) action row.
          const SizedBox(height: 2000, width: 300, child: Text('picker')),
        ),
      ),
    ));
    expect(find.byType(SingleChildScrollView), findsOneWidget,
        reason:
            'a dialog taller than the viewport must be scrollable so its '
            'OK/Cancel row stays reachable');
    expect(tester.takeException(), isNull,
        reason: 'no overflow — the scroll wrap absorbs the excess height');
  });

  test('e8a2c1 — both onboarding pickers use the responsive host', () {
    final muster = _strip(
        File('lib/features/ai_coach/screens/muster_screen.dart').readAsStringSync());
    final identity = _strip(File('lib/features/onboarding/screens/identity_screen.dart')
        .readAsStringSync());
    expect(muster.contains('builder: responsivePickerBuilder'), isTrue,
        reason: 'muster time picker must use the responsive host');
    expect(identity.contains('builder: responsivePickerBuilder'), isTrue,
        reason: 'identity DOB picker must use the responsive host');
  });
}
