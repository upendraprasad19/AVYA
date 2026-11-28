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

    // OI-389 D2 (founder, 2026-10-22): cardio minutes take decimals.
    test('cardio "12.5" is ok, and LOG stores 750 s', () {
      expect(v('cardio', d: '12.5').isOk, isTrue);
      expect(cardioMinutesToSeconds('12.5'), 750);
    });

    test('cardio minutes that do not parse are outOfRange -> Fix time', () {
      final r = v('cardio', d: '12..5');
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

  // ── flip batch (docs/plans/log-exercise-flip.md §6 "Pure") ─────────────
  const sv = SetInputValues(weight: 60, reps: 8);
  Map<String, bool> on(int ex, Iterable<int> sets) =>
      {for (final s in sets) '$ex-$s': true};
  Map<String, SetInputValues> vals(int ex, Iterable<int> sets,
          [SetInputValues v = sv]) =>
      {for (final s in sets) '$ex-$s': v};

  group('isFaded (flip §2)', () {
    final marked = ActiveWorkoutData(
        exercises: [exd('A')], suggestedInputs: const {'0-1-weight'});
    bool f(ActiveWorkoutData d, {bool logMode = true, int set = 1}) => isFaded(
        logMode: logMode,
        data: d,
        exerciseIndex: 0,
        setIndex: set,
        field: SetField.weight);

    test('faded only in LOG mode, on a marked, unchecked, unsaved field', () {
      expect(f(marked), isTrue);
      expect(f(marked, logMode: false), isFalse);
      expect(f(marked, set: 0), isFalse, reason: 'no key');
      expect(f(marked.copyWith(isSaved: true)), isFalse);
      expect(f(marked.copyWith(checkedSets: on(0, [1]))), isFalse,
          reason: 'a logged set is never faded');
      expect(
          isFaded(
              logMode: true,
              data: marked,
              exerciseIndex: 0,
              setIndex: 1,
              field: SetField.duration),
          isFalse,
          reason: 'the key is per field');
    });
  });

  group('sublines (flip §2)', () {
    test('PREFILLED and LIFTED share the kg format; null without volume', () {
      expect(prefilledSubline(1440), '1440 KG · PREFILLED');
      expect(prefilledSubline(142.5), '142.5 KG · PREFILLED');
      expect(prefilledSubline(0), isNull);
      expect(liftedSubline(1440), '1440 KG LIFTED');
      expect(liftedSubline(0), isNull);
    });
  });

  group('capNames (flip §3)', () {
    test('0, 1, 5 and 7 names', () {
      expect(capNames(const []), '');
      expect(capNames(const ['A']), 'A');
      expect(capNames(const ['A', 'B', 'C', 'D', 'E']), 'A, B, C, D, E');
      expect(capNames(const ['A', 'B', 'C', 'D', 'E', 'F', 'G']),
          'A, B, C, D, E +2 more');
    });
  });

  group('workingProgress (flip §3, R4B-06)', () {
    test('0 with no working sets (all warm-up), clamped to 1', () {
      expect(workingProgress((saved: 0, total: 0)), 0.0);
      expect(workingProgress((saved: 3, total: 6)), 0.5);
      expect(workingProgress((saved: 4, total: 3)), 1.0);
    });
  });

  group('finishGuard (flip §3)', () {
    test('reopened, typed, skipped and partial each land in their own list',
        () {
      final d = ActiveWorkoutData(
        exercises: [
          exd('Logged'),
          exd('Reopened'),
          exd('Typed'),
          exd('Untouched new'),
          exd('Untouched returning'),
          exd('Plus after log', sets: '4'),
          exd('Bodyweight typed', type: 'bodyweight_reps'),
        ],
        checkedSets: {...on(0, [0, 1, 2]), ...on(5, [0, 1, 2])},
        setInputValues: {
          ...vals(0, [0, 1, 2]),
          ...vals(1, [0, 1, 2]),
          ...vals(2, [0]), // typed on an unchecked set, no suggested key
          // a returning user's prefill: captured, every weight suggested
          ...vals(4, [0, 1, 2]),
          ...vals(5, [0, 1, 2]),
          ...vals(6, [0, 1, 2], const SetInputValues(reps: 12)),
        },
        suggestedInputs: const {
          '1-0-weight', '1-1-weight', '1-2-weight',
          '4-0-weight', '4-1-weight', '4-2-weight',
        },
        reopenedExercises: const {'Reopened'},
      );
      final g = finishGuard(d);
      expect(g.reopenedUnsaved, ['Reopened']);
      expect(g.typedUnsaved, ['Typed'],
          reason: 'the returning prefill (suggested) and bodyweight reps are '
              'not typed');
      expect(g.skipped,
          ['Untouched new', 'Untouched returning', 'Bodyweight typed']);
      expect([for (final p in g.partial) '${p.name} ${p.saved}/${p.working}'],
          ['Plus after log 3/4']);
    });

    test('timed and cardio: a typed duration / distance is typed; a '
        'suggested one is skipped (B-pass 5)', () {
      final d = ActiveWorkoutData(
        exercises: [
          exd('Plank', type: 'timed'),
          exd('Run', type: 'cardio'),
          exd('Hold', type: 'timed'),
        ],
        setInputValues: {
          '0-0': const SetInputValues(durationSeconds: 45),
          '1-0': const SetInputValues(distanceKm: 5),
          '2-0': const SetInputValues(durationSeconds: 30),
        },
        suggestedInputs: const {'2-0-duration'},
      );
      final g = finishGuard(d);
      expect(g.typedUnsaved, ['Plank', 'Run']);
      expect(g.skipped, ['Hold']);
    });

    test('a LOGGED all-warm-up exercise is skipped, not typed (R6-03)', () {
      final d = ActiveWorkoutData(
        exercises: [exd('Warm')],
        checkedSets: on(0, [0, 1, 2]),
        warmUpSets: on(0, [0, 1, 2]),
        setInputValues: vals(0, [0, 1, 2]),
      );
      final g = finishGuard(d);
      expect(g.typedUnsaved, isEmpty);
      expect(g.skipped, ['Warm']);
    });

    test('nothing saved: everything named, no partial', () {
      final d = ActiveWorkoutData(exercises: [exd('A'), exd('B')]);
      final g = finishGuard(d);
      expect(g.skipped, ['A', 'B']);
      expect(g.partial, isEmpty);
      expect(workingSetCounts(d), (saved: 0, total: 6));
    });

    test('a warm-up-flagged set is out of the total and the working count',
        () {
      final d = ActiveWorkoutData(
        exercises: [exd('A')],
        checkedSets: on(0, [1, 2]),
        warmUpSets: on(0, [0]),
        setInputValues: vals(0, [0, 1, 2]),
      );
      expect(workingSetCounts(d), (saved: 2, total: 2));
      expect(finishGuard(d).partial, isEmpty);
    });
  });

  group('U-E3: hasSaveableSet truth table (OI-361, R7-06)', () {
    test('none, warm-up only, no captured values: false', () {
      expect(ActiveWorkoutData(exercises: [exd('A')]).hasSaveableSet, isFalse);
      expect(
          ActiveWorkoutData(
                  exercises: [exd('A')],
                  checkedSets: on(0, [0, 1]),
                  warmUpSets: on(0, [0, 1]),
                  setInputValues: vals(0, [0, 1]))
              .hasSaveableSet,
          isFalse);
      expect(
          ActiveWorkoutData(exercises: [exd('A')], checkedSets: on(0, [0]))
              .hasSaveableSet,
          isFalse);
    });

    test('one saveable set: true', () {
      expect(
          ActiveWorkoutData(
                  exercises: [exd('A')],
                  checkedSets: on(0, [2]),
                  setInputValues: vals(0, [2]))
              .hasSaveableSet,
          isTrue);
    });

    test('only the SECOND exercise saveable: true', () {
      expect(
          ActiveWorkoutData(
                  exercises: [exd('A'), exd('B')],
                  checkedSets: on(1, [0]),
                  setInputValues: vals(1, [0]))
              .hasSaveableSet,
          isTrue);
    });

    test('only a checked key beyond the template count: true', () {
      expect(
          ActiveWorkoutData(
                  exercises: [exd('A')],
                  checkedSets: on(0, [3]),
                  setInputValues: vals(0, [3]))
              .hasSaveableSet,
          isTrue);
    });
  });
}
