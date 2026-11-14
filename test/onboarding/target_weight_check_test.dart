// Pure rules for the Stats target weight (founder call 2026-11-01).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/onboarding/target_weight_check.dart';

TargetWeightCheck v(String goal, double? cur, double? tgt) =>
    validateTargetWeight(goal: goal, current: cur, target: tgt);

void main() {
  group('Cut (lose_fat): strictly below current', () {
    test('lower is ok', () => expect(v('lose_fat', 75, 70), TargetWeightCheck.ok));
    test('0.1 lower is ok',
        () => expect(v('lose_fat', 75, 74.9), TargetWeightCheck.ok));
    test('equal is invalid',
        () => expect(v('lose_fat', 75, 75), TargetWeightCheck.mustBeBelowCurrent));
    test('higher is invalid',
        () => expect(v('lose_fat', 75, 80), TargetWeightCheck.mustBeBelowCurrent));
    test('0.1 higher is invalid', () {
      expect(v('lose_fat', 75, 75.1), TargetWeightCheck.mustBeBelowCurrent);
    });
  });

  group('Build (build_muscle): strictly above current', () {
    test('higher is ok',
        () => expect(v('build_muscle', 75, 78), TargetWeightCheck.ok));
    test('0.1 higher is ok',
        () => expect(v('build_muscle', 75, 75.1), TargetWeightCheck.ok));
    test('equal is invalid', () {
      expect(v('build_muscle', 75, 75), TargetWeightCheck.mustBeAboveCurrent);
    });
    test('lower is invalid', () {
      expect(v('build_muscle', 75, 70), TargetWeightCheck.mustBeAboveCurrent);
    });
    test('0.1 lower is invalid', () {
      expect(v('build_muscle', 75, 74.9), TargetWeightCheck.mustBeAboveCurrent);
    });
  });

  group('Maintain (general_fitness): within 3.0 kg inclusive', () {
    test('equal ok', () => expect(v('general_fitness', 75, 75), TargetWeightCheck.ok));
    test('+3.0 ok', () => expect(v('general_fitness', 75, 78), TargetWeightCheck.ok));
    test('-3.0 ok', () => expect(v('general_fitness', 75, 72), TargetWeightCheck.ok));
    test('+3.1 invalid', () {
      expect(v('general_fitness', 75, 78.1),
          TargetWeightCheck.outsideMaintainWindow);
    });
    test('-3.1 invalid', () {
      expect(v('general_fitness', 75, 71.9),
          TargetWeightCheck.outsideMaintainWindow);
    });
    test('float trap: 78.3 vs 75.3 is exactly +3.0 and ok', () {
      // 78.3 - 75.3 is not exactly 3.0 in binary floating point.
      expect(v('general_fitness', 75.3, 78.3), TargetWeightCheck.ok);
      expect(v('general_fitness', 78.3, 75.3), TargetWeightCheck.ok);
    });
    test('float trap (the REAL one): 64.4 - 61.4 is 3.000000000000007 in doubles '
        'yet is exactly +3.0 and must be ok', () {
      // Raw `(t - c).abs() <= 3.0` rejects this valid pair (found by sweeping every
      // one-decimal pair; 24 pairs in 40-250 kg misbehave). Tenths arithmetic is exact.
      expect(64.4 - 61.4 > 3.0, isTrue, reason: 'precondition: the double trap is real');
      expect(v('general_fitness', 61.4, 64.4), TargetWeightCheck.ok);
      expect(v('general_fitness', 61.9, 64.9), TargetWeightCheck.ok);
      expect(v('general_fitness', 64.4, 61.4), TargetWeightCheck.ok);
    });
    test('float trap: 78.4 vs 75.3 is +3.1 and invalid', () {
      expect(v('general_fitness', 75.3, 78.4),
          TargetWeightCheck.outsideMaintainWindow);
    });
  });

  group('missing / non-finite / unvalidated goals', () {
    test('blank target is missing for the three validated goals', () {
      for (final g in const ['lose_fat', 'build_muscle', 'general_fitness']) {
        expect(v(g, 75, null), TargetWeightCheck.missing, reason: g);
      }
    });
    test('NaN and Infinity are missing', () {
      expect(v('lose_fat', 75, double.nan), TargetWeightCheck.missing);
      expect(v('build_muscle', 75, double.infinity), TargetWeightCheck.missing);
      expect(v('general_fitness', double.nan, 75), TargetWeightCheck.missing);
    });
    test('recomp / strength / unknown have no rule (even blank)', () {
      for (final g in const ['recomp', 'recompose', 'strength', 'whatever']) {
        expect(v(g, 75, null), TargetWeightCheck.ok, reason: g);
        expect(v(g, 75, 200), TargetWeightCheck.ok, reason: g);
      }
    });
    test('uses the RAW value: Build at current 250 with target 250 is invalid, '
        '260 is ok (no clamp inside the validator)', () {
      expect(v('build_muscle', 250, 250), TargetWeightCheck.mustBeAboveCurrent);
      expect(v('build_muscle', 250, 260), TargetWeightCheck.ok);
    });
  });

  group('messages', () {
    test('every failing check has non-empty copy, ok is empty', () {
      for (final c in TargetWeightCheck.values) {
        final m = targetWeightMessage(c, 75);
        expect(m.isEmpty, c == TargetWeightCheck.ok, reason: '$c');
      }
    });
    test('maintain message states the real window', () {
      final m = targetWeightMessage(TargetWeightCheck.outsideMaintainWindow, 75);
      expect(m, contains('72.0'));
      expect(m, contains('78.0'));
    });
  });

  group('seedTargetWeight', () {
    double seed(String g, double cur, {Object? stored, Object? seededFor}) =>
        seedTargetWeight(
          goal: g,
          currentKg: cur,
          storedTarget: stored,
          seededForGoal: seededFor,
        );
    test('no stored target: Cut -5, Build +3, Maintain = current', () {
      expect(seed('lose_fat', 75), 70);
      expect(seed('build_muscle', 75), 78);
      expect(seed('general_fitness', 75), 75);
    });
    test('seed is clamped to 40-250', () {
      expect(seed('lose_fat', 42), 40);
      expect(seed('build_muscle', 249), 250);
    });
    test('same-goal BACK keeps the user edit', () {
      expect(seed('lose_fat', 75, stored: 68.5, seededFor: 'lose_fat'), 68.5);
    });
    test('goal changed after BACK reseeds (Cut target must not survive a Build)', () {
      expect(seed('build_muscle', 75, stored: 70.0, seededFor: 'lose_fat'), 78);
    });
    test('legacy extras with no seeded_for_goal keep the stored target', () {
      expect(seed('lose_fat', 75, stored: 68.5), 68.5);
    });
    test('BACK with a blank target (null) reseeds from the delta', () {
      expect(seed('lose_fat', 75, stored: null, seededFor: 'lose_fat'), 70);
    });
    test('the seed for each offered goal satisfies its own rule', () {
      for (final g in const ['lose_fat', 'build_muscle', 'general_fitness']) {
        final t = seed(g, 75);
        expect(v(g, 75, t), TargetWeightCheck.ok, reason: g);
      }
    });
  });
}
