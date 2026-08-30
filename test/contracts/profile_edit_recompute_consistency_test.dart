// #150 / Unit E (2026-06-26) — profile-edit live-recompute consistency.
//
// edit_profile._save → recalculateTargets() recomputes via BmrCalculator
// (Katch-McArdle when body-fat is set) AND writes the canonical
// daily_calories/protein_grams/carb_grams/fat_grams back to userBox['profile']
// (profile_provider.dart:102-105), then invalidates the nutrition + home target
// readers + syncs. The recompute/write-back/invalidate were ALREADY implemented
// (Unit 4 fixed the body-fat half); this is a VERIFICATION/pinning test closing
// #150, not a RED→GREEN fix.
//
// It pins the contract that matters (the Unit B tie-in): the canonical the
// Nutrition reader (_resolveNutritionTargets) reads after an edit == what
// BmrCalculator computed == what Home reads — no drift — AND that body-fat
// actually MOVES the canonical on edit (Unit 4 + Unit E).
//
// Run: flutter test test/contracts/profile_edit_recompute_consistency_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';

void main() {
  NutritionTargets compute({double? bodyFat}) => BmrCalculator.calculateTargets(
        weightKg: 75,
        heightCm: 178,
        age: 30,
        gender: 'male',
        activityLevel: 'moderate',
        goal: 'build_muscle',
        pacePreference: 'balanced',
        targetWeightKg: 80,
        bodyFatPercent: bodyFat,
      );

  // Mirror recalculateTargets' write-back into the profile map
  // (profile_provider.dart:102-105 — `...targets.toMap()`).
  Map<String, dynamic> profileFor({double? bodyFat}) => {
        'current_weight_kg': 75,
        'height_cm': 178,
        'gender': 'male',
        'primary_goal': 'build_muscle',
        ...compute(bodyFat: bodyFat).toMap(),
      };

  group('#150 Unit E — profile edit recompute → canonical consistency', () {
    test('the recomputed canonical IS what the Nutrition reader reads '
        '(Home == Nutrition == user_profile; Unit B tie-in)', () {
      final t = compute(bodyFat: 15);
      final read = resolveNutritionTargetsForTest(profileFor(bodyFat: 15));
      expect((read['daily_calories'] as num?)?.toDouble(),
          t.dailyCalories.toDouble(),
          reason: 'Nutrition reads the recomputed canonical daily_calories — '
              'no recompute-vs-stored drift after an edit.');
      expect((read['protein_grams'] as num?)?.toDouble(),
          t.proteinGrams.toDouble());
      expect((read['carb_grams'] as num?)?.toDouble(), t.carbGrams.toDouble(),
          reason: 'the carb dual-name read picks up the recomputed carb target.');
    });

    test('editing body-fat MOVES the canonical (Katch vs Mifflin; Unit 4 tie-in)',
        () {
      final withBf =
          resolveNutritionTargetsForTest(profileFor(bodyFat: 12));
      final noBf = resolveNutritionTargetsForTest(profileFor(bodyFat: null));
      expect(withBf['daily_calories'], isNot(noBf['daily_calories']),
          reason: 'body-fat feeds Katch-McArdle on edit → a different canonical '
              '(pre-Unit-4 it was silently dropped → identical calc).');
    });

    test('recalculateTargets writes the canonical back via toMap, through the '
        'canonical BmrCalculator (write-back contract — source pin)', () {
      // OI-150 — REPOINTED, not loosened. The derivation moved out of
      // profile_provider.dart into the shared `recomputeDerivedTargets` so the
      // restore path and this edit path cannot drift (it previously lived in
      // the provider AND was mirrored again in this file's own `compute()`
      // helper above — two copies, and the restore path was about to be a
      // third). Both original assertions still hold; they now hold at the new
      // home, and a third assertion pins that the provider still DELEGATES —
      // which the single-file grep structurally could not catch.
      final src = _stripDartComments(
          File('lib/features/profile/services/profile_target_recompute.dart')
              .readAsStringSync());
      expect(src.contains('targets.toMap()'), isTrue,
          reason: 'the recompute must persist the recomputed canonical '
              '(daily_calories/protein/carb/fat) back to the profile.');
      expect(src.contains('BmrCalculator.calculateTargets'), isTrue,
          reason: 'the recompute must go through the canonical BmrCalculator.');

      final providerSrc = _stripDartComments(
          File('lib/features/profile/providers/profile_provider.dart')
              .readAsStringSync());
      expect(providerSrc.contains('recomputeDerivedTargets('), isTrue,
          reason: 'recalculateTargets must DELEGATE to the shared derivation — '
              'a re-inlined copy here is exactly the drift this move removed');
    });
  });
}

/// Strips `/* */` blocks then `// ...` line comments so the source-grep assertion
/// matches real CODE, not a comment. Per feedback_source_grep_strip_comments_first.
String _stripDartComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock.split('\n').map((l) {
    final i = l.indexOf('//');
    return i >= 0 ? l.substring(0, i) : l;
  }).join('\n');
}
