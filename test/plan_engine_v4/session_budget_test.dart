// B2 Task 1 (docs/plans/2026-10-22-session-set-budget.md): the budget model and
// the ledger. Pure Dart, no Hive. Every literal below is computed from the
// plan's constants (Rulings 2, 3, 4), not read back from the code.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';

import '_helpers.dart';

SessionBudgetContext ctx({
  int minutes = 60,
  String planGoal = 'build_muscle',
  String level = 'intermediate',
  bool lighterPhase = false,
  Set<String> focusGroups = const {},
  int finisherSeconds = 0,
}) =>
    SessionBudgetContext(
      minutes: minutes,
      planGoal: planGoal,
      level: level,
      lighterPhase: lighterPhase,
      focusGroups: focusGroups,
      finisherSeconds: finisherSeconds,
      archetypeByName: const {},
    );

void main() {
  group('warmCoolMinutes (Ruling 3: affine, clamped to 6..14)', () {
    test('the five anchor points', () {
      expect(SessionBudget.warmCoolMinutes(30), 6.0);
      expect(SessionBudget.warmCoolMinutes(45), closeTo(8.0, 1e-9));
      expect(SessionBudget.warmCoolMinutes(60), closeTo(10.0, 1e-9));
      expect(SessionBudget.warmCoolMinutes(75), closeTo(12.0, 1e-9));
      expect(SessionBudget.warmCoolMinutes(90), closeTo(14.0, 1e-9));
    });

    test('linear between the anchors', () {
      // 45 + 7 minutes: 8 + 7 * 2 / 15
      expect(SessionBudget.warmCoolMinutes(52), closeTo(8.9333333, 1e-6));
    });

    test('clamped at both ends', () {
      expect(SessionBudget.warmCoolMinutes(20), 6.0);
      expect(SessionBudget.warmCoolMinutes(15), 6.0);
      expect(SessionBudget.warmCoolMinutes(120), 14.0);
      expect(SessionBudget.warmCoolMinutes(180), 14.0);
    });
  });

  group('exerciseSeconds (Ruling 2: 1.20 x (overhead + sets*work + (sets-1)*rest))', () {
    test('M, 4 sets, 75 s rest = 1.2 x (90 + 140 + 225) = 546', () {
      expect(SessionBudget.exerciseSeconds(archetype: 'M', sets: 4, restSeconds: 75),
          closeTo(546.0, 1e-9));
    });

    test('I, 3 sets, 150 s rest = 1.2 x (45 + 141 + 300) = 583.2', () {
      expect(SessionBudget.exerciseSeconds(archetype: 'I', sets: 3, restSeconds: 150),
          closeTo(583.2, 1e-9));
    });

    test('H, 1 set has no rest term: 1.2 x (120 + 23) = 171.6', () {
      expect(SessionBudget.exerciseSeconds(archetype: 'H', sets: 1, restSeconds: 150),
          closeTo(171.6, 1e-9));
    });

    test('B, 2 sets, 30 s rest = 1.2 x (30 + 80 + 30) = 168', () {
      expect(SessionBudget.exerciseSeconds(archetype: 'B', sets: 2, restSeconds: 30),
          closeTo(168.0, 1e-9));
    });

    test('zero sets cost nothing and never go negative', () {
      expect(SessionBudget.exerciseSeconds(archetype: 'M', sets: 0, restSeconds: 75), 0.0);
    });

    test('more sets always cost more; a longer rest always costs more', () {
      for (final a in ['H', 'M', 'I', 'B']) {
        var prev = 0.0;
        for (var s = 1; s <= 5; s++) {
          final t = SessionBudget.exerciseSeconds(archetype: a, sets: s, restSeconds: 75);
          expect(t, greaterThan(prev), reason: '$a $s');
          prev = t;
        }
        expect(SessionBudget.exerciseSeconds(archetype: a, sets: 3, restSeconds: 150),
            greaterThan(SessionBudget.exerciseSeconds(archetype: a, sets: 3, restSeconds: 75)));
      }
    });
  });

  group('archetypeOf (Ruling 2)', () {
    String a(List<String> types, String reps, String logging) =>
        SessionBudget.archetypeOf(exerciseTypes: types, reps: reps, loggingType: logging);

    test('type precedence: compound > isolation > calisthenics > other', () {
      expect(a(['calisthenics', 'isolation'], '12-20', 'bodyweight_reps'), 'I');
      expect(a(['calisthenics', 'compound'], '5-8', 'bodyweight_reps'), 'H');
      expect(a(['isolation', 'compound'], '8-12', 'weight_reps'), 'M');
    });

    test('compound: lower bound <= 6 is H, otherwise M (6 is H, 7 is M)', () {
      expect(a(['compound'], '5-8', 'weight_reps'), 'H');
      expect(a(['compound'], '6-10', 'weight_reps'), 'H');
      expect(a(['compound'], '7-10', 'weight_reps'), 'M');
      expect(a(['compound'], '8-12', 'weight_reps'), 'M');
    });

    test('a compound with no usable rep range is M', () {
      expect(a(['compound'], '', 'weight_reps'), 'M');
      expect(a(['compound'], 'AMRAP', 'weight_reps'), 'M');
    });

    test('calisthenics: lower bound <= 10 is M (10 is M, 11 is B)', () {
      expect(a(['calisthenics'], '8-15', 'bodyweight_reps'), 'M');
      expect(a(['calisthenics'], '10-15', 'bodyweight_reps'), 'M');
      expect(a(['calisthenics'], '11-15', 'bodyweight_reps'), 'B');
      expect(a(['calisthenics'], '12-20', 'bodyweight_reps'), 'B');
      expect(a(['calisthenics'], '', 'bodyweight_reps'), 'B');
    });

    test('isolation is I whatever the range', () {
      expect(a(['isolation'], '12-15', 'weight_reps'), 'I');
      expect(a(['isolation'], '', 'weight_reps'), 'I');
    });

    test('any other type is B', () {
      for (final t in ['flexibility', 'activation', 'cardio', 'yoga', 'dynamic_stretch']) {
        expect(a([t], '10-12', 'reps_only'), 'B', reason: t);
      }
    });

    test('timed, cardio and distance logging is B whatever the type', () {
      expect(a(['compound'], '5-8', 'timed'), 'B');
      expect(a(['isolation'], '30-60', 'timed'), 'B');
      expect(a(['compound'], '5-8', 'cardio'), 'B');
      expect(a(['compound'], '5-8', 'distance'), 'B');
    });
  });

  group('archetypeOfRow', () {
    test('accepts exercise_type as a List, a String or null', () {
      expect(
          SessionBudget.archetypeOfRow(
              {'exercise_type': ['compound'], 'rep_range': '5-8', 'logging_type': 'weight_reps'}),
          'H');
      expect(
          SessionBudget.archetypeOfRow(
              {'exercise_type': 'compound', 'rep_range': '5-8', 'logging_type': 'weight_reps'}),
          'H');
      // A null type is treated as compound everywhere (the display rule, Task 6b).
      expect(
          SessionBudget.archetypeOfRow({'rep_range': '8-12', 'logging_type': 'weight_reps'}),
          'M');
    });

    test('a row with no logging_type is read as rep-based', () {
      expect(
          SessionBudget.archetypeOfRow({'exercise_type': ['isolation'], 'rep_range': '10-15'}),
          'I');
    });

    test('a null element of the type list is skipped, never read as the type "null" (B-pass R1 P3-4)', () {
      // [null] is "no type" = compound, so a 5-8 row is H, not the B a "null" string
      // type would give it.
      expect(
          SessionBudget.archetypeOfRow(
              {'exercise_type': [null], 'rep_range': '5-8', 'logging_type': 'weight_reps'}),
          'H');
      expect(
          SessionBudget.archetypeOfRow({
            'exercise_type': [null, 'isolation'],
            'rep_range': '10-15',
            'logging_type': 'weight_reps'
          }),
          'I');
    });

    test('over the shipped library: Bench Press is H, a timed hold is B, all rows map', () {
      final rows = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
              as List)
          .cast<Map<String, dynamic>>();
      final byName = {for (final r in rows) r['name'] as String: r};
      expect(SessionBudget.archetypeOfRow(byName['Barbell Bench Press']!), 'H');
      final timed = rows.firstWhere((r) => r['logging_type'] == 'timed');
      expect(SessionBudget.archetypeOfRow(timed), 'B');
      for (final r in rows) {
        expect({'H', 'M', 'I', 'B'}, contains(SessionBudget.archetypeOfRow(r)),
            reason: r['name'] as String);
      }
    });
  });

  group('isRepBased (the one rep-based set, B-pass R1 P3-9)', () {
    test('the four rep-progressed logging types, and nothing else', () {
      for (final t in ['weight_reps', 'bodyweight_reps', 'weighted_bodyweight', 'reps_only']) {
        expect(SessionBudget.isRepBased(t), isTrue, reason: t);
      }
      for (final t in ['timed', 'cardio', 'distance', '', 'unknown']) {
        expect(SessionBudget.isRepBased(t), isFalse, reason: t);
      }
    });
  });

  group('restFor / desiredFor agree with PeriodizationEngine (the mirror)', () {
    // The model keeps its own table (Ruling 2: all constants in one place), so
    // the engine's `_profileParams` and this table could drift apart silently.
    // Drive the real engine and compare.
    for (final intensity in ['strength', 'hypertrophy', 'endurance', 'something_unknown']) {
      test('$intensity: the engine stamps the rest and base sets the model assumes', () {
        final day = populatedDay(
          intensity: intensity,
          exercisesA: [exercise(name: 'Bench Press', exerciseType: 'compound', sets: 9)],
        );
        final weeks = PeriodizationEngine.apply(
          populated: [day],
          phase: 1,
          is6Day: true,
          effectiveExp: 'beginner', // no 4-set minimum, no cycle multiplier at phase 1
        );
        final ex = weeks[0].workoutDays[0].exercises[0];
        expect(SessionBudget.restFor(intensity), ex.restSeconds);
        expect(SessionBudget.desiredFor(intensity), ex.sets);
      });
    }

    test('the literal table: strength 150 / 4, hypertrophy 75 / 3, endurance 38 / 2, unknown 75 / 3', () {
      expect([for (final i in ['strength', 'hypertrophy', 'endurance', 'x']) SessionBudget.restFor(i)],
          [150, 75, 38, 75]);
      expect([for (final i in ['strength', 'hypertrophy', 'endurance', 'x']) SessionBudget.desiredFor(i)],
          [4, 3, 2, 3]);
    });
  });

  group('bands and caps (Ruling 4)', () {
    test('weekly bands', () {
      expect(SessionBudget.weeklyBand('build_muscle', 'intermediate'), (bottom: 12, top: 16));
      expect(SessionBudget.weeklyBand('build_muscle', 'beginner'), (bottom: 10, top: 12));
      expect(SessionBudget.weeklyBand('build_muscle', 'advanced'), (bottom: 14, top: 20));
      expect(SessionBudget.weeklyBand('strength', 'intermediate'), (bottom: 10, top: 14));
      expect(SessionBudget.weeklyBand('lose_fat', 'advanced'), (bottom: 12, top: 16));
      expect(SessionBudget.weeklyBand('general_fitness', 'beginner'), (bottom: 10, top: 10));
      expect(SessionBudget.weeklyBand('general_fitness', 'advanced'), (bottom: 12, top: 14));
    });

    test('session caps', () {
      expect(SessionBudget.sessionCap('build_muscle', 'beginner'), 6);
      expect(SessionBudget.sessionCap('build_muscle', 'intermediate'), 8);
      expect(SessionBudget.sessionCap('build_muscle', 'advanced'), 10);
      expect(SessionBudget.sessionCap('strength', 'advanced'), 10);
      expect(SessionBudget.sessionCap('lose_fat', 'advanced'), 8);
      expect(SessionBudget.sessionCap('general_fitness', 'advanced'), 8);
    });

    test('an unknown goal uses build_muscle, an unknown level uses intermediate', () {
      expect(SessionBudget.weeklyBand('recomp', 'intermediate'), (bottom: 12, top: 16));
      expect(SessionBudget.weeklyBand('build_muscle', 'elite'), (bottom: 12, top: 16));
      expect(SessionBudget.weeklyBand('???', '???'), (bottom: 12, top: 16));
      expect(SessionBudget.sessionCap('recomp', 'elite'), 8);
      expect(SessionBudget.sessionCap('lose_fat', 'elite'), 8);
    });

    test('every band is ordered and no cap exceeds the focus cap', () {
      for (final g in ['build_muscle', 'strength', 'lose_fat', 'general_fitness']) {
        for (final l in ['beginner', 'intermediate', 'advanced']) {
          final b = SessionBudget.weeklyBand(g, l);
          expect(b.bottom, lessThanOrEqualTo(b.top), reason: '$g $l');
          expect(SessionBudget.sessionCap(g, l), lessThanOrEqualTo(SessionBudget.focusSessionCap));
          expect(b.top, lessThan(SessionBudget.focusWeeklyTop));
        }
      }
    });

    test('the focus constants', () {
      expect(SessionBudget.focusWeeklyTop, 25);
      expect(SessionBudget.focusSessionCap, 12);
      expect(SessionBudget.maxSetsPerExercise, 5);
    });
  });

  group('SessionBudgetContext is immutable', () {
    test('changing the inputs after construction does not change the context', () {
      final focus = <String>{'Chest'};
      final arche = <String, String>{'bench press': 'H'};
      final c = SessionBudgetContext(
        minutes: 60,
        planGoal: 'build_muscle',
        level: 'intermediate',
        lighterPhase: false,
        focusGroups: focus,
        archetypeByName: arche,
      );
      focus.add('Back');
      arche['squat'] = 'H';
      expect(c.focusGroups, {'Chest'});
      expect(c.archetypeByName, {'bench press': 'H'});
    });

    test('its collections reject writes', () {
      final c = ctx(focusGroups: {'Chest'});
      expect(() => c.focusGroups.add('Back'), throwsUnsupportedError);
      expect(() => c.archetypeByName['x'] = 'H', throwsUnsupportedError);
    });

    test('finisherSeconds defaults to 0 (Ruling 6)', () {
      expect(ctx().finisherSeconds, 0);
    });
  });

  group('BudgetLedger', () {
    test('the day budget is (minutes - warm-up/cool-down) x 60 - finisher', () {
      expect(BudgetLedger(ctx(minutes: 60), 3).secondsLeft(0), closeTo(3000.0, 1e-6));
      expect(BudgetLedger(ctx(minutes: 30), 3).secondsLeft(0), closeTo(1440.0, 1e-6));
      expect(BudgetLedger(ctx(minutes: 90), 3).secondsLeft(2), closeTo(4560.0, 1e-6));
      expect(BudgetLedger(ctx(minutes: 60, finisherSeconds: 120), 3).secondsLeft(0),
          closeTo(2880.0, 1e-6));
    });

    test('add credits every group, this day only, and spends the seconds', () {
      final l = BudgetLedger(ctx(), 3);
      l.add(0, {'Chest', 'Triceps'}, 3, 400);
      expect(l.week('Chest'), 3);
      expect(l.week('Triceps'), 3);
      expect(l.session(0, 'Chest'), 3);
      expect(l.session(1, 'Chest'), 0);
      expect(l.week('Back'), 0);
      expect(l.secondsLeft(0), closeTo(2600.0, 1e-6));
      expect(l.secondsLeft(1), closeTo(3000.0, 1e-6));
    });

    test('fits refuses past the session cap (intermediate: 8)', () {
      final l = BudgetLedger(ctx(), 3);
      l.add(0, {'Chest'}, 6, 0);
      expect(l.fits(0, {'Chest'}, 2, 0), isTrue);
      expect(l.fits(0, {'Chest'}, 3, 0), isFalse);
      // The same group on another day has its own session count.
      expect(l.fits(1, {'Chest'}, 3, 0), isTrue);
    });

    test('fits refuses past the weekly top (intermediate build_muscle: 16)', () {
      final l = BudgetLedger(ctx(), 3);
      l.add(0, {'Chest'}, 8, 0);
      l.add(1, {'Chest'}, 7, 0);
      expect(l.week('Chest'), 15);
      expect(l.fits(2, {'Chest'}, 1, 0), isTrue);
      expect(l.fits(2, {'Chest'}, 2, 0), isFalse);
    });

    test('fits refuses past the day budget; the boundary is inclusive', () {
      final l = BudgetLedger(ctx(), 3);
      expect(l.fits(0, {'Chest'}, 1, 3000.0), isTrue);
      expect(l.fits(0, {'Chest'}, 1, 3000.5), isFalse);
      l.add(0, {'Chest'}, 1, 1000);
      expect(l.fits(0, {'Back'}, 1, 2000.0), isTrue);
      expect(l.fits(0, {'Back'}, 1, 2000.5), isFalse);
    });

    test('a multi-group exercise needs room in EVERY group', () {
      final l = BudgetLedger(ctx(), 3);
      l.add(0, {'Triceps'}, 7, 0);
      expect(l.fits(0, {'Chest'}, 2, 0), isTrue);
      expect(l.fits(0, {'Chest', 'Triceps'}, 2, 0), isFalse);
      expect(l.fits(0, {'Chest', 'Triceps'}, 1, 0), isTrue);
    });

    test('an exercise with no group is checked against time only', () {
      final l = BudgetLedger(ctx(), 3);
      expect(l.fits(0, const {}, 5, 100), isTrue);
      expect(l.fits(0, const {}, 5, 3001), isFalse);
    });

    test('not-budgeted rows (no groups, no sets) spend the day budget', () {
      final l = BudgetLedger(ctx(), 3);
      l.add(0, const {}, 0, 600);
      expect(l.secondsLeft(0), closeTo(2400.0, 1e-6));
      expect(l.fits(0, {'Chest'}, 1, 2400.0), isTrue);
      expect(l.fits(0, {'Chest'}, 1, 2400.5), isFalse);
      expect(l.week('Chest'), 0);
    });

    test('focus groups: weekly top 25 and session cap 12 outside a lighter phase', () {
      final l = BudgetLedger(ctx(focusGroups: {'Chest'}), 3);
      expect(l.weeklyTop('Chest'), 25);
      expect(l.cap('Chest'), 12);
      expect(l.weeklyTop('Back'), 16);
      expect(l.cap('Back'), 8);
      l.add(0, {'Chest'}, 11, 0);
      expect(l.fits(0, {'Chest'}, 1, 0), isTrue);
      expect(l.fits(0, {'Chest'}, 2, 0), isFalse);
    });

    test('lighterPhase: every weekly top is the band BOTTOM, focus included', () {
      final l = BudgetLedger(ctx(lighterPhase: true, focusGroups: {'Chest'}), 3);
      expect(l.weeklyTop('Chest'), 12);
      expect(l.weeklyTop('Back'), 12);
      // And the focus session cap falls back to the ordinary cap.
      expect(l.cap('Chest'), 8);
      l.add(0, {'Chest'}, 8, 0);
      l.add(1, {'Chest'}, 4, 0);
      expect(l.fits(2, {'Chest'}, 1, 0), isFalse);
    });

    test('without lighterPhase the same focus group is NOT held to the bottom', () {
      final l = BudgetLedger(ctx(focusGroups: {'Chest'}), 3);
      l.add(0, {'Chest'}, 8, 0);
      l.add(1, {'Chest'}, 4, 0);
      expect(l.fits(2, {'Chest'}, 1, 0), isTrue);
    });

    test('the band follows the goal and the level', () {
      final l = BudgetLedger(ctx(planGoal: 'general_fitness', level: 'beginner'), 3);
      expect(l.weeklyTop('Chest'), 10);
      expect(l.cap('Chest'), 6);
    });
  });
}
