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

  // ---- OI-191: the shared goal / target agreement rules ----

  group('a non-positive weight or target is missing (OI-191)', () {
    test('Cut with a stored 0.0 target is missing, not ok', () {
      expect(v('lose_fat', 75, 0), TargetWeightCheck.missing);
    });
    test('Build and Maintain with 0.0 are missing too', () {
      expect(v('build_muscle', 75, 0), TargetWeightCheck.missing);
      expect(v('general_fitness', 75, 0), TargetWeightCheck.missing);
    });
    test('a negative target and a zero current weight are missing', () {
      expect(v('lose_fat', 75, -3), TargetWeightCheck.missing);
      expect(v('lose_fat', 0, 70), TargetWeightCheck.missing);
    });
    test('a goal with no rule stays ok even with a null or 0 target', () {
      expect(v('recomp', 75, null), TargetWeightCheck.ok);
      expect(v('strength', 75, 0), TargetWeightCheck.ok);
      expect(v('whatever', null, null), TargetWeightCheck.ok);
    });
  });

  group('goalTargetAgree', () {
    bool a(String g, double? c, double? t) =>
        goalTargetAgree(goal: g, current: c, target: t);
    test('is exactly validateTargetWeight == ok', () {
      expect(a('lose_fat', 75, 70), isTrue);
      expect(a('lose_fat', 75, 78), isFalse);
      expect(a('build_muscle', 75, 71), isFalse);
      expect(a('general_fitness', 75, 77.9), isTrue);
      expect(a('general_fitness', 75, 80), isFalse);
      expect(a('lose_fat', 75, 0), isFalse);
    });
    test('a goal with no rule agrees', () => expect(a('recomp', 75, 71), isTrue));
  });

  group('canProjectGoalDate', () {
    bool c(String g, double? cur, double? t) =>
        canProjectGoalDate(goal: g, current: cur, target: t);
    test('Cut and Build with the target on the right side project', () {
      expect(c('lose_fat', 75, 70), isTrue);
      expect(c('build_muscle', 75, 80), isTrue);
    });
    test('the contradictory pair does not project (the OI-191 bug)', () {
      expect(c('build_muscle', 75, 71), isFalse);
      expect(c('lose_fat', 75, 80), isFalse);
    });
    test('a stored 0.0 target does not project', () {
      expect(c('lose_fat', 75, 0), isFalse);
    });
    test('Maintain, legacy and unknown goals never project', () {
      expect(c('general_fitness', 75, 77), isFalse);
      expect(c('strength', 75, 70), isFalse);
    });
    test('a gap of 0.1 kg or less does not project', () {
      expect(c('lose_fat', 75, 74.95), isFalse);
      expect(c('lose_fat', 75, 74.8), isTrue);
    });
    test('a missing or non-finite weight does not project', () {
      expect(c('lose_fat', null, 70), isFalse);
      expect(c('lose_fat', 75, double.nan), isFalse);
    });
  });

  group('projectionCalloutKind: the branch ORDER is part of the contract', () {
    ProjectionCalloutKind k(String g, double first, double last, double weeks,
            double target) =>
        projectionCalloutKind(
            goal: g, firstW: first, lastW: last, weeksDiff: weeks, target: target);
    test('too little history is none (Cut, Build and the legacy goals)', () {
      expect(k('lose_fat', 80, 79, 0.4, 70), ProjectionCalloutKind.none);
      expect(k('build_muscle', 75, 76, 0.4, 80), ProjectionCalloutKind.none);
      expect(k('recomp', 75, 76, 0.4, 80), ProjectionCalloutKind.none);
      expect(k('', 75, 76, 0.4, 80), ProjectionCalloutKind.none);
    });
    test('exactly half a week of history passes the gate for Cut and Build', () {
      expect(k('lose_fat', 80, 79, 0.5, 70), ProjectionCalloutKind.eta);
      expect(k('build_muscle', 75, 76, 0.5, 80), ProjectionCalloutKind.eta);
    });
    test('a Cut already at the target is REACHED, not hidden by the gate', () {
      // 78 / 78 fails goalTargetAgree (mustBeBelowCurrent); the reached branch
      // comes first and stays.
      expect(k('lose_fat', 79, 78, 2, 78), ProjectionCalloutKind.reached);
    });
    test('a Cut falling toward a target above the last weigh-in is none', () {
      // last 77, target 78, rate negative: the old code printed an ETA.
      expect(k('lose_fat', 79, 77, 2, 78), ProjectionCalloutKind.none);
    });
    test('a Build rising past a below-current target is none', () {
      expect(k('build_muscle', 75, 77, 2, 75), ProjectionCalloutKind.none);
    });
    test('a Cut moving the wrong way is adjust', () {
      expect(k('lose_fat', 77, 78, 2, 70), ProjectionCalloutKind.adjust);
    });
    test('a consistent Cut or Build gets the date sentence', () {
      expect(k('lose_fat', 80, 78, 2, 70), ProjectionCalloutKind.eta);
      expect(k('build_muscle', 75, 76, 2, 80), ProjectionCalloutKind.eta);
    });
    test('a flat Cut / Build series with the target exactly 0.5 kg away is none, '
        'not a divide by a zero rate (OI-518, plan round 3)', () {
      // remaining = -0.5 / +0.5 exactly: skips `adjust` (needs > 0.5) and
      // `reached` (needs < 0.5); the date sentence used to take Infinity.ceil().
      expect(k('lose_fat', 80.0, 80.0, 2, 79.5), ProjectionCalloutKind.none);
      expect(k('build_muscle', 80.0, 80.0, 2, 80.5), ProjectionCalloutKind.none);
    });
  });

  // OI-518: a Maintain goal is judged by the DISTANCE of the last weigh-in to the
  // target (the +-3.0 kg window), never by the trend direction, and never gets a
  // date or an "Adjust" verdict inside the window.
  group('projectionCalloutKind: Maintain (general_fitness) is distance, not direction', () {
    ProjectionCalloutKind m(double first, double last, double weeks, double target) =>
        projectionCalloutKind(
            goal: 'general_fitness',
            firstW: first,
            lastW: last,
            weeksDiff: weeks,
            target: target);
    test('inside the window the trend does not matter (falling, rising, flat)', () {
      expect(m(76, 74, 2, 75), ProjectionCalloutKind.onTarget); // the old `adjust`
      expect(m(74, 76, 2, 75), ProjectionCalloutKind.onTarget);
      expect(m(75, 75, 2, 75), ProjectionCalloutKind.onTarget);
      expect(m(74, 75, 2, 77), ProjectionCalloutKind.onTarget); // the old `eta`
    });
    test('the old reached zone does not win', () {
      expect(m(74, 75.2, 2, 75), ProjectionCalloutKind.onTarget);
      expect(m(76, 74.8, 2, 75), ProjectionCalloutKind.onTarget);
    });
    test('the LAST weigh-in decides, not the first', () {
      expect(m(80, 76, 2, 75), ProjectionCalloutKind.onTarget);
      expect(m(76, 80, 2, 75), ProjectionCalloutKind.offTarget);
    });
    test('the window edge is inclusive, in integer tenths', () {
      expect(m(76, 78.3, 2, 75.3), ProjectionCalloutKind.onTarget); // 3.0
      expect(m(76, 78.4, 2, 75.3), ProjectionCalloutKind.offTarget); // 3.1
      expect(m(76, 72.3, 2, 75.3), ProjectionCalloutKind.onTarget);
      expect(m(76, 72.2, 2, 75.3), ProjectionCalloutKind.offTarget);
    });
    test('beyond the window on either side is offTarget, never a date', () {
      expect(m(74, 75, 2, 80), ProjectionCalloutKind.offTarget);
      expect(m(76, 74, 2, 80), ProjectionCalloutKind.offTarget);
      expect(m(76, 79, 2, 70), ProjectionCalloutKind.offTarget);
    });
    test('a big swing in either direction does not hide the distance (no trend gate)', () {
      expect(m(85, 75, 2, 75), ProjectionCalloutKind.onTarget);
      expect(m(65, 75, 2, 75), ProjectionCalloutKind.onTarget);
      expect(m(65, 79, 2, 75), ProjectionCalloutKind.offTarget);
      expect(m(90, 79, 2, 75), ProjectionCalloutKind.offTarget);
    });
    test('Maintain has no history gate (founder 2026-11-19): a distance needs no span', () {
      for (final weeks in [0.0, 0.4, 0.5, 2.0]) {
        expect(m(75, 75, weeks, 75), ProjectionCalloutKind.onTarget);
        expect(m(75, 79, weeks, 75), ProjectionCalloutKind.offTarget);
      }
    });
    test('Maintain with a missing target is still none at zero weeks', () {
      expect(m(75, 75, 0, 0), ProjectionCalloutKind.none);
      expect(m(75, 75, 0.4, double.nan), ProjectionCalloutKind.none);
    });
    test('a missing target or weight is none', () {
      expect(m(75, 75, 2, 0), ProjectionCalloutKind.none);
      expect(m(75, 75, 2, -3), ProjectionCalloutKind.none);
      expect(m(75, 75, 2, double.nan), ProjectionCalloutKind.none);
      expect(m(75, 75, 2, double.infinity), ProjectionCalloutKind.none);
      expect(m(75, 0, 2, 75), ProjectionCalloutKind.none);
      expect(m(75, double.nan, 2, 75), ProjectionCalloutKind.none);
    });
    test('Cut and Build never return the Maintain kinds', () {
      for (final g in ['lose_fat', 'build_muscle', 'recomp', '']) {
        for (final (first, last, target) in [
          (76.0, 74.0, 75.0),
          (74.0, 76.0, 75.0),
          (75.0, 75.0, 75.0),
          (76.0, 79.0, 70.0),
        ]) {
          final kind = projectionCalloutKind(
              goal: g, firstW: first, lastW: last, weeksDiff: 2, target: target);
          expect(kind, isNot(ProjectionCalloutKind.onTarget), reason: '$g');
          expect(kind, isNot(ProjectionCalloutKind.offTarget), reason: '$g');
        }
      }
    });
  });

  group('weightGapTenths: the one expression of the gap', () {
    test('signed tenths of target - current, rounded', () {
      expect(weightGapTenths(73.8, 75), 12);
      expect(weightGapTenths(78.4, 75), -34);
      expect(weightGapTenths(75, 75), 0);
      // 75.3 - 78.3 is not exactly -3.0 in doubles; the tenths are still -30.
      expect(weightGapTenths(78.3, 75.3), -30);
      // measured 2026-11-18: (70.0 - 66.9) * 10 = 30.999999999999943 -> 31, not 30.
      expect(weightGapTenths(66.9, 70.0), 31);
    });
    test('validateTargetWeight still agrees with the same window', () {
      expect(
          validateTargetWeight(goal: 'general_fitness', current: 66.9, target: 70.0),
          TargetWeightCheck.outsideMaintainWindow);
      expect(
          validateTargetWeight(goal: 'general_fitness', current: 78.3, target: 75.3),
          TargetWeightCheck.ok);
    });
  });

  group('canProjectGoalDate: the 0.1 kg gate is inclusive', () {
    test('a gap of exactly 0.1 kg (0.2 - 0.1 is exactly 0.1 in doubles) is no date', () {
      expect(0.2 - 0.1 == 0.1, isTrue); // the premise, checked here
      expect(canProjectGoalDate(goal: 'lose_fat', current: 0.2, target: 0.1), isFalse);
      expect(canProjectGoalDate(goal: 'lose_fat', current: 80.0, target: 79.8), isTrue);
    });
  });

  group('journeyEtaAllowed', () {
    test('false for a contradictory pair, true for an agreeing one', () {
      expect(journeyEtaAllowed(goal: 'lose_fat', lastValue: 77, target: 78), isFalse);
      expect(journeyEtaAllowed(goal: 'lose_fat', lastValue: 80, target: 70), isTrue);
      expect(journeyEtaAllowed(goal: 'build_muscle', lastValue: 75, target: 70), isFalse);
    });
  });

  group('targetWeightMessage editing variant', () {
    test('onboarding words are byte-identical', () {
      expect(targetWeightMessage(TargetWeightCheck.missing, 75),
          'Enter your target weight to continue.');
      expect(targetWeightMessage(TargetWeightCheck.mustBeBelowCurrent, 75),
          'For a Cut your target has to be lower than your current weight (75.0 kg). Adjust it and continue.');
    });
    test('editing swaps only the closing words', () {
      expect(targetWeightMessage(TargetWeightCheck.missing, 75, editing: true),
          'Enter your target weight to save.');
      expect(
          targetWeightMessage(TargetWeightCheck.mustBeAboveCurrent, 75,
              editing: true),
          'For a Build your target has to be higher than your current weight (75.0 kg). Adjust it and save.');
      expect(
          targetWeightMessage(TargetWeightCheck.outsideMaintainWindow, 75,
              editing: true),
          endsWith('Adjust it and save.'));
    });
  });

  group('targetWeightMessage in pounds (Edit Profile imperial users)', () {
    test('the weights read in whole pounds, the words stay', () {
      expect(
          targetWeightMessage(TargetWeightCheck.mustBeBelowCurrent, 75,
              editing: true, metric: false),
          'For a Cut your target has to be lower than your current weight (165 lbs). Adjust it and save.');
      expect(
          targetWeightMessage(TargetWeightCheck.mustBeAboveCurrent, 75,
              editing: true, metric: false),
          'For a Build your target has to be higher than your current weight (165 lbs). Adjust it and save.');
    });
    test('the Maintain window is stated in pounds, both ends and the width', () {
      // 3 kg = 6.6 lbs -> 7; 72 kg = 159 lbs, 78 kg = 172 lbs.
      expect(
          targetWeightMessage(TargetWeightCheck.outsideMaintainWindow, 75,
              editing: true, metric: false),
          'To maintain, keep your target within 7 lbs of your current weight (159–172 lbs). Adjust it and save.');
    });
    test('metric stays the default and no "kg" leaks into the pound text', () {
      expect(
          targetWeightMessage(TargetWeightCheck.outsideMaintainWindow, 75),
          contains('(72.0–78.0 kg)'));
      for (final c in [
        TargetWeightCheck.mustBeBelowCurrent,
        TargetWeightCheck.mustBeAboveCurrent,
        TargetWeightCheck.outsideMaintainWindow,
      ]) {
        expect(targetWeightMessage(c, 75, metric: false), isNot(contains('kg')));
      }
    });
  });
}
