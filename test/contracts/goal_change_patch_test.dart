// OI-191: the shared goal-change patch (pure). Edit Profile and the coach
// switchGoal both write what `goalChange` returns, so these cases are the
// contract of BOTH doors for the seed, the recomputed targets and the preview.
//
// Mutation record: see docs/diagnoses/2026-11-18-goal-target-weight-agreement-*.md
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/onboarding/target_weight_check.dart';
import 'package:icanbefitter/features/profile/services/goal_change_patch.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

final DateTime _now = DateTime(2026, 11, 18, 10);

/// A complete profile, so the recompute overlay exists.
Map<String, dynamic> profile({
  String goal = 'lose_fat',
  double weight = 75.0,
  Object? target = 71.0,
  bool complete = true,
}) =>
    <String, dynamic>{
      'primary_goal': goal,
      'current_weight_kg': weight,
      'target_weight_kg': target,
      'height_cm': 175.0,
      'gender': 'male',
      'activity_level': 'moderate',
      'days_per_week': 4,
      'pace_preference': 'balanced',
      if (complete) 'date_of_birth': '1995-06-15',
      // Stale values from the OLD goal, so a write is visible.
      'daily_calories': 2000,
      'protein_grams': 150,
    };

GoalChange change(Map<String, dynamic> p, String goal) => goalChange(
      Map<String, dynamic>.unmodifiable(p),
      newGoal: goal,
      now: _now,
      bodyFatCalcDisabled: false,
    );

