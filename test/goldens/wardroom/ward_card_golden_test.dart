// test/goldens/wardroom/ward_card_golden_test.dart
//
// Golden test for [WardCard] — renders all 3 variants
// (standard / hero / inset) at a fixed 300x100 surface and compares
// against committed PNG snapshots.
//
// Goldens generated on Windows 11; regenerate via
//   flutter test test/goldens/wardroom/ --update-goldens
// on push to update if font rendering shifts.
//
// Tech-debt audit 2026-05-20 / T14 — Wardroom design-system golden coverage.

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_card.dart';

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
  testWidgets('WardCard standard variant golden', (tester) async {
    await tester.pumpWidget(_harness(
      const WardCard(
        child: SizedBox.expand(),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardCard),
      matchesGoldenFile('goldens/ward_card_standard.png'),
    );
  });

  testWidgets('WardCard hero variant golden', (tester) async {
    await tester.pumpWidget(_harness(
      const WardCard(
        variant: WardCardVariant.hero,
        child: SizedBox.expand(),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardCard),
      matchesGoldenFile('goldens/ward_card_hero.png'),
    );
  });

  testWidgets('WardCard inset variant golden', (tester) async {
    await tester.pumpWidget(_harness(
      const WardCard(
        variant: WardCardVariant.inset,
        child: SizedBox.expand(),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardCard),
      matchesGoldenFile('goldens/ward_card_inset.png'),
    );
  });
}
