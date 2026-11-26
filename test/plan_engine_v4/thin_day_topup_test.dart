// OI-401 thin-day top-up: the PURE rules (floor, neighbour table, trigger,
// anchor ordering). The orchestration that queries the library lives in
// ExerciseSelector.topUpDays and is proven in
// test/contracts/thin_day_topup_behavioral_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/thin_day_topup.dart';

MuscleSlot _slot(String muscle, String pattern, int priority) => MuscleSlot(
      targetMuscle: muscle,
      movementPattern: pattern,
      exerciseType: 'compound',
      priority: priority,
    );

void main() {
  test('floor is 3', () {
    expect(ThinDayTopUp.floor, 3);
  });

  group('applies', () {
    test('uninjured never applies, whatever the count', () {
      expect(ThinDayTopUp.applies(injuries: const [], count: 0), isFalse);
    });
    test('injured and under the floor applies', () {
      expect(ThinDayTopUp.applies(injuries: const ['knee'], count: 2), isTrue);
    });
    test('injured and at the floor does not apply', () {
      expect(ThinDayTopUp.applies(injuries: const ['knee'], count: 3), isFalse);
    });
  });

  group('neighbours', () {
    final nonCore = kMovementPatterns.difference({'core'});

    test('every one of the 10 non-core patterns is a key', () {
      expect(ThinDayTopUp.neighbours.keys.toSet(), nonCore);
    });
    test('every neighbour is a real movement pattern, and never core', () {
      for (final e in ThinDayTopUp.neighbours.entries) {
        for (final n in e.value) {
          expect(kMovementPatterns, contains(n), reason: '${e.key} -> $n');
          expect(n, isNot('core'), reason: '${e.key} lists core');
        }
      }
    });
    test('no pattern lists itself, and no list repeats a pattern', () {
      for (final e in ThinDayTopUp.neighbours.entries) {
        expect(e.value, isNot(contains(e.key)), reason: '${e.key} lists itself');
        expect(e.value.toSet().length, e.value.length,
            reason: '${e.key} repeats a neighbour');
      }
    });
  });

  group('anchors', () {
    test('priority order, ties by original index, core dropped, de-duplicated',
        () {
      final slots = [
        _slot('Lats', 'vertical_pull', 2),
        _slot('Mid Chest', 'horizontal_push', 1),
        _slot('Core', 'core', 1),
        _slot('Lats', 'vertical_pull', 3),
      ];
      final out = ThinDayTopUp.anchors(slots);
      expect(out.map((a) => (a.muscle, a.pattern)).toList(), [
        ('Mid Chest', 'horizontal_push'),
        ('Lats', 'vertical_pull'),
      ]);
    });

    test('equal priorities keep the slot order', () {
      final slots = [
        _slot('Biceps', 'elbow_flexion', 2),
        _slot('Triceps', 'elbow_extension', 2),
        _slot('Rear Delts', 'shoulder_isolation', 2),
      ];
      expect(
        ThinDayTopUp.anchors(slots).map((a) => a.muscle).toList(),
        ['Biceps', 'Triceps', 'Rear Delts'],
      );
    });

    test('the same muscle on two patterns gives two anchors', () {
      final slots = [
        _slot('Lats', 'vertical_pull', 1),
        _slot('Lats', 'horizontal_pull', 2),
      ];
      expect(ThinDayTopUp.anchors(slots), hasLength(2));
    });

    test('an all-core or empty slot list gives no anchors', () {
      expect(ThinDayTopUp.anchors(const []), isEmpty);
      expect(ThinDayTopUp.anchors([_slot('Core', 'core', 1)]), isEmpty);
    });
  });
}
