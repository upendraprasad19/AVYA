// test/goldens/wardroom/ward_rank_pill_golden_test.dart
//
// Golden test for [WardRankPill] — the top-of-Profile pill composed of
// [insignia 24dp][shortCapsName][chevron]. Audit-plan T14 mapped
// "WardPill" → WardRankPill (closest matching primitive; the audit
// brief acknowledged the actual file name).
//
// Only the collapsed-pill state is captured. The expanded state runs
// an InheritedWidget builder slot whose content is owned by the
// caller (Profile screen) and is therefore out of scope for a
// primitive-level golden.
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
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_pill.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppColors.bg, // #02070F
      body: Center(
        child: SizedBox(
          width: 300,
          height: 60,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Warmup: primes the GoogleFonts failure cache so subsequent golden
  // renders use the deterministic fallback. See ward_set_chips_golden_test
  // for the same pattern.
  testWidgets('warmup — prime GoogleFonts failure cache', (tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (_) {};
    for (final family in const ['DM Sans', 'Fraunces', 'JetBrains Mono']) {
      for (final weight in const [
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
        FontWeight.w800,
        FontWeight.w900,
      ]) {
        try {
          await tester.pumpWidget(MaterialApp(
            home: Text(
              'warm',
              style: GoogleFonts.getFont(family, fontWeight: weight),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 200));
        } catch (_) {/* swallow */}
      }
    }
    FlutterError.onError = originalOnError;
  });

  testWidgets('WardRankPill Lt collapsed golden', (tester) async {
    await tester.pumpWidget(_harness(
      WardRankPill(
        rankCode: 'Lt',
        shortCapsName: 'LT. UPENDRA',
        expandedContentBuilder: (_) => const SizedBox.shrink(),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardRankPill),
      matchesGoldenFile('goldens/ward_rank_pill_lt.png'),
    );
  });

  testWidgets('WardRankPill SD1 collapsed golden', (tester) async {
    await tester.pumpWidget(_harness(
      WardRankPill(
        rankCode: 'SD1',
        shortCapsName: 'SD1. RECRUIT',
        expandedContentBuilder: (_) => const SizedBox.shrink(),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardRankPill),
      matchesGoldenFile('goldens/ward_rank_pill_sd1.png'),
    );
  });
}
