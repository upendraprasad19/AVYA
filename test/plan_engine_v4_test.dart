import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

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
}
