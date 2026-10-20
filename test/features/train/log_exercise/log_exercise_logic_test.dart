// Pure decision logic of the one-LOG-per-exercise flow
// (lib/features/train/services/log_exercise_logic.dart). Plan
// docs/plans/active-workout-log-exercise.md §6 tests 1, 15, 16; batch 2
// (docs/plans/log-exercise-batch2.md §6) tests 1-8 and 10b.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
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

  // ── batch 2 ───────────────────────────────────────────────────────────
  ExerciseData exd(String name, {String type = 'weight_reps', String sets = '3'}) =>
      ExerciseData(
          name: name,
          sets: sets,
          reps: '8',
          weight: '0kg',
          rest: '90s',
          loggingType: type);

  group('mirror (batch 2 tests 1-3)', () {
    test('mirrorFieldsFor follows what SetInputRow renders, reps excluded', () {
      expect(mirrorFieldsFor('weight_reps'), {SetField.weight});
      expect(mirrorFieldsFor('weighted_bodyweight'), {SetField.weight});
      expect(mirrorFieldsFor('bodyweight_reps'), isEmpty);
      expect(mirrorFieldsFor('timed'), {SetField.duration});
      expect(mirrorFieldsFor('cardio'), {SetField.duration, SetField.distance});
      expect(mirrorFieldsFor('distance'), {SetField.distance, SetField.weight});
      expect(mirrorFieldsFor('something_new'), {SetField.weight});
    });

    test('mirrorSourceIndex is the first non-warm-up set', () {
      expect(mirrorSourceIndex([false, false, false]), 0);
      expect(mirrorSourceIndex([true, false, false]), 1);
      expect(mirrorSourceIndex([true, true]), isNull);
      expect(mirrorSourceIndex([]), isNull);
    });

    test('mirrorTargets: blank and last-mirrored in; edited, logged, warm-up '
        'and earlier sets out', () {
      List<int> t(List<String> texts,
              {Map<int, String> last = const {},
              List<bool>? warm,
              List<bool>? logged,
              int source = 0}) =>
          mirrorTargets(
            source: source,
            texts: texts,
            lastMirrored: last,
            isWarmUp: warm ?? List.filled(texts.length, false),
            isLogged: logged ?? List.filled(texts.length, false),
          );
      expect(t(['60', '', '  ']), [1, 2], reason: 'blank (and whitespace)');
      expect(t(['65', '60', '60'], last: {1: '60', 2: '60'}), [1, 2]);
      expect(t(['65', '60', '70'], last: {1: '60', 2: '60'}), [1],
          reason: 'set 3 was edited by the user');
      expect(t(['60', '', ''], logged: [false, true, false]), [2]);
      expect(t(['60', '', ''], warm: [false, false, true]), [1]);
      expect(t(['', '60', ''], source: 1), [2],
          reason: 'sets before the source never follow');
      expect(t(['60', '50', '50']), isEmpty,
          reason: 'prefilled values are not followers');
    });

    test('seedIndexForAddedSet (10b): last non-warm-up, else null', () {
      expect(seedIndexForAddedSet([false, false, false], 3), 2);
      expect(seedIndexForAddedSet([false, false, true], 3), 1);
      expect(seedIndexForAddedSet([true, true], 2), isNull);
      expect(seedIndexForAddedSet([], 0), isNull);
    });
  });

  group('UNDO toast (batch 2 tests 4-8)', () {
    ActiveWorkoutData data({
      String type = 'weight_reps',
      Map<String, bool> checked = const {},
      Map<String, bool> warm = const {},
      Map<String, SetInputValues> values = const {},
      bool saved = false,
      List<String> names = const ['Bench Press', 'Row'],
    }) =>
        ActiveWorkoutData(
          exercises: [for (final n in names) exd(n, type: type)],
          checkedSets: checked,
          warmUpSets: warm,
          setInputValues: values,
          isSaved: saved,
        );
    const all = {'0-0': true, '0-1': true, '0-2': true};
    LogUndoRecord rec({Set<int> sets = const {0, 1, 2}, int index = 0,
            String name = 'Bench Press',
            Duration at = const Duration(seconds: 10)}) =>
        LogUndoRecord(
            exerciseIndex: index,
            exerciseName: name,
            setIndexes: sets,
            shownAt: at,
            generation: 1);

    test('logToastText: plural, singular, warm-ups only, kg, no-load types', () {
      const v = SetInputValues(weight: 47.5, reps: 1);
      final vals = {for (final k in all.keys) k: v};
      expect(logToastText(rec(), data(checked: all, values: vals)),
          'Bench Press logged · 3 sets · 142.5 KG');
      expect(
          logToastText(rec(sets: {2}),
              data(checked: all, values: {'0-2': const SetInputValues(weight: 100, reps: 12)})),
          'Bench Press logged · 1 set · 1200 KG');
      expect(
          logToastText(rec(sets: {0}),
              data(checked: all, warm: {'0-0': true}, values: vals)),
          'Bench Press logged',
          reason: 'warm-ups only: no sets segment, no volume');
      expect(
          logToastText(rec(),
              data(checked: all, warm: {'0-0': true}, values: vals)),
          'Bench Press logged · 2 sets · 95 KG',
          reason: 'a set flagged warm-up after LOG drops out at render');
      expect(logToastText(rec(), data(type: 'timed', checked: all, values: vals)),
          'Bench Press logged · 3 sets');
      expect(logToastText(rec(), data(checked: all)),
          'Bench Press logged · 3 sets',
          reason: 'no stored values: no kg segment');
      expect(logToastText(rec(index: 5), data(checked: all)), '');
      expect(logToastText(rec(), data(checked: all, values: vals)),
          contains(WardroomCopy.activeLogToastSeparator));
    });

    test('allExercisesLogged: every exercise done and not saved', () {
      const both = {...all, '1-0': true, '1-1': true, '1-2': true};
      expect(allExercisesLogged(data(checked: both)), isTrue);
      expect(allExercisesLogged(data(checked: all)), isFalse);
      expect(allExercisesLogged(data(checked: both, saved: true)), isFalse);
      expect(allExercisesLogged(const ActiveWorkoutData()), isFalse);
    });

    test('undoRecordFor: only the sets this LOG added; null when nothing was '
        'added or a save is running', () {
      final before = data(checked: {'0-0': true});
      final after = data(checked: all);
      final r = undoRecordFor(
          before: before,
          after: after,
          exerciseIndex: 0,
          shownAt: const Duration(seconds: 3),
          generation: 7,
          completing: false)!;
      expect(r.setIndexes, {1, 2});
      expect(r.exerciseName, 'Bench Press');
      expect(r.generation, 7);
      expect(r.shownAt, const Duration(seconds: 3));
      expect(
          undoRecordFor(
              before: after,
              after: after,
              exerciseIndex: 0,
              shownAt: Duration.zero,
              generation: 1,
              completing: false),
          isNull);
      expect(
          undoRecordFor(
              before: before,
              after: after,
              exerciseIndex: 0,
              shownAt: Duration.zero,
              generation: 1,
              completing: true),
          isNull);
      expect(
          undoRecordFor(
              before: before,
              after: after,
              exerciseIndex: 9,
              shownAt: Duration.zero,
              generation: 1,
              completing: false),
          isNull);
    });

    test('visibleUndoRecord: window, removal (no throw), swap, unchecked, '
        'saved', () {
      const at = Duration(seconds: 10);
      final r = rec(at: at);
      final d = data(checked: all);
      expect(visibleUndoRecord(r, at, d), same(r));
      expect(visibleUndoRecord(r, at + const Duration(milliseconds: 4999), d),
          same(r));
      expect(visibleUndoRecord(r, at + kLogUndoWindow, d), isNull);
      expect(visibleUndoRecord(null, at, d), isNull);
      expect(visibleUndoRecord(rec(index: 1, name: 'Row'), at,
          data(checked: all, names: const ['Bench Press'])), isNull,
          reason: 'index out of range after a removal: null, not a RangeError');
      expect(visibleUndoRecord(r, at, data(checked: all, names: const ['Squat', 'Row'])),
          isNull, reason: 'another exercise at that index');
      expect(visibleUndoRecord(r, at, data(checked: {'0-0': true, '0-1': true})),
          isNull, reason: 'a record set is no longer checked');
      expect(visibleUndoRecord(r, at, data(checked: all, saved: true)), isNull);
    });

    test('shouldIgnoreUndo: the 400 ms LOG guard window after the toast', () {
      const at = Duration(seconds: 10);
      expect(
          shouldIgnoreUndo(
              now: at + const Duration(milliseconds: 399), shownAt: at),
          isTrue);
      expect(
          shouldIgnoreUndo(
              now: at + const Duration(milliseconds: 400), shownAt: at),
          isFalse);
    });
  });
}
