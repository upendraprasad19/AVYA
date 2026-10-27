import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

void main() {
  group('LoggingTypeResolver.resolve', () {
    test('uses explicit logging_type from exercise payload', () {
      final result = LoggingTypeResolver.resolve(
        exercise: {'name': 'Push Up', 'logging_type': 'bodyweight_reps'},
        exerciseLibrary: const {},
        customLibrary: const {},
      );
      expect(result, 'bodyweight_reps');
    });

    test('looks up in custom library when payload omits logging_type', () {
      final result = LoggingTypeResolver.resolve(
        exercise: {'name': 'Handstand Hold'},
        exerciseLibrary: const {},
        customLibrary: {
          'cust_1': {'name': 'Handstand Hold', 'logging_type': 'timed'},
        },
      );
      expect(result, 'timed');
    });

    test('looks up in exercise library when payload + custom omit', () {
      final result = LoggingTypeResolver.resolve(
        exercise: {'name': 'Plank'},
        exerciseLibrary: {
          'exer_1': {'name': 'Plank', 'logging_type': 'timed'},
        },
        customLibrary: const {},
      );
      expect(result, 'timed');
    });

    test('returns null when no source found', () {
      final result = LoggingTypeResolver.resolve(
        exercise: {'name': 'Unknown Move'},
        exerciseLibrary: const {},
        customLibrary: const {},
      );
      expect(result, null);
    });

    test('case-sensitive name match', () {
      final result = LoggingTypeResolver.resolve(
        exercise: {'name': 'Push Up'},
        exerciseLibrary: {
          'exer_1': {'name': 'push up', 'logging_type': 'bodyweight_reps'},
        },
        customLibrary: const {},
      );
      expect(result, null,
          reason: 'Lookup is case-sensitive; matches the rest of the codebase.');
    });

    test('returns null for missing name', () {
      final result = LoggingTypeResolver.resolve(
        exercise: {'logging_type': null},
        exerciseLibrary: const {},
        customLibrary: const {},
      );
      expect(result, null);
    });

    test('custom library takes precedence over exercise library', () {
      final result = LoggingTypeResolver.resolve(
        exercise: {'name': 'Plank'},
        exerciseLibrary: {
          'exer_1': {'name': 'Plank', 'logging_type': 'weight_reps'},
        },
        customLibrary: {
          'cust_1': {'name': 'Plank', 'logging_type': 'timed'},
        },
      );
      expect(result, 'timed',
          reason: 'Custom library is checked first per the resolve order.');
    });
  });
}
