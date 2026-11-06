// Superset groups persist by exercise IDENTITY, and an in-workout swap keeps
// the slot's group (docs/plans/active-workout-swap-move.md Task 2).
//
// Writer: `ActiveWorkoutNotifier._persistSupersetGroups` (via the pure
// `applySupersetGroupsByIdentity`) → `schedule_<date>` row `superset_group`.
// Reader: `_parseExerciseMaps` on the next load (`superset_group`).
// Before this batch the write was by INDEX, so after an in-session reorder it
// stamped each group onto whichever stored row sat at that position.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/train/services/exercise_move_logic.dart';
import 'package:icanbefitter/features/train/services/superset_persist_logic.dart';

import '../helpers/hive_test_setup.dart';

class _SeededNotifier extends ActiveWorkoutNotifier {
  _SeededNotifier(this.seed);
  final ActiveWorkoutData seed;
  @override
  ActiveWorkoutData build() => seed;
}

ExerciseData ex(String name,
        {String type = 'weight_reps', int? group, String? id}) =>
    ExerciseData(
      name: name,
      sets: '3',
      reps: '8',
      weight: '0kg',
      rest: '90s',
      loggingType: type,
      supersetGroup: group,
      exerciseId: id,
    );

ProviderContainer containerWith(ActiveWorkoutData seed) {
  final c = ProviderContainer(overrides: [
    authUserIdTokenProvider.overrideWithValue('u'),
    activeWorkoutProvider.overrideWith(() => _SeededNotifier(seed)),
  ]);
  addTearDown(c.dispose);
  return c;
}

Map<String, dynamic> row(String name, {int? group, String? id}) => {
      'exercise_name': name,
      'superset_group': group,
      'exercise_id': ?id,
    };

SessionExerciseIdentity ident(String name, {int? group, String? id}) =>
    (exerciseId: id, name: name, supersetGroup: group);

List<Object?> groupsOf(List<dynamic> rows) =>
    [for (final r in rows) (r as Map)['superset_group']];

