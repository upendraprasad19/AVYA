// test/goldens/wardroom/ward_set_chips_golden_test.dart
//
// Golden test for [WardSetChips] — pins the bracketed-chip rendering
// for the most common logging types (weight_reps + bodyweight_reps).
// This widget is the SoT for "what was logged" UI; visual regression
// here would silently break both WorkoutReceiptCard + Train expanded
// view.
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
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_set_chips.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: AppColors.bg, // #02070F
      body: Center(
        child: SizedBox(
          width: 300,
          height: 100,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    // Block network font fetches; GoogleFonts caches the first failure
    // and silently falls back to the test framework's embedded font
    // for every subsequent build.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Warmup: primes the GoogleFonts failure cache so subsequent golden
  // renders use the deterministic fallback. The expected font-load
  // exception is swallowed via FlutterError.onError.
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

  testWidgets('WardSetChips weight_reps golden', (tester) async {
    await tester.pumpWidget(_harness(
      const WardSetChips(
        loggingType: 'weight_reps',
        perSetBreakdown: [
          WardSetChip(weightKg: 20, reps: 10),
          WardSetChip(weightKg: 22.5, reps: 8),
          WardSetChip(weightKg: 25, reps: 6),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardSetChips),
      matchesGoldenFile('goldens/ward_set_chips_weight_reps.png'),
    );
  });

  testWidgets('WardSetChips bodyweight_reps golden', (tester) async {
    await tester.pumpWidget(_harness(
      const WardSetChips(
        loggingType: 'bodyweight_reps',
        perSetBreakdown: [
          WardSetChip(reps: 12),
          WardSetChip(reps: 10),
          WardSetChip(reps: 8),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardSetChips),
      matchesGoldenFile('goldens/ward_set_chips_bodyweight_reps.png'),
    );
  });

  testWidgets('WardSetChips fallback label golden', (tester) async {
    await tester.pumpWidget(_harness(
      const WardSetChips(
        loggingType: 'weight_reps',
        perSetBreakdown: [],
        fallbackLabel: '3 sets · 30 reps',
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(WardSetChips),
      matchesGoldenFile('goldens/ward_set_chips_fallback.png'),
    );
  });
}