void main() {
  group('the target is seeded only when it cannot stand beside the new goal', () {
    test('Cut 71 -> Build seeds current + 3.0', () {
      final c = change(profile(), 'build_muscle');
      expect(c.patch['target_weight_kg'], 78.0);
      expect(c.seededTarget, 78.0);
      expect(c.targetFrom, 71.0);
      expect(c.goalChanged, isTrue);
    });

    test('Build 80 -> Cut seeds current - 5.0', () {
      final c = change(profile(goal: 'build_muscle', target: 80.0), 'lose_fat');
      expect(c.patch['target_weight_kg'], 70.0);
    });

    test('Cut 71 -> Maintain seeds the current weight', () {
      final c = change(profile(), 'general_fitness');
      expect(c.patch['target_weight_kg'], 75.0);
    });

    test('the seed is an exact one-decimal double (75.3 + 3.0 is 78.3)', () {
      final c = change(profile(weight: 75.3), 'build_muscle');
      expect(c.patch['target_weight_kg'], 78.3);
      expect(identical(c.patch['target_weight_kg'], 78.3) ||
              c.patch['target_weight_kg'] == 78.3, isTrue);
    });

    test('a target that already fits is never touched', () {
      final c = change(profile(target: 76.0), 'build_muscle'); // Cut 76 is invalid; Build 76 fits
      expect(c.patch.containsKey('target_weight_kg'), isFalse);
      expect(c.targetSeeded, isFalse);
    });

    test('a stored 0.0 or null target is seeded', () {
      expect(change(profile(target: 0.0), 'lose_fat').patch['target_weight_kg'], 70.0);
      expect(change(profile(target: null), 'lose_fat').patch['target_weight_kg'], 70.0);
    });

    test('no known current weight: nothing is seeded, nothing is judged', () {
      final p = profile()..remove('current_weight_kg');
      final c = change(p, 'build_muscle');
      expect(c.patch.containsKey('target_weight_kg'), isFalse);
    });

    test('a seed that would itself break the rule is not written (clamp edges)', () {
      // Cut at 40 kg: the 40..250 clamp turns 35 into 40, which is not below 40.
      final cut = change(profile(weight: 40.0, target: 45.0, goal: 'build_muscle'), 'lose_fat');
      expect(cut.patch.containsKey('target_weight_kg'), isFalse);
      // Build at 250 kg: the clamp turns 253 into 250, which is not above 250.
      final build = change(profile(weight: 250.0, target: 200.0), 'build_muscle');
      expect(build.patch.containsKey('target_weight_kg'), isFalse);
    });
  });

  group('the targets are recomputed with the goal, from the healed profile', () {
    test('the overlay is the shared function on the healed inputs', () {
      final p = profile();
      final c = change(p, 'build_muscle');
      final expected = recomputeDerivedTargets(
        <String, dynamic>{...p, 'primary_goal': 'build_muscle', 'target_weight_kg': 78.0},
        now: _now,
        bodyFatCalcDisabled: false,
      )!;
      for (final k in ['daily_calories', 'protein_grams', 'carb_grams', 'carbs_grams', 'fat_grams', 'bmr', 'tdee']) {
        expect(c.patch[k], expected[k], reason: k);
      }
      expect(c.patch['daily_calories'], isNot(2000));
    });

    test('the dual carb spelling is kept', () {
      final c = change(profile(), 'build_muscle');
      expect(c.patch['carb_grams'], c.patch['carbs_grams']);
    });

    test('Cut reads the SEEDED target: seed before overlay is observable', () {
      // Build 80 -> Cut: the stored 80 is invalid for Cut (ignored by the protein
      // base, which wants 0 < target < weight); the seed 70 is used.
      final p = profile(goal: 'build_muscle', target: 80.0);
      final c = change(p, 'lose_fat');
      final withSeed = recomputeDerivedTargets(
        <String, dynamic>{...p, 'primary_goal': 'lose_fat', 'target_weight_kg': 70.0},
        now: _now,
        bodyFatCalcDisabled: false,
      )!;
      final withStale = recomputeDerivedTargets(
        <String, dynamic>{...p, 'primary_goal': 'lose_fat'},
        now: _now,
        bodyFatCalcDisabled: false,
      )!;
      expect(c.patch['protein_grams'], withSeed['protein_grams']);
      expect(withSeed['protein_grams'], isNot(withStale['protein_grams']),
          reason: 'the fixture must make the seed order visible');
    });

    test('an incomplete profile (no birth date) writes goal and seed only', () {
      final c = change(profile(complete: false), 'build_muscle');
      expect(c.patch['target_weight_kg'], 78.0);
      expect(c.patch.containsKey('daily_calories'), isFalse);
      expect(c.patch.containsKey('protein_grams'), isFalse);
      expect(c.hasTargets, isFalse);
    });

    test('the preview numbers are the patch numbers', () {
      final c = change(profile(), 'build_muscle');
      expect(c.caloriesFrom, 2000);
      expect(c.caloriesTo, c.patch['daily_calories']);
      expect(c.proteinFrom, 150);
      expect(c.proteinTo, c.patch['protein_grams']);
      expect(c.targetsMoved, isTrue);
    });

    test('the input map is never mutated', () {
      final p = Map<String, dynamic>.unmodifiable(profile());
      expect(() => goalChange(p, newGoal: 'build_muscle', now: _now, bodyFatCalcDisabled: false),
          returnsNormally);
    });
  });

  group('a same-goal call never moves a stored value silently', () {
    test('consistent profile: goal only, no overlay, no seed', () {
      final c = change(profile(goal: 'lose_fat', target: 70.0), 'lose_fat');
      expect(c.patch.keys.toList(), ['primary_goal']);
      expect(c.goalChanged, isFalse);
      expect(c.targetsMoved, isFalse);
    });

    test('contradictory profile: it repairs the target and the targets', () {
      final c = change(profile(goal: 'build_muscle', target: 71.0), 'build_muscle');
      expect(c.patch['target_weight_kg'], 78.0);
      expect(c.patch.containsKey('daily_calories'), isTrue);
    });

    test('a legacy stored goal counts as a goal change', () {
      final c = change(profile(goal: 'strength', target: 80.0), 'build_muscle');
      expect(c.goalChanged, isTrue);
      expect(c.patch.containsKey('daily_calories'), isTrue);
    });
  });

  group('targetPrefill (what Edit Profile puts in the field, in kg)', () {
    double? pre({
      String goal = 'build_muscle',
      double? cur = 75.0,
      double? tgt = 71.0,
      double? original,
      bool prior = false,
    }) =>
        targetPrefill(
          goal: goal,
          currentKg: cur,
          targetKg: tgt,
          originalStoredTargetKg: original,
          priorPrefill: prior,
        );

    test('a target that fits the goal is left alone', () {
      expect(pre(tgt: 80.0), isNull);
    });
    test('a target that breaks the goal gets the seed', () {
      expect(pre(), 78.0);
      expect(pre(goal: 'lose_fat', tgt: 80.0), 70.0);
      expect(pre(goal: 'general_fitness', tgt: 90.0), 75.0);
    });
    test('an empty or 0.0 target gets the seed', () {
      expect(pre(tgt: null), 78.0);
      expect(pre(tgt: 0.0), 78.0);
    });
    test('an unknown current weight changes nothing', () {
      expect(pre(cur: null), isNull);
      expect(pre(cur: 0.0), isNull);
    });
    test('a prior prefill that is not a user edit restores the original (Cut 71 -> Build -> Cut)', () {
      // The field holds 78.0 (prefilled for Build); back on Cut, 71.0 fits.
      expect(pre(goal: 'lose_fat', tgt: 78.0, original: 71.0, prior: true), 71.0);
    });
    test('a typed value is not a prior prefill: the seed is used, the original is not', () {
      expect(pre(goal: 'lose_fat', tgt: 78.0, original: 71.0, prior: false), 70.0);
    });
    test('an original that does not fit the new goal is not restored', () {
      expect(pre(goal: 'lose_fat', tgt: 78.0, original: 90.0, prior: true), 70.0);
    });
    test('the seed always satisfies the goal it was made for', () {
      for (final g in const ['lose_fat', 'build_muscle', 'general_fitness']) {
        final t = pre(goal: g, tgt: 0.0)!;
        expect(validateTargetWeight(goal: g, current: 75.0, target: t),
            TargetWeightCheck.ok, reason: g);
      }
    });
  });
  group('resolveFieldKg (the stored-kg rule: an untouched field saves the exact stored kg)', () {
    test('imperial: an unedited whole-pound field keeps the stored kg, not the re-conversion', () {
      // 75.0 kg shows as 165 lbs; 165 / 2.20462 = 74.84 would drift the stored weight.
      expect(
          resolveFieldKg(
              text: '165', initialText: '165', storedKg: 75.0, parsed: 165, metric: false),
          75.0);
      expect(
          resolveFieldKg(
              text: ' 165 ', initialText: '165', storedKg: 75.0, parsed: 165, metric: false),
          75.0,
          reason: 'surrounding spaces are not an edit');
    });

    test('an edited field is the typed number, converted from lbs when not metric', () {
      expect(
          resolveFieldKg(
              text: '170', initialText: '165', storedKg: 75.0, parsed: 170, metric: false),
          closeTo(170 / kLbsPerKg, 1e-9));
      expect(
          resolveFieldKg(
              text: '76.5', initialText: '75.0', storedKg: 75.0, parsed: 76.5, metric: true),
          76.5);
    });

    test('nothing to read is null; a missing stored kg falls back to the typed number', () {
      expect(
          resolveFieldKg(
              text: '', initialText: '', storedKg: null, parsed: null, metric: true),
          isNull);
      expect(
          resolveFieldKg(
              text: '80', initialText: '', storedKg: null, parsed: 80, metric: true),
          80.0);
    });
  });
}
