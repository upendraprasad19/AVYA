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

    group('targetCount', () {
      test('beginner: 6/5/4/4 for 3/4/5/6 days', () {
        expect(VolumeFilter.targetCount('beginner', 3), 6);
        expect(VolumeFilter.targetCount('beginner', 4), 5);
        expect(VolumeFilter.targetCount('beginner', 5), 4);
        expect(VolumeFilter.targetCount('beginner', 6), 4);
      });

      test('intermediate: 8/7/6/6 for 3/4/5/6 days', () {
        expect(VolumeFilter.targetCount('intermediate', 3), 8);
        expect(VolumeFilter.targetCount('intermediate', 4), 7);
        expect(VolumeFilter.targetCount('intermediate', 5), 6);
        expect(VolumeFilter.targetCount('intermediate', 6), 6);
      });

      test('advanced: 10/9/8/8 for 3/4/5/6 days', () {
        expect(VolumeFilter.targetCount('advanced', 3), 10);
        expect(VolumeFilter.targetCount('advanced', 4), 9);
        expect(VolumeFilter.targetCount('advanced', 5), 8);
        expect(VolumeFilter.targetCount('advanced', 6), 8);
      });
    });

    test('advanced 5-day keeps first 8 slots', () {
      final result = VolumeFilter.filter(allSlots, experience: 'advanced', weekCharacter: 'baseline', daysPerWeek: 5);
      expect(result.length, 8);
      expect(result.last.targetMuscle, 'Triceps'); // P4 slot
    });

    test('intermediate 5-day keeps first 6 slots', () {
      final result = VolumeFilter.filter(allSlots, experience: 'intermediate', weekCharacter: 'baseline', daysPerWeek: 5);
      expect(result.length, 6);
    });

    test('beginner 5-day keeps first 4 slots', () {
      final result = VolumeFilter.filter(allSlots, experience: 'beginner', weekCharacter: 'baseline', daysPerWeek: 5);
      expect(result.length, 4);
    });

    test('advanced 3-day keeps all 10 slots', () {
      final result = VolumeFilter.filter(allSlots, experience: 'advanced', weekCharacter: 'baseline', daysPerWeek: 3);
      expect(result.length, 10);
    });

    test('deload week keeps P1 only regardless of experience', () {
      final result = VolumeFilter.filter(allSlots, experience: 'advanced', weekCharacter: 'deload', daysPerWeek: 5);
      expect(result.every((s) => s.priority == 1), isTrue);
      expect(result.length, 2);
    });

    test('fewer slots than target returns all', () {
      final fewSlots = allSlots.take(3).toList();
      final result = VolumeFilter.filter(fewSlots, experience: 'advanced', weekCharacter: 'baseline', daysPerWeek: 5);
      expect(result.length, 3); // only 3 available, target is 8
    });
  });
}
