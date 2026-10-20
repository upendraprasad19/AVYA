// Pure decision logic of the one-LOG-per-exercise flow
// (lib/features/train/services/log_exercise_logic.dart). Plan
// docs/plans/active-workout-log-exercise.md §6 tests 1, 15, 16.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/features/train/services/log_exercise_logic.dart';

SetValidation v(String type,
        {String w = '', String r = '', String d = '', String km = ''}) =>
    validateSetInputs(
        loggingType: type,
        weightText: w,
        repsText: r,
        durationText: d,
        distanceText: km);

void main() {
  group('validateSetInputs: field order, kind and messages', () {
    test('weight_reps checks weight first, then reps', () {
      final a = v('weight_reps', w: '', r: '');
      expect(a.field, SetField.weight);
      expect(a.kind, SetFailureKind.empty);
      expect(a.message, kEnterWeightMessage);

      final b = v('weight_reps', w: '60', r: '');
      expect(b.field, SetField.reps);
      expect(b.kind, SetFailureKind.empty);
      expect(b.message, kEnterRepsMessage);

      final c = v('weight_reps', w: '60', r: '61');
      expect(c.field, SetField.reps);
      expect(c.kind, SetFailureKind.outOfRange);
      expect(c.message, kRepsTooHighMessage);

      expect(v('weight_reps', w: '0', r: '8').field, SetField.weight);
      expect(v('weight_reps', w: '60', r: '60').isOk, isTrue);
      expect(v('weight_reps', w: '60', r: '1').isOk, isTrue);
    });

    test('weighted_bodyweight blocks on reps ONLY (weight never blocks)', () {
      expect(v('weighted_bodyweight', w: '', r: '8').isOk, isTrue);
      expect(v('weighted_bodyweight', w: '10', r: '').field, SetField.reps);
      expect(blockedLogLabel(v('weighted_bodyweight', w: '', r: '')),
          WardroomCopy.activeBlockedAddReps);
    });

    test('bodyweight_reps checks reps', () {
      expect(v('bodyweight_reps', r: '').field, SetField.reps);
      expect(v('bodyweight_reps', r: '12').isOk, isTrue);
    });

    test('timed and cardio check duration only; cardio never blocks on km',
        () {
      expect(v('timed', d: '').field, SetField.duration);
      expect(v('timed', d: '0').kind, SetFailureKind.empty);
      expect(v('timed', d: '45').isOk, isTrue);
      expect(v('cardio', d: '20', km: '').isOk, isTrue);
      expect(v('cardio', d: '', km: '5').field, SetField.duration);
      expect(v('cardio', d: '').message, kEnterDurationMessage);
    });

    test('cardio "12.5" is outOfRange -> Fix time (validator int-parses)', () {
      final r = v('cardio', d: '12.5');
      expect(r.field, SetField.duration);
      expect(r.kind, SetFailureKind.outOfRange);
      expect(blockedLogLabel(r), WardroomCopy.activeBlockedFixTime);
    });

    test('distance checks distance', () {
      expect(v('distance', km: '').field, SetField.distance);
      expect(v('distance', km: '2.5').isOk, isTrue);
      expect(v('distance', km: '').message, kEnterDistanceMessage);
    });

    test('unknown logging type never blocks', () {
      expect(v('something_else').isOk, isTrue);
    });
  });

  test('field-to-label table', () {
    expect(blockedLogLabel(v('weight_reps')), WardroomCopy.activeBlockedAddWeight);
    expect(blockedLogLabel(v('bodyweight_reps')), WardroomCopy.activeBlockedAddReps);
    expect(blockedLogLabel(v('bodyweight_reps', r: '99')),
        WardroomCopy.activeBlockedFixReps);
    expect(blockedLogLabel(v('timed')), WardroomCopy.activeBlockedAddTime);
    expect(blockedLogLabel(v('distance')), WardroomCopy.activeBlockedAddDistance);
    expect(blockedLogLabel(const SetValidation.ok()), '');
  });

  test('parity: the messages are the OFF validator\'s literals', () {
    final src = File(
            'lib/features/train/screens/active_workout/exercise_card.dart')
        .readAsStringSync();
    final start = src.indexOf('String? _validateRepsBound(int reps)');
    final end = src.indexOf('String _metaText()');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final off = src.substring(start, end);
    for (final m in [
      kEnterWeightMessage,
      kEnterRepsMessage,
      kEnterDurationMessage,
      kEnterDistanceMessage,
    ]) {
      expect(off.contains("'$m'"), isTrue, reason: 'OFF validator lost "$m"');
    }
    expect(
        off.contains(
            r"'Reps must be ≤ $_repsMax per set. Typo? Cloud rejects values above this.'"),
        isTrue);
    expect(src.contains('static const int _repsMin = $kLogRepsMin;'), isTrue);
    expect(src.contains('static const int _repsMax = $kLogRepsMax;'), isTrue);
  });

  group('sets to log, button label, subline', () {
    test('setsToLog = every unchecked set, warm-ups included', () {
      expect(
          setsToLog(
              exerciseIndex: 1,
              numSets: 4,
              checkedSets: {'1-0': true, '0-2': true}),
          {1, 2, 3});
      expect(setsToLog(exerciseIndex: 0, numSets: 0, checkedSets: {}), isEmpty);
    });

    test('{n} counts unchecked WORKING sets only', () {
      expect(
          workingSetsToLog(
              exerciseIndex: 0,
              numSets: 4,
              checkedSets: {'0-3': true},
              warmUpSets: {'0-0': true}),
          2);
    });

    test('label singular / plural / all-warm-up', () {
      expect(logButtonLabel(4), 'LOG 4 SETS ✓');
      expect(logButtonLabel(1), 'LOG 1 SET ✓');
      expect(logButtonLabel(0), 'LOG ✓');
    });

    test('volume = sum(weight x reps), loaded types only', () {
      expect(
          loggedVolumeKg(
              loggingType: 'weight_reps',
              weightTexts: ['60', '60', ''],
              repsTexts: ['8', '7', '8']),
          900);
      for (final t in ['bodyweight_reps', 'timed', 'cardio', 'distance']) {
        expect(
            loggedVolumeKg(
                loggingType: t, weightTexts: ['60'], repsTexts: ['8']),
            0,
            reason: t);
      }
      expect(liftedSubline(900), '900 KG LIFTED');
      expect(liftedSubline(452.5), '452.5 KG LIFTED');
      expect(liftedSubline(0), isNull);
    });
  });

  group('seedForAddedSet', () {
    test('copies the last NON-warm-up set field for field', () {
      final seed = seedForAddedSet(const [
        SetTexts(weight: '60', reps: '8'),
        SetTexts(weight: '62.5', reps: '6', duration: '', distance: ''),
        SetTexts(weight: '20', reps: '15'),
      ], [
        false,
        false,
        true
      ]);
      expect(seed.weight, '62.5');
      expect(seed.reps, '6');
    });

    test('never copies reps into duration (e8f95e)', () {
      final seed = seedForAddedSet(
          const [SetTexts(reps: '12', duration: '')], [false]);
      expect(seed.duration, '');
      final timed = seedForAddedSet(
          const [SetTexts(reps: '', duration: '45')], [false]);
      expect(timed.duration, '45');
      expect(timed.reps, '');
    });

    test('all warm-up -> last set; none -> blank', () {
      expect(
          seedForAddedSet(const [SetTexts(weight: '20')], [true]).weight, '20');
      expect(seedForAddedSet(const [], const []).weight, '');
    });
  });

  group('input guard', () {
    test('ignores LOG inside the window after an advance only', () {
      const t = Duration(seconds: 10);
      expect(shouldIgnoreLog(now: t, lastAdvanceAt: null), isFalse);
      expect(
          shouldIgnoreLog(
              now: t + const Duration(milliseconds: 399), lastAdvanceAt: t),
          isTrue);
      expect(
          shouldIgnoreLog(
              now: t + const Duration(milliseconds: 400), lastAdvanceAt: t),
          isFalse);
    });
  });
}
