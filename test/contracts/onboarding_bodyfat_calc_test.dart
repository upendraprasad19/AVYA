// Unit 4 (d-bf, 2026-06-14) — the SAVED onboarding calorie calc must HONOR the
// user's body-fat (Katch-McArdle when provided, Mifflin-St Jeor when skipped),
// and must NEVER persist a fabricated body-fat value.
//
// Two bugs this pins:
//   1. The onboarding COMMIT (completeOnboarding) and PREVIEW (plan_screen) used
//      to pass NO bodyFatPercent to BmrCalculator.calculateTargets — the calc
//      silently ran Mifflin even for a user who typed 12%. Now both feed body-fat
//      through the SHARED BmrCalculator.bodyFatForCalc helper (kill-switch aware),
//      so the value actually changes the target AND preview == saved (no drift).
//   2. A skip-user used to SAVE a fabricated default (18.0, then briefly 0.0 via
//      the 0-flooring _parseDouble). The saved value feeds body_stats.dart, which
//      renders 0.0/18.0 as a made-up "0%"/"18%" (only null → "—"). The commit now
//      parses body-fat with a NULLABLE parse and saves null on skip.
//
// Behavioral (value-level) + source-grep (comment-stripped) — the parity test
// `plan_screen_targets_match_completeOnboarding_test.dart` pins the arg-set match;
// this pins the body-fat SEMANTICS.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

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
  group('BmrCalculator.bodyFatForCalc — shared flag-gated selector', () {
    test('honors a provided body-fat when not disabled', () {
      expect(BmrCalculator.bodyFatForCalc(22.0, disabled: false), 22.0);
    });

    test('kill-switch (disabled) drops body-fat → null (Mifflin)', () {
      expect(BmrCalculator.bodyFatForCalc(22.0, disabled: true), isNull);
    });

    test('a skip (null body-fat) stays null regardless of the flag', () {
      expect(BmrCalculator.bodyFatForCalc(null, disabled: false), isNull);
      expect(BmrCalculator.bodyFatForCalc(null, disabled: true), isNull);
    });
  });

  group('body-fat materially changes the SAVED daily_calories', () {
    // Same person; the ONLY difference is whether body-fat is honored.
    NutritionTargets compute(double? bf, {required bool disabled}) =>
        BmrCalculator.calculateTargets(
          weightKg: 80,
          heightCm: 178,
          age: 29,
          gender: 'male',
          activityLevel: 'moderate',
          goal: 'build_muscle',
          pacePreference: 'balanced',
          bodyFatPercent: BmrCalculator.bodyFatForCalc(bf, disabled: disabled),
        );

    test('lean user (12% BF, Katch) gets a DIFFERENT target than the skip (Mifflin)',
        () {
      final withBf = compute(12.0, disabled: false);
      final skipped = compute(null, disabled: false);
      expect(withBf.bmr, isNot(equals(skipped.bmr)),
          reason: 'Katch (lean mass) must diverge from Mifflin for a lean user');
      expect(withBf.dailyCalories, isNot(equals(skipped.dailyCalories)),
          reason: 'the honored body-fat must flow all the way to daily_calories');
    });

    test('kill-switch makes a body-fat user IDENTICAL to a skip (full revert)',
        () {
      final disabledBf = compute(12.0, disabled: true);
      final skipped = compute(null, disabled: false);
      expect(disabledBf.bmr, skipped.bmr);
      expect(disabledBf.dailyCalories, skipped.dailyCalories);
      expect(disabledBf.proteinGrams, skipped.proteinGrams);
    });
  });

  group('source — onboarding never persists a fabricated body-fat', () {
    final statsSrc = _strip(
        File('lib/features/onboarding/screens/stats_screen.dart')
            .readAsStringSync());
    final planSrc = _strip(
        File('lib/features/onboarding/screens/plan_screen.dart')
            .readAsStringSync());
    final commitSrc = _strip(
        File('lib/features/onboarding/providers/onboarding_provider.dart')
            .readAsStringSync());

    bool hasFabricatedDefault(String src) => src
        .split('\n')
        .where((l) =>
            l.toLowerCase().contains('body_fat') || l.contains('bodyFat'))
        .any((l) => RegExp(r'\?\?\s*18').hasMatch(l));

    test('stats_screen does NOT default body-fat to 18 (the root fabrication)',
        () {
      expect(hasFabricatedDefault(statsSrc), isFalse,
          reason: 'stats_screen must forward the raw (nullable) body-fat, '
              'never `bodyFat ?? 18.0`');
    });

    test('plan_screen does NOT default body-fat to 18', () {
      expect(hasFabricatedDefault(planSrc), isFalse);
    });

    test('completeOnboarding parses body-fat with the NULLABLE parse (saves null on skip)',
        () {
      expect(commitSrc.contains("_parseDoubleOrNull(a['body_fat_percent'])"),
          isTrue,
          reason: 'a skip-user must SAVE null body_fat_percent (→ "—" in '
              'body_stats), not 0.0 from the 0-flooring _parseDouble');
      expect(hasFabricatedDefault(commitSrc), isFalse);
    });

    test('BOTH preview + commit feed body-fat through the shared bodyFatForCalc helper',
        () {
      expect(planSrc.contains('BmrCalculator.bodyFatForCalc'), isTrue,
          reason: 'plan_screen preview must use the shared helper');
      expect(commitSrc.contains('BmrCalculator.bodyFatForCalc'), isTrue,
          reason: 'completeOnboarding must use the shared helper — structural '
              'parity (not a hand-copied ternary that can drift)');
    });
  });
}
