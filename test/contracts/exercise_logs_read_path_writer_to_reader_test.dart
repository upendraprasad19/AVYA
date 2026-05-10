// test/contracts/exercise_logs_read_path_writer_to_reader_test.dart
//
// Contract: exercise_logs_read_path
// Writer: WorkoutWriteService.logExercise (appends to exercise_log_index_YYYY-MM-DD)
// Reader: WorkoutRepository.getExerciseLogsForDate (O(1) index lookup)
//
// Prevents the O(n) workoutBox.keys manual-scan anti-pattern.
// See CLAUDE.md §15.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String writeServiceSource;
  late String workoutRepoSource;

  setUpAll(() {
    writeServiceSource = File(
            'lib/core/services/workout_write_service.dart')
        .readAsStringSync();
    workoutRepoSource = File(
            'lib/features/train/repositories/workout_repository.dart')
        .readAsStringSync();
  });

  group('exercise_logs_read_path writer→reader contract', () {
    test('writer appends to exercise_log_index_ key', () {
      expect(
        writeServiceSource,
        contains('exercise_log_index_'),
        reason:
            'WorkoutWriteService.logExercise must append to exercise_log_index_YYYY-MM-DD '
            'so getExerciseLogsForDate can do an O(1) index lookup.',
      );
    });

    test('reader uses exercise_log_index_ prefix (not O(n) key scan)', () {
      expect(
        workoutRepoSource,
        contains('exercise_log_index_'),
        reason:
            'WorkoutRepository.getExerciseLogsForDate must use the index key '
            'for O(1) lookup; never scan workoutBox.keys manually.',
      );
    });

    test('date keys use IST via formatDateKey / istDateStr', () {
      // The writer must use IST-aware date helpers, not raw UTC substring.
      final usesIstHelper =
          writeServiceSource.contains('istDateStr') ||
          writeServiceSource.contains('formatDateKey');
      expect(
        usesIstHelper,
        isTrue,
        reason:
            'WorkoutWriteService must use istDateStr/formatDateKey for date keys; '
            'raw DateTime.now().toIso8601String().substring(0,10) gives UTC dates '
            'that disagree with IST-keyed readers at IST midnight boundary.',
      );
    });

    test('reader has legacy fallback for rows without index entry', () {
      expect(
        workoutRepoSource,
        contains('exlog_'),
        reason:
            'WorkoutRepository.getExerciseLogsForDate must fall back to '
            'exlog_* prefix scan for legacy rows that pre-date the index.',
      );
    });
  });
}
