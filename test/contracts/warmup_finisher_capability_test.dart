// ⑦ OI-89 seams 10 + 11 — warm-up, cool-down and the cardio finisher.
//
// These two stages prescribe into EVERY generated day (via plan_generator and
// template_service) and neither was equipment-aware:
//
//   warmup_cooldown  'Dead Hang' (pull-up bar), 'Band Pull Apart' (resistance
//                    band) and 'Chest Doorway Stretch' (doorway) go to bodyweight
//                    users. Only `_gymCardio` was ever gated.
//   cardio_finisher  the `jump_rope` case is the ONLY one of five that ignores
//                    hasGymEquipment; every sibling degrades to a bodyweight
//                    move. `recompose` maps to it by GOAL, and the goal-default
//                    flag is ON, so a bodyweight recompose user gets a jump rope
//                    twice a week in the shipped APK.
//
// AND THE DEEPER PROBLEM: `equipmentNeeded` was set ZERO times in either file, so
// every PlannedExercise they build left it null. A capability oracle reading that
// field is therefore BLIND to them, and a fail-closed predicate applied naively
// would delete every warm-up on every tier. The field must be POPULATED before
// any filter can be trusted — which is what these tests pin.
import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/cardio_finisher.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/warmup_cooldown.dart';

WeekPlan _oneDayWeek() => WeekPlan(
      weekNumber: 1,
      weekInPhase: 1,
      overloadNotes: '',
      workoutDays: [
        WorkoutDay(
          dayNumber: 1,
          name: 'Push',
          focus: 'Chest',
          exercises: const [],
        ),
      ],
    );

void main() {
  final bodyweight = EquipmentVocab.effectiveItems('bodyweight', null, null);

  group('every warm-up / cool-down move declares its equipment', () {
    test('no move resolves to an empty requirement', () {
      // [] would make canPerform fail CLOSED and delete the move for everyone.
      for (final name in WarmupCooldownSelector.allMoveNames) {
        final needed = WarmupCooldownSelector.equipmentForMove(name);
        expect(needed, isNotEmpty,
            reason: '"$name" has no declared equipment — canPerform fails '
                'closed on [] and would drop it at every tier');
      }
    });

    test('the three known off-baseline moves are declared honestly', () {
      expect(WarmupCooldownSelector.equipmentForMove('Dead Hang'),
          contains('pull-up bar'));
      expect(WarmupCooldownSelector.equipmentForMove('Band Pull Apart'),
          contains('resistance band'));
      expect(WarmupCooldownSelector.equipmentForMove('Chest Doorway Stretch'),
          contains('doorway'));
    });

    test('a bodyweight user cannot perform those three', () {
      for (final n in const ['Dead Hang', 'Band Pull Apart']) {
        expect(
            EquipmentCapability.canPerform(
                WarmupCooldownSelector.equipmentForMove(n), bodyweight),
            isFalse,
            reason: '$n is outside the "nothing you have to buy" baseline');
      }
    });

    test('a doorway IS in the bodyweight baseline — but is excludable', () {
      expect(
          EquipmentCapability.canPerform(
              WarmupCooldownSelector.equipmentForMove('Chest Doorway Stretch'),
              bodyweight),
          isTrue);
      final noDoor =
          EquipmentVocab.effectiveItems('bodyweight', null, ['doorway']);
      expect(
          EquipmentCapability.canPerform(
              WarmupCooldownSelector.equipmentForMove('Chest Doorway Stretch'),
              noDoor),
          isFalse,
          reason: 'a user who ticked "no doorway" must not be given it');
    });

    test('the ordinary moves are plain bodyweight', () {
      for (final n in const [
        'Arm Circles', 'Torso Twists', 'High Knees', 'Hip Circles',
        'Jumping Jacks', 'Standing Toe Touch', 'Deep Breathing',
      ]) {
        expect(EquipmentCapability.canPerform(
            WarmupCooldownSelector.equipmentForMove(n), bodyweight), isTrue,
            reason: '$n needs nothing and must survive at the baseline');
      }
    });
  });

  group('the cardio finisher declares its equipment', () {
    test('jump rope is declared, so a bodyweight user cannot be given it', () {
      expect(CardioFinisher.equipmentForFinisher('jump_rope'),
          contains('jump rope'));
      expect(
          EquipmentCapability.canPerform(
              CardioFinisher.equipmentForFinisher('jump_rope'), bodyweight),
          isFalse,
          reason: 'recompose maps to jump_rope by GOAL and the goal-default '
              'flag is ON — this is the shipped bug');
    });

    test('the bodyweight finishers survive at the baseline', () {
      for (final t in const ['hiit', 'hate_cardio', 'running', 'cycling']) {
        expect(
            EquipmentCapability.canPerform(
                CardioFinisher.equipmentForFinisher(t), bodyweight),
            isTrue);
      }
    });

    test('no finisher resolves to an empty requirement', () {
      for (final t in CardioFinisher.allFinisherTokens) {
        expect(CardioFinisher.equipmentForFinisher(t), isNotEmpty,
            reason: '$t would fail closed and vanish at every tier');
      }
    });
  });
  group('the filter never empties a warm-up or cool-down', () {
    // A capability filter that strips a day bare has traded one bug for another.
    // Every pool keeps the same FLOOR the injury filter already established.
    test('a bodyweight user still gets cardio, mobility and stretches', () {
      final weeks = WarmupCooldownSelector.attach(
        [_oneDayWeek()],
        'advanced', // the tier whose lists hold Dead Hang + Band Pull Apart
        const ['bodyweight'],
        capability: EquipmentVocab.effectiveItems('bodyweight', null, null),
      );
      final day = weeks.single.workoutDays.single;
      expect(day.warmup, isNotEmpty);
      expect(day.cooldown, isNotEmpty);
      for (final e in [...day.warmup, ...day.cooldown]) {
        expect(
            EquipmentCapability.canPerform(e.equipmentNeeded, bodyweight), isTrue,
            reason: '${e.exerciseName} needs ${e.equipmentNeeded}');
      }
    });

    test('a user who excluded the doorway still gets a cool-down', () {
      final noDoor =
          EquipmentVocab.effectiveItems('bodyweight', null, ['doorway']);
      final weeks = WarmupCooldownSelector.attach(
        [_oneDayWeek()],
        'advanced',
        const ['bodyweight'],
        capability: noDoor,
      );
      final day = weeks.single.workoutDays.single;
      expect(day.cooldown, isNotEmpty);
      for (final e in day.cooldown) {
        expect(EquipmentCapability.canPerform(e.equipmentNeeded, noDoor), isTrue,
            reason: '${e.exerciseName} survived a doorway exclusion');
      }
    });

    test('null capability is inert — the advanced list comes through', () {
      final weeks = WarmupCooldownSelector.attach(
        [_oneDayWeek()],
        'advanced',
        const ['bodyweight'],
        capability: null,
      );
      final names = weeks.single.workoutDays.single.warmup
          .map((e) => e.exerciseName)
          .toList();
      expect(names, isNotEmpty);
    });
  });

}
