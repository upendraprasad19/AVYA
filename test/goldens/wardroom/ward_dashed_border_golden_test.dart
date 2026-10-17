// test/goldens/wardroom/ward_dashed_border_golden_test.dart
//
// Golden test for [WardDashedBorder] — the "empty / add new" affordance
// primitive used for empty meal slots, "+ Create custom exercise"
// rows, and "Request deep analysis" CTAs. Mirrors the handoff
// `borderStyle: 'dashed'` token at 1px / `accent`-44 / radius=radCard.
//
// Goldens generated on Windows 11; regenerate via
//   flutter test test/goldens/wardroom/ --update-goldens
// on push to update.
//
// Tech-debt audit 2026-05-20 / T14 — Wardroom design-system golden coverage.

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_dashed_border.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppColors.bg, // #02070F
      body: Center(
        child: SizedBox(
          width: 300,
          height: 100,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('WardDashedBorder default golden', (tester) async {
    await tester.pumpWidget(_harness(
      WardDashedBorder(
        color: AppColors.accent.withValues(alpha: 0.27), // accent-44 (~0x44)
        radius: 14,
        child: const SizedBox.expand(),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardDashedBorder),
      matchesGoldenFile('goldens/ward_dashed_border_default.png'),
    );
  });

  testWidgets('WardDashedBorder thick dashes golden', (tester) async {
    await tester.pumpWidget(_harness(
      WardDashedBorder(
        color: AppColors.accent,
        strokeWidth: 2.0,
        dashLength: 8.0,
        gapLength: 4.0,
        radius: 22,
        child: const SizedBox.expand(),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardDashedBorder),
      matchesGoldenFile('goldens/ward_dashed_border_thick.png'),
    );
  });
}
