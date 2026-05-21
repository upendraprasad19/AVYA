// test/goldens/wardroom/ward_rank_insignia_golden_test.dart
//
// Golden test for [WardRankInsignia]. Pins 3 representative rank
// painters (chevron / anchor / officer-stripes) at 48dp so the
// CustomPaint output is locked against regression.
//
// Goldens generated on Windows 11; regenerate via
//   flutter test test/goldens/wardroom/ --update-goldens
// on push to update.
//
// Tech-debt audit 2026-05-20 / T14 — Wardroom design-system golden coverage.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

Widget _harness(Widget child, {double size = 48}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppColors.bg, // #02070F
      body: Center(
        child: SizedBox(width: size, height: size, child: child),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('WardRankInsignia SD1 (chevron) golden', (tester) async {
    await tester.pumpWidget(_harness(
      const WardRankInsignia(rankCode: 'SD1', size: 48),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardRankInsignia),
      matchesGoldenFile('goldens/ward_rank_insignia_sd1.png'),
    );
  });

  testWidgets('WardRankInsignia LS (anchor) golden', (tester) async {
    await tester.pumpWidget(_harness(
      const WardRankInsignia(rankCode: 'LS', size: 48),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardRankInsignia),
      matchesGoldenFile('goldens/ward_rank_insignia_ls.png'),
    );
  });

  testWidgets('WardRankInsignia Lt (two-stripe officer) golden',
      (tester) async {
    await tester.pumpWidget(_harness(
      const WardRankInsignia(rankCode: 'Lt', size: 48),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardRankInsignia),
      matchesGoldenFile('goldens/ward_rank_insignia_lt.png'),
    );
  });
}
