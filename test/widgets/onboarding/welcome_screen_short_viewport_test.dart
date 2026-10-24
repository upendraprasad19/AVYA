// test/widgets/onboarding/welcome_screen_short_viewport_test.dart
//
// Regression test for the onboarding welcome-screen overlap bug reported
// alongside diagnose a3f6d9 (same batch, different symptom — this file
// covers the layout-overlap half, not the routing-misroute half).
//
// Bug: WelcomeScreen's `_hero()` was a bare `Center(child: Column(...))`
// with no scroll ancestor, sitting inside `Expanded`. On a short viewport,
// the Expanded region can shrink below the Column's intrinsic content
// height (headline + body + 3 feature rows, ~450-500px), and a Column
// without a scroll ancestor paints past its bounds instead of clipping —
// visually overlapping `_cta()` (the BEGIN ENLISTMENT button / SIGN IN
// link / referral field / privacy footer) below it.
//
// This test pumps WelcomeScreen at a deliberately short viewport (well
// under the hero content's intrinsic height) and asserts no layout
// exception is thrown. Flutter surfaces a RenderFlex-overflow as a
// FlutterError during layout, which flutter_test captures and makes
// retrievable via tester.takeException() — so this test FAILS on the
// pre-fix bare Center(child: Column(...)) (overflow error) and PASSES with
// the LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight:)
// fix (content scrolls internally instead of overflowing).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/onboarding/screens/welcome_screen.dart';

void main() {
  testWidgets(
    'WelcomeScreen at a short viewport does not overflow — hero content '
    'scrolls instead of painting over the CTA section',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Deliberately shorter than the hero content's intrinsic height
      // (~450-500px of headline + body + 3 feature rows) plus the brand
      // row and CTA section combined — reproduces the exact short-window
      // condition from the founder's report.
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: WelcomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'A bare Center(child: Column(...)) with no scroll ancestor '
            'inside Expanded overflows on a short viewport instead of '
            'clipping, which Flutter reports as a RenderFlex layout error '
            '— visually this is the hero content painting over the CTA '
            'section below it. The fix wraps _hero() in '
            'LayoutBuilder + SingleChildScrollView + '
            'ConstrainedBox(minHeight:) so it scrolls internally instead.',
      );

      // The CTA button must still be present and reachable (not just
      // "no crash") — confirms the fix didn't accidentally hide it.
      expect(find.text('BEGIN ENLISTMENT →'), findsOneWidget);
    },
  );

  testWidgets(
    'WelcomeScreen at a normal/tall viewport is unaffected by the fix — '
    'hero content still renders, CTA still present',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: WelcomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('BEGIN ENLISTMENT →'), findsOneWidget);
      expect(find.text('PROSPECTUS'), findsOneWidget);
    },
  );
}
