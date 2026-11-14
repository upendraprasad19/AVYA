// Library Batch S1b-2: the pure SameMovement helper (lib/shared/repositories/plan_engine/same_movement.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/same_movement.dart';

void main() {
  final rows = <Map<String, dynamic>>[
    {'id': 'E147', 'name': 'Sumo Squat'},
    {'id': 'N14', 'name': 'Dumbbell Sumo Squat', 'same_movement_as': 'E147'},
    {'id': 'E048', 'name': 'Glute Bridge'},
    {'id': 'N19', 'name': 'Dumbbell Glute Bridge', 'same_movement_as': 'E048'},
    {'id': 'E001', 'name': 'Push Up'},
    {'id': 'N99', 'name': 'Orphan Version', 'same_movement_as': 'E999'},
  ];
  final sm = SameMovement.fromRows(rows);

  test('symmetric: the original expands to its version and the version to its original', () {
    expect(sm.expand({'Sumo Squat'}), {'Sumo Squat', 'Dumbbell Sumo Squat'});
    expect(sm.expand({'Dumbbell Sumo Squat'}), {'Dumbbell Sumo Squat', 'Sumo Squat'});
    expect(sm.partnersOf('Glute Bridge'), {'Dumbbell Glute Bridge'});
    expect(sm.partnersOf('Dumbbell Glute Bridge'), {'Glute Bridge'});
  });

  test('a name with no partner, an unknown name and a link to a missing id pass through unchanged', () {
    final names = {'Push Up', 'Not In Library', 'Orphan Version'};
    expect(identical(sm.expand(names), names), isTrue, reason: 'nothing added: the same set is returned');
    expect(sm.partnersOf('Push Up'), isEmpty);
  });

  test('the input set is never mutated', () {
    final names = {'Sumo Squat'};
    sm.expand(names);
    expect(names, {'Sumo Squat'});
  });

  test('expandLower serves the lowercase avoid sets and ignores exact-case names', () {
    expect(sm.expandLower({'glute bridge'}), {'glute bridge', 'dumbbell glute bridge'});
    expect(sm.expandLower({'Glute Bridge'}), {'Glute Bridge'});
  });

  test('a library with no link builds the empty helper', () {
    final none = SameMovement.fromRows([{'id': 'E001', 'name': 'Push Up'}]);
    expect(none.isEmpty, isTrue);
    expect(none.expand({'Push Up'}), {'Push Up'});
  });
}