void main() {
  group('applySupersetGroupsByIdentity (pure)', () {
    test('unchanged order writes exactly what the index write wrote', () {
      final out = applySupersetGroupsByIdentity(
        stored: [row('a', group: 5), row('b'), row('c', group: 7)],
        session: [
          ident('a', group: 0),
          ident('b'),
          ident('c', group: 0),
        ],
      );
      expect(groupsOf(out), [0, null, 0]);
    });

    test('a reordered session writes each group onto its own row', () {
      final out = applySupersetGroupsByIdentity(
        stored: [row('A'), row('B'), row('C')],
        session: [ident('C', group: 1), ident('A'), ident('B', group: 1)],
      );
      expect(groupsOf(out), [null, 1, 1]);
    });

    test('ids decide when both are present, even over an equal name', () {
      final out = applySupersetGroupsByIdentity(
        stored: [row('Row', id: 'x1'), row('Row', id: 'x2')],
        session: [ident('Row', id: 'x2', group: 3), ident('Row', id: 'x1')],
      );
      expect(groupsOf(out), [null, 3]);
      final none = applySupersetGroupsByIdentity(
        stored: [row('Row', id: 'x1', group: 9)],
        session: [ident('Row', id: 'zz', group: 3)],
      );
      expect(groupsOf(none), [9], reason: 'different ids never match');
    });

    test('duplicate names without ids pair first-to-first', () {
      final out = applySupersetGroupsByIdentity(
        stored: [row('A'), row('A')],
        session: [ident('A', group: 2), ident('A')],
      );
      expect(groupsOf(out), [2, null]);
    });

    test('a swapped-in exercise with no stored row leaves the old row alone',
        () {
      final out = applySupersetGroupsByIdentity(
        stored: [row('Bench'), row('Fly', group: 4)],
        session: [ident('Bench'), ident('Cable Fly', group: 0)],
      );
      expect(groupsOf(out), [null, 4]);
    });

    test('a pair whose partner has no stored row is not half-stored', () {
      // Swap C→E (session-only), then pair E with D: the old index write
      // stamped C+D; an identity write must not leave D a lone member.
      final out = applySupersetGroupsByIdentity(
        stored: [row('C'), row('D')],
        session: [ident('E', group: 1), ident('D', group: 1)],
      );
      expect(groupsOf(out), [null, null]);
      // Mirror: both partners stored ⇒ the pair is written.
      final both = applySupersetGroupsByIdentity(
        stored: [row('C'), row('D')],
        session: [ident('C', group: 1), ident('D', group: 1)],
      );
      expect(groupsOf(both), [1, 1]);
      // Mirror: a partner that is an UNTOUCHED stored row still counts.
      final kept = applySupersetGroupsByIdentity(
        stored: [row('C', group: 1), row('D')],
        session: [ident('E', group: 1), ident('D', group: 1)],
      );
      expect(groupsOf(kept), [1, 1]);
    });

    test('an id match is never taken by an earlier name-only entry', () {
      final out = applySupersetGroupsByIdentity(
        stored: [row('Row', id: 'x2'), row('Row', id: 'x1')],
        session: [ident('Row', group: 5), ident('Row', id: 'x2', group: 3)],
      );
      // x2 is claimed by id first (3); the id-less entry falls back to the
      // remaining same-name row.
      expect(groupsOf(out), [3, 5]);
    });

    test('non-Map entries pass through, and the input is not mutated', () {
      final stored = <dynamic>['junk', row('A')];
      final out = applySupersetGroupsByIdentity(
          stored: stored, session: [ident('A', group: 1)]);
      expect(out.first, 'junk');
      expect((out[1] as Map)['superset_group'], 1);
      expect((stored[1] as Map)['superset_group'], isNull);
    });

    test('a stored row named by the legacy `name` key still matches', () {
      final out = applySupersetGroupsByIdentity(
        stored: [
          {'name': 'Dip', 'superset_group': null},
        ],
        session: [ident('Dip', group: 2)],
      );
      expect(groupsOf(out), [2]);
    });
  });

  group('notifier: move, then pair, persists to the right stored rows', () {
    late Directory dir;
    setUp(() async => dir = await setUpHiveForTests());
    tearDown(() => tearDownHiveForTests(dir));

    test('Row 3→1, pair Incline+Row: only Row and Incline carry the group',
        () async {
      final date = DateTime(2026, 10, 21);
      final key = 'schedule_${istDateStr(date)}';
      await HiveService.instance.workoutBox.put(key, <String, dynamic>{
        'exercises': [row('Bench'), row('Incline'), row('OHP'), row('Row')],
      });
      final day = [ex('Bench'), ex('Incline'), ex('OHP'), ex('Row')];
      final c = containerWith(ActiveWorkoutData(
        workoutDay:
            WorkoutDayData(dayNumber: 1, name: 'Upper', date: date, exercises: day),
        exercises: day,
      ));
      final n = c.read(activeWorkoutProvider.notifier);
      expect(
          n.applyExerciseMove(moveExerciseInSession(
              c.read(activeWorkoutProvider),
              from: 3,
              to: 1)!),
          isTrue);
      // Session order is now Bench, Row, Incline, OHP.
      n.startSupersetGrouping(2); // Incline
      n.pairSuperset(1); // Row

      Map<String, Object?> byName() {
        final stored = (HiveService.instance.workoutBox.get(key) as Map)['exercises']
            as List;
        return {
          for (final r in stored)
            (r as Map)['exercise_name'] as String: r['superset_group'],
        };
      }

      for (var i = 0; i < 50 && byName()['Row'] == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final groups = byName();
      expect(groups['Row'], isNotNull);
      expect(groups['Incline'], groups['Row']);
      expect(groups['OHP'], isNull);
      expect(groups['Bench'], isNull);
    });
  });

  group('swapExercise keeps the slot\'s superset group', () {
    late Directory dir;
    setUp(() async => dir = await setUpHiveForTests());
    tearDown(() => tearDownHiveForTests(dir));

    ActiveWorkoutData seed() => ActiveWorkoutData(exercises: [
          ex('Incline', group: 0),
          ex('Row', group: 0),
        ]);

    test('same logging type (the replacement is used as-is)', () {
      final c = containerWith(seed());
      c.read(activeWorkoutProvider.notifier).swapExercise(1, ex('Cable Row'));
      final s = c.read(activeWorkoutProvider).exercises[1];
      expect(s.name, 'Cable Row');
      expect(s.supersetGroup, 0);
    });

    test('different logging type (the resolved copy is built)', () {
      final c = containerWith(seed());
      c
          .read(activeWorkoutProvider.notifier)
          .swapExercise(1, ex('Inverted Row', type: ''));
      final s = c.read(activeWorkoutProvider).exercises[1];
      expect(s.loggingType, 'weight_reps', reason: 'resolver fallback');
      expect(s.supersetGroup, 0);
    });

    test('a replacement with its own group keeps it; UNDO restores', () {
      final c = containerWith(seed());
      final n = c.read(activeWorkoutProvider.notifier);
      final original = c.read(activeWorkoutProvider).exercises[1];
      n.swapExercise(1, ex('Cable Row', group: 3));
      expect(c.read(activeWorkoutProvider).exercises[1].supersetGroup, 3);
      n.swapExercise(1, original); // the swap UNDO path
      final s = c.read(activeWorkoutProvider).exercises[1];
      expect(s.name, 'Row');
      expect(s.supersetGroup, 0);
    });

    test('an ungrouped slot stays ungrouped', () {
      final c = containerWith(
          ActiveWorkoutData(exercises: [ex('Bench'), ex('Row')]));
      c.read(activeWorkoutProvider.notifier).swapExercise(1, ex('Cable Row'));
      expect(c.read(activeWorkoutProvider).exercises[1].supersetGroup, isNull);
    });
  });

  test('presence: swapExercise carries the slot group (comments stripped)',
      () {
    final src = File('lib/features/train/providers/train_provider.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final body = RegExp(
      r'void swapExercise\(int exerciseIndex, ExerciseData newExercise\)\s*\{(.*?)\n  \}',
      dotAll: true,
    ).firstMatch(src);
    expect(body, isNotNull);
    expect(body!.group(1)!.contains('supersetGroup'), isTrue);
  });
}
