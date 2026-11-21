import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';

void main() {
  group('MuscleSlot', () {
    test('toString includes all fields', () {
      const slot = MuscleSlot(
        targetMuscle: 'Lats',
        subFocus: 'width',
        movementPattern: 'vertical_pull',
        exerciseType: 'compound',
        priority: 1,
      );
      expect(slot.toString(), contains('Lats/width'));
      expect(slot.toString(), contains('vertical_pull'));
      expect(slot.toString(), contains('P1'));
    });

    test('count defaults to 1', () {
      const slot = MuscleSlot(
        targetMuscle: 'Biceps',
        movementPattern: 'elbow_flexion',
        exerciseType: 'isolation',
        priority: 3,
      );
      expect(slot.count, 1);
    });
  });

  group('kMovementPatterns', () {
    test('has exactly 11 patterns', () {
      expect(kMovementPatterns.length, 11);
    });

    test('contains all required patterns', () {
      expect(kMovementPatterns, contains('horizontal_push'));
      expect(kMovementPatterns, contains('vertical_pull'));
      expect(kMovementPatterns, contains('elbow_flexion'));
      expect(kMovementPatterns, contains('shoulder_isolation'));
      expect(kMovementPatterns, contains('hip_isolation'));
    });
  });

  group('VolumeFilter', () {
    // 10 slots to test various slice points
    final allSlots = [
      const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
      const MuscleSlot(targetMuscle: 'Upper Chest', movementPattern: 'horizontal_push', exerciseType: 'compound', priority: 1),
      const MuscleSlot(targetMuscle: 'Lower Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 2),
      const MuscleSlot(targetMuscle: 'Lateral Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
      const MuscleSlot(targetMuscle: 'Triceps', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 3),
      const MuscleSlot(targetMuscle: 'Mid Chest', movementPattern: 'horizontal_push', exerciseType: 'isolation', priority: 3),
      const MuscleSlot(targetMuscle: 'Front Delts', movementPattern: 'vertical_push', exerciseType: 'compound', priority: 4),
      const MuscleSlot(targetMuscle: 'Triceps', subFocus: 'long_head', movementPattern: 'elbow_extension', exerciseType: 'isolation', priority: 4),
      const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 5),
      const MuscleSlot(targetMuscle: 'Core', movementPattern: 'core', exerciseType: 'isolation', priority: 5),
    ];

    // The flip (2026-11-02) deleted `VolumeFilter.targetCount` and the first-N trim:
    // the session set budget sizes the day by time, so every split slot is kept.
    test('every slot is kept for any week that is not a deload', () {
      final result = VolumeFilter.filter(allSlots, weekCharacter: 'baseline');
      expect(result.length, allSlots.length);
      expect(result.last.targetMuscle, 'Core');
    });

    test('the slot ORDER (priority order from the split) is preserved', () {
      final result = VolumeFilter.filter(allSlots, weekCharacter: 'overreach');
      expect([for (final s in result) s.targetMuscle],
          [for (final s in allSlots) s.targetMuscle]);
    });

    test('deload week keeps P1 only regardless of experience', () {
      final result = VolumeFilter.filter(allSlots, weekCharacter: 'deload');
      expect(result.every((s) => s.priority == 1), isTrue);
      expect(result.length, 2);
    });

    test('a list shorter than any old target is returned whole', () {
      final fewSlots = allSlots.take(3).toList();
      final result = VolumeFilter.filter(fewSlots, weekCharacter: 'baseline');
      expect(result.length, 3);
    });
  });
}
