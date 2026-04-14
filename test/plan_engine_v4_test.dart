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
    final allSlots = [
      const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 1),
      const MuscleSlot(targetMuscle: 'Mid Back', movementPattern: 'horizontal_pull', exerciseType: 'compound', priority: 1),
      const MuscleSlot(targetMuscle: 'Lats', movementPattern: 'vertical_pull', exerciseType: 'compound', priority: 2),
      const MuscleSlot(targetMuscle: 'Rear Delts', movementPattern: 'shoulder_isolation', exerciseType: 'isolation', priority: 2),
      const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
      const MuscleSlot(targetMuscle: 'Biceps', movementPattern: 'elbow_flexion', exerciseType: 'isolation', priority: 3),
    ];

    test('60min advanced keeps all priorities', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 60, experience: 'advanced', weekCharacter: 'baseline');
      expect(result.length, 6);
    });

    test('45min intermediate keeps P1+P2 only', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 45, experience: 'intermediate', weekCharacter: 'baseline');
      expect(result.every((s) => s.priority <= 2), isTrue);
      expect(result.length, 4);
    });

    test('30min keeps P1 only', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 30, experience: 'intermediate', weekCharacter: 'baseline');
      expect(result.every((s) => s.priority == 1), isTrue);
      expect(result.length, 2);
    });

    test('beginner gets P1 + max 1 P2', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 60, experience: 'beginner', weekCharacter: 'baseline');
      final p2Count = result.where((s) => s.priority == 2).length;
      expect(p2Count, lessThanOrEqualTo(1));
      expect(result.every((s) => s.priority <= 2), isTrue);
    });

    test('deload week keeps P1 only', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: 60, experience: 'advanced', weekCharacter: 'deload');
      expect(result.every((s) => s.priority == 1), isTrue);
    });

    test('null sessionMinutes defaults to 45', () {
      final result = VolumeFilter.filter(allSlots, sessionMinutes: null, experience: 'intermediate', weekCharacter: 'baseline');
      expect(result.every((s) => s.priority <= 2), isTrue);
    });
  });
}
